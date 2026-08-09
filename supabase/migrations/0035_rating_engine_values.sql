-- The approved rating values, restated.
--
-- The engine keeps its shape and loses none of its rules: the same four reasons
-- in the same order, the same audit, the same range, the same guard around an
-- absent MVP. What changes is what each reason is worth, and that a player's
-- goals are now worth at most as much in total as a loss costs.
--
--   winner  +0.10   loser  -0.10   draw  nothing
--   goal    +0.02 each, capped at +0.10 in one match
--   MVP     +0.05
--
-- The cap and the smaller MVP award are one rule, not two conveniences: the team
-- result is the most influential factor, so nothing a player does individually
-- may carry them past somebody who won. Five goals bring a loser back to level
-- (-0.10 + 0.10 = 0.00); five goals and the best player on the pitch bring them
-- to +0.05, which is still less than the +0.10 a winner who touched nothing
-- gains. Without the cap a sixth goal would break that, which is why it is
-- applied to the total rather than to each goal.
--
-- Backward compatible: no table, column, policy or grant is touched, and the
-- stored `numeric(4,2)` scale already holds hundredths. Idempotent: one
-- `create or replace function`.
--
-- Nothing recorded before this runs is rewritten. `rating_history.delta` is the
-- change that was *applied*, so old entries stay reversible on their own terms
-- and a reversal keeps subtracting what it actually added.
--
-- This is migration `0033`'s function with three numbers changed and the cap
-- added; the rest is restated only because `create or replace function` replaces
-- the whole body. The same values live in Dart as `ratingRules`, and
-- `integration/result_test.dart` holds the two to each other.
create or replace function public.apply_match_rating_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result match_results%rowtype;
  r record;
begin
  select * into v_result from match_results where match_id = p_match_id;
  if not found then return; end if;

  -- Outcome first, then goals, then the MVP. Any order reaches the same rating;
  -- a fixed one makes the audit read the same way every time.
  --
  -- A draw takes this branch not at all: it is the absence of a win and of a
  -- loss, so a drawn side gets no entry from the outcome.
  if v_result.team_a_score <> v_result.team_b_score then
    for r in
      select a.user_id,
        case
          when (a.team = 'A' and v_result.team_a_score > v_result.team_b_score)
            or (a.team = 'B' and v_result.team_b_score > v_result.team_a_score)
          then 'WIN' else 'LOSS' end as outcome
      from match_team_assignments a
      where a.match_id = p_match_id
      order by a.team, a.user_id
    loop
      perform apply_rating_delta(
        r.user_id, p_match_id, r.outcome,
        case when r.outcome = 'WIN' then 0.10 else -0.10 end
      );
    end loop;
  end if;

  -- One entry per scorer, carrying the whole of what their goals were worth.
  -- `least` is the cap: five goals reach 0.10 exactly and a sixth adds nothing.
  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', least(0.10, 0.02 * r.goals)
    );
  end loop;

  -- No MVP, no MVP award. The absence of a rating change is what "do not award"
  -- means here, and it is also what makes a later correction exact: there is no
  -- entry to reverse, so naming an MVP afterwards is an ordinary re-record.
  if v_result.mvp_user_id is not null then
    perform apply_rating_delta(
      v_result.mvp_user_id, p_match_id, 'MVP', 0.05
    );
  end if;
end;
$$;

revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;
