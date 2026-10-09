-- == tool/0095_platform_admin_user_account_management_verify.sql ==
-- Post-apply checks for migration 0095. READ ONLY: one SELECT, no write, no
-- impersonation. Run it after the migration has been applied and read the `ok`
-- column: every row should be true.
--
-- Success is the resulting database state (functions, signatures, grants,
-- constraint, untouched policies and column grants), not the migration record
-- alone -- the Architect ruling of 2026-10-06, point 3. The first row is the
-- record; the rest are the state.
--
-- What this cannot show is behaviour. That is the controlled verification in
-- `0095_platform_admin_user_account_management_controlled_verification.md`,
-- run against a designated test account.
--
-- If the migration was applied under a name other than the file's, change the
-- pattern in check 1. The expected `admin_*` baseline in check 12 is the 26
-- functions that existed at `0094`; if `0095` was preceded by another admin
-- migration, extend that list, not the expected count.

with
expected(fn, args) as (
  values
    ('admin_get_user_account',
     'p_user_id uuid'),
    ('admin_update_user_account',
     'p_user_id uuid, p_full_name text, p_phone text, p_reason text'),
    ('admin_update_user_player_profile',
     'p_user_id uuid, p_date_of_birth date, p_primary_position text, p_secondary_position text, p_reason text'),
    ('admin_update_user_privacy',
     'p_user_id uuid, p_profile_visibility text, p_age_visible boolean, p_reason text'),
    ('admin_update_user_default_wilayat',
     'p_user_id uuid, p_wilayat_code smallint, p_reason text'),
    ('admin_update_user_push_preferences',
     'p_user_id uuid, p_match_push boolean, p_community_push boolean, p_mute_all boolean, p_reason text')
),
found as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.provolatile,
         pg_get_function_identity_arguments(p.oid) as args,
         exists (
           select 1
             from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where a.grantee = 0 and a.privilege_type = 'EXECUTE'
         ) as public_can_execute
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in (select fn from expected)
),
baseline_admin(fn) as (
  values
    ('admin_add_player_to_match'), ('admin_analytics_communities'),
    ('admin_analytics_communities_v2'), ('admin_analytics_matches'),
    ('admin_analytics_matches_v2'), ('admin_analytics_overview'),
    ('admin_analytics_overview_v2'), ('admin_analytics_registrations'),
    ('admin_analytics_registrations_v2'), ('admin_analytics_users'),
    ('admin_analytics_users_v2'), ('admin_delete_community'),
    ('admin_delete_match'), ('admin_delete_user'),
    ('admin_get_community_inspection'), ('admin_get_match_inspection'),
    ('admin_list_audit_log'), ('admin_list_communities'),
    ('admin_list_matches'), ('admin_list_users'),
    ('admin_reactivate_community'), ('admin_reactivate_user'),
    ('admin_suspend_community'), ('admin_suspend_user'),
    ('admin_user_activity_summary'), ('admin_user_activity_timeline')
),
admin_fns as (
  select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'admin\_%'
),
audit_check as (
  select pg_get_constraintdef(c.oid) as def
    from pg_constraint c
   where c.conrelid = 'public.admin_audit_log'::regclass
     and c.conname = 'admin_audit_log_action_check'
),
user_update_cols as (
  select a.attname::text as col
    from pg_attribute a
   where a.attrelid = 'public.users'::regclass
     and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('authenticated', 'public.users', a.attname, 'UPDATE')
)
select n, check_name, expected, actual, ok
from (
  -- 1. The record.
  select 1 as n, 'migration recorded' as check_name,
         '1 record' as expected,
         (select count(*)::text || ' record(s)'
            from supabase_migrations.schema_migrations
           where name like '%0095_platform_admin_user_account_management%') as actual,
         (select count(*) = 1
            from supabase_migrations.schema_migrations
           where name like '%0095_platform_admin_user_account_management%') as ok

  union all
  -- 2. The six functions, by exact signature (one row each, so a missing one
  --    is named).
  select 2, 'function ' || e.fn || '(' || e.args || ')', 'exists, once',
         (select count(*)::text from found f where f.proname = e.fn and f.args = e.args),
         (select count(*) = 1 from found f where f.proname = e.fn and f.args = e.args)
    from expected e

  union all
  -- 3. No extra overload of any of them.
  select 3, 'no other overload of the six', '6 functions in all',
         (select count(*)::text from found),
         (select count(*) = 6 from found)

  union all
  select 4, 'all six are security definer', '6',
         (select count(*)::text from found where prosecdef),
         (select count(*) = 6 from found where prosecdef)

  union all
  select 5, 'all six have search_path = public', '6',
         (select count(*)::text from found where proconfig = array['search_path=public']),
         (select count(*) = 6 from found where proconfig = array['search_path=public'])

  union all
  -- 6. The read is stable; the five writes are not.
  select 6, 'volatility: read stable, writes volatile', 'read s; 5 writes v',
         (select string_agg(proname || '=' || provolatile::text, ', ' order by proname) from found),
         (select count(*) filter (where proname = 'admin_get_user_account' and provolatile = 's') = 1
             and count(*) filter (where proname <> 'admin_get_user_account' and provolatile = 'v') = 5
            from found)

  union all
  select 7, 'anon cannot execute any of them', '0',
         (select count(*)::text from found where has_function_privilege('anon', oid, 'EXECUTE')),
         (select count(*) = 0 from found where has_function_privilege('anon', oid, 'EXECUTE'))

  union all
  select 8, 'PUBLIC cannot execute any of them', '0',
         (select count(*)::text from found where public_can_execute),
         (select count(*) = 0 from found where public_can_execute)

  union all
  select 9, 'authenticated can execute all six (the gate is inside)', '6',
         (select count(*)::text from found where has_function_privilege('authenticated', oid, 'EXECUTE')),
         (select count(*) = 6 from found where has_function_privilege('authenticated', oid, 'EXECUTE'))

  union all
  select 10, 'service_role can execute all six (as 0066 and 0068)', '6',
         (select count(*)::text from found where has_function_privilege('service_role', oid, 'EXECUTE')),
         (select count(*) = 6 from found where has_function_privilege('service_role', oid, 'EXECUTE'))

  union all
  -- 11. The CHECK: five values, the new one among them, target_type untouched.
  select 11, 'admin_audit_log_action_check has five values', '5, incl. USER_PROFILE_UPDATED',
         (select (length(def) - length(replace(def, '::text', ''))) / 6 || ' values; ' || def from audit_check),
         (select (length(def) - length(replace(def, '::text', ''))) / 6 = 5
                 and def like '%USER_PROFILE_UPDATED%'
                 and def like '%USER_SUSPENDED%' and def like '%USER_REACTIVATED%'
                 and def like '%COMMUNITY_SUSPENDED%' and def like '%COMMUNITY_REACTIVATED%'
            from audit_check)

  union all
  select 12, 'admin_audit_log_target_type_check unchanged (USER, COMMUNITY)', 'USER, COMMUNITY',
         (select pg_get_constraintdef(oid) from pg_constraint
           where conrelid = 'public.admin_audit_log'::regclass
             and conname = 'admin_audit_log_target_type_check'),
         (select pg_get_constraintdef(oid) like '%USER%' and pg_get_constraintdef(oid) like '%COMMUNITY%'
                 and (length(pg_get_constraintdef(oid)) - length(replace(pg_get_constraintdef(oid), '::text', ''))) / 6 = 2
            from pg_constraint
           where conrelid = 'public.admin_audit_log'::regclass
             and conname = 'admin_audit_log_target_type_check')

  union all
  -- 13. The admin function set grew by exactly the six.
  select 13, 'admin_* functions: the baseline plus exactly the six', '32 (26 + 6)',
         (select count(*)::text || '; new: ' ||
                 coalesce((select string_agg(proname, ', ' order by proname)
                             from admin_fns where proname not in (select fn from baseline_admin)), 'none')
            from admin_fns),
         (select count(*) = 32 from admin_fns)
         and not exists (select 1 from admin_fns
                          where proname not in (select fn from baseline_admin)
                            and proname not in (select fn from expected))

  union all
  select 14, 'no admin_* function is executable by anon', '0',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'admin\_%'
             and has_function_privilege('anon', p.oid, 'EXECUTE')),
         (select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'admin\_%'
             and has_function_privilege('anon', p.oid, 'EXECUTE'))

  union all
  -- 15. record_admin_audit is still reachable from no client role.
  select 15, 'record_admin_audit still not executable by anon or authenticated', 'false, false',
         has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text
           || ', ' ||
         has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')::text,
         not has_function_privilege('anon', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')
           and not has_function_privilege('authenticated', 'public.record_admin_audit(text,text,uuid,text,text,jsonb)'::regprocedure, 'EXECUTE')

  union all
  -- 16. users: the policies of the baseline, and only those.
  select 16, 'users policies unchanged', 'authenticated_select_active_users (SELECT), users_update_own_profile (UPDATE)',
         (select string_agg(policyname || ' (' || cmd || ') ' || coalesce(qual, '') || coalesce(' / ' || with_check, ''),
                            E'\n' order by policyname)
            from pg_policies where schemaname = 'public' and tablename = 'users'),
         (select count(*) = 2
                 and count(*) filter (where policyname = 'authenticated_select_active_users' and cmd = 'SELECT') = 1
                 and count(*) filter (where policyname = 'users_update_own_profile' and cmd = 'UPDATE') = 1
            from pg_policies where schemaname = 'public' and tablename = 'users')

  union all
  -- 17. users: authenticated may UPDATE these nine columns and no others.
  select 17, 'users column UPDATE grants unchanged', '9 columns: full_name, phone, date_of_birth, primary_position, secondary_position, avatar_path, profile_visibility, age_visible, default_wilayat_code',
         (select count(*)::text || ': ' || coalesce(string_agg(col, ', ' order by col), '') from user_update_cols),
         (select coalesce(array_agg(col order by col), '{}'::text[]) =
                 array['age_visible', 'avatar_path', 'date_of_birth', 'default_wilayat_code',
                       'full_name', 'phone', 'primary_position', 'profile_visibility',
                       'secondary_position']
            from user_update_cols)

  union all
  select 18, 'users: anon holds no UPDATE or INSERT or DELETE', 'false, false, false',
         has_table_privilege('anon', 'public.users', 'UPDATE')::text || ', ' ||
         has_table_privilege('anon', 'public.users', 'INSERT')::text || ', ' ||
         has_table_privilege('anon', 'public.users', 'DELETE')::text,
         not has_table_privilege('anon', 'public.users', 'UPDATE')
           and not has_table_privilege('anon', 'public.users', 'INSERT')
           and not has_table_privilege('anon', 'public.users', 'DELETE')

  union all
  -- 19. The audit table is still reachable by no client role.
  select 19, 'admin_audit_log: RLS on, no policy, no client privilege', 'rls true; 0 policies; no privilege',
         (select relrowsecurity::text from pg_class where oid = 'public.admin_audit_log'::regclass)
           || '; ' || (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'admin_audit_log')
           || ' policies; anon/authenticated select='
           || has_table_privilege('anon', 'public.admin_audit_log', 'SELECT')::text || '/'
           || has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')::text,
         (select relrowsecurity from pg_class where oid = 'public.admin_audit_log'::regclass)
           and (select count(*) = 0 from pg_policies where schemaname = 'public' and tablename = 'admin_audit_log')
           and not has_table_privilege('anon', 'public.admin_audit_log', 'SELECT')
           and not has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')
           and not has_table_privilege('authenticated', 'public.admin_audit_log', 'INSERT')

  union all
  -- 20. notification_push_preferences: still the three own-row policies.
  select 20, 'notification_push_preferences policies unchanged', '3 (SELECT, INSERT, UPDATE)',
         (select count(*)::text || ': ' || coalesce(string_agg(policyname || ' (' || cmd || ')', ', ' order by cmd), '')
            from pg_policies where schemaname = 'public' and tablename = 'notification_push_preferences'),
         (select count(*) = 3
                 and count(*) filter (where cmd = 'SELECT') = 1
                 and count(*) filter (where cmd = 'INSERT') = 1
                 and count(*) filter (where cmd = 'UPDATE') = 1
            from pg_policies where schemaname = 'public' and tablename = 'notification_push_preferences')

  union all
  -- 21. The column defaults the read and the push write both rely on.
  select 21, 'push column defaults are true, true, false', 'true, true, false',
         (select string_agg(a.attname || '=' || pg_get_expr(d.adbin, d.adrelid), ', ' order by a.attname)
            from pg_attrdef d
            join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
           where d.adrelid = 'public.notification_push_preferences'::regclass
             and a.attname in ('match_push', 'community_push', 'mute_all')),
         (select count(*) = 3
                 and count(*) filter (where a.attname = 'match_push' and pg_get_expr(d.adbin, d.adrelid) = 'true') = 1
                 and count(*) filter (where a.attname = 'community_push' and pg_get_expr(d.adbin, d.adrelid) = 'true') = 1
                 and count(*) filter (where a.attname = 'mute_all' and pg_get_expr(d.adbin, d.adrelid) = 'false') = 1
            from pg_attrdef d
            join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
           where d.adrelid = 'public.notification_push_preferences'::regclass
             and a.attname in ('match_push', 'community_push', 'mute_all'))
) checks
order by n, check_name;
