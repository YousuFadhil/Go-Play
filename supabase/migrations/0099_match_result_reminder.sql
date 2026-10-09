-- 0099: one medium-priority reminder to the community owner and admins
-- when a non-historical, future-at-activation match has no saved result
-- 30 minutes after its end. Runs in PostgreSQL, not in the Flutter client.
--
-- This migration schedules a live minute-by-minute job when APPLIED.
-- Do not apply it to production before offline validation and release approval.
-- pg_cron is available but not installed on production as of 2026-10-09.

create table if not exists public.match_result_reminder_activation (
  id boolean primary key default true check (id),
  activated_at timestamptz not null default clock_timestamp()
);
alter table public.match_result_reminder_activation enable row level security;
revoke all on public.match_result_reminder_activation
  from public, anon, authenticated, service_role;

-- The activation watermark prevents any backfill of matches that ended
-- before the feature was enabled, without excluding already-planned FUTURE
-- matches. Reapplying the migration never resets that watermark.
insert into public.match_result_reminder_activation (id, activated_at)
values (true, clock_timestamp())
on conflict (id) do nothing;

-- Once per MATCH, not once per run. In particular a newly promoted admin
-- must not receive an old reminder on a later cron run. Notifications may be
-- deleted by their owner, but that must not cause a second reminder.
create table if not exists public.match_result_reminder_dispatches (
  match_id uuid primary key references public.matches (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.match_result_reminder_dispatches enable row level security;
revoke all on public.match_result_reminder_dispatches
  from public, anon, authenticated, service_role;

insert into public.notification_types (type, priority, category, push_title)
values (
  'match_result_reminder',
  'medium',
  'match',
  'تذكير بتسجيل نتيجة المباراة'
)
on conflict (type) do update
  set priority = excluded.priority,
      category = excluded.category,
      push_title = excluded.push_title;

-- Called exclusively by a database cron job owned by postgres.
-- SECURITY INVOKER deliberately avoids adding another exposed definer RPC.
create or replace function public.emit_missing_match_result_reminders_v1()
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_match record;
  v_inserted integer;
  v_total integer := 0;
begin
  -- record_match_result locks the same match row before writing a result.
  -- SKIP LOCKED avoids a reminder racing a result currently being saved.
  for v_match in
    select m.id, m.community_id
    from public.matches m
    join public.communities c on c.id = m.community_id
    cross join public.match_result_reminder_activation a
    where a.id = true
      and c.is_active = true
      and m.is_historical = false
      and m.end_at > a.activated_at
      and m.end_at + interval '30 minutes' <= now()
      and not exists (
        select 1 from public.match_results r where r.match_id = m.id
      )
      and not exists (
        select 1 from public.match_result_reminder_dispatches d
        where d.match_id = m.id
      )
    order by m.end_at, m.id
    for update of m skip locked
  loop
    -- A single atomic statement owns the claim AND the notification fanout.
    -- Failure inserting any notice rolls back its claim; retries are safe.
    with recipients as materialized (
      select u.id as user_id
      from public.users u
      join (
        select c.owner_id as user_id
        from public.communities c where c.id = v_match.community_id
        union
        select cm.user_id
        from public.community_members cm
        where cm.community_id = v_match.community_id
          and cm.role = 'admin'
      ) managers on managers.user_id = u.id
      where u.is_active = true
    ),
    claimed as (
      insert into public.match_result_reminder_dispatches (match_id)
      select v_match.id
      where exists (select 1 from recipients)
      on conflict (match_id) do nothing
      returning match_id
    )
    insert into public.notifications (user_id, match_id, type, message)
    select r.user_id, cl.match_id,
           'match_result_reminder',
           'انتهت المباراة. يرجى تسجيل النتيجة.'
    from claimed cl
    cross join recipients r;

    get diagnostics v_inserted = row_count;
    v_total := v_total + v_inserted;
  end loop;

  return v_total;
end;
$function$;

-- No web or anonymous caller, including service_role, can invoke this job.
-- The scheduled command runs as its postgres owner.
revoke all on function public.emit_missing_match_result_reminders_v1()
  from public, anon, authenticated, service_role;

-- Supabase Cron is approved for this feature; schedule runs every minute.
-- Named schedules are upserted by pg_cron rather than duplicated.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule(
  'go-play-missing-match-result-v1',
  '* * * * *',
  'select public.emit_missing_match_result_reminders_v1()'
);
