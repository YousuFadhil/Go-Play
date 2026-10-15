-- ============================================================================
-- 0105 -- A former member's record stays history, not a current ranking
-- ============================================================================
-- Migration 0104 made leaving a community possible and kept everything a
-- member did there: a played match is history (DD-21), and a statistics row
-- with anything counted in it survives the membership. What it left open is
-- where that surviving row still SHOWS. Today it shows in every ranking of the
-- community, as though the player were still in it.
--
-- The Product Owner's rule (2026-10-15, DD-21 phase 2):
--
--   * the community's current rankings show current members only -- the five
--     boards and the three leaders of the Statistics tab, the public Top
--     Players, and the read model below;
--   * the record itself is history and stays exactly as it is: match details,
--     the Team of the Period, and the community's totals (goals, MVPs, players
--     who played) keep counting what a former member did;
--   * nothing is deleted. A former member who joins again appears again, with
--     the same record, because the row was never removed.
--
-- The five boards of the Statistics tab already ranked current members: the
-- application builds them from the member roster, not from these rows. What
-- still ranked a former member there were the summary card's three leaders,
-- which the application now draws from the roster as well, leaving the totals
-- untouched. The two database objects below are rankings and nothing else, so
-- they are filtered here.
--
-- "Still a member" is a `community_members` row for the same community and
-- user, the same test `has_community_role` makes. No column, index or grant
-- changes: `community_members` is keyed on (community_id, user_id).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- public_community_top_players -- effective definition from `0093`.
-- CHANGED (0105): current members only. Every other line is byte-preserved;
-- `create or replace` keeps the grants 0093 wrote (anon and authenticated).
create or replace function public.public_community_top_players(
  p_community_id uuid
)
returns table (
  community_id uuid,
  user_id uuid,
  display_name text,
  avatar_path text,
  overall_rating numeric,
  matches_played int,
  goals int,
  mvp_count int
)
language sql
security definer
stable
set search_path = ''
as $$
  select
    cs.community_id,
    cs.user_id,
    u.full_name::text,
    u.avatar_path::text,
    coalesce(u.overall_rating, 5.0)::numeric(5,3),
    cs.matches_played::int,
    cs.goals::int,
    cs.mvp_count::int
  from public.community_statistics cs
  join public.users u       on u.id = cs.user_id and u.is_active
  join public.communities c on c.id = cs.community_id and c.is_active
  where cs.community_id = p_community_id
    and cs.period_type = 'overall'
    -- CHANGED (0105): a former member's record is history, not a ranking.
    and exists (
      select 1 from public.community_members cm
      where cm.community_id = cs.community_id and cm.user_id = cs.user_id
    )
  order by coalesce(u.overall_rating, 5.0) desc,
           cs.goals desc,
           cs.mvp_count desc,
           u.full_name collate "C" asc,
           cs.user_id asc
  limit 11;
$$;

comment on function public.public_community_top_players(uuid) is
  'The Top 11 players of one active community, for the public community page: '
  'display name, picture path, Global Rating and three career counters, '
  'ranked by rating, then goals, then MVPs, then name. Active players who are '
  'still members of an active community only (a former member''s record is '
  'history -- migration 0105); a user id only for a player whose public profile '
  'exists. No phone, email, date of birth, auth identifier, join code or '
  'Professional Guest. Takes no limit -- the cap is 11. Executable by anon -- '
  'see migration 0093.';

-- ---------------------------------------------------------------------------
-- v_football_community_player_stats -- effective definition from `0073`.
-- CHANGED (0105): current members only. Same columns in the same order, so
-- `create or replace view` applies and keeps the grants 0073 wrote.
create or replace view public.v_football_community_player_stats as
select
  cs.community_id,
  cs.user_id,
  u.full_name                             as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  coalesce(u.overall_rating, 5.0)::numeric(5,3) as overall_rating,
  cs.matches_played,
  cs.wins,
  cs.draws,
  cs.losses,
  cs.goals,
  cs.mvp_count
from public.community_statistics cs
join public.users u       on u.id = cs.user_id
join public.communities c on c.id = cs.community_id and c.is_active
where cs.period_type = 'overall'
  -- CHANGED (0105): a former member's record is history, not a ranking.
  and exists (
    select 1 from public.community_members cm
    where cm.community_id = cs.community_id and cm.user_id = cs.user_id
  );

comment on view public.v_football_community_player_stats is
  'Cycle 2 read model: one row per current member with an all-time record in a '
  'community -- the counters the leaderboards rank on, plus the Global Rating. '
  'An account suspension does not erase the player''s football identity or '
  'statistics, so a suspended member still appears here; a former member does '
  'not, because their record is history rather than a ranking (migration 0105). '
  'Inactive communities remain excluded from the public surface. See migrations '
  '0057, 0063 and 0105.';
