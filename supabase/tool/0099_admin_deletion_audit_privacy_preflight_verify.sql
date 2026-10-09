-- == tool/0099_admin_deletion_audit_privacy_preflight_verify.sql ==
-- Post-apply checks for migration 0099. READ ONLY: one SELECT, no write, no
-- impersonation. Run it after the migration has been applied and read the `ok`
-- column: every row should be true.
--
-- Success is the resulting database state (the function, its signature, its grants,
-- its search path, its body), not the migration record alone -- the Architect ruling of
-- 2026-10-06, point 3. The first row is the record; the rest are the state.
--
-- It checks that `admin_preview_account_deletion` is the function 0099 defines, that
-- it is as locked down as 0096 left it, that the audit finding is a BLOCKER, that no
-- other finding moved, and that the merge preview and the helper are untouched. It
-- cannot show behaviour. Because the preview is READ ONLY, behaviour is safe to try on
-- real accounts: see the block at the foot.
--
-- ## BASELINE
--
-- Checks 13 and 14 pin the bodies by hash. They are exact for the chain this was
-- written for: 0096 as committed, then 0099. If a later migration changes any of the
-- three preview functions, they go false for the right reason, and are retired with
-- that migration. Nothing else here depends on the rest of the database.
--
-- ## ORDER
--
--   1. 0096 is applied (it is: run `0096_..._verify.sql` if in doubt).
--   2. Apply 0099. Run THIS file: every row true.
--   3. `0096_..._verify.sql` is still valid afterwards.

with
found as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.provolatile,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_function_result(p.oid) as result,
         -- The body with every space and newline removed, so a check on it does
         -- not depend on how the migration was formatted when it was applied.
         regexp_replace(p.prosrc, '\s+', '', 'g') as src_compact,
         -- ...and a hash of the body as written, line endings normalised.
         md5(replace(p.prosrc, E'\r\n', E'\n')) as src_md5,
         exists (
           select 1
             from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where a.grantee = 0 and a.privilege_type = 'EXECUTE'
         ) as public_can_execute
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname like 'admin\_preview\_account\_%'
),
-- The function by exact signature: an extra overload makes check 3 false instead of
-- making every scalar subquery below fail.
del as (
  select * from found where proname = 'admin_preview_account_deletion' and args = 'p_user_id uuid'
),
-- Every finding row of the deletion body as `CODE=SEVERITY`, in code order.
findings as (
  select string_agg(m[1] || '=' || m[2], ', ' order by m[1]) as listing
    from del d,
         regexp_matches(d.src_compact, '\(''([A-Z_]+)'',''(BLOCKER|CONFLICT|CONSTRAINT)'',''', 'g') m
)
select n, check_name, expected, actual, ok
from (
  -- 1. The record.
  select 1 as n, 'migration recorded' as check_name,
         '1 record' as expected,
         (select count(*)::text || ' record(s)'
            from supabase_migrations.schema_migrations
           where name like '%0099_admin_deletion_audit_privacy_preflight%') as actual,
         (select count(*) = 1
            from supabase_migrations.schema_migrations
           where name like '%0099_admin_deletion_audit_privacy_preflight%') as ok

  union all
  -- 2. The function, by exact signature, once; and no sibling was added.
  select 2, 'admin_preview_account_deletion(p_user_id uuid) exists once, returning jsonb', '1; jsonb',
         (select count(*)::text from del where args = 'p_user_id uuid') || '; '
           || coalesce((select result from del limit 1), 'none'),
         (select count(*) = 1 from del where args = 'p_user_id uuid' and result = 'jsonb')

  union all
  select 3, 'still exactly the three 0096 functions, no overload', '3 in all',
         (select count(*)::text from found),
         (select count(*) = 3 from found)

  union all
  select 4, 'it is security definer, STABLE (cannot write), search_path = public, pg_temp', 'true; s; public, pg_temp',
         (select prosecdef::text || '; ' || provolatile::text || '; ' || coalesce(array_to_string(proconfig, ','), 'none') from del limit 1),
         (select count(*) = 1 from del
           where prosecdef and provolatile = 's' and proconfig = array['search_path=public, pg_temp'])

  union all
  -- 5. Who can run it: as 0096 left it.
  select 5, 'anon and PUBLIC cannot execute it; authenticated and service_role can', 'false; false; true; true',
         (select has_function_privilege('anon', oid, 'EXECUTE')::text || '; ' || public_can_execute::text || '; '
                 || has_function_privilege('authenticated', oid, 'EXECUTE')::text || '; '
                 || has_function_privilege('service_role', oid, 'EXECUTE')::text from del limit 1),
         (select not has_function_privilege('anon', oid, 'EXECUTE') and not public_can_execute
                 and has_function_privilege('authenticated', oid, 'EXECUTE')
                 and has_function_privilege('service_role', oid, 'EXECUTE')
            from del limit 1)

  union all
  select 6, 'the helper is still executable by no client role', 'anon false, authenticated false',
         (select has_function_privilege('anon', oid, 'EXECUTE')::text || ', ' || has_function_privilege('authenticated', oid, 'EXECUTE')::text
            from found where proname = 'admin_preview_account_snapshot'),
         (select not has_function_privilege('anon', oid, 'EXECUTE') and not has_function_privilege('authenticated', oid, 'EXECUTE')
            from found where proname = 'admin_preview_account_snapshot')

  union all
  -- 7. The gate: the helper-based check AND an independent look at public.system_admins.
  select 7, 'it independently checks public.system_admins for auth.uid()', 'true',
         (select (src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%')::text from del),
         (select src_compact like '%public.is_system_admin()%'
                 and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%'
            from del)

  union all
  select 8, 'it names no shared table or function without its schema', '0',
         (select count(*)::text from del
           where src_compact ~ '(from|join|into)(users|system_admins|communities|community_members|matches|match_[a-z_]+|rating_[a-z_]+|notifications|notification_[a-z_]+|product_events|team_of_period_awards|player_statistics|community_statistics|btge_generation_runs|admin_audit_log)'
              or src_compact ~ '(perform|ifnot)(is_system_admin|record_admin_audit|admin_preview_account_snapshot)\('),
         (select count(*) = 0 from del
           where src_compact ~ '(from|join|into)(users|system_admins|communities|community_members|matches|match_[a-z_]+|rating_[a-z_]+|notifications|notification_[a-z_]+|product_events|team_of_period_awards|player_statistics|community_statistics|btge_generation_runs|admin_audit_log)'
              or src_compact ~ '(perform|ifnot)(is_system_admin|record_admin_audit|admin_preview_account_snapshot)\(')

  union all
  -- 9. READ ONLY by what the body says as well as by STABLE.
  select 9, 'the body contains no write, no audit call and no dynamic SQL', '0',
         (select count(*)::text from del
           where src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|dropfunction|record_admin_audit|executeformat|execute'')'),
         (select count(*) = 0 from del
           where src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|dropfunction|record_admin_audit|executeformat|execute'')')

  union all
  -- 10. THE CHANGE: audit entries are a BLOCKER, counted as before, and never a
  --     CONSTRAINT again.
  select 10, 'AUDIT_LOG_APPEND_ONLY is a BLOCKER of category AUDIT, counted from audit_entries', 'blocker; counted; not a constraint',
         (select case when src_compact like '%(''AUDIT_LOG_APPEND_ONLY'',''BLOCKER'',''AUDIT'',(v_counts->>''audit_entries'')::bigint,1)%' then 'blocker; counted' else 'WRONG' end
                 || '; ' || case when src_compact like '%''AUDIT_LOG_APPEND_ONLY'',''CONSTRAINT''%' then 'STILL A CONSTRAINT' else 'not a constraint' end
            from del),
         (select src_compact like '%(''AUDIT_LOG_APPEND_ONLY'',''BLOCKER'',''AUDIT'',(v_counts->>''audit_entries'')::bigint,1)%'
                 and src_compact not like '%''AUDIT_LOG_APPEND_ONLY'',''CONSTRAINT''%'
                 and src_compact not like '%''AUDIT_LOG_APPEND_ONLY'',''CONFLICT''%'
            from del)

  union all
  -- 11. NO OTHER FINDING MOVED: the eleven findings of 0096, with their severities.
  select 11, 'the deletion findings are exactly the eleven of 0096, only the audit one a BLOCKER now', 'see listing',
         (select listing from findings),
         (select listing = 'AUDIT_LOG_APPEND_ONLY=BLOCKER, CREATED_MATCHES=BLOCKER, EVENT_LOGS_NAME_ACCOUNT=CONSTRAINT, '
                        || 'HISTORY_WOULD_CASCADE=BLOCKER, MVP_RESULTS_WOULD_CASCADE=BLOCKER, OWNS_COMMUNITIES=BLOCKER, '
                        || 'RATING_ARCHIVE_IMMUTABLE=BLOCKER, RATING_HISTORY_IMMUTABLE=CONSTRAINT, TARGET_IS_CALLER=BLOCKER, '
                        || 'TARGET_IS_SYSTEM_ADMIN=BLOCKER, UPCOMING_REGISTRATIONS=CONFLICT'
            from findings)

  union all
  -- 12. The verdict is still `has_blockers`, built from the findings.
  select 12, 'the verdict is has_blockers, built from the findings; never can_proceed', 'true; no can_proceed',
         (select (src_compact like '%''has_blockers'',exists(select1fromjsonb_array_elements(v_findings)e%')::text
                 || '; ' || case when src_compact like '%can_proceed%' then 'can_proceed PRESENT' else 'no can_proceed' end from del),
         (select src_compact like '%''has_blockers'',exists(select1fromjsonb_array_elements(v_findings)e%'
                 and src_compact not like '%can_proceed%' from del)

  union all
  -- 13. The deletion body is exactly the one 0099 applies.
  select 13, 'the deletion body is exactly the body 0099 defines (hash)', 'b34fcb36ecf531263044af13c8da0b66',
         (select src_md5 from del),
         (select src_md5 = 'b34fcb36ecf531263044af13c8da0b66' from del)

  union all
  -- 14. The merge preview and the helper are byte for byte what 0096 left.
  select 14, 'the merge preview and the helper are unchanged from 0096 (hashes)', 'merge 52aa9c51; snapshot 99fefffa',
         (select coalesce(string_agg(case proname when 'admin_preview_account_merge' then 'merge ' else 'snapshot ' end || left(src_md5, 8), '; ' order by proname), 'none')
            from found where proname in ('admin_preview_account_merge', 'admin_preview_account_snapshot')),
         (select count(*) = 2 from found
           where (proname = 'admin_preview_account_merge' and src_md5 = '52aa9c51eb20b4fd46f99874a98cbd8a')
              or (proname = 'admin_preview_account_snapshot' and src_md5 = '99fefffab545f72e72496b5213c59ad5'))

  union all
  -- 15. The audit log's own protection is untouched, and record_admin_audit is still
  --     reachable from no client role.
  select 15, 'audit log still closed: rls on, no client select; record_admin_audit not executable by anon or authenticated', 'rls on; false, false',
         'rls ' || (select relrowsecurity::text from pg_class where oid = 'public.admin_audit_log'::regclass)
           || '; ' || has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text
           || ', ' || has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text,
         (select relrowsecurity from pg_class where oid = 'public.admin_audit_log'::regclass)
           and not has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')
           and not has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')
           and not has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')
) checks
order by n, check_name;


-- ============================================================================
-- Trying the preview (optional, after every row above is true)
-- ============================================================================
-- The preview is read only, so it is safe to run against real accounts. It shows
-- personal data to whoever runs it: use it only for accounts you are entitled to
-- see. Replace the placeholders; <ADMIN_ID> must be in system_admins. Run it as ONE
-- batch (the claim lasts for the batch).
--
--   select set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
--   select set_config('request.jwt.claims',
--     json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);
--   select public.admin_preview_account_deletion('<ACCOUNT_ID>'::uuid);
--
-- Expected for an account that any audit entry references (as the administrator who
-- acted, or as the account acted on): a finding `AUDIT_LOG_APPEND_ONLY` with
-- `severity = 'BLOCKER'`, and `has_blockers = true`. For an account no entry
-- references: no audit finding. `has_blockers = false` is a statement about this
-- preview only: it does NOT mean a deletion is available, safe or authorised, and none
-- exists. The preview never returns the e-mail or label stored in the audit entries,
-- only how many entries there are. Nothing is written either way: the audit log gains
-- no row.
