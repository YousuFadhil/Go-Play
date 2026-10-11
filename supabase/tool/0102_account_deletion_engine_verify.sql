-- == tool/0102_account_deletion_engine_verify.sql ==
-- Post-apply checks for migration 0102. READ ONLY: one SELECT, no write, no impersonation, no
-- deletion. Run it after the migration has been applied and read the `ok` column: every row should
-- be true.
--
-- Success is the resulting database state (functions, signatures, grants, search path, bodies, the
-- one constraint that is gone, the trigger, and the data), not the migration record alone. The first
-- row is the record; the rest are the state.
--
-- It cannot show behaviour, and it must never be answered by deleting a real account: a deletion is
-- permanent. The behaviour was shown offline, against the real migration chain, on synthetic data.
--
-- ## WHAT THE OLDER VERIFY SCRIPTS SAY AFTERWARDS
--
-- 0102 redefines `admin_merge_accounts` and `admin_preview_account_deletion`, drops `users_id_fkey`
-- and adds an AFTER DELETE trigger on `auth.users`. So, on purpose, and each for the right reason:
--   * `0101_..._verify.sql` check 13 (the merge body hash), check 20 (no trigger on auth.users runs
--     on DELETE) and check 22 (the deletion preview is still the 0099 body) go false;
--   * `0099_..._verify.sql` checks that pin the deletion preview body go false.
-- Run THIS script for the merge executor and the deletion preview from now on. The data checks 17
-- and 18 read `deleted_at` through `to_jsonb`, so that on a database without 0102 they show red
-- rows instead of failing to run.

with
fn(name, args) as (
  values
    ('delete_account_core',            'p_user_id uuid'),
    ('admin_delete_account',           'p_user_id uuid'),
    ('delete_my_account',              ''),
    ('admin_preview_account_deletion', 'p_user_id uuid'),
    ('preview_my_account_deletion',    ''),
    ('account_deletion_blockers',      'p_user_id uuid'),
    ('account_football_evidence',      'p_user_id uuid'),
    ('anonymize_user_profile',         'p_user_id uuid'),
    ('handle_auth_user_deleted',       ''),
    ('deleted_player_name',            '')
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
     and p.proname in ('delete_account_core', 'admin_delete_account', 'delete_my_account',
                       'admin_preview_account_deletion', 'preview_my_account_deletion',
                       'account_deletion_blockers', 'account_football_evidence',
                       'anonymize_user_profile', 'handle_auth_user_deleted', 'deleted_player_name',
                       'admin_merge_accounts', 'admin_preview_account_merge', 'merge_invariants',
                       'merge_source_stored_files', 'merge_shared_matches',
                       'merge_participation_blockers', 'merge_skips_lifecycle',
                       'merge_rating_scope_excludes')
),
mine as (
  select f.* from found f join fn on fn.name = f.proname and fn.args = f.args
),
core as (select * from found where proname = 'delete_account_core'),
merge_fn as (select * from found where proname = 'admin_merge_accounts'),
-- everything in the engine AFTER its last statement that deletes from auth.users
after_auth as (
  select substring(m.src_compact from '.*deletefromauth\.userswhereid=p_user_id;(.*)$') as tail
    from core m
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
           where name like '%0102_account_deletion_engine%') as actual,
         (select count(*) = 1 from supabase_migrations.schema_migrations
           where name like '%0102_account_deletion_engine%') as ok

  union all
  -- 2. The ten functions, by exact signature, once each.
  select 2, 'function ' || fn.name || '(' || fn.args || ')', 'exists, once',
         (select count(*)::text from found f where f.proname = fn.name and f.args = fn.args),
         (select count(*) = 1 from found f where f.proname = fn.name and f.args = fn.args)
    from fn

  union all
  -- 3. The engine and the two entry points write, so they are VOLATILE; the previews are STABLE.
  select 3, 'engine and entry points are security definer, volatile, search_path = public, pg_temp', '3 of 3',
         (select count(*)::text || ' of 3' from mine
           where proname in ('delete_account_core', 'admin_delete_account', 'delete_my_account')
             and prosecdef and provolatile = 'v' and proconfig = array['search_path=public, pg_temp']),
         (select count(*) = 3 from mine
           where proname in ('delete_account_core', 'admin_delete_account', 'delete_my_account')
             and prosecdef and provolatile = 'v' and proconfig = array['search_path=public, pg_temp'])

  union all
  select 4, 'both previews are security definer, STABLE, search_path = public, pg_temp', '2 of 2',
         (select count(*)::text || ' of 2' from mine
           where proname in ('admin_preview_account_deletion', 'preview_my_account_deletion')
             and prosecdef and provolatile = 's' and proconfig = array['search_path=public, pg_temp']),
         (select count(*) = 2 from mine
           where proname in ('admin_preview_account_deletion', 'preview_my_account_deletion')
             and prosecdef and provolatile = 's' and proconfig = array['search_path=public, pg_temp'])

  union all
  -- 5. Who can run what: anon and PUBLIC nothing; signed-in users only the four API functions.
  select 5, 'anon and PUBLIC cannot execute any of them', '0',
         (select count(*)::text from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute),
         (select count(*) = 0 from mine where has_function_privilege('anon', oid, 'EXECUTE') or public_can_execute)

  union all
  select 6, 'authenticated can execute the four API functions and NO internal one', 'api 4; internal 0',
         (select coalesce(string_agg(proname, ', ' order by proname), 'none') from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE')),
         (select count(*) = 4 and bool_and(proname in ('admin_delete_account', 'delete_my_account',
                                                       'admin_preview_account_deletion',
                                                       'preview_my_account_deletion')) from mine
           where has_function_privilege('authenticated', oid, 'EXECUTE'))

  union all
  -- 7. Authorization is the server's: the admin route checks the helper AND system_admins; the self
  --    route has no user argument at all.
  select 7, 'the admin entry point and the admin preview check System Admin twice; the self route takes no user', '3',
         (select count(*)::text from mine
           where (proname in ('admin_delete_account', 'admin_preview_account_deletion')
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=%')
              or (proname = 'delete_my_account' and args = '' and src_compact like '%auth.uid()%'
                  and src_compact not like '%p_user_id%')),
         (select count(*) = 3 from mine
           where (proname in ('admin_delete_account', 'admin_preview_account_deletion')
                  and src_compact like '%public.is_system_admin()%'
                  and src_compact like '%notexists(select1frompublic.system_adminssawheresa.user_id=%')
              or (proname = 'delete_my_account' and args = '' and src_compact like '%auth.uid()%'
                  and src_compact not like '%p_user_id%'))

  union all
  -- 8. The previews write nothing and the engine does not touch a setting or a trigger.
  select 8, 'the previews write nothing; the engine makes no HTTP call, disables no trigger, runs no dynamic SQL', '0',
         (select count(*)::text from mine
           where (proname in ('admin_preview_account_deletion', 'preview_my_account_deletion', 'account_deletion_blockers')
                  and src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|record_admin_audit|executeformat|execute'')')
              or (proname = 'delete_account_core'
                  and src_compact ~ '(http_post|http_get|net\.http|session_replication_role|disabletrigger|enabletrigger|altertable|createtable|droptable|set_config|executeformat|execute'')')),
         (select count(*) = 0 from mine
           where (proname in ('admin_preview_account_deletion', 'preview_my_account_deletion', 'account_deletion_blockers')
                  and src_compact ~ '(insertinto|deletefrom|truncate|update(public\.)?[a-z_]+set|record_admin_audit|executeformat|execute'')')
              or (proname = 'delete_account_core'
                  and src_compact ~ '(http_post|http_get|net\.http|session_replication_role|disabletrigger|enabletrigger|altertable|createtable|droptable|set_config|executeformat|execute'')'))

  union all
  -- 9. One transaction: the Auth delete is in the engine, appears exactly once, and is the last write.
  select 9, 'the engine deletes from auth.users exactly once and writes nothing after it', '1; no write after',
         (select ((length(src_compact) - length(replace(src_compact, 'deletefromauth.usersw', ''))) / length('deletefromauth.usersw'))::text
                 || '; ' || case when (select tail from after_auth) ~ '(insertinto|deletefrom|update[a-z_.]+set|perform)' then 'WRITE AFTER' else 'no write after' end
            from core),
         (select ((length(src_compact) - length(replace(src_compact, 'deletefromauth.usersw', ''))) / length('deletefromauth.usersw')) = 1
             and (select tail from after_auth) is not null
             and (select tail from after_auth) !~ '(insertinto|deletefrom|update[a-z_.]+set|perform)'
            from core)

  union all
  -- 10. The merge deletes the source's profile itself, before the Auth user, now that nothing cascades.
  select 10, 'the merge executor deletes the source profile explicitly, before the Auth user', 'profile, then auth',
         (select case when position('deletefrompublic.userswhereid=p_source_user_id;' in src_compact) > 0
                       and position('deletefrompublic.userswhereid=p_source_user_id;' in src_compact)
                           < position('deletefromauth.userswhereid=p_source_user_id;' in src_compact)
                      then 'profile, then auth' else 'WRONG ORDER OR MISSING' end
            from merge_fn),
         (select position('deletefrompublic.userswhereid=p_source_user_id;' in src_compact) > 0
             and position('deletefrompublic.userswhereid=p_source_user_id;' in src_compact)
                 < position('deletefromauth.userswhereid=p_source_user_id;' in src_compact)
             and src_compact like '%pg_advisory_xact_lock(hashtextextended(''goplay.account_lifecycle'',0))%'
             and src_compact like '%u.deleted_atisnull%'
            from merge_fn)

  union all
  -- 11. The bodies are exactly the ones 0102 defines (hashes).
  select 11, 'the engine, entry points, previews, helpers and the merge executor are exactly the bodies 0102 defines (hashes)', '11 of 11',
         ((select count(*) from mine where
            (proname = 'delete_account_core'            and src_md5 = 'd6b48aacf7d46d97171315879cd22fbf')
         or (proname = 'admin_delete_account'           and src_md5 = 'e4195abc5c4316ed8830f746e2368da4')
         or (proname = 'delete_my_account'              and src_md5 = '1a30e15427ea2d563995c3815e6a048d')
         or (proname = 'admin_preview_account_deletion' and src_md5 = '85019d7b52192a3b773c96bb1b6fa52c')
         or (proname = 'preview_my_account_deletion'    and src_md5 = 'f9d57a36fd6acb61bde46c193c215492')
         or (proname = 'account_deletion_blockers'      and src_md5 = '650c2dc71834aeda4b6d52e7070b9f19')
         or (proname = 'account_football_evidence'      and src_md5 = 'cf97ab689c514498322253c8281a961b')
         or (proname = 'anonymize_user_profile'         and src_md5 = 'd83ce5f5557120aa45d6cba83b724059')
         or (proname = 'handle_auth_user_deleted'       and src_md5 = 'e49d5bd8ded588d742323e881a43720a')
         or (proname = 'deleted_player_name'            and src_md5 = 'fad9cf195517c9fb4d3139017db70658'))
         + (select count(*) from found where proname = 'admin_merge_accounts' and src_md5 = '9915f182d8e9bbcc34da688f1610aac4'))::text || ' of 11',
         (select count(*) from mine where
            (proname = 'delete_account_core'            and src_md5 = 'd6b48aacf7d46d97171315879cd22fbf')
         or (proname = 'admin_delete_account'           and src_md5 = 'e4195abc5c4316ed8830f746e2368da4')
         or (proname = 'delete_my_account'              and src_md5 = '1a30e15427ea2d563995c3815e6a048d')
         or (proname = 'admin_preview_account_deletion' and src_md5 = '85019d7b52192a3b773c96bb1b6fa52c')
         or (proname = 'preview_my_account_deletion'    and src_md5 = 'f9d57a36fd6acb61bde46c193c215492')
         or (proname = 'account_deletion_blockers'      and src_md5 = '650c2dc71834aeda4b6d52e7070b9f19')
         or (proname = 'account_football_evidence'      and src_md5 = 'cf97ab689c514498322253c8281a961b')
         or (proname = 'anonymize_user_profile'         and src_md5 = 'd83ce5f5557120aa45d6cba83b724059')
         or (proname = 'handle_auth_user_deleted'       and src_md5 = 'e49d5bd8ded588d742323e881a43720a')
         or (proname = 'deleted_player_name'            and src_md5 = 'fad9cf195517c9fb4d3139017db70658'))
         + (select count(*) from found where proname = 'admin_merge_accounts' and src_md5 = '9915f182d8e9bbcc34da688f1610aac4') = 11

  union all
  -- 12. The 0101 functions this migration relies on are as 0101 left them.
  select 12, 'the 0101 helpers and the merge preview are unchanged (hashes)', '7 of 7',
         (select count(*)::text || ' of 7' from found where
            (proname = 'admin_preview_account_merge'    and src_md5 = '54bd260bb7d073208667a2fc7c656876')
         or (proname = 'merge_skips_lifecycle'          and src_md5 = '42282473e1813a112c13d3f840b0f6b5')
         or (proname = 'merge_rating_scope_excludes'    and src_md5 = '46a3e57a19c56f20e3b02df9829b693d')
         or (proname = 'merge_shared_matches'           and src_md5 = '2c29a044403fbc49f99d58dfb24cdc85')
         or (proname = 'merge_participation_blockers'   and src_md5 = 'a863bf56041fc6f3be7069e0a5700d79')
         or (proname = 'merge_invariants'               and src_md5 = '91d2aee4c54bae6f5ad112e6aa7d0597')
         or (proname = 'merge_source_stored_files'      and src_md5 = '5ad5a3749c12802f8312cc92bd359df9')),
         (select count(*) = 7 from found where
            (proname = 'admin_preview_account_merge'    and src_md5 = '54bd260bb7d073208667a2fc7c656876')
         or (proname = 'merge_skips_lifecycle'          and src_md5 = '42282473e1813a112c13d3f840b0f6b5')
         or (proname = 'merge_rating_scope_excludes'    and src_md5 = '46a3e57a19c56f20e3b02df9829b693d')
         or (proname = 'merge_shared_matches'           and src_md5 = '2c29a044403fbc49f99d58dfb24cdc85')
         or (proname = 'merge_participation_blockers'   and src_md5 = 'a863bf56041fc6f3be7069e0a5700d79')
         or (proname = 'merge_invariants'               and src_md5 = '91d2aee4c54bae6f5ad112e6aa7d0597')
         or (proname = 'merge_source_stored_files'      and src_md5 = '5ad5a3749c12802f8312cc92bd359df9'))

  union all
  -- 13. THE structural change, and only it: users_id_fkey is gone, deleted_at exists, and every other
  --     foreign key to public.users is exactly the 0101 list (none dropped, none added).
  select 13, 'users_id_fkey is gone, users.deleted_at exists, and the foreign keys to users are exactly the known 16', 'gone; exists; 16 as before',
         (select (not exists (select 1 from pg_constraint where conname = 'users_id_fkey' and conrelid = 'public.users'::regclass))::text
                 || '; ' || exists (select 1 from information_schema.columns
                                     where table_schema = 'public' and table_name = 'users' and column_name = 'deleted_at')::text
                 || '; ' || (select listing from known_fks)),
         (not exists (select 1 from pg_constraint where conname = 'users_id_fkey' and conrelid = 'public.users'::regclass))
         and exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'users' and column_name = 'deleted_at')
         and (select listing from known_fks) =
             'communities.owner_id, community_members.user_id, community_statistics.user_id, match_goals.user_id, match_professional_guests.created_by, match_registrations.user_id, match_results.mvp_user_id, match_results.recorded_by, match_team_assignments.user_id, matches.created_by, notification_push_preferences.user_id, notification_push_tokens.user_id, notifications.user_id, player_statistics.user_id, rating_history.user_id, system_admins.user_id'

  union all
  -- 14. The trigger that anonymises a profile whose Auth user is deleted any other way.
  select 14, 'one enabled AFTER DELETE trigger on auth.users anonymises the profile', '1',
         (select count(*)::text from pg_trigger t
           where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal and t.tgenabled = 'O'
             and t.tgname = 'auth_user_deleted_anonymize_profile'),
         (select count(*) = 1 from pg_trigger t
           where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal and t.tgenabled = 'O'
             and t.tgname = 'auth_user_deleted_anonymize_profile'
             and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 8) = 8)

  union all
  -- 15. No trigger of the football lifecycle is disabled.
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
  -- 16. The audit action list: the six that were there and the one more.
  select 16, 'the audit action list holds the six earlier actions and USER_ACCOUNT_DELETED', '7 actions',
         (select (regexp_matches(pg_get_constraintdef(oid), 'ARRAY\[(.*)\]'))[1]
            from pg_constraint where conname = 'admin_audit_log_action_check'),
         (select pg_get_constraintdef(oid) ~ 'USER_ACCOUNT_DELETED'
             and pg_get_constraintdef(oid) ~ 'USER_ACCOUNTS_MERGED'
             and pg_get_constraintdef(oid) ~ 'USER_PROFILE_UPDATED'
             and pg_get_constraintdef(oid) ~ 'USER_SUSPENDED'
             and pg_get_constraintdef(oid) ~ 'USER_REACTIVATED'
             and pg_get_constraintdef(oid) ~ 'COMMUNITY_SUSPENDED'
             and pg_get_constraintdef(oid) ~ 'COMMUNITY_REACTIVATED'
            from pg_constraint where conname = 'admin_audit_log_action_check')

  union all
  -- 17. DATA, read only: a live profile always has an Auth user (the guarantee the dropped constraint gave).
  select 17, 'every live profile has an Auth user', '0 without',
         (select count(*)::text || ' without' from public.users u
           where (to_jsonb(u)->>'deleted_at') is null and not exists (select 1 from auth.users au where au.id = u.id)),
         (select count(*) = 0 from public.users u
           where (to_jsonb(u)->>'deleted_at') is null and not exists (select 1 from auth.users au where au.id = u.id))

  union all
  -- 18. DATA, read only: a deleted account has no Auth user, no profile data and is not a suspension.
  select 18, 'every deleted account has no Auth user and no identifying data', '0 violations',
         (select count(*)::text || ' violations' from public.users u
           where (to_jsonb(u)->>'deleted_at') is not null
             and (exists (select 1 from auth.users au where au.id = u.id)
                  or u.full_name <> 'لاعب محذوف / Deleted Player' or u.phone <> ''
                  or u.date_of_birth is not null or u.avatar_path is not null
                  or u.default_wilayat_code is not null or u.is_active
                  or u.suspended_at is not null or u.suspension_reason is not null)),
         (select count(*) = 0 from public.users u
           where (to_jsonb(u)->>'deleted_at') is not null
             and (exists (select 1 from auth.users au where au.id = u.id)
                  or u.full_name <> 'لاعب محذوف / Deleted Player' or u.phone <> ''
                  or u.date_of_birth is not null or u.avatar_path is not null
                  or u.default_wilayat_code is not null or u.is_active
                  or u.suspended_at is not null or u.suspension_reason is not null))
) c
order by n, check_name;
