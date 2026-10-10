-- == tool/0101_platform_admin_account_merge_verify.sql ==
-- Post-apply checks for migration 0101. READ ONLY: one SELECT, no write, no
-- impersonation, no merge. Run it after the migration has been applied and read the
-- `ok` column: every row should be true.
--
-- Success is the resulting database state (functions, signatures, grants, search path,
-- bodies, trigger state, and what the Auth deletion depends on), not the migration
-- record alone -- the Architect ruling of 2026-10-06, point 3. The first row is the
-- record; the rest are the state.
--
-- It cannot show behaviour, and it must never be answered by trying a merge on a real
-- account: a merge is permanent. The behaviour was shown offline, against the real
-- migration chain, on synthetic data.
--
-- ## WHAT CHECKS 18-20 ARE FOR
--
-- The merge deletes the source from `auth.users` inside the same transaction. That is
-- only safe while four things stay true of the project it runs on, and they are checked
-- here from the catalog, every time, rather than assumed:
--   18. the function's owner may delete from the Auth tables it touches;
--   19. nothing in `auth` that references `auth.users` can REFUSE the delete (every such
--       foreign key cascades or sets null);
--   20. no trigger on `auth.users` runs on DELETE.
--
-- ## WHAT THE OLDER VERIFY SCRIPTS SAY AFTERWARDS
--
-- 0101 redefines the merge preview on purpose, and two older checks pin or grade the OLD
-- one. Measured offline, on the real chain with 0101 applied, EXACTLY two checks in the
-- older scripts go false, each for the right reason, and are retired with 0101:
--   * `0096_..._verify.sql` check 18, "RATING_ARCHIVE_IMMUTABLE is a BLOCKER in both
--     previews": the immutable archives are a CONSTRAINT of a merge now, because they keep
--     naming the old UUID on purpose and `account_merge_map` says whom it became;
--   * `0099_..._verify.sql` check 14, "the merge preview and the helper are unchanged from
--     0096 (hashes)": the merge preview is the function 0101 replaces.
-- Every other check of both scripts stays true. Run THIS script for the merge.
--
-- ## BASELINE
--
-- Checks 13 and 14 pin bodies by hash. They are exact for the chain this was written for:
-- 0096 and 0099 as committed, then 0101. If a later migration changes one of those
-- functions, the matching check goes false for the right reason and is retired with it.

with
fn(name, args, kind) as (
  values
    ('admin_merge_accounts',            'p_retained_user_id uuid, p_source_user_id uuid, p_resolutions jsonb', 'api'),
    ('admin_preview_account_merge',     'p_retained_user_id uuid, p_source_user_id uuid', 'api'),
    ('merge_skips_lifecycle',           'p_user_id uuid', 'internal'),
    ('merge_rating_scope_excludes',     'p_user_id uuid', 'internal'),
    ('merge_shared_matches',            'p_retained_user_id uuid, p_source_user_id uuid', 'internal'),
    ('merge_participation_blockers',    'p_match_id uuid, p_user_id uuid', 'internal'),
    ('merge_invariants',                'p_retained_user_id uuid, p_source_user_id uuid', 'internal')
),
found as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.provolatile, p.proowner,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_function_result(p.oid) as result,
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
     and (p.proname like 'merge\_%' or p.proname = 'admin_merge_accounts'
          or p.proname = 'admin_preview_account_merge' or p.proname = 'apply_rating_delta'
          or p.proname in ('capture_match_registration_event', 'capture_community_membership_event',
                           'advance_match_participation_revision', 'admin_preview_account_snapshot',
                           'admin_preview_account_deletion'))
),
mine as (
  select f.* from found f
    join fn on fn.name = f.proname and fn.args = f.args
),
merge_fn as (select * from found where proname = 'admin_merge_accounts'),
-- everything in the merge body AFTER its last statement that deletes from auth.users
after_auth as (
  select substring(m.src_compact from '.*deletefromauth\.userswhereid=p_source_user_id;(.*)$') as tail
    from merge_fn m
),
known_fks as (
  select string_agg(cl.relname::text || '.' || a.attname::text, ', ' order by cl.relname, a.attname) as listing
    from pg_constraint k
    join pg_class cl on cl.oid = k.conrelid
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
   where k.contype = 'f' and k.confrelid = 'public.users'::regclass
     and cl.relnamespace = 'public'::regnamespace
)
select n, check_name, expected, actual, ok
from (
  -- 1. The record.
  select 1 as n, 'migration recorded' as check_name, '1 record' as expected,
         (select count(*)::text || ' record(s)' from supabase_migrations.schema_migrations
           where name like '%0101_platform_admin_account_merge%') as actual,
         (select count(*) = 1 from supabase_migrations.schema_migrations
           where name like '%0101_platform_admin_account_merge%') as ok

  union all
  -- 2. The seven functions, by exact signature, once each.
  select 2, 'function ' || fn.name || '(' || fn.args || ')', 'exists, once',
         (select count(*)::text from found f where f.proname = fn.name and f.args = fn.args),
         (select count(*) = 1 from found f where f.proname = fn.name and f.args = fn.args)
    from fn

  union all
  select 3, 'no overload of a merge function exists besides those', '7',
         (select count(*)::text from found
           where proname like 'merge\_%' or proname in ('admin_merge_accounts', 'admin_preview_account_merge')),
         (select count(*) = 7 from found
           where proname like 'merge\_%' or proname in ('admin_merge_accounts', 'admin_preview_account_merge'))

  union all
  -- 4. The merge: security definer, VOLATILE (it writes), pg_temp last.
  select 4, 'admin_merge_accounts is security definer, volatile, search_path = public, pg_temp, returns jsonb', 'true; v; public, pg_temp; jsonb',
         (select prosecdef::text || '; ' || provolatile::text || '; ' || coalesce(array_to_string(proconfig, ','), 'none') || '; ' || result from merge_fn),
         (select prosecdef and provolatile = 'v' and proconfig = array['search_path=public, pg_temp'] and result = 'jsonb' from merge_fn)

  union all
  -- 5. The preview stays read only: STABLE makes PostgreSQL itself refuse a write.
  select 5, 'admin_preview_account_merge is security definer, STABLE, search_path = public, pg_temp', 'true; s; public, pg_temp',
         (select prosecdef::text || '; ' || provolatile::text || '; ' || coalesce(array_to_string(proconfig, ','), 'none')
            from found where proname = 'admin_preview_account_merge'),
         (select prosecdef and provolatile = 's' and proconfig = array['search_path=public, pg_temp']
            from found where proname = 'admin_preview_account_merge')

  union all
  select 6, 'every internal helper is STABLE and has pg_temp last', '5',
         (select count(*)::text from mine where proname not in ('admin_merge_accounts', 'admin_preview_account_merge')
             and provolatile = 's' and proconfig = array['search_path=public, pg_temp']),
         (select count(*) = 5 from mine where proname not in ('admin_merge_accounts', 'admin_preview_account_merge')
             and provolatile = 's' and proconfig = array['search_path=public, pg_temp'])

  union all
  -- 7. Who can run what: anon and PUBLIC nothing; signed-in users the merge and its preview; the helpers no client.
  select 7, 'anon and PUBLIC cannot execute any merge function', '0',
         (select count(*)::text from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute),
         (select count(*) = 0 from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute)

  union all
  select 8, 'authenticated and service_role can execute the merge and its preview, and NO client role any helper', 'merge, preview; no helper',
         (select coalesce(string_agg(proname, ', ' order by proname), 'none') from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE')),
         (select count(*) = 2 and bool_and(proname in ('admin_merge_accounts', 'admin_preview_account_merge')) from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE'))
         and (select count(*) = 2 from mine
               where proname in ('admin_merge_accounts', 'admin_preview_account_merge')
                 and has_function_privilege('service_role', oid, 'EXECUTE'))

  union all
  -- 9. The gate: the helper-based check AND an independent look at public.system_admins, in both.
  select 9, 'both API functions independently check public.system_admins for auth.uid()', '2',
         (select count(*)::text from mine
           where (proname = 'admin_preview_account_merge'
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%')
              or (proname = 'admin_merge_accounts'
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=v_caller)%')),
         (select count(*) = 2 from mine
           where (proname = 'admin_preview_account_merge'
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=auth.uid())%')
              or (proname = 'admin_merge_accounts'
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=v_caller)%'))

  union all
  -- 10. The preview writes nothing; the merge reaches no network, disables no trigger, runs no dynamic SQL, changes no schema.
  select 10, 'the preview writes nothing; the merge makes no HTTP call, disables no trigger, runs no dynamic SQL and alters no schema', '0',
         (select count(*)::text from mine
           where (proname <> 'admin_merge_accounts'
                  and src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|record_admin_audit|executeformat|execute'')')
              or (proname = 'admin_merge_accounts'
                  and src_compact ~ '(http_post|http_get|net\.http|session_replication_role|disabletrigger|enabletrigger|altertable|createtable|droptable|dropfunction|executeformat|execute'')')),
         (select count(*) = 0 from mine
           where (proname <> 'admin_merge_accounts'
                  and src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|createtable|altertable|droptable|record_admin_audit|executeformat|execute'')')
              or (proname = 'admin_merge_accounts'
                  and src_compact ~ '(http_post|http_get|net\.http|session_replication_role|disabletrigger|enabletrigger|altertable|createtable|droptable|dropfunction|executeformat|execute'')'))

  union all
  -- 11. Locking and serialising: one advisory lock, the two accounts locked first, switches bound to the transaction.
  select 11, 'the merge takes one advisory lock, locks accounts, communities and matches FOR UPDATE, and arms its switches for this transaction only', 'lock; 3 x for update; armed twice; none session-wide',
         (select (src_compact like '%pg_advisory_xact_lock(%')::text || '; '
                 || ((length(src_compact) - length(replace(src_compact, 'forupdate;', ''))) / length('forupdate;'))::text || '; '
                 || ((length(src_compact) - length(replace(src_compact, '''goplay.account_merge'',''tx:''||txid_current()::text,true)', ''))) / length('''goplay.account_merge'',''tx:''||txid_current()::text,true)'))::text || '; '
                 || (src_compact ~ 'set_config\([^;]*,false\)')::text
            from merge_fn),
         (select src_compact like '%pg_advisory_xact_lock(%'
             and ((length(src_compact) - length(replace(src_compact, 'forupdate;', ''))) / length('forupdate;')) >= 3
             and ((length(src_compact) - length(replace(src_compact, '''goplay.account_merge'',''tx:''||txid_current()::text,true)', ''))) / length('''goplay.account_merge'',''tx:''||txid_current()::text,true)')) = 2
             and src_compact like '%set_config(''goplay.account_merge_users'',p_retained_user_id::text||'',''||p_source_user_id::text,true)%'
             and src_compact like '%set_config(''goplay.rating_replay_user'',p_retained_user_id::text,true)%'
             and src_compact !~ 'set_config\([^;]*,false\)'
            from merge_fn)

  union all
  -- 12. The AUTH deletion is in the same function, appears exactly once, and is the last WRITE of it.
  select 12, 'the merge deletes from auth.users exactly once, inside the same function, and writes nothing after it', '1; no write after',
         (select ((length(src_compact) - length(replace(src_compact, 'deletefromauth.usersw', ''))) / length('deletefromauth.usersw'))::text
                 || '; ' || case when (select tail from after_auth) ~ '(insertinto|deletefrom|update[a-z_.]+set|perform(?!set_config))' then 'WRITE AFTER' else 'no write after' end
            from merge_fn),
         (select ((length(src_compact) - length(replace(src_compact, 'deletefromauth.usersw', ''))) / length('deletefromauth.usersw')) = 1
             and (select tail from after_auth) is not null
             and (select tail from after_auth) !~ '(insertinto|deletefrom|update[a-z_.]+set|perform(?!set_config))'
            from merge_fn)

  union all
  -- 13. The bodies are exactly the ones 0101 defines (hashes).
  select 13, 'the merge, its preview and the five helpers are exactly the bodies 0101 defines (hashes)', '7 of 7',
         (select count(*)::text || ' of 7' from mine where
            (proname = 'admin_merge_accounts'           and src_md5 = 'f8d2ec026cb79d58363c985866347098')
         or (proname = 'admin_preview_account_merge'    and src_md5 = 'd56b5e4610d54e2a49a7b215ea7cd545')
         or (proname = 'merge_skips_lifecycle'          and src_md5 = '42282473e1813a112c13d3f840b0f6b5')
         or (proname = 'merge_rating_scope_excludes'    and src_md5 = '46a3e57a19c56f20e3b02df9829b693d')
         or (proname = 'merge_shared_matches'           and src_md5 = '2c29a044403fbc49f99d58dfb24cdc85')
         or (proname = 'merge_participation_blockers'   and src_md5 = 'a863bf56041fc6f3be7069e0a5700d79')
         or (proname = 'merge_invariants'               and src_md5 = '91d2aee4c54bae6f5ad112e6aa7d0597')),
         (select count(*) = 7 from mine where
            (proname = 'admin_merge_accounts'           and src_md5 = 'f8d2ec026cb79d58363c985866347098')
         or (proname = 'admin_preview_account_merge'    and src_md5 = 'd56b5e4610d54e2a49a7b215ea7cd545')
         or (proname = 'merge_skips_lifecycle'          and src_md5 = '42282473e1813a112c13d3f840b0f6b5')
         or (proname = 'merge_rating_scope_excludes'    and src_md5 = '46a3e57a19c56f20e3b02df9829b693d')
         or (proname = 'merge_shared_matches'           and src_md5 = '2c29a044403fbc49f99d58dfb24cdc85')
         or (proname = 'merge_participation_blockers'   and src_md5 = 'a863bf56041fc6f3be7069e0a5700d79')
         or (proname = 'merge_invariants'               and src_md5 = '91d2aee4c54bae6f5ad112e6aa7d0597'))

  union all
  -- 14. The four existing functions carry their guard and are otherwise unchanged (hashes), and are SECURITY DEFINER as before.
  select 14, 'the four guarded functions are exactly the live bodies plus their one guard (hashes)', '4 of 4',
         (select count(*)::text || ' of 4' from found where prosecdef and (
            (proname = 'capture_match_registration_event'      and src_md5 = '12fd8d14b105784c158441a334481379')
         or (proname = 'capture_community_membership_event'    and src_md5 = 'fe6776cc73cee63f0ed48056eed5ec50')
         or (proname = 'advance_match_participation_revision'  and src_md5 = '52b368367bae17adfe00181ed9b0346c')
         or (proname = 'apply_rating_delta'                    and src_md5 = '2d2fc5f4d68e43573136864be91d1019'))),
         (select count(*) = 4 from found where prosecdef and (
            (proname = 'capture_match_registration_event'      and src_md5 = '12fd8d14b105784c158441a334481379')
         or (proname = 'capture_community_membership_event'    and src_md5 = 'fe6776cc73cee63f0ed48056eed5ec50')
         or (proname = 'advance_match_participation_revision'  and src_md5 = '52b368367bae17adfe00181ed9b0346c')
         or (proname = 'apply_rating_delta'                    and src_md5 = '2d2fc5f4d68e43573136864be91d1019')))

  union all
  -- 15. NO TRIGGER IS DISABLED: every trigger the merge stands aside for, and the archives' own, are enabled.
  select 15, 'the lifecycle, lineup and archive triggers all exist and are enabled (none disabled)', '7 enabled',
         (select count(*)::text || ' enabled' from pg_trigger t
           where not t.tgisinternal and t.tgenabled = 'O'
             and t.tgname in ('match_registrations_capture_lifecycle', 'community_members_capture_lifecycle',
                              'match_team_assignments_advance_participation_revision', 'rating_history_immutable',
                              'rating_history_archive_immutable', 'rating_history_archive_undeletable',
                              'user_rating_archive_immutable')),
         (select count(*) = 7 from pg_trigger t
           where not t.tgisinternal and t.tgenabled = 'O'
             and t.tgname in ('match_registrations_capture_lifecycle', 'community_members_capture_lifecycle',
                              'match_team_assignments_advance_participation_revision', 'rating_history_immutable',
                              'rating_history_archive_immutable', 'rating_history_archive_undeletable',
                              'user_rating_archive_immutable'))

  union all
  -- 16. The mapping: three columns, closed to every client role, row level security on.
  select 16, 'account_merge_map has exactly source, retained and time; RLS on; no client privilege', 'merged_at, retained_user_id, source_user_id; rls; none',
         (select coalesce(string_agg(a.attname, ', ' order by a.attname), 'missing')
            from pg_attribute a where a.attrelid = to_regclass('public.account_merge_map') and a.attnum > 0 and not a.attisdropped)
           || '; rls ' || coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.account_merge_map')), 'missing'),
         (select count(*) = 3 from pg_attribute a where a.attrelid = to_regclass('public.account_merge_map') and a.attnum > 0 and not a.attisdropped
                   and a.attname in ('source_user_id', 'retained_user_id', 'merged_at'))
         and (select count(*) = 3 from pg_attribute a where a.attrelid = to_regclass('public.account_merge_map') and a.attnum > 0 and not a.attisdropped)
         and (select relrowsecurity from pg_class where oid = to_regclass('public.account_merge_map'))
         and not has_table_privilege('anon', 'public.account_merge_map', 'SELECT')
         and not has_table_privilege('authenticated', 'public.account_merge_map', 'SELECT')
         and not has_table_privilege('authenticated', 'public.account_merge_map', 'INSERT')

  union all
  -- 17. The audit log accepts the one new action, still accepts the old ones, and is still closed to clients.
  select 17, 'admin_audit_log accepts USER_ACCOUNTS_MERGED and the five older actions; still closed to clients', 'six actions; rls; no select',
         (select (pg_get_constraintdef(oid) like '%USER_ACCOUNTS_MERGED%')::text from pg_constraint where conname = 'admin_audit_log_action_check')
           || '; ' || (select relrowsecurity::text from pg_class where oid = 'public.admin_audit_log'::regclass),
         (select pg_get_constraintdef(oid) like '%USER_ACCOUNTS_MERGED%' and pg_get_constraintdef(oid) like '%USER_PROFILE_UPDATED%'
                 and pg_get_constraintdef(oid) like '%COMMUNITY_REACTIVATED%'
            from pg_constraint where conname = 'admin_audit_log_action_check')
         and (select relrowsecurity from pg_class where oid = 'public.admin_audit_log'::regclass)
         and not has_table_privilege('authenticated', 'public.admin_audit_log', 'SELECT')

  union all
  -- 18. THE AUTH DELETE IS PERMITTED: the merge's owner may delete from every Auth table it touches.
  select 18, 'the merge''s owner may delete from auth.users, identities, sessions, refresh_tokens and flow_state', 'all true',
         (select (has_table_privilege(pg_get_userbyid(proowner), 'auth.users', 'DELETE')
                  and has_table_privilege(pg_get_userbyid(proowner), 'auth.identities', 'DELETE')
                  and has_table_privilege(pg_get_userbyid(proowner), 'auth.sessions', 'DELETE')
                  and has_table_privilege(pg_get_userbyid(proowner), 'auth.refresh_tokens', 'DELETE')
                  and has_table_privilege(pg_get_userbyid(proowner), 'auth.flow_state', 'DELETE'))::text from merge_fn),
         (select has_table_privilege(pg_get_userbyid(proowner), 'auth.users', 'DELETE')
             and has_table_privilege(pg_get_userbyid(proowner), 'auth.identities', 'DELETE')
             and has_table_privilege(pg_get_userbyid(proowner), 'auth.sessions', 'DELETE')
             and has_table_privilege(pg_get_userbyid(proowner), 'auth.refresh_tokens', 'DELETE')
             and has_table_privilege(pg_get_userbyid(proowner), 'auth.flow_state', 'DELETE')
            from merge_fn)

  union all
  -- 19. NOTHING IN AUTH CAN REFUSE IT: every foreign key to auth.users cascades or sets null.
  select 19, 'no foreign key to auth.users can refuse the delete (every one cascades or sets null)', '0 that refuse',
         (select count(*)::text || ' that refuse' from pg_constraint k
           where k.contype = 'f' and k.confrelid = 'auth.users'::regclass and k.confdeltype in ('a', 'r')),
         (select count(*) = 0 from pg_constraint k
           where k.contype = 'f' and k.confrelid = 'auth.users'::regclass and k.confdeltype in ('a', 'r'))

  union all
  -- 20. NO TRIGGER ON auth.users RUNS ON DELETE (tgtype bit 8), so a delete runs nothing else.
  select 20, 'no trigger on auth.users fires on DELETE', '0',
         (select count(*)::text from pg_trigger t
           where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal and (t.tgtype & 8) <> 0),
         (select count(*) = 0 from pg_trigger t
           where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal and (t.tgtype & 8) <> 0)

  union all
  -- 21. THE SCHEMA STILL HAS NO REFERENCE TO public.users THE MERGE DOES NOT KNOW.
  select 21, 'the foreign keys to public.users are exactly the sixteen the merge knows', 'see listing',
         (select listing from known_fks),
         (select listing = 'communities.owner_id, community_members.user_id, community_statistics.user_id, match_goals.user_id, '
                        || 'match_professional_guests.created_by, match_registrations.user_id, match_results.mvp_user_id, '
                        || 'match_results.recorded_by, match_team_assignments.user_id, matches.created_by, '
                        || 'notification_push_preferences.user_id, notification_push_tokens.user_id, notifications.user_id, '
                        || 'player_statistics.user_id, rating_history.user_id, system_admins.user_id'
            from known_fks)

  union all
  -- 22. The neighbours 0101 does not redefine are as 0096 and 0099 left them (hashes).
  select 22, 'the helper snapshot and the deletion preview are unchanged (hashes)', '2 of 2',
         (select count(*)::text || ' of 2' from found where
            (proname = 'admin_preview_account_snapshot' and src_md5 = '99fefffab545f72e72496b5213c59ad5')
         or (proname = 'admin_preview_account_deletion' and src_md5 = 'b34fcb36ecf531263044af13c8da0b66')),
         (select count(*) = 2 from found where
            (proname = 'admin_preview_account_snapshot' and src_md5 = '99fefffab545f72e72496b5213c59ad5')
         or (proname = 'admin_preview_account_deletion' and src_md5 = 'b34fcb36ecf531263044af13c8da0b66'))
) checks
order by n, check_name;


-- ============================================================================
-- What this script will not do
-- ============================================================================
-- It will not run a merge. A merge removes an account permanently, and nothing here
-- needs one: every property a merge relies on is checked above from the catalog. To
-- see what a merge WOULD do for two real accounts, use the read-only preview:
--
--   select set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
--   select set_config('request.jwt.claims',
--     json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);
--   select public.admin_preview_account_merge('<RETAINED_ID>'::uuid, '<SOURCE_ID>'::uuid);
--
-- Run it as ONE batch. `has_blockers = false` is a statement about the preview only: it
-- does NOT mean a merge is safe or authorised for those two people. The preview shows
-- personal data to whoever runs it: use it only for accounts you are entitled to see.
