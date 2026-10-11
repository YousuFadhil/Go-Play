-- == tool/0103_admin_user_auth_management_verify.sql ==
-- Post-apply checks for migration 0103. READ ONLY: one SELECT, no write, no impersonation, no
-- credential change, no email. Run it after the migration has been applied and read the `ok` column:
-- every row should be true.
--
-- Success is the resulting database state (functions, signatures, grants, search path, volatility,
-- bodies, the audit action list), not the migration record alone. The first row is the record; the
-- rest are the state.
--
-- It cannot show behaviour, and it must never be answered by changing a real account's email or
-- password: that is a real credential change, and the recovery check sends a real email. The behaviour
-- was shown offline, against the real migration chain, on synthetic data; the first live exercise is a
-- designated test account, after the Edge Function is deployed.
--
-- 0103 redefines nothing from an earlier migration, so no earlier verify script changes its answer.

with
fn(name, args) as (
  values
    ('admin_user_auth_guard',            'p_user_id uuid'),
    ('admin_check_user_auth_action',     'p_user_id uuid, p_action text, p_new_email text'),
    ('admin_record_user_email_changed',  'p_user_id uuid, p_reason text'),
    ('admin_record_user_recovery_sent',  'p_user_id uuid, p_reason text, p_after_email_change boolean'),
    ('admin_record_user_password_set',   'p_user_id uuid, p_reason text')
),
found as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.provolatile,
         pg_get_function_identity_arguments(p.oid) as args,
         regexp_replace(p.prosrc, '\s+', '', 'g') as src_compact,
         md5(replace(p.prosrc, E'\r\n', E'\n')) as src_md5,
         exists (
           select 1
             from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where a.grantee = 0 and a.privilege_type = 'EXECUTE'
         ) as public_can_execute
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_user_auth_guard', 'admin_check_user_auth_action',
                       'admin_record_user_email_changed', 'admin_record_user_recovery_sent',
                       'admin_record_user_password_set', 'record_admin_audit')
),
mine as (
  select f.* from found f join fn on fn.name = f.proname and fn.args = f.args
),
writers as (select * from mine where proname like 'admin\_record\_user\_%'),
audit_def as (
  select pg_get_constraintdef(c.oid) as def
    from pg_constraint c
   where c.conname = 'admin_audit_log_action_check'
     and c.conrelid = 'public.admin_audit_log'::regclass
)
select n, check_name, expected, actual, ok
from (
  -- 1. The record.
  select 1 as n, 'migration recorded' as check_name, '1 record' as expected,
         (select count(*)::text || ' record(s)' from supabase_migrations.schema_migrations
           where name like '%0103_admin_user_auth_management%') as actual,
         (select count(*) = 1 from supabase_migrations.schema_migrations
           where name like '%0103_admin_user_auth_management%') as ok

  union all
  -- 2. The five functions, by exact signature, once each.
  select 2, 'function ' || fn.name || '(' || fn.args || ')', 'exists, once',
         (select count(*)::text from found f where f.proname = fn.name and f.args = fn.args),
         (select count(*) = 1 from found f where f.proname = fn.name and f.args = fn.args)
    from fn

  union all
  -- 3. Hardened the same way as 0095: security definer, search_path = public, pg_temp.
  select 3, 'all five are security definer with search_path = public, pg_temp', '5 of 5',
         (select count(*)::text || ' of 5' from mine
           where prosecdef and proconfig = array['search_path=public, pg_temp']),
         (select count(*) = 5 from mine
           where prosecdef and proconfig = array['search_path=public, pg_temp'])

  union all
  -- 4. The check and the guard only read (STABLE); the writers write one audit row (VOLATILE).
  select 4, 'the check and the guard are STABLE; the three writers are VOLATILE', '2 stable, 3 volatile',
         (select count(*) filter (where provolatile = 's')::text || ' stable, '
                 || count(*) filter (where provolatile = 'v')::text || ' volatile' from mine),
         (select count(*) filter (where provolatile = 's' and proname in ('admin_user_auth_guard', 'admin_check_user_auth_action')) = 2
             and count(*) filter (where provolatile = 'v' and proname like 'admin\_record\_user\_%') = 3 from mine)

  union all
  -- 5. anon and PUBLIC can run none of them.
  select 5, 'anon and PUBLIC cannot execute any of them', '0',
         (select count(*)::text from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute),
         (select count(*) = 0 from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute)

  union all
  -- 6. Signed-in users: the four API functions and NOT the guard.
  select 6, 'authenticated can execute the four API functions and not the guard', 'api 4; guard 0',
         (select coalesce(string_agg(proname, ', ' order by proname), 'none') from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE')),
         (select count(*) = 4 and bool_and(proname <> 'admin_user_auth_guard') from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE'))

  union all
  -- 7. The gate is in ONE place, asks the helper AND the table, and every public function calls it first.
  select 7, 'the guard checks System Admin twice and the caller from auth.uid(); the four others call it first', '5',
         (select count(*)::text from mine
           where (proname = 'admin_user_auth_guard'
                  and src_compact like '%v_calleruuid:=auth.uid()%'
                  and src_compact like '%notpublic.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=v_caller)%'
                  and src_compact like '%raiseexception''CANNOT_MODIFY_SELF''%'
                  and src_compact like '%raiseexception''CANNOT_MODIFY_SYSTEM_ADMIN''%'
                  and src_compact like '%andu.deleted_atisnull%'
                  and src_compact like '%andau.deleted_atisnull%')
              or (proname <> 'admin_user_auth_guard'
                  and src_compact like '%:=public.admin_user_auth_guard(p_user_id);%'
                  and src_compact not like '%auth.uid()%')),
         (select count(*) = 5 from mine
           where (proname = 'admin_user_auth_guard'
                  and src_compact like '%v_calleruuid:=auth.uid()%'
                  and src_compact like '%notpublic.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=v_caller)%'
                  and src_compact like '%raiseexception''CANNOT_MODIFY_SELF''%'
                  and src_compact like '%raiseexception''CANNOT_MODIFY_SYSTEM_ADMIN''%'
                  and src_compact like '%andu.deleted_atisnull%'
                  and src_compact like '%andau.deleted_atisnull%')
              or (proname <> 'admin_user_auth_guard'
                  and src_compact like '%:=public.admin_user_auth_guard(p_user_id);%'
                  and src_compact not like '%auth.uid()%'))

  union all
  -- 8. No actor is ever a parameter, and nothing here writes a credential, an identity or a session.
  select 8, 'no function takes an actor; none writes auth.*, sends a request or runs dynamic SQL', '0',
         (select count(*)::text from mine
           where args ilike '%actor%'
              or src_compact ~ '(insertintoauth\.|updateauth\.|deletefromauth\.|net\.http|http_post|executeformat|execute'')'),
         (select count(*) = 0 from mine
           where args ilike '%actor%'
              or src_compact ~ '(insertintoauth\.|updateauth\.|deletefromauth\.|net\.http|http_post|executeformat|execute'')')

  union all
  -- 9. The check and the guard write nothing at all.
  select 9, 'the check and the guard contain no INSERT, UPDATE, DELETE or audit call', '0',
         (select count(*)::text from mine
           where proname in ('admin_user_auth_guard', 'admin_check_user_auth_action')
             and src_compact ~ '(insertinto|deletefrom|truncate|update[a-z_.]+set|record_admin_audit)'),
         (select count(*) = 0 from mine
           where proname in ('admin_user_auth_guard', 'admin_check_user_auth_action')
             and src_compact ~ '(insertinto|deletefrom|truncate|update[a-z_.]+set|record_admin_audit)')

  union all
  -- 10. Each writer is fixed to ITS action and to its own metadata: one record_admin_audit call, one literal.
  select 10, 'each writer records exactly its own action through record_admin_audit, and no other', '3',
         (select count(*)::text from writers w
           where (select count(*) from regexp_matches(w.src_compact, 'record_admin_audit\(', 'g')) = 1
             and (select count(*) from regexp_matches(w.src_compact, '''USER_[A-Z_]+''', 'g')) = 1
             and ((w.proname = 'admin_record_user_email_changed'  and w.src_compact like '%''USER_EMAIL_CHANGED''%')
               or (w.proname = 'admin_record_user_recovery_sent'  and w.src_compact like '%''USER_RECOVERY_SENT''%')
               or (w.proname = 'admin_record_user_password_set'   and w.src_compact like '%''USER_PASSWORD_SET''%'))),
         (select count(*) = 3 from writers w
           where (select count(*) from regexp_matches(w.src_compact, 'record_admin_audit\(', 'g')) = 1
             and (select count(*) from regexp_matches(w.src_compact, '''USER_[A-Z_]+''', 'g')) = 1
             and ((w.proname = 'admin_record_user_email_changed'  and w.src_compact like '%''USER_EMAIL_CHANGED''%')
               or (w.proname = 'admin_record_user_recovery_sent'  and w.src_compact like '%''USER_RECOVERY_SENT''%')
               or (w.proname = 'admin_record_user_password_set'   and w.src_compact like '%''USER_PASSWORD_SET''%')))

  union all
  -- 11. The reason is required and bounded in every writer.
  select 11, 'every writer requires a reason of 1..500 characters', '3',
         (select count(*)::text from writers
           where src_compact like '%v_reasonisnullorchar_length(v_reason)>500%'
             and src_compact like '%raiseexception''INVALID_REASON''%'),
         (select count(*) = 3 from writers
           where src_compact like '%v_reasonisnullorchar_length(v_reason)>500%'
             and src_compact like '%raiseexception''INVALID_REASON''%')

  union all
  -- 12. The audit action list: the seven older actions and the three new ones, nothing else.
  select 12, 'the audit action list holds exactly the ten actions', '10',
         (select (select count(*) from regexp_matches(def, '''[A-Z_]+''', 'g'))::text from audit_def),
         (select (select count(*) from regexp_matches(def, '''[A-Z_]+''', 'g')) = 10
             and def like '%''USER_SUSPENDED''%' and def like '%''USER_REACTIVATED''%'
             and def like '%''COMMUNITY_SUSPENDED''%' and def like '%''COMMUNITY_REACTIVATED''%'
             and def like '%''USER_PROFILE_UPDATED''%' and def like '%''USER_ACCOUNTS_MERGED''%'
             and def like '%''USER_ACCOUNT_DELETED''%' and def like '%''USER_EMAIL_CHANGED''%'
             and def like '%''USER_RECOVERY_SENT''%' and def like '%''USER_PASSWORD_SET''%'
            from audit_def)

  union all
  -- 13. The generic audit writer is still granted to nobody.
  select 13, 'record_admin_audit is still executable by no client role', '0',
         (select count(*)::text from found
           where proname = 'record_admin_audit'
             and (has_function_privilege('anon', oid, 'EXECUTE')
                  or has_function_privilege('authenticated', oid, 'EXECUTE') or public_can_execute)),
         (select count(*) = 0 from found
           where proname = 'record_admin_audit'
             and (has_function_privilege('anon', oid, 'EXECUTE')
                  or has_function_privilege('authenticated', oid, 'EXECUTE') or public_can_execute))

  union all
  -- 14-18. The five bodies, pinned: any later edit of a function shows here.
  select 14, 'body of admin_user_auth_guard is the reviewed one', 'e4d76ba57d39764ee3883a58c0d647d3',
         (select src_md5 from mine where proname = 'admin_user_auth_guard'),
         coalesce((select src_md5 = 'e4d76ba57d39764ee3883a58c0d647d3' from mine where proname = 'admin_user_auth_guard'), false)
  union all
  select 15, 'body of admin_check_user_auth_action is the reviewed one', '6e55e5ebcde9c4572ecbd0570bd26463',
         (select src_md5 from mine where proname = 'admin_check_user_auth_action'),
         coalesce((select src_md5 = '6e55e5ebcde9c4572ecbd0570bd26463' from mine where proname = 'admin_check_user_auth_action'), false)
  union all
  select 16, 'body of admin_record_user_email_changed is the reviewed one', '84e20c7c351c750f32c397504f25fee4',
         (select src_md5 from mine where proname = 'admin_record_user_email_changed'),
         coalesce((select src_md5 = '84e20c7c351c750f32c397504f25fee4' from mine where proname = 'admin_record_user_email_changed'), false)
  union all
  select 17, 'body of admin_record_user_recovery_sent is the reviewed one', '1cc3219a1c8240e138187cd2a8af9ebe',
         (select src_md5 from mine where proname = 'admin_record_user_recovery_sent'),
         coalesce((select src_md5 = '1cc3219a1c8240e138187cd2a8af9ebe' from mine where proname = 'admin_record_user_recovery_sent'), false)
  union all
  select 18, 'body of admin_record_user_password_set is the reviewed one', '874f2d3420b9dc55750bd2c89fff9da8',
         (select src_md5 from mine where proname = 'admin_record_user_password_set'),
         coalesce((select src_md5 = '874f2d3420b9dc55750bd2c89fff9da8' from mine where proname = 'admin_record_user_password_set'), false)

  union all
  -- 19. The data: no event of the three kinds holds an address, and their metadata is the fixed shape.
  select 19, 'no event of the three kinds carries an address, a password or an unexpected key', '0',
         (select count(*)::text from public.admin_audit_log a
           where a.action in ('USER_EMAIL_CHANGED', 'USER_RECOVERY_SENT', 'USER_PASSWORD_SET')
             and (a.metadata::text like '%@%' or a.metadata::text ilike '%password%'
                  or (a.action <> 'USER_RECOVERY_SENT' and a.metadata <> '{}'::jsonb)
                  or (a.action = 'USER_RECOVERY_SENT' and a.metadata - 'after_email_change' <> '{}'::jsonb))),
         (select count(*) = 0 from public.admin_audit_log a
           where a.action in ('USER_EMAIL_CHANGED', 'USER_RECOVERY_SENT', 'USER_PASSWORD_SET')
             and (a.metadata::text like '%@%' or a.metadata::text ilike '%password%'
                  or (a.action <> 'USER_RECOVERY_SENT' and a.metadata <> '{}'::jsonb)
                  or (a.action = 'USER_RECOVERY_SENT' and a.metadata - 'after_email_change' <> '{}'::jsonb)))
) checks
order by n, check_name;
