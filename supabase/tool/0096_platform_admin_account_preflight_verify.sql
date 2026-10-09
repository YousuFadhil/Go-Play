-- == tool/0096_platform_admin_account_preflight_verify.sql ==
-- Post-apply checks for migration 0096. READ ONLY: one SELECT, no write, no
-- impersonation. Run it after the migration has been applied and read the `ok`
-- column: every row should be true.
--
-- Success is the resulting database state (functions, signatures, grants, search
-- path, bodies), not the migration record alone -- the Architect ruling of
-- 2026-10-06, point 3. The first row is the record; the rest are the state.
--
-- This checks that the three preview functions exist as written and are as
-- locked down as written. It cannot show behaviour. Because the previews are READ
-- ONLY, behaviour is safe to try on real accounts: see the block at the foot.
--
-- ## VERIFICATION ORDER
--
--   1. Apply 0095. Run `0095_..._verify.sql`: every row true. Then its controlled
--      verification against the designated test account.
--   2. Apply 0096. Run THIS file: every row true.
--   3. Do NOT run `0095_..._verify.sql` again after 0096 is applied, and do not
--      read a red check 13 there as a fault.
--
-- Why: `0095` check 13 is specific to the 0094 baseline. It holds a fixed list of
-- the 26 `admin_*` functions that existed at 0094, expects exactly those plus the
-- six of 0095 (32 in all), and goes false for any other `admin_*` function. The
-- three functions here are `admin_*` too, so after 0096 that check counts 35 and
-- reports a function it has never heard of. It is right to: the baseline it
-- describes no longer exists. Every OTHER `0095` check stays true, which is what
-- confirms 0096 changed nothing of 0095 (and check 15 below re-checks that). This
-- was run offline against a database built both ways, before and after 0096.
-- `0095` is not edited for this: its file is correct for the moment it was
-- written for, and the order above is the fix.

with
expected(fn, args, is_preview) as (
  values
    ('admin_preview_account_snapshot', 'p_user_id uuid', false),
    ('admin_preview_account_merge',    'p_retained_user_id uuid, p_source_user_id uuid', true),
    ('admin_preview_account_deletion', 'p_user_id uuid', true)
),
found as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.provolatile,
         pg_get_function_identity_arguments(p.oid) as args,
         -- The body with every space and newline removed, so a check on it does
         -- not depend on how the migration was formatted when it was applied.
         regexp_replace(p.prosrc, '\s+', '', 'g') as src_compact,
         exists (
           select 1
             from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where a.grantee = 0 and a.privilege_type = 'EXECUTE'
         ) as public_can_execute
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname like 'admin\_preview\_account\_%'
)
select n, check_name, expected, actual, ok
from (
  -- 1. The record.
  select 1 as n, 'migration recorded' as check_name,
         '1 record' as expected,
         (select count(*)::text || ' record(s)'
            from supabase_migrations.schema_migrations
           where name like '%0096_platform_admin_account_preflight%') as actual,
         (select count(*) = 1
            from supabase_migrations.schema_migrations
           where name like '%0096_platform_admin_account_preflight%') as ok

  union all
  -- 2. The three functions, by exact signature (one row each).
  select 2, 'function ' || e.fn || '(' || e.args || ')', 'exists, once',
         (select count(*)::text from found f where f.proname = e.fn and f.args = e.args),
         (select count(*) = 1 from found f where f.proname = e.fn and f.args = e.args)
    from expected e

  union all
  select 3, 'no other admin_preview_account_* function or overload', '3 in all',
         (select count(*)::text from found),
         (select count(*) = 3 from found)

  union all
  select 4, 'all three are security definer', '3',
         (select count(*)::text from found where prosecdef),
         (select count(*) = 3 from found where prosecdef)

  union all
  -- 5. pg_temp named, and last.
  select 5, 'all three have search_path = public, pg_temp (pg_temp last)', '3',
         (select count(*)::text from found where proconfig = array['search_path=public, pg_temp']),
         (select count(*) = 3 from found where proconfig = array['search_path=public, pg_temp'])

  union all
  -- 6. Stable: PostgreSQL itself then refuses any write from them.
  select 6, 'all three are STABLE (cannot write)', '3 x s',
         (select string_agg(proname || '=' || provolatile::text, ', ' order by proname) from found),
         (select count(*) = 3 from found where provolatile = 's')

  union all
  select 7, 'anon cannot execute any of them', '0',
         (select count(*)::text from found where has_function_privilege('anon', oid, 'EXECUTE')),
         (select count(*) = 0 from found where has_function_privilege('anon', oid, 'EXECUTE'))

  union all
  select 8, 'PUBLIC cannot execute any of them', '0',
         (select count(*)::text from found where public_can_execute),
         (select count(*) = 0 from found where public_can_execute)

  union all
  -- 9. The two previews are for signed-in System Admins; the helper is for no one.
  select 9, 'authenticated can execute the two previews and NOT the helper', 'merge, deletion',
         (select coalesce(string_agg(proname, ', ' order by proname), 'none')
            from found where has_function_privilege('authenticated', oid, 'EXECUTE')),
         (select count(*) = 2
                 and count(*) filter (where proname = 'admin_preview_account_snapshot') = 0
            from found where has_function_privilege('authenticated', oid, 'EXECUTE'))

  union all
  select 10, 'service_role can execute the two previews (as 0066, 0068, 0095)', 'merge, deletion',
         (select coalesce(string_agg(proname, ', ' order by proname), 'none')
            from found where has_function_privilege('service_role', oid, 'EXECUTE')
                         and proname <> 'admin_preview_account_snapshot'),
         (select count(*) = 2 from found
           where has_function_privilege('service_role', oid, 'EXECUTE')
             and proname <> 'admin_preview_account_snapshot')

  union all
  -- 11. Each body asks, besides the helper, whether auth.uid() is in
  --     public.system_admins itself (is_system_admin() has only search_path = public).
  select 11, 'all three independently check public.system_admins for auth.uid()', '3',
         (select count(*)::text from found
           where src_compact like '%public.is_system_admin()%'
             and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%'),
         (select count(*) = 3 from found
           where src_compact like '%public.is_system_admin()%'
             and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%')

  union all
  -- 12. And none reaches a shared table or function by a bare name.
  select 12, 'no body names a shared table or function without its schema', '0',
         (select count(*)::text from found
           where src_compact ~ '(from|join|into)(users|system_admins|communities|community_members|matches|match_[a-z_]+|rating_[a-z_]+|notifications|notification_[a-z_]+|product_events|team_of_period_awards|player_statistics|community_statistics|btge_generation_runs|admin_audit_log)'
              or src_compact ~ '(perform|ifnot)(is_system_admin|record_admin_audit|admin_preview_account_snapshot)\('),
         (select count(*) = 0 from found
           where src_compact ~ '(from|join|into)(users|system_admins|communities|community_members|matches|match_[a-z_]+|rating_[a-z_]+|notifications|notification_[a-z_]+|product_events|team_of_period_awards|player_statistics|community_statistics|btge_generation_runs|admin_audit_log)'
              or src_compact ~ '(perform|ifnot)(is_system_admin|record_admin_audit|admin_preview_account_snapshot)\(')

  union all
  -- 13. READ ONLY, by what the bodies say as well as by STABLE: no DML, no DDL,
  --     no audit call, no dynamic SQL.
  select 13, 'no body contains a write, an audit call or dynamic SQL', '0',
         (select count(*)::text from found
           where src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|dropfunction|record_admin_audit|executeformat|execute'')'),
         (select count(*) = 0 from found
           where src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|dropfunction|record_admin_audit|executeformat|execute'')')

  union all
  -- 14. The previews bound their lists.
  select 14, 'the two previews bound their lists to 25', '2',
         (select count(*)::text from found where src_compact like '%v_limitconstantint:=25%'),
         (select count(*) = 2 from found where src_compact like '%v_limitconstantint:=25%'
                                           and proname <> 'admin_preview_account_snapshot')

  union all
  -- 15. 0095's six functions were not touched: still present, still hardened.
  select 15, '0095''s six functions are unchanged: present, security definer, pg_temp last', '6',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and p.proconfig = array['search_path=public, pg_temp']
             and p.proname in ('admin_get_user_account', 'admin_update_user_account',
                               'admin_update_user_player_profile', 'admin_update_user_privacy',
                               'admin_update_user_default_wilayat', 'admin_update_user_push_preferences')),
         (select count(*) = 6 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and p.proconfig = array['search_path=public, pg_temp']
             and p.proname in ('admin_get_user_account', 'admin_update_user_account',
                               'admin_update_user_player_profile', 'admin_update_user_privacy',
                               'admin_update_user_default_wilayat', 'admin_update_user_push_preferences'))

  union all
  -- 16. record_admin_audit is still reachable from no client role, and the audit
  --     log's own protection is untouched.
  select 16, 'record_admin_audit still not executable by anon or authenticated; audit log still closed', 'false, false; rls on; no client select',
         has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text
           || ', ' ||
         has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text
           || '; rls ' || (select relrowsecurity::text from pg_class where oid = 'public.admin_audit_log'::regclass),
         not has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')
           and not has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')
           and (select relrowsecurity from pg_class where oid = 'public.admin_audit_log'::regclass)
           and not has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')

  union all
  -- 17. The verdict is `has_blockers` and nothing that reads as permission: no
  --     body uses the name `can_proceed`, and both previews build `has_blockers`
  --     from the findings.
  select 17, 'both previews report has_blockers; none uses the name can_proceed', '2; 0',
         (select count(*)::text from found
           where proname <> 'admin_preview_account_snapshot'
             and src_compact like '%''has_blockers'',exists(select1fromjsonb_array_elements(v_findings)e%')
           || '; ' ||
         (select count(*)::text from found where src_compact like '%can_proceed%'),
         (select count(*) = 2 from found
           where proname <> 'admin_preview_account_snapshot'
             and src_compact like '%''has_blockers'',exists(select1fromjsonb_array_elements(v_findings)e%')
           and (select count(*) = 0 from found where src_compact like '%can_proceed%')

  union all
  -- 18. Immutable rating archives are BLOCKERs in both previews, never downgraded.
  select 18, 'RATING_ARCHIVE_IMMUTABLE is a BLOCKER in both previews', '2',
         (select count(*)::text from found
           where src_compact like '%(''RATING_ARCHIVE_IMMUTABLE'',''BLOCKER'',''ARCHIVE''%'),
         (select count(*) = 2 from found
           where proname <> 'admin_preview_account_snapshot'
             and src_compact like '%(''RATING_ARCHIVE_IMMUTABLE'',''BLOCKER'',''ARCHIVE''%')

  union all
  -- 19. A System Admin on either side of a merge, or as the account to delete, is
  --     a BLOCKER.
  select 19, 'System Admins are BLOCKERs: either side of a merge, and the account to delete', '2 (merge: both sides; deletion: the target)',
         (select count(*)::text from found
           where (proname = 'admin_preview_account_merge'
                  and src_compact like '%(''SOURCE_IS_SYSTEM_ADMIN'',''BLOCKER''%'
                  and src_compact like '%(''RETAINED_IS_SYSTEM_ADMIN'',''BLOCKER''%')
              or (proname = 'admin_preview_account_deletion'
                  and src_compact like '%(''TARGET_IS_SYSTEM_ADMIN'',''BLOCKER''%')),
         (select count(*) = 2 from found
           where (proname = 'admin_preview_account_merge'
                  and src_compact like '%(''SOURCE_IS_SYSTEM_ADMIN'',''BLOCKER''%'
                  and src_compact like '%(''RETAINED_IS_SYSTEM_ADMIN'',''BLOCKER''%')
              or (proname = 'admin_preview_account_deletion'
                  and src_compact like '%(''TARGET_IS_SYSTEM_ADMIN'',''BLOCKER''%'))

  union all
  -- 20. rating_history is football history that the deletion ERASES, not a
  --     preserved record: its foreign keys cascade and only UPDATE is rejected.
  --     It must sit in the historical list as CASCADE_DELETE and not in the
  --     preserved list.
  select 20, 'rating_history is CASCADE_DELETE history, never a preserved record', 'historical yes; preserved no',
         (select 'historical ' || case when src_compact like '%(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint,''CASCADE_DELETE''%' then 'yes' else 'no' end
                 || '; preserved ' || case when src_compact like '%(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint)%' then 'YES' else 'no' end
            from found where proname = 'admin_preview_account_deletion'),
         (select src_compact like '%(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint,''CASCADE_DELETE''%'
                 and src_compact not like '%(''RATING_HISTORY'',(v_counts->>''rating_entries'')::bigint)%'
            from found where proname = 'admin_preview_account_deletion')

  union all
  -- 21. Football history the deletion would erase is a BLOCKER, and the finding
  --     that keeps the trigger's name describes UPDATE protection only (a
  --     constraint of category HISTORY, not an "archive").
  select 21, 'HISTORY_WOULD_CASCADE is a BLOCKER; RATING_HISTORY_IMMUTABLE is a HISTORY constraint', 'blocker; constraint/HISTORY',
         (select case when src_compact like '%(''HISTORY_WOULD_CASCADE'',''BLOCKER'',''HISTORY''%' then 'blocker' else 'NOT blocker' end
                 || '; ' || case when src_compact like '%(''RATING_HISTORY_IMMUTABLE'',''CONSTRAINT'',''HISTORY''%' then 'constraint/HISTORY' else 'WRONG' end
            from found where proname = 'admin_preview_account_deletion'),
         (select src_compact like '%(''HISTORY_WOULD_CASCADE'',''BLOCKER'',''HISTORY''%'
                 and src_compact like '%(''RATING_HISTORY_IMMUTABLE'',''CONSTRAINT'',''HISTORY''%'
            from found where proname = 'admin_preview_account_deletion')
) checks
order by n, check_name;


-- ============================================================================
-- Trying the previews (optional, after every row above is true)
-- ============================================================================
-- Both previews are read only, so they are safe to run against real accounts.
-- Run ONE of these at a time, as one batch (the claim lasts for the batch). They
-- show personal data to whoever runs them: use only for accounts you are entitled
-- to see. Replace the placeholders; <ADMIN_ID> must be in system_admins.
--
--   select set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
--   select set_config('request.jwt.claims',
--     json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);
--   select public.admin_preview_account_deletion('<ACCOUNT_ID>'::uuid);
--
--   select set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
--   select set_config('request.jwt.claims',
--     json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);
--   select public.admin_preview_account_merge('<RETAINED_ID>'::uuid, '<SOURCE_ID>'::uuid);
--
-- Expected: a jsonb document with `version = 1`, `limit = 25`, a `findings` array
-- and `has_blockers`. `has_blockers = false` is a statement about this preview
-- only: it does NOT mean a merge or deletion is available, safe or authorised,
-- and none exists. Calling either without the claim, or with the id of an
-- ordinary account, raises NOT_AUTHORIZED. Nothing is written either way: the
-- audit log gains no row.
