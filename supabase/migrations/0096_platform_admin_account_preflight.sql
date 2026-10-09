-- ===== migrations/0096_platform_admin_account_preflight.sql =====
-- Platform Admin: read-only preflight for merging and deleting an account.
--
-- Merging two accounts and deleting one are destructive, and the database is
-- built so that a careless version of either loses football history: most of the
-- tables that name a player cascade-delete with the `users` row, two block the
-- delete outright, ten more name a player by a bare uuid with no foreign key, and
-- the rating archives cannot be updated or deleted at all. Before anything is
-- built that acts, an administrator needs to SEE what an account is entangled
-- with. This migration adds exactly that and nothing more.
--
--   1. `admin_preview_account_snapshot(uuid)`  -- INTERNAL helper: one account's
--                                                 identity and activity counts
--   2. `admin_preview_account_merge(uuid, uuid)`
--   3. `admin_preview_account_deletion(uuid)`
--
-- **Nothing is written, anywhere.** All three are `stable`, so PostgreSQL itself
-- refuses a write from them; there is no DML, no `record_admin_audit` call (a
-- preview is not an act and leaves no trace), no DDL beyond the three functions,
-- no new table, column, index, policy or privilege on any existing object, and no
-- existing function is changed. `auth` is read for the e-mail, the last sign-in
-- and the NAMES of the sign-in providers, as `0095` does; nothing else of it is
-- read and nothing of it is written.
--
-- ## WHO MAY CALL
--
-- The two previews are granted to `authenticated` and `service_role` as `0066`,
-- `0068` and `0095` grant the other admin RPCs, and refuse everyone who is not a
-- System Admin with `NOT_AUTHORIZED` as the first statement. The helper is NOT
-- granted to any client role (like `record_admin_audit`): it is reached only from
-- inside the two previews. It carries the same gate anyway, so a grant added by
-- mistake later would still not open it.
--
-- ## HARDENING (as 0095, after its Architect review)
--
-- `set search_path = public, pg_temp` with `pg_temp` explicitly last; every table,
-- function and row type schema-qualified; and an INDEPENDENT check that
-- `auth.uid()` is in `public.system_admins`, because `is_system_admin()` (`0017`)
-- has `search_path = public` only and can be answered "yes" by a temp table named
-- `system_admins`. Both checks must pass; the refusal is the same.
--
-- ## THE CONTRACTS
--
-- Both previews return one `jsonb` document, because a preview is nested (an
-- account, its counts, several bounded lists, a list of findings). Every list is
-- BOUNDED to 25 items and carries its own `total`, so a large account costs the
-- caller a page, not a table; the totals are counted over everything.
--
-- Findings are the heart of it. Each is `{code, severity, category, count}`:
--
--   BLOCKER     execution must not proceed until it is resolved
--   CONFLICT    needs an explicit resolution rule before execution
--   CONSTRAINT  a preservation fact to accept (nothing to resolve)
--
-- `has_blockers` is true when any finding is a BLOCKER. **It is a statement about
-- this preview and nothing else.** `false` does NOT mean a merge or a deletion is
-- available, safe or authorised: none exists in this phase, the preview does not
-- look at everything (`coverage_notes` says what it leaves out), and any later
-- phase must establish its own preconditions again from scratch. The name is
-- deliberately not `can_proceed`, so that no caller can read it as permission.
--
--   merge:    {version, limit, has_blockers, retained, source, overlapping_communities,
--              source_owned_communities, shared_matches, statistics_overlap,
--              findings, coverage_notes}
--   deletion: {version, limit, has_blockers, account, personal_data, owned_communities,
--              created_matches, historical_records, preserved_records, findings,
--              coverage_notes}
--
-- ## WHAT IS ALWAYS A BLOCKER
--
--   * a System Admin on either side of a merge, or as the account to delete
--     (`SOURCE_IS_SYSTEM_ADMIN`, `RETAINED_IS_SYSTEM_ADMIN`, `TARGET_IS_SYSTEM_ADMIN`)
--     -- those accounts are managed outside the app;
--   * the administrator asking being on either side, or the account to delete
--     (`*_IS_CALLER`, `TARGET_IS_CALLER`);
--   * **immutable rating archives** that name the account being retired -- the
--     merge's source, or the account to delete (`RATING_ARCHIVE_IMMUTABLE`).
--     `rating_history_archive` and `user_rating_archive` reject UPDATE and DELETE,
--     so their rows can be neither moved to another account nor removed, and
--     nothing yet demonstrates that an account they name can be retired or
--     deleted safely. That is a BLOCKER until it is demonstrated, and it is not
--     inferred from anything else -- in particular not from
--     `rating_rebase_runs.rollback_skipped_rows`, which says a past rollback
--     skipped some rows, not that skipping them is safe. Archives naming the
--     merge's RETAINED account are not a finding: that account is not retired.
--
-- `retained`, `source` and `account` are `{account: {...identity...}, counts: {...}}`
-- as the helper builds them.
--
-- ## WHAT THE PREVIEW DOES NOT SEE
--
-- `coverage_notes` says so in the document itself, by code:
--   * `EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED` -- `btge_generation_runs` embeds
--     player ids inside jsonb (`player_inputs`, `generated_lineup`); only the
--     `generated_by` column is counted.
--   * `STORAGE_OBJECTS_NOT_INSPECTED` -- the avatar file lives in Storage; the
--     preview sees only that `users.avatar_path` is set.
--   * `AUTH_SESSIONS_NOT_INSPECTED` -- sessions, refresh tokens and other `auth`
--     rows are not read.
--
-- ## BARE-UUID COLUMNS
--
-- Ten columns name a player by bare uuid and no constraint would ever stop a
-- merge or a delete from orphaning them: `community_membership_events`,
-- `match_registration_events`, `product_events` (two), `product_activity_last_seen`,
-- `rating_history_archive`, `user_rating_archive`, `team_of_period_awards`,
-- `admin_audit_log` (two). The previews count them so they are visible.


-- ============================================================================
-- 1) admin_preview_account_snapshot() -- INTERNAL
-- ============================================================================
-- One account: who it is, and how much of the database names it. `counts` has a
-- fixed set of keys (the Flutter side maps them to labels by key), every one a
-- count except `rating` (the account's overall rating) and `push_preferences`
-- (a flag, 0 or 1).
--
-- `USER_NOT_FOUND` for an id with no `users` row. `is_caller` is "this account is
-- the administrator asking", which the previews turn into a BLOCKER: an
-- administrator cannot be the subject of their own merge or deletion.
create or replace function public.admin_preview_account_snapshot(p_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_account jsonb;
begin
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select jsonb_build_object(
           'id', u.id,
           'full_name', u.full_name,
           'email', au.email::text,
           'is_active', u.is_active,
           'is_system_admin',
             exists (select 1 from public.system_admins sa where sa.user_id = u.id),
           'is_caller', u.id = auth.uid(),
           'created_at', u.created_at,
           'last_sign_in_at', au.last_sign_in_at,
           'sign_in_providers',
             coalesce((select jsonb_agg(p.provider order by p.provider)
                         from (select distinct i.provider::text as provider
                                 from auth.identities i
                                where i.user_id = u.id) p), '[]'::jsonb)
         )
    into v_account
    from public.users u
    join auth.users au on au.id = u.id
   where u.id = p_user_id;

  if v_account is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'account', v_account,
    'counts', jsonb_build_object(
      'memberships',
        (select count(*) from public.community_members cm where cm.user_id = p_user_id),
      'memberships_owner',
        (select count(*) from public.community_members cm
          where cm.user_id = p_user_id and cm.role = 'owner'),
      'memberships_admin',
        (select count(*) from public.community_members cm
          where cm.user_id = p_user_id and cm.role = 'admin'),
      'owned_communities',
        (select count(*) from public.communities c where c.owner_id = p_user_id),
      'created_matches',
        (select count(*) from public.matches m where m.created_by = p_user_id),
      'registrations',
        (select count(*) from public.match_registrations r where r.user_id = p_user_id),
      'upcoming_registrations',
        (select count(*) from public.match_registrations r
           join public.matches m on m.id = r.match_id
          where r.user_id = p_user_id
            and m.end_at > now() and m.status <> 'completed'),
      'lineup_assignments',
        (select count(*) from public.match_team_assignments t where t.user_id = p_user_id),
      'goal_rows',
        (select count(*) from public.match_goals g where g.user_id = p_user_id),
      'goals_total',
        (select coalesce(sum(g.goals), 0) from public.match_goals g
          where g.user_id = p_user_id),
      'mvp_awards',
        (select count(*) from public.match_results mr where mr.mvp_user_id = p_user_id),
      'recorded_results',
        (select count(*) from public.match_results mr where mr.recorded_by = p_user_id),
      'matches_played',
        coalesce((select ps.matches_played from public.player_statistics ps
                   where ps.user_id = p_user_id), 0),
      'player_statistics_rows',
        (select count(*) from public.player_statistics ps where ps.user_id = p_user_id),
      'community_statistics_rows',
        (select count(*) from public.community_statistics cs where cs.user_id = p_user_id),
      'rating_entries',
        (select count(*) from public.rating_history h where h.user_id = p_user_id),
      'rating_archive_rows',
        (select count(*) from public.rating_history_archive a where a.user_id = p_user_id),
      'user_rating_archive_rows',
        (select count(*) from public.user_rating_archive a where a.user_id = p_user_id),
      'team_of_period_awards',
        (select count(*) from public.team_of_period_awards w where w.user_id = p_user_id),
      'registration_events',
        (select count(*) from public.match_registration_events e
          where e.user_id = p_user_id or e.actor_user_id = p_user_id),
      'membership_events',
        (select count(*) from public.community_membership_events e
          where e.user_id = p_user_id or e.actor_user_id = p_user_id),
      'generation_runs',
        (select count(*) from public.btge_generation_runs b where b.generated_by = p_user_id),
      'confirmed_lineups',
        (select count(*) from public.match_participation_state s
          where s.confirmed_by = p_user_id),
      'professional_guests_created',
        (select count(*) from public.match_professional_guests pg
          where pg.created_by = p_user_id),
      'notifications',
        (select count(*) from public.notifications n where n.user_id = p_user_id),
      'push_tokens',
        (select count(*) from public.notification_push_tokens t where t.user_id = p_user_id),
      'push_preferences',
        (select count(*) from public.notification_push_preferences p
          where p.user_id = p_user_id),
      'product_events',
        (select count(*) from public.product_events pe
          where pe.user_id = p_user_id or pe.target_user_id = p_user_id),
      'audit_entries',
        (select count(*) from public.admin_audit_log l
          where l.actor_user_id = p_user_id or l.target_id = p_user_id),
      'rating',
        (select u.overall_rating from public.users u where u.id = p_user_id)
    )
  );
end;
$$;

comment on function public.admin_preview_account_snapshot(uuid) is
  'Platform Admin, INTERNAL: one account''s identity (name, e-mail, state, '
  'sign-in provider NAMES, last sign-in) and how many rows in each table name it. '
  'Read only. Executable by no client role; reached from the two preview RPCs, '
  'and gated on System Admin itself. USER_NOT_FOUND for an unknown id. Migration '
  '0096.';

revoke execute on function public.admin_preview_account_snapshot(uuid)
  from anon, authenticated, public;



-- ============================================================================
-- 2) admin_preview_account_merge()
-- ============================================================================
-- "Fold the source account into the retained one": what would collide, what would
-- need a rule, and what cannot be moved. It does not do any of it.
--
-- The checks, in order: the gate, then `SAME_ACCOUNT` (the same id twice is not a
-- merge), then both accounts must exist (`USER_NOT_FOUND`, from the helper).
-- Everything after that is a FINDING rather than an error, so the screen can show
-- all of them at once instead of the first one.
--
-- Where "collision" comes from: these are the unique keys that include the
-- player, so repointing the source's rows to the retained account would violate
-- them if both hold a row for the same thing --
--   community_members (community_id, user_id)
--   match_registrations / match_team_assignments / match_goals (match_id, user_id)
--   community_statistics (community_id, period_type, period_key, user_id)
--   team_of_period_awards (snapshot_id, user_id)
--   player_statistics (user_id)            -- both always hold a row; sums needed
--
-- A "shared match" is one where BOTH accounts have any participation evidence:
-- a registration, a lineup place, goals, the MVP award, or a rating entry. It
-- is a COLLISION when both hold the same kind of evidence for it (two
-- registrations for one match cannot be merged into one), and merely shared
-- otherwise.
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



-- ============================================================================
-- 3) admin_preview_account_deletion()
-- ============================================================================
-- "Delete this account": which personal data it holds, what stops the delete
-- today, which football history would be erased by the cascade and so has to be
-- anonymised instead, and what cannot be touched at all.
--
-- What the foreign keys actually do on `public.users` today (live, 2026-10-09):
--   NO ACTION  communities.owner_id, matches.created_by          -> BLOCKERS
--   CASCADE    community_members, community_statistics, match_goals,
--              match_registrations, match_results.mvp_user_id,
--              match_team_assignments, notifications, player_statistics,
--              notification_push_tokens / _preferences, rating_history,
--              system_admins                                       -> ERASED
--   SET NULL   match_professional_guests.created_by,
--              match_results.recorded_by                           -> DETACHED
--   (none)     the ten bare-uuid columns listed in the header      -> LEFT BEHIND
--
-- `match_results.mvp_user_id` cascading is the dangerous one: deleting the MVP's
-- account would delete the whole match RESULT, and with it the score both teams
-- were credited. It is reported as a BLOCKER of its own.
--
-- A deletion preview about the administrator themselves, or a System Admin, is
-- still returned -- with the BLOCKER that says so -- rather than refused.
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
  v_cascade_history bigint;
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

  -- ---- what cannot be changed by anyone, however it is deleted ----------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n) order by f.code),
           '[]'::jsonb)
    into v_preserved
    from (values
      ('RATING_HISTORY_ARCHIVE', (v_counts->>'rating_archive_rows')::bigint),
      ('USER_RATING_ARCHIVE',    (v_counts->>'user_rating_archive_rows')::bigint),
      ('RATING_HISTORY',         (v_counts->>'rating_entries')::bigint),
      ('ADMIN_AUDIT_LOG',        (v_counts->>'audit_entries')::bigint)
    ) as f(code, n)
   where f.n > 0;

  v_cascade_history :=
      (v_counts->>'memberships')::bigint + (v_counts->>'registrations')::bigint
    + (v_counts->>'lineup_assignments')::bigint + (v_counts->>'goal_rows')::bigint
    + (v_counts->>'player_statistics_rows')::bigint + (v_counts->>'community_statistics_rows')::bigint
    + (v_counts->>'rating_entries')::bigint;

  -- ---- findings ----------------------------------------------------------------
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
      ('HISTORY_WOULD_CASCADE', 'CONFLICT', 'HISTORY', v_cascade_history, 2),
      ('UPCOMING_REGISTRATIONS', 'CONFLICT', 'MATCH',
         (v_counts->>'upcoming_registrations')::bigint, 2),
      ('RATING_ARCHIVE_IMMUTABLE', 'BLOCKER', 'ARCHIVE',
         (v_counts->>'rating_archive_rows')::bigint
           + (v_counts->>'user_rating_archive_rows')::bigint, 1),
      ('RATING_HISTORY_IMMUTABLE', 'CONSTRAINT', 'ARCHIVE',
         (v_counts->>'rating_entries')::bigint, 3),
      ('AUDIT_LOG_APPEND_ONLY', 'CONSTRAINT', 'AUDIT',
         (v_counts->>'audit_entries')::bigint, 3),
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
  '(both block the delete today), football history the cascade would erase and '
  'so needs anonymising, and the rating archives (a BLOCKER) and audit log that '
  'cannot be changed -- with findings graded BLOCKER / CONFLICT / CONSTRAINT. Lists are '
  'bounded to 25 with totals. has_blockers says nothing about whether a deletion '
  'is available or authorised: none exists. Writes nothing and records no audit '
  'event. System Admin only (NOT_AUTHORIZED); USER_NOT_FOUND for an unknown '
  'account. Migration 0096.';

revoke execute on function public.admin_preview_account_deletion(uuid)
  from anon, public;
grant execute on function public.admin_preview_account_deletion(uuid)
  to authenticated;
grant execute on function public.admin_preview_account_deletion(uuid)
  to service_role;



-- ============================================================================
-- 4) What this migration did not touch
-- ============================================================================
--   * no merge, no deletion, no anonymisation and no identity migration exists
--     here, or is implied to: these functions only describe;
--   * `is_system_admin`, `record_admin_audit`, `admin_delete_user` (`0017`, still
--     in the database and still not called by the console) and every other
--     existing function -- unchanged in body and in privilege;
--   * every table, column, index, trigger, RLS policy and column grant;
--   * `auth` and `storage`: `auth.users` and `auth.identities` are read in the
--     helper for the e-mail, last sign-in and provider names only;
--   * `setup_all.sql`, as before.
