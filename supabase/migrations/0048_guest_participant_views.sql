-- The two read models that lost a participant.
--
-- `v_match_registrations` and `v_match_teams` (migration `0025`) each join
-- `users` to put a name beside a row. That join was inner, because before
-- Professional Guests every participant had a `users` row and an inner join said
-- something true. It does not any more: a guest's registration and a guest's
-- lineup row have a null `user_id`, and an inner join does not merely leave the
-- name blank -- it **drops the row entirely**. A roster read through the view
-- would show four players in a match of five, and a lineup read would show a
-- side with a hole in it, with nothing to indicate anything was missing.
--
-- So both joins become outer, and both views gain the three columns a reader
-- needs to tell the two kinds of participant apart:
--
--   professional_guest_id  -- null for a registered user
--   participant_type       -- 'USER' or 'PROFESSIONAL'
--   display_name           -- the user's name or the guest's, whichever applies
--
-- `participant_type` is a projection of which identity column is set, derived
-- the same way the XOR check states it. It is **not** a new entity: there is no
-- participant table, no participant id, and nothing above these views is asked
-- to treat the two kinds as one thing. It is a label on a row, so a reader can
-- branch without having to know that a null `user_id` means anything.
--
-- `full_name`, `primary_position`, `secondary_position` and `overall_rating`
-- stay exactly what they were: facts about a **user profile**, null for a guest
-- because a guest has none. `display_name` is the column to render. Widening
-- `full_name` to carry a guest's name would have made "this player's profile
-- name" and "what to print" the same column, and they are not -- a guest has the
-- second and not the first.
--
-- ## What `create or replace view` allows
--
-- Columns may be appended; they may not be renamed, reordered, retyped or
-- dropped. Every existing column below therefore keeps its name, its position
-- and its type, and the three new ones are at the end. Two *expressions* change
-- (`is_mvp`, and the goals join in `v_match_teams`), which is permitted because
-- neither changes a name or a type.
--
-- `security_invoker = on` is carried through, per `0025`'s third rule: the base
-- tables' policies decide the rows, and these views restate no policy. A guest
-- is visible to exactly the members who can already see the match, because
-- `match_professional_guests_select_members` (migration `0044`) says so.

-- 1) v_match_registrations ---------------------------------------------------------
-- Sources: match_registrations, matches, users, match_professional_guests
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
  m.status              as match_status,
  -- Appended by migration 0048.
  r.professional_guest_id,
  case when r.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end::text  as participant_type,
  coalesce(u.full_name, g.display_name)           as display_name
from public.match_registrations r
join public.matches m on m.id = r.match_id
-- CHANGED (0048): outer, so a guest's seat is a row with no profile rather than
-- no row at all.
left join public.users u on u.id = r.user_id
left join public.match_professional_guests g on g.id = r.professional_guest_id;

comment on view public.v_match_registrations is
  'Read model: match registrations (confirmed and reserve) for both kinds of '
  'participant. participant_type distinguishes USER from PROFESSIONAL; '
  'display_name is what to render, while full_name and the profile columns are '
  'null for a guest. registration_order is the queue position written by the '
  'RPC and is never recomputed here.';

-- 2) v_match_teams ------------------------------------------------------------------
-- Sources: match_team_assignments, matches, users, match_goals, match_results,
--          match_professional_guests
--
-- Two expressions change beyond the join.
--
-- **The goals join** matched on `user_id` alone, so a guest's tally would never
-- have been found. It now matches whichever identity the lineup row carries.
-- The partial unique indexes of migration `0044` keep it one row either way, so
-- the lineup is still not multiplied.
--
-- **`is_mvp`** asked only about `mvp_user_id`. It now asks about both, and
-- yields false rather than null where it used to be null for a match with no
-- result -- "this player is not the MVP" is true of a match that has no MVP, and
-- a null there made every reader handle a third case that meant nothing.
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
  -- CHANGED (0048): both identities, and false rather than null.
  coalesce(
    (mr.mvp_user_id is not null and mr.mvp_user_id = a.user_id)
    or (mr.mvp_professional_guest_id is not null
        and mr.mvp_professional_guest_id = a.professional_guest_id),
    false)                              as is_mvp,
  m.start_at            as match_start_at,
  m.status              as match_status,
  a.created_at,
  a.updated_at,
  -- Appended by migration 0048.
  a.professional_guest_id,
  case when a.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end::text  as participant_type,
  coalesce(u.full_name, pg.display_name)          as display_name
from public.match_team_assignments a
join public.matches m on m.id = a.match_id
-- CHANGED (0048): outer, so a guest's lineup row survives the read.
left join public.users u on u.id = a.user_id
left join public.match_professional_guests pg on pg.id = a.professional_guest_id
-- CHANGED (0048): whichever identity the row carries.
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

-- Privileges are unchanged by `create or replace view`, which preserves them.
-- Restated for the same reason `0025` states them: `anon` may not read either,
-- and `security_invoker` decides which rows `authenticated` gets.
revoke all on public.v_match_registrations from anon, public;
grant select on public.v_match_registrations to authenticated;
revoke all on public.v_match_teams from anon, public;
grant select on public.v_match_teams to authenticated;
