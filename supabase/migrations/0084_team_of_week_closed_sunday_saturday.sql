-- ===== migrations/0084_team_of_week_closed_sunday_saturday.sql =====
-- The FINAL weekly Team of Period contract: Sunday to Saturday, and only the
-- week that has fully closed.
--
-- **This supersedes `0077` for Team of Period, and only for Team of Period.**
-- `0077` made Team of the Week the *running* ISO week (Monday to Sunday). Two
-- things about that are now decided differently by the Product Owner:
--
--   1. the football week here begins on **Sunday** and ends when the next
--      Sunday begins, so **Saturday is the last day of the week**;
--   2. the award is about the **last fully closed** week, never the running
--      one -- an XI that changes every time a result is recorded is not an
--      award.
--
-- The interval is half-open, as every period in this database is:
--
--     [ Sunday 00:00 Asia/Muscat , next Sunday 00:00 Asia/Muscat )
--
-- ## WHAT THIS DOES NOT TOUCH
--
-- **General weekly statistics keep their ISO Monday-to-Sunday buckets.**
-- `statistics_period_key`, `statistics_period_zone`,
-- `last_completed_statistics_period`, `current_statistics_week_at`,
-- `community_statistics`, `player_statistics`, the leaderboards and the
-- Community/Period Rating (`0081`) are not redefined by this migration and
-- behave exactly as before. This is the *award* contract, not the counters.
--
-- Monthly Team of Period is unchanged in every respect: still the last
-- completed calendar month, still resolved by
-- `last_completed_statistics_period('monthly')`.
--
-- The rating engine (`0078`), the rebase (`0082`) and every historical
-- migration are untouched. Append-only: nothing in `0022`-`0083` is edited.
--
-- ## THE PERIOD KEY STAYS `YYYY-W##`
--
-- The stored key shape does not change -- `team_of_period_snapshots`, the
-- achievement mapper and the profile cards all read `2026-W37`. What changes is
-- *which* Sunday-to-Saturday week a given key names. The key is derived from
-- the **Saturday that ends** the period, through the existing
-- `statistics_period_key`, so there is one week-numbering rule in the database
-- and this migration does not invent a second one:
--
--     Sunday 2026-09-06 .. Saturday 2026-09-12   ->  2026-W37
--     Sunday 2026-09-13 .. Saturday 2026-09-19   ->  2026-W38
--
-- That mapping is exactly invertible, which is what lets a key alone name a
-- canonical period: the ISO Monday of `2026-W37` is 2026-09-07, and the Sunday
-- before it is 2026-09-06.
--
-- ## WHY THE MATCH FILTER HAD TO CHANGE TOO
--
-- The old qualifying filter was `statistics_period_key(start_at, 'weekly') =
-- key`, which is an **ISO Monday-to-Sunday** test. Under the new contract that
-- is simply wrong: a Sunday match is the *first* day of the award week and ISO
-- puts it in the previous week -- Sunday 2026-09-06 keys as `2026-W36`. Moving
-- only `period_start`/`period_end` and leaving that filter would have produced
-- a window and an evidence set that disagreed with their own stated period. So
-- membership is now decided by the canonical bounds:
--
--     start_at >= period_start and start_at < period_end
--
-- and the window and the evidence consume that one function, so they cannot
-- count different matches.

-- ============================================================================
-- 1) The Team of Period week, in one place
-- ============================================================================
-- The Sunday-to-Saturday week containing `p_at`, on the Muscat wall clock.
--
-- `extract(dow)` is 0 on Sunday, so subtracting it from the truncated local day
-- lands on that week's Sunday for every day of the week, including Sunday
-- itself. Nothing here rounds or guesses: a day belongs to exactly one week and
-- every instant of Saturday still belongs to the running week.
create or replace function public.team_of_period_week_at(
  p_at timestamptz
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
declare
  v_zone text;
  v_local timestamp;
  v_sunday timestamp;
begin
  v_zone := public.statistics_period_zone();
  v_local := p_at at time zone v_zone;
  v_sunday := date_trunc('day', v_local)
                - (extract(dow from v_local))::int * interval '1 day';

  return query
  select
    'weekly'::text,
    -- Named after the Saturday that closes it, through the one key function
    -- this database has.
    public.statistics_period_key(
      (v_sunday + interval '6 days') at time zone v_zone, 'weekly'),
    v_sunday at time zone v_zone,
    (v_sunday + interval '7 days') at time zone v_zone;
end;
$$;

comment on function public.team_of_period_week_at(timestamptz) is
  'The Team of Period football week containing p_at: Sunday 00:00 Asia/Muscat '
  'to the next Sunday 00:00, half-open, keyed by the Saturday that ends it. '
  'The award week only -- general weekly statistics keep their ISO buckets. '
  'Internal to Team of Period -- see migration 0084.';

revoke execute on function public.team_of_period_week_at(timestamptz)
  from anon, authenticated, public;

-- The inverse: the canonical week a stored key names.
--
-- One rule, read backwards. `statistics_period_key` numbers a week by ISO, so
-- the ISO Monday of the key is the day after our Sunday -- which makes a key
-- enough to reconstruct the exact bounds, and means a caller that passes only a
-- key can still be held to canonical boundaries.
create or replace function public.team_of_period_week_of_key(
  p_period_key text
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
declare
  v_zone text;
  v_sunday timestamp;
begin
  if p_period_key is null or p_period_key !~ '^\d{4}-W\d{2}$' then
    raise exception 'INVALID_PERIOD_KEY';
  end if;

  v_zone := public.statistics_period_zone();
  -- The ISO Monday of that week, less one day.
  v_sunday := to_timestamp(p_period_key, 'IYYY-"W"IW')::timestamp
                - interval '1 day';

  return query
  select
    'weekly'::text,
    p_period_key,
    v_sunday at time zone v_zone,
    (v_sunday + interval '7 days') at time zone v_zone;
end;
$$;

comment on function public.team_of_period_week_of_key(text) is
  'The canonical Sunday-to-Saturday Team of Period week a YYYY-W## key names -- '
  'the inverse of the key derivation in team_of_period_week_at. Internal to '
  'Team of Period -- see migration 0084.';

revoke execute on function public.team_of_period_week_of_key(text)
  from anon, authenticated, public;

-- The last week that has fully closed.
--
-- One week before the week containing now(), which rolls over exactly once, at
-- Sunday 00:00: at any instant of Saturday the answer is still the week before
-- last Sunday, and one microsecond into Sunday it becomes the week that has
-- just ended.
create or replace function public.last_completed_team_of_period_week()
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz
)
language sql
stable
set search_path = public
as $$
  select w.period_type, w.period_key, w.period_start, w.period_end
  from public.team_of_period_week_at(now() - interval '7 days') w;
$$;

comment on function public.last_completed_team_of_period_week() is
  'The last FULLY CLOSED Team of Period week: Sunday to Saturday, Asia/Muscat, '
  'never the running week. The single weekly answer every Team of Period read '
  'path uses -- see migration 0084.';

revoke execute on function public.last_completed_team_of_period_week()
  from anon, authenticated, public;

-- ============================================================================
-- 2) The award period, weekly and monthly
-- ============================================================================
-- REPLACED (0084). `0077` answered weekly with the *running* ISO week; it now
-- answers with the last closed Sunday-to-Saturday week. Monthly is untouched
-- and still delegates to `last_completed_statistics_period`. `overall` is
-- refused with the token `0070` introduced.
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
    from public.last_completed_team_of_period_week() w;
  else
    return query
    select m.period_type, m.period_key, m.period_start, m.period_end
    from public.last_completed_statistics_period('monthly') m;
  end if;
end;
$$;

comment on function public.team_of_period_statistics_period(text) is
  'The period a Team of Period award describes: for weekly, the last CLOSED '
  'Sunday-to-Saturday week in Asia/Muscat -- never the running week; for '
  'monthly, the last COMPLETED calendar month, through '
  'last_completed_statistics_period exactly as before. overall is refused. '
  'Every Team of Period read path calls it, member-facing and service-role '
  'alike, so the screen and the snapshot cannot describe different periods -- '
  'see migration 0084, superseding 0077 for weekly.';

revoke execute on function public.team_of_period_statistics_period(text)
  from anon, authenticated, public;

-- The canonical bounds of a (period_type, period_key) pair.
--
-- Weekly reads them back from the key; monthly truncates the month the key
-- names, which is what it has always meant.
create or replace function public.team_of_period_period_bounds(
  p_period_type text,
  p_period_key text
)
returns table (period_start timestamptz, period_end timestamptz)
language plpgsql
stable
set search_path = public
as $$
declare
  v_zone text;
  v_month timestamp;
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  if p_period_type = 'weekly' then
    return query
    select w.period_start, w.period_end
    from public.team_of_period_week_of_key(p_period_key) w;
  else
    if p_period_key is null or p_period_key !~ '^\d{4}-\d{2}$' then
      raise exception 'INVALID_PERIOD_KEY';
    end if;
    v_zone := public.statistics_period_zone();
    v_month := to_timestamp(p_period_key, 'YYYY-MM')::timestamp;
    return query
    select
      v_month at time zone v_zone,
      (v_month + interval '1 month') at time zone v_zone;
  end if;
end;
$$;

comment on function public.team_of_period_period_bounds(text, text) is
  'The canonical half-open bounds of a Team of Period period named by its key. '
  'Internal -- see migration 0084.';

revoke execute on function public.team_of_period_period_bounds(text, text)
  from anon, authenticated, public;

-- ============================================================================
-- 3) Which matches a period is decided from
-- ============================================================================
-- NEW (0084). Membership by the canonical bounds, and nothing else.
create or replace function public.community_period_xi_matches_between(
  p_community_id uuid,
  p_period_start timestamptz,
  p_period_end timestamptz
)
returns table (match_id uuid, start_at timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  select c.match_id, c.start_at
  from v_completed_matches c
  join match_results r on r.match_id = c.match_id
  -- Isolation as well as filter: with RLS bypassed this is what keeps another
  -- community's football out of the answer entirely.
  where c.community_id = p_community_id
    -- Half-open, as every period in this database is: the instant a period
    -- ends is the first instant of the next one.
    and c.start_at >= p_period_start
    and c.start_at < p_period_end
    and exists (
      select 1 from match_team_assignments a
      where a.match_id = c.match_id and a.user_id is not null
    );
$$;

comment on function public.community_period_xi_matches_between(
  uuid, timestamptz, timestamptz
) is
  'The matches a Team of Period award is decided from, by canonical bounds: '
  'this community, start_at inside [period_start, period_end), completed, with '
  'a result, and with at least one real Go Play user on the stored lineup. A '
  'guest-only match is excluded entirely. Internal -- see migration 0084.';

revoke execute on function public.community_period_xi_matches_between(
  uuid, timestamptz, timestamptz)
  from anon, authenticated, public;

-- REPLACED (0084). The key-equality filter is gone: it was ISO Monday-based
-- and would have split a Sunday-to-Saturday award week on the wrong day. The
-- key still names the period, but the bounds decide membership.
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
  select m.match_id, m.start_at
  from public.team_of_period_period_bounds(p_period_type, p_period_key) b
  cross join lateral public.community_period_xi_matches_between(
    p_community_id, b.period_start, b.period_end) m;
$$;

revoke execute on function
  public.community_period_xi_matches_in(uuid, text, text)
  from anon, authenticated, public;

-- ============================================================================
-- 4) The service-role closed reads
-- ============================================================================
-- REPLACED (0084). Both pointed at `last_completed_statistics_period`, whose
-- weekly answer is the last completed ISO week. They now resolve the award
-- period through `team_of_period_statistics_period` -- **the same function the
-- member-facing Team of the Week screen calls** -- so the screen's period and
-- the snapshot's period are the same value by construction rather than by
-- coincidence. Monthly is unchanged: that function delegates to
-- `last_completed_statistics_period('monthly')`.
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
  from public.team_of_period_statistics_period(p_period_type) p
  cross join lateral public.community_period_xi_window_in(
    p_community_id, p.period_type, p.period_key, p.period_start, p.period_end
  ) r;
end;
$$;

comment on function public.community_period_xi_closed_window(uuid, text) is
  'Team of Period evidence for the period that has CLOSED -- the last closed '
  'Sunday-to-Saturday week, or the last completed calendar month, in '
  'Asia/Muscat -- for the service-role snapshot writer. Resolves that period '
  'through the same function the member-facing screen uses, so the two cannot '
  'differ. Evidence only, no selection. service_role only -- see migrations '
  '0079 and 0084.';

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
  from public.team_of_period_statistics_period(p_period_type) p
  cross join lateral public.community_period_xi_evidence_in(
    p_community_id, p.period_type, p.period_key, p.period_start, p.period_end
  ) r;
end;
$$;

comment on function public.community_period_xi_closed_evidence(uuid, text) is
  'The candidate rows for the period that has CLOSED -- the last closed '
  'Sunday-to-Saturday week, or the last completed calendar month -- resolved '
  'through the same function the member-facing screen uses. service_role only '
  '-- see migrations 0079 and 0084.';

revoke execute on function
  public.community_period_xi_closed_evidence(uuid, text)
  from anon, authenticated, public;
grant execute on function
  public.community_period_xi_closed_evidence(uuid, text) to service_role;

-- ============================================================================
-- 5) The writer's canonical-period validation
-- ============================================================================
-- REPLACED (0084). `0079` validated a weekly period against
-- `current_statistics_week_at` -- an ISO Monday-to-Sunday week -- and derived
-- the expected key with `statistics_period_key(period_start, 'weekly')`, which
-- on a Sunday start names the *previous* ISO week. Both are replaced by the
-- Team of Period week. **Nothing else in this function moves:** every error
-- token, every other invariant, the finality check, the inserts and the
-- privileges are `0079`'s, restated because `create or replace` replaces a
-- whole body.
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
  v_expected_key text;
  v_award_count int;
  v_snapshot_id uuid;
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  -- The period must be the canonical one, not merely a pair of instants.
  v_zone := public.statistics_period_zone();
  if p_period_type = 'weekly' then
    -- CHANGED (0084): the canonical Sunday-to-Saturday week, and its key.
    select w.period_start, w.period_end, w.period_key
      into v_expected_start, v_expected_end, v_expected_key
    from public.team_of_period_week_at(p_period_start) w;
  else
    v_expected_start :=
      date_trunc('month', p_period_start at time zone v_zone) at time zone v_zone;
    v_expected_end :=
      (date_trunc('month', p_period_start at time zone v_zone)
        + interval '1 month') at time zone v_zone;
    v_expected_key := public.statistics_period_key(p_period_start, 'monthly');
  end if;

  if p_period_start is distinct from v_expected_start
     or p_period_end is distinct from v_expected_end
     or p_period_key is distinct from v_expected_key then
    raise exception 'PERIOD_IDENTITY_MISMATCH';
  end if;

  -- Closed periods only. A running week's XI changes every time a result is
  -- recorded, so it is never stored.
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

  -- The selector's own invariants, restated as a consistency check: a team was
  -- chosen exactly when there are seats, and never more than eleven.
  if (p_state = 'SELECTED' and (v_award_count < 1 or v_award_count > 11))
     or (p_state <> 'SELECTED' and v_award_count <> 0)
     or v_award_count > coalesce(p_target_size, -1) then
    raise exception 'INVALID_SNAPSHOT_AWARDS';
  end if;

  if nullif(trim(coalesce(p_selector_version, '')), '') is null then
    raise exception 'INVALID_SELECTOR_VERSION';
  end if;

  -- Final once written. Checked before the insert for a stable error; the
  -- unique constraint is what guarantees it under concurrency.
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

comment on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) is
  'The only writer of Team of Period snapshots. service_role only. Accepts the '
  'existing TeamOfPeriodSelector result for a closed, canonical period -- a '
  'Sunday-to-Saturday week or a calendar month -- and refuses a second '
  'snapshot for the same period (SNAPSHOT_ALREADY_FINAL). See migrations 0079 '
  'and 0084.';

revoke execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) from anon, authenticated, public;
grant execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) to service_role;

-- ============================================================================
-- 6) Recent Achievements
-- ============================================================================
-- REPLACED (0084). `0081` asked `last_completed_statistics_period('weekly')`
-- which period a stored award had to match, and that is an ISO week: after this
-- migration a weekly snapshot is keyed by its Saturday, so the old question
-- would have named a week no award is ever stored under and Team of the Week
-- would never appear on a profile again. Monthly is unchanged, and so is
-- everything else about the contract: the latest MVP, every real selection in
-- the last closed week and month, every community, newest first, at most five,
-- and no fallback to an older award.
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
    -- CHANGED (0084): the weekly half is the last closed Sunday-to-Saturday
    -- Team of Period week, which is the period a weekly snapshot is stored
    -- under. The monthly half is the last completed calendar month, exactly as
    -- before.
    select w.period_type, w.period_key
    from public.last_completed_team_of_period_week() w
    union all
    select m.period_type, m.period_key
    from public.last_completed_statistics_period('monthly') m
  ),
  awards as (
    select
      'TEAM_OF_PERIOD'::text as achievement_type,
      -- The last instant of the period, as every Team of Period date is.
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
  -- Newest first; the rest of the order is only for display stability, so two
  -- reads of the same profile put the same cards in the same places.
  -- Qualified, because the function's own OUT parameters carry these names
  -- and an unqualified reference in a `language sql` body is ambiguous.
  order by all_achievements.occurred_at desc,
           all_achievements.achievement_type,
           all_achievements.community_name,
           all_achievements.community_id
  limit least(greatest(coalesce(p_limit, 5), 1), 10);
$$;

comment on function public.player_recent_achievements(uuid, int) is
  'A player''s recent achievements: their latest MVP, and every stored Team of '
  'Period award for the last closed Sunday-to-Saturday week and the last '
  'completed calendar month, one per community. Newest first, at most five. '
  'Never falls back to an older period -- see migrations 0081 and 0084.';

revoke execute on function public.player_recent_achievements(uuid, int)
  from anon, public;
grant execute on function public.player_recent_achievements(uuid, int)
  to authenticated;

-- `public_player_recent_achievements` is left exactly as `0081` wrote it: it
-- delegates to this function, so it follows the new weekly period without
-- being redefined, and its own public column list is unchanged.
