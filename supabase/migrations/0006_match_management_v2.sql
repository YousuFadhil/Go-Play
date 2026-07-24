-- V2: match management, final business rules.
--
-- Lifecycle:  open -> full (registrations reach max_registration) -> back to
--             open when a slot frees; completed automatically once the
--             scheduled end time passes. No draft/cancelled/postponed.
-- Capacity:   starting_players (first N are starting) and max_registration
--             (registration closes there); max_registration >= starting_players.
-- Deletion:   organizer may delete any match that is not completed; all
--             registered players are notified first.

-- Drop anything from an earlier iteration of this migration.
drop function if exists public.cancel_match(uuid);
drop function if exists public.postpone_match(uuid);
drop function if exists public.recompute_match_fill(uuid);
drop function if exists public.update_match(uuid, text, text, timestamptz, timestamptz, int, text);
drop function if exists public.update_match(uuid, text, text, timestamptz, timestamptz, int, int, text);

-- 0) Global application settings ----------------------------------------------
-- Reserve capacity is a single global value; maximum registration is always
-- derived as starting_players + reserve_players.
create table if not exists public.app_settings (
  id boolean primary key default true check (id),
  reserve_players int not null default 6
    check (reserve_players between 0 and 30)
);

insert into public.app_settings (id) values (true)
on conflict (id) do nothing;

alter table public.app_settings enable row level security;
drop policy if exists "app_settings_select_all" on public.app_settings;
create policy "app_settings_select_all"
  on public.app_settings for select to authenticated using (true);
-- No write policy: the value is changed by an administrator via SQL.

-- 1) Optional match fields -----------------------------------------------------
alter table public.matches
  add column if not exists title text;
alter table public.matches
  add column if not exists description text;
alter table public.matches drop constraint if exists matches_title_check;
alter table public.matches drop constraint if exists matches_description_check;
alter table public.matches add constraint matches_title_check
  check (title is null or char_length(trim(title)) between 2 and 60);
alter table public.matches add constraint matches_description_check
  check (description is null or char_length(description) <= 300);

-- 2) Capacity model: starting_players + max_registration ----------------------
alter table public.matches add column if not exists starting_players int;
alter table public.matches add column if not exists max_registration int;

-- Backfill from the old single limit, then retire it.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'matches'
      and column_name = 'max_players'
  ) then
    update public.matches
    set starting_players = coalesce(starting_players, max_players),
        max_registration = coalesce(max_registration, max_players);
  end if;
end $$;

update public.matches
set starting_players = coalesce(starting_players, 10),
    max_registration = coalesce(max_registration, 10)
where starting_players is null or max_registration is null;

alter table public.matches alter column starting_players set not null;
alter table public.matches alter column max_registration set not null;

alter table public.matches drop constraint if exists matches_starting_players_check;
alter table public.matches drop constraint if exists matches_max_registration_check;
alter table public.matches drop constraint if exists matches_capacity_check;
alter table public.matches add constraint matches_starting_players_check
  check (starting_players between 2 and 30);
alter table public.matches add constraint matches_max_registration_check
  check (max_registration between 2 and 60);
alter table public.matches add constraint matches_capacity_check
  check (max_registration >= starting_players);

alter table public.matches drop column if exists max_players;

-- max_registration is derived, never supplied by the organizer: it is set on
-- insert and whenever starting_players changes.
create or replace function public.set_match_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reserve int;
begin
  if tg_op = 'INSERT'
     or new.starting_players is distinct from old.starting_players then
    select reserve_players into v_reserve from app_settings limit 1;
    new.max_registration := new.starting_players + coalesce(v_reserve, 6);
  end if;
  return new;
end;
$$;

drop trigger if exists matches_set_capacity on public.matches;
create trigger matches_set_capacity
  before insert or update on public.matches
  for each row execute function public.set_match_capacity();

-- Align existing rows with the derived rule.
update public.matches m
set max_registration = m.starting_players
    + (select reserve_players from public.app_settings limit 1);

-- 3) Status model: open | full | completed ------------------------------------
-- Map any legacy value onto the new set before tightening the constraint.
alter table public.matches drop constraint if exists matches_status_check;
update public.matches set status = 'completed' where status = 'cancelled';
update public.matches set status = 'open' where status in ('draft', 'postponed');
update public.matches set status = 'completed'
  where end_at <= now() and status <> 'completed';
alter table public.matches add constraint matches_status_check
  check (status in ('open', 'full', 'completed'));

-- 4) Notifications -------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  -- Kept when the match is deleted, so the "match deleted" notice survives.
  match_id uuid references public.matches (id) on delete set null,
  type text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

-- Guarantee the match reference never cascade-deletes notifications, so the
-- "match deleted" notice outlives the match (idempotent).
alter table public.notifications
  drop constraint if exists notifications_match_id_fkey;
alter table public.notifications
  add constraint notifications_match_id_fkey
  foreign key (match_id) references public.matches (id) on delete set null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
drop policy if exists "notifications_update_own" on public.notifications;
drop policy if exists "notifications_delete_own" on public.notifications;

create policy "notifications_select_own"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notifications_delete_own"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid());
-- inserts happen only through the SECURITY DEFINER RPCs below.

create or replace function public.create_notification(
  p_user_id uuid, p_match_id uuid, p_type text, p_message text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notifications (user_id, match_id, type, message)
  values (p_user_id, p_match_id, p_type, p_message);
$$;

-- 5) Automatic status: completed by time, else full/open by registrations ------
create or replace function public.recompute_match_status(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
begin
  select * into v_match from matches where id = p_match_id;
  if not found then return; end if;

  if v_match.end_at <= now() then
    update matches set status = 'completed'
    where id = p_match_id and status <> 'completed';
    return;
  end if;

  select count(*) into v_total
  from match_registrations where match_id = p_match_id;

  update matches
  set status = case when v_total >= v_match.max_registration
                    then 'full' else 'open' end
  where id = p_match_id;
end;
$$;

-- Re-sorts the roster so the first starting_players registrations (by
-- registration order) are starting players and the rest are reserve.
-- Notifies anyone whose place changed.
create or replace function public.rebalance_roster(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_starting int;
  r record;
begin
  select starting_players into v_starting from matches where id = p_match_id;

  for r in
    select mr.id, mr.user_id, mr.status,
           case when row_number() over (order by mr.registration_order)
                     <= v_starting
                then 'confirmed' else 'reserve' end as desired
    from match_registrations mr
    where mr.match_id = p_match_id
  loop
    if r.status <> r.desired then
      update match_registrations set status = r.desired where id = r.id;
      if r.desired = 'reserve' then
        perform create_notification(r.user_id, p_match_id, 'moved_to_reserve',
            'تم نقلك إلى قائمة الاحتياط بسبب تعديل عدد اللاعبين.');
      else
        perform create_notification(r.user_id, p_match_id, 'promoted',
            'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
      end if;
    end if;
  end loop;
end;
$$;

-- 6) Registration --------------------------------------------------------------
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_confirmed int;
  v_status text;
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  perform 1 from users where id = auth.uid() for update;

  -- Completed (end time passed) matches are read-only.
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  -- Registration closes at the scheduled start time; the match is then
  -- locked until it completes.
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  if not is_group_member(v_match.group_id, auth.uid()) then
    raise exception 'NOT_GROUP_MEMBER';
  end if;

  if exists (
    select 1 from match_registrations
    where match_id = p_match_id and user_id = auth.uid()
  ) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  -- Registration closes at max_registration.
  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  -- No overlapping registration in another live match.
  if exists (
    select 1
    from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = auth.uid()
      and m.status in ('open', 'full')
      and m.end_at > now()
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  select count(*) into v_confirmed
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  v_status := case
    when v_confirmed < v_match.starting_players then 'confirmed'
    else 'reserve'
  end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, auth.uid(), v_status, v_order);

  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

-- 7) Withdrawal: promote the first reserve and notify them ---------------------
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
  v_promoted uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  -- No withdrawals once the match has started.
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (
      select id from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    )
    returning user_id into v_promoted;

    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
    end if;
  end if;

  perform recompute_match_status(p_match_id);
end;
$$;

-- 8) Organizer: edit match -----------------------------------------------------
create or replace function public.update_match(
  p_match_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players int,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  -- Locked from the scheduled start time onwards.
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_starting_players < 2 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  -- Maximum registration is derived; make sure the new capacity still fits
  -- everyone already registered.
  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if p_starting_players
     + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;

  update matches set
    title = case when p_title is null or trim(p_title) = ''
                 then null else trim(p_title) end,
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    -- max_registration is recomputed by the matches_set_capacity trigger.
    description = case when p_description is null or trim(p_description) = ''
                       then null else trim(p_description) end
  where id = p_match_id;

  -- Re-sort starting/reserve for the new starting_players and notify movers.
  perform rebalance_roster(p_match_id);
  perform recompute_match_status(p_match_id);

  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;
end;
$$;

-- 9) Organizer: remove a player (notifies removed + promoted) ------------------
create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
  v_promoted uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  -- No organizer roster changes once the match has started.
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (
      select id from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    )
    returning user_id into v_promoted;

    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
    end if;
  end if;

  perform recompute_match_status(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed',
      'قام المنظم بإزالتك من المباراة.');
end;
$$;

-- 10) Organizer: delete a match ------------------------------------------------
-- Deletion is deliberately time-independent: a match may be deleted whether or
-- not it has started or ended. It becomes protected only once the match is
-- historical (recorded result, statistics, ratings, best player, standings or
-- tournament history). None of those exist at this MVP stage, so no such guard
-- is added yet -- add it here when those features land.
create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;

  -- Notify everyone first; notifications survive the match (match_id is
  -- set to null by the foreign key).
  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      'تم حذف المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;

  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

-- Grants -----------------------------------------------------------------------
revoke execute on function public.create_notification(uuid, uuid, text, text)
  from anon, authenticated, public;
revoke execute on function public.recompute_match_status(uuid)
  from anon, authenticated, public;
revoke execute on function public.rebalance_roster(uuid)
  from anon, authenticated, public;
revoke execute on function public.set_match_capacity()
  from anon, authenticated, public;
revoke execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text)
  from anon, public;
revoke execute on function public.remove_player(uuid, uuid) from anon, public;
revoke execute on function public.delete_match(uuid) from anon, public;
grant execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text)
  to authenticated;
grant execute on function public.remove_player(uuid, uuid) to authenticated;
grant execute on function public.delete_match(uuid) to authenticated;
