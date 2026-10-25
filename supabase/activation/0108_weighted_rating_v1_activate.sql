-- 0108 activation, explicit operator action only, after the separate
-- Product Owner release decision. Running this file changes every live
-- player's Global Rating immediately. Staging and production share the
-- database; this is not isolated by a staging deploy.
-- Kept outside supabase/migrations/ so `supabase db push` never applies it.
-- Requires migration 0108 first. The switch of the live result path and the
-- historical rebase are one transaction: there is no state where the weighted
-- path is live over unrebased legacy history (it would reject every result
-- with WEIGHTED_REBASE_REQUIRED). Undo with supabase/rollback/.
begin;
set local lock_timeout = '15s';

create or replace function public.apply_match_rating_effects(p_match_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare r record;
begin
  -- Lock affected player rows in UUID order as their replay is processed.
  for r in
    select u.id from public.users u where
      not public.merge_rating_scope_excludes(u.id) and (
        exists (select 1 from public.match_team_assignments a
          where a.match_id = p_match_id and a.user_id = u.id)
        or exists (select 1 from public.rating_history h
          where h.match_id = p_match_id and h.user_id = u.id
            and h.reverses_id is null
            and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)))
    order by u.id for update
  loop
    perform public.replay_weighted_player_v1(r.id, p_match_id, true);
  end loop;
end;
$$;

create or replace function public.reverse_match_rating_effects(p_match_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare r record;
begin
  for r in
    select u.id from public.users u
    where not public.merge_rating_scope_excludes(u.id)
      and exists (select 1 from public.rating_history h
        where h.match_id = p_match_id and h.user_id = u.id
          and h.reverses_id is null
          and not exists (select 1 from public.rating_history x where x.reverses_id = h.id))
    order by u.id for update
  loop
    perform public.replay_weighted_player_v1(r.id, p_match_id, false);
  end loop;
end;
$$;

-- Changing the played date changes recency/order even when the score is intact.
create or replace function public.refresh_weighted_match_time_v1()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.match_results where match_id = new.id) then
    perform public.apply_match_rating_effects(new.id);
  end if;
  return new;
end;
$$;
create trigger matches_refresh_weighted_rating_time
  after update of start_at on public.matches
  for each row when (old.start_at is distinct from new.start_at)
  execute function public.refresh_weighted_match_time_v1();
revoke all on function public.refresh_weighted_match_time_v1()
  from public, anon, authenticated;

lock table public.match_goals, public.match_results,
  public.match_team_assignments, public.matches, public.rating_history,
  public.users in share row exclusive mode;
select public.rebase_rating_engine_v1('0108_weighted_v1');
commit;
