-- ============ migrations/0087_admin_analytics_drilldowns_v2.sql ============
-- Additive drill-downs aligned exactly with admin_analytics_overview_v2().
--
-- Read-only. No existing RPC is replaced, no row is written, and Production
-- clients remain on the V1 contracts until explicitly moved.

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
    (select max(pe.created_at)
       from product_events pe
       where pe.user_id = t.user_id),
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


create or replace function public.admin_analytics_communities_v2(
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
  v_day_start timestamptz;
  v_current_7d_start timestamptz;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_metric is null or p_metric <> 'weekly_active_communities' then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_day_start :=
    date_trunc('day', now() at time zone statistics_period_zone())
      at time zone statistics_period_zone();
  v_current_7d_start := v_day_start - interval '6 days';

  return query
  with activity as (
    select m.community_id, m.created_at as at
    from matches m
    where not m.is_historical
      and m.created_at >= v_current_7d_start

    union all

    select m.community_id, r.created_at
    from match_registrations r
    join matches m on m.id = r.match_id
    where not m.is_historical
      and r.created_at >= v_current_7d_start

    union all

    select m.community_id, res.created_at
    from match_results res
    join matches m on m.id = res.match_id
    where not m.is_historical
      and res.created_at >= v_current_7d_start

    union all

    select pe.community_id, pe.created_at
    from product_events pe
    join communities c on c.id = pe.community_id
    where pe.event_name in ('match_registered', 'match_withdrawn')
      and pe.created_at >= v_current_7d_start
      and pe.community_id is not null
  ),
  active as (
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
  from active a
  join communities c on c.id = a.community_id
  left join users o on o.id = c.owner_id
  order by a.last_activity_at desc, c.id
  limit v_limit offset v_offset;
end;
$$;

revoke execute on function public.admin_analytics_communities_v2(text, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_communities_v2(text, integer, integer)
  to authenticated, service_role;


create or replace function public.admin_analytics_matches_v2(
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
  v_day_start timestamptz;
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

  v_day_start :=
    date_trunc('day', now() at time zone statistics_period_zone())
      at time zone statistics_period_zone();
  v_since := case
    when p_metric in ('matches_7d', 'results_7d')
      then v_day_start - interval '6 days'
    else v_day_start - interval '29 days'
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
  left join match_results res on res.match_id = m.id
  left join communities c on c.id = m.community_id
  where not m.is_historical
    and (
      (not v_results and m.created_at >= v_since)
      or (v_results and res.created_at >= v_since)
    )
  order by case when v_results then res.created_at else m.created_at end desc,
           m.id
  limit v_limit offset v_offset;
end;
$$;

revoke execute on function public.admin_analytics_matches_v2(text, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_matches_v2(text, integer, integer)
  to authenticated, service_role;


create or replace function public.admin_analytics_registrations_v2(
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
  v_day_start timestamptz;
  v_since timestamptz;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_period_days is null or p_period_days not in (7, 30) then
    raise exception 'INVALID_ADMIN_ANALYTICS_METRIC';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_day_start :=
    date_trunc('day', now() at time zone statistics_period_zone())
      at time zone statistics_period_zone();
  v_since := case
    when p_period_days = 7 then v_day_start - interval '6 days'
    else v_day_start - interval '29 days'
  end;

  return query
  select
    pe.id,
    pe.user_id,
    u.full_name,
    au.email::text,
    pe.match_id,
    m.title,
    coalesce(pe.community_id, m.community_id),
    c.name,
    pe.created_at
  from product_events pe
  left join users u on u.id = pe.user_id
  left join auth.users au on au.id = pe.user_id
  left join matches m on m.id = pe.match_id
  left join communities c on c.id = coalesce(pe.community_id, m.community_id)
  where pe.event_name = 'match_registered'
    and pe.created_at >= v_since
  order by pe.created_at desc, pe.id
  limit v_limit offset v_offset;
end;
$$;

revoke execute on function public.admin_analytics_registrations_v2(integer, integer, integer)
  from anon, public;
grant execute on function public.admin_analytics_registrations_v2(integer, integer, integer)
  to authenticated, service_role;
