-- 0108 rollback, explicit operator action only. Run atomically.
-- Rebuilds the legacy engine from CURRENT match evidence (including results
-- recorded since activation); never restores a stale rating over new football.
-- Both generations of audit/ratings remain archived. Does not alter football
-- facts, community statistics, PFS, permissions, or remove the added columns.
begin;
set local lock_timeout = '15s';
lock table public.match_goals, public.match_results,
  public.match_team_assignments, public.matches, public.rating_history,
  public.users in share row exclusive mode;
do $$ begin
  if not exists (select 1 from public.rating_rebase_runs
    where rebase_version = '0108_weighted_v1' and completed_at is not null
      and rolled_back_at is null) then
    raise exception 'WEIGHTED_ENGINE_NOT_ACTIVE';
  end if;
end $$;
drop trigger matches_refresh_weighted_rating_time on public.matches;

CREATE OR REPLACE FUNCTION public.apply_match_rating_effects(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.reverse_match_rating_effects(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
begin
  for r in
    select h.id, h.user_id, h.delta
    from rating_history h
    where h.match_id = p_match_id
      and h.reverses_id is null
      and not exists (
        select 1 from rating_history x where x.reverses_id = h.id
      )
    order by h.entry_no desc
  loop
    perform apply_rating_delta(r.user_id, p_match_id, 'REVERSAL', -r.delta, r.id);
  end loop;
end;
$function$;
select public.rebase_rating_engine_v1('0108_rollback_0078');
update public.rating_rebase_runs set rolled_back_at = now()
  where rebase_version = '0108_weighted_v1';
grant execute on function public.rebase_ratings_to_0078(text) to service_role;
commit;
