-- == rollback/0101_platform_admin_account_merge_rollback.sql ==
-- Puts the database back to what it was before 0101: the merge and its helpers gone,
-- the four guarded functions as they were, the merge preview as 0096 left it.
--
-- **It refuses once a merge has happened.** A merge removes an account for good and
-- cannot be undone, and `account_merge_map` is the only record of whom an old UUID
-- became: dropping it would leave the archives and event logs that still name that UUID
-- unreadable, and the audit log keeps a `USER_ACCOUNTS_MERGED` entry the older constraint
-- would not accept. So with any merge on record this script stops before it changes
-- anything. With none, it loses nothing: 0101 added functions and an empty table.
--
-- Roll the client back with it: the previous client has no merge screen, and the current
-- client's preview screen reads fields the 0096 preview does not return.
--
-- Safe to run again.

do $$
declare
  v_merges boolean := false;
begin
  -- Dynamic, so this still runs when the table is already gone (a second run): a plain
  -- `exists (select ... from account_merge_map)` is planned before any `and` short-circuits.
  if to_regclass('public.account_merge_map') is not null then
    execute 'select exists (select 1 from public.account_merge_map)' into v_merges;
    if v_merges then
      raise exception 'ROLLBACK_REFUSED_MERGES_EXIST';
    end if;
  end if;
  if exists (select 1 from public.admin_audit_log
              where action = 'USER_ACCOUNTS_MERGED') then
    raise exception 'ROLLBACK_REFUSED_MERGES_EXIST';
  end if;
end
$$;

drop function if exists public.admin_merge_accounts(uuid, uuid, jsonb);
drop function if exists public.merge_invariants(uuid, uuid);

create or replace function public.admin_preview_account_merge(
  p_retained_user_id uuid,
  p_source_user_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_limit constant int := 25;
  v_retained jsonb;
  v_source jsonb;
  v_overlap_total bigint;
  v_role_conflicts bigint;
  v_ownership_conflicts bigint;
  v_overlap_items jsonb;
  v_owned_total bigint;
  v_owned_items jsonb;
  v_shared jsonb;
  v_stat_collisions bigint;
  v_award_collisions bigint;
  v_findings jsonb;
begin
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_retained_user_id is not distinct from p_source_user_id then
    raise exception 'SAME_ACCOUNT';
  end if;

  v_retained := public.admin_preview_account_snapshot(p_retained_user_id);
  v_source := public.admin_preview_account_snapshot(p_source_user_id);

  -- ---- communities both belong to ------------------------------------------
  select count(*),
         count(*) filter (where a.role <> b.role),
         count(*) filter (where c.owner_id = p_source_user_id)
    into v_overlap_total, v_role_conflicts, v_ownership_conflicts
    from public.community_members a
    join public.community_members b
      on b.community_id = a.community_id and b.user_id = p_source_user_id
    join public.communities c on c.id = a.community_id
   where a.user_id = p_retained_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_overlap_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'retained_role', a.role,
                   'source_role', b.role,
                   'role_conflict', a.role <> b.role,
                   'source_owns', c.owner_id = p_source_user_id,
                   'retained_owns', c.owner_id = p_retained_user_id) as item,
                 row_number() over (
                   order by (c.owner_id = p_source_user_id) desc,
                            (a.role <> b.role) desc, c.name, c.id) as rn
            from public.community_members a
            join public.community_members b
              on b.community_id = a.community_id and b.user_id = p_source_user_id
            join public.communities c on c.id = a.community_id
           where a.user_id = p_retained_user_id) s
   where s.rn <= v_limit;

  -- ---- communities the source OWNS (ownership has to go somewhere) ----------
  select count(*) into v_owned_total
    from public.communities c
   where c.owner_id = p_source_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_owned_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'retained_is_member', a.id is not null,
                   'retained_role', a.role) as item,
                 row_number() over (order by c.name, c.id) as rn
            from public.communities c
            left join public.community_members a
              on a.community_id = c.id and a.user_id = p_retained_user_id
           where c.owner_id = p_source_user_id) s
   where s.rn <= v_limit;

  -- ---- matches both appear in ------------------------------------------------
  with ev as (
    select r.match_id, 'REGISTRATION'::text as kind, r.user_id
      from public.match_registrations r
     where r.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select t.match_id, 'LINEUP', t.user_id
      from public.match_team_assignments t
     where t.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select g.match_id, 'GOALS', g.user_id
      from public.match_goals g
     where g.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select mr.match_id, 'MVP', mr.mvp_user_id
      from public.match_results mr
     where mr.mvp_user_id in (p_retained_user_id, p_source_user_id)
    union all
    select h.match_id, 'RATING', h.user_id
      from public.rating_history h
     where h.user_id in (p_retained_user_id, p_source_user_id)
  ),
  shared as (
    select ev.match_id,
           array_agg(distinct ev.kind order by ev.kind)
             filter (where ev.user_id = p_retained_user_id) as retained_kinds,
           array_agg(distinct ev.kind order by ev.kind)
             filter (where ev.user_id = p_source_user_id) as source_kinds
      from ev
     group by ev.match_id
    having bool_or(ev.user_id = p_retained_user_id)
       and bool_or(ev.user_id = p_source_user_id)
  ),
  flagged as (
    select sh.*, (sh.retained_kinds && sh.source_kinds) as collision
      from shared sh
  )
  select jsonb_build_object(
           'total', count(*),
           'colliding_total', count(*) filter (where f.collision),
           'by_kind', jsonb_build_object(
             'registration', count(*) filter (
               where 'REGISTRATION' = any(f.retained_kinds) and 'REGISTRATION' = any(f.source_kinds)),
             'lineup', count(*) filter (
               where 'LINEUP' = any(f.retained_kinds) and 'LINEUP' = any(f.source_kinds)),
             'goals', count(*) filter (
               where 'GOALS' = any(f.retained_kinds) and 'GOALS' = any(f.source_kinds)),
             'rating', count(*) filter (
               where 'RATING' = any(f.retained_kinds) and 'RATING' = any(f.source_kinds))),
           'items', (
             select coalesce(jsonb_agg(i.item order by i.rn), '[]'::jsonb)
               from (select jsonb_build_object(
                              'match_id', m.id,
                              'title', m.title,
                              'community_name', c.name,
                              'start_at', m.start_at,
                              'status', m.status,
                              'is_historical', m.is_historical,
                              'retained_evidence', f2.retained_kinds,
                              'source_evidence', f2.source_kinds,
                              'collision', f2.collision) as item,
                            row_number() over (
                              order by f2.collision desc, m.start_at desc, m.id) as rn
                       from flagged f2
                       join public.matches m on m.id = f2.match_id
                       join public.communities c on c.id = m.community_id) i
              where i.rn <= v_limit))
    into v_shared
    from flagged f;

  -- ---- statistics rows that would collide -------------------------------------
  select count(*) into v_stat_collisions
    from public.community_statistics a
    join public.community_statistics b
      on b.community_id = a.community_id
     and b.period_type = a.period_type
     and b.period_key = a.period_key
     and b.user_id = p_source_user_id
   where a.user_id = p_retained_user_id;

  select count(*) into v_award_collisions
    from public.team_of_period_awards a
    join public.team_of_period_awards b
      on b.snapshot_id = a.snapshot_id and b.user_id = p_source_user_id
   where a.user_id = p_retained_user_id;

  -- ---- findings ----------------------------------------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'severity', f.severity,
                              'category', f.category, 'count', f.n)
           order by f.rank, f.code), '[]'::jsonb)
    into v_findings
    from (values
      ('SOURCE_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_source->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('RETAINED_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_retained->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('SOURCE_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_source->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('RETAINED_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_retained->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('OWNERSHIP_CONFLICT', 'BLOCKER', 'OWNERSHIP', v_ownership_conflicts, 1),
      ('SHARED_MATCH_COLLISION', 'BLOCKER', 'MATCH',
         coalesce((v_shared->>'colliding_total')::bigint, 0), 1),
      ('SOURCE_OWNS_COMMUNITIES', 'CONFLICT', 'OWNERSHIP',
         v_owned_total - v_ownership_conflicts, 2),
      ('ROLE_CONFLICT', 'CONFLICT', 'ROLE', v_role_conflicts, 2),
      ('SHARED_MATCH_PARTICIPATION', 'CONFLICT', 'MATCH',
         coalesce((v_shared->>'total')::bigint, 0)
           - coalesce((v_shared->>'colliding_total')::bigint, 0), 2),
      ('SOURCE_CREATED_MATCHES', 'CONFLICT', 'MATCH',
         (v_source->'counts'->>'created_matches')::bigint, 2),
      ('COMMUNITY_STATISTICS_COLLISION', 'CONFLICT', 'STATISTICS', v_stat_collisions, 2),
      ('TEAM_AWARD_COLLISION', 'CONFLICT', 'STATISTICS', v_award_collisions, 2),
      ('PLAYER_STATISTICS_RECOMPUTE', 'CONFLICT', 'STATISTICS',
         (v_source->'counts'->>'matches_played')::bigint, 2),
      ('RATING_REPLAY_REQUIRED', 'CONFLICT', 'RATING',
         (v_source->'counts'->>'rating_entries')::bigint, 2),
      ('RATING_ARCHIVE_IMMUTABLE', 'BLOCKER', 'ARCHIVE',
         (v_source->'counts'->>'rating_archive_rows')::bigint
           + (v_source->'counts'->>'user_rating_archive_rows')::bigint, 1),
      ('EVENT_LOGS_NAME_SOURCE', 'CONSTRAINT', 'HISTORY',
         (v_source->'counts'->>'registration_events')::bigint
           + (v_source->'counts'->>'membership_events')::bigint
           + (v_source->'counts'->>'product_events')::bigint, 3),
      ('AUDIT_LOG_NAMES_SOURCE', 'CONSTRAINT', 'AUDIT',
         (v_source->'counts'->>'audit_entries')::bigint, 3)
    ) as f(code, severity, category, n, rank)
   where f.n > 0;

  return jsonb_build_object(
    'version', 1,
    'limit', v_limit,
    'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e
                             where e->>'severity' = 'BLOCKER'),
    'retained', v_retained,
    'source', v_source,
    'overlapping_communities', jsonb_build_object(
      'total', v_overlap_total,
      'role_conflicts_total', v_role_conflicts,
      'ownership_conflicts_total', v_ownership_conflicts,
      'items', v_overlap_items),
    'source_owned_communities', jsonb_build_object(
      'total', v_owned_total,
      'items', v_owned_items),
    'shared_matches', v_shared,
    'statistics_overlap', jsonb_build_object(
      'community_statistics_collisions', v_stat_collisions,
      'team_award_collisions', v_award_collisions),
    'findings', v_findings,
    'coverage_notes', jsonb_build_array(
      'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED',
      'STORAGE_OBJECTS_NOT_INSPECTED',
      'AUTH_SESSIONS_NOT_INSPECTED')
  );
end;
$$;

comment on function public.admin_preview_account_merge(uuid, uuid) is
  'Platform Admin, READ ONLY: what folding a source account into a retained one '
  'would collide with -- both accounts'' identity and activity counts, '
  'overlapping community memberships and roles, communities the source owns, '
  'matches both appear in (registrations, lineups, goals, MVP, rating), '
  'statistics that would collide, and findings graded BLOCKER / CONFLICT / '
  'CONSTRAINT. Lists are bounded to 25 with totals. has_blockers says nothing '
  'about whether a merge is available or authorised: none exists. Writes nothing '
  'and records no audit event. System Admin only (NOT_AUTHORIZED); SAME_ACCOUNT '
  'for one id twice; USER_NOT_FOUND for an unknown account. Migration 0096.';

revoke execute on function public.admin_preview_account_merge(uuid, uuid)
  from anon, public;
grant execute on function public.admin_preview_account_merge(uuid, uuid)
  to authenticated;
grant execute on function public.admin_preview_account_merge(uuid, uuid)
  to service_role;

drop function if exists public.merge_participation_blockers(uuid, uuid);
drop function if exists public.merge_shared_matches(uuid, uuid);
drop function if exists public.merge_source_stored_files(uuid);

-- The four functions, as they were (their bodies are the live ones, without the guard).

create or replace function public.capture_match_registration_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id uuid;
  v_user_id uuid;
  v_registration_id uuid;
  v_community_id uuid;
  v_completed boolean;
  v_from_status text;
  v_to_status text;
  v_operation text;
begin
  if tg_op = 'INSERT' then
    if new.user_id is null then return new; end if;
    v_match_id := new.match_id;
    v_user_id := new.user_id;
    v_registration_id := new.id;
    v_operation := 'created';
    v_from_status := null;
    v_to_status := new.status;
  elsif tg_op = 'UPDATE' then
    if new.user_id is null or new.status is not distinct from old.status then
      return new;
    end if;
    v_match_id := new.match_id;
    v_user_id := new.user_id;
    v_registration_id := new.id;
    v_operation := 'status_changed';
    v_from_status := old.status;
    v_to_status := new.status;
  else
    if old.user_id is null then return old; end if;
    v_match_id := old.match_id;
    v_user_id := old.user_id;
    v_registration_id := old.id;
    v_operation := 'deleted';
    v_from_status := old.status;
    v_to_status := null;
  end if;

  select
    m.community_id,
    (m.status = 'completed' or m.end_at <= now())
  into v_community_id, v_completed
  from public.matches m
  where m.id = v_match_id;

  insert into public.match_registration_events (
    registration_id,
    match_id,
    community_id,
    user_id,
    actor_user_id,
    operation,
    from_status,
    to_status,
    match_was_completed
  )
  values (
    v_registration_id,
    v_match_id,
    v_community_id,
    v_user_id,
    auth.uid(),
    v_operation,
    v_from_status,
    v_to_status,
    v_completed
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.capture_community_membership_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.community_membership_events (
      membership_id,
      community_id,
      user_id,
      actor_user_id,
      operation,
      from_role,
      to_role
    )
    values (
      new.id,
      new.community_id,
      new.user_id,
      auth.uid(),
      'joined',
      null,
      new.role
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.role is not distinct from old.role then return new; end if;
    insert into public.community_membership_events (
      membership_id,
      community_id,
      user_id,
      actor_user_id,
      operation,
      from_role,
      to_role
    )
    values (
      new.id,
      new.community_id,
      new.user_id,
      auth.uid(),
      'role_changed',
      old.role,
      new.role
    );
    return new;
  end if;

  insert into public.community_membership_events (
    membership_id,
    community_id,
    user_id,
    actor_user_id,
    operation,
    from_role,
    to_role
  )
  values (
    old.id,
    old.community_id,
    old.user_id,
    auth.uid(),
    'deleted',
    old.role,
    null
  );
  return old;
end;
$$;

create or replace function public.advance_match_participation_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id uuid;
  v_community_id uuid;
  v_status text;
  v_end_at timestamptz;
  v_revision bigint;
  v_actor uuid;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select m.community_id, m.status, m.end_at
  into v_community_id, v_status, v_end_at
  from public.matches m
  where m.id = v_match_id;

  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  insert into public.match_participation_state (
    match_id,
    lineup_revision
  )
  values (v_match_id, 1)
  on conflict (match_id) do update
    set lineup_revision =
      public.match_participation_state.lineup_revision + 1
  returning lineup_revision into v_revision;

  v_actor := auth.uid();

  if (v_status = 'completed' or v_end_at <= now())
     and v_actor is not null
     and public.has_active_community_role(
       v_community_id,
       v_actor,
       'admin'
     )
  then
    update public.match_participation_state
    set confirmed_revision = v_revision,
        confirmed_at = now(),
        confirmed_by = v_actor
    where match_id = v_match_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.apply_rating_delta(
  p_user_id uuid,
  p_match_id uuid,
  p_reason text,
  p_delta numeric,
  p_reverses_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before numeric(5,3);
  v_after numeric(5,3);
begin
  if p_user_id is null then return; end if;

  select overall_rating into v_before
  from users where id = p_user_id
  for update;
  if not found then return; end if;

  v_after := least(10.000, greatest(0.000, v_before + p_delta));

  update users set overall_rating = v_after where id = p_user_id;

  insert into rating_history (
    user_id, match_id, change_reason, delta,
    rating_before, rating_after, reverses_id
  )
  values (
    p_user_id, p_match_id, p_reason, v_after - v_before,
    v_before, v_after, p_reverses_id
  );
end;
$$;

drop function if exists public.merge_rating_scope_excludes(uuid);
drop function if exists public.merge_skips_lifecycle(uuid);

-- The audit trail loses the one action it gained. No row uses it (checked above).
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED',
    'USER_PROFILE_UPDATED'
  ));

-- Empty by the check at the top.
drop table if exists public.account_merge_map;
