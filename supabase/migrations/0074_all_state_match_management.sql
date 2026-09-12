-- ============ migrations/0074_all_state_match_management.sql ============
-- Owner/admin management in every lifecycle state, and one atomic correction.
--
-- ## What this migration is for
--
-- An owner or admin may administer a match whenever they need to: before it is
-- played, while it is being played, and after it is over, without a limit on
-- how many times. `0065` already removed the edit gates from `update_match`;
-- what was still missing is the three rules that make unlimited management safe
-- rather than merely possible.
--
--   A1. Correcting several players of a completed match is ONE transaction.
--   A2. A match's lifecycle may move forward, never backwards.
--   A3. A final result exists only for a match that has been played.
--
-- `0071`'s guard -- generation may not rewrite a completed match, while an
-- explicit correction may -- is relied on and not touched. `0073` is not
-- touched either: this migration is written to run after it and says nothing
-- about rating precision or the participation value.
--
-- Append-only. No prior migration is edited, no table is altered, no trigger is
-- added and no view is dropped.
--
-- ## A1. Why a batch is not a loop
--
-- `set_completed_match_player` (0029, latest body in 0065) corrects one player:
-- it asserts the result survives the change, detaches the match's effects,
-- moves the roster row and the lineup row together, and attaches the effects
-- again. Calling it N times to correct N players would detach and reattach N
-- times -- N rating reversals and N reapplications over intermediate lineups
-- that never existed -- and a failure at player K would leave K-1 corrections
-- standing. The screen that shows an organizer a completed lineup lets them
-- move several players at once, so the database is given the whole intent:
--
--   * the ENTIRE payload is validated before anything is written;
--   * the FINAL lineup is projected and the result-survivability guard is asked
--     about that projection, not about each step of it;
--   * `detach_match_effects` runs ONCE, every change is applied, and
--     `attach_match_effects` runs ONCE;
--   * any refusal anywhere rolls the whole batch back, because it is one
--     function in one transaction.
--
-- Ratings and statistics are therefore recalculated exactly once, from the
-- lineup the organizer actually meant.
--
-- `set_completed_match_player` is kept exactly as it is. An older client still
-- calls it and still works; the new application path calls the batch.
--
-- ## One new error token
--
-- `INVALID_CHANGES`, approved by the Product Owner for two refusals that the
-- existing vocabulary had no word for: a `p_changes` that is not a JSON array,
-- and a batch naming the same player twice. Both say the same thing -- this is
-- not a well-formed batch -- and `record_match_result` sets the precedent by
-- raising its own payload token, `INVALID_GOALS`, for exactly these two faults.
-- Every other refusal here is existing vocabulary: `NOT_AUTHENTICATED`,
-- `ACCOUNT_SUSPENDED`, `MATCH_NOT_FOUND`, `COMMUNITY_INACTIVE`,
-- `NOT_AUTHORIZED`, `MATCH_NOT_COMPLETED`, `MEMBER_NOT_FOUND`,
-- `NOT_COMMUNITY_MEMBER`, `INVALID_TEAM`, `INVALID_POSITION` and
-- `RESULT_PARTICIPANT_REMOVED`.
--
-- ## A2. Lifecycle monotonicity
--
-- The lifecycle of a match is read from its times, exactly as the rest of the
-- product reads it:
--
--   FUTURE     start_at > now()
--   ACTIVE     start_at <= now() < end_at, and not already completed
--   COMPLETED  status = 'completed' OR end_at <= now()
--
-- Time moves one way and so does a match. An organizer may correct a future
-- match into any state -- including recording one that has already happened --
-- may end an active match early, and may keep editing a completed one forever.
-- What they may not do is move a match backwards:
--
--   FUTURE    -> FUTURE, ACTIVE, COMPLETED      allowed
--   ACTIVE    -> ACTIVE, COMPLETED              allowed
--   COMPLETED -> COMPLETED                      allowed
--   ACTIVE    -> FUTURE                         MATCH_LOCKED
--   COMPLETED -> ACTIVE or FUTURE               MATCH_COMPLETED
--
-- Both tokens are the existing vocabulary for precisely these states:
-- `MATCH_LOCKED` has meant "this match has started" since `0013`, and
-- `MATCH_COMPLETED` has meant "this match has been played" throughout. Neither
-- is new and both are already mapped by the application's failure mapper.
--
-- The original lifecycle is read from the row that was locked BEFORE the new
-- times are applied -- otherwise the question would be asked of the answer.
--
-- A completed match's new `end_at` must therefore be in the past. The refusal is
-- what stops a match from storing `status = 'completed'` while its times claim
-- it is still to be played, which is a state nothing downstream can read.
--
-- `starting_players` stays editable in every state, and on a match that has
-- started or finished, changing it deliberately does NOT re-cut the roster:
-- `0065`'s `v_played` branch is preserved as it stands, so no player is promoted
-- or demoted out of a lineup that has already been played, no assignment is
-- rewritten and no team is regenerated. A future match keeps the ordinary
-- rebalance-and-recompute path, which is the behaviour it has today.
--
-- ## A3. A result belongs to a played match
--
-- `record_match_result` reversed the old result's ratings and statistics,
-- deleted its goals and wrote the new one without ever asking whether the match
-- had been played. A result entered for a match still to come is not a
-- provisional score; it is a rating movement credited to a match nobody has
-- played yet. The guard is placed immediately after authorization, before every
-- validation and long before the first reversal, so a refused write mutates
-- nothing at all.
--
-- `MATCH_NOT_COMPLETED` is the token `0071` already uses for this state. After
-- completion nothing changes: the first save is allowed, repeated edits stay
-- unlimited, and the atomic reverse-then-reapply behaviour is untouched. No
-- provisional or live score is introduced and no new result state exists.

-- 1) The atomic batch correction ------------------------------------------------
--
-- `p_changes` is a JSON array. Each element names one community player and what
-- is to become of them:
--
--   {"user_id": "...", "action": "UPSERT", "team": "A",
--    "assigned_position": "MID"}
--   {"user_id": "...", "action": "REMOVE"}
--
-- `assignment_basis` is deliberately NOT accepted from the caller. Per §5.1 it
-- records which rule produced the position, which is a fact about the player's
-- profile, so it is derived here from `users.primary_position` and
-- `users.secondary_position` -- the same three-way case expression
-- `set_completed_match_player` uses, unchanged.
--
-- Professional Guests are not touched by this function. They keep their lineup
-- rows, their sides and their positions, and they are collected into the
-- projected lineup so that the survivability guard is asked about the lineup as
-- it will actually be. Guests are corrected by their own functions (`0059`).

create or replace function public.correct_completed_match_players(
  p_match_id uuid,
  p_changes jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_entries int;
  v_players int;
  v_user_ids uuid[];
  v_guest_ids uuid[];
  v_change record;
  v_basis text;
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- A suspended account performs no new activity (0064).
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- The match is locked for the whole transaction: its lifecycle is read from
  -- this row, and two organizers correcting the same match serialize here
  -- rather than interleaving their detach/attach cycles.
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

  -- Correction is for the record of a match that has been played. The
  -- authoritative completion rule is the stored status OR the passed end.
  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
  end if;

  -- EVERYTHING BELOW VALIDATES. Nothing is written until the last check passes,
  -- which is what makes a refused batch leave no trace.

  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'INVALID_CHANGES';
  end if;

  -- Every element names a player and an action this function understands. A
  -- user_id that is not a uuid is a malformed batch, not a missing member, so
  -- it is refused here rather than by a cast failing mid-statement.
  if exists (
    select 1 from jsonb_array_elements(p_changes) as e
    where nullif(e->>'user_id', '') is null
       or e->>'user_id' !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or upper(coalesce(e->>'action', '')) not in ('UPSERT', 'REMOVE')
  ) then
    raise exception 'INVALID_CHANGES';
  end if;

  -- One statement per player. Two entries for the same player are not a bigger
  -- correction, they are two answers to one question, and which of them won
  -- would depend on the order the array happened to arrive in.
  select count(*), count(distinct e->>'user_id')
    into v_entries, v_players
  from jsonb_array_elements(p_changes) as e;
  if v_entries <> v_players then
    raise exception 'INVALID_CHANGES';
  end if;

  -- The vocabulary of an UPSERT, before the identities are looked up: a refusal
  -- about the payload should not depend on which row the database read first.
  if exists (
    select 1 from jsonb_array_elements(p_changes) as e
    where upper(e->>'action') = 'UPSERT'
      and coalesce(e->>'team', '') not in ('A', 'B')
  ) then
    raise exception 'INVALID_TEAM';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_changes) as e
    where upper(e->>'action') = 'UPSERT'
      and coalesce(e->>'assigned_position', '')
          not in ('GK', 'DEF', 'MID', 'FWD')
  ) then
    raise exception 'INVALID_POSITION';
  end if;

  -- Every named player exists. True of a REMOVE as well: the batch names
  -- people, and a uuid belonging to nobody is a batch built from something
  -- stale.
  if exists (
    select 1 from jsonb_array_elements(p_changes) as e
    where not exists (
      select 1 from users u where u.id = (e->>'user_id')::uuid
    )
  ) then
    raise exception 'MEMBER_NOT_FOUND';
  end if;

  -- Membership is required to be PUT INTO a lineup, and deliberately not to be
  -- taken out of one: a player who has since left the community may still be
  -- wrongly recorded as having played, and removing them is the correction.
  if exists (
    select 1 from jsonb_array_elements(p_changes) as e
    where upper(e->>'action') = 'UPSERT'
      and not is_community_member(v_match.community_id, (e->>'user_id')::uuid)
  ) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  -- THE PROJECTED FINAL LINEUP. The whole batch is applied logically -- the
  -- players it removes are gone, the players it upserts are in, everyone it
  -- does not mention stays -- and the result is what the guard is asked about.
  -- Asking per change would refuse a batch that removes a scorer and adds them
  -- back, or allow one whose intermediate state happened to look survivable.
  select coalesce(array_agg(final.user_id), array[]::uuid[]) into v_user_ids
  from (
    select a.user_id
    from match_team_assignments a
    where a.match_id = p_match_id
      and a.user_id is not null
      and not exists (
        select 1 from jsonb_array_elements(p_changes) as e
        where (e->>'user_id')::uuid = a.user_id
      )
    union
    select (e->>'user_id')::uuid
    from jsonb_array_elements(p_changes) as e
    where upper(e->>'action') = 'UPSERT'
  ) final;

  -- Guests are preserved by this function, so every guest in the lineup is in
  -- the projection too.
  select coalesce(array_agg(a.professional_guest_id), array[]::uuid[])
    into v_guest_ids
  from match_team_assignments a
  where a.match_id = p_match_id and a.professional_guest_id is not null;

  -- A scorer or the best player may not disappear from the lineup that produced
  -- the result. Unchanged guard (0044), asked once, about the final lineup.
  perform assert_result_survives_lineup(p_match_id, v_user_ids, v_guest_ids);

  -- VALIDATION IS COMPLETE. From here the match comes apart once, every change
  -- is applied, and it goes back together once.
  perform detach_match_effects(p_match_id);

  for v_change in
    select
      (e->>'user_id')::uuid as user_id,
      upper(e->>'action') as action,
      e->>'team' as team,
      e->>'assigned_position' as assigned_position
    from jsonb_array_elements(p_changes) as e
    -- Ordered so that a batch applies in a defined sequence, which keeps the
    -- registration_order it hands out reproducible.
    order by e->>'user_id'
  loop
    if v_change.action = 'REMOVE' then
      -- The approved semantics of removal (0029): this player did not play
      -- after all, so the lineup row and the roster seat go together.
      delete from match_team_assignments
      where match_id = p_match_id and user_id = v_change.user_id;
      delete from match_registrations
      where match_id = p_match_id and user_id = v_change.user_id;
    else
      -- §5.1: the basis is which rule produced the position, derived from the
      -- profile rather than trusted from the client.
      select case
        when u.primary_position = v_change.assigned_position then 'PRIMARY'
        when u.secondary_position = v_change.assigned_position then 'SECONDARY'
        else 'TRANSITION'
      end into v_basis
      from users u where u.id = v_change.user_id;

      -- A completed match has no reserve queue to wait in and no capacity left
      -- to claim: somebody who played is confirmed, whether or not they ever
      -- registered.
      if not exists (
        select 1 from match_registrations
        where match_id = p_match_id and user_id = v_change.user_id
      ) then
        select coalesce(max(registration_order), 0) + 1 into v_order
        from match_registrations where match_id = p_match_id;
        insert into match_registrations
          (match_id, user_id, status, registration_order)
        values (p_match_id, v_change.user_id, 'confirmed', v_order);
      else
        update match_registrations set status = 'confirmed'
        where match_id = p_match_id and user_id = v_change.user_id;
      end if;

      insert into match_team_assignments
        (match_id, user_id, team, assigned_position, assignment_basis)
      values (p_match_id, v_change.user_id, v_change.team,
              v_change.assigned_position, v_basis)
      -- The partial unique index of 0044 is what this infers, which is why the
      -- predicate is restated.
      on conflict (match_id, user_id) where user_id is not null do update set
        team = excluded.team,
        assigned_position = excluded.assigned_position,
        assignment_basis = excluded.assignment_basis;
    end if;
  end loop;

  perform attach_match_effects(p_match_id);
end;
$$;

comment on function public.correct_completed_match_players(uuid, jsonb) is
  'Corrects several community players of a COMPLETED match in one atomic '
  'transaction: each element of p_changes is an UPSERT (team + '
  'assigned_position) or a REMOVE for one user_id. The entire payload is '
  'validated first, the final lineup is projected and checked against the '
  'recorded result once, and then match effects are detached ONCE, every change '
  'is applied, and they are attached ONCE -- so ratings and statistics are '
  'recalculated a single time from the lineup the organizer meant. Any refusal '
  'rolls back the whole batch. assignment_basis is derived from the player''s '
  'profile and never taken from the caller; Professional Guests are preserved '
  'and never modified here. INVALID_CHANGES means the payload is not an array, '
  'names a player twice, or is otherwise malformed. Owner/admin only, '
  'authenticated, on an active community -- see migration 0074.';

-- Authenticated callers only, and the same shape every client RPC uses.
revoke execute on function public.correct_completed_match_players(uuid, jsonb)
  from anon, public;
grant execute on function public.correct_completed_match_players(uuid, jsonb)
  to authenticated;

-- 2) update_match -- lifecycle monotonicity -------------------------------------
-- `0065`'s body, with three mechanical additions and nothing else: the original
-- ACTIVE test is derived from the already-locked row, and the monotonicity guard
-- is inserted after the time range is known to be valid. Authentication, the
-- suspension check, the role check, title validation, the 4..30 bound, the
-- capacity rule, the notification fan-out and -- crucially -- the `v_played`
-- branch that keeps a played match's roster and status untouched are all
-- preserved exactly as they stand.
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
  if v_played then
    if p_end_at > now() then raise exception 'MATCH_COMPLETED'; end if;
  -- A match that has kicked off cannot be returned to the schedule. Players
  -- have turned up to it; reopening it for registration would be a different
  -- match wearing this one's record.
  elsif v_was_active then
    if p_start_at > now() then raise exception 'MATCH_LOCKED'; end if;
  end if;
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

comment on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) is
  'Owner/admin match administration, allowed in every lifecycle state and any '
  'number of times. Title, location, times, starting_players and description are '
  'all editable while a match is future, active or completed. The lifecycle may '
  'only move forward: an active match may not be returned to the future '
  '(MATCH_LOCKED) and a completed match may not be reopened as active or future '
  '(MATCH_COMPLETED), which also means a completed match''s new end_at must '
  'already have passed. Changing starting_players on a match that has started or '
  'finished deliberately does not rebalance the roster, promote or demote '
  'anybody, rewrite assignments or regenerate teams -- a future match keeps the '
  'ordinary rebalance and status recomputation. See migration 0074.';

-- 3) record_match_result -- the result guard ------------------------------------
-- `0065`'s body with the completion guard inserted after authorization. Every
-- other rule is byte-preserved: score and MVP validation, the lineup
-- requirement, the goals payload checks, the scorer and MVP participation tests,
-- and the atomic reverse-then-reapply of ratings and statistics around the
-- write.
create or replace function public.record_match_result(
  p_match_id uuid,
  p_team_a_score int,
  p_team_b_score int,
  p_mvp_user_id uuid,
  p_goals jsonb default '[]'::jsonb,
  p_mvp_professional_guest_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  -- NEW (0074): the locked row is read rather than merely locked, so its
  -- status and end can be tested.
  v_match matches%rowtype;
  v_participants int;
  v_total_goals int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  -- Added by migration 0065: a suspended community is frozen for new activity.
  if not exists (
    select 1 from matches m
    join communities c on c.id = m.community_id
    where m.id = p_match_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  -- Management is a community role (PD-07, PD-16): the same predicate that gates
  -- the lineup gates its result. Who created the match is attribution.
  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- NEW (0074): A FINAL RESULT BELONGS TO A MATCH THAT HAS BEEN PLAYED.
  --
  -- Placed here, before every input validation and long before the first
  -- reversal, so that a result offered for a future or in-progress match
  -- mutates nothing whatsoever: no rating reversed, no statistic moved, no
  -- goal deleted, no result row written. The authoritative completion rule
  -- is the stored status OR the passed end, the same one `0071` uses.
  --
  -- This is the MVP rule and not a new result state: there is no provisional
  -- score, and after completion the first save and every later correction
  -- stay allowed without limit.
  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
  end if;

  if p_team_a_score < 0 or p_team_b_score < 0 then
    raise exception 'INVALID_SCORE';
  end if;

  -- NEW: one best player, or none. Two would be two answers to one question.
  if p_mvp_user_id is not null and p_mvp_professional_guest_id is not null then
    raise exception 'INVALID_MVP';
  end if;

  -- Who played is the stored lineup. Without one there is no side for a player
  -- to have been on, so there is no winner to reward and no loser to charge --
  -- the rating engine has nothing to work from and the result cannot be taken.
  select count(*) into v_participants
  from match_team_assignments where match_id = p_match_id;
  if v_participants = 0 then
    raise exception 'LINEUP_REQUIRED';
  end if;

  if p_goals is null or jsonb_typeof(p_goals) <> 'array' then
    raise exception 'INVALID_GOALS';
  end if;

  -- A scorer's entry says they scored, so nothing and less than nothing are both
  -- refused rather than quietly dropped.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where coalesce((e->>'goals')::int, 0) <= 0
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- NEW: exactly one identity per entry, which is `match_goals`' own XOR asked
  -- before the insert so the caller gets a named refusal. Equality on the two
  -- booleans is true when they agree -- both set, or neither.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where (nullif(e->>'user_id', '') is not null)
        = (nullif(e->>'professional_guest_id', '') is not null)
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- Two entries for one participant is not a bigger number, it is the same fact
  -- recorded twice, and which of them counted would be arbitrary. Compared over
  -- the identity pair so a user and a guest are never confused for each other.
  if (
    select count(*) from (
      select distinct
        nullif(e->>'user_id', ''),
        nullif(e->>'professional_guest_id', '')
      from jsonb_array_elements(p_goals) as e
    ) d
  ) <> jsonb_array_length(p_goals) then
    raise exception 'INVALID_GOALS';
  end if;

  select coalesce(sum((e->>'goals')::int), 0) into v_total_goals
  from jsonb_array_elements(p_goals) as e;

  if v_total_goals <> p_team_a_score + p_team_b_score then
    raise exception 'GOALS_DO_NOT_MATCH_SCORE';
  end if;

  if p_mvp_user_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id = p_mvp_user_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- NEW: the same rule for a guest. A best player has to have played.
  if p_mvp_professional_guest_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id
      and professional_guest_id = p_mvp_professional_guest_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- A goal is credited to somebody who played it. Otherwise a rating could be
  -- raised for a player who was never in the match.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'user_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.user_id = (e->>'user_id')::uuid
      )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- NEW: and the same for a guest scorer.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'professional_guest_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.professional_guest_id
              = (e->>'professional_guest_id')::uuid
      )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- Nothing has been written yet: everything above refuses before the previous
  -- result is disturbed. From here the old result comes apart and the new one
  -- goes on, in one transaction.
  perform reverse_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, -1);

  delete from match_goals where match_id = p_match_id;

  insert into match_results (
    match_id, team_a_score, team_b_score, mvp_user_id,
    mvp_professional_guest_id, recorded_by
  )
  values (
    p_match_id, p_team_a_score, p_team_b_score, p_mvp_user_id,
    p_mvp_professional_guest_id, auth.uid()
  )
  -- NEW: both MVP columns are assigned, never one. Setting a user MVP over a
  -- stored guest MVP without clearing the guest would leave both non-null and
  -- violate `match_results_mvp_identity_check`.
  on conflict (match_id) do update set
    team_a_score = excluded.team_a_score,
    team_b_score = excluded.team_b_score,
    mvp_user_id = excluded.mvp_user_id,
    mvp_professional_guest_id = excluded.mvp_professional_guest_id,
    recorded_by = excluded.recorded_by;

  insert into match_goals
    (match_id, user_id, professional_guest_id, goals)
  select
    p_match_id,
    nullif(e->>'user_id', '')::uuid,
    nullif(e->>'professional_guest_id', '')::uuid,
    (e->>'goals')::int
  from jsonb_array_elements(p_goals) as e;

  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;

revoke execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb, uuid) from anon, public;
grant execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb, uuid) to authenticated;

comment on function public.record_match_result(uuid, int, int, uuid, jsonb, uuid)
  is
  'Records or corrects the final result of a COMPLETED match: refused with '
  'MATCH_NOT_COMPLETED while the match is future or in progress, and refused '
  'before any mutation so that nothing is reversed, deleted or written by the '
  'attempt. Completion is the stored status OR the passed end. After completion '
  'the first save and every later correction are allowed without limit, each one '
  'reversing the previous result''s ratings and statistics and reapplying the '
  'new one in a single transaction. There is no provisional or live score. See '
  'migration 0074.';
