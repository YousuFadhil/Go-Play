-- ===== migrations/0081_community_scoped_rating_and_public_results.sql =====
-- Package 5 follow-up: a rating scoped to a community and a period, the
-- achievements a profile shows, and the completed results a visitor may read.
--
-- Five read models are added. **Nothing is stored, nothing is written and no
-- existing object is altered** — every function below derives its answer from
-- the evidence that is already authoritative (`matches`, `match_results`,
-- `match_team_assignments`, `match_result_contribution`, the Team of Period
-- snapshots), so a corrected, re-recorded or deleted result simply stops being
-- evidence. There is no second rating engine and no second copy of a rating to
-- go stale.
--
--   1. `community_scoped_rating`             -- the Community/Period Rating
--   2. `public_recent_results`               -- Discover's Latest Results
--   3. `public_community_recent_results`     -- one community's, for its page
--   4. `player_recent_achievements`          -- MVP + last closed week/month
--   5. `public_player_recent_achievements`   -- the public-safe subset
--
-- ## THE RATING RULES ARE `0078`'s, AND ONLY `0078`'s
--
-- Participation `+0.005`, win `+0.100`, draw `+0.010`, loss `-0.100`, goal
-- `+0.010` capped at `+0.070` per player per match, MVP `+0.020`, applied in
-- that order and clamped to `0.000 … 10.000` at every step — the same sequence
-- and the same clamp `apply_match_rating_effects` and `apply_rating_delta`
-- use. The constants are written out once, in
-- `community_scoped_rating`, and this migration changes neither `0078` nor the
-- Global Rating it maintains: `users.overall_rating` and `rating_history` are
-- not read, not written and not referenced anywhere below.
--
-- **The scoped rating starts every player at 5.000 inside its own scope.** It
-- is therefore not the Global Rating restricted to a community, and it will not
-- equal it: the stored Global Rating accumulated under earlier rule sets (only
-- a minority of `rating_history` even carries a `PARTICIPATION` row) and
-- carries the reversal bookkeeping of every correction. Recomputing one from
-- the other is not attempted, in either direction.
--
-- ## WHAT `anon` GAINS
--
-- The two results functions and the public achievements function, each with a
-- hand-written column list, in the shape `0079` already approved for
-- `public_match_detail`: a completed match's identity, when and where, the
-- score, and the best player's display name. No roster, no registration, no
-- join code, no guest identity, no user id. `community_scoped_rating` and
-- `player_recent_achievements` stay authenticated, as their member-facing
-- counterparts do.
--
-- Append-only. Nothing in `0022`-`0080` is edited.

-- ============================================================================
-- 1) community_scoped_rating() -- the Community/Period Rating
-- ============================================================================
-- One rating per player per scope, derived and never stored.
--
-- **Why a loop rather than a sum.** The clamp is applied after every delta, not
-- to the total, exactly as `apply_rating_delta` applies it — so a player who
-- reaches 10.000 mid-period absorbs part of the next gain and no more. A `sum`
-- would answer differently at the ends of the scale, and "the same rules as the
-- Global engine" has to mean the same arithmetic in the same order.
--
-- **The window is the statistics window.** Membership of a period is
-- `statistics_period_key(m.start_at, p_period_type)`, which is what
-- `community_statistics` buckets on (`0028`) — so a week here is the same week
-- the counters, the leaderboards and Team of Period already mean, in
-- Asia/Muscat, and no second definition of "this week" is introduced.
--
-- A Professional Guest has no row: `match_team_assignments.user_id` is null for
-- one and `match_result_contribution` already excludes them.
create or replace function public.community_scoped_rating(
  p_community_id uuid,
  p_period_type text,
  p_period_key text
)
returns table (
  user_id uuid,
  rating numeric(5,3),
  matches_played int
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_player uuid;
  v_rating numeric(5,3);
  v_matches int;
  r record;
begin
  if p_period_type is null
     or p_period_type not in ('overall', 'weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;
  if p_period_key is null then
    raise exception 'INVALID_PERIOD_KEY';
  end if;

  for v_player in
    select distinct a.user_id
    from match_team_assignments a
    join matches m       on m.id = a.match_id
    join match_results res on res.match_id = m.id
    where m.community_id = p_community_id
      and a.user_id is not null
      -- The project's own definition of completed (`0029`, `0037`).
      and (m.status = 'completed' or m.end_at <= now())
      and public.statistics_period_key(m.start_at, p_period_type) = p_period_key
  loop
    v_rating := 5.000;
    v_matches := 0;

    for r in
      select m.id as match_id, m.start_at, k.won, k.lost, k.scored, k.mvp
      from match_team_assignments a
      join matches m         on m.id = a.match_id
      join match_results res on res.match_id = m.id
      join lateral public.match_result_contribution(m.id) k
        on k.user_id = v_player
      where a.user_id = v_player
        and m.community_id = p_community_id
        and (m.status = 'completed' or m.end_at <= now())
        and public.statistics_period_key(m.start_at, p_period_type)
              = p_period_key
      -- Chronological, because the clamp makes the order matter.
      order by m.start_at, m.id
    loop
      v_matches := v_matches + 1;

      -- PARTICIPATION, then the outcome, then the goals, then the MVP --
      -- `0078`'s order, clamped after each.
      v_rating := least(10.000, greatest(0.000, v_rating + 0.005));
      v_rating := least(10.000, greatest(0.000, v_rating + case
        when r.won  = 1 then 0.100
        when r.lost = 1 then -0.100
        else 0.010
      end));
      if r.scored > 0 then
        v_rating := least(10.000, greatest(0.000,
          v_rating + least(0.070, 0.010 * r.scored)));
      end if;
      if r.mvp = 1 then
        v_rating := least(10.000, greatest(0.000, v_rating + 0.020));
      end if;
    end loop;

    user_id := v_player;
    rating := v_rating;
    matches_played := v_matches;
    return next;
  end loop;
end;
$$;

comment on function public.community_scoped_rating(uuid, text, text) is
  'The Community/Period Rating: one rating per player, from 5.000, over the '
  'matches played in this community inside this statistics period. Derived '
  'from the recorded results with migration 0078''s values, applied in the '
  'engine''s own order and clamped at every step -- never stored, so a '
  'correction cannot leave it stale. It is not the Global Rating and is not '
  'derived from it: users.overall_rating and rating_history are untouched by '
  'this function. Only players with at least one match in the scope have a '
  'row, which is what excludes a member who has not played -- see migration '
  '0081.';

revoke execute on function public.community_scoped_rating(uuid, text, text)
  from anon, public;
grant execute on function public.community_scoped_rating(uuid, text, text)
  to authenticated;
grant execute on function public.community_scoped_rating(uuid, text, text)
  to service_role;

-- ============================================================================
-- 2) public_recent_results() -- the Latest Results a visitor may read
-- ============================================================================
-- The completed half of `public_match_detail`, as a list.
--
-- **The same columns `0079` approved for one match, for the most recent few.**
-- A visitor could already open any one of these by id; what was missing was the
-- way to find them, which is why the fix is a listing and not a wider row. No
-- roster, no registration, no places, no identifiers.
create or replace function public.public_recent_results(p_limit int default 5)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  community_logo_url text,
  title text,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  has_result boolean,
  team_a_score int,
  team_b_score int,
  mvp_display_name text,
  mvp_avatar_path text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    f.match_id,
    f.community_id,
    f.community_name,
    c.logo_url,
    f.title,
    f.location,
    f.start_at,
    f.end_at,
    f.has_result,
    f.team_a_score,
    f.team_b_score,
    f.mvp_display_name,
    f.mvp_avatar_path
  from v_football_completed_matches f
  join communities c on c.id = f.community_id and c.is_active
  -- A match that ended with nothing recorded is not a result to publish.
  where f.has_result
  order by f.start_at desc, f.match_id desc
  limit least(greatest(coalesce(p_limit, 5), 1), 20);
$$;

comment on function public.public_recent_results(int) is
  'The most recent completed matches with a recorded result, across every '
  'active community: identity, when, where, the score and the best player''s '
  'display name. The completed shape public_match_detail already returns, as a '
  'list -- no roster, no registration, no places and no identifiers beyond the '
  'match and its community. Executable by anon -- see migration 0081.';

revoke execute on function public.public_recent_results(int) from public;
grant execute on function public.public_recent_results(int)
  to anon, authenticated, service_role;

-- ============================================================================
-- 3) public_community_recent_results() -- the same list, for one community
-- ============================================================================
-- What a public community page shows under its upcoming matches, so a
-- community with nothing scheduled is not an empty page. The community must be
-- active; `join_policy` decides joining and never browsing (`0016`).
create or replace function public.public_community_recent_results(
  p_community_id uuid,
  p_limit int default 5
)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  community_logo_url text,
  title text,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  has_result boolean,
  team_a_score int,
  team_b_score int,
  mvp_display_name text,
  mvp_avatar_path text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    f.match_id,
    f.community_id,
    f.community_name,
    c.logo_url,
    f.title,
    f.location,
    f.start_at,
    f.end_at,
    f.has_result,
    f.team_a_score,
    f.team_b_score,
    f.mvp_display_name,
    f.mvp_avatar_path
  from v_football_completed_matches f
  join communities c on c.id = f.community_id and c.is_active
  where f.community_id = p_community_id
    and f.has_result
  order by f.start_at desc, f.match_id desc
  limit least(greatest(coalesce(p_limit, 5), 1), 20);
$$;

comment on function public.public_community_recent_results(uuid, int) is
  'One active community''s most recent completed results, in the same public '
  'shape as public_recent_results. Executable by anon -- see migration 0081.';

revoke execute on function public.public_community_recent_results(uuid, int)
  from public;
grant execute on function public.public_community_recent_results(uuid, int)
  to anon, authenticated, service_role;

-- ============================================================================
-- 4) player_recent_achievements() -- what a profile puts under "Achievements"
-- ============================================================================
-- **Three sources, one rule each, and no fallback between them:**
--
--   * the player's most recent MVP award, dated by kick-off;
--   * every Team of Period award they hold for the **last closed week**;
--   * every Team of Period award they hold for the **last closed month**.
--
-- "Last closed" is `last_completed_statistics_period` (`0070`), which is the
-- single interpretation of an award period in this database. An older weekly
-- award is therefore **not** shown because it happens to be the player's most
-- recent one: a profile says what somebody won *this* period, and a period
-- they were not selected in shows nothing rather than something older.
--
-- Selections in two communities are two rows. The awards are read from the
-- immutable snapshots `0079` stores; nothing is recomputed here and no
-- selection is made here.
create or replace function public.player_recent_achievements(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  achievement_type text,
  occurred_at timestamptz,
  community_id uuid,
  community_name text,
  period_type text,
  period_key text
)
language sql
security definer
stable
set search_path = public
as $$
  with mvp as (
    select
      'MVP'::text        as achievement_type,
      m.start_at         as occurred_at,
      m.community_id,
      c.name             as community_name,
      null::text         as period_type,
      null::text         as period_key
    from match_results r
    join matches m     on m.id = r.match_id
    join communities c on c.id = m.community_id and c.is_active
    where r.mvp_user_id = p_user_id
      and (m.status = 'completed' or m.end_at <= now())
    order by m.start_at desc, m.id desc
    limit 1
  ),
  closed as (
    select p.period_type, p.period_key
    from (values ('weekly'), ('monthly')) as t(period_type)
    cross join lateral public.last_completed_statistics_period(t.period_type) p
  ),
  awards as (
    select
      'TEAM_OF_PERIOD'::text as achievement_type,
      -- The last instant of the period, as every Team of Period date is.
      s.period_end - interval '1 millisecond' as occurred_at,
      s.community_id,
      c.name                 as community_name,
      s.period_type,
      s.period_key
    from team_of_period_awards a
    join team_of_period_snapshots s on s.id = a.snapshot_id
    join closed k
      on k.period_type = s.period_type and k.period_key = s.period_key
    join communities c on c.id = s.community_id and c.is_active
    where a.user_id = p_user_id
  )
  select * from (
    select * from mvp
    union all
    select * from awards
  ) all_achievements
  -- Newest first; the rest of the order is only for display stability, so two
  -- reads of the same profile put the same cards in the same places.
  -- Qualified, because the function's own OUT parameters carry these names
  -- and an unqualified reference in a `language sql` body is ambiguous.
  order by all_achievements.occurred_at desc,
           all_achievements.achievement_type,
           all_achievements.community_name,
           all_achievements.community_id
  limit least(greatest(coalesce(p_limit, 5), 1), 10);
$$;

comment on function public.player_recent_achievements(uuid, int) is
  'A player''s recent achievements, newest first: their latest MVP award, and '
  'every Team of Period award they hold for the last CLOSED week and the last '
  'closed month -- one row per community selection, in active communities '
  'only. An older period is never shown as a substitute for one the player was '
  'not selected in. Read from the stored snapshots; no selection is made here '
  '-- see migration 0081.';

revoke execute on function public.player_recent_achievements(uuid, int)
  from anon, public;
grant execute on function public.player_recent_achievements(uuid, int)
  to authenticated;
grant execute on function public.player_recent_achievements(uuid, int)
  to service_role;

-- ============================================================================
-- 5) public_player_recent_achievements() -- the public-safe subset
-- ============================================================================
-- The same rows a signed-in reader gets, minus the community id: a visitor is
-- shown what was won, when, in which named community, and nothing that
-- identifies a row in the database. The player must be active, exactly as the
-- other public player contracts require.
create or replace function public.public_player_recent_achievements(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  achievement_type text,
  occurred_at timestamptz,
  community_name text,
  period_type text,
  period_key text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    a.achievement_type,
    a.occurred_at,
    a.community_name,
    a.period_type,
    a.period_key
  from public.player_recent_achievements(p_user_id, p_limit) a
  join users u on u.id = p_user_id and u.is_active;
$$;

comment on function public.public_player_recent_achievements(uuid, int) is
  'The public Recent Achievements: kind, date, community name and period, for '
  'an active player. No community id, no match id and no user id -- see '
  'migration 0081.';

revoke execute on function public.public_player_recent_achievements(uuid, int)
  from public;
grant execute on function public.public_player_recent_achievements(uuid, int)
  to anon, authenticated, service_role;
