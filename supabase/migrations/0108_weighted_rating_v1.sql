-- 0108: corrected weighted Global Rating v1, schema and engine only.
-- Inert by itself: it adds input columns and engine functions that nothing
-- live calls yet, so it is safe to merge and push at any time. Ratings change
-- only when supabase/activation/0108_weighted_rating_v1_activate.sql is run,
-- separately, after the Product Owner release decision.
-- Frozen 2026-10-21: C=14, prior=5, q=26/27, half lifetime / half recency.
-- No attendance factor. Community/period rating and PFS remain unchanged.
-- Inputs are stored on immutable operational history rows, so detach/attach,
-- deletion and the existing account-merge replay all use the SAME engine.
-- Calculation uses numeric; the existing API/storage remains three decimals.
-- A value below 10 is never rounded up to 10.000.

set local lock_timeout = '15s';
lock table public.match_goals, public.match_results,
  public.match_team_assignments, public.matches, public.rating_history,
  public.users in share row exclusive mode;

alter table public.rating_history
  add column engine_version text,
  add column match_score numeric,
  add column played_at timestamptz,
  add column raw_rating_after numeric;
alter table public.rating_history
  add constraint rating_history_weighted_input_check check (
    engine_version is null or (
      engine_version = 'weighted_v1'
      and match_score is not null and match_score >= 0 and match_score < 10
      and played_at is not null
      and raw_rating_after is not null
      and raw_rating_after >= 0 and raw_rating_after < 10
    )
  );
alter table public.rating_history_archive
  add column engine_version text,
  add column match_score numeric,
  add column played_at timestamptz,
  add column raw_rating_after numeric;

comment on column public.rating_history.match_score is
  'weighted_v1 immutable match input; outcome reason is WIN/DRAW/LOSS, not an additive bonus.';
comment on column public.rating_history.raw_rating_after is
  'Unrounded weighted mean at this chronological prefix; overall_rating retains its three-decimal API.';

create or replace function public.weighted_match_score_v1(
  p_outcome text, p_goals integer, p_mvp boolean
) returns numeric
language plpgsql immutable strict set search_path = public, pg_temp
as $$
declare v_base numeric; v_budget numeric;
begin
  if p_goals < 0 then raise exception 'NEGATIVE_GOALS'; end if;
  case p_outcome
    when 'WIN' then v_base := 8.8; v_budget := 1.2;
    when 'DRAW' then v_base := 4.4; v_budget := 0.6;
    when 'LOSS' then v_base := 0; v_budget := 0.7;
    else raise exception 'INVALID_OUTCOME';
  end case;
  return v_base + v_budget * (
    (2::numeric / 3) * p_goals / (p_goals::numeric + 2)
    + case when p_mvp then 1::numeric / 3 else 0 end);
end;
$$;

-- Existing public rating reads and BTGE keep sorting the stored three-decimal
-- number, never the one-decimal label. Quantisation is at most 0.001, once per
-- prefix; neither H nor E ever feeds a rounded rating back into the calculation.
create or replace function public.weighted_rating_storage_v1(p_raw numeric)
returns numeric language sql immutable strict set search_path = public, pg_temp
as $$ select least(9.999::numeric, greatest(0::numeric, round(p_raw, 3))) $$;

-- Replace one active match input (or detach it), then replay the player's
-- chronological inputs. A correction reverses the affected suffix exactly
-- and appends its corrected replacement: no UPDATE/DELETE of audit evidence.
-- Unchanged earlier entries keep their IDs; new matches append just one row.
-- Fixed 24-place recurrence state prevents numeric scale growing with career length.
create or replace function public.replay_weighted_player_v1(
  p_user_id uuid, p_match_id uuid, p_attach boolean
) returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_inputs jsonb; v_new jsonb; v_old record; r record;
  v_cut timestamptz; v_expected_before numeric(5,3) := 5;
  v_before numeric(5,3); v_after numeric(5,3);
  v_sum numeric := 70; v_n integer := 14;
  v_num numeric(50,24) := 70; v_den numeric(50,24) := 14;
  v_q constant numeric := 26::numeric / 27;
  v_raw numeric;
begin
  if public.merge_rating_scope_excludes(p_user_id) then return; end if;
  select u.overall_rating into v_before from public.users u
    where u.id = p_user_id for update;
  if not found then return; end if;

  if exists (
    select 1 from public.rating_history h where h.user_id = p_user_id
      and h.reverses_id is null
      and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)
      and h.engine_version is distinct from 'weighted_v1'
  ) then raise exception 'WEIGHTED_REBASE_REQUIRED'; end if;

  select h.* into v_old from public.rating_history h
  where h.user_id = p_user_id and h.match_id = p_match_id
    and h.reverses_id is null
    and not exists (select 1 from public.rating_history x where x.reverses_id = h.id);
  if not p_attach and not found then return; end if;

  if p_attach then
    select jsonb_build_object(
      'match_id', m.id, 'played_at', m.start_at,
      'reason', case when mr.team_a_score = mr.team_b_score then 'DRAW'
        when (a.team = 'A' and mr.team_a_score > mr.team_b_score)
          or (a.team = 'B' and mr.team_b_score > mr.team_a_score) then 'WIN'
        else 'LOSS' end,
      'score', public.weighted_match_score_v1(
        case when mr.team_a_score = mr.team_b_score then 'DRAW'
          when (a.team = 'A' and mr.team_a_score > mr.team_b_score)
            or (a.team = 'B' and mr.team_b_score > mr.team_a_score) then 'WIN'
          else 'LOSS' end,
        coalesce((select sum(g.goals)::integer from public.match_goals g
          where g.match_id = m.id and g.user_id = p_user_id), 0),
        coalesce(mr.mvp_user_id = p_user_id, false)))
    into v_new
    from public.matches m
    join public.match_results mr on mr.match_id = m.id
    join public.match_team_assignments a
      on a.match_id = m.id and a.user_id = p_user_id
    where m.id = p_match_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'match_id', h.match_id, 'played_at', h.played_at,
    'reason', h.change_reason, 'score', h.match_score)), '[]'::jsonb)
  into v_inputs from public.rating_history h
  where h.user_id = p_user_id and h.match_id <> p_match_id
    and h.reverses_id is null
    and not exists (select 1 from public.rating_history x where x.reverses_id = h.id);

  if v_new is not null then v_inputs := v_inputs || jsonb_build_array(v_new); end if;

  -- Idempotence: applying an unchanged match must not grow the audit.
  if p_attach and v_new is not null and exists (
    select 1 from public.rating_history h
    where h.user_id = p_user_id and h.match_id = p_match_id
      and h.reverses_id is null
      and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)
      and h.match_score = (v_new->>'score')::numeric
      and h.played_at = (v_new->>'played_at')::timestamptz
      and h.change_reason = v_new->>'reason'
  ) then return; end if;

  v_cut := least(coalesce(v_old.played_at, 'infinity'::timestamptz),
    coalesce((v_new->>'played_at')::timestamptz, 'infinity'::timestamptz));

  for r in
    select h.* from public.rating_history h
    where h.user_id = p_user_id and h.reverses_id is null
      and (h.played_at, h.match_id) >= (v_cut, p_match_id)
      and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)
    order by h.entry_no desc
  loop
    perform public.apply_rating_delta(p_user_id, r.match_id, 'REVERSAL', -r.delta, r.id);
  end loop;
  select u.overall_rating into v_before from public.users u where u.id = p_user_id;

  for r in
    select * from jsonb_to_recordset(v_inputs)
      as x(match_id uuid, played_at timestamptz, reason text, score numeric)
    order by played_at, match_id
  loop
    v_sum := v_sum + r.score; v_n := v_n + 1;
    v_num := v_q * v_num + r.score; v_den := v_q * v_den + 1;
    v_raw := (v_sum / v_n + v_num / v_den) / 2;
    v_after := public.weighted_rating_storage_v1(v_raw);
    if (r.played_at, r.match_id) < (v_cut, p_match_id) then
      v_expected_before := v_after;
      continue;
    end if;
    if v_before <> v_expected_before then
      raise exception 'RATING_BASELINE_MISMATCH';
    end if;
    update public.users set overall_rating = v_after where id = p_user_id;
    insert into public.rating_history (
      user_id, match_id, change_reason, delta, rating_before, rating_after,
      engine_version, match_score, played_at, raw_rating_after
    ) values (
      p_user_id, r.match_id, r.reason, v_after - v_before, v_before, v_after,
      'weighted_v1', r.score, r.played_at, v_raw
    );
    v_before := v_after;
    v_expected_before := v_after;
  end loop;
  if v_before <> v_expected_before then raise exception 'RATING_BASELINE_MISMATCH'; end if;
end;
$$;


-- Rebase infrastructure also used by the explicit rollback script. It archives
-- the new input columns as well as the existing immutable audit and snapshots.
create or replace function public.rebase_rating_engine_v1(p_version text)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_run uuid; r record; v_h integer; v_u integer; v_m integer := 0;
begin
  set local lock_timeout = '15s';
  lock table public.match_goals, public.match_results,
    public.match_team_assignments, public.matches, public.rating_history,
    public.users in share row exclusive mode;
  if exists (select 1 from public.rating_rebase_runs where rebase_version = p_version)
    then raise exception 'REBASE_ALREADY_COMPLETED'; end if;

  insert into public.rating_rebase_runs(rebase_version)
    values(p_version) returning id into v_run;
  insert into public.rating_history_archive (
    rebase_version, id, entry_no, user_id, match_id, change_reason,
    delta, rating_before, rating_after, reverses_id, created_at,
    engine_version, match_score, played_at, raw_rating_after)
  select p_version, id, entry_no, user_id, match_id, change_reason,
    delta, rating_before, rating_after, reverses_id, created_at,
    engine_version, match_score, played_at, raw_rating_after
  from public.rating_history;
  get diagnostics v_h = row_count;
  insert into public.user_rating_archive(rebase_version, user_id, overall_rating)
    select p_version, id, overall_rating from public.users;
  get diagnostics v_u = row_count;
  delete from public.rating_history;
  update public.users set overall_rating = 5.000;
  for r in
    select m.id from public.matches m join public.match_results mr on mr.match_id = m.id
    order by m.start_at, m.id
  loop
    perform public.apply_match_rating_effects(r.id);
    v_m := v_m + 1;
  end loop;
  update public.rating_rebase_runs set completed_at = now(),
    archived_history_rows = v_h, archived_user_rows = v_u, replayed_matches = v_m,
    rebuilt_history_rows = (select count(*) from public.rating_history)
  where id = v_run;
end;
$$;

revoke all on function public.weighted_match_score_v1(text, integer, boolean)
  from public, anon, authenticated;
revoke all on function public.weighted_rating_storage_v1(numeric)
  from public, anon, authenticated;
revoke all on function public.replay_weighted_player_v1(uuid, uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.apply_match_rating_effects(uuid)
  from public, anon, authenticated;
revoke all on function public.reverse_match_rating_effects(uuid)
  from public, anon, authenticated;
revoke all on function public.rebase_rating_engine_v1(text)
  from public, anon, authenticated;
revoke execute on function public.rebase_ratings_to_0078(text) from service_role;
grant execute on function public.rebase_rating_engine_v1(text) to service_role;
