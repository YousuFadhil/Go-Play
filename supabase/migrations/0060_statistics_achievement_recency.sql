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
-- ## Why this is `security definer`
--
-- **Because one of the five answers is global, and RLS cannot give a global
-- answer consistently.**
--
-- Four of the timestamps are about this community's matches, and any member can
-- already read those. The fifth is not. Highest Rated ranks the **Global**
-- Rating -- one number spanning every community a player has ever played in --
-- so the tie-break for it has to be global too, or it is breaking ties on a
-- different measure than the one being ranked.
--
-- `rating_history` is protected by `is_match_community_member(match_id,
-- auth.uid())`: a reader sees a rating entry only for a match in a community
-- *they* belong to. Under `security invoker` that produces a genuinely wrong
-- answer, not merely a partial one -- two members of the same community, both
-- authorized, looking at the same board with the same tied ratings, would be
-- shown **different orders**, because one of them happens to share a second
-- community with the tied player and the other does not. An ordering that
-- depends on who is looking is not an ordering.
--
-- So the function runs as its owner, and pays for that with the authorization
-- it now has to state itself:
--
--   * `auth.uid()` must exist -- no anonymous caller;
--   * the caller must be a **current member of `p_community_id`**, asked
--     directly through `is_community_member` rather than inferred from what a
--     base-table policy happened to return;
--   * both checks run **before any row is read**, so a refusal never depends on
--     what was found.
--
-- This is the same shape `community_join_code` (0055) uses for the same reason.
--
-- ## What it does not disclose
--
-- The widening is exactly one number: how recently a player last had a rating
-- change, wherever it happened. It is bounded deliberately:
--
--   * **No identifiers.** The match and the community behind that timestamp are
--     read inside the function and never returned. The output has six columns
--     and five of them are timestamps; there is no `match_id`, no
--     `community_id`, and no way to ask which match it was.
--   * **No history.** `max(start_at)` over effective entries -- not the entries,
--     not the deltas, not the ratings before and after.
--   * **No new population.** Rows come back only for players of the requested
--     community: the four event timestamps for whoever played in *its* matches,
--     and the rating timestamp only for its current members. Naming another
--     community here returns nothing, because the caller is not a member of it.
--
-- No policy is changed. `rating_history`, `matches`, `match_results`,
-- `match_goals`, `match_team_assignments` and `community_members` keep exactly
-- the SELECT policies they had; nothing is readable through the base tables
-- that was not readable before.

-- The read model ---------------------------------------------------------------------
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
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  -- Stated here rather than left to the base tables, because this function no
  -- longer runs under the caller's policies. Both questions are asked before a
  -- single row is read.
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Current membership of the community being asked about. This is the whole
  -- of the authorization: a non-member cannot enumerate a community's players
  -- through this function, and a member of one community cannot name another
  -- and receive its players.
  if not public.is_community_member(p_community_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return query
  with played as (
    -- `match_result_contribution`'s join, restricted to one community and one
    -- period. A row here is one player's participation in one match that has a
    -- recorded result -- which is exactly what the counters are built from, so
    -- the recency and the number it breaks ties for always describe the same
    -- matches.
    --
    -- `m.community_id = p_community_id` is the isolation as well as the filter:
    -- with RLS bypassed it is what keeps another community's football out of
    -- the answer entirely.
    select
      a.user_id as player_id,
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
      p.player_id,
      max(p.start_at) filter (where p.scored)  as last_goal_at,
      max(p.start_at) filter (where p.was_mvp) as last_mvp_at,
      -- Played participation, which is what the Most Active counter counts:
      -- being on the stored lineup of a match that has a result. Not
      -- registration, and not a reserve seat.
      max(p.start_at)                          as last_played_at,
      max(p.start_at) filter (where p.won)     as last_win_at
    from played p
    group by p.player_id
  ),
  rating as (
    -- **Global, and this is the reason the function is definer.** Highest Rated
    -- shows the Global Rating, so its tie-break spans every community the
    -- player has played in -- including ones the caller cannot see. Two
    -- authorized members of this community therefore get the same order as each
    -- other, which is the contract; under the caller's own policies they would
    -- not have.
    --
    -- No `community_id` filter on the match, deliberately. It also ignores
    -- `p_period_type` entirely: the rating has no periodic form, so neither has
    -- its recency, and the answer is the same in every period.
    --
    -- What leaves this CTE is one `max()`. The match and its community are read
    -- and discarded.
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
    -- not filtered out here. A player with no effective entry at all -- still on
    -- the opening 5.00, never rated -- gets null, which the caller sorts last.
    --
    -- Scoped to the community's **current members**, which is both the only
    -- population the Highest Rated board can rank and the boundary that keeps
    -- this from becoming a way to ask about anybody at all.
    select h.user_id as player_id, max(rm.start_at) as last_rating_at
    from rating_history h
    join matches rm on rm.id = h.match_id
    where h.reverses_id is null
      and not exists (
        select 1 from rating_history x where x.reverses_id = h.id
      )
      and exists (
        select 1 from community_members cm
        where cm.community_id = p_community_id and cm.user_id = h.user_id
      )
    group by h.user_id
  )
  -- Full join: a player may have counters without a rating event (a draw moves
  -- no rating) or a rating event without counters in this period.
  select
    coalesce(c.player_id, r.player_id),
    c.last_goal_at,
    c.last_mvp_at,
    c.last_played_at,
    c.last_win_at,
    r.last_rating_at
  from counters c
  full outer join rating r on r.player_id = c.player_id;
end;
$$;

comment on function public.community_statistics_recency(uuid, text, text) is
  'Per-player timestamps of the most recent goal, MVP, played match and win in '
  'one community and period, plus the most recent currently-effective rating '
  'event -- which is global and periodless, because the Global Rating it '
  'breaks ties for is. Every timestamp is matches.start_at. A read model over '
  'existing evidence: no stored state, and corrections are followed because the '
  'evidence itself moves. security definer so the global half is the same for '
  'every authorized viewer; it checks authentication and current membership of '
  'p_community_id itself, returns no match or community identifiers, and '
  'changes no policy -- see migration 0060.';

-- Default privileges on a new function include EXECUTE for PUBLIC, which for a
-- definer function would mean anybody. Revoked first, then granted to exactly
-- the role the client uses.
revoke execute on function
  public.community_statistics_recency(uuid, text, text) from anon, public;
grant execute on function
  public.community_statistics_recency(uuid, text, text) to authenticated;
