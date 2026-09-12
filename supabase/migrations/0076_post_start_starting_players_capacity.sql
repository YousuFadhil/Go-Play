-- ============ migrations/0076_post_start_starting_players_capacity.sql ========
-- `starting_players` is editable after kickoff, which means the capacity rule
-- has to stop applying there.
--
-- ## The block this removes
--
-- `0074` made the roster decision follow the RESULTING lifecycle: an edit whose
-- result is active or completed rebalances nothing, promotes nobody and leaves
-- the factual lineup alone. What it carried forward unchanged was the capacity
-- check that runs before the write:
--
--     select count(*) into v_total from match_registrations where ...
--     if p_starting_players + reserve_players < v_total then
--       raise exception 'MAX_BELOW_REGISTERED';
--     end if;
--
-- On a match still to come that is the right rule -- the places being offered
-- have to fit the registrations already taken. On a match that has been played
-- it is a refusal about nothing: the fixture happened, the participation is
-- recorded, and `starting_players` is planning metadata describing a plan that
-- has already been overtaken. Worse, a completed match can legitimately hold
-- more confirmed participants than it has starting slots -- both completed
-- correction paths confirm a corrected player without consulting the count --
-- so the very matches most likely to be corrected were the ones the check
-- refused.
--
-- The result was that the approved contract could not be honoured: the product
-- says `starting_players` is editable in FUTURE, ACTIVE and COMPLETED, and the
-- database said MAX_BELOW_REGISTERED.
--
-- ## The rule
--
--   resulting FUTURE      capacity enforced, exactly as before
--   resulting ACTIVE      capacity not consulted
--   resulting COMPLETED   capacity not consulted
--
-- Decided by `v_becomes_completed` and `v_becomes_active`, the two flags
-- `0074`'s monotonicity guard already derives from the requested times, so this
-- migration adds no second definition of what a lifecycle state is.
--
-- ## What does not change
--
-- Everything else in the function is `0074`'s, byte for byte: authentication,
-- the suspended-account check, the owner/admin role test, title validation, the
-- valid time range, the 4..30 bound on `starting_players` itself -- which stays
-- universal, because it is a statement about the number and not about the
-- roster -- lifecycle monotonicity with its MATCH_LOCKED and MATCH_COMPLETED
-- refusals, the resulting-state roster branch, and the notification fan-out.
-- The signature, the SECURITY DEFINER, the pinned `search_path` and the
-- privileges are unchanged.
--
-- Append-only: `0073`, `0074` and `0075` are not edited, no table is altered and
-- no new error token is introduced.

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
  -- NEW (0074): the ORIGINAL lifecycle, read from the locked row before
  -- the new times are applied.
  v_was_active boolean;
  -- NEW (0074): the REQUESTED lifecycle, derived from the new times. The
  -- original state decides which transitions are allowed; the resulting state
  -- decides what happens to the roster afterwards. They are not the same
  -- question and a single flag cannot answer both.
  v_becomes_completed boolean;
  v_becomes_active boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- CHANGED: the MATCH_COMPLETED and MATCH_LOCKED gates are gone. Owner/admin
  -- administration is allowed in every match state. Whether the match has been
  -- played decides what happens to the roster below, never whether the caller
  -- may act.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  -- NEW (0074): ACTIVE is "started but not yet played". Derived here, from
  -- the same locked row, so the guard below cannot be asked of the values it
  -- is about to write.
  v_was_active := not v_played and v_match.start_at <= now();
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;

  -- NEW (0074): LIFECYCLE MONOTONICITY.
  --
  -- This is not a reinstated edit gate. `0065` removed the gates that asked
  -- whether an organizer may edit at all, and they stay removed: every field
  -- above is editable in every state, any number of times. What is refused
  -- here is a specific pair of new times -- the ones that would move a match
  -- backwards into a state it has already left.
  --
  --   FUTURE    -> FUTURE, ACTIVE, COMPLETED      allowed
  --   ACTIVE    -> ACTIVE, COMPLETED              allowed
  --   COMPLETED -> COMPLETED                      allowed
  --
  -- A completed match is history. Its new end must already have passed, which
  -- is the one test that refuses COMPLETED -> ACTIVE and COMPLETED -> FUTURE
  -- together: both of them ask for an end that has not happened yet. It also
  -- stops the unreadable state where `status` says completed and the times
  -- say the match is still to come.
  v_becomes_completed := p_end_at <= now();
  v_becomes_active := not v_becomes_completed and p_start_at <= now();

  if v_played then
    if not v_becomes_completed then raise exception 'MATCH_COMPLETED'; end if;
  -- A match that has kicked off cannot be returned to the schedule. Players
  -- have turned up to it; reopening it for registration would be a different
  -- match wearing this one's record.
  elsif v_was_active then
    if not (v_becomes_completed or v_becomes_active) then
      raise exception 'MATCH_LOCKED';
    end if;
  end if;
  if p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  -- CHANGED (0076): the capacity rule applies only while the match remains a
  -- plan. `starting_players` means two different things either side of kickoff:
  -- before it, it is the number of places the roster is being cut to, and the
  -- registrations already taken have to fit inside it; after it, the match has
  -- been played with whoever actually turned up, and the count is planning
  -- metadata about a fixture whose participation is already recorded.
  --
  -- Keeping the check unconditional made the approved contract unreachable:
  -- `starting_players` is editable in every state, yet an organizer correcting a
  -- played match that had more registrations than places was refused with
  -- MAX_BELOW_REGISTERED -- a capacity complaint about a match nobody can join
  -- any more. A completed match can legitimately hold more confirmed
  -- participants than it has starting slots, because
  -- `set_completed_match_player` and `correct_completed_match_players` confirm a
  -- corrected player without regard to the count.
  --
  -- Asked of the same two flags the monotonicity guard above uses, so there is
  -- one lifecycle definition in this function and not a second one. The 4..30
  -- bound stays universal: it is a statement about the number itself.
  if not (v_becomes_completed or v_becomes_active) then
    -- Guests are part of `v_total`: the capacity a new starting count has to fit
    -- is every participant, which is the same rule registration applies.
    select count(*) into v_total from match_registrations where match_id = p_match_id;
    if p_starting_players + (select reserve_players from app_settings limit 1) < v_total then
      raise exception 'MAX_BELOW_REGISTERED';
    end if;
  end if;
  update matches set
    title = trim(p_title),
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;
  -- CHANGED (0074): WHAT HAPPENS TO THE ROSTER FOLLOWS THE RESULTING STATE.
  --
  -- `0065` asked this of the ORIGINAL state, which was wrong in three cases an
  -- organizer can reach: an active match being edited, a future match corrected
  -- into an active one, and a future match entered as a record of one already
  -- played. All three still ran `rebalance_roster`, so changing the starting
  -- count promoted and demoted players -- and `recompute_match_status` went on
  -- to re-cut the status and, through `reconcile_match_lineup`, the stored
  -- lineup -- for a match that is being played or is over. Once a match has
  -- kicked off its roster is participation rather than a plan, and editing its
  -- details must not rewrite who took part.
  --
  -- RESULTING COMPLETED: the match is history. The stored status is settled and
  -- nothing else is touched. This is the statement `recompute_match_status` runs
  -- in its own completed branch, so a match that finished without anything
  -- having touched it still gets the status it was owed.
  if v_becomes_completed then
    update matches set status = 'completed'
    where id = p_match_id and status <> 'completed';
  -- RESULTING ACTIVE: the match is being played. No rebalance, no promotion or
  -- demotion, no lineup reconciliation, and no status recomputation -- the
  -- stored status is already one of the non-completed ones and recomputing it
  -- would reopen registration on a match in progress.
  elsif v_becomes_active then
    null;
  -- RESULTING FUTURE: still a plan, so the ordinary behaviour is untouched --
  -- the roster is re-cut to the new starting count and the status recomputed,
  -- exactly as before this migration.
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

comment on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) is
  'Owner/admin match administration, allowed in every lifecycle state and any '
  'number of times. Title, location, times, starting_players and description are '
  'all editable while a match is future, active or completed. The lifecycle may '
  'only move forward: an active match may not be returned to the future '
  '(MATCH_LOCKED) and a completed match may not be reopened as active or future '
  '(MATCH_COMPLETED), which also means a completed match''s new end_at must '
  'already have passed. starting_players must always be 4..30, and the '
  'registration-capacity rule (MAX_BELOW_REGISTERED) applies ONLY while the '
  'resulting state is future, where the count is the number of places being '
  'offered; once the match is under way or played it is planning metadata about '
  'participation that is already recorded, and a played match may legitimately '
  'hold more confirmed participants than it has starting slots. What happens to '
  'the roster afterwards follows the RESULTING state: once the result of the '
  'edit is active or completed -- including a future match corrected into '
  'either -- nothing is rebalanced, nobody is promoted or demoted, the status is '
  'not recomputed and the stored lineup is not reconciled. An edit whose result '
  'is still a future match keeps the ordinary rebalance and status '
  'recomputation. See migrations 0074 and 0076.';
