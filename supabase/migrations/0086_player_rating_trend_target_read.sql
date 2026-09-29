-- ============ migrations/0086_player_rating_trend_target_read.sql ============
-- Additive overload for a target player. The no-argument 0085 function stays
-- untouched for compatibility; Staging will adopt this target-aware contract.
--
-- Read only: no tables, rows, triggers, policies or existing functions change.

create or replace function public.player_rating_trend_v1(
  p_user_id uuid
)
returns table (
  matches_count integer,
  rating_delta numeric
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

  -- Match the authenticated player-profile read population: the target must
  -- be an active account. No rating-history rows or match details leave this
  -- function; it returns only one aggregate.
  if not exists (
    select 1 from users u
    where u.id = p_user_id
      and u.is_active
  ) then
    raise exception 'USER_NOT_FOUND';
  end if;

  return query
  with recent_matches as (
    select f.match_id
    from player_recent_form(p_user_id, 5) f
  ),
  per_match as (
    select
      rm.match_id,
      coalesce(sum(rh.delta), 0::numeric) as net_delta
    from recent_matches rm
    left join rating_history rh
      on rh.match_id = rm.match_id
     and rh.user_id = p_user_id
    group by rm.match_id
  )
  select
    count(*)::integer,
    coalesce(sum(pm.net_delta), 0::numeric)::numeric(8,3)
  from per_match pm;
end;
$$;

comment on function public.player_rating_trend_v1(uuid) is
  'Wave 1 target-aware rating trend. Authenticated read of one active player, '
  'returning only the net rating movement across the same up-to-five completed '
  'matches used by Recent Form. All rating_history rows per match are netted, '
  'so corrections and reversals remain authoritative.';

revoke execute on function public.player_rating_trend_v1(uuid)
  from anon, public;
grant execute on function public.player_rating_trend_v1(uuid)
  to authenticated;
grant execute on function public.player_rating_trend_v1(uuid)
  to service_role;
