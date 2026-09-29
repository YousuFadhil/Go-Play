-- ===== migrations/0093_public_community_football_contract.sql =====
-- The football a visitor may read on a community's page: its record, and its
-- Top 11 players.
--
-- Two read functions are added. **Nothing is stored, nothing is written and no
-- existing object is altered** -- no table, no view, no policy and no existing
-- grant. Both answer from `community_statistics` and `matches`, the sources the
-- authenticated football views already read, so a corrected or reversed result
-- simply changes the answer and there is no second copy to go stale.
--
--   1. `public_community_football_record`   -- the four figures above the tabs
--   2. `public_community_top_players`       -- the Top Players tab
--
-- ## WHY TWO NEW FUNCTIONS AND NOT A WIDER GRANT
--
-- The community page for a signed-out visitor and for a signed-in non-member is
-- one hierarchy: the record, then Latest Results, Upcoming Matches and Top
-- Players. The record and the players were only ever readable by
-- `authenticated`, through `v_football_community_stats` and
-- `v_football_community_player_stats` (`0057`, `0063`, `0073`). The obvious fix
-- -- granting `anon` SELECT on those views -- is the wrong one: they belong to
-- a family (`v_football_completed_matches`, `v_football_match_participants`,
-- `v_football_match_lineup`) whose grants are approved as one closed set for
-- signed-in readers. A view's grant is a grant of every column it has and every
-- column it will ever be given; these views also carry positions and win/draw/
-- loss splits this page never draws.
--
-- So `anon` gains exactly two functions, each with a hand-written column list
-- and no `select *` anywhere. **None of the five `v_football_*` views is
-- granted, revoked or replaced here.**
--
-- ## WHAT A VISITOR MAY LEARN
--
-- The record: community id, completed matches, players with a record, goals and
-- MVP awards -- the figures `v_football_community_stats` already reports, with
-- the community name left out because the page already has it.
--
-- A Top Players row: community id, user id, display name, picture path, rating
-- and three career counters. **The user id is there because a name leads to a
-- profile**, and is returned only for a player whose public profile exists
-- right now (`users.is_active`, the predicate `public_player_profile` answers
-- on), so an id is present exactly when `/player/{id}` would open.
--
-- Never returned: phone, email, date of birth, auth identifier, join code,
-- invitation data, an owner or administrator identifier, the roster of a match
-- that has not been played, a Professional Guest (they have no user and so no
-- `community_statistics` row) or any suspension metadata.
--
-- ## VISIBILITY
--
-- Both require an **active community**. An inactive or suspended community and
-- one that never existed are one answer -- no rows -- so a guessed id cannot
-- tell them apart. `join_policy` decides joining and never browsing (`0016`),
-- so it is not consulted.
--
-- Top Players additionally requires an **active player**. That is narrower than
-- `v_football_community_player_stats`, which keeps a suspended player's record
-- (`0063`) for a signed-in reader; a public list is held to the public profile
-- contract instead, which has no page for a suspended account.
--
-- ## THE RANKING IS NOT CHANGED
--
-- Rating, then goals, then MVPs, then name -- the order the client has always
-- applied to this list, now applied where the rows are, so both audiences read
-- one answer instead of each sorting its own. Two details are stated because
-- each is a place a rewrite could quietly change the result:
--
--   * **The rating is the Global Rating** (`users.overall_rating`, `0073`),
--     defaulting to 5.000, exactly as `v_football_community_player_stats`
--     computes it. It is not the Community/Period Rating of `0081`.
--   * **The name is compared with `collate "C"`**, which is code-point order:
--     the order Dart's `String.compareTo` gave the client-side sort this
--     replaces. Under the database default collation two players who tie on
--     everything else could swap places on capitalisation alone. A final
--     `user_id` key makes the order total, so two identical names still cannot
--     trade places between reads.
--
-- The list is capped at 11 in the function. It takes no limit argument: a
-- caller cannot ask for more than the approved eleven.
--
-- Read-only and additive: `create or replace`, so it is safe to re-run.


-- ============================================================================
-- 1) public_community_football_record() -- the four figures above the tabs
-- ============================================================================
-- Every relation and function is schema-qualified because `search_path` is
-- empty (below). Every column reference is qualified too: the function's own
-- OUT parameters carry the names `community_id`, `goals`, `players` and
-- `mvp_count`, and an unqualified reference in a `language sql` body is
-- ambiguous.
--
-- The completed-match rule and the two statistics sums are `0057`'s, restated
-- rather than delegated to `v_football_community_stats`: delegating would put
-- `anon`'s disclosure at the mercy of a later edit to a view approved for
-- `authenticated`.
create or replace function public.public_community_football_record(
  p_community_id uuid
)
returns table (
  community_id uuid,
  completed_matches int,
  players int,
  goals int,
  mvp_count int
)
language sql
security definer
stable
set search_path = ''
as $$
  select
    c.id,
    (
      select count(*)
      from public.matches m
      where m.community_id = c.id
        and (m.status = 'completed' or m.end_at <= now())
    )::int,
    coalesce(s.player_count, 0),
    coalesce(s.goal_count, 0),
    coalesce(s.mvp_total, 0)
  from public.communities c
  left join lateral (
    select
      count(*)::int          as player_count,
      sum(cs.goals)::int     as goal_count,
      sum(cs.mvp_count)::int as mvp_total
    from public.community_statistics cs
    where cs.community_id = c.id
      and cs.period_type = 'overall'
  ) s on true
  where c.id = p_community_id
    and c.is_active;
$$;

comment on function public.public_community_football_record(uuid) is
  'The public football record of one active community: completed matches, '
  'players with an all-time record, goals and MVP awards. The four figures '
  'v_football_community_stats reports, in a fixed column list of their own -- '
  'no community name, no roster and nothing about any player. No rows for an '
  'inactive, suspended or unknown community. Executable by anon -- see '
  'migration 0093.';


-- ============================================================================
-- 2) public_community_top_players() -- the Top Players tab
-- ============================================================================
-- One row per active player with an all-time record in an active community,
-- best first, at most eleven.
--
-- `community_statistics` is keyed by user, so a Professional Guest cannot
-- appear here; the `overall` period only, exactly as `0057` chose, because the
-- weekly and monthly buckets across every community would be a wider
-- disclosure than this page asks for.
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
  'ranked by rating, then goals, then MVPs, then name. Active players in an '
  'active community only; a user id only for a player whose public profile '
  'exists. No phone, email, date of birth, auth identifier, join code or '
  'Professional Guest. Takes no limit -- the cap is 11. Executable by anon -- '
  'see migration 0093.';


-- ============================================================================
-- 3) Privileges -- the only thing `anon` gains in this migration
-- ============================================================================
-- Supabase's default-privileges rule grants EXECUTE on a new function in
-- `public` to `anon`, `authenticated` and `service_role`, and PostgreSQL grants
-- it to PUBLIC besides. Both are cleared first, and the intended grant is then
-- written out, so the file says what must be true when it finishes rather than
-- relying on what the defaults happened to leave.
--
-- `anon` is granted on purpose: this is the narrow public contract. Nothing
-- here grants on a table or a view, and none of the five `v_football_*` views
-- is named.
revoke all on function public.public_community_football_record(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.public_community_football_record(uuid)
  to anon, authenticated, service_role;

revoke all on function public.public_community_top_players(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.public_community_top_players(uuid)
  to anon, authenticated, service_role;
