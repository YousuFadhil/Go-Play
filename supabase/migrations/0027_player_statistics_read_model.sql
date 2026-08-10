-- Sprint DB-07: Read Model Refinement
--
-- Product decision: every registered user has a statistics record from the
-- application's perspective, from registration onward and not from their first
-- recorded match. A player who has played nothing has counters of zero -- that
-- is a fact about them, not the absence of one.
--
-- `v_player_statistics` as migration 0025 defined it said the opposite. It was
-- `player_statistics JOIN users`, so a player with no counters row was not in
-- it at all, and a read for one answered "no such player". On the project at
-- the time of this migration that was 11 of 23 users -- every account that had
-- yet to finish a match. This migration makes `users` the preserved side.
--
-- This migration changes ONE view and nothing else. No table is altered, no
-- function is created or replaced, no trigger is added and no policy is
-- touched. `player_statistics` still gains its row on the first recorded
-- result, exactly as 0022 wrote it; what changes is only how the read model
-- reports a player who has no row yet.
--
-- WHAT IS PRESERVED, and why it constrains the SQL below:
--
--   `create or replace view` may add trailing columns but may not rename,
--   reorder, retype or drop one. Every column therefore keeps its name, its
--   position and its type. Two of those cost something to hold:
--
--   * `overall_rating` is `numeric(4,2)`. `coalesce(x, 5.0)` is unconstrained
--     `numeric`, which is a different type and would make the replace fail, so
--     the result is cast back. The cast is not cosmetic -- without it this
--     migration does not apply.
--
--   * `user_id` was `ps.user_id`. It is now `u.id`, because the row is a
--     user's and `ps.user_id` is null for exactly the players this migration
--     exists to include. Same name, same uuid type.
--
-- SECURITY INVOKER is kept. The view still evaluates the base tables' policies
-- as the caller, so this changes what a permitted read *contains*, never who
-- may perform it.

-- ============================================================================
-- v_player_statistics
-- Sources: users, player_statistics
-- ============================================================================
-- One row per active user: their profile, their Global Rating, and their
-- career counters -- zeros until the first result is recorded.
--
-- ACTIVE USERS ONLY. `where u.is_active` states in the view what the `users`
-- policy already enforces for every signed-in caller, so a privileged reader
-- (a migration, a job, the service role) sees the same population an
-- application caller does. `user_is_active` is kept as a column because the
-- replace may not drop it; it is now constant true by construction.
--
-- COALESCE covers the six counters, which are `not null` in
-- `player_statistics` and can therefore only be null here by way of the left
-- join. Zero is the true value for a player who has played nothing.
--
-- `overall_rating` is coalesced to 5.0 as the decision requires. On this schema
-- the column is `not null` with default 5.00 and sits on the preserved side, so
-- the fallback cannot currently fire -- it states the intended default rather
-- than repairing a reachable gap.
--
-- `created_at` and `updated_at` are deliberately NOT coalesced. They describe
-- the counters row, and for a player who has none there is no honest value to
-- give: substituting the user's own timestamps would report a profile edit as
-- the moment statistics last changed, and a later "recently active" read would
-- act on it. Null says "no counters row yet", which is exactly what is true.
-- The zeros above are a fact about the player; a timestamp would be a
-- fabrication about a record. If Product wants these filled, that is a
-- deliberate follow-up and a one-line change here.
create or replace view public.v_player_statistics
with (security_invoker = on) as
select
  u.id                                        as user_id,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.is_active                                 as user_is_active,
  -- cast: coalesce widens numeric(4,2) to numeric, which replace would reject
  coalesce(u.overall_rating, 5.0)::numeric(4,2) as overall_rating,
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

-- Privileges are unchanged by `create or replace view`, which preserves the
-- existing grants. They are restated so this migration is self-contained and
-- re-runnable to the same end state: `authenticated` reads, `anon` gets
-- nothing.
revoke all on public.v_player_statistics from anon, public;
grant select on public.v_player_statistics to authenticated;
