-- == tool/0107_lineup_line_order_verify.sql ==
-- Post-apply checks for migration 0107. READ ONLY: one SELECT, no write, no
-- impersonation. Run it after the migration has been applied and read the `ok`
-- column: every row should be true.
--
-- Behaviour (the order written, refusals, the reset, participation evidence left
-- alone) was shown in a rolled-back dry run on the live database before the
-- apply. This checks the resulting state: the column, the trigger, the
-- functions, their search paths and grants, and the two read models.
--
-- 0107 redefines `replace_match_lineup` (0071) and
-- `advance_match_participation_revision` (0101); a verify script of those
-- migrations that hashes their bodies now answers false by design.

with
fn as (
  select p.proname, p.prosecdef, p.proconfig,
         pg_get_function_identity_arguments(p.oid) as args, p.oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('set_match_lineup_line_order', 'reset_lineup_line_order',
                      'replace_match_lineup', 'advance_match_participation_revision',
                      'public_match_lineup')
)
select 'migration recorded' as check,
       exists (select 1 from supabase_migrations.schema_migrations
               where name = '0107_lineup_line_order') as ok
union all
select 'line_order column (smallint, nullable)',
       exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'match_team_assignments'
                 and column_name = 'line_order' and data_type = 'smallint'
                 and is_nullable = 'YES')
union all
select 'reset trigger present',
       exists (select 1 from pg_trigger
               where tgrelid = 'public.match_team_assignments'::regclass
                 and tgname = 'match_team_assignments_reset_line_order'
                 and not tgisinternal)
union all
select 'set_match_lineup_line_order signature + definer + search path',
       exists (select 1 from fn where proname = 'set_match_lineup_line_order'
               and args = 'p_match_id uuid, p_team text, p_assigned_position text, p_participant_ids uuid[]'
               and prosecdef and proconfig @> array['search_path=public, pg_temp'])
union all
select 'set_match_lineup_line_order: authenticated yes, anon no',
       has_function_privilege('authenticated',
         'public.set_match_lineup_line_order(uuid,text,text,uuid[])', 'execute')
       and not has_function_privilege('anon',
         'public.set_match_lineup_line_order(uuid,text,text,uuid[])', 'execute')
union all
select 'reset_lineup_line_order not executable by clients',
       not has_function_privilege('authenticated', 'public.reset_lineup_line_order()', 'execute')
       and not has_function_privilege('anon', 'public.reset_lineup_line_order()', 'execute')
union all
select 'replace_match_lineup carries line_order, grants unchanged',
       exists (select 1 from fn where proname = 'replace_match_lineup'
               and pg_get_functiondef(oid) like '%v_previous_order%'
               and proconfig @> array['search_path=public, pg_temp'])
       and has_function_privilege('authenticated',
         'public.replace_match_lineup(uuid,jsonb,boolean,boolean)', 'execute')
       and not has_function_privilege('anon',
         'public.replace_match_lineup(uuid,jsonb,boolean,boolean)', 'execute')
union all
select 'participation trigger skips order-only updates',
       exists (select 1 from fn where proname = 'advance_match_participation_revision'
               and pg_get_functiondef(oid) like '%''line_order''%')
union all
select 'v_football_match_lineup returns line_order',
       exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'v_football_match_lineup'
                 and column_name = 'line_order')
union all
select 'public_match_lineup returns line_order, anon + authenticated',
       exists (select 1 from fn where proname = 'public_match_lineup'
               and pg_get_function_result(oid) like '%line_order smallint%')
       and has_function_privilege('anon', 'public.public_match_lineup(uuid)', 'execute')
       and has_function_privilege('authenticated', 'public.public_match_lineup(uuid)', 'execute');
