-- ============ migrations/0091_uat_stabilization_round1.sql ============
-- UAT stabilization, round 1.
--
-- Created with `supabase migration new uat_stabilization_round1` and renamed
-- from the CLI's timestamp to this repository's four-digit sequence, as 0089
-- and 0090 were.
--
-- Four database contracts, each backward-compatible with the currently
-- released client (staging and production share one Supabase project):
--
--   1. Meaningful activity: `profile_viewed` and `player_statistics_viewed`,
--      a nullable `product_events.target_user_id`, and an Admin timeline that
--      says who was viewed and what kind of thing was shared.
--   2. Retention as database logic only: one internal cleanup function and a
--      durable Last Seen. NOTHING IS SCHEDULED AND NOTHING IS EXECUTED HERE --
--      no pg_cron, no job, no call to the function.
--   3. Match lifecycle: a normal match may be created while ACTIVE, an
--      owner/admin may add a member to an ACTIVE match but never to a played
--      one, and a completed match with no result that is not historical may be
--      reopened as ACTIVE or FUTURE.
--   4. Nothing else. The recent-six, Discover, share-payload and
--      swap-positions changes are client-only: the existing RPCs already clamp
--      recent form to 10 and recent results to 20, and a position swap is one
--      `replace_match_lineup` write.
--
-- Append-only: no earlier migration is edited. No football history table is
-- altered or deleted from: matches, match_results, match_goals,
-- match_team_assignments, ratings, player/community statistics and Team of
-- Period awards/snapshots are untouched.


-- ============================================================================
-- 1) product_events -- who was viewed
-- ============================================================================
-- `target_user_id` names the player a view was about. Nullable, and every
-- existing row stays valid unchanged: no historical event is about a target.
--
-- **No foreign key to users**, for the rule 0067 set for this table: activity
-- must survive the account it mentions being deleted. No name or email is
-- snapshotted here either -- the Admin read LEFT JOINs `users` for the current
-- name and says "no longer available" when the account is gone.
alter table public.product_events
  add column if not exists target_user_id uuid;

comment on column public.product_events.target_user_id is
  'The player a profile_viewed or player_statistics_viewed was about (migration '
  '0091). No FK: the event survives that account being deleted. Null on every '
  'other event, which product_events_target_shape_check enforces.';

-- Fourteen names: 0089's twelve and the two views. Dropped and re-added
-- because a CHECK has no `or replace`.
alter table public.product_events
  drop constraint product_events_event_name_check;
alter table public.product_events
  add constraint product_events_event_name_check
    check (event_name in (
      'session_started',
      'community_viewed',
      'community_created',
      'community_joined',
      'match_viewed',
      'match_registered',
      'match_withdrawn',
      'teams_viewed',
      'result_viewed',
      'share_used',
      'public_link_opened',
      'public_link_signup_completed',
      'profile_viewed',
      'player_statistics_viewed'
    ));

-- A view is always about somebody, and nothing else is about anybody.
alter table public.product_events
  drop constraint if exists product_events_target_shape_check;
alter table public.product_events
  add constraint product_events_target_shape_check
    check (
      (
        event_name in ('profile_viewed', 'player_statistics_viewed')
        and target_user_id is not null
      )
      or (
        event_name not in ('profile_viewed', 'player_statistics_viewed')
        and target_user_id is null
      )
    );


-- --- 1b) record_product_event -- one more defaulted parameter ----------------
-- Dropped and recreated rather than overloaded: a second signature would make
-- every named-argument call ambiguous (PGRST203), in the one path the client
-- swallows every error from. `p_target_user_id` is defaulted, so the released
-- client's seven named arguments resolve to this function unchanged.
--
-- The actor is still `auth.uid()` and never an argument; a suspended account
-- still records nothing; `anon` still has no execute. A signed-out public
-- profile arrival stays with Wave 3's anonymous writer and is never assigned
-- to an account here.
drop function if exists public.record_product_event(
  text, uuid, uuid, text, text, text, text
);

create or replace function public.record_product_event(
  p_event_name text,
  p_community_id uuid default null,
  p_match_id uuid default null,
  p_platform text default null,
  p_app_version text default null,
  p_share_type text default null,
  p_source text default null,
  p_target_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- `public_link_signup_completed` is deliberately absent: it has its own
  -- writer (0089) and this function must never be able to write it.
  if p_event_name is null or p_event_name not in (
    'session_started',
    'community_viewed',
    'community_created',
    'community_joined',
    'match_viewed',
    'match_registered',
    'match_withdrawn',
    'teams_viewed',
    'result_viewed',
    'share_used',
    'public_link_opened',
    'profile_viewed',
    'player_statistics_viewed'
  ) then
    raise exception 'INVALID_ANALYTICS_EVENT';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  if p_share_type is not null and p_share_type not in (
    'player_profile',
    'player_statistics',
    'community',
    'match',
    'lineup',
    'result'
  ) then
    raise exception 'INVALID_ANALYTICS_SHARE_TYPE';
  end if;

  -- NEW (0091): restated from product_events_target_shape_check so a
  -- malformed call arrives as a stable token rather than a raw violation.
  if p_event_name in ('profile_viewed', 'player_statistics_viewed') then
    if p_target_user_id is null then
      raise exception 'INVALID_ANALYTICS_TARGET';
    end if;
  elsif p_target_user_id is not null then
    raise exception 'INVALID_ANALYTICS_TARGET';
  end if;

  insert into product_events (
    user_id, event_name, community_id, match_id, platform, app_version,
    share_type, source, target_user_id
  )
  values (
    v_user_id,
    p_event_name,
    p_community_id,
    p_match_id,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), ''),
    p_share_type,
    nullif(left(trim(coalesce(p_source, '')), 64), ''),
    p_target_user_id
  );
end;
$$;

comment on function public.record_product_event(
  text, uuid, uuid, text, text, text, text, uuid
) is
  'The authenticated writer for product_events (migrations 0067, 0079, 0091). '
  'Records the event against auth.uid() -- there is deliberately no actor '
  'argument -- after checking that the caller is signed in, active, and naming '
  'an approved event, platform, share type and target shape. p_target_user_id '
  'is required for profile_viewed and player_statistics_viewed and refused '
  'otherwise. Raises NOT_AUTHENTICATED, ACCOUNT_SUSPENDED, '
  'INVALID_ANALYTICS_EVENT, INVALID_ANALYTICS_PLATFORM, '
  'INVALID_ANALYTICS_SHARE_TYPE or INVALID_ANALYTICS_TARGET; the client '
  'swallows all six, because analytics never blocks a product flow.';

-- The drop took the ACL with it; restated in full.
revoke execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text, uuid)
  from anon, public;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text, uuid)
  to authenticated;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text, uuid)
  to service_role;


-- --- 1c) admin_user_activity_timeline -- what actually happened -------------
-- Four more columns, appended after 0068's eight so a positional reader is
-- unaffected and the released client simply ignores them:
--
--   target_user_id    who a view was about;
--   target_user_name  their CURRENT name, LEFT JOINed -- null once the account
--                     is gone, and the event still stands;
--   share_type        what a share_used shared (0079);
--   source            where it came from (0079).
--
-- No metadata JSON is exposed; product_events has none. A new return type
-- cannot be `create or replace`d, so the function is dropped and recreated
-- with the same arguments and its privileges restated.
drop function if exists public.admin_user_activity_timeline(uuid, integer);

create or replace function public.admin_user_activity_timeline(
  p_user_id uuid,
  p_limit integer default 50
)
returns table (
  event_name text,
  community_id uuid,
  community_name text,
  match_id uuid,
  match_title text,
  platform text,
  app_version text,
  created_at timestamptz,
  target_user_id uuid,
  target_user_name text,
  share_type text,
  source text
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit integer;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if not exists (select 1 from users u where u.id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);

  -- Every join is LEFT (0068): deleted context leaves the event standing with a
  -- null label rather than removing it from the history.
  return query
    select pe.event_name,
           pe.community_id,
           c.name,
           pe.match_id,
           m.title,
           pe.platform,
           pe.app_version,
           pe.created_at,
           pe.target_user_id,
           tu.full_name,
           pe.share_type,
           pe.source
    from product_events pe
    left join communities c on c.id = pe.community_id
    left join matches m on m.id = pe.match_id
    left join users tu on tu.id = pe.target_user_id
    where pe.user_id = p_user_id
    order by pe.created_at desc
    limit v_limit;
end;
$$;

comment on function public.admin_user_activity_timeline(uuid, integer) is
  'Platform Admin: one account''s recent activity, newest first (migrations '
  '0068, 0091). Gated on is_system_admin() as the first executable statement; '
  'USER_NOT_FOUND for an unknown id. p_limit is clamped to 1..100. Returns the '
  'viewed player (target_user_id and their current name), share_type and '
  'source. Every context join is LEFT: a deleted community, match or target '
  'leaves the event with a null label. No metadata JSON is returned.';

revoke execute on function public.admin_user_activity_timeline(uuid, integer)
  from anon, public;
grant execute on function public.admin_user_activity_timeline(uuid, integer)
  to authenticated;
grant execute on function public.admin_user_activity_timeline(uuid, integer)
  to service_role;


-- ============================================================================
-- 2) Retention -- database logic only
-- ============================================================================
-- --- 2a) A durable Last Seen --------------------------------------------------
-- Last Seen has been `max(product_events.created_at)` (0068). Once raw events
-- are kept for twelve months, an account idle for longer would lose its Last
-- Seen and read as never observed, which would be false.
--
-- The smallest mechanism that keeps it: one row per account holding the newest
-- `created_at` of the events the cleanup is about to delete. It is written only
-- by the cleanup function, just before its delete, and read as
-- `greatest(max(live events), rollup)` -- `greatest` ignores null, and every
-- live event is newer than anything rolled up, so the answer is exactly what it
-- would have been with no retention at all.
--
-- It is not a second activity log: a timestamp per account, no event name, no
-- context, no platform. No FK to users, for product_events' own reason.
create table if not exists public.product_activity_last_seen (
  user_id uuid primary key,
  last_seen_at timestamptz not null
);

comment on table public.product_activity_last_seen is
  'Migration 0091: the newest product_events.created_at per account among '
  'events removed by retention, so Last Seen survives the 12-month window. '
  'One timestamp per account, written only by run_retention_cleanup_v1. No FK. '
  'Not an activity log.';

-- The product_events posture: RLS on, no policy, no client privilege.
-- Supabase's default privileges grant ALL on a new table before these run.
alter table public.product_activity_last_seen enable row level security;
revoke all on table public.product_activity_last_seen
  from anon, authenticated, public;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.product_activity_last_seen
  from anon, authenticated, public;
revoke all on table public.product_activity_last_seen from service_role;
grant select on table public.product_activity_last_seen to service_role;


-- --- 2b) The one cleanup function ---------------------------------------------
-- Deletes rows older than the approved retention of each operational log, and
-- nothing else. The cutoffs are constants of this function, all measured from
-- one `now()` -- the transaction's start time -- so one run applies one
-- consistent boundary and no caller can move it.
--
--   product_events                 12 months  (created_at)
--   client_runtime_events          90 days    (occurred_at)
--   push_dispatch_outcomes         90 days    (occurred_at)
--   notifications                  90 days    (created_at)
--   match_registration_events      24 months  (occurred_at)
--   community_membership_events    24 months  (occurred_at)
--   admin_audit_log                24 months  (created_at)
--   btge_generation_runs           12 months  (generated_at)
--   telemetry_ingest_windows        1 day     (minute_bucket)
--
-- **Football history is not here and never will be.** matches, match_results,
-- match_goals, match_team_assignments, ratings, player/community statistics
-- and Team of Period awards/snapshots are the product's record, not logs.
--
-- **Not executed and not scheduled.** This migration only defines it. pg_cron
-- is not enabled on the project and nothing here enables it or schedules a
-- job; activation is a separate environment decision after UAT.
--
-- `security definer` because the evidence tables deliberately grant no role a
-- DELETE (0088, 0089, 0090): this function is the only delete path, and only
-- service_role (and the owner) may execute it. No dynamic SQL, no external
-- call, an empty search_path and schema-qualified names throughout.
--
-- ## Indexes
--
-- Inspected per table; none is added.
--
--   * push_dispatch_outcomes (occurred_at desc) and admin_audit_log
--     (created_at desc) serve their predicates directly.
--   * telemetry_ingest_windows is bounded to about 4,300 rows (three channels
--     times a day of minutes) and already pruned this way by 0090.
--   * product_events, client_runtime_events, notifications, the two Wave 2
--     logs and btge_generation_runs have the timestamp only as a second
--     column of their access-path indexes. A sequential scan by an off-peak
--     service job over MVP-scale tables is cheap, while a new index would tax
--     every insert on product_events and client_runtime_events -- the two
--     hottest write paths -- for a query that runs once a day at most. Revisit
--     if a run's duration says otherwise.
create or replace function public.run_retention_cleanup_v1()
returns table (
  table_name text,
  cutoff timestamptz,
  deleted_rows bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_product_events_cutoff timestamptz := v_now - interval '12 months';
  v_client_runtime_cutoff timestamptz := v_now - interval '90 days';
  v_push_outcomes_cutoff timestamptz := v_now - interval '90 days';
  v_notifications_cutoff timestamptz := v_now - interval '90 days';
  v_registration_events_cutoff timestamptz := v_now - interval '24 months';
  v_membership_events_cutoff timestamptz := v_now - interval '24 months';
  v_admin_audit_cutoff timestamptz := v_now - interval '24 months';
  v_btge_runs_cutoff timestamptz := v_now - interval '12 months';
  v_telemetry_windows_cutoff timestamptz := v_now - interval '1 day';
  v_count bigint;
begin
  -- Last Seen first, in the same transaction as the delete it protects.
  insert into public.product_activity_last_seen as s (user_id, last_seen_at)
  select pe.user_id, max(pe.created_at)
  from public.product_events pe
  where pe.user_id is not null
    and pe.created_at < v_product_events_cutoff
  group by pe.user_id
  on conflict (user_id) do update
    set last_seen_at = greatest(s.last_seen_at, excluded.last_seen_at);

  delete from public.product_events pe
  where pe.created_at < v_product_events_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'product_events';
  cutoff := v_product_events_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.client_runtime_events e
  where e.occurred_at < v_client_runtime_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'client_runtime_events';
  cutoff := v_client_runtime_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.push_dispatch_outcomes o
  where o.occurred_at < v_push_outcomes_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'push_dispatch_outcomes';
  cutoff := v_push_outcomes_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.notifications n
  where n.created_at < v_notifications_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'notifications';
  cutoff := v_notifications_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.match_registration_events e
  where e.occurred_at < v_registration_events_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'match_registration_events';
  cutoff := v_registration_events_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.community_membership_events e
  where e.occurred_at < v_membership_events_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'community_membership_events';
  cutoff := v_membership_events_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.admin_audit_log a
  where a.created_at < v_admin_audit_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'admin_audit_log';
  cutoff := v_admin_audit_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.btge_generation_runs r
  where r.generated_at < v_btge_runs_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'btge_generation_runs';
  cutoff := v_btge_runs_cutoff;
  deleted_rows := v_count;
  return next;

  delete from public.telemetry_ingest_windows t
  where t.minute_bucket < v_telemetry_windows_cutoff;
  get diagnostics v_count = row_count;
  table_name := 'telemetry_ingest_windows';
  cutoff := v_telemetry_windows_cutoff;
  deleted_rows := v_count;
  return next;
end;
$$;

comment on function public.run_retention_cleanup_v1() is
  'Migration 0091: internal retention cleanup. Deletes rows older than the '
  'approved windows -- product_events 12 months, client_runtime_events 90 '
  'days, push_dispatch_outcomes 90 days, notifications 90 days, '
  'match_registration_events 24 months, community_membership_events 24 '
  'months, admin_audit_log 24 months, btge_generation_runs 12 months, '
  'telemetry_ingest_windows 1 day -- all measured from one now(). Rolls Last '
  'Seen into product_activity_last_seen before deleting product_events. Never '
  'touches football history. Returns one row per table. Service role only; '
  'not scheduled by any migration.';

revoke execute on function public.run_retention_cleanup_v1()
  from public, anon, authenticated;
grant execute on function public.run_retention_cleanup_v1()
  to service_role;


-- --- 2c) Last Seen reads through the rollup ---------------------------------
-- The two Admin readers of Last Seen, each with that one expression changed
-- and nothing else. Same signatures and return types, so `create or replace`;
-- privileges restated anyway.
--
-- Sessions, active days, registrations, withdrawals, platforms and app version
-- stay RETAINED-window figures from the live events: the summary no longer
-- presents them as lifetime history, and the client labels them so.
create or replace function public.admin_user_activity_summary(
  p_user_id uuid
)
returns table (
  user_id uuid,
  full_name text,
  email text,
  created_at timestamptz,
  is_active boolean,
  suspended_at timestamptz,
  suspension_reason text,
  last_seen_at timestamptz,
  active_days_7d bigint,
  active_days_30d bigint,
  sessions_total bigint,
  platforms text[],
  latest_app_version text,
  community_count bigint,
  tracked_registrations bigint,
  matches_played integer,
  tracked_withdrawals bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_zone text;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if not exists (select 1 from users u where u.id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_zone := statistics_period_zone();

  return query
  with events as (
    select pe.event_name, pe.created_at, pe.platform, pe.app_version
    from product_events pe
    where pe.user_id = p_user_id
  )
  select
    u.id,
    u.full_name,
    au.email::text,
    u.created_at,
    u.is_active,
    u.suspended_at,
    u.suspension_reason,

    -- CHANGED (0091): durable across retention. Null only when the product
    -- has never observed this account.
    greatest(
      (select max(e.created_at) from events e),
      (select ls.last_seen_at from product_activity_last_seen ls
        where ls.user_id = p_user_id)
    ),

    (select count(distinct (e.created_at at time zone v_zone)::date)
       from events e
      where e.event_name = 'session_started'
        and e.created_at >= now() - interval '7 days'),
    (select count(distinct (e.created_at at time zone v_zone)::date)
       from events e
      where e.event_name = 'session_started'
        and e.created_at >= now() - interval '30 days'),

    -- Retained sessions: the live events only.
    (select count(*) from events e
      where e.event_name = 'session_started'),

    (select coalesce(array_agg(distinct e.platform order by e.platform),
                     array[]::text[])
       from events e
      where e.platform is not null),

    (select e.app_version from events e
      where e.app_version is not null
      order by e.created_at desc
      limit 1),

    (select count(*) from community_members cm
      where cm.user_id = p_user_id),

    (select count(*) from events e
      where e.event_name = 'match_registered'),

    coalesce(
      (select ps.matches_played from player_statistics ps
        where ps.user_id = p_user_id),
      0
    ),

    (select count(*) from events e
      where e.event_name = 'match_withdrawn')

  from users u
  join auth.users au on au.id = u.id
  where u.id = p_user_id;
end;
$$;

comment on function public.admin_user_activity_summary(uuid) is
  'Platform Admin: one account in figures (migrations 0068, 0091). Gated on '
  'is_system_admin() as the first executable statement; USER_NOT_FOUND for an '
  'id with no users row. Last Seen is the newest observed product event, '
  'durable across retention through product_activity_last_seen -- '
  'auth.last_sign_in_at is never read. Sessions, active days, registrations, '
  'withdrawals, platforms and app version are RETAINED-window figures (product '
  'events are kept 12 months), not lifetime history. Matches Played reads '
  'player_statistics directly. Reads auth.users for the email only.';

revoke execute on function public.admin_user_activity_summary(uuid)
  from anon, public;
grant execute on function public.admin_user_activity_summary(uuid)
  to authenticated;
grant execute on function public.admin_user_activity_summary(uuid)
  to service_role;


create or replace function public.admin_analytics_users_v2(
  p_metric text,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  full_name text,
  email text,
  created_at timestamptz,
  is_active boolean,
  is_system_admin boolean,
  last_seen_at timestamptz,
  returned_in_current_week boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit integer;
  v_offset integer;
  v_day_start timestamptz;
  v_current_7d_start timestamptz;
  v_previous_7d_start timestamptz;
  v_30d_start timestamptz;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if p_metric is null or p_metric not in (
    'total_users', 'new_users_today', 'new_users_7d', 'new_users_30d',
    'dau', 'wau', 'mau', 'weekly_retention'
  ) then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_day_start :=
    date_trunc('day', now() at time zone statistics_period_zone())
      at time zone statistics_period_zone();
  v_current_7d_start := v_day_start - interval '6 days';
  v_previous_7d_start := v_day_start - interval '13 days';
  v_30d_start := v_day_start - interval '29 days';

  return query
  with
    sessions as (
      select pe.user_id, pe.created_at
      from product_events pe
      where pe.event_name = 'session_started'
        and pe.created_at >= v_30d_start
    ),
    previous_week as (
      select s.user_id, max(s.created_at) as last_at
      from sessions s
      where s.created_at >= v_previous_7d_start
        and s.created_at < v_current_7d_start
      group by s.user_id
    ),
    target as (
      select u.id as user_id, u.created_at as sort_at, null::boolean as returned
      from users u
      where p_metric = 'total_users'

      union all
      select u.id, u.created_at, null::boolean
      from users u
      where p_metric = 'new_users_today'
        and u.created_at >= v_day_start

      union all
      select u.id, u.created_at, null::boolean
      from users u
      where p_metric = 'new_users_7d'
        and u.created_at >= v_current_7d_start

      union all
      select u.id, u.created_at, null::boolean
      from users u
      where p_metric = 'new_users_30d'
        and u.created_at >= v_30d_start

      union all
      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'dau'
        and s.created_at >= v_day_start
      group by s.user_id

      union all
      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'wau'
        and s.created_at >= v_current_7d_start
      group by s.user_id

      union all
      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'mau'
      group by s.user_id

      union all
      select p.user_id,
             p.last_at,
             exists (
               select 1
               from sessions s
               where s.user_id = p.user_id
                 and s.created_at >= v_current_7d_start
             )
      from previous_week p
      where p_metric = 'weekly_retention'
    )
  select
    t.user_id,
    u.full_name,
    au.email::text,
    u.created_at,
    u.is_active,
    case when u.id is null then null::boolean
         else exists (select 1 from system_admins sa where sa.user_id = u.id)
    end,
    -- CHANGED (0091): durable across retention, as in the summary.
    greatest(
      (select max(pe.created_at)
         from product_events pe
         where pe.user_id = t.user_id),
      (select ls.last_seen_at
         from product_activity_last_seen ls
         where ls.user_id = t.user_id)
    ),
    t.returned
  from target t
  left join users u on u.id = t.user_id
  left join auth.users au on au.id = t.user_id
  order by t.sort_at desc nulls last, t.user_id
  limit v_limit offset v_offset;
end;
$$;

revoke execute on function public.admin_analytics_users_v2(text, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_users_v2(text, integer, integer)
  to authenticated, service_role;


-- ============================================================================
-- 3) Match lifecycle
-- ============================================================================
-- The lifecycle is still read from time, and the stored status model is still
-- open / full / completed -- no status is added:
--
--   FUTURE     start_at > now()
--   ACTIVE     start_at <= now() < end_at, and not completed
--   COMPLETED  status = 'completed' OR end_at <= now()
--
-- --- 3a) create_match -- a normal match may already be ACTIVE ---------------
-- 0065's body with one statement changed. A normal match may be FUTURE or
-- ACTIVE; one that has wholly ended is refused with MATCH_ALREADY_ENDED and
-- belongs on the historical path, which is unchanged: p_is_historical => true,
-- end_at already past, never registrable.
create or replace function public.create_match(
  p_community_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players integer,
  p_description text default null,
  p_is_historical boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
  v_match_id uuid;
  v_historical boolean := coalesce(p_is_historical, false);
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_community from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if not v_community.is_active then raise exception 'COMMUNITY_INACTIVE'; end if;

  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_location is null or char_length(trim(p_location)) < 2 then
    raise exception 'INVALID_LOCATION';
  end if;
  if p_start_at is null or p_end_at is null then
    raise exception 'INVALID_TIME_RANGE';
  end if;

  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;

  if v_historical then
    if p_end_at > now() then raise exception 'HISTORICAL_NOT_PAST'; end if;
  else
    -- CHANGED (0091): was `p_start_at <= now()` -> START_IN_PAST. A fixture
    -- that is already under way is an ACTIVE match and may be created; one
    -- that has wholly ended is a record of the past and is refused here.
    if p_end_at <= now() then raise exception 'MATCH_ALREADY_ENDED'; end if;
  end if;

  if p_starting_players is null
     or p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  insert into matches (
    community_id, created_by, title, location,
    start_at, end_at, starting_players, description, is_historical
  )
  values (
    p_community_id,
    auth.uid(),
    trim(p_title),
    trim(p_location),
    p_start_at,
    p_end_at,
    p_starting_players,
    case
      when p_description is null or trim(p_description) = '' then null
      else trim(p_description)
    end,
    v_historical
  )
  returning id into v_match_id;

  if not v_historical then
    perform create_notification(
        cm.user_id,
        v_match_id,
        'match_created',
        trim(p_title) || ' — ' || trim(p_location)
    )
    from community_members cm
    where cm.community_id = p_community_id
      and cm.user_id <> auth.uid();
  end if;

  return v_match_id;
end;
$$;

revoke execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text, boolean
) from anon, public;
grant execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text, boolean
) to authenticated;


-- --- 3b) register_player_in_match -- one registration transaction -----------
-- 0065's body with one statement moved. `p_enforce_time_lock` now governs only
-- the KICKOFF lock, which is the self-registration rule. A PLAYED match
-- (completed or ended) refuses a new registration from every caller:
--
--   register_for_match (self)      FUTURE only; ACTIVE -> MATCH_LOCKED,
--                                  played -> MATCH_CLOSED       (unchanged)
--   admin_add_player_to_match      FUTURE or ACTIVE; played -> MATCH_CLOSED
--                                  (was: allowed after the end)
--   either, historical             MATCH_HISTORICAL             (unchanged)
--
-- Authentication and the owner/admin check stay in the two wrappers, which are
-- untouched. Membership, duplicate prevention, capacity, the overlap rule and
-- the ordering below are unchanged, so both paths still share one source of
-- truth.
--
-- Reconcile the historical helper drift before defining the canonical helper.
-- Migration 0041 created a two-argument version; later migrations moved both
-- wrappers to the three-argument version below. The old overload has no caller
-- or dependency and keeping it would leave two public-schema functions with
-- the same RPC name.
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

  if not exists (
    select 1 from communities c
    where c.id = v_match.community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;
  if not exists (
    select 1 from users u
    where u.id = p_user_id and u.is_active
  ) then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  if v_match.is_historical then raise exception 'MATCH_HISTORICAL'; end if;

  -- CHANGED (0091): outside the flag. Nobody registers into a played match;
  -- who played is then corrected through the completed-match paths.
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  -- The kickoff lock is the self-registration rule. An owner/admin add
  -- (p_enforce_time_lock => false) may still place a member in an ACTIVE match.
  if p_enforce_time_lock and v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;
  if exists (select 1 from match_registrations
             where match_id = p_match_id and user_id = p_user_id) then
    raise exception 'ALREADY_REGISTERED';
  end if;
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
  if v_match.roster_order_mode = 'manual' then
    v_status := case when v_total + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  else
    select count(*) into v_community
    from match_registrations
    where match_id = p_match_id and user_id is not null;
    v_status := case when v_community + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  end if;
  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;
  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);
  perform rebalance_roster(p_match_id);
  select status into v_status from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

-- Unchanged audience, restated: service_role only. Both wrappers reach it as
-- its owner.
revoke execute on function public.register_player_in_match(uuid, uuid, boolean)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid, boolean)
  to service_role;


-- --- 3c) update_match -- a completed match without a result may reopen -----
-- 0076's body with the COMPLETED branch of the guard relaxed:
--
--   FUTURE    -> FUTURE, ACTIVE, COMPLETED      allowed        (unchanged)
--   ACTIVE    -> ACTIVE, COMPLETED              allowed        (unchanged)
--   ACTIVE    -> FUTURE                         MATCH_LOCKED   (unchanged)
--   COMPLETED -> COMPLETED                      allowed        (unchanged)
--   COMPLETED -> ACTIVE or FUTURE               allowed ONLY when the match is
--                                               not historical and has no
--                                               match_results row; otherwise
--                                               MATCH_COMPLETED (unchanged)
--
-- A reopen changes the lifecycle and nothing else:
--
--   * registrations and the stored lineup are left exactly as they are --
--     no rebalance, no reconciliation, no regeneration;
--   * the stored status becomes open or full, by the count
--     recompute_match_status uses;
--   * the participation confirmation (0088) is cleared -- confirmed_revision,
--     confirmed_at, confirmed_by -- because it described a completed match;
--     lineup_revision is kept;
--   * ratings, statistics, goals and results are not touched: there is no
--     result, so no effect was ever attached, and nothing detaches or
--     reattaches one here.
--
-- After a reopen the ordinary rules resume: a FUTURE match opens to
-- registration by the existing rules; an ACTIVE match keeps self-registration
-- locked while an owner/admin may still add a member (3b).
--
-- `record_match_result` locks the same match row, so a result cannot land
-- between the no-result check below and the reopen.
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
  v_was_active boolean;
  v_becomes_completed boolean;
  v_becomes_active boolean;
  -- NEW (0091): a played match being returned to ACTIVE or FUTURE.
  v_reopening boolean := false;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  v_was_active := not v_played and v_match.start_at <= now();
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;

  v_becomes_completed := p_end_at <= now();
  v_becomes_active := not v_becomes_completed and p_start_at <= now();

  if v_played then
    if not v_becomes_completed then
      -- CHANGED (0091): a completed match may reopen only while it is not a
      -- historical record and has no result. A result is never reversed or
      -- deleted to make room for a reopen.
      if v_match.is_historical
         or exists (
           select 1 from match_results mr where mr.match_id = p_match_id
         )
      then
        raise exception 'MATCH_COMPLETED';
      end if;
      v_reopening := true;
    end if;
  elsif v_was_active then
    if not (v_becomes_completed or v_becomes_active) then
      raise exception 'MATCH_LOCKED';
    end if;
  end if;
  if p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  if not (v_becomes_completed or v_becomes_active) then
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
  if v_becomes_completed then
    update matches set status = 'completed'
    where id = p_match_id and status <> 'completed';
  -- NEW (0091): RESULTING ACTIVE OR FUTURE, FROM A PLAYED MATCH.
  elsif v_reopening then
    -- The count and the rule recompute_match_status uses, without the lineup
    -- reconciliation it would run next: a reopen preserves the lineup.
    -- max_registration has already followed starting_players through the
    -- matches_set_capacity trigger on the update above.
    select count(*) into v_total from match_registrations where match_id = p_match_id;
    update matches m
    set status = case when v_total >= m.max_registration
                      then 'full' else 'open' end
    where m.id = p_match_id;

    update match_participation_state
    set confirmed_revision = null,
        confirmed_at = null,
        confirmed_by = null
    where match_id = p_match_id
      and confirmed_revision is not null;
  elsif v_becomes_active then
    null;
  else
    perform rebalance_roster(p_match_id);
    perform recompute_match_status(p_match_id);
  end if;
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      trim(p_title))
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
  'Owner/admin match administration in every lifecycle state (migrations '
  '0074, 0076, 0091). An active match may not return to the future '
  '(MATCH_LOCKED). A completed match may be reopened as active or future only '
  'when it is not historical and has no match_results row; otherwise '
  'MATCH_COMPLETED. A reopen preserves registrations and the stored lineup, '
  'restores an open/full status, clears the participation confirmation and '
  'keeps lineup_revision; it never touches ratings, statistics, goals or '
  'results. starting_players must be 4..30; MAX_BELOW_REGISTERED applies only '
  'when the resulting state is future. A future result keeps the ordinary '
  'rebalance and status recomputation; an active or completed result does not.';


-- ============================================================================
-- 4) What this migration does not do
-- ============================================================================
--   * It does not run run_retention_cleanup_v1, enable pg_cron or schedule
--     anything. No row of any table is deleted by applying it.
--   * It adds no foreign key, and no index (see 2b).
--   * register_for_match, admin_add_player_to_match, record_match_result,
--     replace_match_lineup, save_generated_lineup_v1 and every read model are
--     unchanged.
--   * The anonymous public-link writers (0089, 0090) are unchanged: a
--     signed-out arrival is never assigned to an account.
