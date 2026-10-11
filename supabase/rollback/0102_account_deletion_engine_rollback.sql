-- == rollback/0102_account_deletion_engine_rollback.sql ==
-- Puts the database back to what it was before 0102: the deletion engine and its entry points gone, the
-- merge executor and the deletion preview as 0101 and 0099 left them, `users_id_fkey` back.
--
-- **It refuses once an account has been deleted.** A deletion cannot be undone, and the stand-in profile
-- of a deleted account has no Auth user, so `users_id_fkey` could not be put back over it; dropping the
-- stand-in would erase the history it carries. With none, it loses nothing: 0102 added functions, a
-- trigger and a column that is NULL everywhere.
--
-- Roll the client back with it: the previous client has no deletion action, and the current client's
-- merge and deletion screens call the `delete-account` Edge Function.
--
-- Safe to run again.

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'users' and column_name = 'deleted_at') then
    if exists (select 1 from public.users where deleted_at is not null) then
      raise exception 'ROLLBACK_REFUSED_DELETED_ACCOUNTS_EXIST';
    end if;
  end if;
  if exists (select 1 from public.admin_audit_log where action = 'USER_ACCOUNT_DELETED') then
    raise exception 'ROLLBACK_REFUSED_DELETED_ACCOUNTS_EXIST';
  end if;
end
$$;

drop trigger if exists auth_user_deleted_anonymize_profile on auth.users;
drop function if exists public.handle_auth_user_deleted();

drop function if exists public.delete_my_account();
drop function if exists public.admin_delete_account(uuid);
drop function if exists public.preview_my_account_deletion();
drop function if exists public.delete_account_core(uuid);
drop function if exists public.anonymize_user_profile(uuid);
drop function if exists public.account_football_evidence(uuid);
drop function if exists public.account_deletion_blockers(uuid);
drop function if exists public.deleted_player_name();

-- the merge executor, as 0101 defined it
create or replace function public.admin_merge_accounts(
  p_retained_user_id uuid,
  p_source_user_id uuid,
  p_resolutions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_doc jsonb;
  v_blockers text[];
  v_res_ids uuid[] := '{}';
  v_res_keep text[] := '{}';
  v_entry jsonb;
  v_mid uuid;
  v_dropped uuid;
  v_norm jsonb := '[]'::jsonb;
  v_shared_ids uuid[];
  v_missing uuid[];
  v_unknown uuid[];
  v_codes text[];
  v_ref record;
  v_c record;
  v_m record;
  v_before jsonb;
  v_after jsonb;
  v_n bigint;
  v_i int;
  v_name text;
  v_rating_before numeric;
  v_rating_after numeric;
  v_rating_reset numeric;
  v_replayed int := 0;
  v_drop_rank int;
  v_keep_rank int;
  v_reversed int := 0;
  v_audit uuid;
  v_restore_ids uuid[] := '{}';
  -- what the merge reports, and writes into the one audit event
  c_dropped_registrations bigint := 0;
  c_dropped_lineup_places bigint := 0;
  c_moved_registrations bigint := 0;
  c_moved_lineup_places bigint := 0;
  c_moved_goal_rows bigint := 0;
  c_moved_mvp_awards bigint := 0;
  c_communities_transferred bigint := 0;
  c_memberships_moved bigint := 0;
  c_memberships_merged bigint := 0;
  c_roles_upgraded bigint := 0;
  c_matches_reattributed bigint := 0;
  c_team_awards_moved bigint := 0;
  c_push_tokens_invalidated bigint := 0;
  c_audit_redacted bigint := 0;
begin
  -- ---- 1. who may ask -------------------------------------------------------
  if v_caller is null
     or not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = v_caller) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- ---- 2. arguments ---------------------------------------------------------
  if p_retained_user_id is null or p_source_user_id is null then
    raise exception 'USER_NOT_FOUND';
  end if;
  if p_retained_user_id = p_source_user_id then
    raise exception 'SAME_ACCOUNT';
  end if;
  if p_retained_user_id = v_caller or p_source_user_id = v_caller then
    raise exception 'CANNOT_MERGE_SELF';
  end if;

  if p_resolutions is null or jsonb_typeof(p_resolutions) <> 'array'
     or jsonb_array_length(p_resolutions) > 100 then
    raise exception 'RESOLUTIONS_INVALID';
  end if;
  for v_entry in select e from jsonb_array_elements(p_resolutions) e loop
    if jsonb_typeof(v_entry) <> 'object'
       or (v_entry->>'keep') is null
       or (v_entry->>'keep') not in ('retained', 'source') then
      raise exception 'RESOLUTIONS_INVALID';
    end if;
    begin
      v_mid := (v_entry->>'match_id')::uuid;
    exception when others then
      raise exception 'RESOLUTIONS_INVALID';
    end;
    if v_mid is null or v_mid = any (v_res_ids) then
      raise exception 'RESOLUTIONS_INVALID';
    end if;
    v_res_ids := v_res_ids || v_mid;
    v_res_keep := v_res_keep || (v_entry->>'keep');
    v_norm := v_norm || jsonb_build_array(
      jsonb_build_object('match_id', v_mid, 'keep', v_entry->>'keep'));
  end loop;

  -- One merge at a time, anywhere: a rare administrative act, and the cheapest
  -- way to rule out two merges that share a community or a match deadlocking.
  perform pg_advisory_xact_lock(hashtextextended('goplay.admin_merge_accounts', 0));

  -- ---- 3. lock, in a fixed order -------------------------------------------
  perform 1
    from public.users u
   where u.id in (p_retained_user_id, p_source_user_id)
   order by u.id
     for update;
  -- Both must still exist AFTER the lock: a second request for the same source,
  -- queued behind the first, finds the source gone and stops here.
  if (select count(*) from public.users u
       where u.id in (p_retained_user_id, p_source_user_id)) <> 2 then
    raise exception 'USER_NOT_FOUND';
  end if;

  perform 1
    from public.communities c
   where c.owner_id = p_source_user_id
      or c.id in (select cm.community_id from public.community_members cm
                   where cm.user_id in (p_retained_user_id, p_source_user_id))
   order by c.id
     for update;

  perform 1
    from public.matches m
   where m.created_by = p_source_user_id
      or m.id in (
           select r.match_id from public.match_registrations r
            where r.user_id in (p_retained_user_id, p_source_user_id)
           union
           select t.match_id from public.match_team_assignments t
            where t.user_id in (p_retained_user_id, p_source_user_id)
           union
           select g.match_id from public.match_goals g
            where g.user_id in (p_retained_user_id, p_source_user_id)
           union
           select mr.match_id from public.match_results mr
            where mr.mvp_user_id in (p_retained_user_id, p_source_user_id)
           union
           select h.match_id from public.rating_history h
            where h.user_id in (p_retained_user_id, p_source_user_id))
   order by m.id
     for update;

  -- ---- 4. the switches, bound to this transaction and to these two accounts ---
  perform set_config('goplay.account_merge', 'tx:' || txid_current()::text, true);
  perform set_config('goplay.account_merge_users',
                     p_retained_user_id::text || ',' || p_source_user_id::text, true);

  -- ---- 5. a reference this function does not know about ---------------------
  -- Deleting the source cascades through every foreign key to `users`. If a later
  -- migration adds one this function has never heard of, a merge must refuse
  -- rather than let that cascade take rows nobody decided about.
  for v_ref in
    select cl.relname::text as tbl, a.attname::text as col
      from pg_constraint k
      join pg_class cl on cl.oid = k.conrelid
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
     where k.contype = 'f'
       and k.confrelid = 'public.users'::regclass
       and cl.relnamespace = 'public'::regnamespace
  loop
    if (v_ref.tbl || '.' || v_ref.col) not in (
         'communities.owner_id', 'community_members.user_id',
         'community_statistics.user_id', 'match_goals.user_id',
         'match_professional_guests.created_by', 'match_registrations.user_id',
         'match_results.mvp_user_id', 'match_results.recorded_by',
         'match_team_assignments.user_id', 'matches.created_by',
         'notification_push_preferences.user_id', 'notification_push_tokens.user_id',
         'notifications.user_id', 'player_statistics.user_id',
         'rating_history.user_id', 'system_admins.user_id') then
      raise exception 'MERGE_UNHANDLED_REFERENCE'
        using detail = v_ref.tbl || '.' || v_ref.col;
    end if;
  end loop;

  -- ---- 6. the preview, again, in this transaction ----------------------------
  v_doc := public.admin_preview_account_merge(p_retained_user_id, p_source_user_id);
  v_blockers := array(
    select e->>'code'
      from jsonb_array_elements(v_doc->'findings') e
     where e->>'severity' = 'BLOCKER'
     order by 1);
  if cardinality(v_blockers) > 0 then
    raise exception 'MERGE_BLOCKED' using detail = array_to_string(v_blockers, ',');
  end if;
  -- The picture is removed through the Storage API BEFORE this runs (the
  -- `admin-merge-accounts` Edge Function). Not removed means not called through it: refuse
  -- rather than leave a public file behind a deleted account.
  if cardinality(public.merge_source_stored_files(p_source_user_id)) > 0 then
    raise exception 'SOURCE_FILES_REMAIN';
  end if;

  -- ---- 7. the admin's explicit choices ------------------------------------------
  v_shared_ids := array(
    select s.match_id
      from public.merge_shared_matches(p_retained_user_id, p_source_user_id) s
     order by 1);
  v_missing := array(select x from unnest(v_shared_ids) x where x <> all (v_res_ids));
  if cardinality(v_missing) > 0 then
    raise exception 'RESOLUTION_REQUIRED'
      using detail = array_to_string(v_missing[1:25], ',');
  end if;
  v_unknown := array(select x from unnest(v_res_ids) x where x <> all (v_shared_ids));
  if cardinality(v_unknown) > 0 then
    raise exception 'RESOLUTION_UNKNOWN_MATCH'
      using detail = array_to_string(v_unknown[1:25], ',');
  end if;
  for v_i in 1 .. coalesce(cardinality(v_res_ids), 0) loop
    -- keeping the retained account's side removes the source's, and vice versa
    v_codes := public.merge_participation_blockers(
      v_res_ids[v_i],
      case when v_res_keep[v_i] = 'retained' then p_source_user_id
           else p_retained_user_id end);
    if cardinality(v_codes) > 0 then
      raise exception 'RESOLUTION_BLOCKED'
        using detail = v_res_ids[v_i]::text || ':' || array_to_string(v_codes, '+');
    end if;
  end loop;

  -- ---- 8. what must not change ---------------------------------------------------
  v_before := public.merge_invariants(p_retained_user_id, p_source_user_id);
  select u.overall_rating into v_rating_before
    from public.users u where u.id = p_retained_user_id;
  select u.full_name into v_name
    from public.users u where u.id = p_retained_user_id;

  -- ---- 9a. remove the dropped side of every shared match -------------------------
  for v_i in 1 .. coalesce(cardinality(v_res_ids), 0) loop
    v_mid := v_res_ids[v_i];
    -- the account whose participation goes
    v_dropped := case when v_res_keep[v_i] = 'retained'
                      then p_source_user_id else p_retained_user_id end;

    delete from public.match_registrations r
     where r.match_id = v_mid and r.user_id = v_dropped;
    get diagnostics v_n = row_count;
    c_dropped_registrations := c_dropped_registrations + v_n;
    if v_n > 0 and exists (select 1 from public.matches m
                            where m.id = v_mid and m.end_at > now()
                              and m.status <> 'completed') then
      v_restore_ids := v_restore_ids || v_mid;
    end if;

    delete from public.match_team_assignments t
     where t.match_id = v_mid and t.user_id = v_dropped;
    get diagnostics v_n = row_count;
    c_dropped_lineup_places := c_dropped_lineup_places + v_n;
    if v_n > 0 and exists (select 1 from public.matches m
                            where m.id = v_mid and m.end_at > now()
                              and m.status <> 'completed')
       and not (v_mid = any (v_restore_ids)) then
      v_restore_ids := v_restore_ids || v_mid;
    end if;
  end loop;

  -- ---- 9b. move every other football record from the source to the retained ------
  update public.match_registrations
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_registrations = row_count;

  update public.match_team_assignments
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_lineup_places = row_count;

  update public.match_goals
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_goal_rows = row_count;

  update public.match_results
     set mvp_user_id = p_retained_user_id
   where mvp_user_id = p_source_user_id;
  get diagnostics c_moved_mvp_awards = row_count;

  update public.team_of_period_awards
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_team_awards_moved = row_count;

  -- who did it, who confirmed it, who generated it: attribution follows the person
  update public.matches
     set created_by = p_retained_user_id
   where created_by = p_source_user_id;
  get diagnostics c_matches_reattributed = row_count;

  update public.match_results
     set recorded_by = p_retained_user_id
   where recorded_by = p_source_user_id;
  update public.match_professional_guests
     set created_by = p_retained_user_id
   where created_by = p_source_user_id;
  update public.match_participation_state
     set confirmed_by = p_retained_user_id
   where confirmed_by = p_source_user_id;
  update public.btge_generation_runs
     set generated_by = p_retained_user_id
   where generated_by = p_source_user_id;
  update public.users
     set suspended_by = p_retained_user_id
   where suspended_by = p_source_user_id and id <> p_source_user_id;
  update public.communities
     set suspended_by = p_retained_user_id
   where suspended_by = p_source_user_id;

  -- ---- 10. communities: ownership passes, memberships merge, the higher role stays
  update public.communities
     set owner_id = p_retained_user_id
   where owner_id = p_source_user_id;
  get diagnostics c_communities_transferred = row_count;

  for v_c in
    select a.id as keep_id, a.role as keep_role, b.id as drop_id, b.role as drop_role
      from public.community_members a
      join public.community_members b
        on b.community_id = a.community_id and b.user_id = p_source_user_id
     where a.user_id = p_retained_user_id
     order by a.community_id
  loop
    v_drop_rank := case v_c.drop_role when 'owner' then 3 when 'admin' then 2 else 1 end;
    v_keep_rank := case v_c.keep_role when 'owner' then 3 when 'admin' then 2 else 1 end;
    if v_drop_rank > v_keep_rank then
      update public.community_members set role = v_c.drop_role where id = v_c.keep_id;
      c_roles_upgraded := c_roles_upgraded + 1;
    end if;
    delete from public.community_members where id = v_c.drop_id;
    c_memberships_merged := c_memberships_merged + 1;
  end loop;

  update public.community_members
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_memberships_moved = row_count;

  -- ---- 11. the retained player's ratings, recalculated chronologically -----------
  -- Only the retained player moves: the engine's one write path stands aside for
  -- everyone else while this is set (section 3). First every entry still in effect
  -- is reversed, newest first, with the engine's own reversal -- an append-only
  -- trail, nothing is deleted -- then every recorded result the retained player
  -- now has evidence in is replayed oldest first, exactly as the one-time rebase
  -- of 0082 did, through the engine itself.
  perform set_config('goplay.rating_replay_user', p_retained_user_id::text, true);

  for v_m in
    select h.match_id
      from public.rating_history h
     where h.user_id = p_retained_user_id
       and h.reverses_id is null
       and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)
     group by h.match_id
     order by max(h.entry_no) desc
  loop
    perform public.reverse_match_rating_effects(v_m.match_id);
    v_reversed := v_reversed + 1;
  end loop;

  select u.overall_rating into v_rating_reset
    from public.users u where u.id = p_retained_user_id;
  if v_rating_reset is distinct from 5.000 then
    raise exception 'RATING_BASELINE_MISMATCH'
      using detail = coalesce(v_rating_reset::text, 'null');
  end if;

  for v_m in
    select m.id
      from public.matches m
      join public.match_results r on r.match_id = m.id
     where exists (select 1 from public.match_team_assignments a
                    where a.match_id = m.id and a.user_id = p_retained_user_id)
        or exists (select 1 from public.match_goals g
                    where g.match_id = m.id and g.user_id = p_retained_user_id)
        or r.mvp_user_id = p_retained_user_id
     order by m.start_at, m.id
  loop
    perform public.apply_match_rating_effects(v_m.id);
    v_replayed := v_replayed + 1;
  end loop;

  perform set_config('goplay.rating_replay_user', '', true);

  select u.overall_rating into v_rating_after
    from public.users u where u.id = p_retained_user_id;

  -- The replayed chain has to be one unbroken chain from the baseline to the rating.
  if exists (
       select 1
         from (select h.rating_before, h.rating_after,
                      lag(h.rating_after) over (order by h.entry_no) as prev_after,
                      row_number() over (order by h.entry_no) as rn
                 from public.rating_history h
                where h.user_id = p_retained_user_id
                  and h.entry_no > (select coalesce(max(x.entry_no), 0)
                                      from public.rating_history x
                                     where x.user_id = p_retained_user_id
                                       and x.reverses_id is not null)) c
        where c.rn > 1 and c.rating_before is distinct from c.prev_after) then
    raise exception 'RATING_CHAIN_BROKEN';
  end if;

  -- ---- 12. the retained player's statistics, from the evidence -----------------
  -- Player statistics have a rebuild scoped to one player. Community statistics
  -- are rebuilt per community for EVERYONE, which would rewrite other players'
  -- rows; this does the same work for the retained player alone.
  perform public.rebuild_player_statistics(p_retained_user_id);

  update public.community_statistics cs
     set matches_played = 0, wins = 0, losses = 0, draws = 0, goals = 0, mvp_count = 0
   where cs.user_id = p_retained_user_id
     and (cs.matches_played, cs.wins, cs.losses, cs.draws, cs.goals, cs.mvp_count)
         is distinct from (0, 0, 0, 0, 0, 0);

  insert into public.community_statistics as cs (
    community_id, period_type, period_key, user_id,
    matches_played, wins, losses, draws, goals, mvp_count
  )
  select e.community_id, e.period_type, e.period_key, e.user_id,
         e.played, e.won, e.lost, e.drawn, e.scored, e.mvp
    from (select c.community_id, c.period_type, c.period_key, c.user_id,
                 sum(c.played)::int as played, sum(c.won)::int as won,
                 sum(c.lost)::int as lost, sum(c.drawn)::int as drawn,
                 sum(c.scored)::int as scored, sum(c.mvp)::int as mvp
            from public.matches m
            cross join lateral public.match_community_contribution(m.id) c
           where c.user_id = p_retained_user_id
             and m.id in (select a.match_id from public.match_team_assignments a
                           where a.user_id = p_retained_user_id)
           group by c.community_id, c.period_type, c.period_key, c.user_id) e
  on conflict (community_id, period_type, period_key, user_id) do update set
    matches_played = excluded.matches_played,
    wins           = excluded.wins,
    losses         = excluded.losses,
    draws          = excluded.draws,
    goals          = excluded.goals,
    mvp_count      = excluded.mvp_count;

  insert into public.community_statistics (community_id, period_type, period_key, user_id)
  select cm.community_id, 'overall', 'overall', cm.user_id
    from public.community_members cm
   where cm.user_id = p_retained_user_id
  on conflict (community_id, period_type, period_key, user_id) do nothing;

  delete from public.community_statistics cs
   where cs.user_id = p_retained_user_id
     and cs.period_type <> 'overall'
     and cs.matches_played = 0 and cs.wins = 0 and cs.losses = 0
     and cs.draws = 0 and cs.goals = 0 and cs.mvp_count = 0;

  -- ---- a roster that lost a registration is a roster like any other -------------
  -- For a match that has not been played, removing a registration may let a reserve
  -- in. That is a real change to other people's places and is captured and notified
  -- exactly as a cancellation would be, so the switch is off while it runs.
  perform set_config('goplay.account_merge', '', true);
  for v_i in 1 .. coalesce(cardinality(v_restore_ids), 0) loop
    perform public.rebalance_roster(v_restore_ids[v_i]);
    perform public.recompute_match_status(v_restore_ids[v_i]);
  end loop;
  perform set_config('goplay.account_merge', 'tx:' || txid_current()::text, true);

  -- ---- 13. the source's personal operational data, the mapping, the one event ----
  -- Push preferences: the retained account's stay as they are, and the source's go
  -- with it. Tokens are invalidated first, by name, rather than left to the cascade.
  delete from public.notification_push_tokens where user_id = p_source_user_id;
  get diagnostics c_push_tokens_invalidated = row_count;
  delete from public.product_activity_last_seen where user_id = p_source_user_id;

  -- The audit entries that name the source stay, with their id, actor and target UUIDs,
  -- action, reason, metadata and date. Only the e-mail of the actor and the name of the
  -- target -- the two columns that identify a person -- are emptied.
  update public.admin_audit_log a
     set actor_email_snapshot = case when a.actor_user_id = p_source_user_id
                                     then null else a.actor_email_snapshot end,
         target_label_snapshot = case when a.target_type = 'USER'
                                           and a.target_id = p_source_user_id
                                      then null else a.target_label_snapshot end
   where a.actor_user_id = p_source_user_id
      or (a.target_type = 'USER' and a.target_id = p_source_user_id);
  get diagnostics c_audit_redacted = row_count;

  insert into public.account_merge_map (source_user_id, retained_user_id)
  values (p_source_user_id, p_retained_user_id);

  v_audit := public.record_admin_audit(
    'USER_ACCOUNTS_MERGED', 'USER', p_retained_user_id, v_name, null,
    jsonb_build_object(
      'source_user_id', p_source_user_id,
      'resolutions', v_norm,
      'dropped', jsonb_build_object(
        'registrations', c_dropped_registrations,
        'lineup_places', c_dropped_lineup_places),
      'moved', jsonb_build_object(
        'registrations', c_moved_registrations,
        'lineup_places', c_moved_lineup_places,
        'goal_rows', c_moved_goal_rows,
        'mvp_awards', c_moved_mvp_awards,
        'team_awards', c_team_awards_moved,
        'communities_transferred', c_communities_transferred,
        'memberships_moved', c_memberships_moved,
        'memberships_merged', c_memberships_merged,
        'roles_upgraded', c_roles_upgraded,
        'created_matches', c_matches_reattributed),
      'rating', jsonb_build_object(
        'before', v_rating_before,
        'after', v_rating_after,
        'matches_reversed', v_reversed,
        'matches_replayed', v_replayed),
      'push_tokens_invalidated', c_push_tokens_invalidated,
      'audit_entries_redacted', c_audit_redacted));

  -- ---- 14. nothing of the source may be left, then the source goes ---------------
  if exists (select 1 from public.communities where owner_id = p_source_user_id)
     or exists (select 1 from public.community_members where user_id = p_source_user_id)
     or exists (select 1 from public.match_registrations where user_id = p_source_user_id)
     or exists (select 1 from public.match_team_assignments where user_id = p_source_user_id)
     or exists (select 1 from public.match_goals where user_id = p_source_user_id)
     or exists (select 1 from public.match_results
                 where mvp_user_id = p_source_user_id or recorded_by = p_source_user_id)
     or exists (select 1 from public.matches where created_by = p_source_user_id)
     or exists (select 1 from public.match_professional_guests
                 where created_by = p_source_user_id)
     or exists (select 1 from public.admin_audit_log a
                 where (a.actor_user_id = p_source_user_id
                        and a.actor_email_snapshot is not null)
                    or (a.target_type = 'USER' and a.target_id = p_source_user_id
                        and a.target_label_snapshot is not null))
     or cardinality(public.merge_source_stored_files(p_source_user_id)) > 0 then
    raise exception 'MERGE_RESIDUAL_REFERENCE';
  end if;

  v_after := public.merge_invariants(p_retained_user_id, p_source_user_id);
  if v_after is distinct from v_before then
    raise exception 'MERGE_INVARIANT_BROKEN'
      using detail = (select string_agg(k, ',' order by k)
                        from jsonb_object_keys(v_before) k
                       where v_before->k is distinct from v_after->k);
  end if;

  -- The Auth deletion and everything above are one transaction. Deleting the row
  -- cascades to `public.users` and to the source's identities, sessions and
  -- one-time tokens; a failure here undoes the whole merge.
  --
  -- Two Auth tables name the user WITHOUT a foreign key (checked on the live
  -- project): `refresh_tokens.user_id` (text) and `flow_state.user_id`. A refresh
  -- token normally goes with its session, but one with no session would outlive the
  -- user, and a pending sign-in flow carries an authorisation code. Both are removed
  -- by name, first, so nothing that could still sign the source in is left behind.
  delete from auth.refresh_tokens where user_id = p_source_user_id::text;
  delete from auth.flow_state where user_id = p_source_user_id;

  delete from auth.users where id = p_source_user_id;
  get diagnostics v_n = row_count;
  if v_n <> 1
     or exists (select 1 from public.users where id = p_source_user_id)
     or exists (select 1 from auth.identities where user_id = p_source_user_id)
     or exists (select 1 from auth.sessions where user_id = p_source_user_id)
     or exists (select 1 from auth.refresh_tokens where user_id = p_source_user_id::text)
     or exists (select 1 from auth.flow_state where user_id = p_source_user_id) then
    raise exception 'AUTH_DELETE_INCOMPLETE';
  end if;

  perform set_config('goplay.account_merge', '', true);
  perform set_config('goplay.account_merge_users', '', true);

  return jsonb_build_object(
    'merged', true,
    'retained_user_id', p_retained_user_id,
    'source_user_id', p_source_user_id,
    'audit_id', v_audit,
    'dropped', jsonb_build_object(
      'registrations', c_dropped_registrations,
      'lineup_places', c_dropped_lineup_places),
    'moved', jsonb_build_object(
      'registrations', c_moved_registrations,
      'lineup_places', c_moved_lineup_places,
      'goal_rows', c_moved_goal_rows,
      'mvp_awards', c_moved_mvp_awards,
      'team_awards', c_team_awards_moved,
      'communities_transferred', c_communities_transferred,
      'memberships_moved', c_memberships_moved,
      'memberships_merged', c_memberships_merged,
      'roles_upgraded', c_roles_upgraded,
      'created_matches', c_matches_reattributed),
    'rating', jsonb_build_object(
      'before', v_rating_before,
      'after', v_rating_after,
      'matches_replayed', v_replayed),
    'audit_entries_redacted', c_audit_redacted);
end;
$$;

comment on function public.admin_merge_accounts(uuid, uuid, jsonb) is
  'Platform Admin: folds a source account into a retained one and removes the '
  'source for good -- from public.users and auth.users, with its identities and '
  'sessions -- in ONE transaction. Needs the admin''s explicit choice for every '
  'match both accounts took part in. Refuses (MERGE_BLOCKED, RESOLUTION_*) rather '
  'than discard goals, an MVP award, a result or a confirmed lineup. Recalculates '
  'the retained player''s ratings chronologically and rebuilds their statistics; '
  'touches no other player''s. Empties the name and e-mail snapshots of the audit '
  'entries that name the source, writes one USER_ACCOUNTS_MERGED audit event and one '
  'row of account_merge_map. Refuses while the source still has a stored profile '
  'picture (SOURCE_FILES_REMAIN): the admin-merge-accounts Edge Function removes it '
  'first. System Admin only (NOT_AUTHORIZED). Migration 0101.';

-- the deletion preview, as 0099 defined it
create or replace function public.admin_preview_account_deletion(p_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_limit constant int := 25;
  v_snapshot jsonb;
  v_counts jsonb;
  v_flags record;
  v_owned_total bigint;
  v_owned_items jsonb;
  v_created_total bigint;
  v_created_by_status jsonb;
  v_created_items jsonb;
  v_personal jsonb;
  v_historical jsonb;
  v_preserved jsonb;
  v_findings jsonb;
  v_history_evidence bigint;
  v_identities bigint;
begin
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  v_snapshot := public.admin_preview_account_snapshot(p_user_id);
  v_counts := v_snapshot->'counts';

  select (u.avatar_path is not null) as has_avatar,
         (u.date_of_birth is not null) as has_dob,
         (u.default_wilayat_code is not null) as has_location,
         (btrim(u.phone) <> '') as has_phone
    into v_flags
    from public.users u
   where u.id = p_user_id;

  select count(*) into v_identities
    from auth.identities i
   where i.user_id = p_user_id;

  -- ---- communities the account owns: ownership must be transferred -----------
  select count(*) into v_owned_total
    from public.communities c
   where c.owner_id = p_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_owned_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'is_active', c.is_active,
                   'member_count',
                     (select count(*) from public.community_members cm
                       where cm.community_id = c.id),
                   'other_admin_count',
                     (select count(*) from public.community_members cm
                       where cm.community_id = c.id and cm.role = 'admin'
                         and cm.user_id <> p_user_id),
                   'match_count',
                     (select count(*) from public.matches m
                       where m.community_id = c.id)) as item,
                 row_number() over (order by c.name, c.id) as rn
            from public.communities c
           where c.owner_id = p_user_id) s
   where s.rn <= v_limit;

  -- ---- matches the account created: matches.created_by cannot be left dangling
  select count(*) into v_created_total
    from public.matches m
   where m.created_by = p_user_id;

  select coalesce(jsonb_object_agg(g.status, g.n), '{}'::jsonb)
    into v_created_by_status
    from (select m.status, count(*) as n
            from public.matches m
           where m.created_by = p_user_id
           group by m.status) g;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_created_items
    from (select jsonb_build_object(
                   'match_id', m.id,
                   'title', m.title,
                   'community_name', c.name,
                   'status', m.status,
                   'start_at', m.start_at,
                   'is_historical', m.is_historical,
                   'has_result',
                     exists (select 1 from public.match_results mr
                              where mr.match_id = m.id)) as item,
                 row_number() over (order by m.start_at desc, m.id) as rn
            from public.matches m
            join public.communities c on c.id = m.community_id
           where m.created_by = p_user_id) s
   where s.rn <= v_limit;

  -- ---- personal data this account holds ----------------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n) order by f.code),
           '[]'::jsonb)
    into v_personal
    from (values
      ('PROFILE', 1::bigint),
      ('EMAIL_ADDRESS',
         case when nullif(v_snapshot->'account'->>'email', '') is not null then 1 else 0 end),
      ('SIGN_IN_IDENTITIES', v_identities),
      ('PHONE_NUMBER', case when v_flags.has_phone then 1 else 0 end),
      ('DATE_OF_BIRTH', case when v_flags.has_dob then 1 else 0 end),
      ('AVATAR', case when v_flags.has_avatar then 1 else 0 end),
      ('DEFAULT_LOCATION', case when v_flags.has_location then 1 else 0 end),
      ('PUSH_TOKENS', (v_counts->>'push_tokens')::bigint),
      ('PUSH_PREFERENCES', (v_counts->>'push_preferences')::bigint),
      ('NOTIFICATIONS', (v_counts->>'notifications')::bigint),
      ('ACTIVITY_EVENTS', (v_counts->>'product_events')::bigint)
    ) as f(code, n)
   where f.n > 0;

  -- ---- football history, and what deleting the user would do to each ---------
  --   CASCADE_DELETE  erased with the users row (FK ON DELETE CASCADE)
  --   DETACH          the reference is nulled (FK ON DELETE SET NULL)
  --   RETAINED_ID     a bare uuid with no FK: the row stays and names no one
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n, 'treatment', f.treatment)
           order by f.rank, f.code), '[]'::jsonb)
    into v_historical
    from (values
      ('COMMUNITY_MEMBERSHIPS',    (v_counts->>'memberships')::bigint,               'CASCADE_DELETE', 1),
      ('MATCH_REGISTRATIONS',      (v_counts->>'registrations')::bigint,             'CASCADE_DELETE', 1),
      ('LINEUP_ASSIGNMENTS',       (v_counts->>'lineup_assignments')::bigint,        'CASCADE_DELETE', 1),
      ('GOAL_RECORDS',             (v_counts->>'goal_rows')::bigint,                 'CASCADE_DELETE', 1),
      ('MVP_RESULTS',              (v_counts->>'mvp_awards')::bigint,                'CASCADE_DELETE', 1),
      ('PLAYER_STATISTICS',        (v_counts->>'player_statistics_rows')::bigint,    'CASCADE_DELETE', 1),
      ('COMMUNITY_STATISTICS',     (v_counts->>'community_statistics_rows')::bigint, 'CASCADE_DELETE', 1),
      ('RATING_HISTORY',           (v_counts->>'rating_entries')::bigint,            'CASCADE_DELETE', 1),
      ('RECORDED_RESULTS',         (v_counts->>'recorded_results')::bigint,          'DETACH',         2),
      ('PROFESSIONAL_GUESTS_ADDED',(v_counts->>'professional_guests_created')::bigint,'DETACH',        2),
      ('TEAM_OF_PERIOD_AWARDS',    (v_counts->>'team_of_period_awards')::bigint,     'RETAINED_ID',    3),
      ('REGISTRATION_EVENTS',      (v_counts->>'registration_events')::bigint,       'RETAINED_ID',    3),
      ('MEMBERSHIP_EVENTS',        (v_counts->>'membership_events')::bigint,         'RETAINED_ID',    3),
      ('GENERATION_RUNS',          (v_counts->>'generation_runs')::bigint,           'RETAINED_ID',    3),
      ('CONFIRMED_LINEUPS',        (v_counts->>'confirmed_lineups')::bigint,         'RETAINED_ID',    3),
      ('ACTIVITY_EVENTS',          (v_counts->>'product_events')::bigint,            'RETAINED_ID',    3)
    ) as f(code, n, treatment, rank)
   where f.n > 0;

  -- ---- what survives the deletion untouched ----------------------------------
  -- Only records the deletion cannot reach: the two rating archives (their
  -- triggers reject UPDATE and DELETE) and the audit log (no foreign key leads
  -- to it and no client role can write it). `rating_history` is deliberately NOT
  -- here: it rejects UPDATE only, and the cascade deletes it with the account.
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n) order by f.code),
           '[]'::jsonb)
    into v_preserved
    from (values
      ('RATING_HISTORY_ARCHIVE', (v_counts->>'rating_archive_rows')::bigint),
      ('USER_RATING_ARCHIVE',    (v_counts->>'user_rating_archive_rows')::bigint),
      ('ADMIN_AUDIT_LOG',        (v_counts->>'audit_entries')::bigint)
    ) as f(code, n)
   where f.n > 0;

  -- ---- historical match evidence: the part of the cascade that blocks -------
  -- `historical_records` above lists everything the deletion erases. Only the
  -- records that say a match WAS PLAYED, and who took part, are evidence: a
  -- CONFIRMED registration, a lineup place, a goal or a rating entry of a COMPLETED
  -- match. A reserve registration (status 'reserve') only says the player was on the
  -- waiting list, so it is listed in MATCH_REGISTRATIONS but not counted here; the
  -- other three kinds are counted independently of it, so a reserve who really
  -- played (a lineup place, a goal, a rating) is still blocked by that evidence.
  -- "Completed" is the application's rule (see the header): status 'completed' OR
  -- the end has passed. A registration for a match not yet played is the exact
  -- complement, and is the CONFLICT UPCOMING_REGISTRATIONS instead. Memberships and
  -- the two statistics tables are not evidence (see the header) and MVP awards are
  -- counted by MVP_RESULTS_WOULD_CASCADE, so none of them is added here.
  v_history_evidence :=
      (select count(*) from public.match_registrations r
         join public.matches m on m.id = r.match_id
        where r.user_id = p_user_id
          and r.status = 'confirmed'
          and (m.status = 'completed' or m.end_at <= now()))
    + (select count(*) from public.match_team_assignments t
         join public.matches m on m.id = t.match_id
        where t.user_id = p_user_id
          and (m.status = 'completed' or m.end_at <= now()))
    + (select count(*) from public.match_goals g
         join public.matches m on m.id = g.match_id
        where g.user_id = p_user_id
          and (m.status = 'completed' or m.end_at <= now()))
    + (select count(*) from public.rating_history h
         join public.matches m on m.id = h.match_id
        where h.user_id = p_user_id
          and (m.status = 'completed' or m.end_at <= now()));

  -- ---- findings ----------------------------------------------------------------
  -- AUDIT_LOG_APPEND_ONLY is a BLOCKER (0099). The audit log is append-only and keeps,
  -- as written, the e-mail of the administrator who acted and a label for the account
  -- acted on; no foreign key leads to it, so a deletion would leave every entry that
  -- references this account -- as actor or as target -- still identifying it. Account
  -- deletion must erase identifying data, so that blocks until the log's snapshots
  -- have a retention rule. The count is the one the preview always returned.
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'severity', f.severity,
                              'category', f.category, 'count', f.n)
           order by f.rank, f.code), '[]'::jsonb)
    into v_findings
    from (values
      ('TARGET_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_snapshot->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('TARGET_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_snapshot->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('OWNS_COMMUNITIES', 'BLOCKER', 'OWNERSHIP', v_owned_total, 1),
      ('CREATED_MATCHES', 'BLOCKER', 'MATCH', v_created_total, 1),
      ('MVP_RESULTS_WOULD_CASCADE', 'BLOCKER', 'MATCH',
         (v_counts->>'mvp_awards')::bigint, 1),
      ('HISTORY_WOULD_CASCADE', 'BLOCKER', 'HISTORY', v_history_evidence, 1),
      ('UPCOMING_REGISTRATIONS', 'CONFLICT', 'MATCH',
         (v_counts->>'upcoming_registrations')::bigint, 2),
      ('RATING_ARCHIVE_IMMUTABLE', 'BLOCKER', 'ARCHIVE',
         (v_counts->>'rating_archive_rows')::bigint
           + (v_counts->>'user_rating_archive_rows')::bigint, 1),
      ('RATING_HISTORY_IMMUTABLE', 'CONSTRAINT', 'HISTORY',
         (v_counts->>'rating_entries')::bigint, 3),
      ('AUDIT_LOG_APPEND_ONLY', 'BLOCKER', 'AUDIT',
         (v_counts->>'audit_entries')::bigint, 1),
      ('EVENT_LOGS_NAME_ACCOUNT', 'CONSTRAINT', 'HISTORY',
         (v_counts->>'registration_events')::bigint
           + (v_counts->>'membership_events')::bigint, 3)
    ) as f(code, severity, category, n, rank)
   where f.n > 0;

  return jsonb_build_object(
    'version', 1,
    'limit', v_limit,
    'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e
                             where e->>'severity' = 'BLOCKER'),
    'account', v_snapshot,
    'personal_data', v_personal,
    'owned_communities', jsonb_build_object(
      'total', v_owned_total,
      'items', v_owned_items),
    'created_matches', jsonb_build_object(
      'total', v_created_total,
      'by_status', v_created_by_status,
      'items', v_created_items),
    'historical_records', v_historical,
    'preserved_records', v_preserved,
    'findings', v_findings,
    'coverage_notes', jsonb_build_array(
      'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED',
      'STORAGE_OBJECTS_NOT_INSPECTED',
      'AUTH_SESSIONS_NOT_INSPECTED')
  );
end;
$$;

comment on function public.admin_preview_account_deletion(uuid) is
  'Platform Admin, READ ONLY: what deleting an account would touch -- the '
  'personal-data categories it holds, communities it owns and matches it created '
  '(both block the delete today), the historical match evidence of completed '
  'matches that the cascade would erase (a BLOCKER: football results and '
  'participation are preserved; memberships, statistics and upcoming '
  'registrations are listed but do not block), the rating archives (a BLOCKER) '
  'and the audit log, whose e-mail and name snapshots would still identify the '
  'account after a deletion (a BLOCKER when any entry references it) -- with '
  'findings graded BLOCKER / CONFLICT / CONSTRAINT. rating_history rejects UPDATE '
  'only and is deleted with the account. Lists are '
  'bounded to 25 with totals. has_blockers says nothing about whether a deletion '
  'is available or authorised: none exists. Writes nothing and records no audit '
  'event. System Admin only (NOT_AUTHORIZED); USER_NOT_FOUND for an unknown '
  'account. Migrations 0096, 0099.';

revoke execute on function public.admin_preview_account_deletion(uuid)
  from anon, public;
grant execute on function public.admin_preview_account_deletion(uuid)
  to authenticated;
grant execute on function public.admin_preview_account_deletion(uuid)
  to service_role;

-- The audit trail loses the one action it gained. No row uses it (checked above).
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED',
    'USER_PROFILE_UPDATED',
    'USER_ACCOUNTS_MERGED'
  ));

-- A live profile has an Auth user again. Fails, and so changes nothing, if one does not.
alter table public.users
  drop constraint if exists users_id_fkey;
alter table public.users
  add constraint users_id_fkey foreign key (id) references auth.users(id) on delete cascade;

alter table public.users
  drop column if exists deleted_at;
