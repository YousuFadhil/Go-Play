-- ============ migrations/0085_intelligence_wave1_read_models.sql ============
-- Go Play Intelligence Wave 1: additive read models only.
--
-- Safety contract:
--   * no INSERT / UPDATE / DELETE;
--   * no table, view, policy, trigger or existing function is changed;
--   * no backfill;
--   * no Production read contract is replaced;
--   * all new contracts are separately named and can be adopted by Staging
--     without changing the current Production client.
--
-- Sources and definitions are frozen in:
-- Docs/engineering/INTELLIGENCE_METRIC_CONTRACT_V1.md


-- ============================================================================
-- 1) player_rating_trend_v1()
-- ============================================================================
-- The signed-in player's recent rating direction: net rating movement across
-- the same most-recent five completed matches used by Recent Form.
--
-- This is SECURITY DEFINER deliberately. Direct rating_history SELECT is
-- membership-scoped, so a player who later leaves a community can lose read
-- access to their own old rating rows. The read below is narrower: it accepts
-- no user id and can only return auth.uid()'s aggregate.
create or replace function public.player_rating_trend_v1()
returns table (
  matches_count integer,
  rating_delta numeric
)
language plpgsql
security definer
stable
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

  return query
  with recent_matches as (
    select f.match_id
    from player_recent_form(v_user_id, 5) f
  ),
  per_match as (
    select
      rm.match_id,
      coalesce(sum(rh.delta), 0::numeric) as net_delta
    from recent_matches rm
    left join rating_history rh
      on rh.match_id = rm.match_id
     and rh.user_id = v_user_id
    group by rm.match_id
  )
  select
    count(*)::integer,
    coalesce(sum(pm.net_delta), 0::numeric)::numeric(8,3)
  from per_match pm;
end;
$$;

comment on function public.player_rating_trend_v1() is
  'Wave 1 read model. Returns the signed-in active player''s net rating '
  'movement across the same up-to-five completed matches used by Recent Form. '
  'No user-id argument: it can return only auth.uid()''s aggregate. Corrections '
  'and reversals remain honest because all rating_history deltas for each match '
  'are netted before the five-match sum.';

revoke execute on function public.player_rating_trend_v1()
  from anon, public;
grant execute on function public.player_rating_trend_v1()
  to authenticated;
grant execute on function public.player_rating_trend_v1()
  to service_role;


-- ============================================================================
-- 2) community_insights_v1(uuid)
-- ============================================================================
-- Organizer-only rolling 30-day Community Intelligence from existing evidence.
--
-- Two measures are intentionally provisional:
--   * Active Members uses final/current match_team_assignments as the played
--     proxy until Participation Truth exists.
--   * Capacity Utilization uses those same assignments as final lineup seats.
--
-- Historical imports are excluded from every match-based measure.
create or replace function public.community_insights_v1(
  p_community_id uuid
)
returns table (
  eligible_members integer,
  active_members_30d integer,
  participation_rate_30d numeric,
  matches_30d integer,
  matches_per_week numeric,
  avg_capacity_utilization numeric,
  guest_dependency numeric
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not has_active_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return query
  with
    eligible_members_set as (
      select cm.user_id
      from community_members cm
      join users u
        on u.id = cm.user_id
       and u.is_active
      where cm.community_id = p_community_id
    ),

    eligible_matches as (
      select m.id, m.starting_players
      from matches m
      where m.community_id = p_community_id
        and not m.is_historical
        and (m.status = 'completed' or m.end_at <= now())
        and m.start_at >= now() - interval '30 days'
    ),

    assignments as (
      select
        a.id,
        a.match_id,
        a.user_id,
        a.professional_guest_id
      from match_team_assignments a
      join eligible_matches em on em.id = a.match_id
    ),

    member_counts as (
      select
        (select count(*) from eligible_members_set)::integer
          as eligible_members,
        (
          select count(distinct a.user_id)
          from assignments a
          join eligible_members_set em on em.user_id = a.user_id
          where a.user_id is not null
        )::integer as active_members
    ),

    match_lineups as (
      select
        em.id,
        em.starting_players,
        count(a.id)::integer as lineup_count
      from eligible_matches em
      left join assignments a on a.match_id = em.id
      group by em.id, em.starting_players
    ),

    match_counts as (
      select
        count(*)::integer as matches_30d,
        round(count(*)::numeric * 7 / 30, 2) as matches_per_week,
        round(
          avg(
            100.0 * ml.lineup_count::numeric
              / nullif(ml.starting_players, 0)::numeric
          ),
          1
        ) as avg_capacity_utilization
      from match_lineups ml
    ),

    assignment_counts as (
      select
        count(*)::numeric as total_assignments,
        count(*) filter (
          where professional_guest_id is not null
        )::numeric as guest_assignments
      from assignments
    )

  select
    mc.eligible_members,
    mc.active_members,
    case
      when mc.eligible_members = 0 then null::numeric
      else round(
        mc.active_members::numeric * 100 / mc.eligible_members::numeric,
        1
      )
    end,
    mt.matches_30d,
    mt.matches_per_week,
    mt.avg_capacity_utilization,
    case
      when ac.total_assignments = 0 then null::numeric
      else round(ac.guest_assignments * 100 / ac.total_assignments, 1)
    end
  from member_counts mc
  cross join match_counts mt
  cross join assignment_counts ac;
end;
$$;

comment on function public.community_insights_v1(uuid) is
  'Wave 1 organizer-only rolling-30-day Community Intelligence. Excludes '
  'historical matches. Active participation and capacity use '
  'match_team_assignments as the provisional played/final-lineup proxy until '
  'Participation Truth is implemented. Returns aggregates only; exposes no '
  'member or match rows.';

revoke execute on function public.community_insights_v1(uuid)
  from anon, public;
grant execute on function public.community_insights_v1(uuid)
  to authenticated;
grant execute on function public.community_insights_v1(uuid)
  to service_role;


-- ============================================================================
-- 3) admin_analytics_overview_v2()
-- ============================================================================
-- Product-Owner analytics corrected around the Wave 0 Source-of-Truth contract.
--
-- Differences from V1:
--   * calendar windows use the product statistics timezone consistently;
--   * imported historical matches/results do not count as product activity;
--   * registration counts are explicitly named TRACKED registrations because
--     current telemetry is incomplete and the business row disappears on
--     withdrawal;
--   * V1 remains untouched for the current Production client.
create or replace function public.admin_analytics_overview_v2()
returns table (
  total_users bigint,
  new_users_today bigint,
  new_users_7d bigint,
  new_users_30d bigint,
  dau bigint,
  wau bigint,
  mau bigint,
  weekly_active_communities bigint,
  matches_created_7d bigint,
  matches_created_30d bigint,
  tracked_registrations_7d bigint,
  tracked_registrations_30d bigint,
  results_recorded_7d bigint,
  results_recorded_30d bigint,
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
  v_current_7d_start timestamptz;
  v_previous_7d_start timestamptz;
  v_30d_start timestamptz;
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;

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
      select distinct s.user_id
      from sessions s
      where s.created_at >= v_previous_7d_start
        and s.created_at < v_current_7d_start
    ),

    returning_week as (
      select p.user_id
      from previous_week p
      where exists (
        select 1
        from sessions s
        where s.user_id = p.user_id
          and s.created_at >= v_current_7d_start
      )
    ),

    active_communities as (
      select m.community_id
      from matches m
      where not m.is_historical
        and m.created_at >= v_current_7d_start

      union

      select m.community_id
      from match_registrations r
      join matches m on m.id = r.match_id
      where not m.is_historical
        and r.created_at >= v_current_7d_start

      union

      select m.community_id
      from match_results res
      join matches m on m.id = res.match_id
      where not m.is_historical
        and res.created_at >= v_current_7d_start

      union

      -- Telemetry is supplementary evidence for a registration or withdrawal
      -- that the surviving registration table may no longer carry. It is not
      -- used as the authoritative registration count.
      select pe.community_id
      from product_events pe
      join communities c on c.id = pe.community_id
      where pe.event_name in ('match_registered', 'match_withdrawn')
        and pe.created_at >= v_current_7d_start
        and pe.community_id is not null
    )

  select
    (select count(*) from users)::bigint,

    (select count(*) from users u
       where u.created_at >= v_day_start)::bigint,
    (select count(*) from users u
       where u.created_at >= v_current_7d_start)::bigint,
    (select count(*) from users u
       where u.created_at >= v_30d_start)::bigint,

    (select count(distinct s.user_id) from sessions s
       where s.created_at >= v_day_start)::bigint,
    (select count(distinct s.user_id) from sessions s
       where s.created_at >= v_current_7d_start)::bigint,
    (select count(distinct s.user_id) from sessions s)::bigint,

    (select count(distinct a.community_id)
       from active_communities a)::bigint,

    (select count(*) from matches m
       where not m.is_historical
         and m.created_at >= v_current_7d_start)::bigint,
    (select count(*) from matches m
       where not m.is_historical
         and m.created_at >= v_30d_start)::bigint,

    (select count(*) from product_events pe
       where pe.event_name = 'match_registered'
         and pe.created_at >= v_current_7d_start)::bigint,
    (select count(*) from product_events pe
       where pe.event_name = 'match_registered'
         and pe.created_at >= v_30d_start)::bigint,

    (select count(*)
       from match_results res
       join matches m on m.id = res.match_id
       where not m.is_historical
         and res.created_at >= v_current_7d_start)::bigint,
    (select count(*)
       from match_results res
       join matches m on m.id = res.match_id
       where not m.is_historical
         and res.created_at >= v_30d_start)::bigint,

    (select count(*) from previous_week)::bigint,
    (select count(*) from returning_week)::bigint,

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

comment on function public.admin_analytics_overview_v2() is
  'Wave 1 additive Platform Admin read model. Calendar windows use '
  'statistics_period_zone(); historical imported matches/results are excluded '
  'from product activity; registration telemetry is explicitly returned as '
  'tracked_registrations because current tracking is incomplete. V1 is '
  'unchanged for the Production client.';

revoke execute on function public.admin_analytics_overview_v2()
  from anon, public;
grant execute on function public.admin_analytics_overview_v2()
  to authenticated;
grant execute on function public.admin_analytics_overview_v2()
  to service_role;


-- ============================================================================
-- 4) Explicit non-actions
-- ============================================================================
-- No table changed.
-- No row written.
-- No existing function replaced.
-- No trigger, policy, view, index or privilege on an existing object changed.
-- No historical data fabricated.
