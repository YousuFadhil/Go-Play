-- ============ migrations/0033_public_discovery.sql ============
-- Sprint 1: Public Discovery Experience
--
-- Two approved changes, and deliberately nothing else. No table is dropped, no
-- column renamed, no existing policy altered, no business rule added. Three
-- existing functions are replaced in place; every other object here is new.
--
--   1) Guests can browse. Two read-only views expose the communities and the
--      upcoming matches a signed-out visitor is allowed to see, and nothing
--      more.
--
--   2) The MVP is optional. A result may be recorded without one; when it is,
--      no MVP rating is awarded and no MVP counter moves.
--
-- Idempotent: every statement is `create or replace`, `drop ... if exists` or
-- a guarded `alter`. Re-running it is a no-op.


-- ============================================================================
-- 1) What a guest may read
-- ============================================================================
-- The existing read models (`v_community_summary`, `v_upcoming_matches` from
-- `0025`) are `security_invoker = on`, so RLS applies to whoever selects from
-- them and a guest gets nothing back. That is correct for those views and is
-- not changed here.
--
-- These two are their public counterparts. They are deliberately NOT
-- `security_invoker`, so they execute with the privileges of the view owner and
-- the underlying policies do not filter them. That is the whole mechanism, and
-- it is why the column lists below matter more than usual: a view like this
-- exposes exactly what it selects, to exactly whoever is granted it.
--
-- Three things are therefore absent on purpose:
--
--   * `join_code`. It is the credential a CODE_REQUIRED community is joined
--     with. Publishing it beside the community's name would make the join
--     policy decorative — a guest could read the code off the Discover page and
--     walk into a community that requires one. The rule is unchanged; this is
--     what keeps it unchanged.
--
--   * `owner_id`, and every other user id. A guest browsing a list of clubs has
--     no business receiving the identifiers of the people in them. The counts
--     below are aggregates for exactly this reason: `member_count` says how big
--     a community is without saying who is in it.
--
--   * inactive communities. `is_active` is the project's soft delete, and a
--     deleted community is not discoverable.

-- Every community, which is the product decision this sprint rests on: the list
-- is not filtered by policy, by membership or by anything else. A CODE_REQUIRED
-- community appears here exactly as an OPEN one does — being listed is not being
-- joinable, and `join_community` still refuses without the code.
create or replace view public.v_public_communities as
select
  c.id,
  c.name,
  c.description,
  (
    select count(*)
    from public.community_members cm
    where cm.community_id = c.id
  )::int                                  as member_count,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and m.end_at > now()
      and m.status <> 'completed'
  )::int                                  as upcoming_match_count,
  c.created_at
from public.communities c
where c.is_active;

comment on view public.v_public_communities is
  'Public read model: every active community, with aggregate counts only. '
  'Readable without a session. Carries no join_code and no user ids by '
  'design -- see migration 0033.';

-- Matches that have not ended yet. `end_at` rather than `start_at` is what the
-- application already means by upcoming (`Match.effectiveStatus`), so a match
-- in progress is still shown rather than vanishing at kick-off.
--
-- `open_slots` is against `starting_players`, not `max_registration`, matching
-- what the match card has always shown: `max_registration` is the starting
-- eleven plus the global reserve allowance (DD-06), and offering it as
-- "remaining seats" would promise a six-a-side match twelve places.
create or replace view public.v_public_upcoming_matches as
select
  m.id,
  m.community_id,
  c.name                                  as community_name,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.starting_players,
  greatest(m.starting_players - coalesce(reg.confirmed_count, 0), 0)::int
                                          as open_slots
from public.matches m
join public.communities c on c.id = m.community_id
left join lateral (
  select count(*) filter (where r.status = 'confirmed') as confirmed_count
  from public.match_registrations r
  where r.match_id = m.id
) reg on true
where c.is_active
  and m.end_at > now()
  and m.status <> 'completed';

comment on view public.v_public_upcoming_matches is
  'Public read model: matches that have not ended, with remaining places. '
  'Readable without a session. Unordered by design -- the caller sorts.';

-- Read-only, to both roles. `anon` is the point of the exercise; `authenticated`
-- is granted the same views so the Discover screen is one query regardless of
-- whether anyone is signed in, rather than two that can drift apart.
grant select on public.v_public_communities       to anon, authenticated;
grant select on public.v_public_upcoming_matches  to anon, authenticated;


-- ============================================================================
-- 2) The MVP becomes optional
-- ============================================================================
-- Recording who was best on the pitch is worth doing and stays exactly as it
-- was. What changes is that a result no longer waits on it: an organizer with a
-- score and a set of goals can save, and name the MVP later or never.
--
-- The column is what said otherwise, so it is the column that changes.
alter table public.match_results
  alter column mvp_user_id drop not null;

comment on column public.match_results.mvp_user_id is
  'Best player, or null when the organizer did not name one. Null awards no '
  'MVP rating and moves no MVP counter -- see migration 0033.';

-- Everything downstream of the column was already null-safe, and is left alone:
--
--   * `apply_match_statistics` (0023) counts the MVP with
--     `case when a.user_id = v_result.mvp_user_id then 1 else 0 end`. A null
--     makes the WHEN unknown rather than true, so the CASE yields 0 and
--     `mvp_count` does not move.
--   * `rebuild_player_statistics` (0032) uses `count(*) filter (where ...)`,
--     which skips an unknown predicate for the same reason.
--   * `assert_result_survives_lineup` (0029) asks `if not (v_mvp = any(...))`.
--     With no MVP that test is unknown, the branch is not taken, and no
--     exception is raised -- which is the right answer: a result with no MVP has
--     no MVP to lose when the lineup changes.
--
-- Only the two that would have written a null are replaced.

-- `apply_match_rating_effects`, unchanged but for its last statement.
--
-- The approved constants are untouched: winner +0.10, loser -0.10, goal +0.05
-- each, MVP +0.20. The award is now conditional on there being someone to award
-- it to. Without the guard `apply_rating_delta` would be handed a null player
-- and would write a `rating_history` row for nobody.
create or replace function public.apply_match_rating_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result match_results%rowtype;
  r record;
begin
  select * into v_result from match_results where match_id = p_match_id;
  if not found then return; end if;

  -- Outcome first, then goals, then the MVP. Any order reaches the same rating;
  -- a fixed one makes the audit read the same way every time.
  if v_result.team_a_score <> v_result.team_b_score then
    for r in
      select a.user_id,
        case
          when (a.team = 'A' and v_result.team_a_score > v_result.team_b_score)
            or (a.team = 'B' and v_result.team_b_score > v_result.team_a_score)
          then 'WIN' else 'LOSS' end as outcome
      from match_team_assignments a
      where a.match_id = p_match_id
      order by a.team, a.user_id
    loop
      perform apply_rating_delta(
        r.user_id, p_match_id, r.outcome,
        case when r.outcome = 'WIN' then 0.10 else -0.10 end
      );
    end loop;
  end if;

  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', 0.05 * r.goals
    );
  end loop;

  -- No MVP, no MVP award. The absence of a rating change is what "do not award"
  -- means here, and it is also what makes a later correction exact: there is no
  -- entry to reverse, so naming an MVP afterwards is an ordinary re-record.
  if v_result.mvp_user_id is not null then
    perform apply_rating_delta(
      v_result.mvp_user_id, p_match_id, 'MVP', 0.20
    );
  end if;
end;
$$;

revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;

-- `record_match_result`, unchanged but for one validation.
--
-- MVP_NOT_PARTICIPANT still holds for anyone who *is* named: a best player has
-- to have played. What no longer holds is that somebody must be named. Every
-- other rule -- authorization, the score, the goals, the lineup, the scorers --
-- is exactly as it was, and is restated here only because `create or replace
-- function` replaces the whole body.
create or replace function public.record_match_result(
  p_match_id uuid,
  p_team_a_score int,
  p_team_b_score int,
  p_mvp_user_id uuid,
  p_goals jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participants int;
  v_total_goals int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  -- Management is a community role (PD-07, PD-16): the same predicate that gates
  -- the lineup gates its result. Who created the match is attribution.
  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_team_a_score < 0 or p_team_b_score < 0 then
    raise exception 'INVALID_SCORE';
  end if;

  -- Who played is the stored lineup. Without one there is no side for a player
  -- to have been on, so there is no winner to reward and no loser to charge —
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

  -- Two entries for one player is not a bigger number, it is the same fact
  -- recorded twice, and which of them counted would be arbitrary.
  if (
    select count(distinct e->>'user_id') from jsonb_array_elements(p_goals) as e
  ) <> jsonb_array_length(p_goals) then
    raise exception 'INVALID_GOALS';
  end if;

  select coalesce(sum((e->>'goals')::int), 0) into v_total_goals
  from jsonb_array_elements(p_goals) as e;

  if v_total_goals <> p_team_a_score + p_team_b_score then
    raise exception 'GOALS_DO_NOT_MATCH_SCORE';
  end if;

  -- Naming nobody is allowed; naming somebody who did not play is not. The
  -- check is skipped rather than weakened, so `MVP_NOT_PARTICIPANT` means what
  -- it always meant for every result that names one.
  if p_mvp_user_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id = p_mvp_user_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- A goal is credited to somebody who played it. Otherwise a rating could be
  -- raised for a player who was never in the match.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where not exists (
      select 1 from match_team_assignments a
      where a.match_id = p_match_id
        and a.user_id = (e->>'user_id')::uuid
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
    match_id, team_a_score, team_b_score, mvp_user_id, recorded_by
  )
  values (
    p_match_id, p_team_a_score, p_team_b_score, p_mvp_user_id, auth.uid()
  )
  on conflict (match_id) do update set
    team_a_score = excluded.team_a_score,
    team_b_score = excluded.team_b_score,
    mvp_user_id = excluded.mvp_user_id,
    recorded_by = excluded.recorded_by;

  insert into match_goals (match_id, user_id, goals)
  select p_match_id, (e->>'user_id')::uuid, (e->>'goals')::int
  from jsonb_array_elements(p_goals) as e;

  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;

revoke execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb) from anon, public;
grant execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb) to authenticated;
