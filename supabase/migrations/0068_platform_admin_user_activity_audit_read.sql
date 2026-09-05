-- ======== migrations/0068_platform_admin_user_activity_audit_read.sql ========
-- Platform Admin: one account in detail, and the record of what was done.
--
-- `0067` gave the platform a way to see the shape of the whole product. What it
-- still cannot do is answer either of the two questions an administrator
-- actually opens the console holding:
--
--   * **"who is this person?"** -- when did they join, when were they last
--     here, how much do they actually use this, what have they done;
--   * **"what have we done to them?"** -- `admin_audit_log` has been recording
--     every suspension since `0062` and no client can read a single row of it.
--
-- Three read RPCs, and nothing else. **This migration creates no table, writes
-- no row, and changes no existing object.** There is no INSERT, no UPDATE, no
-- DELETE, no backfill, no new index -- `0062` already indexed the audit log on
-- `created_at desc`, on the actor and on the target, and `0067` already indexed
-- `product_events` on the user, so every scan below is served by an index that
-- exists.
--
-- ## THE TWO TABLES STAY UNREACHABLE
--
-- `product_events` and `admin_audit_log` both have RLS on with zero policies
-- and no client privileges, and both keep it. Nothing here grants SELECT on
-- either, adds a policy to either, or alters their RLS. Everything a client can
-- see arrives through one of the three `security definer` functions below,
-- which decide what to expose -- and each one opens with `is_system_admin()`.
--
-- `record_admin_audit` (`0062`) is not touched. It is the internal writer,
-- granted to nobody, and this migration is about reading.
--
-- ## WHAT IS DELIBERATELY NOT RETURNED
--
-- No date of birth, no age, no IP address, no user agent, no device identifier,
-- no browser fingerprint, no typed text, no search history and no raw auth
-- metadata. `auth.users` is read for exactly one column -- the email -- which is
-- the same single field `admin_list_users` (`0017`, `0066`) already reads
-- through the same `security definer` device.
--
-- The audit log's `metadata` jsonb is **not** returned either. It is structured
-- detail for a future reader that knows what to do with it; putting raw JSON in
-- front of an administrator is not a feature, and a column that is not returned
-- cannot leak something a later action decides to record in it.



-- ============================================================================
-- 1) admin_user_activity_summary() -- one account, in figures
-- ============================================================================
-- Everything the User Detail screen shows above its timeline, in one row from
-- one call.
--
-- **`is_system_admin()` is the first executable statement.** Not the first
-- interesting one -- the first. `v_zone` is declared without an initializer so
-- that not even reading the time zone precedes the authorization decision, and
-- the existence check for the target follows the gate rather than preceding it:
-- whether an account exists is itself something only a System Admin may learn.
--
-- ## WHERE EACH FIGURE COMES FROM
--
-- **Last Seen is observed activity, never a sign-in timestamp.**
-- `auth.last_sign_in_at` is not read here or anywhere in this file. It is one
-- value per account, it moves when a token refreshes rather than when a person
-- does something, and using it would report somebody as "seen" who has not
-- opened the app in a year. `max(product_events.created_at)` is what the
-- product actually watched happen, and it is null -- not a guess, not
-- `created_at` -- for an account that has done nothing since `0067` was
-- deployed.
--
-- **Matches Played comes from `player_statistics`, not from
-- `v_player_statistics`.** That view carries `where u.is_active`, so a
-- suspended account vanishes from it entirely -- and a suspended account is
-- precisely the one an administrator is most likely to be looking at. Reading
-- the table directly is the only way this figure survives the suspension it is
-- being used to review. `player_profile()` (`0043`, `0056`) already reads the
-- table for the same reason.
--
-- **An Active Day is a `session_started` on a local calendar day.** Bucketed by
-- `statistics_period_zone()` (`0028`, FROZEN), which is the product's one
-- definition of what day it is; a second constant here would be a second
-- "today" free to drift from the first in silence. No other event makes a day
-- active -- viewing a match at 11pm and again at 1am is one person, two events
-- and, correctly, no active days at all unless a session was started.
--
-- **Sessions, Registrations and Withdrawals are TRACKED counts.** They start at
-- `0067` and nothing older is invented to pad them. Withdrawals in particular
-- exist nowhere else: withdrawing deletes the `match_registrations` row, so the
-- event is the only record there has ever been.
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

  -- Every column reference below is qualified, without exception. This
  -- function's output columns are named after real columns -- `created_at`,
  -- `is_active`, `user_id`, `matches_played` -- and in plpgsql an output column
  -- is a variable, so an unqualified reference to any of them is ambiguous and
  -- raises at run time rather than at deploy time. Qualifying is what makes
  -- that unreachable.
  return query
  with events as (
    -- Read once. Six of the figures below are questions about this one set.
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

    -- Observed activity of any kind, not just a session: the last time this
    -- person was demonstrably using the product.
    (select max(e.created_at) from events e),

    -- Distinct local calendar days carrying at least one session.
    (select count(distinct (e.created_at at time zone v_zone)::date)
       from events e
      where e.event_name = 'session_started'
        and e.created_at >= now() - interval '7 days'),
    (select count(distinct (e.created_at at time zone v_zone)::date)
       from events e
      where e.event_name = 'session_started'
        and e.created_at >= now() - interval '30 days'),

    (select count(*) from events e
      where e.event_name = 'session_started'),

    -- An empty array rather than null, so the caller has one shape to render
    -- and "no platform observed" is a list with nothing in it. Ordered, so two
    -- reads of the same account never disagree about which came first.
    (select coalesce(array_agg(distinct e.platform order by e.platform),
                     array[]::text[])
       from events e
      where e.platform is not null),

    -- The version the most recent event that carried one was recorded on. Null
    -- when nothing has ever carried one.
    (select e.app_version from events e
      where e.app_version is not null
      order by e.created_at desc
      limit 1),

    -- Membership as it stands now. Not historical: leaving a community removes
    -- the row, and this figure has never claimed to be a history.
    (select count(*) from community_members cm
      where cm.user_id = p_user_id),

    (select count(*) from events e
      where e.event_name = 'match_registered'),

    -- The historical fact, from the table rather than the view. See the header.
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
  'Platform Admin: one account in figures (migration 0068). Gated on '
  'is_system_admin() as the first executable statement; USER_NOT_FOUND for an '
  'id with no users row. Last Seen is max(product_events.created_at) -- '
  'auth.last_sign_in_at is never read. Active Days count distinct local days '
  'carrying a session_started, bucketed by statistics_period_zone(). '
  'Matches Played reads player_statistics directly, NOT v_player_statistics, '
  'which filters on users.is_active and would erase the suspended account this '
  'screen exists to inspect. Sessions, registrations and withdrawals are '
  'tracked counts and begin at migration 0067. Reads auth.users for the email '
  'only.';

-- The same two executing roles as every other `admin_*` RPC, both named.
-- `create or replace` keeps an existing ACL so these are additive today, but
-- `0066` is the reason they are written down: a signature change means a drop,
-- and a drop takes the whole ACL with it including the `service_role` grant
-- Supabase's default rule made and no migration ever mentioned.
revoke execute on function public.admin_user_activity_summary(uuid)
  from anon, public;
grant execute on function public.admin_user_activity_summary(uuid)
  to authenticated;
grant execute on function public.admin_user_activity_summary(uuid)
  to service_role;



-- ============================================================================
-- 2) admin_user_activity_timeline() -- what that account actually did
-- ============================================================================
-- The most recent events for one account, newest first, with whatever display
-- context still exists for each.
--
-- **Both joins are LEFT, and that is the whole design.** `product_events` has
-- no foreign keys, deliberately (`0067`), because the legacy `admin_delete_*`
-- RPCs hard-delete and a FK would either block them or silently rewrite the
-- activity record. The consequence is that a community or a match named by an
-- event may be gone. An INNER join would then make the event itself disappear
-- -- so deleting a community would quietly erase a person's history of having
-- been in it, which is the precise opposite of what an audit surface is for.
-- With LEFT joins the row survives and the label arrives null, and the screen
-- says "no longer available" rather than showing a uuid or showing nothing.
--
-- **`user_id` is deliberately not returned.** The caller named the account in
-- the argument; echoing it on all fifty rows would be fifty copies of something
-- already known.
--
-- There is no metadata column on `product_events` and none is added. The event
-- name, the two optional contexts, the platform and the version are the whole
-- of what was ever recorded.
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
  created_at timestamptz
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

  -- Clamped rather than validated. A caller asking for 5000 rows has made a
  -- mistake, not an attack, and the useful answer is 100 of them -- refusing
  -- would turn a harmless argument into a failed screen. `coalesce` because an
  -- explicit null is not the same as an omitted argument and would otherwise
  -- reach `least()` and produce null.
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);

  return query
    select pe.event_name,
           pe.community_id,
           c.name,
           pe.match_id,
           m.title,
           pe.platform,
           pe.app_version,
           pe.created_at
    from product_events pe
    left join communities c on c.id = pe.community_id
    left join matches m on m.id = pe.match_id
    where pe.user_id = p_user_id
    order by pe.created_at desc
    limit v_limit;
end;
$$;

comment on function public.admin_user_activity_timeline(uuid, integer) is
  'Platform Admin: one account''s recent activity, newest first (migration '
  '0068). Gated on is_system_admin() as the first executable statement; '
  'USER_NOT_FOUND for an unknown id. p_limit is clamped to 1..100. The '
  'community and match joins are LEFT on purpose: product_events has no '
  'foreign keys, so deleted context must leave the event standing with a null '
  'label rather than removing it from the history. user_id is not returned -- '
  'the caller chose it.';

revoke execute on function public.admin_user_activity_timeline(uuid, integer)
  from anon, public;
grant execute on function public.admin_user_activity_timeline(uuid, integer)
  to authenticated;
grant execute on function public.admin_user_activity_timeline(uuid, integer)
  to service_role;



-- ============================================================================
-- 3) admin_list_audit_log() -- what administrators have done
-- ============================================================================
-- The administrative record, newest first. `admin_audit_log` has been filling
-- up since `0062` and until now nothing could read it: RLS with no policies,
-- every client privilege revoked, and a writer granted to nobody. This is the
-- one door, and it opens only for a System Admin.
--
-- **The table is not altered and nothing is granted on it.** Its RLS stands, its
-- privileges stand, `record_admin_audit` stands. This function reads it as its
-- owner, which is what `security definer` is for, and returns nine of its ten
-- columns.
--
-- **The tenth is `metadata`, and it is withheld deliberately.** Raw jsonb in
-- front of an administrator is not information, and a column that is never
-- returned cannot surface whatever a future action decides to record in it.
-- Exposing it is its own decision, for a cycle that has a reason to make it.
--
-- **Nothing constrains which actions come back.** The four the product writes
-- today are `USER_SUSPENDED`, `USER_REACTIVATED`, `COMMUNITY_SUSPENDED` and
-- `COMMUNITY_REACTIVATED`, and it would be easy to filter to them here -- and
-- wrong. An append-only log whose reader silently drops rows it does not
-- recognise is a log that hides exactly the entries most worth seeing. Every
-- row is returned and the client renders an unfamiliar action as itself.
create or replace function public.admin_list_audit_log(
  p_limit integer default 100
)
returns table (
  id uuid,
  actor_user_id uuid,
  actor_email_snapshot text,
  action text,
  target_type text,
  target_id uuid,
  target_label_snapshot text,
  reason text,
  created_at timestamptz
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

  v_limit := least(greatest(coalesce(p_limit, 100), 1), 200);

  -- Served by `admin_audit_log_created_at_idx` (`0062`), which is
  -- `(created_at desc)` for exactly this read. No index is added here.
  return query
    select a.id,
           a.actor_user_id,
           a.actor_email_snapshot,
           a.action,
           a.target_type,
           a.target_id,
           a.target_label_snapshot,
           a.reason,
           a.created_at
    from admin_audit_log a
    order by a.created_at desc
    limit v_limit;
end;
$$;

comment on function public.admin_list_audit_log(integer) is
  'Platform Admin: the administrative audit trail, newest first (migration '
  '0068). Gated on is_system_admin() as the first executable statement; '
  'p_limit clamped to 1..200. The one read path into admin_audit_log, which '
  'keeps its RLS, its revoked privileges and its internal-only writer. Returns '
  'nine of ten columns -- metadata jsonb is deliberately withheld. Does not '
  'filter by action: the log is append-only and a reader that dropped '
  'unrecognised entries would hide the ones most worth seeing.';

revoke execute on function public.admin_list_audit_log(integer)
  from anon, public;
grant execute on function public.admin_list_audit_log(integer)
  to authenticated;
grant execute on function public.admin_list_audit_log(integer)
  to service_role;



-- ============================================================================
-- 4) What this migration did not do
-- ============================================================================
--   * **No table, no column, no index, no constraint.** `0062` and `0067`
--     already index every scan above.
--   * **No DML of any kind.** No INSERT, no UPDATE, no DELETE, no backfill, no
--     fabricated activity. Three functions and their grants are the whole file.
--   * `product_events` and `admin_audit_log` -- RLS untouched, no policy added,
--     no privilege granted on either table to any client role.
--   * `record_admin_audit` (`0062`) -- unchanged in definition and in
--     privilege; it stays the internal writer, granted to nobody.
--   * `admin_suspend_user`, `admin_reactivate_user` (`0064`),
--     `admin_suspend_community`, `admin_reactivate_community` (`0065`) --
--     unchanged. No suspension semantics move in this migration.
--   * `admin_list_users`, `admin_list_communities` (`0066`),
--     `admin_analytics_overview`, `record_product_event` (`0067`) -- unchanged.
--   * `v_player_statistics` (`0027`) -- **not read**, and not altered either.
--     Its `where u.is_active` is correct for the public football surfaces it
--     serves; it is simply the wrong source for a screen about a suspended
--     account.
--   * `statistics_period_zone()` (`0028`) -- read, never redefined. Still
--     FROZEN.
--   * every RLS policy, every Storage policy, every normal-user read model and
--     every public football view -- unchanged.
