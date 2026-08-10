-- Sprint DB-01: Database Views
--
-- Read-only views over the approved schema (migrations 0001-0024). This
-- migration adds views and nothing else: no table is altered, no function is
-- created or replaced, no trigger is added and no policy is touched.
--
-- Three rules govern every view here:
--
-- 1) READ ONLY. No view writes, and none is auto-updatable in a way the app
--    is meant to use: every one either aggregates, joins beyond a single key
--    or projects derived columns. Writes stay on the approved RPCs.
--
-- 2) NO BUSINESS LOGIC. A view composes columns that already exist. It does
--    not decide eligibility, allocate seats, move a rating or record a
--    result. The one derived flag present -- `is_out_of_position` -- is
--    derived rather than stored by explicit design (BTGE spec 5.1: it is
--    exactly `assignment_basis = 'TRANSITION'`, and storing it would let the
--    two disagree).
--
-- 3) SECURITY INVOKER. `security_invoker = on` (PostgreSQL 15+, project runs
--    17) makes every view evaluate the base tables' RLS as the *caller*,
--    not as the view owner. Without it a view is a hole straight through
--    every policy migrations 0005-0024 established. Each view is therefore
--    readable exactly when its sources are, and no view restates a policy.
--
-- Naming: `v_` prefix; column names match the source columns except where a
-- join makes the source ambiguous, in which case the table is the prefix
-- (`community_name`, `match_start_at`).
--
-- `create or replace view` is used throughout: this migration is re-runnable
-- as written. Note the PostgreSQL restriction -- replace may add trailing
-- columns but may not rename, reorder, retype or drop one. A future change of
-- that kind needs an explicit `drop view` in its own migration.
--
-- DEFERRED: `v_leaderboards` is NOT in this migration. The nine approved
-- boards rank on `community_statistics` and `community_ratings`
-- (Leaderboards_Read_Specification 4), both approved-but-unbuilt per
-- 07-Database-Design "Phase Status" 3. The same specification forbids every
-- source that does exist today: the Match domain (2.4) and
-- `player_statistics` (4.2). A board built on what is available would be the
-- wrong board, so none is built. It also gates on three open Product
-- decisions -- LB-X1 (nine boards or fifteen), LB-D1 (zero-valued entries)
-- and LB-D2 (tie-break order). The view belongs with the Level 2 build.

-- ============================================================================
-- 1) v_user_profile
-- Sources: users, player_statistics
-- ============================================================================
-- The profile screen's whole read: identity, playing attributes, the Global
-- Rating and the career counters, in one row.
--
-- `player_statistics` is joined LEFT because the row is created by the result
-- engine on a player's first recorded match, not at signup. A player who has
-- never played has a profile and no counters, and the view says so with
-- nulls rather than inventing zeros -- the counters are absent, which is not
-- the same fact as "played and scored none".
create or replace view public.v_user_profile
with (security_invoker = on) as
select
  u.id                as user_id,
  u.full_name,
  u.phone,
  u.primary_position,
  u.secondary_position,
  u.date_of_birth,
  u.overall_rating,
  u.is_active,
  u.created_at,
  u.updated_at,
  ps.matches_played,
  ps.wins,
  ps.losses,
  ps.draws,
  ps.goals,
  ps.mvp_count,
  ps.updated_at      as statistics_updated_at
from public.users u
left join public.player_statistics ps on ps.user_id = u.id;

comment on view public.v_user_profile is
  'Read model: a player profile -- users joined to the global career counters '
  'in player_statistics. Counters are null until the first recorded result.';

-- ============================================================================
-- 2) v_community_summary
-- Sources: communities, community_members, matches
-- ============================================================================
-- One row per community with the counts a community card shows.
--
-- Scalar subqueries rather than grouped joins: each count is independent, and
-- a single `group by` over three one-to-many relations would multiply rows
-- before it counted them.
--
-- `join_code` is deliberately absent. It is a credential, and a summary read
-- is not where one belongs; the app reads it from `communities` under that
-- table's own policy when it actually needs it.
--
-- This is NOT the ten-figure Community Dashboard. Six of those figures come
-- from `community_statistics` (Community_Dashboard_Read_Specification 4),
-- which is unbuilt -- see the DEFERRED note in this file's header. The four
-- Match-domain figures are here (`total_matches`, `last_match_at`, and the
-- windowed counts are a read away); the statistics figures are not, and are
-- not approximated from another source.
create or replace view public.v_community_summary
with (security_invoker = on) as
select
  c.id            as community_id,
  c.name,
  c.description,
  c.owner_id,
  c.join_policy,
  c.is_active,
  c.created_at,
  c.updated_at,
  (
    select count(*)
    from public.community_members cm
    where cm.community_id = c.id
  )               as member_count,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
  )               as total_matches,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and m.status = 'completed'
  )               as completed_matches,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and m.start_at > now()
      and m.status <> 'completed'
  )               as upcoming_matches,
  (
    select max(m.start_at)
    from public.matches m
    where m.community_id = c.id
  )               as last_match_at
from public.communities c;

comment on view public.v_community_summary is
  'Read model: one row per community with member and match counts. Not the '
  'Community Dashboard -- its statistics figures need the unbuilt Level 2 '
  'tables. join_code is excluded: a credential is not a summary figure.';

-- ============================================================================
-- 3) v_community_members
-- Sources: community_members, users
-- ============================================================================
-- The roster: who is in a community, in what role, with the profile fields a
-- member list displays.
--
-- The join to `users` is INNER. Deletion in this schema is soft
-- (`users.is_active`) and the users policy already returns active profiles
-- only, so an outer join would produce roster rows with a null name for
-- accounts that are deliberately not shown. Consequence worth knowing:
-- `member_count` in v_community_summary counts membership rows, so it can
-- exceed the rows this view returns.
create or replace view public.v_community_members
with (security_invoker = on) as
select
  cm.id             as membership_id,
  cm.community_id,
  cm.user_id,
  cm.role,
  cm.created_at     as joined_at,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  u.is_active       as user_is_active
from public.community_members cm
join public.users u on u.id = cm.user_id;

comment on view public.v_community_members is
  'Read model: community roster -- membership joined to the member profile. '
  'Inner join, so profiles hidden by the users policy do not appear.';

-- ============================================================================
-- 4) v_match_details
-- Sources: matches, communities, users, match_registrations, match_results
-- ============================================================================
-- Everything the match detail header shows, including the recorded result
-- when there is one.
--
-- `match_results` is joined LEFT and `has_result` reports which case a row
-- is: a match with no result is the normal state for anything not yet
-- played, not a missing row.
--
-- `open_slots` is arithmetic over two columns of this same row, not a
-- capacity decision -- allocation stays in `register_for_match`, which locks
-- the match row. `greatest(..., 0)` guards the display only: a caller whose
-- RLS hides registration rows would otherwise see a negative count.
create or replace view public.v_match_details
with (security_invoker = on) as
select
  m.id                  as match_id,
  m.community_id,
  c.name                as community_name,
  m.title,
  m.description,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.starting_players,
  m.max_registration,
  m.created_by,
  cu.full_name          as created_by_name,
  m.created_at,
  m.updated_at,
  coalesce(reg.confirmed_count, 0)  as confirmed_count,
  coalesce(reg.reserve_count, 0)    as reserve_count,
  coalesce(reg.total_count, 0)      as registration_count,
  greatest(m.starting_players - coalesce(reg.confirmed_count, 0), 0)
                                    as open_slots,
  (mr.match_id is not null)         as has_result,
  mr.team_a_score,
  mr.team_b_score,
  mr.mvp_user_id,
  mvp.full_name         as mvp_name,
  mr.recorded_by,
  mr.created_at         as result_recorded_at
from public.matches m
join public.communities c on c.id = m.community_id
join public.users cu on cu.id = m.created_by
left join lateral (
  select
    count(*) filter (where r.status = 'confirmed') as confirmed_count,
    count(*) filter (where r.status = 'reserve')   as reserve_count,
    count(*)                                       as total_count
  from public.match_registrations r
  where r.match_id = m.id
) reg on true
left join public.match_results mr on mr.match_id = m.id
left join public.users mvp on mvp.id = mr.mvp_user_id;

comment on view public.v_match_details is
  'Read model: a match with its community, organizer, registration counts and '
  'recorded result. has_result distinguishes "not yet played" from a missing '
  'row; open_slots is display arithmetic, never the seat allocation.';

-- ============================================================================
-- 5) v_match_registrations
-- Sources: match_registrations, users, matches
-- ============================================================================
-- The registration list, confirmed and reserve alike, with the profile of
-- each registrant and enough of the match to filter and sort without a second
-- read.
--
-- `registration_order` is carried through unchanged: it is the queue position
-- the RPC assigned, and it is what makes promotion order reproducible. The
-- view does not renumber it.
create or replace view public.v_match_registrations
with (security_invoker = on) as
select
  r.id                  as registration_id,
  r.match_id,
  m.community_id,
  r.user_id,
  r.status,
  r.registration_order,
  r.created_at          as registered_at,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  m.title               as match_title,
  m.start_at            as match_start_at,
  m.status              as match_status
from public.match_registrations r
join public.matches m on m.id = r.match_id
join public.users u on u.id = r.user_id;

comment on view public.v_match_registrations is
  'Read model: match registrations (confirmed and reserve) with the '
  'registrant profile and match context. registration_order is the queue '
  'position written by the RPC and is never recomputed here.';

-- ============================================================================
-- 6) v_upcoming_matches
-- Sources: matches, communities, match_registrations
-- ============================================================================
-- The home and community feeds: matches that have not started and are not
-- closed.
--
-- "Upcoming" is `start_at > now()` and a status other than `completed`.
-- `now()` is the transaction timestamp, so every row of one read is measured
-- against one instant.
--
-- Ordering is left to the caller. A view that sorted would impose its order
-- on every consumer, and PostgreSQL is free to ignore an inner ORDER BY in
-- any case.
create or replace view public.v_upcoming_matches
with (security_invoker = on) as
select
  m.id                  as match_id,
  m.community_id,
  c.name                as community_name,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.starting_players,
  m.max_registration,
  m.created_by,
  coalesce(reg.confirmed_count, 0)  as confirmed_count,
  coalesce(reg.reserve_count, 0)    as reserve_count,
  greatest(m.starting_players - coalesce(reg.confirmed_count, 0), 0)
                                    as open_slots
from public.matches m
join public.communities c on c.id = m.community_id
left join lateral (
  select
    count(*) filter (where r.status = 'confirmed') as confirmed_count,
    count(*) filter (where r.status = 'reserve')   as reserve_count
  from public.match_registrations r
  where r.match_id = m.id
) reg on true
where m.start_at > now()
  and m.status <> 'completed';

comment on view public.v_upcoming_matches is
  'Read model: matches starting after now() that are not completed, with '
  'registration counts. Unordered by design -- the caller sorts.';

-- ============================================================================
-- 7) v_match_teams
-- Sources: match_team_assignments, users, matches, match_goals, match_results
-- ============================================================================
-- The lineup that actually played: one row per player per match, with the
-- team, the position and the basis on which it was given.
--
-- `is_out_of_position` is derived, exactly as BTGE spec 5.1 requires -- it is
-- `assignment_basis = 'TRANSITION'` and nothing else. The column is absent
-- from `match_team_assignments` for this reason, and deriving it here is the
-- design working as intended, not logic leaking into a view.
--
-- Goals and the MVP flag join at the same grain: `match_goals` is unique on
-- (match_id, user_id) and `match_results` on match_id, so neither multiplies
-- the lineup. `goals` is null when the player did not score -- not scoring is
-- the absence of a row (0022), and the view does not convert that absence
-- into a zero.
create or replace view public.v_match_teams
with (security_invoker = on) as
select
  a.id                  as assignment_id,
  a.match_id,
  m.community_id,
  a.user_id,
  a.team,
  a.assigned_position,
  a.assignment_basis,
  (a.assignment_basis = 'TRANSITION')   as is_out_of_position,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  g.goals,
  (mr.mvp_user_id = a.user_id)          as is_mvp,
  m.start_at            as match_start_at,
  m.status              as match_status,
  a.created_at,
  a.updated_at
from public.match_team_assignments a
join public.matches m on m.id = a.match_id
join public.users u on u.id = a.user_id
left join public.match_goals g
  on g.match_id = a.match_id and g.user_id = a.user_id
left join public.match_results mr on mr.match_id = a.match_id;

comment on view public.v_match_teams is
  'Read model: the played lineup -- team, assigned position and basis, with '
  'goals and the MVP flag. is_out_of_position is derived from '
  'assignment_basis per BTGE 5.1; goals is null when the player did not score.';

-- ============================================================================
-- 8) v_player_statistics
-- Sources: player_statistics, users
-- ============================================================================
-- The career record: one row per player, across every community they play in,
-- with the Global Rating from `users`.
--
-- The rating is read by joining rather than stored on `player_statistics`
-- (0022, section 5): a copy would be a second number for the same thing, free
-- to disagree with the one the rating engine maintains.
--
-- No win rate, no per-match average, no rank. Each is a definition -- what a
-- draw does to a rate, what an empty record shows -- and a definition is a
-- Product decision, not a projection.
create or replace view public.v_player_statistics
with (security_invoker = on) as
select
  ps.user_id,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.is_active           as user_is_active,
  u.overall_rating,
  ps.matches_played,
  ps.wins,
  ps.losses,
  ps.draws,
  ps.goals,
  ps.mvp_count,
  ps.created_at,
  ps.updated_at
from public.player_statistics ps
join public.users u on u.id = ps.user_id;

comment on view public.v_player_statistics is
  'Read model: global career counters with the current Global Rating joined '
  'from users. No derived rates -- each would be a Product definition.';

-- ============================================================================
-- Privileges
-- ============================================================================
-- Views are reachable through PostgREST as soon as they exist, so the grant
-- is explicit and narrow: `authenticated` only. `anon` gets nothing -- no
-- read in this product is public, and a view left readable by `anon` would be
-- the one place that stopped being true.
--
-- These grants control who may issue the select. `security_invoker = on`
-- controls which rows come back, and every base-table policy still applies.
do $$
declare
  v_view text;
begin
  foreach v_view in array array[
    'v_user_profile',
    'v_community_summary',
    'v_community_members',
    'v_match_details',
    'v_match_registrations',
    'v_upcoming_matches',
    'v_match_teams',
    'v_player_statistics'
  ]
  loop
    execute format('revoke all on public.%I from anon, public', v_view);
    execute format('grant select on public.%I to authenticated', v_view);
  end loop;
end $$;
