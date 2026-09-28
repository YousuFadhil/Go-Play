-- ============ migrations/0090_wave4_operational_hardening.sql ============
-- Wave 4: Operational hardening.
--
-- Design authority: Docs/engineering/WAVE4_OPERATIONAL_HARDENING_DESIGN.md
-- (approved).
--
-- Minimal operational evidence where logs cannot answer the question, and a
-- circuit breaker for the intentionally public telemetry writers:
--
--   1. push_dispatch_outcomes + record_push_dispatch_outcome_v1
--      -- transport evidence for OI-05, written by the push-dispatch Edge
--         Function through the service role only.
--   2. telemetry_ingest_windows + consume_telemetry_budget_v1
--      -- a global, non-identifying minute-bucket ingest limiter.
--   3. client_runtime_events + start_client_runtime_v1 +
--      report_client_error_v1
--      -- production run starts and uncaught client errors for OI-06.
--   4. record_anonymous_public_link_open (Wave 3, same signature)
--      -- now consumes the acquisition_open budget before inserting.
--
-- What does not change:
--
--   * notifications stays the Notification Center truth; push outcomes are
--     transport evidence only and never read notification content.
--   * No business table, row or existing function other than
--     record_anonymous_public_link_open is modified.
--   * No historical backfill: every new table starts empty.
--
-- No evidence table carries a user id, email, phone, name, IP address, device
-- id, cookie, session or auth token, push token, notification text, raw
-- exception message or stack trace.


-- ============================================================================
-- 1) push_dispatch_outcomes -- what the push transport did, once per attempt
-- ============================================================================
-- One row per terminal outcome of one push-dispatch invocation.
--
-- **No foreign key to notifications.** Transport evidence must survive the
-- later deletion of the business row it describes (the 0067/0088/0089 rule).
--
-- OI-05 FCM Acceptance Rate = sent / (sent + stale + failed), over dispatched
-- rows only. The other outcomes attempted no FCM send and are reported beside
-- the rate, not inside its denominator.
create table public.push_dispatch_outcomes (
  attempt_no bigint generated always as identity primary key,
  notification_id uuid not null,
  occurred_at timestamptz not null default now(),
  outcome text not null
    constraint push_dispatch_outcomes_outcome_check
      check (outcome in (
        'not_found',
        'suppressed',
        'no_devices',
        'unrenderable',
        'dispatched',
        'internal_error'
      )),
  -- The registry's priorities (0036). Null when the dispatch never learned it.
  priority text
    constraint push_dispatch_outcomes_priority_check
      check (priority is null or priority in ('high', 'medium', 'low')),
  token_count integer not null default 0,
  sent_count integer not null default 0,
  stale_count integer not null default 0,
  failed_count integer not null default 0,
  constraint push_dispatch_outcomes_counts_nonnegative_check
    check (
      token_count >= 0
      and sent_count >= 0
      and stale_count >= 0
      and failed_count >= 0
    ),
  -- A dispatch sent to every device it had, and each device ended one way.
  -- Nothing else sent anything.
  constraint push_dispatch_outcomes_counts_shape_check
    check (
      case
        when outcome = 'dispatched' then
          token_count >= 1
          and token_count = sent_count + stale_count + failed_count
        else
          sent_count = 0 and stale_count = 0 and failed_count = 0
      end
    ),
  -- Nothing was loaded, or there was nothing to send to.
  constraint push_dispatch_outcomes_no_token_outcomes_check
    check (outcome not in ('not_found', 'no_devices') or token_count = 0)
);

create index push_dispatch_outcomes_time_idx
  on public.push_dispatch_outcomes (occurred_at desc);
create index push_dispatch_outcomes_notification_idx
  on public.push_dispatch_outcomes (notification_id);

comment on table public.push_dispatch_outcomes is
  'Wave 4 (migration 0090): append-only push transport evidence, one row per '
  'terminal push-dispatch outcome. Counts only: no token, message, user id or '
  'Firebase response. No FK to notifications. Written only by '
  'record_push_dispatch_outcome_v1 (service role).';

alter table public.push_dispatch_outcomes enable row level security;

revoke all on table public.push_dispatch_outcomes
  from anon, authenticated, public;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.push_dispatch_outcomes
  from anon, authenticated, public;
revoke all on sequence public.push_dispatch_outcomes_attempt_no_seq
  from anon, authenticated, public;

-- The service role reads for operational inspection and writes only through
-- the function below; nothing updates or deletes evidence through an API role.
revoke all on table public.push_dispatch_outcomes from service_role;
grant select on table public.push_dispatch_outcomes to service_role;


-- ============================================================================
-- 2) record_push_dispatch_outcome_v1 -- the one writer, service role only
-- ============================================================================
-- Called best-effort by push-dispatch at each terminal outcome. It validates
-- the closed outcome/count shape and appends one row. It reads nothing --
-- in particular it never reads notification content.
create or replace function public.record_push_dispatch_outcome_v1(
  p_notification_id uuid,
  p_outcome text,
  p_priority text default null,
  p_token_count integer default 0,
  p_sent_count integer default 0,
  p_stale_count integer default 0,
  p_failed_count integer default 0
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_notification_id is null
     or p_outcome is null
     or p_outcome not in (
       'not_found',
       'suppressed',
       'no_devices',
       'unrenderable',
       'dispatched',
       'internal_error'
     )
     or (p_priority is not null and p_priority not in ('high', 'medium', 'low'))
     or p_token_count is null or p_token_count < 0
     or p_sent_count is null or p_sent_count < 0
     or p_stale_count is null or p_stale_count < 0
     or p_failed_count is null or p_failed_count < 0
  then
    raise exception 'INVALID_PUSH_OUTCOME';
  end if;

  if p_outcome = 'dispatched' then
    if p_token_count < 1
       or p_token_count <> p_sent_count + p_stale_count + p_failed_count
    then
      raise exception 'INVALID_PUSH_OUTCOME';
    end if;
  elsif p_sent_count <> 0 or p_stale_count <> 0 or p_failed_count <> 0 then
    raise exception 'INVALID_PUSH_OUTCOME';
  end if;

  if p_outcome in ('not_found', 'no_devices') and p_token_count <> 0 then
    raise exception 'INVALID_PUSH_OUTCOME';
  end if;

  insert into public.push_dispatch_outcomes (
    notification_id,
    outcome,
    priority,
    token_count,
    sent_count,
    stale_count,
    failed_count
  )
  values (
    p_notification_id,
    p_outcome,
    p_priority,
    p_token_count,
    p_sent_count,
    p_stale_count,
    p_failed_count
  );
end;
$$;

comment on function public.record_push_dispatch_outcome_v1(
  uuid, text, text, integer, integer, integer, integer
) is
  'Wave 4 (migration 0090): appends one push_dispatch_outcomes row for a '
  'terminal push-dispatch outcome. Service role only. Validates the closed '
  'outcome/count shape; raises INVALID_PUSH_OUTCOME otherwise. Reads nothing.';

revoke execute on function public.record_push_dispatch_outcome_v1(
  uuid, text, text, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.record_push_dispatch_outcome_v1(
  uuid, text, text, integer, integer, integer, integer
) to service_role;


-- ============================================================================
-- 3) telemetry_ingest_windows -- the public telemetry circuit breaker
-- ============================================================================
-- Control state, not evidence: how many units each public telemetry channel
-- has accepted in each minute. Global per channel -- it identifies nobody and
-- stores no IP, user, device, cookie, session or fingerprint.
create table public.telemetry_ingest_windows (
  channel text not null
    constraint telemetry_ingest_windows_channel_check
      check (channel in ('acquisition_open', 'client_run', 'client_error')),
  minute_bucket timestamptz not null,
  accepted_count integer not null
    constraint telemetry_ingest_windows_count_check
      check (accepted_count >= 0),
  constraint telemetry_ingest_windows_pkey primary key (channel, minute_bucket)
);

comment on table public.telemetry_ingest_windows is
  'Wave 4 (migration 0090): per-channel accepted counts per minute for the '
  'public telemetry circuit breaker. Control state pruned after a day; no '
  'caller identity of any kind. Written only by consume_telemetry_budget_v1.';

alter table public.telemetry_ingest_windows enable row level security;

revoke all on table public.telemetry_ingest_windows
  from anon, authenticated, public;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.telemetry_ingest_windows
  from anon, authenticated, public;
revoke all on table public.telemetry_ingest_windows from service_role;
grant select on table public.telemetry_ingest_windows to service_role;


-- ============================================================================
-- 4) consume_telemetry_budget_v1 -- one unit, atomically, or refuse
-- ============================================================================
-- The limits are fixed here; no caller supplies one:
--
--   acquisition_open  120 / minute
--   client_run        120 / minute
--   client_error      240 / minute
--
-- **Atomic and race-safe.** One INSERT ... ON CONFLICT DO UPDATE ... WHERE:
-- concurrent callers serialise on the (channel, minute) row, and the WHERE is
-- re-checked against the latest row version, so the count can never pass the
-- limit. When it refuses, no row is returned and nothing changes.
--
-- Not client-executable: only the public telemetry writers below call it, as
-- their owner.
create or replace function public.consume_telemetry_budget_v1(p_channel text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer;
  v_bucket timestamptz := date_trunc('minute', now());
  v_accepted integer;
begin
  v_limit := case p_channel
    when 'acquisition_open' then 120
    when 'client_run' then 120
    when 'client_error' then 240
  end;
  if v_limit is null then
    raise exception 'INVALID_TELEMETRY_CHANNEL';
  end if;

  insert into public.telemetry_ingest_windows as w (
    channel,
    minute_bucket,
    accepted_count
  )
  values (p_channel, v_bucket, 1)
  on conflict (channel, minute_bucket) do update
    set accepted_count = w.accepted_count + 1
    where w.accepted_count < v_limit
  returning w.accepted_count into v_accepted;

  if v_accepted is null then
    return false;
  end if;

  -- Opportunistic pruning, once per channel per minute: this is control
  -- state, and a day is far longer than any window it answers for.
  if v_accepted = 1 then
    delete from public.telemetry_ingest_windows t
    where t.minute_bucket < v_bucket - interval '1 day';
  end if;

  return true;
end;
$$;

comment on function public.consume_telemetry_budget_v1(text) is
  'Wave 4 (migration 0090): consumes one unit of a public telemetry channel''s '
  'fixed per-minute budget (acquisition_open 120, client_run 120, '
  'client_error 240). Returns false when the minute is exhausted. Internal: '
  'not executable by any client role.';

revoke execute on function public.consume_telemetry_budget_v1(text)
  from public, anon, authenticated;


-- ============================================================================
-- 5) record_anonymous_public_link_open -- Wave 3 writer, now budgeted
-- ============================================================================
-- Same signature, same validation, same privacy boundary and same grants as
-- 0089. The one change: after validation and before inserting, it consumes
-- one acquisition_open unit, and refuses with TELEMETRY_RATE_LIMITED when the
-- minute is exhausted. The client already swallows every failure of this call.
create or replace function public.record_anonymous_public_link_open(
  p_kind text,
  p_platform text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text;
  v_acquisition_id uuid;
begin
  if auth.uid() is not null then
    raise exception 'ANONYMOUS_ONLY';
  end if;

  v_source := case p_kind
    when 'player' then 'public_link_player'
    when 'community' then 'public_link_community'
    when 'match' then 'public_link_match'
  end;
  if v_source is null then
    raise exception 'INVALID_PUBLIC_LINK_KIND';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  -- NEW (0090): the ingest circuit breaker.
  if not public.consume_telemetry_budget_v1('acquisition_open') then
    raise exception 'TELEMETRY_RATE_LIMITED';
  end if;

  v_acquisition_id := gen_random_uuid();

  insert into public.product_events (
    user_id,
    event_name,
    acquisition_id,
    source,
    platform,
    app_version
  )
  values (
    null,
    'public_link_opened',
    v_acquisition_id,
    v_source,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), '')
  );

  return v_acquisition_id;
end;
$$;

comment on function public.record_anonymous_public_link_open(text, text, text) is
  'Wave 3 (migration 0089), budgeted by Wave 4 (0090): records one anonymous '
  'public_link_opened for a signed-out reader and returns its server-generated '
  'acquisition_id. Accepts only the link kind (player/community/match), '
  'platform (web/android/null) and app version. Stores no target id and no '
  'personal or device data. Raises ANONYMOUS_ONLY, INVALID_PUBLIC_LINK_KIND, '
  'INVALID_ANALYTICS_PLATFORM or TELEMETRY_RATE_LIMITED; the client swallows '
  'all four.';

-- Unchanged audience, restated: anon and service_role only.
revoke execute on function
  public.record_anonymous_public_link_open(text, text, text)
  from public, authenticated;
grant execute on function
  public.record_anonymous_public_link_open(text, text, text)
  to anon, service_role;


-- ============================================================================
-- 6) client_runtime_events -- production run starts and uncaught errors
-- ============================================================================
-- OI-06 Client Error Rate =
--   distinct production run_id with >= 1 error / distinct run_id started.
--
-- A run is one app process or page load, identified by a server-generated
-- random id the client keeps in memory only. The run carries the build, never
-- the person: no user id, contact detail, IP, device id, cookie or session.
-- An error carries a category, a fixed-shape fingerprint the client derives
-- locally, and at most a short sanitized code -- never the exception message
-- or stack trace.
create table public.client_runtime_events (
  event_no bigint generated always as identity primary key,
  run_id uuid not null,
  event_type text not null
    constraint client_runtime_events_event_type_check
      check (event_type in ('run_started', 'error')),
  occurred_at timestamptz not null default now(),
  platform text not null
    constraint client_runtime_events_platform_check
      check (platform in ('web', 'android', 'ios')),
  app_version text not null
    constraint client_runtime_events_app_version_check
      check (app_version ~ '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$'),
  build_sha text not null
    constraint client_runtime_events_build_sha_check
      check (build_sha ~ '^[0-9a-f]{40}$'),
  category text
    constraint client_runtime_events_category_check
      check (
        category is null
        or category in ('flutter_framework', 'platform_unhandled')
      ),
  fingerprint text
    constraint client_runtime_events_fingerprint_check
      check (fingerprint is null or fingerprint ~ '^[0-9a-f]{16}$'),
  context_code text
    constraint client_runtime_events_context_code_check
      check (context_code is null or context_code ~ '^[A-Za-z0-9_]{1,64}$'),
  constraint client_runtime_events_shape_check
    check (
      (
        event_type = 'run_started'
        and category is null
        and fingerprint is null
        and context_code is null
      )
      or (
        event_type = 'error'
        and category is not null
        and fingerprint is not null
      )
    )
);

-- Exactly one run_started per run; also the lookup an error report makes.
create unique index client_runtime_events_one_start_per_run_key
  on public.client_runtime_events (run_id)
  where event_type = 'run_started';

-- Run and error windows (the OI-06 numerator and denominator).
create index client_runtime_events_type_time_idx
  on public.client_runtime_events (event_type, occurred_at desc);

-- Top fingerprints by version and platform.
create index client_runtime_events_error_analysis_idx
  on public.client_runtime_events (
    fingerprint,
    app_version,
    platform,
    occurred_at desc
  )
  where event_type = 'error';

comment on table public.client_runtime_events is
  'Wave 4 (migration 0090): append-only production client runtime evidence -- '
  'run starts and uncaught errors, keyed by a server-generated in-memory run '
  'id. No user, contact, IP, device, cookie, session, raw message or stack. '
  'Written only by start_client_runtime_v1 and report_client_error_v1.';

alter table public.client_runtime_events enable row level security;

revoke all on table public.client_runtime_events
  from anon, authenticated, public;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.client_runtime_events
  from anon, authenticated, public;
revoke all on sequence public.client_runtime_events_event_no_seq
  from anon, authenticated, public;
revoke all on table public.client_runtime_events from service_role;
grant select on table public.client_runtime_events to service_role;


-- ============================================================================
-- 7) start_client_runtime_v1 -- one run, generated on the server
-- ============================================================================
-- Intentionally callable by anon and authenticated: a run is an app process,
-- signed in or not. Accepts the build identity only, consumes one client_run
-- unit, and returns only the new run id.
create or replace function public.start_client_runtime_v1(
  p_platform text,
  p_app_version text,
  p_build_sha text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id uuid;
begin
  if p_platform is null
     or p_platform not in ('web', 'android', 'ios')
     or p_app_version is null
     or p_app_version !~ '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$'
     or p_build_sha is null
     or p_build_sha !~ '^[0-9a-f]{40}$'
  then
    raise exception 'INVALID_CLIENT_RUNTIME';
  end if;

  if not public.consume_telemetry_budget_v1('client_run') then
    raise exception 'TELEMETRY_RATE_LIMITED';
  end if;

  v_run_id := gen_random_uuid();

  insert into public.client_runtime_events (
    run_id,
    event_type,
    platform,
    app_version,
    build_sha
  )
  values (
    v_run_id,
    'run_started',
    p_platform,
    p_app_version,
    p_build_sha
  );

  return v_run_id;
end;
$$;

comment on function public.start_client_runtime_v1(text, text, text) is
  'Wave 4 (migration 0090): records one run_started for a production client '
  'build and returns its server-generated run id. Accepts platform '
  '(web/android/ios), app version and a 40-hex build SHA only. Raises '
  'INVALID_CLIENT_RUNTIME or TELEMETRY_RATE_LIMITED; the client swallows both.';

revoke execute on function public.start_client_runtime_v1(text, text, text)
  from public;
grant execute on function public.start_client_runtime_v1(text, text, text)
  to anon, authenticated, service_role;


-- ============================================================================
-- 8) report_client_error_v1 -- one uncaught error of an existing run
-- ============================================================================
-- The run must exist; platform, version and build SHA are copied from its
-- run_started row and never accepted again. A missing or invalid run records
-- nothing and consumes no budget.
create or replace function public.report_client_error_v1(
  p_run_id uuid,
  p_category text,
  p_fingerprint text,
  p_context_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.client_runtime_events%rowtype;
begin
  if p_run_id is null
     or p_category is null
     or p_category not in ('flutter_framework', 'platform_unhandled')
     or p_fingerprint is null
     or p_fingerprint !~ '^[0-9a-f]{16}$'
     or (p_context_code is not null and p_context_code !~ '^[A-Za-z0-9_]{1,64}$')
  then
    raise exception 'INVALID_CLIENT_ERROR';
  end if;

  select * into v_run
  from public.client_runtime_events e
  where e.run_id = p_run_id
    and e.event_type = 'run_started';
  if not found then
    raise exception 'CLIENT_RUN_NOT_FOUND';
  end if;

  if not public.consume_telemetry_budget_v1('client_error') then
    raise exception 'TELEMETRY_RATE_LIMITED';
  end if;

  insert into public.client_runtime_events (
    run_id,
    event_type,
    platform,
    app_version,
    build_sha,
    category,
    fingerprint,
    context_code
  )
  values (
    p_run_id,
    'error',
    v_run.platform,
    v_run.app_version,
    v_run.build_sha,
    p_category,
    p_fingerprint,
    p_context_code
  );
end;
$$;

comment on function public.report_client_error_v1(uuid, text, text, text) is
  'Wave 4 (migration 0090): records one uncaught client error against an '
  'existing run, copying its platform, version and build SHA. Category, '
  '16-hex fingerprint and optional sanitized context code only. Raises '
  'INVALID_CLIENT_ERROR, CLIENT_RUN_NOT_FOUND or TELEMETRY_RATE_LIMITED; the '
  'client swallows all three.';

revoke execute on function public.report_client_error_v1(uuid, text, text, text)
  from public;
grant execute on function public.report_client_error_v1(uuid, text, text, text)
  to anon, authenticated, service_role;
