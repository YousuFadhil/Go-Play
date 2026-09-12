-- ============ migrations/0073_rating_precision_and_participation.sql ============
-- Rating Engine v2: three-decimal precision, a participation bonus and a draw
-- bonus. Approved by the Product Owner.
--
--     PARTICIPATION +0.005   per real player on the stored lineup
--     WIN           +0.100
--     DRAW          +0.010   now an entry of its own for every real player
--     LOSS          -0.100
--     GOAL          +0.020 each, capped at +0.100 per player per match
--     MVP           +0.050
--
-- Applied and audited in that order -- PARTICIPATION, OUTCOME, GOAL, MVP -- and
-- each step clamped to 0.000..10.000 by `apply_rating_delta`, which records
-- the movement actually applied rather than the one requested.
--
-- ## Precision
--
-- `numeric(5,3)`, not `numeric(4,3)`: the scale leaves one integer digit in a
-- `numeric(4,3)`, and 10.000 has two. Widening from `numeric(4,2)` is exact --
-- 5.32 becomes 5.320 -- so nothing already stored is recalculated.
--
-- ## Why eight views are dropped and recreated
--
-- PostgreSQL will not change the type of a column a view uses, and eight views
-- select `users.overall_rating`. They are dropped by name -- never CASCADE, so
-- an unexpected dependant fails this migration rather than disappearing with
-- it -- and recreated from their current definitions, written out below as
-- static SQL. Each keeps its columns, joins, filters, `security_invoker`
-- setting and comment, and its privileges are replayed exactly as they stand
-- today. Recreated views start from the same default privileges the originals
-- were created under, so the replay lands on the same ACL: access is neither
-- widened nor narrowed.
--
-- Two of them used to cast the rating to `numeric(4,2)`, which would have
-- discarded the third decimal at the read model. They now cast to
-- `numeric(5,3)`. Presenting two decimals is the app's job, not the database's.
--
-- ## Corrections
--
-- `reverse_match_rating_effects` is untouched: it reverses each stored delta
-- exactly, and the correction path then applies the rules in force today. That
-- is the approved current-rule-on-correction policy, with no rule versioning
-- and no backfill.
--
-- ## Not touched
--
-- Period Form Score v1 and everything Team of Period reads are separate by
-- design and are not referenced here: PFS keeps its own frozen weights and has
-- no participation bonus.

-- 1) Drop the eight views that pin the column type -----------------------
drop view public.v_community_members;
drop view public.v_user_profile;
drop view public.v_player_statistics;
drop view public.v_match_registrations;
drop view public.v_match_teams;
drop view public.v_football_match_lineup;
drop view public.v_football_match_participants;
drop view public.v_football_community_player_stats;

-- 2) Three decimals ---------------------------------------------------------------
alter table public.users
  alter column overall_rating type numeric(5,3);

alter table public.rating_history
  alter column delta type numeric(5,3),
  alter column rating_before type numeric(5,3),
  alter column rating_after type numeric(5,3);

-- 3) Two new reasons ----------------------------------------------------------------
-- Dropped by its deterministic name and without `if exists`: a constraint under
-- any other name would leave the old one rejecting every v2 insert, and that
-- must fail here rather than at the first recorded result.
alter table public.rating_history
  drop constraint rating_history_change_reason_check;
alter table public.rating_history
  add constraint rating_history_change_reason_check
    check (change_reason in (
      'PARTICIPATION', 'WIN', 'DRAW', 'LOSS', 'GOAL', 'MVP', 'REVERSAL'
    ));

-- 4) One clamped step ---------------------------------------------------------------
-- `0046`'s function at the new precision. The delta written is the one the clamp
-- let through, which is what makes a reversal exact.
create or replace function public.apply_rating_delta(
  p_user_id uuid,
  p_match_id uuid,
  p_reason text,
  p_delta numeric,
  p_reverses_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before numeric(5,3);
  v_after numeric(5,3);
begin
  if p_user_id is null then return; end if;

  select overall_rating into v_before
  from users where id = p_user_id
  for update;
  if not found then return; end if;

  v_after := least(10.000, greatest(0.000, v_before + p_delta));

  update users set overall_rating = v_after where id = p_user_id;

  insert into rating_history (
    user_id, match_id, change_reason, delta,
    rating_before, rating_after, reverses_id
  )
  values (
    p_user_id, p_match_id, p_reason, v_after - v_before,
    v_before, v_after, p_reverses_id
  );
end;
$$;

revoke execute on function public.apply_rating_delta(uuid, uuid, text, numeric,
  uuid) from anon, authenticated, public;

-- 5) The v2 rules ---------------------------------------------------------------------
create or replace function public.apply_match_rating_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result match_results%rowtype;
  r record;
begin
  select * into v_result from match_results where match_id = p_match_id;
  if not found then return; end if;

  -- PARTICIPATION: once per real player. Grouped, so a lineup that somehow
  -- named a player twice still pays them once. A Professional Guest has no
  -- account and receives nothing (0046).
  for r in
    select a.user_id
    from match_team_assignments a
    where a.match_id = p_match_id
      and a.user_id is not null
    group by a.user_id
    order by a.user_id
  loop
    perform apply_rating_delta(r.user_id, p_match_id, 'PARTICIPATION', 0.005);
  end loop;

  -- OUTCOME: a win, a loss, or a draw -- which is now an entry of its own.
  for r in
    select a.user_id, min(a.team) as team
    from match_team_assignments a
    where a.match_id = p_match_id
      and a.user_id is not null
    group by a.user_id
    order by min(a.team), a.user_id
  loop
    if v_result.team_a_score = v_result.team_b_score then
      perform apply_rating_delta(r.user_id, p_match_id, 'DRAW', 0.010);
    elsif (r.team = 'A' and v_result.team_a_score > v_result.team_b_score)
       or (r.team = 'B' and v_result.team_b_score > v_result.team_a_score) then
      perform apply_rating_delta(r.user_id, p_match_id, 'WIN', 0.100);
    else
      perform apply_rating_delta(r.user_id, p_match_id, 'LOSS', -0.100);
    end if;
  end loop;

  -- GOAL: unchanged. The cap is on the match total, not on each goal.
  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
      and g.user_id is not null
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', least(0.100, 0.020 * r.goals)
    );
  end loop;

  -- MVP: unchanged. A guest named best on the pitch has no user id here.
  if v_result.mvp_user_id is not null then
    perform apply_rating_delta(
      v_result.mvp_user_id, p_match_id, 'MVP', 0.050
    );
  end if;
end;
$$;

revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;

-- 6) The eight views, recreated -------------------------------------------------

-- v_community_members
create view public.v_community_members
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

revoke all on public.v_community_members from anon, public;
grant select on public.v_community_members to authenticated;

-- v_user_profile
create view public.v_user_profile
with (security_invoker = on) as
select
  u.id                as user_id,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.avatar_path,
  ps.matches_played,
  ps.wins,
  ps.losses,
  ps.draws,
  ps.goals,
  ps.mvp_count,
  ps.updated_at       as statistics_updated_at
from public.users u
left join public.player_statistics ps on ps.user_id = u.id;

comment on view public.v_user_profile is
  'Read model: a player identity joined to the global career counters in '
  'player_statistics. Counters are null until the first recorded result. '
  'Carries no phone, no date of birth and no privacy preference -- those are '
  'the owner''s own and are answered by my_profile() (migration 0055).';

revoke all on public.v_user_profile from anon, public, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.v_user_profile from anon, authenticated;
grant select on public.v_user_profile to authenticated;

-- v_player_statistics
create view public.v_player_statistics
with (security_invoker = on) as
select
  u.id                                        as user_id,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.is_active                                 as user_is_active,
  coalesce(u.overall_rating, 5.0)::numeric(5,3) as overall_rating,
  coalesce(ps.matches_played, 0)              as matches_played,
  coalesce(ps.wins, 0)                        as wins,
  coalesce(ps.losses, 0)                      as losses,
  coalesce(ps.draws, 0)                       as draws,
  coalesce(ps.goals, 0)                       as goals,
  coalesce(ps.mvp_count, 0)                   as mvp_count,
  ps.created_at,
  ps.updated_at
from public.users u
left join public.player_statistics ps on ps.user_id = u.id
where u.is_active;

comment on view public.v_player_statistics is
  'Read model: one row per active user -- profile, Global Rating and career '
  'counters, zero until the first recorded result. Counters are COALESCEd '
  'because a player who has played nothing has zeros, not no statistics; '
  'created_at and updated_at stay null for such a player because the counters '
  'row genuinely does not exist yet.';

revoke all on public.v_player_statistics from anon, public;
grant select on public.v_player_statistics to authenticated;

-- v_match_registrations
create view public.v_match_registrations
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
  m.status              as match_status,
  r.professional_guest_id,
  case when r.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end::text  as participant_type,
  coalesce(u.full_name, g.display_name)           as display_name,
  r.admin_order,
  row_number() over (
    partition by r.match_id
    order by r.admin_order nulls last,
             (r.user_id is null), r.registration_order
  )::int                                          as roster_position
from public.match_registrations r
join public.matches m on m.id = r.match_id
left join public.users u on u.id = r.user_id
left join public.match_professional_guests g on g.id = r.professional_guest_id;

comment on view public.v_match_registrations is
  'Read model: match registrations (confirmed and reserve) for both kinds of '
  'participant. participant_type distinguishes USER from PROFESSIONAL; '
  'display_name is what to render, while full_name and the profile columns are '
  'null for a guest. registration_order is the queue position written by the '
  'RPC and is never recomputed here. roster_position is the authoritative '
  'participant order -- the owner/admin arrangement when the match has one, '
  'and arrival order otherwise -- and is the same expression rebalance_roster '
  'cuts at starting_players.';

revoke all on public.v_match_registrations from anon, public;
grant select on public.v_match_registrations to authenticated;

-- v_match_teams
create view public.v_match_teams
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
  coalesce(
    (mr.mvp_user_id is not null and mr.mvp_user_id = a.user_id)
    or (mr.mvp_professional_guest_id is not null
        and mr.mvp_professional_guest_id = a.professional_guest_id),
    false)                              as is_mvp,
  m.start_at            as match_start_at,
  m.status              as match_status,
  a.created_at,
  a.updated_at,
  a.professional_guest_id,
  case when a.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end::text  as participant_type,
  coalesce(u.full_name, pg.display_name)          as display_name
from public.match_team_assignments a
join public.matches m on m.id = a.match_id
left join public.users u on u.id = a.user_id
left join public.match_professional_guests pg on pg.id = a.professional_guest_id
left join public.match_goals g
  on g.match_id = a.match_id
 and ((g.user_id is not null and g.user_id = a.user_id)
   or (g.professional_guest_id is not null
       and g.professional_guest_id = a.professional_guest_id))
left join public.match_results mr on mr.match_id = a.match_id;

comment on view public.v_match_teams is
  'Read model: the played lineup for both kinds of participant -- team, '
  'assigned position and basis, with goals and the MVP flag. participant_type '
  'distinguishes USER from PROFESSIONAL and display_name is what to render. '
  'is_out_of_position is derived from assignment_basis per BTGE 5.1, so a GUEST '
  'basis is never out of position; goals is null when the player did not score.';

revoke all on public.v_match_teams from anon, public;
grant select on public.v_match_teams to authenticated;

-- v_football_match_lineup (non-invoker, as it is today)
create view public.v_football_match_lineup as
select
  a.match_id,
  m.community_id,
  a.team,
  a.assigned_position,
  a.assignment_basis,
  (a.assignment_basis = 'TRANSITION')             as is_out_of_position,
  case when a.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end        as participant_type,
  a.user_id,
  a.professional_guest_id,
  coalesce(u.full_name, g.display_name)           as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  coalesce(gl.goals, 0)                           as goals,
  coalesce(
    (r.mvp_user_id is not null and r.mvp_user_id = a.user_id)
    or (r.mvp_professional_guest_id is not null
        and r.mvp_professional_guest_id = a.professional_guest_id),
    false)                                        as is_mvp
from public.match_team_assignments a
join public.matches m     on m.id = a.match_id
join public.communities c on c.id = m.community_id and c.is_active
left join public.users u                     on u.id = a.user_id
left join public.match_professional_guests g on g.id = a.professional_guest_id
left join public.match_goals gl
  on gl.match_id = a.match_id
 and ((gl.user_id is not null and gl.user_id = a.user_id)
   or (gl.professional_guest_id is not null
       and gl.professional_guest_id = a.professional_guest_id))
left join public.match_results r on r.match_id = a.match_id
where m.status = 'completed' or m.end_at <= now();

comment on view public.v_football_match_lineup is
  'Cycle 2 read model: the stored lineup of a completed match -- side, assigned '
  'position, goals and the MVP flag, for both kinds of participant. See '
  'migration 0057.';

revoke all on public.v_football_match_lineup from anon, authenticated, public;
revoke insert, update, delete, truncate, references, trigger
  on public.v_football_match_lineup from anon, authenticated;
grant select on public.v_football_match_lineup to authenticated;

-- v_football_match_participants (non-invoker, as it is today)
create view public.v_football_match_participants as
select
  reg.match_id,
  m.community_id,
  reg.status,
  reg.registration_order,
  row_number() over (
    partition by reg.match_id
    order by reg.admin_order nulls last,
             (reg.user_id is null), reg.registration_order
  )::int                                          as roster_position,
  case when reg.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end        as participant_type,
  reg.user_id,
  reg.professional_guest_id,
  coalesce(u.full_name, g.display_name)           as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  u.overall_rating
from public.match_registrations reg
join public.matches m     on m.id = reg.match_id
join public.communities c on c.id = m.community_id and c.is_active
left join public.users u                       on u.id = reg.user_id
left join public.match_professional_guests g   on g.id = reg.professional_guest_id
where m.status = 'completed' or m.end_at <= now();

comment on view public.v_football_match_participants is
  'Cycle 2 read model: the roster of a completed match, confirmed and reserve, '
  'for both kinds of participant. Restricted to completed matches on purpose -- '
  'who is registered for a future match is not published by this cycle. See '
  'migration 0057.';

revoke all on public.v_football_match_participants from anon, authenticated, public;
revoke insert, update, delete, truncate, references, trigger
  on public.v_football_match_participants from anon, authenticated;
grant select on public.v_football_match_participants to authenticated;

-- v_football_community_player_stats (non-invoker, as it is today)
create view public.v_football_community_player_stats as
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
where cs.period_type = 'overall';

comment on view public.v_football_community_player_stats is
  'Cycle 2 read model: one row per player with an all-time record in a '
  'community -- the counters the leaderboards rank on, plus the Global Rating. '
  'A preserved record, not a roster: an account suspension does not erase the '
  'player''s football identity or statistics, so a suspended player still '
  'appears here. Inactive communities remain excluded from the public surface. '
  'See migrations 0057 and 0063.';

revoke all on public.v_football_community_player_stats from anon, authenticated, public;
revoke insert, update, delete, truncate, references, trigger
  on public.v_football_community_player_stats from anon, authenticated;
grant select on public.v_football_community_player_stats to authenticated;
