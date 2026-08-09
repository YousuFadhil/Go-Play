-- Editing a match that has already been played.
--
-- An owner or admin may correct a completed match: move a player to the other
-- side, add a community member who played but was never registered, remove one
-- who did not, and re-enter the score, the scorers and the MVP. `0022` already
-- made the last of those atomic — `record_match_result` reverses everything the
-- previous result did and applies the new one inside one transaction.
--
-- The lineup had no such treatment, and that was the gap. `replace_match_lineup`
-- (migration `0020`) rewrote `match_team_assignments` and stopped there, while
-- every counter and every rating derived from that lineup stayed as it was. A
-- player moved from the losing side to the winning one kept the loss; a player
-- added to a played match got nothing; the community leaderboards of `0028`
-- disagreed with the lineup they were computed from. Nothing detected it,
-- because nothing was wrong at the row level — the statistics simply described a
-- lineup that no longer existed.
--
-- So this migration makes the rule the same at both levels: **anything that
-- changes who played, or which side they played on, reverses the result's
-- effects and reapplies them in the same transaction.** `apply_match_statistics`
-- carries both the player counters (`0023`) and the community records (`0028`),
-- so one call keeps all three levels — ratings, statistics, leaderboards — in
-- step, and a refusal anywhere rolls the whole edit back.
--
-- Backward compatible: no table, column, constraint or policy changes, and both
-- functions keep the privileges `create or replace` preserves. A match with no
-- recorded result takes the same path it always did, because there is nothing to
-- reverse and nothing to reapply.

-- 1) The two halves of a recalculation ------------------------------------------
-- Stated once and called in pairs. Splitting them is what lets a caller mutate
-- the lineup in between: the effects come off the *old* lineup, the lineup
-- changes, and the effects go back on the *new* one.
--
-- Order within each half follows `record_match_result`: ratings first coming
-- off, ratings first going back on. The two are independent — statistics read
-- the lineup and the result, ratings read the audit — so the order is for
-- readability, not correctness.
--
-- A match with no result makes both of these no-ops: `reverse_match_rating`
-- finds no history to undo and `apply_match_statistics` finds no contribution
-- rows. That is what keeps this invisible to matches that were never played.
create or replace function public.detach_match_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform reverse_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, -1);
end;
$$;

create or replace function public.attach_match_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;

revoke execute on function public.detach_match_effects(uuid)
  from anon, authenticated, public;
revoke execute on function public.attach_match_effects(uuid)
  from anon, authenticated, public;

-- 2) The rule a recorded result puts on its lineup ------------------------------
-- The MVP and every scorer must still be in the lineup afterwards.
--
-- This is not a new rule. `record_match_result` already refuses an MVP or a
-- scorer who is not a participant, and removing one from the lineup reaches the
-- same forbidden state from the other direction: goals credited to somebody who
-- did not play, or a best player who was not on the pitch. Refusing is
-- deliberately chosen over quietly deleting their goals — that would leave the
-- goals no longer adding up to the score, which is the one thing the result
-- rules will not have. The admin edits the result first, then the lineup.
--
-- [p_user_ids] is the lineup as it will be. A match with no result imposes
-- nothing.
create or replace function public.assert_result_survives_lineup(
  p_match_id uuid,
  p_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mvp uuid;
begin
  select mvp_user_id into v_mvp from match_results where match_id = p_match_id;
  if not found then return; end if;

  if not (v_mvp = any(p_user_ids)) then
    raise exception 'RESULT_PARTICIPANT_REMOVED';
  end if;

  if exists (
    select 1 from match_goals g
    where g.match_id = p_match_id and not (g.user_id = any(p_user_ids))
  ) then
    raise exception 'RESULT_PARTICIPANT_REMOVED';
  end if;
end;
$$;

revoke execute on function public.assert_result_survives_lineup(uuid, uuid[])
  from anon, authenticated, public;

-- 3) Replacing a lineup, with the effects that follow from it -------------------
-- `0020`'s function, with the recalculation around it. Everything that made it
-- what it is stays: `security definer` with its own `is_match_community_admin`
-- check, the match taken from the argument rather than the payload, a single
-- transaction, and an empty payload meaning a lineup of nobody rather than a
-- no-op.
--
-- The match row is locked first. `record_match_result` takes the same lock, so
-- two admins — one correcting the score, one moving a player — cannot interleave
-- a reversal and an application between them.
create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' then
    v_user_ids := array[]::uuid[];
  else
    select coalesce(array_agg((a->>'user_id')::uuid), array[]::uuid[])
      into v_user_ids
      from jsonb_array_elements(p_assignments) as a;
  end if;

  -- Refused before anything is written, so a rejected edit leaves the stored
  -- lineup and its effects exactly as they were.
  perform assert_result_survives_lineup(p_match_id, v_user_ids);

  perform detach_match_effects(p_match_id);

  delete from match_team_assignments where match_id = p_match_id;

  -- Clearing a lineup is a lineup of nobody, not a no-op: the delete above is
  -- the whole operation, and there is nothing to insert.
  if array_length(v_user_ids, 1) is not null then
    insert into match_team_assignments
      (match_id, user_id, team, assigned_position, assignment_basis)
    select
      p_match_id,
      (assignment->>'user_id')::uuid,
      assignment->>'team',
      assignment->>'assigned_position',
      assignment->>'assignment_basis'
    from jsonb_array_elements(p_assignments) as assignment;
  end if;

  perform attach_match_effects(p_match_id);
end;
$$;

revoke execute on function public.replace_match_lineup(uuid, jsonb)
  from anon, public;
grant execute on function public.replace_match_lineup(uuid, jsonb)
  to authenticated;

-- 4) Who played a match that has already been played ----------------------------
-- Adding a community member to a completed match, or taking one out of it.
--
-- Registration and the lineup move together here, and that is the point of a
-- single entry point. For a match still to come they are different things — a
-- seat is claimed by the player, a lineup is written by the organizer. For one
-- already played there is only the record of who was on the pitch, and a player
-- present in one but not the other would be a record that contradicts itself.
--
-- Deliberately restricted to completed matches. The roster of a live match is
-- governed by capacity, the reserve queue, the kickoff lock and the player's own
-- decision to join or withdraw, and none of that is this function's to override;
-- `register_for_match`, `withdraw_from_match` and `remove_player` remain the
-- only ways in and out of one.
--
-- [p_team] null removes the player. Anything else is an add or a move: `A` or
-- `B`, with the position they played. A move is the same call as an add, because
-- a lineup row is a statement about where somebody played and correcting it is
-- one operation.
--
-- The assignment basis is derived from the profile the same way §5.1 defines it,
-- rather than taken from the caller: it is the record of *which rule* produced
-- the position, so a caller-supplied one could mark a player out of position who
-- is playing where they always do.
create or replace function public.set_completed_match_player(
  p_match_id uuid,
  p_user_id uuid,
  p_team text default null,
  p_assigned_position text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_user users%rowtype;
  v_basis text;
  v_user_ids uuid[];
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
  end if;

  -- A match belongs to a community, and so does everyone who can have played
  -- in it. This is the same membership rule registration has always applied.
  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  -- The lineup as it will be, so the result's rule is asked of the outcome
  -- rather than of the step.
  select coalesce(array_agg(a.user_id), array[]::uuid[]) into v_user_ids
  from match_team_assignments a
  where a.match_id = p_match_id and a.user_id <> p_user_id;
  if p_team is not null then
    v_user_ids := v_user_ids || p_user_id;
  end if;

  perform assert_result_survives_lineup(p_match_id, v_user_ids);

  perform detach_match_effects(p_match_id);

  if p_team is null then
    delete from match_team_assignments
    where match_id = p_match_id and user_id = p_user_id;
    delete from match_registrations
    where match_id = p_match_id and user_id = p_user_id;
  else
    if p_team not in ('A', 'B') then raise exception 'INVALID_TEAM'; end if;
    if p_assigned_position is null
       or p_assigned_position not in ('GK', 'DEF', 'MID', 'FWD') then
      raise exception 'INVALID_POSITION';
    end if;

    select * into v_user from users where id = p_user_id;
    if not found then raise exception 'MEMBER_NOT_FOUND'; end if;

    v_basis := case
      when v_user.primary_position = p_assigned_position then 'PRIMARY'
      when v_user.secondary_position = p_assigned_position then 'SECONDARY'
      else 'TRANSITION'
    end;

    -- A played match has no reserve: everyone in the record played. The order
    -- continues the existing roster so the column keeps meaning what it means.
    if not exists (
      select 1 from match_registrations
      where match_id = p_match_id and user_id = p_user_id
    ) then
      select coalesce(max(registration_order), 0) + 1 into v_order
      from match_registrations where match_id = p_match_id;
      insert into match_registrations
        (match_id, user_id, status, registration_order)
      values (p_match_id, p_user_id, 'confirmed', v_order);
    else
      update match_registrations set status = 'confirmed'
      where match_id = p_match_id and user_id = p_user_id;
    end if;

    insert into match_team_assignments
      (match_id, user_id, team, assigned_position, assignment_basis)
    values (p_match_id, p_user_id, p_team, p_assigned_position, v_basis)
    on conflict (match_id, user_id) do update set
      team = excluded.team,
      assigned_position = excluded.assigned_position,
      assignment_basis = excluded.assignment_basis;
  end if;

  perform attach_match_effects(p_match_id);
end;
$$;

revoke execute on function public.set_completed_match_player(uuid, uuid, text,
  text) from anon, public;
grant execute on function public.set_completed_match_player(uuid, uuid, text,
  text) to authenticated;
