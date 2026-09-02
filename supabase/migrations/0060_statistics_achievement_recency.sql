-- ============ migrations/0060_statistics_achievement_recency.sql ============
-- When two players are level, which of them did it more recently.
--
-- ## What this is for
--
-- A leaderboard and a dashboard both have to put equal values in *some* order.
-- Today that order is the player's name, which is arbitrary and says nothing:
-- two players on eight goals are separated by the alphabet. The approved rule
-- is that the one who scored more recently comes first.
--
-- Equal values still share a rank -- this decides display order inside a tie
-- and never turns a tie into a difference. That reasoning stays in the
-- repository. What is here is only the evidence it needs.
--
-- ## Why the client cannot answer it
--
-- Two reasons, both about not having a second opinion:
--
--   1. **The period boundaries.** A weekly counter is bucketed by
--      `statistics_period_key(m.start_at, 'weekly')`, which is an ISO week in
--      Asia/Muscat (migration `0028`, frozen). Recency has to describe the same
--      week the counter describes. Recomputing that in Dart would be a second
--      implementation of a frozen rule, free to disagree with the first at
--      exactly the boundaries that are hardest to test.
--
--   2. **What "achieved" means.** A goal counts when it is in the recorded
--      result of a match whose lineup the player is on; a win is decided by the
--      stored side against the stored score. That join already exists as
--      `match_result_contribution` (0023, 0046) and is the same shape here.
--      Deriving it client-side would be a third copy of the counters' own
--      definition.
--
-- ## No new state, and nothing persisted
--
-- This adds **no column, no table, no trigger and no stored counter.** It is a
-- read model over evidence that is already authoritative:
--
--     matches x match_results x match_team_assignments x match_goals
--     rating_history x matches
--
-- That is what makes corrections work without any code for corrections. A
-- result that is undone takes its `match_goals` and `match_team_assignments`
-- rows with it, so the goal that no longer counts stops being a timestamp; a
-- corrected lineup moves the win to the side that actually won; a replaced MVP
-- is simply a different `mvp_user_id`. There is no "latest achievement" field
-- to go stale because there is no field.
--
-- ## `security invoker`, deliberately
--
-- This function is **not** `security definer`. It reads the same tables the
-- caller could already read, under the same policies:
--
--     match_results / match_goals / rating_history
--         -> is_match_community_member(match_id, auth.uid())
--     matches, v_community_members
--         -> the community policies
--
-- So a non-member gets an empty result, exactly as they get an empty result
-- from `community_statistics` today. **No policy is changed and no statistics
-- visibility is widened.** A definer function here would have been easier and
-- would have leaked: rating history is readable per match-community, and
-- bypassing that to compute a truly global recency would tell a reader when a
-- player last played somewhere the reader cannot see.
--
-- The consequence is stated rather than hidden: `last_rating_at` is the newest
-- effective rating event **among the matches the reader may see**. That is the
-- same shape of answer `CS-D3` already accepts for a player's own periodic
-- totals, and it keeps this read from being a hole in the policies around it.
--
-- Two pure helpers are granted to `authenticated` so this can stay invoker:
-- `statistics_period_zone()` returns a constant string and
-- `statistics_period_key(timestamptz, text)` formats a timestamp the caller
-- already supplied. Neither reads a row, so neither can disclose anything --
-- and granting them is what removes the reason to make this function definer.

-- 1) The two pure period helpers, callable by the read below -------------------------
-- Data-free: a constant, and a `to_char` over an argument. Granting them
-- exposes no row and is the price of keeping the read model `security invoker`.
grant execute on function public.statistics_period_zone() to authenticated;
grant execute on function
  public.statistics_period_key(timestamptz, text) to authenticated;

-- 2) The read model ------------------------------------------------------------------
-- One row per player the community has evidence about, with the timestamp of
-- their most recent achievement of each measure. Null where the measure has
-- never happened to them, which the caller reads as "sorts last".
--
-- Every timestamp is `matches.start_at` and none is a `created_at`. When a
-- match was *played* is what makes one achievement more recent than another;
-- when the row was *entered* is not. Recording last season's match today must
-- not make it newer than yesterday's.
create or replace function public.community_statistics_recency(
  p_community_id uuid,
  p_period_type text,
  p_period_key text
)
returns table (
  user_id uuid,
  last_goal_at timestamptz,
  last_mvp_at timestamptz,
  last_played_at timestamptz,
  last_win_at timestamptz,
  last_rating_at timestamptz
)
language sql
stable
set search_path = public
as $$
  with played as (
    -- `match_result_contribution`'s join, restricted to one community and one
    -- period. A row here is one player's participation in one match that has a
    -- recorded result -- which is exactly what the counters are built from, so
    -- the recency and the number it breaks ties for always describe the same
    -- matches.
    select
      a.user_id,
      m.start_at,
      coalesce(g.goals, 0) > 0                     as scored,
      a.user_id = r.mvp_user_id                    as was_mvp,
      (a.team = 'A' and r.team_a_score > r.team_b_score)
        or (a.team = 'B' and r.team_b_score > r.team_a_score) as won
    from matches m
    join match_results r on r.match_id = m.id
    join match_team_assignments a on a.match_id = m.id
    left join match_goals g
      on g.match_id = a.match_id and g.user_id = a.user_id
    where m.community_id = p_community_id
      -- A Professional Guest is not a player with statistics, here as
      -- everywhere else (0046).
      and a.user_id is not null
      -- The counters' own bucketing, called rather than restated.
      and public.statistics_period_key(m.start_at, p_period_type) = p_period_key
  ),
  counters as (
    select
      p.user_id,
      max(p.start_at) filter (where p.scored)  as last_goal_at,
      max(p.start_at) filter (where p.was_mvp) as last_mvp_at,
      -- Played participation, which is what the Most Active counter counts:
      -- being on the stored lineup of a match that has a result. Not
      -- registration, and not a reserve seat.
      max(p.start_at)                          as last_played_at,
      max(p.start_at) filter (where p.won)     as last_win_at
    from played p
    group by p.user_id
  ),
  rating as (
    -- Highest Rated shows the Global Rating, which has no periodic form, so its
    -- recency has none either: this ignores `p_period_type` entirely and is the
    -- same answer in every period.
    --
    -- "Currently effective" is `reverse_match_rating_effects`'s own predicate,
    -- verbatim (0022): an entry that reverses nothing and that nothing has
    -- reversed. A reversed entry is not part of the rating the player holds
    -- now, and the REVERSAL row that undid it is not an achievement.
    --
    -- A zero-delta entry **is** kept. `apply_rating_delta` writes a row for
    -- every application, recording the change actually applied -- which is zero
    -- for a player already at the top of the 0.00-10.00 range. That is a real
    -- rating event about a real match, and the contract records it, so it is
    -- not filtered out here.
    --
    -- Scoped to the community's current members because they are the only
    -- population the Highest Rated board can rank.
    select h.user_id, max(rm.start_at) as last_rating_at
    from rating_history h
    join matches rm on rm.id = h.match_id
    where h.reverses_id is null
      and not exists (
        select 1 from rating_history x where x.reverses_id = h.id
      )
      and exists (
        select 1 from v_community_members v
        where v.community_id = p_community_id and v.user_id = h.user_id
      )
    group by h.user_id
  )
  -- Full join: a player may have counters without a rating event (a draw moves
  -- no rating) or a rating event without counters in this period.
  select
    coalesce(c.user_id, r.user_id),
    c.last_goal_at,
    c.last_mvp_at,
    c.last_played_at,
    c.last_win_at,
    r.last_rating_at
  from counters c
  full outer join rating r on r.user_id = c.user_id;
$$;

comment on function public.community_statistics_recency(uuid, text, text) is
  'Per-player timestamps of the most recent goal, MVP, played match and win in '
  'one community and period, plus the most recent currently-effective rating '
  'event (global, non-periodic). Every timestamp is matches.start_at. A read '
  'model over existing evidence: no stored state, and corrections are followed '
  'because the evidence itself moves. security invoker -- see migration 0060.';

revoke execute on function
  public.community_statistics_recency(uuid, text, text) from anon, public;
grant execute on function
  public.community_statistics_recency(uuid, text, text) to authenticated;
