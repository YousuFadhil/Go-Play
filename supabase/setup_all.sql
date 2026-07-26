-- Go Play: combined setup script (migrations 0001-0009, in order).
-- Generated convenience copy - the individual files in migrations/ are the source of truth.

-- ============ migrations/0001_users.sql ============
-- Sprint 1: Authentication
-- Creates the public.users profile table linked to Supabase Auth,
-- per Docs/07-Database-Design.md (MVP scope per Docs/01-PRD.md).
-- Identity is email+password (see Docs/10-Design-Decisions.md DD-02);
-- phone is a required contact field, not a login identity.

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text not null,
  full_name text not null,
  primary_position text not null
    check (primary_position in ('GK', 'DEF', 'MID', 'FWD')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index users_phone_idx on public.users (phone);

-- Keep updated_at current on every update.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger users_set_updated_at
  before update on public.users
  for each row
  execute function public.set_updated_at();

-- Create the profile row automatically when a user signs up.
-- full_name, primary_position and phone arrive via auth signUp metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, phone, full_name, primary_position)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'primary_position', 'MID')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- Row Level Security
alter table public.users enable row level security;

-- Any signed-in user can see active profiles (needed for group member
-- lists in Sprint 2).
create policy "authenticated_select_active_users"
  on public.users
  for select
  to authenticated
  using (is_active);

-- Users can update only their own profile.
create policy "users_update_own_profile"
  on public.users
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- No insert/delete policies: inserts happen via the trigger above and
-- deletion is soft (is_active) per the database design.

-- ============ migrations/0002_groups.sql ============
-- Sprint 2: Groups
-- Tables: groups, group_members. Writes go through RPC functions so that
-- multi-step operations are atomic without a custom backend.

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users (id),
  name text not null check (char_length(trim(name)) between 2 and 50),
  description text check (char_length(description) <= 200),
  is_private boolean not null default false,
  join_code text not null unique
    default upper(substr(md5(random()::text), 1, 6)),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index groups_owner_id_idx on public.groups (owner_id);

create trigger groups_set_updated_at
  before update on public.groups
  for each row
  execute function public.set_updated_at();

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create index group_members_user_id_idx on public.group_members (user_id);
create index group_members_group_id_idx on public.group_members (group_id);

-- Membership check used inside RLS policies. SECURITY DEFINER avoids
-- recursive policy evaluation between groups and group_members.
create or replace function public.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from group_members
    where group_id = p_group_id
      and user_id = p_user_id
  );
$$;

-- Creates a group and its owner membership atomically. Returns group id.
create or replace function public.create_group(
  p_name text,
  p_description text,
  p_is_private boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  insert into groups (owner_id, name, description, is_private)
  values (auth.uid(), trim(p_name), p_description, p_is_private)
  returning id into v_group_id;

  insert into group_members (group_id, user_id, role)
  values (v_group_id, auth.uid(), 'owner');

  return v_group_id;
end;
$$;

-- Joins the calling user to a group by join code. Returns group id.
create or replace function public.join_group_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select id into v_group_id
  from groups
  where join_code = upper(trim(p_code))
    and is_active;

  if v_group_id is null then
    raise exception 'GROUP_NOT_FOUND';
  end if;

  if is_group_member(v_group_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into group_members (group_id, user_id, role)
  values (v_group_id, auth.uid(), 'member');

  return v_group_id;
end;
$$;

revoke execute on function public.create_group from anon, public;
revoke execute on function public.join_group_by_code from anon, public;
grant execute on function public.create_group to authenticated;
grant execute on function public.join_group_by_code to authenticated;

-- Row Level Security
alter table public.groups enable row level security;
alter table public.group_members enable row level security;

-- Public groups are visible to any signed-in user; private groups only to
-- their members (join happens via the RPC, which bypasses RLS safely).
create policy "groups_select_visible"
  on public.groups
  for select
  to authenticated
  using (
    is_active
    and (
      not is_private
      or owner_id = auth.uid()
      or public.is_group_member(id, auth.uid())
    )
  );

-- Only the owner can update group settings.
create policy "groups_update_owner"
  on public.groups
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Members see the member list of their own groups.
create policy "group_members_select_same_group"
  on public.group_members
  for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- A regular member can leave a group. Owners cannot leave their own group
-- (ownership transfer is out of MVP scope).
create policy "group_members_delete_self"
  on public.group_members
  for delete
  to authenticated
  using (user_id = auth.uid() and role = 'member');

-- No insert policies: inserts happen only via the RPC functions above.

-- ============ migrations/0003_matches.sql ============
-- Sprint 3: Matches
-- A match belongs to a group. Location is free text for the MVP (no fields
-- table; see sprint report). Registration arrives in Sprint 4.

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_by uuid not null references public.users (id),
  location text not null check (char_length(trim(location)) between 2 and 100),
  start_at timestamptz not null,
  end_at timestamptz not null,
  max_players int not null check (max_players between 2 and 30),
  status text not null default 'open'
    check (status in ('open', 'cancelled', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);

create index matches_group_id_start_at_idx
  on public.matches (group_id, start_at);
create index matches_status_idx on public.matches (status);

create trigger matches_set_updated_at
  before update on public.matches
  for each row
  execute function public.set_updated_at();

-- Row Level Security
alter table public.matches enable row level security;

-- Matches are visible to members of the match's group.
create policy "matches_select_group_members"
  on public.matches
  for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- Any group member can create a match in their group; the creator column
-- must be the caller.
create policy "matches_insert_group_members"
  on public.matches
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_group_member(group_id, auth.uid())
  );

-- Only the creator manages the match (cancel / edit).
create policy "matches_update_creator"
  on public.matches
  for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

-- ============ migrations/0004_match_registrations.sql ============
-- Sprint 4: Match Registration & Reserve queue
-- All writes go through RPCs that lock the match row (FOR UPDATE), making
-- seat allocation, queue order, overlap checks and promotion race-safe.
-- Lock order is always: match row first, then user row.

create table public.match_registrations (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  status text not null check (status in ('confirmed', 'reserve')),
  registration_order int not null,
  created_at timestamptz not null default now(),
  unique (match_id, user_id),
  unique (match_id, registration_order)
);

create index match_registrations_queue_idx
  on public.match_registrations (match_id, status, registration_order);
create index match_registrations_user_id_idx
  on public.match_registrations (user_id);

-- Visibility helper: is the user a member of the match's group?
create or replace function public.is_match_group_member(
  p_match_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from matches m
    join group_members gm on gm.group_id = m.group_id
    where m.id = p_match_id
      and gm.user_id = p_user_id
  );
$$;

-- Registers the caller. Returns 'confirmed' or 'reserve'.
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed_count int;
  v_status text;
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Serializes all registration activity for this match.
  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  -- Serializes this user's registrations across matches so the overlap
  -- check cannot race with itself.
  perform 1 from users where id = auth.uid() for update;

  if v_match.status <> 'open' or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
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

  -- Overlap rule: no registration (confirmed OR reserve) in another open
  -- match whose time range intersects this one. Reserves count because
  -- they can be promoted at any moment.
  if exists (
    select 1
    from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = auth.uid()
      and m.status = 'open'
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  select count(*) into v_confirmed_count
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  v_status := case
    when v_confirmed_count < v_match.max_players then 'confirmed'
    else 'reserve'
  end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations
  where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, auth.uid(), v_status, v_order);

  return v_status;
end;
$$;

-- Withdraws the caller. If a confirmed player leaves, the first reserve
-- (lowest registration_order) is promoted in the same transaction.
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  if v_match.status <> 'open' or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  -- Withdrawal deletes the row (allows re-registration; no MVP feature
  -- consumes withdrawal history). See Docs/10-Design-Decisions.md (DD-01)
  -- before changing this to a soft-delete.
  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations
    set status = 'confirmed'
    where id = (
      select id
      from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    );
  end if;
end;
$$;

revoke execute on function public.register_for_match from anon, public;
revoke execute on function public.withdraw_from_match from anon, public;
grant execute on function public.register_for_match to authenticated;
grant execute on function public.withdraw_from_match to authenticated;

-- Row Level Security
alter table public.match_registrations enable row level security;

-- The roster is visible to members of the match's group.
create policy "match_registrations_select_group_members"
  on public.match_registrations
  for select
  to authenticated
  using (public.is_match_group_member(match_id, auth.uid()));

-- No insert/update/delete policies: all writes go through the RPCs above.

-- ============ migrations/0005_security_hardening.sql ============
-- Security hardening (from Supabase security advisor):
-- 1. Pin search_path on the trigger helper.
alter function public.set_updated_at() set search_path = public;

-- 2. handle_new_user is a trigger-only function; it must not be callable
--    through the API by any role.
revoke execute on function public.handle_new_user()
  from anon, authenticated, public;

-- 3. Membership helpers: needed by RLS policy evaluation for signed-in
--    users, but anon has no policies referencing them and should not be
--    able to probe membership.
revoke execute on function public.is_group_member(uuid, uuid)
  from anon, public;
revoke execute on function public.is_match_group_member(uuid, uuid)
  from anon, public;
grant execute on function public.is_group_member(uuid, uuid)
  to authenticated;
grant execute on function public.is_match_group_member(uuid, uuid)
  to authenticated;

-- ============ migrations/0006_match_management_v2.sql ============
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


-- ============ migrations/0007_community_rename.sql ============
-- Phase 2 (AMS v1.2): rename the aggregate to Community.
--
-- groups        -> communities
-- group_members -> community_members
-- *.group_id    -> *.community_id
-- role values   -> owner | admin | player   (the stored 'member' becomes
--                  'player'; 'admin' is accepted but not yet granted)
--
-- Behaviour is deliberately unchanged: every policy keeps exactly the rule it
-- had, expressed against the new names. Moving authorization onto
-- community_members.role is Phase 3 - which is why the owner_id and
-- created_by predicates below are copied across untouched for now.
--
-- Renames are in place: no table is dropped, no data is copied.

-- 1) Tables and columns -------------------------------------------------------
alter table public.groups rename to communities;
alter table public.group_members rename to community_members;
alter table public.community_members rename column group_id to community_id;
alter table public.matches rename column group_id to community_id;

alter index public.groups_owner_id_idx rename to communities_owner_id_idx;
alter index public.group_members_user_id_idx rename to community_members_user_id_idx;
alter index public.group_members_group_id_idx
  rename to community_members_community_id_idx;
alter index public.matches_group_id_start_at_idx
  rename to matches_community_id_start_at_idx;

alter trigger groups_set_updated_at on public.communities
  rename to communities_set_updated_at;

-- Constraint names were generated by PostgreSQL and are read from the catalog,
-- not guessed. They only ever surface in error messages, but leaving them
-- saying "group" would be misleading. The role CHECK is not renamed here: it
-- is replaced below to widen the allowed values.
alter table public.communities rename constraint groups_pkey to communities_pkey;
alter table public.communities
  rename constraint groups_join_code_key to communities_join_code_key;
alter table public.communities
  rename constraint groups_owner_id_fkey to communities_owner_id_fkey;
alter table public.communities
  rename constraint groups_name_check to communities_name_check;
alter table public.communities
  rename constraint groups_description_check to communities_description_check;

alter table public.community_members
  rename constraint group_members_pkey to community_members_pkey;
alter table public.community_members
  rename constraint group_members_group_id_user_id_key
  to community_members_community_id_user_id_key;
alter table public.community_members
  rename constraint group_members_group_id_fkey
  to community_members_community_id_fkey;
alter table public.community_members
  rename constraint group_members_user_id_fkey to community_members_user_id_fkey;

alter table public.matches
  rename constraint matches_group_id_fkey to matches_community_id_fkey;

-- 2) Role vocabulary ----------------------------------------------------------
-- The delete policy tests the stored value, so it is dropped first and
-- recreated in step 4 with the new value.
drop policy if exists "group_members_delete_self" on public.community_members;

alter table public.community_members
  drop constraint if exists group_members_role_check;
update public.community_members set role = 'player' where role = 'member';
alter table public.community_members
  add constraint community_members_role_check
  check (role in ('owner', 'admin', 'player'));
alter table public.community_members alter column role set default 'player';

-- 3) Membership helpers -------------------------------------------------------
create or replace function public.is_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from community_members
    where community_id = p_community_id
      and user_id = p_user_id
  );
$$;

create or replace function public.is_match_community_member(
  p_match_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from matches m
    join community_members cm on cm.community_id = m.community_id
    where m.id = p_match_id
      and cm.user_id = p_user_id
  );
$$;

revoke execute on function public.is_community_member(uuid, uuid)
  from anon, public;
revoke execute on function public.is_match_community_member(uuid, uuid)
  from anon, public;
grant execute on function public.is_community_member(uuid, uuid)
  to authenticated;
grant execute on function public.is_match_community_member(uuid, uuid)
  to authenticated;

-- 4) Policies: same rules, new names ------------------------------------------
drop policy if exists "groups_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (
    is_active
    and (
      not is_private
      or owner_id = auth.uid()
      or public.is_community_member(id, auth.uid())
    )
  );

drop policy if exists "groups_update_owner" on public.communities;
create policy "communities_update_owner"
  on public.communities
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "group_members_select_same_group" on public.community_members;
create policy "community_members_select_same_community"
  on public.community_members
  for select
  to authenticated
  using (public.is_community_member(community_id, auth.uid()));

create policy "community_members_delete_self"
  on public.community_members
  for delete
  to authenticated
  using (user_id = auth.uid() and role = 'player');

drop policy if exists "matches_select_group_members" on public.matches;
create policy "matches_select_community_members"
  on public.matches
  for select
  to authenticated
  using (public.is_community_member(community_id, auth.uid()));

drop policy if exists "matches_insert_group_members" on public.matches;
create policy "matches_insert_community_members"
  on public.matches
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_community_member(community_id, auth.uid())
  );

drop policy if exists "match_registrations_select_group_members"
  on public.match_registrations;
create policy "match_registrations_select_community_members"
  on public.match_registrations
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

-- 5) Community RPCs -----------------------------------------------------------
create or replace function public.create_community(
  p_name text,
  p_description text,
  p_is_private boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  insert into communities (owner_id, name, description, is_private)
  values (auth.uid(), trim(p_name), p_description, p_is_private)
  returning id into v_community_id;

  insert into community_members (community_id, user_id, role)
  values (v_community_id, auth.uid(), 'owner');

  return v_community_id;
end;
$$;

create or replace function public.join_community_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select id into v_community_id
  from communities
  where join_code = upper(trim(p_code))
    and is_active;

  if v_community_id is null then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  if is_community_member(v_community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (v_community_id, auth.uid(), 'player');

  return v_community_id;
end;
$$;

revoke execute on function public.create_community(text, text, boolean)
  from anon, public;
revoke execute on function public.join_community_by_code(text)
  from anon, public;
grant execute on function public.create_community(text, text, boolean)
  to authenticated;
grant execute on function public.join_community_by_code(text)
  to authenticated;

-- 6) register_for_match: same logic, community names --------------------------
-- Only the membership check and the column reference change; the lock order,
-- overlap rule, seat allocation and capacity rules are untouched.
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

  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  if not is_community_member(v_match.community_id, auth.uid()) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  if exists (
    select 1 from match_registrations
    where match_id = p_match_id and user_id = auth.uid()
  ) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

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

-- 7) Retire the superseded functions ------------------------------------------
-- Nothing references these once the policies and RPCs above are in place.
drop function if exists public.create_group(text, text, boolean);
drop function if exists public.join_group_by_code(text);
drop function if exists public.is_group_member(uuid, uuid);
drop function if exists public.is_match_group_member(uuid, uuid);

-- ============ migrations/0008_role_based_authorization.sql ============
-- Phase 3 (AMS v1.2): authorization moves onto community_members.role.
--
-- has_community_role is the only authorization predicate from here on.
-- owner_id and created_by are never read to grant or deny anything: owner_id
-- is reporting only (PD-15) and created_by is audit metadata (PD-16).
--
-- Approved behaviour changes (PD-05, PD-06, PD-07):
--   * community settings: owner only, now resolved by role instead of owner_id
--   * create / edit / delete a match, and remove a player from one:
--     owner + admin, instead of whoever created the match
--
-- Roles are cumulative (PD-01): owner >= admin >= player.

-- 1) The authorization primitive ----------------------------------------------
create or replace function public.has_community_role(
  p_community_id uuid,
  p_user_id uuid,
  p_min_role text
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from community_members cm
    where cm.community_id = p_community_id
      and cm.user_id = p_user_id
      and case cm.role when 'owner' then 3 when 'admin' then 2 else 1 end
          >= case p_min_role when 'owner' then 3 when 'admin' then 2 else 1 end
  );
$$;

-- Membership is simply the lowest role, so it delegates rather than repeating
-- the lookup: one predicate, one place to get it wrong.
create or replace function public.is_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_community_role(p_community_id, p_user_id, 'player');
$$;

revoke execute on function public.has_community_role(uuid, uuid, text)
  from anon, public;
grant execute on function public.has_community_role(uuid, uuid, text)
  to authenticated;

-- 2) Policies -----------------------------------------------------------------
-- Visibility is unchanged (PD-14); the owner_id branch is dropped because the
-- owner is always a member, so the rule it expressed is already covered.
drop policy if exists "communities_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (
    is_active
    and (
      not is_private
      or public.is_community_member(id, auth.uid())
    )
  );

-- Settings stay owner-only (PD-05); the source of that fact changes.
drop policy if exists "communities_update_owner" on public.communities;
create policy "communities_update_owner"
  on public.communities
  for update
  to authenticated
  using (public.has_community_role(id, auth.uid(), 'owner'))
  with check (public.has_community_role(id, auth.uid(), 'owner'));

-- Match creation narrows from any member to owner + admin (PD-06).
-- created_by must still be the caller: that keeps the audit field honest, it
-- is not what grants the insert.
drop policy if exists "matches_insert_community_members" on public.matches;
create policy "matches_insert_community_admins"
  on public.matches
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.has_community_role(community_id, auth.uid(), 'admin')
  );

-- Editing a match is no longer the creator's privilege (PD-07).
drop policy if exists "matches_update_creator" on public.matches;
create policy "matches_update_community_admins"
  on public.matches
  for update
  to authenticated
  using (public.has_community_role(community_id, auth.uid(), 'admin'))
  with check (public.has_community_role(community_id, auth.uid(), 'admin'));

-- Admins may leave too; an owner must hand the community over first (PD-12).
drop policy if exists "community_members_delete_self" on public.community_members;
create policy "community_members_delete_self"
  on public.community_members
  for delete
  to authenticated
  using (user_id = auth.uid() and role <> 'owner');

-- 3) Invitations ---------------------------------------------------------------
create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null
    references public.communities (id) on delete cascade,
  invited_by uuid not null references public.users (id),
  invitee_id uuid not null references public.users (id) on delete cascade,
  -- An invitation can never confer ownership; that only moves by transfer.
  role text not null check (role in ('admin', 'player')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default now() + interval '14 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- At most one live invitation per person per community.
create unique index if not exists invitations_one_pending_idx
  on public.invitations (community_id, invitee_id)
  where status = 'pending';
create index if not exists invitations_invitee_idx
  on public.invitations (invitee_id, status);

drop trigger if exists invitations_set_updated_at on public.invitations;
create trigger invitations_set_updated_at
  before update on public.invitations
  for each row execute function public.set_updated_at();

alter table public.invitations enable row level security;

drop policy if exists "invitations_select_visible" on public.invitations;
create policy "invitations_select_visible"
  on public.invitations
  for select
  to authenticated
  using (
    invitee_id = auth.uid()
    or public.has_community_role(community_id, auth.uid(), 'admin')
  );
-- No write policies: every change goes through the RPCs below.

-- An admin may invite players; only an owner may offer the admin role (PD-10).
create or replace function public.create_invitation(
  p_community_id uuid,
  p_invitee_id uuid,
  p_role text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_role not in ('admin', 'player') then
    raise exception 'INVALID_ROLE';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if is_community_member(p_community_id, p_invitee_id) then
    raise exception 'ALREADY_MEMBER';
  end if;

  begin
    insert into invitations (community_id, invited_by, invitee_id, role)
    values (p_community_id, auth.uid(), p_invitee_id, p_role)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'INVITATION_EXISTS';
  end;

  return v_id;
end;
$$;

create or replace function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_inv from invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if not has_community_role(v_inv.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;

  update invitations set status = 'revoked' where id = p_invitation_id;
end;
$$;

-- Only the named invitee can accept. The row lock makes a double accept a
-- no-op rather than a second membership.
create or replace function public.accept_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_inv from invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_inv.invitee_id <> auth.uid() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'INVITATION_EXPIRED';
  end if;
  if is_community_member(v_inv.community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (v_inv.community_id, auth.uid(), v_inv.role);

  update invitations set status = 'accepted' where id = p_invitation_id;
  return v_inv.community_id;
end;
$$;

-- 4) Role assignment -----------------------------------------------------------
-- Owner only (PD-02, PD-03). Ownership itself is not settable here.
create or replace function public.set_member_role(
  p_community_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_role not in ('admin', 'player') then
    raise exception 'INVALID_ROLE';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;

  update community_members
  set role = p_role
  where community_id = p_community_id
    and user_id = p_user_id
    and role <> 'owner';

  if not found then
    raise exception 'MEMBER_NOT_FOUND';
  end if;
end;
$$;

-- 5) Organizer RPCs: creator check -> role check --------------------------------
-- Bodies are otherwise unchanged; only the guard and its error code differ.
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
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_starting_players < 2 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

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
    description = case when p_description is null or trim(p_description) = ''
                       then null else trim(p_description) end
  where id = p_match_id;

  perform rebalance_roster(p_match_id);
  perform recompute_match_status(p_match_id);

  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;
end;
$$;

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
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
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
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      'تم حذف المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;

  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

-- 6) Grants ---------------------------------------------------------------------
revoke execute on function public.create_invitation(uuid, uuid, text)
  from anon, public;
revoke execute on function public.revoke_invitation(uuid) from anon, public;
revoke execute on function public.accept_invitation(uuid) from anon, public;
revoke execute on function public.set_member_role(uuid, uuid, text)
  from anon, public;

grant execute on function public.create_invitation(uuid, uuid, text)
  to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;
grant execute on function public.accept_invitation(uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text)
  to authenticated;

-- ============ migrations/0009_community_management.sql ============
-- Phase 3 (AMS v1.2), second part: the three community-management operations
-- whose behaviour the Product Owner ruled on after 0008 was applied.
--
-- All three are authorized through has_community_role, like everything else
-- since 0008; owner_id and created_by remain non-authorization fields.

-- 1) Ownership transfer ---------------------------------------------------------
-- Owner only. Demote-and-promote happen in one transaction, so the community is
-- never observable with zero or two owners. owner_id is the derived reporting
-- field (PD-15) and is re-pointed here, the one place ownership can move.
create or replace function public.transfer_ownership(
  p_community_id uuid,
  p_new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_new_owner_id = auth.uid() then
    raise exception 'ALREADY_OWNER';
  end if;

  -- Serializes concurrent transfers of the same community.
  perform 1 from communities where id = p_community_id for update;

  if not exists (
    select 1 from community_members
    where community_id = p_community_id and user_id = p_new_owner_id
  ) then
    raise exception 'MEMBER_NOT_FOUND';
  end if;

  update community_members set role = 'admin'
  where community_id = p_community_id and user_id = auth.uid();

  update community_members set role = 'owner'
  where community_id = p_community_id and user_id = p_new_owner_id;

  update communities set owner_id = p_new_owner_id where id = p_community_id;
end;
$$;

-- 2) Member removal --------------------------------------------------------------
-- Owner removes admins and players; an admin removes players only (PD-11). The
-- owner can never be removed. Removal also takes the member out of every match
-- in the community -- confirmed and reserve alike -- freeing each confirmed seat
-- through the existing promotion path so the roster stays correct.
create or replace function public.remove_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_role text;
  r record;
  v_promoted uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_REMOVE_SELF';
  end if;

  select role into v_target_role
  from community_members
  where community_id = p_community_id and user_id = p_user_id;
  if not found then
    raise exception 'MEMBER_NOT_FOUND';
  end if;
  if v_target_role = 'owner' then
    raise exception 'CANNOT_REMOVE_OWNER';
  end if;
  -- Removing an admin changes the role structure, which is owner territory.
  if v_target_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  for r in
    select mr.id, mr.status, mr.match_id
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id
      and mr.user_id = p_user_id
  loop
    -- Same lock order as every other roster write: match row first.
    perform 1 from matches where id = r.match_id for update;

    delete from match_registrations where id = r.id;

    if r.status = 'confirmed' then
      update match_registrations set status = 'confirmed'
      where id = (
        select id from match_registrations
        where match_id = r.match_id and status = 'reserve'
        order by registration_order
        limit 1
      )
      returning user_id into v_promoted;

      if v_promoted is not null then
        perform create_notification(v_promoted, r.match_id, 'promoted',
            'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
      end if;
    end if;

    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

-- 3) Community deletion ----------------------------------------------------------
-- Owner only. Everything scoped to the community goes with it; no archive and no
-- soft delete at this stage.
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform 1 from communities where id = p_community_id for update;

  -- Notifications point at the match with ON DELETE SET NULL, so they have to go
  -- first: once the matches are gone there is no way left to tell which
  -- notifications belonged to this community.
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);

  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from invitations where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- Grants ---------------------------------------------------------------------------
revoke execute on function public.transfer_ownership(uuid, uuid) from anon, public;
revoke execute on function public.remove_member(uuid, uuid) from anon, public;
revoke execute on function public.delete_community(uuid) from anon, public;
grant execute on function public.transfer_ownership(uuid, uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.delete_community(uuid) to authenticated;
