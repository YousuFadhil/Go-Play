-- Roster ordering with Professional Guests, and the administrative unlock.
--
-- Two things happen here, and they are separate.
--
-- ## 1. One ordering, stated once
--
-- Every approved priority rule collapses into a single sort key:
--
--     ORDER BY (user_id IS NULL), registration_order
--
-- `false` sorts before `true`, so every community participant precedes every
-- guest, and each class keeps its own arrival order. That one clause is the
-- whole of four product rules:
--
--   * community confirmed players outrank guests
--   * a freed starting slot goes to the first community reserve, and only to a
--     guest when there is no community reserve -- guests then in arrival order
--     (**FIFO**)
--   * a community player entering pushes guests rightwards, so the guest who
--     falls past `starting_players` first is the one added last (**LIFO**)
--   * guests take starting slots before reserve capacity, because the cut is
--     made at `starting_players` over the same single ordering
--
-- No second queue and no guest-specific ordering column: guests share the
-- existing per-match `registration_order` sequence, so
-- `UNIQUE (match_id, registration_order)` keeps meaning what it meant.
--
-- **Notifications.** `create_notification` writes `notifications.user_id`, which
-- is `NOT NULL`. Every fan-out over `match_registrations` therefore has to skip
-- guest rows or the statement fails outright -- this is not a courtesy, it is
-- what keeps `update_match` and `purge_match` working at all once a match holds
-- a guest. A guest is never notified of anything; a real user is notified
-- exactly as before.
--
-- ## 2. The administrative unlock
--
-- The approved decision is that an owner or admin manages a match's players in
-- **all** states -- open, full, during the scheduled time, after it, and
-- completed -- and that the time-derived lock must not stand in the way.
--
-- The lock is not removed. It is moved to where it belongs: `register_for_match`
-- and `withdraw_from_match` are **self-service** and keep every gate they have,
-- because relaxing them is not what was approved and would let a player join a
-- match that has already kicked off. The administrative entry points
-- (`admin_add_player_to_match`, `remove_player`) stop asking.
--
-- `register_player_in_match` is the transaction both registration paths share
-- (migration `0041`), so the policy becomes an explicit argument rather than
-- something the helper decides. It is not defaulted: a caller that does not
-- state its policy is a caller that has not thought about it.
--
-- `update_match` is unlocked on the same terms, and its hazard is handled rather
-- than avoided: re-cutting the roster of a match that has already been played
-- would demote community players out of a lineup whose result is recorded, and
-- notify them about it. So a played match is edited without a rebalance. See
-- section 8.
--
-- Idempotent: `create or replace` throughout, plus one `drop function` for the
-- helper whose signature gains the policy argument.

-- 1) rebalance_roster -------------------------------------------------------------
-- The canonical placement of every participant in a match. `update_match` calls
-- it when capacity changes, and migration `0047`'s guest operations call it for
-- the same reason: the roster has been disturbed and has to be re-cut.
--
-- Two changes to migration `0040`'s body, both marked below. Everything else --
-- the title-carrying notification, the single pass, the update-only-if-changed
-- test -- is exactly as it was.
create or replace function public.rebalance_roster(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_starting int; v_title text; r record;
begin
  select starting_players, title into v_starting, v_title
  from matches where id = p_match_id;
  for r in
    select mr.id, mr.user_id, mr.status,
           case when row_number() over (
                  -- CHANGED: community participants first, then guests; each in
                  -- arrival order. This single clause is FIFO promotion, LIFO
                  -- displacement and community priority all at once.
                  order by (mr.user_id is null), mr.registration_order
                ) <= v_starting
                then 'confirmed' else 'reserve' end as desired
    from match_registrations mr where mr.match_id = p_match_id
  loop
    if r.status <> r.desired then
      update match_registrations set status = r.desired where id = r.id;
      -- CHANGED: a guest has nobody to notify. `notifications.user_id` is NOT
      -- NULL, so this guard is what keeps the statement legal as well as quiet.
      if r.user_id is not null then
        if r.desired = 'reserve' then
          perform create_notification(r.user_id, p_match_id, 'moved_to_reserve',
              coalesce(v_title, ''));
        else
          perform create_notification(r.user_id, p_match_id, 'promoted',
              coalesce(v_title, ''));
        end if;
      end if;
    end if;
  end loop;
end;
$$;

revoke execute on function public.rebalance_roster(uuid)
  from anon, authenticated, public;

-- 2) The shared registration transaction ------------------------------------------
-- Migration `0041`'s helper, with two changes.
--
-- **(a) The time lock became an argument.** `p_enforce_time_lock` is required,
-- not defaulted. `register_for_match` passes true and behaves exactly as it
-- always has; `admin_add_player_to_match` passes false, which is the approved
-- administrative unlock and the only behaviour change in this function.
--
-- **(b) The seat is decided over community players and then re-cut.** The old
-- body asked `count(*) where status = 'confirmed' < starting_players`. With
-- guests in the same table that count includes them, so a joining community
-- player would be sent to the reserve by a guest sitting in a starting slot --
-- precisely the inversion the approved rules forbid.
--
-- The question it now asks is how many **community** registrations there are.
-- The new row is the last of them, so it starts if the community count after
-- the insert still fits inside `starting_players`. For a match with no guests
-- this is arithmetically identical to the old test, because the confirmed set
-- has always been the first `starting_players` registrations: where the old
-- count was `min(community_total, starting_players)`, both expressions flip at
-- the same registration. Nothing changes for a community-only match.
--
-- `rebalance_roster` then runs, and *that* is what performs the LIFO
-- displacement: the guest holding the last starting slot moves to the reserve.
-- The status is read back afterwards rather than assumed, so the value returned
-- to the caller is the one actually stored.
--
-- Note on the shape of (b): the approved instruction was to insert as `reserve`
-- and let `rebalance_roster` place the row. That is not done, for one concrete
-- reason -- `rebalance_roster` notifies on every status change it makes, so a
-- row inserted as `reserve` and immediately promoted would send the registrant a
-- "you have been promoted from the reserve" notification for an ordinary
-- sign-up that was never on the reserve. Preserving existing notification
-- behaviour for real users is also an approved requirement, and computing the
-- seat over community players satisfies both: displacement still happens in
-- `rebalance_roster`, and the row is never written in a state it was not in.
drop function if exists public.register_player_in_match(uuid, uuid);

create or replace function public.register_player_in_match(
  p_match_id uuid,
  p_user_id uuid,
  p_enforce_time_lock boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_community int;
  v_status text;
  v_order int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  perform 1 from users where id = p_user_id for update;

  -- CHANGED: the two lifecycle gates are now the caller's policy. Self-service
  -- passes true and is refused after kickoff exactly as before; the
  -- administrative path passes false, which is the approved unlock.
  if p_enforce_time_lock then
    if v_match.status = 'completed' or v_match.end_at <= now() then
      raise exception 'MATCH_CLOSED';
    end if;
    if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  end if;

  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  if exists (select 1 from match_registrations
             where match_id = p_match_id and user_id = p_user_id) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  -- Total capacity, and guests are inside it: the count is over every row of the
  -- match, so a guest occupies a place a community player then cannot have.
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  if exists (
    select 1 from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = p_user_id
      and m.status in ('open', 'full')
      and m.end_at > now()
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  -- CHANGED: over community registrations, not over the confirmed count.
  select count(*) into v_community
  from match_registrations
  where match_id = p_match_id and user_id is not null;

  v_status := case when v_community + 1 <= v_match.starting_players
                   then 'confirmed' else 'reserve' end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);

  -- CHANGED: re-cut the roster, which is where a displaced guest moves down.
  perform rebalance_roster(p_match_id);

  -- CHANGED: report what was stored rather than what was intended.
  select status into v_status from match_registrations
  where match_id = p_match_id and user_id = p_user_id;

  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

revoke execute on function public.register_player_in_match(uuid, uuid, boolean)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid, boolean)
  to service_role;

-- 3) Self-registration -------------------------------------------------------------
-- Unchanged in every respect a caller can observe: same signature, same return
-- values, same exceptions in the same order. It states its policy explicitly.
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- A player registering themselves is refused once the match has started. That
  -- rule is untouched by the administrative unlock below.
  return register_player_in_match(p_match_id, auth.uid(), true);
end;
$$;

revoke execute on function public.register_for_match(uuid) from anon, public;
grant execute on function public.register_for_match(uuid) to authenticated;

-- 4) The administrative add ---------------------------------------------------------
-- Migration `0041`'s function with one change: it no longer inherits the time
-- lock. An owner or admin may add a community member to a match in any state,
-- which is the approved decision.
--
-- Everything else the helper enforces still applies to the player being added --
-- community membership, the duplicate rule, total capacity and the overlap
-- check. An admin may add somebody; an admin may not add somebody twice, past
-- capacity, into a clash, or into a community they do not belong to.
--
-- What this deliberately does **not** do is write a lineup row. For a completed
-- match, `set_completed_match_player` remains the operation that records who was
-- on the pitch and recalculates the result's effects around the change; this
-- records only that they were on the roster.
create or replace function public.admin_add_player_to_match(
  p_match_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- CHANGED: false. Owner/admin management is allowed in every match state.
  return register_player_in_match(p_match_id, p_user_id, false);
end;
$$;

revoke execute on function public.admin_add_player_to_match(uuid, uuid)
  from anon, public;
grant execute on function public.admin_add_player_to_match(uuid, uuid)
  to authenticated;

-- 5) withdraw_from_match --------------------------------------------------------------
-- Self-service. Every gate it has is kept, including `MATCH_LOCKED` after
-- kickoff: this is the player's own decision to leave, not administration.
--
-- One change: the promotion picks the first row of the approved ordering, so a
-- waiting community player is always promoted ahead of a guest. When the
-- promoted row *is* a guest, `returning user_id` yields null and the existing
-- `is not null` guard already suppresses the notification -- the guest is
-- promoted silently, which is exactly the required behaviour.
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype; v_registration match_registrations%rowtype; v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then raise exception 'MATCH_CLOSED'; end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  select * into v_registration from match_registrations where match_id = p_match_id and user_id = auth.uid();
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (select id from match_registrations
                where match_id = p_match_id and status = 'reserve'
                -- CHANGED: community reserve first, then guests in arrival order.
                order by (user_id is null), registration_order limit 1)
    returning user_id into v_promoted;
    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted', v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
end;
$$;

revoke execute on function public.withdraw_from_match(uuid) from anon, public;
grant execute on function public.withdraw_from_match(uuid) to authenticated;

-- 6) remove_player ----------------------------------------------------------------------
-- Administration, so the two lifecycle gates go: an owner or admin may take a
-- player off the roster of a match in any state, including one that has been
-- played.
--
-- The promotion ordering changes with everything else.
--
-- **Scope note, deliberately left alone.** This removes the registration and not
-- the lineup row. Before this migration the question could not arise, because
-- the gates refused the call from kickoff onwards. It can now: removing a player
-- from a completed match leaves their `match_team_assignments` row, and with it
-- the statistics and ratings that row earned. `set_completed_match_player` is
-- the operation that removes both together and recalculates the result's
-- effects around the change, and it remains the correct tool for a played
-- match. Making `remove_player` cascade into the lineup is a real change to what
-- it means and is not part of the approved guest work -- it is reported as an
-- open item rather than decided here.
create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
  v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- CHANGED: the MATCH_COMPLETED and MATCH_LOCKED gates are gone. Owner/admin
  -- management is allowed in every match state.
  select * into v_registration from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (select id from match_registrations
                where match_id = p_match_id and status = 'reserve'
                -- CHANGED: community reserve first, then guests in arrival order.
                order by (user_id is null), registration_order limit 1)
    returning user_id into v_promoted;
    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed', v_match.title);
end;
$$;

revoke execute on function public.remove_player(uuid, uuid) from anon, public;
grant execute on function public.remove_player(uuid, uuid) to authenticated;

-- 7) purge_membership -------------------------------------------------------------------
-- A member leaving the community leaves every match in it. Same promotion
-- ordering as everywhere else; the guest case is again silent by way of the
-- existing null guard.
create or replace function public.purge_membership(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_promoted uuid;
begin
  for r in
    select mr.id, mr.status, mr.match_id, m.title
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id and mr.user_id = p_user_id
  loop
    perform 1 from matches where id = r.match_id for update;
    delete from match_registrations where id = r.id;
    if r.status = 'confirmed' then
      update match_registrations set status = 'confirmed'
      where id = (select id from match_registrations
                  where match_id = r.match_id and status = 'reserve'
                  -- CHANGED: community reserve first, then guests in arrival order.
                  order by (user_id is null), registration_order limit 1)
      returning user_id into v_promoted;
      if v_promoted is not null then
        perform create_notification(v_promoted, r.match_id, 'promoted',
            coalesce(r.title, ''));
      end if;
    end if;
    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

revoke execute on function public.purge_membership(uuid, uuid)
  from anon, authenticated, public;

-- 8) The two notification fan-outs over the roster ------------------------------------------
-- `update_match` and `purge_match` each write one notification per registration.
-- `notifications.user_id` is NOT NULL, so a guest row in the roster makes the
-- whole statement fail -- editing or deleting a match that has a guest in it
-- would raise a not-null violation.
--
-- `update_match` also loses its two lifecycle gates, which is the rest of the
-- approved administrative unlock: an owner or admin edits a match in every
-- state, including one that has been played.
--
-- **What replaces the gate is a rule about the match, not about permission.**
-- A match that has been played stays played, in two respects.
--
-- *Its roster.* `rebalance_roster` re-cuts confirmed and reserve from
-- `starting_players`, and on a played match that would be destructive in two
-- ways at once: it would demote community players whose lineup rows and result
-- are already recorded, and it would send each of them a "you have been moved to
-- the reserve" notice about a match that finished. A played match has no reserve
-- -- everyone in the record played, which is what migration `0029` says where it
-- first mattered -- so the roster of one is left as the record it is.
--
-- *Its status.* `recompute_match_status` decides from the **stored** `end_at`,
-- so an administrator moving a completed match's schedule forward would have it
-- recomputed back to `open` or `full` -- a match with a recorded lineup, result,
-- goals and MVP, reopened for registration. `v_played` is read from the row as it
-- was *before* the update, so what a match has already been is not something an
-- edit to its times can undo. This is a rule about the outcome of the edit and
-- never a restriction on making it: an owner or admin may move the times of a
-- completed match freely, and it stays completed.
--
-- `MAX_BELOW_REGISTERED` is what keeps that atomic. A starting count that no
-- longer fits every participant is refused *before* the update, so there is no
-- path on which capacity shrinks under a roster and something has to be dropped
-- to make it fit. Nothing here deletes or demotes a historical record.
create or replace function public.update_match(
  p_match_id uuid, p_title text, p_location text,
  p_start_at timestamptz, p_end_at timestamptz,
  p_starting_players integer, p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_played boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- CHANGED: the MATCH_COMPLETED and MATCH_LOCKED gates are gone. Owner/admin
  -- administration is allowed in every match state. Whether the match has been
  -- played decides what happens to the roster below, never whether the caller
  -- may act.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  -- Guests are part of `v_total`: the capacity a new starting count has to fit
  -- is every participant, which is the same rule registration applies.
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if p_starting_players + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;
  update matches set
    title = trim(p_title),
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;
  -- CHANGED: a played match keeps the roster it played with, and the status it
  -- earned. Re-cutting the roster would demote players out of a recorded lineup
  -- and notify them about a match that is already over; recomputing the status
  -- from the new `end_at` would reopen it for registration.
  --
  -- The statement below is the one `recompute_match_status` runs in its own
  -- completed branch, so a match that finished without anything having touched it
  -- still gets the stored status it was owed. An Open or Full match takes the
  -- unchanged path and is recomputed exactly as before.
  if v_played then
    update matches set status = 'completed'
    where id = p_match_id and status <> 'completed';
  else
    perform rebalance_roster(p_match_id);
    perform recompute_match_status(p_match_id);
  end if;
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      trim(p_title))
  -- CHANGED: guests have nobody to notify, and notifications.user_id is NOT NULL.
  from match_registrations mr
  where mr.match_id = p_match_id and mr.user_id is not null;
end;
$$;

revoke execute on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) from anon, public;
grant execute on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) to authenticated;

create or replace function public.purge_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select title into v_title from matches where id = p_match_id;
  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      coalesce(v_title, ''))
  -- CHANGED: guests have nobody to notify, and notifications.user_id is NOT NULL.
  from match_registrations mr
  where mr.match_id = p_match_id and mr.user_id is not null;
  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

revoke execute on function public.purge_match(uuid) from anon, authenticated, public;
