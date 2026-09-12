-- ============ migrations/0075_completed_professional_guest_correction.sql ======
-- A Professional Guest added to a match that has been played is a correction to
-- the record of who played, not a registration.
--
-- ## The hole this closes
--
-- `add_professional_guest` (0047, latest body in 0065) is the roster operation.
-- On a match still to come it creates the guest, takes a seat, rebalances the
-- roster and lets `recompute_match_status` place the guest on a side through
-- `assign_professional_guest_teams`. That chain is what puts a guest on the
-- pitch, and on a completed match it stops short:
--
--   * `rebalance_roster` is deliberately skipped -- a played match has no
--     reserve to promote from and re-cutting it would demote players out of a
--     recorded lineup;
--   * `recompute_match_status` is called, but its first branch is
--     `end_at <= now()`, where it settles the stored status and RETURNS. It
--     never reaches the lineup reconciliation that places guests.
--
-- So a guest added to a completed match got a row in
-- `match_professional_guests` and a confirmed seat in `match_registrations`,
-- and **no row in `match_team_assignments`**. The application reported a guest
-- added while the factual lineup -- which is what the pitch, the result, the
-- share card and every historical read are drawn from -- did not contain them.
--
-- ## The rule
--
-- Before completion, a guest is a roster matter and nothing here changes:
-- `add_professional_guest` keeps its seat, its capacity rule, its reserve
-- semantics and its placement.
--
-- After completion, a guest is historical evidence. The organizer states who
-- played, on which side, in which position, and all three rows are written
-- together:
--
--   match_professional_guests   the guest exists
--   match_registrations         confirmed, because everyone in the record played
--   match_team_assignments      the factual lineup row, basis GUEST
--
-- One transaction, so a refusal anywhere leaves no half-added guest.
--
-- ## What this deliberately does not do
--
-- **No capacity rule, no reserve, no promotion or demotion.** A completed match
-- can legitimately hold more confirmed participants than it has starting slots --
-- `set_completed_match_player` has always confirmed a corrected player without
-- regard to `starting_players` -- and a reserve seat on a match that has been
-- played would claim somebody waited to play a match that is over.
--
-- **No `rebalance_roster`, no `recompute_match_status`.** Both re-cut a roster
-- that is now a record; the second would also reconcile the stored lineup, which
-- is the very thing being corrected.
--
-- **No notification.** There is nobody to notify: a guest has no account.
--
-- **No `detach_match_effects` / `attach_match_effects`, and no rating or
-- statistics call.** A Professional Guest owns no rating and no player
-- statistics -- `apply_match_rating_effects` and `apply_match_statistics` both
-- read `user_id is not null`. Adding one removes nothing from the result either:
-- no stored scorer and no recorded best player is touched, and the outcome is
-- read from the score. So there is nothing to reverse and nothing to reapply,
-- and detaching would mean reversing every community player's ratings in order
-- to write them back unchanged.
--
-- **No change to the community-player path.** `correct_completed_match_players`
-- (0074) corrects community players and knows nothing about guests; guests keep
-- their own operations, as the approved boundary requires. This migration does
-- not touch it, or `add_professional_guest`, or `remove_professional_guest`, or
-- `remove_played_professional_guest` -- removal after the fact already works and
-- is unchanged, so an older client keeps every behaviour it has.
--
-- Append-only: no prior migration is edited, no table is altered, no view is
-- dropped, and every error token is existing vocabulary.

create or replace function public.add_played_professional_guest(
  p_match_id uuid,
  p_name text,
  p_team text,
  p_assigned_position text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_order int;
  v_guest_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- A suspended account performs no new activity (0064).
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- Locked for the whole transaction, as every other write against a match's
  -- participants is: two organizers correcting the same record serialize here.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  -- A suspended community is frozen for new activity (0065), asked before
  -- authorization so a Platform Admin's suspension is the answer the caller
  -- gets rather than a role refusal.
  if not exists (
    select 1 from communities c
    where c.id = v_match.community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  -- Management is a community role (PD-07, PD-16), and the predicate is the one
  -- every other match write uses.
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- This is a correction to a record, so there has to be a record. A guest on a
  -- match still to come is `add_professional_guest`'s business -- the seat, the
  -- capacity and the reserve are all still live there. The condition is the
  -- authoritative one every completed-match operation uses: the stored status,
  -- or an end that has passed.
  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
  end if;

  -- EVERYTHING BELOW VALIDATES, and nothing is written until the last check
  -- passes: a refused correction leaves no guest, no seat and no lineup row.

  -- The bounds the table's own check states, asked here so the caller gets a
  -- named refusal rather than a constraint violation.
  if p_name is null or char_length(trim(p_name)) < 2
     or char_length(trim(p_name)) > 60 then
    raise exception 'INVALID_GUEST_NAME';
  end if;

  if p_team is null or p_team not in ('A', 'B') then
    raise exception 'INVALID_TEAM';
  end if;

  -- Asked for explicitly and never defaulted. A guest has no profile, so there
  -- is nothing to infer a position from, and where they played is a fact about
  -- the match rather than about them.
  if p_assigned_position is null
     or p_assigned_position not in ('GK', 'DEF', 'MID', 'FWD') then
    raise exception 'INVALID_POSITION';
  end if;

  insert into match_professional_guests (match_id, display_name, created_by)
  values (p_match_id, trim(p_name), auth.uid())
  returning id into v_guest_id;

  -- One sequence per match, shared with community registrations, so
  -- `(user_id is null), registration_order` orders every participant of the
  -- match against every other. Deterministic: the next number after the highest
  -- this match has given out.
  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  -- Confirmed, and never reserve: everyone in the record of a played match
  -- played it.
  insert into match_registrations
    (match_id, professional_guest_id, status, registration_order)
  values (p_match_id, v_guest_id, 'confirmed', v_order);

  -- The factual lineup row -- the one the old path never wrote. `GUEST` is the
  -- basis 0044 gives a participant with no profile: none of PRIMARY, SECONDARY
  -- or TRANSITION can be true of somebody who has no positions to compare
  -- against.
  insert into match_team_assignments
    (match_id, professional_guest_id, team, assigned_position, assignment_basis)
  values (p_match_id, v_guest_id, p_team, p_assigned_position, 'GUEST');

  return v_guest_id;
end;
$$;

comment on function public.add_played_professional_guest(
  uuid, text, text, text
) is
  'Records that a Professional Guest played a COMPLETED match: the guest, a '
  'confirmed registration and the factual match_team_assignments row, written '
  'together in one transaction. The side and the position are stated by the '
  'organizer and never inferred -- a guest has no profile to infer them from -- '
  'and assignment_basis is GUEST. Refused with MATCH_NOT_COMPLETED before '
  'completion, where add_professional_guest remains the roster operation. '
  'Deliberately applies no capacity rule, creates no reserve seat, rebalances '
  'and recomputes nothing, notifies nobody, and touches no rating or statistic: '
  'a guest owns none, and no stored scorer, best player or score is changed by '
  'adding one. Community players keep their own correction path. Owner/admin '
  'only, authenticated, on an active community -- see migration 0075.';

-- Authenticated callers only, the same shape every client RPC uses.
revoke execute on function
  public.add_played_professional_guest(uuid, text, text, text)
  from anon, public;
grant execute on function
  public.add_played_professional_guest(uuid, text, text, text)
  to authenticated;
