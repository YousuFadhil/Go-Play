-- ============ migrations/0067_platform_admin_product_analytics.sql ============
-- Platform Admin: product analytics, and the Overview the Platform Admin reads.
--
-- `0062`-`0066` gave the platform the ability to suspend a record and to see
-- that it is suspended. What it still cannot answer is the question the product
-- is actually run on: **is anybody using this**. `users.created_at` says how
-- many accounts exist, and nothing in this schema says how many of them came
-- back this week.
--
-- This migration adds exactly what answers that, and no more:
--
--   * `product_events`            -- ten approved events, nothing else;
--   * `record_product_event(...)` -- the one way a row reaches that table;
--   * `admin_analytics_overview()`-- one System-Admin-gated read, one row.
--
-- ## THE TABLE STARTS EMPTY, AND STAYS HONEST
--
-- **There is no backfill in this file, deliberately, and that is the most
-- important sentence in it.** It would be easy to manufacture a plausible
-- history -- turn `auth.last_sign_in_at` into a session, turn every surviving
-- `match_registrations` row into a registration event -- and every figure it
-- produced would be a lie of a particularly bad kind: not obviously wrong, just
-- quietly wrong, forever, with nothing afterwards able to tell which rows were
-- observed and which were invented.
--
-- Two facts make that especially clear here:
--
--   * `auth.last_sign_in_at` is one timestamp per account. It cannot produce a
--     history of sessions, and using it as "active" would count somebody who
--     signed in once a year ago as active today.
--   * a withdrawal **deletes** the `match_registrations` row (`0004` onward),
--     so the surviving rows are the registrations that were *not* withdrawn.
--     Backfilling `match_registered` from them would silently assert that
--     nobody has ever withdrawn from anything.
--
-- So behavioural metrics start accumulating from the day this is deployed, and
-- the dashboard says so on its face. Metrics whose evidence genuinely exists in
-- the business tables -- accounts, matches, results -- are correct immediately,
-- because those tables really do record the historical fact.
--
-- ## WHAT IS DELIBERATELY NOT COLLECTED
--
-- No IP address. No device identifier. No browser fingerprint. No user agent.
-- No typed text, no search terms, no free-text metadata and no generic JSON
-- column to smuggle any of it in later. No page-by-page navigation trail and no
-- session replay. The table has room for a user, an event name, an optional
-- community, an optional match, a platform word and a version string, and it
-- has room for nothing else -- which is a schema-level product decision, not a
-- policy that a later caller can quietly ignore.



-- ============================================================================
-- 1) product_events
-- ============================================================================
-- One row per meaningful thing a signed-in player did.
--
-- **No foreign keys, and this is the same decision `admin_audit_log` (`0062`)
-- made for the same reason.** `admin_delete_user`, `admin_delete_community` and
-- `admin_delete_match` (`0017`) still exist and still hard-delete. A FK here
-- would give this table two ways to do harm and no way to do good:
--
--   * `on delete restrict` would let an analytics row **block** an
--     administrative delete -- history holding a person's account hostage;
--   * `on delete cascade` would let a delete **silently rewrite** the activity
--     record, so a community that was busy last week becomes a community that
--     was never busy at all, with no trace that the figure moved.
--
-- Bare uuids, therefore. An id whose row is gone is simply an id whose row is
-- gone: the aggregate that counted it stays honest about the week it describes,
-- and the Overview only ever counts, so a dangling id costs nothing.
--
-- `gen_random_uuid()` for the key, this schema's convention throughout.
create table if not exists public.product_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  event_name text not null
    constraint product_events_event_name_check check (event_name in (
      'session_started',
      'community_viewed',
      'community_created',
      'community_joined',
      'match_viewed',
      'match_registered',
      'match_withdrawn',
      'teams_viewed',
      'result_viewed',
      'share_used'
    )),
  community_id uuid,
  match_id uuid,
  platform text
    constraint product_events_platform_check
      check (platform is null or platform in ('web', 'android')),
  app_version text,
  created_at timestamptz not null default now()
);

comment on table public.product_events is
  'Product analytics (migration 0067). Append-only, ten approved event names, '
  'no free-text and no generic metadata column. Bare uuids with no foreign '
  'key, deliberately: the legacy admin_delete_* RPCs hard-delete, and a FK '
  'would either block them or silently rewrite the activity record. Written '
  'only by record_product_event(); read only by admin_analytics_overview(). '
  'No client can reach it directly. Contains no backfilled or fabricated row: '
  'it started empty on the day this migration was applied.';

comment on column public.product_events.user_id is
  'Who acted, always taken from auth.uid() by the writer and never from an '
  'argument. No FK: the row must survive the account being deleted.';
comment on column public.product_events.community_id is
  'The community the event happened in, when the acting screen already knew '
  'it. Null is ordinary and never means "no community" -- it means the caller '
  'had no context to hand, and no screen makes an extra request to fill it.';
comment on column public.product_events.match_id is
  'The match the event happened on, on the same terms as community_id.';
comment on column public.product_events.platform is
  'web or android, or null where the platform is one this cycle does not '
  'report. Not a device identifier: it is one of two words.';
comment on column public.product_events.app_version is
  'The application build that recorded the event, so a change in a metric can '
  'be read against the release it followed. Truncated by the writer.';
comment on column public.product_events.created_at is
  'Database time, from the column default. Never client-supplied: a clock the '
  'product does not own must not decide which day a metric falls in.';

-- Indexes: four, one per scan the Overview actually performs, and no others.
--
--   * (user_id, created_at)      -- a single account's activity, and the
--                                   distinct-user scans DAU/WAU/MAU/retention
--                                   all reduce to;
--   * (event_name, created_at)   -- every metric filters on an event name and
--                                   a window, and this is that pair;
--   * (community_id, created_at) -- the community half of Weekly Active
--                                   Communities;
--   * (match_id, created_at)     -- the match half, for later match-level
--                                   reads.
--
-- `created_at desc` in each, because every window this table is asked about is
-- a recent one and every one of them is served backwards from now.
create index if not exists product_events_user_created_idx
  on public.product_events (user_id, created_at desc);
create index if not exists product_events_name_created_idx
  on public.product_events (event_name, created_at desc);
create index if not exists product_events_community_created_idx
  on public.product_events (community_id, created_at desc);
create index if not exists product_events_match_created_idx
  on public.product_events (match_id, created_at desc);



-- ============================================================================
-- 2) No client reaches this table
-- ============================================================================
-- Two independent mechanisms, exactly as `admin_audit_log` (`0062`) has, and
-- for the reason `0034` recorded: relying on one of them is how a read-only
-- view became an anonymous DELETE against `public.communities`.
--
-- **RLS with no policies.** The `system_admins` (`0017`), `push_config`
-- (`0036`) and `admin_audit_log` (`0062`) pattern: row-level security on and
-- not a single policy, so every client role is denied every row for every
-- command. There is deliberately no INSERT policy -- the only writer is section
-- 3, which is `security definer` and runs past RLS -- and deliberately no
-- SELECT policy, because the only reader is section 4, which is gated on
-- `is_system_admin()`.
alter table public.product_events enable row level security;

-- **And the privileges themselves.** Supabase ships a default-privileges rule
-- on schema `public` that grants ALL to `anon`, `authenticated` and
-- `service_role` on every newly created table, and it fires before this file's
-- own statements are reached. This table arrives carrying those grants, so the
-- two client roles have theirs taken back here.
--
-- RLS would already deny a client that held them. That is not a reason to leave
-- them: a grant that is merely unreachable is one policy mistake away from
-- being reachable, and TRUNCATE in particular is **not filtered by RLS at all**
-- -- it is a table-level privilege, and a role holding it could empty the
-- activity record in a single statement.
revoke all on public.product_events from anon, authenticated, public;

-- Named individually as well, in the manner `0034` established, so this file
-- states which privileges rather than leaving a reader to work out what `all`
-- covered.
revoke select, insert, update, delete, truncate, references, trigger
  on public.product_events
  from anon, authenticated, public;

-- `service_role` is deliberately left as it is. It is the trusted server-side
-- key, it is never shipped to a client, and it is the role a future export or
-- maintenance job would run as. `0066` is the reminder that a privilege this
-- schema never wrote down is still a privilege something depends on.



-- ============================================================================
-- 3) record_product_event() -- the one writer
-- ============================================================================
-- The only way a row reaches `product_events`. No client holds INSERT on the
-- table, so this is not one path among several: it is the path.
--
-- **The caller cannot say who they are.** There is no `p_user_id`, and adding
-- one would be the whole vulnerability: an argument the client controls,
-- written into a table the client cannot otherwise touch, is an invitation to
-- attribute activity to somebody else. `auth.uid()` is read here and used
-- directly, so an event is always recorded against the session that recorded
-- it and against nothing else.
--
-- **A suspended account records nothing.** `is_current_user_active()` (`0062`)
-- is the same predicate every enforcement path in `0064` uses. A suspended
-- reader cannot reach the product at all, so in practice this guard is never
-- the thing that stops them -- it is here so that the analytics surface does
-- not become the one write in the schema that a suspension does not cover.
--
-- **Errors are stable and boring.** They exist so a client can be tested
-- against them, not so a player can ever see one: analytics is non-blocking on
-- the Flutter side and every one of these is swallowed there.
create or replace function public.record_product_event(
  p_event_name text,
  p_community_id uuid default null,
  p_match_id uuid default null,
  p_platform text default null,
  p_app_version text default null
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

  -- Restated here rather than left to the CHECK constraint. The constraint is
  -- the guarantee; this is the stable error, so a rejected event name arrives
  -- as INVALID_ANALYTICS_EVENT rather than as a raw constraint violation.
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
    'share_used'
  ) then
    raise exception 'INVALID_ANALYTICS_EVENT';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  -- `created_at` is left to the column default, which is database `now()`. A
  -- client clock must not decide which calendar day a metric falls in.
  --
  -- `app_version` is bounded rather than validated. It is a free string from
  -- the client and the only thing that matters about it is that it cannot grow
  -- without limit; 64 characters is far more than `0.4.1-public-beta+2` needs,
  -- and truncating cannot reject a legitimate write the way a CHECK could.
  insert into product_events (
    user_id, event_name, community_id, match_id, platform, app_version
  )
  values (
    v_user_id,
    p_event_name,
    p_community_id,
    p_match_id,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), '')
  );
end;
$$;

comment on function public.record_product_event(text, uuid, uuid, text, text) is
  'The one writer for product_events (migration 0067). Records the event '
  'against auth.uid() -- there is deliberately no user-id argument -- after '
  'checking that the caller is signed in, active, and naming an approved event '
  'and platform. Raises NOT_AUTHENTICATED, ACCOUNT_SUSPENDED, '
  'INVALID_ANALYTICS_EVENT or INVALID_ANALYTICS_PLATFORM; the client swallows '
  'all four, because analytics never blocks a product flow.';

-- `authenticated` executes it, because every event is an authenticated
-- player's. `anon` has none: an event belongs to a session, and `anon` has no
-- session to belong to.
--
-- `service_role` is granted **by name**, which is `0066`'s lesson written down
-- rather than remembered. `create or replace` keeps an existing ACL, so these
-- grants are additive today -- but the day one of these functions changes its
-- signature it will have to be dropped, and a drop takes the whole ACL with it
-- including the grant Supabase's default rule made and no migration mentioned.
-- Naming it here means the next author reads it in the file instead of finding
-- out from production.
revoke execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  from anon, public;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  to authenticated;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  to service_role;



-- ============================================================================
-- 4) admin_analytics_overview() -- the Platform Admin's one read
-- ============================================================================
-- Every figure on the Overview dashboard, in one row, from one call.
--
-- **`is_system_admin()` is the first executable statement, before anything
-- else happens.** Not the first interesting statement -- the first one. The day
-- boundary is computed *after* it, and `v_day_start` is declared without an
-- initializer precisely so that no work at all precedes the authorization
-- decision. This is the same gate `admin_list_users` and every other `admin_*`
-- RPC opens with, in the same position.
--
-- **`product_events` is never exposed.** This function returns counts. There is
-- no row, no id, no event and no way to ask it what one person did -- that is
-- User Activity Detail, which is a later cycle with its own decisions to make.
--
-- ## WHERE EACH FIGURE COMES FROM, AND WHY
--
-- The choice between a business table and an event is not stylistic. It is
-- decided, per metric, by which one actually preserves the historical fact:
--
--   * accounts, matches, results -> the business tables. `users.created_at`,
--     `matches.created_at` and `match_results.created_at` are all still there
--     for every row that ever existed, so these figures are complete from the
--     first day the dashboard is opened.
--
--   * sessions and registrations -> `product_events`. There is no session
--     table and there never was; and a withdrawal *deletes* the
--     `match_registrations` row, so counting surviving rows would report the
--     registrations nobody withdrew from and call it registration activity.
--     Both are therefore partial until tracking accumulates, and partial-but-
--     true is the only honest option available.
create or replace function public.admin_analytics_overview()
returns table (
  total_users bigint,
  new_users_today bigint,
  new_users_7d bigint,
  new_users_30d bigint,
  dau bigint,
  wau bigint,
  mau bigint,
  weekly_active_communities bigint,
  matches_7d bigint,
  matches_30d bigint,
  registrations_7d bigint,
  registrations_30d bigint,
  results_7d bigint,
  results_30d bigint,
  retention_previous_week_users bigint,
  retention_returning_users bigint,
  weekly_retention_percent numeric
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_day_start timestamptz;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  -- The start of today in the product's one statistics time zone. `0028` froze
  -- that zone and every figure in the product is bucketed by it; a second
  -- constant here would be a second definition of "today" that could drift
  -- from the first without anything failing.
  v_day_start := date_trunc('day', now() at time zone statistics_period_zone())
                   at time zone statistics_period_zone();

  return query
  with
    -- Every session in the widest window any metric needs. Read once: MAU,
    -- WAU, DAU and both halves of retention are all questions about this set.
    sessions as (
      select pe.user_id, pe.created_at
      from product_events pe
      where pe.event_name = 'session_started'
        and pe.created_at >= now() - interval '30 days'
    ),

    -- The previous week's cohort: everybody who had a session in
    -- [now - 14 days, now - 7 days). Half-open on purpose, so the two weeks
    -- tile exactly and no session is counted in both.
    previous_week as (
      select distinct s.user_id
      from sessions s
      where s.created_at >= now() - interval '14 days'
        and s.created_at <  now() - interval '7 days'
    ),

    -- Of that cohort, who came back in [now - 7 days, now). This is the
    -- overlap the metric is made of: the same user, in both windows.
    returning_week as (
      select p.user_id
      from previous_week p
      where exists (
        select 1
        from sessions s
        where s.user_id = p.user_id
          and s.created_at >= now() - interval '7 days'
      )
    ),

    -- **Weekly Active Communities: real football, not page views.**
    --
    -- A community is active because somebody organised, joined, left or
    -- recorded a game there -- never because somebody looked at it. So
    -- `community_viewed`, `community_joined`, `community_created`,
    -- `match_viewed`, `teams_viewed`, `result_viewed` and `share_used` are all
    -- absent from this union, deliberately.
    --
    -- Both sources appear because neither alone is complete. The business
    -- tables hold the historical fact for creation and results and are correct
    -- from day one; the events hold the registration activity the business
    -- table destroys on withdrawal. `union` de-duplicates and the result is
    -- counted `distinct`, so a community proved active twice is still one
    -- community and the overlap costs nothing.
    active_communities as (
      -- a match was organised
      select m.community_id
      from matches m
      where m.created_at >= now() - interval '7 days'

      union

      -- somebody is registered for one, and has not withdrawn
      select m.community_id
      from match_registrations r
      join matches m on m.id = r.match_id
      where r.created_at >= now() - interval '7 days'

      union

      -- a result was recorded
      select m.community_id
      from match_results res
      join matches m on m.id = res.match_id
      where res.created_at >= now() - interval '7 days'

      union

      -- somebody registered or withdrew, as tracked. This is the half that
      -- survives a withdrawal, and the join to `communities` is what keeps a
      -- community that has since been deleted from counting: the event row has
      -- no foreign key, so its id can outlive the row it names.
      select pe.community_id
      from product_events pe
      join communities c on c.id = pe.community_id
      where pe.event_name in ('match_registered', 'match_withdrawn')
        and pe.created_at >= now() - interval '7 days'
    )

  select
    (select count(*) from users)::bigint,
    (select count(*) from users u where u.created_at >= v_day_start)::bigint,
    (select count(*) from users u
       where u.created_at >= now() - interval '7 days')::bigint,
    (select count(*) from users u
       where u.created_at >= now() - interval '30 days')::bigint,

    -- Active means a session, and nothing else means active.
    -- `auth.last_sign_in_at` is not read here or anywhere in this file: it is
    -- one timestamp per account and cannot describe a period.
    (select count(distinct s.user_id) from sessions s
       where s.created_at >= v_day_start)::bigint,
    (select count(distinct s.user_id) from sessions s
       where s.created_at >= now() - interval '7 days')::bigint,
    (select count(distinct s.user_id) from sessions s)::bigint,

    (select count(distinct a.community_id) from active_communities a)::bigint,

    (select count(*) from matches m
       where m.created_at >= now() - interval '7 days')::bigint,
    (select count(*) from matches m
       where m.created_at >= now() - interval '30 days')::bigint,

    -- Registrations come from the events, not from `match_registrations`,
    -- because that table loses a row when a player withdraws.
    (select count(*) from product_events pe
       where pe.event_name = 'match_registered'
         and pe.created_at >= now() - interval '7 days')::bigint,
    (select count(*) from product_events pe
       where pe.event_name = 'match_registered'
         and pe.created_at >= now() - interval '30 days')::bigint,

    (select count(*) from match_results res
       where res.created_at >= now() - interval '7 days')::bigint,
    (select count(*) from match_results res
       where res.created_at >= now() - interval '30 days')::bigint,

    (select count(*) from previous_week)::bigint,
    (select count(*) from returning_week)::bigint,

    -- **Null, not zero, when there is no previous cohort.** No cohort to
    -- return is not a cohort that failed to return, and reporting 0% would
    -- describe a product nobody came back to rather than a product nobody had
    -- yet been measured on. The dashboard renders this as an em dash.
    case
      when (select count(*) from previous_week) = 0 then null::numeric
      else round(
        (select count(*) from returning_week)::numeric * 100
          / (select count(*) from previous_week)::numeric,
        1
      )
    end;
end;
$$;

comment on function public.admin_analytics_overview() is
  'Platform Admin: the Overview dashboard, one row, one call (migration 0067). '
  'Gated on is_system_admin() as the first executable statement. Counts only '
  '-- product_events is never exposed as rows. Accounts, matches and results '
  'come from the business tables and are historically complete; sessions and '
  'registrations come from product_events and are therefore partial until '
  'tracking accumulates, because no session table ever existed and a '
  'withdrawal deletes the match_registrations row. Days are bucketed by '
  'statistics_period_zone(). weekly_retention_percent is NULL, never 0, when '
  'the previous week had no cohort.';

-- The same two executing roles as every other `admin_*` RPC, both named for
-- the reason section 3 gives. `anon` and PUBLIC get nothing: this is the
-- Platform Admin's read, and the function refuses anybody who is not a System
-- Admin in any case.
revoke execute on function public.admin_analytics_overview() from anon, public;
grant execute on function public.admin_analytics_overview() to authenticated;
grant execute on function public.admin_analytics_overview() to service_role;



-- ============================================================================
-- 5) What this migration did not do
-- ============================================================================
--   * **No backfill of any kind.** No INSERT into `product_events` from any
--     business table, no fabricated `session_started`, no conversion of
--     `auth.last_sign_in_at`, no synthetic withdrawal. The table starts empty
--     and every row in it was observed.
--   * **No user data was rewritten.** There is no UPDATE and no DELETE in this
--     file against any table.
--   * `users`, `communities`, `matches`, `match_registrations`, `match_results`
--     -- no column added, no constraint changed, no privilege changed, no row
--     written.
--   * `statistics_period_zone()` (`0028`) -- read, never redefined. It is
--     FROZEN and a second timezone constant would be a second definition of
--     "today" that could drift from the first in silence.
--   * `admin_list_users`, `admin_list_communities` (`0066`), the four
--     suspension RPCs (`0064`, `0065`), the three `admin_delete_*` RPCs
--     (`0017`), `admin_audit_log` and `record_admin_audit` (`0062`) --
--     unchanged in definition and in privilege.
--   * every RLS policy, every Storage policy, every normal-user read model and
--     every public football view -- unchanged.
--   * no materialized view, no cron job, no Edge Function, no Realtime
--     publication and no external service. The Overview is a small query a
--     System Admin runs on demand, and it is served by the four indexes above.
