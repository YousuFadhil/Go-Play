-- Global Rating values adjustment.
-- No backfill: historical rating_history rows remain unchanged.
-- Existing correction flow continues to reverse stored deltas exactly, then
-- applies the rules currently in force.

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

  for r in
    select a.user_id
    from match_team_assignments a
    where a.match_id = p_match_id
      and a.user_id is not null
    group by a.user_id
    order by a.user_id
  loop
    perform apply_rating_delta(r.user_id, p_match_id, 'PARTICIPATION', 0.005);
  end loop;

  for r in
    select a.user_id, min(a.team) as team
    from match_team_assignments a
    where a.match_id = p_match_id
      and a.user_id is not null
    group by a.user_id
    order by min(a.team), a.user_id
  loop
    if v_result.team_a_score = v_result.team_b_score then
      perform apply_rating_delta(r.user_id, p_match_id, 'DRAW', 0.010);
    elsif (r.team = 'A' and v_result.team_a_score > v_result.team_b_score)
       or (r.team = 'B' and v_result.team_b_score > v_result.team_a_score) then
      perform apply_rating_delta(r.user_id, p_match_id, 'WIN', 0.100);
    else
      perform apply_rating_delta(r.user_id, p_match_id, 'LOSS', -0.100);
    end if;
  end loop;

  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
      and g.user_id is not null
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', least(0.070, 0.010 * r.goals)
    );
  end loop;

  if v_result.mvp_user_id is not null then
    perform apply_rating_delta(
      v_result.mvp_user_id, p_match_id, 'MVP', 0.020
    );
  end if;
end;
$$;

revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;
