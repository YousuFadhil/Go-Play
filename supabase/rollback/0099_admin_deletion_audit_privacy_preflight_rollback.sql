-- == rollback/0099_admin_deletion_audit_privacy_preflight_rollback.sql ==
-- Puts `admin_preview_account_deletion(uuid)` back to what 0096 defined: the audit
-- log finding, `AUDIT_LOG_APPEND_ONLY`, is a CONSTRAINT again and no longer moves
-- `has_blockers`.
--
-- **This rollback loses no data and cannot.** 0099 redefined one read-only function
-- and nothing else -- no table, column, index, policy or row -- and the function
-- writes nothing. The body below is the 0096 body, verbatim.
--
-- Roll the client back with it: the previous client's wording for the audit finding
-- ("Audit log entries are kept, with names and emails as they were written") describes
-- a constraint, not a blocker. A client newer than this rollback still works -- it
-- reads whatever severity it is sent -- but its wording would then be too strong.
--
-- `create or replace` is idempotent, so this is safe to run again.

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
  '(both block the delete today), the historical match evidence of completed '
  'matches that the cascade would erase (a BLOCKER: football results and '
  'participation are preserved; memberships, statistics and upcoming '
  'registrations are listed but do not block), the rating archives (a BLOCKER) '
  'and the audit log that survive untouched -- with findings graded BLOCKER / '
  'CONFLICT / CONSTRAINT. rating_history rejects UPDATE only and is deleted with '
  'the account. Lists are '
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
