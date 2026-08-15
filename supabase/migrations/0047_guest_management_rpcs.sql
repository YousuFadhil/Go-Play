-- Managing Professional Guests: the three operations, and nothing else.
--
-- Adding a guest, removing one, and correcting the name. Each is one
-- transaction, each takes the match row `for update` before it touches anything
-- that depends on capacity or ordering, and each authorizes the **caller**
-- against the match's community rather than trusting anything the client sent.
--
-- ## Authorization, and the lock these functions deliberately do not ask about
--
-- `has_community_role(community_id, auth.uid(), 'admin')` is the existing gate,
-- used exactly as `remove_player`, `update_match` and `admin_add_player_to_match`
-- use it, and it already admits owner (rank 3) as well as admin (rank 2).
-- `matches.created_by` is not consulted for permission anywhere in this schema
-- and is not consulted here.
--
-- None of these functions asks whether the match has started or finished. That
-- is the approved decision, not an oversight: an owner or admin manages guests
-- in **every** state -- open, full, during the scheduled time, after it, and
-- completed. The time-derived lock exists to freeze *self-service*, and
-- migration `0045` left `register_for_match` and `withdraw_from_match` holding
-- every gate they had.
--
-- ## Capacity
--
-- A guest occupies a place in the same `max_registration` everyone else does.
-- The count is over every row of `match_registrations`, community and guest
-- alike, and it is taken under the match row lock -- which is what makes two
-- administrators adding a guest at the same moment serialize into one success
-- and one `REGISTRATION_CLOSED` rather than two rows past the cap.
--
-- ## Placement
--
-- Not one of these functions decides whether a guest starts. They write the row
-- and call `rebalance_roster`, which holds the single approved ordering
-- (migration `0045`) and is the only thing in the schema that decides who is
-- confirmed. A guest is inserted as `reserve` because that is a statement about
-- nothing -- `rebalance_roster` immediately re-cuts the roster, and a guest is
-- never notified of the move.
--
-- Idempotent: `create or replace` and the usual revoke/grant pairs.

-- 1) Add ---------------------------------------------------------------------------
-- Returns the new guest's id, which is what the caller needs to name them in any
-- later operation.
--
-- The order of the steps is the order of the guarantees: the lock comes before
-- the capacity read, the capacity read before the insert, and the rebalance
-- after both. Validation of the name happens before either row is written, so a
-- rejected name leaves no orphan.
--
-- `created_by` records who added them and confers nothing. It is nullable and
-- clears itself when the account goes (migration `0044`), so adding a guest can
-- never be the reason a user cannot be deleted.
create or replace function public.add_professional_guest(
  p_match_id uuid,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_order int;
  v_guest_id uuid;
  v_played boolean;
  v_seat text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- Serializes every capacity and ordering decision for this match, exactly as
  -- registration and withdrawal already do.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- The same bounds the table's own check states. Asked here as well so the
  -- caller gets a named refusal instead of a constraint violation.
  if p_name is null or char_length(trim(p_name)) < 2
     or char_length(trim(p_name)) > 60 then
    raise exception 'INVALID_GUEST_NAME';
  end if;

  -- Guests do not create capacity, they consume it: community registrations and
  -- guests share one maximum.
  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  insert into match_professional_guests (match_id, display_name, created_by)
  values (p_match_id, trim(p_name), auth.uid())
  returning id into v_guest_id;

  -- One sequence per match, shared with community registrations, so
  -- `(user_id is null), registration_order` orders every participant of the
  -- match against every other.
  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  -- **A played match has no reserve: everyone in the record played.** Migration
  -- `0029` states that where it first mattered, and it decides the seat here.
  --
  -- Re-cutting the roster of a finished match would be actively wrong, not
  -- merely pointless. `set_completed_match_player` confirms a corrected player
  -- without regard to `starting_players`, so a completed match can legitimately
  -- hold more confirmed players than it has starting slots -- and
  -- `rebalance_roster` would demote the excess and send them a "you have been
  -- moved to the reserve" notification about a match that has already been
  -- played. So a guest added to a played match simply joins it, and the roster
  -- is left as the record it is.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  v_seat := case when v_played then 'confirmed' else 'reserve' end;

  insert into match_registrations
    (match_id, professional_guest_id, status, registration_order)
  values (p_match_id, v_guest_id, v_seat, v_order);

  -- Placement belongs to the one function that knows the ordering. A guest that
  -- lands in a starting slot is promoted here, silently.
  if not v_played then
    perform rebalance_roster(p_match_id);
  end if;
  perform recompute_match_status(p_match_id);

  return v_guest_id;
end;
$$;

-- 2) Remove ------------------------------------------------------------------------
-- **This removes a guest from the current roster. It does not erase that they
-- played.**
--
-- The distinction is the whole of this function. `match_registrations` is a
-- statement about who is expected; `match_team_assignments`, `match_goals` and
-- `match_results.mvp_professional_guest_id` are statements about what happened.
-- A match that has been played is a record, so taking somebody off the roster
-- must never delete the side they played on, the goals they scored, or the
-- award they were given -- and it must never leave the completed match unable
-- to show who was on the pitch.
--
-- So the seat always goes, and nothing else does unless there is nothing else
-- to keep:
--
--   * the seat in `match_registrations`  -- always removed
--   * the lineup row, the goals, the MVP -- kept whenever they exist
--   * the guest's identity row           -- kept when anything above refers to
--                                           it, so the completed match can
--                                           still name them
--
-- A guest added by mistake and removed before they played leaves nothing
-- behind: there is no lineup row and no result data, so the identity goes too
-- and the match is as if they were never added. A guest who played is preserved
-- in full and simply stops being on the roster.
--
-- The `on delete no action` references migration `0044` puts on the three
-- historical tables are what make this safe rather than merely intended: the
-- delete below is refused outright by the database if anything historical still
-- points at the guest, so a future edit to this function cannot quietly start
-- destroying records.
--
-- There is deliberately **no refusal** here. An earlier draft raised
-- `RESULT_PARTICIPANT_REMOVED` when the guest was a scorer or the MVP, which
-- was the wrong answer to the right question: that rule exists to stop a
-- *lineup* edit from orphaning a result, and this is not a lineup edit. The
-- approved rule is that an owner or admin may take a guest off the roster in
-- any state, so it is allowed, and the record it leaves behind is intact.
--
-- No `detach_match_effects` / `attach_match_effects` pair either. Migration
-- `0046` made a guest contribute nothing to any rating, player counter or
-- community figure, so nothing here moves one -- which is what "no persistent
-- statistics" buys.
create or replace function public.remove_professional_guest(
  p_match_id uuid,
  p_guest_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_has_history boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- Both halves matter: the guest must exist, and it must belong to *this*
  -- match. A guest is match-scoped, so an id from another match is not a guest
  -- this caller has any business naming.
  if not exists (
    select 1 from match_professional_guests
    where id = p_guest_id and match_id = p_match_id
  ) then
    raise exception 'GUEST_NOT_FOUND';
  end if;

  -- The roster seat, always.
  delete from match_registrations
  where match_id = p_match_id and professional_guest_id = p_guest_id;

  -- Everything the completed match needs in order to still be true about them.
  v_has_history :=
    exists (select 1 from match_team_assignments
            where match_id = p_match_id and professional_guest_id = p_guest_id)
    or exists (select 1 from match_goals
               where match_id = p_match_id
                 and professional_guest_id = p_guest_id)
    or exists (select 1 from match_results
               where match_id = p_match_id
                 and mvp_professional_guest_id = p_guest_id);

  -- Nothing to preserve: the guest never played, so the identity goes with the
  -- seat and the match keeps no trace of an addition that was a mistake.
  if not v_has_history then
    delete from match_professional_guests
    where id = p_guest_id and match_id = p_match_id;
  end if;

  -- A freed starting slot goes to the first community reserve, and only to
  -- another guest when there is none.
  --
  -- Not on a played match, for the same reason `add_professional_guest` does
  -- not: there is no reserve to promote out of, and re-cutting the roster would
  -- rewrite the record of a match that has already happened.
  if not (v_match.status = 'completed' or v_match.end_at <= now()) then
    perform rebalance_roster(p_match_id);
  end if;
  perform recompute_match_status(p_match_id);
end;
$$;

-- 3) Rename ------------------------------------------------------------------------
-- A correction to how somebody is written down, and nothing more: no seat
-- moves, no ordering changes, no status is recomputed.
--
-- The match row is still locked. It costs nothing, it keeps the authorization
-- read and the write in one consistent view of the match, and it means all
-- three operations take the same lock in the same order -- which is how a
-- deadlock between two of them is ruled out rather than hoped against.
create or replace function public.rename_professional_guest(
  p_match_id uuid,
  p_guest_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_name is null or char_length(trim(p_name)) < 2
     or char_length(trim(p_name)) > 60 then
    raise exception 'INVALID_GUEST_NAME';
  end if;

  update match_professional_guests
  set display_name = trim(p_name)
  where id = p_guest_id and match_id = p_match_id;

  if not found then raise exception 'GUEST_NOT_FOUND'; end if;
end;
$$;

-- Grants ---------------------------------------------------------------------------
-- The same shape every match-management RPC has: unreachable by `anon`, reachable
-- by `authenticated`, and the role check inside decides the rest. `SECURITY
-- DEFINER` is required because `match_registrations` and
-- `match_professional_guests` have no write policies at all -- every write in
-- this schema goes through a function, which is what makes the rules
-- unavoidable.
revoke execute on function public.add_professional_guest(uuid, text)
  from anon, public;
grant execute on function public.add_professional_guest(uuid, text)
  to authenticated;

revoke execute on function public.remove_professional_guest(uuid, uuid)
  from anon, public;
grant execute on function public.remove_professional_guest(uuid, uuid)
  to authenticated;

revoke execute on function public.rename_professional_guest(uuid, uuid, text)
  from anon, public;
grant execute on function public.rename_professional_guest(uuid, uuid, text)
  to authenticated;
