-- ========= migrations/0069_platform_admin_analytics_drilldown.sql =========
-- Platform Admin: the records behind each Overview number.
--
-- `0067` gave the console a dashboard and `0068` gave it one account in detail.
-- What is missing is the step between them: an administrator reads "Weekly
-- Active Users: 88" and has no way to ask *which* 88. Every figure is a
-- dead end.
--
-- Six read-only, System-Admin-gated functions close that. Four answer "who or
-- what is in this number"; two answer "show me this community / this match"
-- for the records those lists point at.
--
-- **This migration creates no table, records no event, writes no row and
-- changes no existing object.** There is no INSERT, UPDATE, DELETE, backfill,
-- policy change or RLS change. `admin_analytics_overview()` is not redefined
-- and no metric moves.
--
-- ## THE RULE THAT SHAPES EVERY FUNCTION BELOW: COUNT FIDELITY
--
-- A drill-down that does not list exactly what the number counted is worse
-- than no drill-down. It looks authoritative and quietly disagrees with the
-- card above it, and the administrator has no way to tell which is wrong.
--
-- So each list here reproduces its metric's population *exactly*, and the
-- temptations are all in the same direction -- adding a filter that seems
-- obviously right:
--
--   * **not** `and u.is_active` on the user lists. The Overview counts every
--     account, so the drill-down lists every account. A suspended user is in
--     the number and must be in the list.
--   * **not** an INNER JOIN to `users` on the session-derived metrics.
--     `product_events` has no foreign keys (`0067`), so DAU/WAU/MAU/retention
--     can legitimately contain a `user_id` whose account was later deleted.
--     `count(distinct s.user_id)` counted it; an inner join would drop the row
--     and the list would come up short. LEFT JOIN, and the client renders the
--     missing name as "no longer available".
--   * **not** `distinct` on the registration list. The Overview counts
--     *events*, so one player registering for three matches is three rows.
--
-- Where the existing metric *does* narrow -- Weekly Active Communities inner
-- joins `communities` on its event branch -- that narrowing is reproduced
-- verbatim, for the same reason. Fidelity means copying the definition, not
-- improving it.
--
-- ## WHAT THESE DO NOT DO
--
-- No mutation path of any kind. No System Admin is granted a community role by
-- any of this -- the two inspection functions are `security definer` reads that
-- return facts, not authorization that unlocks a member screen. No join code is
-- exposed. `auth.users` is read for the email only, exactly as
-- `admin_list_users` (`0017`, `0066`) and `admin_user_activity_summary`
-- (`0068`) already do. `auth.last_sign_in_at` is not read anywhere.



-- ============================================================================
-- 1) admin_analytics_users() -- the people behind eight of the figures
-- ============================================================================
-- One function for eight metrics, because they differ only in which set of
-- user ids they name and every one of them wants the same row rendered
-- afterwards. Eight functions would be eight copies of that projection, free to
-- drift.
--
-- **The metric is a closed vocabulary, checked before anything is read.** An
-- unrecognised value raises rather than quietly returning an empty list, which
-- would look exactly like a metric that genuinely had nobody in it.
--
-- **`returned_in_current_week` is null for seven of the eight.** Null there
-- means "this metric does not ask that question", not "did not return" -- the
-- retention list is the only one for which returning is a property a row has.
create or replace function public.admin_analytics_users(
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
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if p_metric is null or p_metric not in (
    'total_users',
    'new_users_today',
    'new_users_7d',
    'new_users_30d',
    'dau',
    'wau',
    'mau',
    'weekly_retention'
  ) then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  -- The same expression `admin_analytics_overview()` uses, and it must stay
  -- the same expression: a second definition of "today" would put a user in
  -- the card and not in the list on the two days a year the zones disagree.
  v_day_start := date_trunc('day', now() at time zone statistics_period_zone())
                   at time zone statistics_period_zone();

  -- Every column reference below is qualified. This function's output columns
  -- are named after real columns -- `user_id`, `created_at`, `is_active` -- and
  -- in plpgsql an output column is a variable, so an unqualified reference is
  -- ambiguous and raises at run time rather than at deploy time.
  return query
  with
    -- `0067`'s own session set, reproduced exactly: the event name, the
    -- thirty-day horizon, and nothing else.
    sessions as (
      select pe.user_id, pe.created_at
      from product_events pe
      where pe.event_name = 'session_started'
        and pe.created_at >= now() - interval '30 days'
    ),

    -- The previous week's cohort. `0067` takes `distinct s.user_id` over the
    -- same half-open window; grouping produces the identical membership and
    -- carries a sort key with it.
    previous_week as (
      select s.user_id, max(s.created_at) as last_at
      from sessions s
      where s.created_at >= now() - interval '14 days'
        and s.created_at <  now() - interval '7 days'
      group by s.user_id
    ),

    -- Which ids this metric names, with what to sort them by and -- for
    -- retention only -- whether they came back.
    --
    -- One branch per metric, each guarded on `p_metric`, so exactly one can
    -- contribute rows. Whether the others are folded away at plan time or
    -- filtered at run time depends on whether PostgreSQL chose a custom or a
    -- generic plan; either is fine here, because this is a System-Admin read
    -- over an indexed window rather than a hot path.
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
        and u.created_at >= now() - interval '7 days'

      union all

      select u.id, u.created_at, null::boolean
      from users u
      where p_metric = 'new_users_30d'
        and u.created_at >= now() - interval '30 days'

      union all

      -- Distinct session users, which is what `count(distinct s.user_id)`
      -- counted. Grouped rather than DISTINCTed so the most recent session
      -- can order the list.
      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'dau'
        and s.created_at >= v_day_start
      group by s.user_id

      union all

      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'wau'
        and s.created_at >= now() - interval '7 days'
      group by s.user_id

      union all

      select s.user_id, max(s.created_at), null::boolean
      from sessions s
      where p_metric = 'mau'
        and s.created_at >= now() - interval '30 days'
      group by s.user_id

      union all

      -- The whole previous-week cohort, each carrying whether that same person
      -- had a session in [now - 7 days, now). This is `0067`'s
      -- `returning_week` predicate applied per row instead of counted.
      select p.user_id,
             p.last_at,
             exists (
               select 1
               from sessions s
               where s.user_id = p.user_id
                 and s.created_at >= now() - interval '7 days'
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
    -- Observed activity of any kind, on the same terms as `0068`. Null for an
    -- account the product has never watched do anything.
    (select max(pe.created_at) from product_events pe where pe.user_id = t.user_id),
    t.returned

  from target t
  -- **LEFT, and this is the count-fidelity rule in one line.** A session event
  -- can name an account that has since been deleted; it was counted, so it is
  -- listed, with null where the name would have been.
  left join users u on u.id = t.user_id
  left join auth.users au on au.id = t.user_id
  order by t.sort_at desc nulls last, t.user_id
  limit v_limit offset v_offset;
end;
$$;

comment on function public.admin_analytics_users(text, integer, integer) is
  'Platform Admin: the people behind eight Overview figures (migration 0069). '
  'Gated on is_system_admin() as the first executable statement; unknown '
  'metric raises INVALID_ADMIN_ANALYTICS_METRIC. Limit clamped 1..100, offset '
  '>= 0. Reproduces 0067 exactly: session_started for DAU/WAU/MAU, '
  'statistics_period_zone() for the calendar day, [now-14d, now-7d) for the '
  'retention cohort. Joins to users and auth.users are LEFT so a session event '
  'naming a deleted account still yields the row the Overview counted. No '
  'is_active filter is added, because the Overview does not have one. '
  'auth.last_sign_in_at is never read.';

revoke execute on function public.admin_analytics_users(text, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_users(text, integer, integer)
  to authenticated;
grant execute on function public.admin_analytics_users(text, integer, integer)
  to service_role;



-- ============================================================================
-- 2) admin_analytics_communities() -- the communities behind WAC
-- ============================================================================
-- **The membership of this list is `0067`'s Weekly Active Communities union,
-- copied branch for branch.** A match organised, a surviving registration, a
-- recorded result, or a tracked registration/withdrawal event -- and nothing
-- else. `community_viewed`, `community_joined`, `community_created`,
-- `match_viewed`, `teams_viewed`, `result_viewed` and `share_used` are absent
-- here because they are absent there: looking at a community is not activity
-- in it.
--
-- Two differences from `0067`'s text, neither of which changes the set:
--
--   * it uses `union` over bare community ids; this uses `union all` and
--     carries the activity timestamp, then groups. Grouping collapses the
--     duplicates that `union` would have removed, so the resulting set of
--     community ids is identical -- and the list gains a "last active" to sort
--     by, which a bare id could not provide.
--   * the fourth branch keeps `0067`'s **inner** join to `communities`,
--     deliberately. Elsewhere in this file a missing entity is preserved; here
--     it is not, because the Overview does not count it either. Fidelity means
--     copying the definition rather than improving it.
--
-- The other three branches derive `community_id` from `matches`, whose
-- `community_id` is a foreign key with `on delete cascade` (`0003`, `0007`), so
-- every id they produce has a live community row and the join below cannot drop
-- one.
create or replace function public.admin_analytics_communities(
  p_metric text,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  community_id uuid,
  name text,
  owner_name text,
  member_count bigint,
  match_count bigint,
  is_active boolean,
  last_activity_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit integer;
  v_offset integer;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if p_metric is null or p_metric <> 'weekly_active_communities' then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  return query
  with
    activity as (
      -- a match was organised
      select m.community_id, m.created_at as at
      from matches m
      where m.created_at >= now() - interval '7 days'

      union all

      -- somebody is registered for one, and has not withdrawn
      select m.community_id, r.created_at
      from match_registrations r
      join matches m on m.id = r.match_id
      where r.created_at >= now() - interval '7 days'

      union all

      -- a result was recorded
      select m.community_id, res.created_at
      from match_results res
      join matches m on m.id = res.match_id
      where res.created_at >= now() - interval '7 days'

      union all

      -- somebody registered or withdrew, as tracked
      select pe.community_id, pe.created_at
      from product_events pe
      join communities c on c.id = pe.community_id
      where pe.event_name in ('match_registered', 'match_withdrawn')
        and pe.created_at >= now() - interval '7 days'
    ),

    active_communities as (
      select a.community_id, max(a.at) as last_activity_at
      from activity a
      group by a.community_id
    )

  select
    c.id,
    c.name,
    o.full_name,
    (select count(*) from community_members cm where cm.community_id = c.id),
    (select count(*) from matches m2 where m2.community_id = c.id),
    c.is_active,
    a.last_activity_at
  from active_communities a
  join communities c on c.id = a.community_id
  -- The owner join stays LEFT, exactly as `admin_list_communities` (`0066`)
  -- has it: a community whose owner row is gone still lists.
  left join users o on o.id = c.owner_id
  order by a.last_activity_at desc, c.id
  limit v_limit offset v_offset;
end;
$$;

comment on function public.admin_analytics_communities(text, integer, integer) is
  'Platform Admin: the communities behind Weekly Active Communities (migration '
  '0069). Gated on is_system_admin() first; only weekly_active_communities is '
  'accepted. Reproduces 0067''s WAC union branch for branch -- match created, '
  'surviving registration, result recorded, tracked match_registered / '
  'match_withdrawn -- and no viewing event. union all plus group by yields the '
  'identical set of ids while carrying a last-activity timestamp to sort by. '
  'No current-is_active filter is added, because 0067 has none.';

revoke execute on function
  public.admin_analytics_communities(text, integer, integer)
  from anon, public;
grant execute on function
  public.admin_analytics_communities(text, integer, integer)
  to authenticated;
grant execute on function
  public.admin_analytics_communities(text, integer, integer)
  to service_role;



-- ============================================================================
-- 3) admin_analytics_matches() -- the matches, and the matches with results
-- ============================================================================
-- Four metrics over one row shape. The distinction that matters is *which
-- timestamp is filtered*:
--
--   * `matches_7d` / `matches_30d` filter `matches.created_at` -- when the
--     match was organised. A match with no result yet is in this list.
--   * `results_7d` / `results_30d` filter `match_results.created_at` -- when
--     the write-up happened. A match organised months ago and written up
--     yesterday belongs to *this week's* results and not to this week's
--     matches.
--
-- Turning the second into the first is the one mistake this function could
-- make, and it is invisible in the output because both produce a plausible
-- list of matches. The `where` below keeps them apart, and a test asserts it.
create or replace function public.admin_analytics_matches(
  p_metric text,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  match_id uuid,
  title text,
  community_id uuid,
  community_name text,
  location text,
  start_at timestamptz,
  status text,
  match_created_at timestamptz,
  result_created_at timestamptz,
  score_a integer,
  score_b integer
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit integer;
  v_offset integer;
  v_since timestamptz;
  v_results boolean;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if p_metric is null or p_metric not in (
    'matches_7d', 'matches_30d', 'results_7d', 'results_30d'
  ) then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_results := p_metric in ('results_7d', 'results_30d');
  v_since := case
               when p_metric in ('matches_7d', 'results_7d')
                 then now() - interval '7 days'
               else now() - interval '30 days'
             end;

  return query
    select
      m.id,
      m.title,
      m.community_id,
      c.name,
      m.location,
      m.start_at,
      m.status,
      m.created_at,
      res.created_at,
      res.team_a_score,
      res.team_b_score
    from matches m
    -- LEFT for the match metrics, where a match may have no result yet. For
    -- the result metrics the `where` below requires a non-null
    -- `res.created_at`, which makes it behave as an inner join -- the rows
    -- being counted are the result rows.
    left join match_results res on res.match_id = m.id
    -- LEFT, though `matches.community_id` is a foreign key and cannot dangle.
    -- It costs nothing and it means no future schema change can make a counted
    -- match vanish from its own list.
    left join communities c on c.id = m.community_id
    where (not v_results and m.created_at >= v_since)
       or (v_results and res.created_at >= v_since)
    -- Ordered by whichever timestamp the metric is about, so the newest thing
    -- that actually happened is first in both cases.
    order by case when v_results then res.created_at else m.created_at end desc,
             m.id
    limit v_limit offset v_offset;
end;
$$;

comment on function public.admin_analytics_matches(text, integer, integer) is
  'Platform Admin: the matches behind Matches 7d/30d and Results 7d/30d '
  '(migration 0069). Gated on is_system_admin() first. Match metrics filter '
  'matches.created_at; result metrics filter match_results.created_at -- a '
  'match organised long ago and written up this week belongs to the results '
  'list, not the matches list. Limit clamped 1..100.';

revoke execute on function public.admin_analytics_matches(text, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_matches(text, integer, integer)
  to authenticated;
grant execute on function public.admin_analytics_matches(text, integer, integer)
  to service_role;



-- ============================================================================
-- 4) admin_analytics_registrations() -- one row per event, never per person
-- ============================================================================
-- **The Overview counts events, so this lists events.** `count(*) from
-- product_events where event_name = 'match_registered'` is what the card shows;
-- a player who registered for three matches contributed three to that number
-- and appears three times here. There is deliberately no `distinct` anywhere in
-- this function, and a test asserts its absence -- de-duplicating by user would
-- produce a list shorter than the number above it, with nothing to explain the
-- gap.
--
-- Every context join is LEFT. `product_events` has no foreign keys, so the
-- user, the match and the community named by an event may each be gone; the
-- event was counted regardless and must be listed regardless.
create or replace function public.admin_analytics_registrations(
  p_period_days integer,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  event_id uuid,
  user_id uuid,
  full_name text,
  email text,
  match_id uuid,
  match_title text,
  community_id uuid,
  community_name text,
  created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_limit integer;
  v_offset integer;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  -- Only the two windows the Overview actually shows. Anything else would be a
  -- figure with no card to agree with.
  if p_period_days is null or p_period_days not in (7, 30) then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  return query
    select
      pe.id,
      pe.user_id,
      u.full_name,
      au.email::text,
      pe.match_id,
      m.title,
      -- The event carries a community only when the recording screen already
      -- knew one; the match always knows. Falling back to the match's
      -- community resolves the same fact from the row the event points at
      -- rather than inventing one, and it cannot change the row count -- only
      -- how many rows can be labelled.
      coalesce(pe.community_id, m.community_id),
      c.name,
      pe.created_at
    from product_events pe
    left join users u on u.id = pe.user_id
    left join auth.users au on au.id = pe.user_id
    left join matches m on m.id = pe.match_id
    left join communities c on c.id = coalesce(pe.community_id, m.community_id)
    where pe.event_name = 'match_registered'
      and pe.created_at >= now() - (p_period_days * interval '1 day')
    order by pe.created_at desc, pe.id
    limit v_limit offset v_offset;
end;
$$;

comment on function public.admin_analytics_registrations(integer, integer, integer) is
  'Platform Admin: the individual match_registered events behind Registrations '
  '7d/30d (migration 0069). Gated on is_system_admin() first; p_period_days '
  'accepts 7 or 30 only. ONE ROW PER EVENT and no DISTINCT anywhere -- the '
  'Overview counts events, so one player registering three times is three '
  'rows. Every context join is LEFT because product_events has no foreign '
  'keys: a deleted user, match or community leaves the event standing with a '
  'null label. community_id falls back to the match''s community, which '
  'changes labelling only and never the row count.';

revoke execute on function
  public.admin_analytics_registrations(integer, integer, integer)
  from anon, public;
grant execute on function
  public.admin_analytics_registrations(integer, integer, integer)
  to authenticated;
grant execute on function
  public.admin_analytics_registrations(integer, integer, integer)
  to service_role;



-- ============================================================================
-- 5) admin_get_community_inspection() -- a community, as an administrator reads
-- ============================================================================
-- **Inspection, not membership.** This exists so a System Admin can look at a
-- community they are not in, without the product having to weaken the member
-- screens to let them. `CommunityDetailsScreen` is built out of a member's
-- reads -- the roster, the dashboard, the leaderboards -- and every one of them
-- is role-checked in the database; making it reachable for a System Admin would
-- mean loosening those checks, which is a far larger change than "show me the
-- facts about this community".
--
-- So this returns facts and grants nothing. Calling it does not make the caller
-- a member, does not create a `community_members` row, and does not let any
-- other RPC behave differently afterwards.
--
-- **The join code is deliberately absent.** It is the credential a
-- CODE_REQUIRED community is entered with (`0056` revoked SELECT on the column
-- for exactly that reason), and an inspection surface has no use for it.
create or replace function public.admin_get_community_inspection(
  p_community_id uuid
)
returns table (
  community_id uuid,
  name text,
  description text,
  join_policy text,
  logo_url text,
  created_at timestamptz,
  owner_id uuid,
  owner_name text,
  member_count bigint,
  match_count bigint,
  is_active boolean,
  suspended_at timestamptz,
  suspension_reason text
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if not exists (select 1 from communities c where c.id = p_community_id) then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  return query
    select
      c.id,
      c.name,
      c.description,
      c.join_policy,
      c.logo_url,
      c.created_at,
      c.owner_id,
      o.full_name,
      (select count(*) from community_members cm where cm.community_id = c.id),
      (select count(*) from matches m where m.community_id = c.id),
      c.is_active,
      c.suspended_at,
      c.suspension_reason
    from communities c
    left join users o on o.id = c.owner_id
    where c.id = p_community_id;
end;
$$;

comment on function public.admin_get_community_inspection(uuid) is
  'Platform Admin: one community, read only (migration 0069). Gated on '
  'is_system_admin() as the first executable statement; COMMUNITY_NOT_FOUND '
  'for an unknown id. Grants the caller no community role and creates no '
  'membership -- it returns facts and nothing else. join_code is deliberately '
  'not exposed: it is the credential a CODE_REQUIRED community is entered '
  'with.';

revoke execute on function public.admin_get_community_inspection(uuid)
  from anon, public;
grant execute on function public.admin_get_community_inspection(uuid)
  to authenticated;
grant execute on function public.admin_get_community_inspection(uuid)
  to service_role;



-- ============================================================================
-- 6) admin_get_match_inspection() -- a match, as an administrator reads it
-- ============================================================================
-- The same principle as section 5, for a match. Facts only: what it is, whose
-- it is, when and where, how many are registered, and how it finished if it
-- has. No register, no withdraw, no roster, no team generation, no result
-- entry -- none of which this function could enable in any case, because it
-- returns rows and grants nothing.
--
-- The MVP is included because it is part of "how it finished" and is cleanly
-- available: `match_results.mvp_user_id` is a plain reference to `users`. The
-- join is LEFT so a deleted account leaves the score standing.
create or replace function public.admin_get_match_inspection(
  p_match_id uuid
)
returns table (
  match_id uuid,
  title text,
  description text,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  status text,
  community_id uuid,
  community_name text,
  created_at timestamptz,
  created_by uuid,
  creator_name text,
  registration_count bigint,
  starting_players integer,
  max_registration integer,
  score_a integer,
  score_b integer,
  result_created_at timestamptz,
  mvp_name text
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if not exists (select 1 from matches m where m.id = p_match_id) then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  return query
    select
      m.id,
      m.title,
      m.description,
      m.location,
      m.start_at,
      m.end_at,
      m.status,
      m.community_id,
      c.name,
      m.created_at,
      m.created_by,
      creator.full_name,
      (select count(*) from match_registrations r where r.match_id = m.id),
      m.starting_players,
      m.max_registration,
      res.team_a_score,
      res.team_b_score,
      res.created_at,
      mvp.full_name
    from matches m
    left join communities c on c.id = m.community_id
    left join users creator on creator.id = m.created_by
    left join match_results res on res.match_id = m.id
    left join users mvp on mvp.id = res.mvp_user_id
    where m.id = p_match_id;
end;
$$;

comment on function public.admin_get_match_inspection(uuid) is
  'Platform Admin: one match, read only (migration 0069). Gated on '
  'is_system_admin() as the first executable statement; MATCH_NOT_FOUND for an '
  'unknown id. Facts only -- no registration, roster, team-generation or '
  'result-entry path exists here or is unlocked by it, and the caller is '
  'granted no community role. Every context join is LEFT so a deleted '
  'community, creator or MVP leaves the match standing.';

revoke execute on function public.admin_get_match_inspection(uuid)
  from anon, public;
grant execute on function public.admin_get_match_inspection(uuid)
  to authenticated;
grant execute on function public.admin_get_match_inspection(uuid)
  to service_role;



-- ============================================================================
-- 7) What this migration did not do
-- ============================================================================
--   * **No table, column, index, constraint, type or view.** Six functions and
--     their grants are the whole file.
--   * **No DML.** No INSERT, UPDATE, DELETE, TRUNCATE or backfill.
--   * **No metric was redefined.** `admin_analytics_overview()` (`0067`) is
--     untouched; every window, event name and time zone above is copied from
--     it rather than restated in different words.
--   * **No analytics event was added.** The ten approved names in
--     `product_events` are unchanged, and nothing here writes an event.
--   * `product_events`, `admin_audit_log` and `auth.users` -- no policy, no
--     RLS change, and no privilege granted on any of them to any client role.
--     Everything a client sees arrives through a `security definer` function
--     gated on `is_system_admin()`.
--   * `admin_suspend_*` / `admin_reactivate_*` (`0064`, `0065`),
--     `admin_delete_*` (`0017`), `record_admin_audit` (`0062`),
--     `record_product_event` (`0067`), `admin_user_activity_summary`,
--     `admin_user_activity_timeline`, `admin_list_audit_log` (`0068`) --
--     unchanged in definition and in privilege.
--   * **No System Admin was granted a community role.** No
--     `community_members` row is created or implied by anything above.
--   * `statistics_period_zone()` (`0028`) -- read, never redefined. Still
--     FROZEN.
