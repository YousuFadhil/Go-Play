-- Repairing counters that stopped agreeing with the matches behind them.
--
-- The bug, and why it surfaced as a failed delete:
--
-- `match_result_contribution` computes what a match is worth to each player from
-- the lineup **as it stands now** — which side they are on decides win, loss or
-- draw. `apply_match_statistics(+1)` adds that at record time and
-- `apply_match_statistics(-1)` subtracts it at reversal time. The subtraction is
-- only the inverse of the addition while the lineup has not moved in between.
--
-- Until migration `0029`, `replace_match_lineup` moved players between sides
-- *without* reversing and reapplying the result's effects. So a player who was
-- on the winning side when the result was recorded banked a win, and if an
-- organizer then moved them to the losing side, the stored row still said `wins
-- = 1` while the evidence said `losses = 1`. Deleting that match ran
-- `apply_match_statistics(-1)`, which subtracted the *evidence's* loss from a
-- row that never held one — and `player_statistics_wins_check` refused the
-- whole transaction with `23514` and `wins = -1`.
--
-- The CHECK constraints are right and are not touched. What was wrong is the
-- stored aggregate: it is a sum over matches, so it can only be negative if it
-- disagrees with the matches. `0029` closed the way in — every lineup edit now
-- reverses and reapplies inside one transaction — but it could not repair rows
-- that were already wrong when it was applied. This does that.
--
-- `apply_match_statistics` is deliberately NOT changed. Clamping the
-- subtraction at zero would turn a detectable contradiction into a silent one,
-- and the arithmetic is correct as written once the data it operates on is.
--
-- Level 2 needs the same treatment and already has the tool for it:
-- `rebuild_community_statistics` from `0028` recomputes `community_statistics`
-- from the same evidence, and `community_statistics` carries the same `>= 0`
-- CHECKs, so it can fail a delete the same way.

-- 1) The evidence, per player -----------------------------------------------
-- One row per player who appears in the lineup of any match that has a recorded
-- result. This is the definition of the counters, stated as a query: a player's
-- record IS the sum over the matches they played, and anything else stored
-- against them is drift.
--
-- `matches_played` counts matches, not lineup rows — `unique (match_id,
-- user_id)` on `match_team_assignments` makes those the same thing, and counting
-- the join directly would double a player if that ever stopped being true.
create or replace function public.player_statistics_evidence(
  p_user_id uuid default null
)
returns table (
  user_id uuid,
  matches_played int,
  wins int,
  losses int,
  draws int,
  goals int,
  mvp_count int
)
language sql
security definer
stable
set search_path = public
as $$
  select
    a.user_id,
    count(distinct a.match_id)::int,
    count(*) filter (
      where (a.team = 'A' and r.team_a_score > r.team_b_score)
         or (a.team = 'B' and r.team_b_score > r.team_a_score))::int,
    count(*) filter (
      where (a.team = 'A' and r.team_a_score < r.team_b_score)
         or (a.team = 'B' and r.team_b_score < r.team_a_score))::int,
    count(*) filter (where r.team_a_score = r.team_b_score)::int,
    coalesce(sum(g.goals), 0)::int,
    count(*) filter (where a.user_id = r.mvp_user_id)::int
  from match_results r
  join match_team_assignments a on a.match_id = r.match_id
  left join match_goals g
    on g.match_id = a.match_id and g.user_id = a.user_id
  where p_user_id is null or a.user_id = p_user_id
  group by a.user_id;
$$;

revoke execute on function public.player_statistics_evidence(uuid)
  from anon, authenticated, public;

-- 2) The repair ---------------------------------------------------------------
-- Sets every counter to what the evidence says, for one player or for all.
--
-- Three cases, and all three are reachable:
--
--   * a row that disagrees with the evidence  -> corrected
--   * evidence with no row                    -> the row is created
--   * a row with no evidence left             -> zeroed, not deleted
--
-- Zeroed rather than deleted because `created_at` on the row is the only record
-- of when the player first finished a match, and a player whose every match has
-- since been removed has a career of zeros — which is what
-- `PlayerStatistics.none` already means to the application. Deleting the row
-- would say something subtly different and would lose the date.
--
-- Returns the number of rows it wrote, so a caller can see whether there was
-- anything to repair.
create or replace function public.rebuild_player_statistics(
  p_user_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int;
begin
  -- (a) Zero the scope first, so a row whose evidence has gone away is
  --     corrected rather than left holding its last value.
  update player_statistics ps set
    matches_played = 0, wins = 0, losses = 0,
    draws = 0, goals = 0, mvp_count = 0
  where p_user_id is null or ps.user_id = p_user_id;

  -- (b) Then write what the evidence says, creating the row where a player has
  --     a record but no counters.
  insert into player_statistics as ps (
    user_id, matches_played, wins, losses, draws, goals, mvp_count
  )
  select e.user_id, e.matches_played, e.wins, e.losses, e.draws, e.goals,
         e.mvp_count
  from player_statistics_evidence(p_user_id) e
  on conflict (user_id) do update set
    matches_played = excluded.matches_played,
    wins           = excluded.wins,
    losses         = excluded.losses,
    draws          = excluded.draws,
    goals          = excluded.goals,
    mvp_count      = excluded.mvp_count;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke execute on function public.rebuild_player_statistics(uuid)
  from anon, authenticated, public;

-- 3) Repair what is already stored -------------------------------------------
-- Both levels, once, now. Level 1 from the function above; Level 2 from `0028`'s
-- own rebuild, which recomputes `community_statistics` from the same evidence
-- and is the reason no second implementation is written here.
--
-- Neither is a no-op to run again: both set rather than accumulate, so this
-- migration is idempotent and either function can be re-run by hand if drift is
-- ever suspected again.
do $$
declare
  v_players int;
  v_community int;
begin
  v_players := public.rebuild_player_statistics();
  v_community := public.rebuild_community_statistics();
  raise notice 'repaired % player rows, % community rows', v_players, v_community;
end $$;
