-- Fix: the Community Statistics "Completed Matches" figure read zero while the
-- community had finished matches.
--
-- The stored `matches.status` is not the authority on completion and never was.
-- `0006` makes completion time-driven, but the only thing that writes
-- `'completed'` is `recompute_match_status`, and every path that calls it —
-- `register_for_match`, `withdraw_from_match` and the organizer roster RPCs —
-- refuses to run once `end_at` has passed (`MATCH_CLOSED` / `MATCH_LOCKED`). So
-- a match that simply finishes is never marked: there is no path that takes it
-- there. The observed state is the expected one, not corruption — every
-- finished match in this database sits at `open`.
--
-- Everything else in the product already knows this and derives completion from
-- the clock. `0029` is the authority and states the rule as a guard:
--
--     if v_match.status <> 'completed' and v_match.end_at > now() then
--       raise exception 'MATCH_NOT_COMPLETED';
--
-- — a match is completed when its status says so *or* its end time has passed.
-- `register_for_match` (`0006`) gates on the same disjunction, and the Flutter
-- client derives `Match.effectiveStatus` identically. The statistics read was
-- the single place in the system reading the stored status alone, which is why
-- it was the single place showing a different number.
--
-- This migration adds one read model that states that rule once, in the
-- database, so the count agrees with `0029` by construction rather than by two
-- copies of a condition staying in step.
--
-- What this migration deliberately does NOT do:
--
--   * It does not update any `matches` row. Nothing reads the stored status as
--     the truth any more, so a backfill would correct a value that no longer
--     decides anything — and it would fire `matches_set_capacity`, re-deriving
--     `max_registration` on historical rows for no reason.
--   * It adds no scheduled job. `now()` is evaluated per read, so a match is
--     counted the instant it ends, with no window in which the dashboard and
--     the match list disagree. A periodic job would introduce exactly that
--     window.
--   * It does not touch `v_community_summary.completed_matches` (`0025`), which
--     carries the same stored-status filter. That figure belongs to the
--     community card, not to this fix, and is left for its own change.
--
-- Backward compatible: no table, function, trigger or policy is altered.

-- ============================================================================
-- v_completed_matches
-- Sources: matches
-- ============================================================================
-- One row per match that is completed under `0029`'s rule. It projects rather
-- than aggregates, so a community with none produces no rows and counts zero
-- without the view having to know which communities exist.
--
-- `security_invoker = on`, per `0025`'s third rule: the `matches` policies
-- decide whose rows come back. The view restates no policy and grants sight of
-- nothing that a direct read of `matches` would not.
create or replace view public.v_completed_matches
with (security_invoker = on) as
select
  m.id            as match_id,
  m.community_id,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.created_by,
  m.created_at
from public.matches m
where m.status = 'completed'
   or m.end_at <= now();

comment on view public.v_completed_matches is
  'Read model: matches that are completed under 0029''s rule — status is '
  'completed OR end_at has passed. The stored status alone is not the '
  'authority: no path marks a match completed once it simply finishes.';

-- Privileges, exactly as `0025` sets them for every view: `authenticated` may
-- issue the select, `anon` may not, and `security_invoker` decides the rows.
revoke all on public.v_completed_matches from anon, public;
grant select on public.v_completed_matches to authenticated;
