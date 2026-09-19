-- == rollback/0084_team_of_week_closed_sunday_saturday_rollback.sql ==
-- Puts the weekly Team of Period contract back to what it was before `0084`:
-- the RUNNING ISO week (Monday to Sunday) for the member-facing read, the last
-- completed ISO week for the snapshot reads, and the ISO key-equality match
-- filter.
--
-- **Nothing historical is edited.** `0077`, `0079` and `0081` stay exactly as
-- they were written; this file restates their current function bodies through
-- `create or replace`, which is the only way a forward-only migration history
-- can be undone.
--
-- Monthly behaviour is not mentioned anywhere below because `0084` did not
-- change it: it delegated to `last_completed_statistics_period('monthly')`
-- before and after, and still does.
--
-- Run the whole file in one transaction.

-- ============================================================================
-- 1) The award period: back to the running ISO week (0077)
-- ============================================================================
create or replace function public.team_of_period_statistics_period(
  p_period_type text
)
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz
)
language plpgsql
stable
set search_path = public
as $$
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  if p_period_type = 'weekly' then
    return query
    select w.period_type, w.period_key, w.period_start, w.period_end
    from public.current_statistics_week_at(now()) w;
  else
    return query
    select m.period_type, m.period_key, m.period_start, m.period_end
    from public.last_completed_statistics_period('monthly') m;
  end if;
end;
$$;

comment on function public.team_of_period_statistics_period(text) is
  'The period a Team of Period award describes: for weekly, the CURRENT ISO '
  'week in Asia/Muscat, resolved from now() on every read, so it rolls over on '
  'its own at Monday 00:00 and an empty week is still that week; for monthly, '
  'the last COMPLETED calendar month, through last_completed_statistics_period '
  'exactly as before. overall is refused. Both read paths call it so the '
  'window and the candidates always describe the same period -- see migration '
  '0077.';

revoke execute on function public.team_of_period_statistics_period(text)
  from anon, authenticated, public;

-- ============================================================================
-- 2) Match membership: back to ISO key equality (0079)
-- ============================================================================
create or replace function public.community_period_xi_matches_in(
  p_community_id uuid,
  p_period_type text,
  p_period_key text
)
returns table (match_id uuid, start_at timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  with period as (
    select p_period_key as period_key
  )
  select c.match_id, c.start_at
  from v_completed_matches c
  join match_results r on r.match_id = c.match_id
  cross join period pk
  where c.community_id = p_community_id
    and public.statistics_period_key(c.start_at, p_period_type) = pk.period_key
    and exists (
      select 1 from match_team_assignments a
      where a.match_id = c.match_id and a.user_id is not null
    );
$$;

revoke execute on function
  public.community_period_xi_matches_in(uuid, text, text)
  from anon, authenticated, public;

-- ============================================================================
-- 3) The closed reads: back to last_completed_statistics_period (0079)
-- ============================================================================
create or replace function public.community_period_xi_closed_window(
  p_community_id uuid,
  p_period_type text
)
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz,
  qualifying_match_count int,
  required_matches int,
  evidence_last_changed_at timestamptz,
  team_size_observations int[],
  position_shape_observations jsonb,
  position_shape jsonb
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  return query
  select r.*
  from public.last_completed_statistics_period(p_period_type) p
  cross join lateral public.community_period_xi_window_in(
    p_community_id, p.period_type, p.period_key, p.period_start, p.period_end
  ) r;
end;
$$;

comment on function public.community_period_xi_closed_window(uuid, text) is
  'Team of Period evidence for the period that has just CLOSED -- the last '
  'completed week or calendar month in Asia/Muscat -- for the service-role '
  'snapshot writer. Evidence only: the same rows the member-facing read '
  'returns for its period, and no selection. Callable by service_role only; '
  'reads nothing but the last closed period, so it cannot backfill -- see '
  'migration 0079.';

revoke execute on function public.community_period_xi_closed_window(uuid, text)
  from anon, authenticated, public;
grant execute on function public.community_period_xi_closed_window(uuid, text)
  to service_role;

create or replace function public.community_period_xi_closed_evidence(
  p_community_id uuid,
  p_period_type text
)
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz,
  qualifying_match_count int,
  required_matches int,
  matches_played int,
  participation_rate numeric,
  eligible boolean,
  wins int,
  draws int,
  losses int,
  goals int,
  goals_per_match numeric,
  mvp_count int,
  win_rate numeric,
  points_per_game numeric,
  period_form_score numeric,
  goal_form_contribution_total numeric,
  period_primary_position text,
  period_secondary_position text,
  position_appearances jsonb,
  position_basis_evidence jsonb,
  current_overall_rating numeric,
  user_id uuid
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  return query
  select r.*
  from public.last_completed_statistics_period(p_period_type) p
  cross join lateral public.community_period_xi_evidence_in(
    p_community_id, p.period_type, p.period_key, p.period_start, p.period_end
  ) r;
end;
$$;

revoke execute on function
  public.community_period_xi_closed_evidence(uuid, text)
  from anon, authenticated, public;
grant execute on function
  public.community_period_xi_closed_evidence(uuid, text) to service_role;

-- ============================================================================
-- 4) The writer: back to the ISO weekly validation (0079)
-- ============================================================================
create or replace function public.record_team_of_period_snapshot(
  p_community_id uuid,
  p_period_type text,
  p_period_key text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_state text,
  p_target_size int,
  p_evidence_last_changed_at timestamptz,
  p_selector_version text,
  p_awards jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone text;
  v_expected_start timestamptz;
  v_expected_end timestamptz;
  v_award_count int;
  v_snapshot_id uuid;
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  v_zone := public.statistics_period_zone();
  if p_period_type = 'weekly' then
    select w.period_start, w.period_end
      into v_expected_start, v_expected_end
    from public.current_statistics_week_at(p_period_start) w;
  else
    v_expected_start :=
      date_trunc('month', p_period_start at time zone v_zone) at time zone v_zone;
    v_expected_end :=
      (date_trunc('month', p_period_start at time zone v_zone)
        + interval '1 month') at time zone v_zone;
  end if;

  if p_period_start is distinct from v_expected_start
     or p_period_end is distinct from v_expected_end
     or p_period_key is distinct from
          public.statistics_period_key(p_period_start, p_period_type) then
    raise exception 'PERIOD_IDENTITY_MISMATCH';
  end if;

  if p_period_end > now() then
    raise exception 'PERIOD_NOT_CLOSED';
  end if;

  if not exists (select 1 from communities c where c.id = p_community_id) then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  if p_state is null or p_state not in (
    'SELECTED', 'NO_QUALIFYING_MATCHES', 'INSUFFICIENT_ELIGIBLE_PLAYERS'
  ) then
    raise exception 'INVALID_SNAPSHOT_STATE';
  end if;

  if p_awards is null or jsonb_typeof(p_awards) <> 'array' then
    raise exception 'INVALID_SNAPSHOT_AWARDS';
  end if;
  v_award_count := jsonb_array_length(p_awards);

  if (p_state = 'SELECTED' and (v_award_count < 1 or v_award_count > 11))
     or (p_state <> 'SELECTED' and v_award_count <> 0)
     or v_award_count > coalesce(p_target_size, -1) then
    raise exception 'INVALID_SNAPSHOT_AWARDS';
  end if;

  if nullif(trim(coalesce(p_selector_version, '')), '') is null then
    raise exception 'INVALID_SELECTOR_VERSION';
  end if;

  if exists (
    select 1 from team_of_period_snapshots s
    where s.community_id = p_community_id
      and s.period_type = p_period_type
      and s.period_key = p_period_key
  ) then
    raise exception 'SNAPSHOT_ALREADY_FINAL';
  end if;

  insert into team_of_period_snapshots (
    community_id, period_type, period_key, period_start, period_end,
    state, target_size, evidence_last_changed_at, selector_version
  )
  values (
    p_community_id, p_period_type, p_period_key, p_period_start, p_period_end,
    p_state, p_target_size, p_evidence_last_changed_at,
    left(trim(p_selector_version), 64)
  )
  returning id into v_snapshot_id;

  insert into team_of_period_awards (
    snapshot_id, user_id, assigned_position, rank_in_role
  )
  select v_snapshot_id, a.user_id, a.assigned_position, a.rank_in_role
  from jsonb_to_recordset(p_awards)
    as a(user_id uuid, assigned_position text, rank_in_role int);

  return v_snapshot_id;
end;
$$;

revoke execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) from anon, authenticated, public;
grant execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) to service_role;

-- ============================================================================
-- 5) Recent Achievements: back to the ISO weekly period (0081)
-- ============================================================================
create or replace function public.player_recent_achievements(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  achievement_type text,
  occurred_at timestamptz,
  community_id uuid,
  community_name text,
  period_type text,
  period_key text
)
language sql
security definer
stable
set search_path = public
as $$
  with mvp as (
    select
      'MVP'::text        as achievement_type,
      m.start_at         as occurred_at,
      m.community_id,
      c.name             as community_name,
      null::text         as period_type,
      null::text         as period_key
    from match_results r
    join matches m     on m.id = r.match_id
    join communities c on c.id = m.community_id and c.is_active
    where r.mvp_user_id = p_user_id
      and (m.status = 'completed' or m.end_at <= now())
    order by m.start_at desc, m.id desc
    limit 1
  ),
  closed as (
    select p.period_type, p.period_key
    from (values ('weekly'), ('monthly')) as t(period_type)
    cross join lateral public.last_completed_statistics_period(t.period_type) p
  ),
  awards as (
    select
      'TEAM_OF_PERIOD'::text as achievement_type,
      s.period_end - interval '1 millisecond' as occurred_at,
      s.community_id,
      c.name                 as community_name,
      s.period_type,
      s.period_key
    from team_of_period_awards a
    join team_of_period_snapshots s on s.id = a.snapshot_id
    join closed k
      on k.period_type = s.period_type and k.period_key = s.period_key
    join communities c on c.id = s.community_id and c.is_active
    where a.user_id = p_user_id
  )
  select * from (
    select * from mvp
    union all
    select * from awards
  ) all_achievements
  order by all_achievements.occurred_at desc,
           all_achievements.achievement_type,
           all_achievements.community_name,
           all_achievements.community_id
  limit least(greatest(coalesce(p_limit, 5), 1), 10);
$$;

revoke execute on function public.player_recent_achievements(uuid, int)
  from anon, public;
grant execute on function public.player_recent_achievements(uuid, int)
  to authenticated;

-- ============================================================================
-- 6) The helpers 0084 introduced
-- ============================================================================
-- Dropped last, because everything above stopped referring to them first.
drop function if exists public.community_period_xi_matches_between(
  uuid, timestamptz, timestamptz);
drop function if exists public.team_of_period_period_bounds(text, text);
drop function if exists public.last_completed_team_of_period_week();
drop function if exists public.team_of_period_week_of_key(text);
drop function if exists public.team_of_period_week_at(timestamptz);

-- Stored snapshots are NOT touched. A weekly snapshot written under `0084` is
-- keyed by its Saturday and describes a Sunday-to-Saturday period; after this
-- rollback the achievement query asks for ISO weeks again and simply will not
-- match it. The row is evidence of an award that was made and is left alone --
-- retiring one is a separate, deliberate act, exactly as it is for the rating
-- archive.
