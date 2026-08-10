-- Taking a result's counters back off.
--
-- Migration `0022` reversed a result's statistics with the same statement that
-- applied them — one `insert ... on conflict (user_id) do update`, handed a
-- contribution of -1 per counter. That cannot work, and the reason is worth
-- writing down: PostgreSQL validates a proposed row's CHECK constraints
-- **before** it looks for the conflict. So `(matches_played, goals) = (-1, -3)`
-- was rejected by `player_statistics_goals_check` even though the row already
-- existed and the statement would have taken the `do update` branch and left a
-- perfectly valid row behind.
--
-- What that broke was everything that takes a result away: correcting one, and
-- the `before delete on matches` trigger that gives a deleted match's ratings
-- and counters back. Both raised, so a correction was refused and a match with a
-- result could not be deleted at all.
--
-- The fix is to stop pretending the two directions are one statement. Adding a
-- result may have to create a counters row; taking one away never does, because
-- there is nothing to subtract from a player who was never added. So applying is
-- an upsert and reversing is an update, and the arithmetic they share is stated
-- once, below, rather than twice.
--
-- Scope: two functions, both `create or replace`. No table, column, constraint,
-- policy or trigger changes, and `0022` is left exactly as it was applied.

-- 1) What a result is worth to each player who played it ------------------------
-- One row per participant, carrying the numbers their counters move by. The
-- participants are the stored lineup — `KB-017` makes that the record of who
-- actually played, and a win belongs to the side a player was on.
--
-- A match with no recorded result yields no rows, which is what the two callers
-- below used to check for themselves.
create or replace function public.match_result_contribution(p_match_id uuid)
returns table (
  user_id uuid,
  played int,
  won int,
  lost int,
  drawn int,
  scored int,
  mvp int
)
language sql
security definer
stable
set search_path = public
as $$
  select
    a.user_id,
    1,
    case
      when (a.team = 'A' and r.team_a_score > r.team_b_score)
        or (a.team = 'B' and r.team_b_score > r.team_a_score)
      then 1 else 0 end,
    case
      when (a.team = 'A' and r.team_a_score < r.team_b_score)
        or (a.team = 'B' and r.team_b_score < r.team_a_score)
      then 1 else 0 end,
    case when r.team_a_score = r.team_b_score then 1 else 0 end,
    coalesce(g.goals, 0),
    case when a.user_id = r.mvp_user_id then 1 else 0 end
  from match_results r
  join match_team_assignments a on a.match_id = r.match_id
  left join match_goals g
    on g.match_id = a.match_id and g.user_id = a.user_id
  where r.match_id = p_match_id;
$$;

-- 2) Applying and reversing, as the two statements they are ---------------------
-- Reversing subtracts from rows that already exist. A player in the lineup with
-- no counters row is left alone rather than created at zero and decremented:
-- there is nothing of theirs recorded to take away.
create or replace function public.apply_match_statistics(
  p_match_id uuid,
  p_sign int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_sign < 0 then
    update player_statistics ps set
      matches_played = ps.matches_played - c.played,
      wins = ps.wins - c.won,
      losses = ps.losses - c.lost,
      draws = ps.draws - c.drawn,
      goals = ps.goals - c.scored,
      mvp_count = ps.mvp_count - c.mvp
    from match_result_contribution(p_match_id) c
    where ps.user_id = c.user_id;
    return;
  end if;

  insert into player_statistics as ps (
    user_id, matches_played, wins, losses, draws, goals, mvp_count
  )
  select c.user_id, c.played, c.won, c.lost, c.drawn, c.scored, c.mvp
  from match_result_contribution(p_match_id) c
  on conflict (user_id) do update set
    matches_played = ps.matches_played + excluded.matches_played,
    wins = ps.wins + excluded.wins,
    losses = ps.losses + excluded.losses,
    draws = ps.draws + excluded.draws,
    goals = ps.goals + excluded.goals,
    mvp_count = ps.mvp_count + excluded.mvp_count;
end;
$$;

-- `create or replace` keeps a function's privileges, so `apply_match_statistics`
-- stays revoked as `0022` left it. The new helper is stated here for the same
-- reason `0022` states them: no role reaches these through the API, and
-- `record_match_result` remains the only entry point.
revoke execute on function public.match_result_contribution(uuid)
  from anon, authenticated, public;
revoke execute on function public.apply_match_statistics(uuid, int)
  from anon, authenticated, public;
