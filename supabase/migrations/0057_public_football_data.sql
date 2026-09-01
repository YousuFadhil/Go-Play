-- ============ migrations/0057_public_football_data.sql ============
-- Cycle 2: the football data foundation.
--
-- The approved rule this serves:
--
--     Football activity is discoverable; private account data is private;
--     participation requires membership.
--
-- Cycle 1 closed the private half. This opens the football half, and it opens
-- exactly that half: what was played, by whom, on which side, who scored and
-- who was best. Nothing here grants participation, administration, or a single
-- private column.
--
-- ## THE PROBLEM THIS SOLVES
--
-- Every football-history table is gated on membership, and correctly so for the
-- paths that write them:
--
--     matches                  -> is_community_member(community_id, auth.uid())
--     match_registrations      -> is_match_community_member(match_id, auth.uid())
--     match_team_assignments   -> is_match_community_member(...)
--     match_results            -> is_match_community_member(...)
--     match_goals              -> is_match_community_member(...)
--     match_professional_guests-> is_match_community_member(...)
--     community_statistics     -> is_community_member(community_id, auth.uid())
--
-- Measured against the live project: a signed-in non-member reads **0** of the
-- 14 completed matches and **0** of the 14 recorded results. That is the gap.
--
-- ## THE INSTRUMENT
--
-- Five read models, built the way `v_public_communities` (migration `0033`) was:
-- deliberately NOT `security_invoker`, so they execute with the view owner's
-- privileges and the base-table policies do not filter them. That is what lets
-- a non-member read football history **without loosening a single policy on
-- `matches`, `match_results` or anything else**. The write paths are untouched;
-- only these five relations can see across a community boundary, and only for
-- the columns written out below.
--
-- The alternative -- widening the base-table policies -- was rejected: it would
-- have handed non-members the roster of every *upcoming* match, the creator of
-- every match, and every column of every row, in exchange for a convenience the
-- client does not need.
--
-- ## AUTHENTICATED ONLY, DELIBERATELY
--
-- `anon` receives nothing here. The signed-out surface stays exactly what it is
-- today -- `v_public_communities` and `v_public_upcoming_matches` -- and this
-- migration does not touch either. Football *history* is for people with an
-- account; that is the approved Cycle 2 boundary and the grants below are it.
--
-- ## COMPLETED MATCHES ONLY
--
-- Participants and lineups are restricted to completed matches. The cycle's
-- subject is football that has been played, and the roster of a match that has
-- *not* been played is a different disclosure with a different argument behind
-- it -- who is going to be somewhere, on a date, in the future. `0033` already
-- publishes what an upcoming match is (when, where, how many places); who is in
-- it stays where it is.
--
-- "Completed" is the project's existing rule and is not restated differently
-- here: `status = 'completed' OR end_at <= now()` (migrations `0029`, `0037`).
-- A historical match (`0054`) satisfies it the moment it is recorded, which is
-- the intent -- a recorded fixture is football that happened.
--
-- ## WHAT IS NOT HERE
--
-- No `join_code`. No `phone`, `email` or auth identifier. No `date_of_birth`.
-- No `owner_id`, `created_by` or `recorded_by` -- who organised a match and who
-- typed its score are administration, not football. No invitation data. The
-- column lists below are the whole of what these views can ever return, which is
-- the same property that makes `player_profile` safe.
--
-- ## WHAT IS REUSED RATHER THAN REBUILT
--
-- Player football statistics already work across communities and are not
-- duplicated here:
--
--   * `player_profile(uuid)` (migrations `0043`, `0056`) -- one player's
--     hardened 13-column football profile.
--   * `v_player_statistics` (migration `0027`) -- the same career counters for
--     every active player; its policies (`users.is_active`,
--     `player_statistics` USING (true)) already answer a non-member.
--
-- A second profile contract would be a second answer to a question that already
-- has one, and the two would drift.
--
-- Additive throughout: five new relations, no existing object altered, no
-- policy touched, no privilege withdrawn. Nothing the production client does
-- today behaves differently after this runs.


-- ============================================================================
-- 1) Completed matches, across communities
-- ============================================================================
-- The football summary of a match that has been played: when, where, whose, and
-- how it finished. One row per completed match in an active community.
--
-- The score and the MVP ride on this row rather than in a view of their own.
-- They are what "how it finished" means, a list of matches is the place both are
-- read, and a separate relation for two integers and one name would be a join
-- the caller has to remember to make.
--
-- `has_result` distinguishes the two honest states: played-and-recorded, and
-- played-but-not-yet-recorded. A null score is the second of those, never a
-- missing row.
--
-- The MVP is optional (migration `0033` made the column nullable) and may be
-- either kind of participant, so it is published the way every other participant
-- in this migration is: a type, an id of that type, and a name to draw.
create or replace view public.v_football_completed_matches as
select
  m.id                                    as match_id,
  m.community_id,
  c.name                                  as community_name,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.is_historical,
  (r.match_id is not null)                as has_result,
  r.team_a_score,
  r.team_b_score,
  case
    when r.mvp_user_id is not null              then 'USER'
    when r.mvp_professional_guest_id is not null then 'PROFESSIONAL'
  end                                     as mvp_participant_type,
  r.mvp_user_id,
  r.mvp_professional_guest_id,
  coalesce(mu.full_name, mg.display_name) as mvp_display_name,
  mu.avatar_path                          as mvp_avatar_path
from public.matches m
join public.communities c
  on c.id = m.community_id and c.is_active
left join public.match_results r              on r.match_id = m.id
left join public.users mu                     on mu.id = r.mvp_user_id
left join public.match_professional_guests mg on mg.id = r.mvp_professional_guest_id
where m.status = 'completed' or m.end_at <= now();

comment on view public.v_football_completed_matches is
  'Cycle 2 read model: one row per completed match in an active community, with '
  'its score and its MVP when one was recorded. Readable by any signed-in user, '
  'whatever communities they are in. Carries no join code, no organizer and no '
  'recorder -- see migration 0057.';


-- ============================================================================
-- 2) Who took part
-- ============================================================================
-- The roster of a completed match: everybody who registered, confirmed and
-- reserve alike, of both kinds.
--
-- A Professional Guest (`0044`) has no account, so the columns an account would
-- supply are null for them and `display_name` is what to draw. That is the same
-- shape `v_match_registrations` already uses, and it is deliberate: a caller
-- that reads `display_name` and `participant_type` never has to know which kind
-- of row it is holding.
--
-- `roster_position` is carried through because it is what reconstructs the
-- order the organizer arranged (`0053`), and a roster shown in a different order
-- from the one that was saved is a different roster.
create or replace view public.v_football_match_participants as
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


-- ============================================================================
-- 3) The saved lineup
-- ============================================================================
-- The two sides as they were stored, with each participant's assigned position,
-- their goals, and whether they were named best on the pitch.
--
-- Goals and the MVP flag are columns here rather than a relation of their own,
-- which follows `v_match_teams` and is not merely imitation: a goal is credited
-- only to somebody who played (`record_match_result` enforces it), so the
-- lineup is where a scorer already is. A separate goals view would be the same
-- rows with fewer columns.
--
-- `is_out_of_position` is derived from `assignment_basis` exactly as `v_match_
-- teams` derives it (BTGE §5.1), so a GUEST basis is never out of position.
create or replace view public.v_football_match_lineup as
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


-- ============================================================================
-- 4) A community's football record
-- ============================================================================
-- The three figures the Community Dashboard already reports, made readable
-- across communities: how many matches have been played, how many players have
-- a record here, and how many goals they have between them.
--
-- No new metric is invented. These are `CommunityDashboard.completedMatches`,
-- `.totalPlayers` and `.totalGoals` as `StatisticsRepository` already computes
-- them, taken from the same two sources: the completed-match rule for the first,
-- and the `overall` period of `community_statistics` for the other two.
create or replace view public.v_football_community_stats as
select
  c.id                                    as community_id,
  c.name                                  as community_name,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and (m.status = 'completed' or m.end_at <= now())
  )::int                                  as completed_matches,
  coalesce(s.players, 0)                  as players,
  coalesce(s.goals, 0)                    as goals,
  coalesce(s.mvp_count, 0)                as mvp_count
from public.communities c
left join lateral (
  select count(*)::int        as players,
         sum(cs.goals)::int   as goals,
         sum(cs.mvp_count)::int as mvp_count
  from public.community_statistics cs
  where cs.community_id = c.id
    and cs.period_type = 'overall'
) s on true
where c.is_active;

comment on view public.v_football_community_stats is
  'Cycle 2 read model: a community''s football record -- completed matches, '
  'players with a record, goals and MVP awards. The same three figures the '
  'Community Dashboard already reports, readable across communities. See '
  'migration 0057.';


-- ============================================================================
-- 5) A community's players, for ranking
-- ============================================================================
-- One row per player with a career record in one community, carrying the same
-- counters the leaderboards already rank on plus the Global Rating they already
-- read from the roster.
--
-- The `overall` period only. Weekly and monthly buckets are a filter the
-- Community Dashboard applies to its *own* members' data; publishing every
-- period across every community would be a wider disclosure than the approved
-- statistics, for a feature this cycle does not build.
--
-- Only active users appear. A statistics row survives a player leaving or being
-- deactivated (`0028`), and ranking somebody who is gone would be publishing a
-- record with nobody attached to it.
create or replace view public.v_football_community_player_stats as
select
  cs.community_id,
  cs.user_id,
  u.full_name                             as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  coalesce(u.overall_rating, 5.0)::numeric(4,2) as overall_rating,
  cs.matches_played,
  cs.wins,
  cs.draws,
  cs.losses,
  cs.goals,
  cs.mvp_count
from public.community_statistics cs
join public.users u       on u.id = cs.user_id and u.is_active
join public.communities c on c.id = cs.community_id and c.is_active
where cs.period_type = 'overall';

comment on view public.v_football_community_player_stats is
  'Cycle 2 read model: one row per active player with an all-time record in a '
  'community -- the counters the leaderboards rank on, plus the Global Rating. '
  'Active users only: a preserved record with a deactivated player behind it is '
  'not a ranking. See migration 0057.';


-- ============================================================================
-- 6) Privileges
-- ============================================================================
-- Read-only, to `authenticated`, and to nobody else.
--
-- The named revoke is migration `0034`'s hazard handled at the point it bites:
-- Supabase ships a default-privileges rule that grants ALL on every newly
-- created object in schema `public` to `anon` and `authenticated`, and it fires
-- before this migration's own grant is reached. Every view above is therefore
-- created carrying INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER,
-- and `0034` documented what that once cost: `v_public_communities` was briefly
-- deletable by an anonymous caller, because a non-`security_invoker` view runs
-- as its owner and does not consult the policies underneath.
--
-- Each view here is non-`security_invoker` for exactly the same reason and would
-- inherit exactly the same hole. `revoke all` closes it; the named revoke that
-- follows is not redundant with it but is the audit trail, in `0034`'s own
-- words, of which six privileges must not be there.
--
-- `anon` is revoked rather than merely not granted. Football history is for
-- people with an account.
--
-- The schema-wide default-privileges rule itself is left alone, as `0034` left
-- it: changing it governs every future object in `public` and is not a decision
-- to make inside a migration about football data.
do $$
declare
  v_view text;
begin
  foreach v_view in array array[
    'v_football_completed_matches',
    'v_football_match_participants',
    'v_football_match_lineup',
    'v_football_community_stats',
    'v_football_community_player_stats'
  ]
  loop
    execute format('revoke all on public.%I from anon, authenticated, public', v_view);
    execute format(
      'revoke insert, update, delete, truncate, references, trigger '
      'on public.%I from anon, authenticated', v_view);
    execute format('grant select on public.%I to authenticated', v_view);
  end loop;
end $$;


-- ============================================================================
-- 7) What this migration deliberately does NOT do
-- ============================================================================
-- Stated rather than left to inference, because each absence is a decision:
--
--   * No policy on any base table is created, altered or dropped. Membership
--     still decides every direct read and every write.
--   * No privilege is withdrawn from anything that exists. The production client
--     is unaffected -- it reads none of these five relations.
--   * `anon` gains nothing. `v_public_communities` and
--     `v_public_upcoming_matches` are untouched and remain the whole of the
--     signed-out surface.
--   * No participation or administration path is widened. Registering,
--     withdrawing, arranging a roster, recording a result and reading a join
--     code all still go through the RPCs that check a role.
--   * Professional Guests gain no persistent identity. They appear in the three
--     match-scoped views above, by `professional_guest_id` and `display_name`,
--     and appear in neither statistics view -- `community_statistics` and
--     `player_statistics` are keyed by `user_id`, and nothing here changes that.
