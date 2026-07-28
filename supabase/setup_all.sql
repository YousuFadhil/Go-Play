-- Go Play: combined setup script (migrations 0001-0018, in order).
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

-- ============ migrations/0010_invite_links.sql ============
-- Smart Community Invitation: shareable invite links.
--
-- A shareable link is a bearer token naming a community and, optionally, one
-- match. It is a sibling of `invitations`, not a replacement: a directed
-- invitation names an existing user, is single-use and may offer admin, while a
-- link has no named recipient, is multi-use and only ever grants player.
-- Nothing in this migration alters an existing table, policy or function.
--
-- Approved decisions:
--   * a community-only link never expires; it is valid until an admin revokes it
--   * a community+match link expires when the match starts, or is deleted
--   * redemption always grants the player role
--   * the preview is readable before authentication
--
-- Authorization is unchanged: has_community_role remains the only predicate,
-- and redemption composes the existing membership insert with the existing
-- register_for_match. No business rule is restated here.

-- 1) Table ---------------------------------------------------------------------
create table if not exists public.community_invite_links (
  id uuid primary key default gen_random_uuid(),
  -- 32 hex chars from a v4 UUID: unguessable, URL-safe, no extension needed.
  token text not null unique
    default replace(gen_random_uuid()::text, '-', ''),
  community_id uuid not null
    references public.communities (id) on delete cascade,
  -- Kept alongside match_id because the two disagree after a match is deleted:
  -- kind stays 'match' while match_id becomes null, which is precisely how an
  -- expired-by-deletion link is told apart from a community-only one.
  kind text not null check (kind in ('community', 'match')),
  match_id uuid references public.matches (id) on delete set null,
  created_by uuid not null references public.users (id),
  -- A link has no named recipient, so it can never confer more than the lowest
  -- role. Admin is offered only through a directed invitation (PD-10).
  role text not null default 'player' check (role = 'player'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invite_links_match_kind_agree check (
    (kind = 'community' and match_id is null) or kind = 'match'
  )
);

-- Sharing the same thing twice should hand back the same link rather than
-- breeding new ones, so at most one active link per community and per match.
create unique index if not exists invite_links_one_active_community_idx
  on public.community_invite_links (community_id)
  where is_active and kind = 'community';
create unique index if not exists invite_links_one_active_match_idx
  on public.community_invite_links (match_id)
  where is_active and match_id is not null;
create index if not exists invite_links_community_idx
  on public.community_invite_links (community_id);

drop trigger if exists invite_links_set_updated_at
  on public.community_invite_links;
create trigger invite_links_set_updated_at
  before update on public.community_invite_links
  for each row execute function public.set_updated_at();

-- 2) RLS -----------------------------------------------------------------------
alter table public.community_invite_links enable row level security;

-- Organizers can list and audit their own community's links. Everyone else
-- reaches a link only through preview_invite_link, which returns a fixed set of
-- fields and never the row. anon has no table access at all.
drop policy if exists "invite_links_select_admins"
  on public.community_invite_links;
create policy "invite_links_select_admins"
  on public.community_invite_links
  for select
  to authenticated
  using (public.has_community_role(community_id, auth.uid(), 'admin'));
-- No write policies: every change goes through the RPCs below.

-- 3) Validity ------------------------------------------------------------------
-- One place decides whether a token is usable, shared by preview and redeem so
-- the landing screen can never disagree with what redemption will do.
create or replace function public.invite_link_state(
  p_link public.community_invite_links
)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_link.id is null then 'not_found'
    when not p_link.is_active then 'revoked'
    when p_link.kind = 'community' then 'valid'
    when p_link.match_id is null then 'match_deleted'
    when (select m.start_at from matches m where m.id = p_link.match_id)
         <= now() then 'expired'
    else 'valid'
  end;
$$;

-- 4) Create and revoke ---------------------------------------------------------
create or replace function public.create_invite_link(
  p_community_id uuid,
  p_match_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := case when p_match_id is null then 'community' else 'match' end;
  v_match matches%rowtype;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_match_id is not null then
    select * into v_match from matches m where m.id = p_match_id;
    if not found then
      raise exception 'MATCH_NOT_FOUND';
    end if;
    if v_match.community_id <> p_community_id then
      raise exception 'MATCH_NOT_IN_COMMUNITY';
    end if;
    -- A link that expires at kick-off is pointless once kick-off has passed.
    if v_match.start_at <= now() then
      raise exception 'MATCH_LOCKED';
    end if;
  end if;

  select l.token into v_token
  from community_invite_links l
  where l.is_active
    and l.kind = v_kind
    and l.community_id = p_community_id
    and l.match_id is not distinct from p_match_id;
  if found then
    return v_token;
  end if;

  begin
    insert into community_invite_links (community_id, kind, match_id, created_by)
    values (p_community_id, v_kind, p_match_id, auth.uid())
    returning token into v_token;
  exception when unique_violation then
    -- Two organizers pressed share at the same moment; either link will do.
    select l.token into v_token
    from community_invite_links l
    where l.is_active
      and l.kind = v_kind
      and l.community_id = p_community_id
      and l.match_id is not distinct from p_match_id;
  end;

  return v_token;
end;
$$;

create or replace function public.revoke_invite_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_link
  from community_invite_links l where l.id = p_link_id for update;
  if not found then
    raise exception 'INVITE_NOT_FOUND';
  end if;
  if not has_community_role(v_link.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  update community_invite_links l set is_active = false where l.id = p_link_id;
end;
$$;

-- 5) Preview -------------------------------------------------------------------
-- Callable before sign-in, so it is deliberately narrow: the community's name,
-- the match's public face, and enough counts for the screen to be honest about
-- a reserve place. It never returns join_code, the roster, who created the link
-- or anything about other members. A caller who is signed in additionally
-- learns where they already stand.
--
-- A revoked or unknown token returns its state and nothing else: revoking a
-- link means it stops telling strangers what it used to point at.
create or replace function public.preview_invite_link(p_token text)
returns table (
  state text,
  community_id uuid,
  community_name text,
  match_id uuid,
  match_title text,
  match_location text,
  match_start_at timestamptz,
  match_end_at timestamptz,
  starting_players int,
  seats_remaining int,
  would_be_reserve boolean,
  is_member boolean,
  is_registered boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
  v_state text;
  v_community communities%rowtype;
  v_match matches%rowtype;
  v_total int := 0;
  v_confirmed int := 0;
begin
  select * into v_link
  from community_invite_links l where l.token = trim(p_token);

  v_state := invite_link_state(v_link);

  if v_state in ('not_found', 'revoked') then
    return query select v_state, null::uuid, null::text, null::uuid,
      null::text, null::text, null::timestamptz, null::timestamptz,
      null::int, null::int, null::boolean, false, false;
    return;
  end if;

  select * into v_community from communities c where c.id = v_link.community_id;

  if v_link.match_id is not null then
    select * into v_match from matches m where m.id = v_link.match_id;
    select count(*) into v_total
    from match_registrations r where r.match_id = v_link.match_id;
    select count(*) into v_confirmed
    from match_registrations r
    where r.match_id = v_link.match_id and r.status = 'confirmed';
  end if;

  return query select
    v_state,
    v_link.community_id,
    v_community.name,
    v_link.match_id,
    v_match.title,
    v_match.location,
    v_match.start_at,
    v_match.end_at,
    v_match.starting_players,
    case when v_link.match_id is null then null::int
         else greatest(v_match.max_registration - v_total, 0) end,
    -- The same expression register_for_match uses to allocate a seat, so the
    -- screen promises exactly what redemption will deliver.
    case when v_link.match_id is null then null::boolean
         else v_confirmed >= v_match.starting_players end,
    auth.uid() is not null
      and is_community_member(v_link.community_id, auth.uid()),
    v_link.match_id is not null
      and auth.uid() is not null
      and exists (
        select 1 from match_registrations r
        where r.match_id = v_link.match_id and r.user_id = auth.uid()
      );
end;
$$;

-- 6) Redeem --------------------------------------------------------------------
-- Joining and registering are separate outcomes on purpose: if registration
-- fails the membership stands and the caller is told why. The inner block is
-- what makes that true -- a caught exception rolls back to its savepoint, not
-- past the membership insert.
--
-- register_for_match is called unchanged, so capacity, the reserve queue, the
-- overlap rule, the lock and closure are all decided where they always were.
create or replace function public.redeem_invite_link(p_token text)
returns table (
  community_id uuid,
  match_id uuid,
  registration_status text,
  failure_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
  v_state text;
  v_status text;
  v_failure text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_link
  from community_invite_links l where l.token = trim(p_token);

  v_state := invite_link_state(v_link);
  if v_state <> 'valid' then
    raise exception 'INVITE_%', upper(v_state);
  end if;

  if not is_community_member(v_link.community_id, auth.uid()) then
    begin
      insert into community_members (community_id, user_id, role)
      values (v_link.community_id, auth.uid(), v_link.role);
    exception when unique_violation then
      -- Someone redeemed the same link twice at once; membership is what
      -- matters and it now exists.
      null;
    end;
  end if;

  if v_link.match_id is not null then
    begin
      v_status := register_for_match(v_link.match_id);
    exception when others then
      v_failure := sqlerrm;
      v_status := null;
    end;

    -- Redeeming twice is expected of a link that lives in a group chat, so an
    -- existing registration is an outcome, not a failure.
    if v_failure = 'ALREADY_REGISTERED' then
      select r.status into v_status
      from match_registrations r
      where r.match_id = v_link.match_id and r.user_id = auth.uid();
      v_failure := null;
    end if;
  end if;

  return query select v_link.community_id, v_link.match_id, v_status, v_failure;
end;
$$;

-- 7) Grants --------------------------------------------------------------------
-- An internal helper, not an entry point: only the definer functions above call
-- it. Supabase's default privileges grant new functions to authenticated, so
-- that grant has to be taken back explicitly, not merely left ungranted.
revoke execute on function public.invite_link_state(public.community_invite_links)
  from anon, authenticated, public;
revoke execute on function public.create_invite_link(uuid, uuid)
  from anon, public;
revoke execute on function public.revoke_invite_link(uuid) from anon, public;
revoke execute on function public.redeem_invite_link(text) from anon, public;
revoke execute on function public.preview_invite_link(text) from public;

grant execute on function public.create_invite_link(uuid, uuid) to authenticated;
grant execute on function public.revoke_invite_link(uuid) to authenticated;
grant execute on function public.redeem_invite_link(text) to authenticated;
-- The one deliberately unauthenticated entry point in the system.
grant execute on function public.preview_invite_link(text)
  to anon, authenticated;

-- ============ migrations/0011_match_title_required.sql ============
-- Community-first simplification, part 1: every match has a name.
--
-- Rows with no title displayed their location, because Match.displayName fell
-- back to it. Copying the location into the title is therefore the backfill
-- that changes nothing a user can see. Approved as a one-off for existing rows;
-- new matches are never given a generated title, the organizer types one.

-- 1) Backfill ------------------------------------------------------------------
update public.matches
set title = left(trim(location), 60)
where title is null or trim(title) = '';

-- The title check requires at least two characters. Nothing in production has a
-- location that short, but an unusable location should not block the migration.
update public.matches
set title = 'Match'
where char_length(trim(title)) < 2;

-- 2) Require it from here on ---------------------------------------------------
alter table public.matches
  alter column title set not null;

alter table public.matches
  drop constraint if exists matches_title_check;
alter table public.matches
  add constraint matches_title_check
  check (char_length(trim(title)) between 2 and 60);

-- update_match still accepts a null title; with the column NOT NULL the update
-- would fail on the constraint. 0013 gives it a clear error code instead.

-- ============ migrations/0012_community_first_simplification.sql ============
-- Community-first simplification: one way into a community.
--
-- Before this migration there were three: a directed invitation naming a user,
-- a shareable link carrying its own 32-character token, and the community's
-- 6-character join code. They overlapped, and the link and the code were
-- separate identifiers for the same act of joining.
--
-- After it there is one: the community's join_code. It is the token. The
-- invitation link carries it, the join dialog accepts it, and
-- join_community_by_code redeems it — the function that already existed.
--
-- Removed here: the invitations table and its three RPCs, and the
-- community_invite_links table with its four RPCs and helper. Nothing else
-- referenced them; match registration was always self-service.

-- 1) Directed invitations ------------------------------------------------------
drop function if exists public.create_invitation(uuid, uuid, text);
drop function if exists public.revoke_invitation(uuid);
drop function if exists public.accept_invitation(uuid);
drop table if exists public.invitations cascade;

-- 2) Shareable invite links ----------------------------------------------------
-- Superseded by join_code. Match-attached links go with them: an organizer no
-- longer registers anyone, players register themselves.
drop function if exists public.create_invite_link(uuid, uuid);
drop function if exists public.revoke_invite_link(uuid);
drop function if exists public.preview_invite_link(text);
drop function if exists public.redeem_invite_link(text);
drop function if exists public.invite_link_state(public.community_invite_links);
drop table if exists public.community_invite_links cascade;

-- 3) The join code becomes the token -------------------------------------------
-- Twelve characters from a 31-symbol alphabet (Crockford-style base32 without
-- I, L, O, 0 and 1, which people mistype): about 59 bits. The old six
-- characters were guessable by brute force, which matters now that the code is
-- what an unauthenticated preview accepts.
create or replace function public.generate_join_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    select string_agg(
             substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1),
             '')
      into v_code
      from generate_series(1, 12);
    exit when not exists (select 1 from communities where join_code = v_code);
  end loop;
  return v_code;
end;
$$;

alter table public.communities
  alter column join_code set default public.generate_join_code();

-- Existing codes are six characters, which is the weakness this migration
-- closes, so they are reissued rather than left as a mixed-strength estate.
-- BREAKING: any six-character code already shared stops working.
update public.communities set join_code = public.generate_join_code();

alter table public.communities
  drop constraint if exists communities_join_code_length_check;
alter table public.communities
  add constraint communities_join_code_length_check
  check (char_length(join_code) between 6 and 32);

-- 4) Preview before signing in -------------------------------------------------
-- The landing screen has to show what a link offers to someone who has not
-- installed the app yet, let alone signed in. Deliberately narrow: the
-- community's name and whether the caller is already in it. Never the join
-- code itself, the roster, the matches, or who owns it.
create or replace function public.preview_community_invite(p_code text)
returns table (
  state text,
  community_id uuid,
  community_name text,
  is_member boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_community communities%rowtype;
begin
  select * into v_community
  from communities c
  where c.join_code = upper(trim(p_code)) and c.is_active;

  if not found then
    return query select 'not_found'::text, null::uuid, null::text, false;
    return;
  end if;

  return query select
    'valid'::text,
    v_community.id,
    v_community.name,
    auth.uid() is not null and is_community_member(v_community.id, auth.uid());
end;
$$;

revoke execute on function public.generate_join_code() from anon, authenticated, public;
revoke execute on function public.preview_community_invite(text) from public;
grant execute on function public.preview_community_invite(text)
  to anon, authenticated;

-- ============ migrations/0013_update_match_requires_title.sql ============
-- A match cannot be edited into having no name.
--
-- 0011 made matches.title NOT NULL, but update_match still wrote null when
-- handed a blank one, so an edit failed on the constraint with a Postgres
-- message instead of a code the app can translate. Same rule, said clearly.
--
-- Only the title guard and the title assignment change; every other check in
-- this function is untouched.

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
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_starting_players < 2 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if p_starting_players + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;
  update matches set
    title = trim(p_title),
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;
  perform rebalance_roster(p_match_id);
  perform recompute_match_status(p_match_id);
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
end;
$$;

-- ============ migrations/0014_delete_community_without_invitations.sql ============
-- delete_community still deleted from the invitations table that 0012 dropped,
-- so every call raised "relation does not exist" and no community could be
-- deleted at all. Same function, one line shorter.
--
-- Found because the integration suite's teardown uses this RPC: communities
-- leaked between tests and later registrations tripped OVERLAPPING_MATCH. The
-- teardown swallows its own errors, which is why the symptom surfaced far from
-- the cause.

create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform 1 from communities where id = p_community_id for update;
  -- Notifications first: match_id is ON DELETE SET NULL, so they would survive
  -- the matches and be orphaned rather than removed (DD-08).
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);
  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- ============ migrations/0015_regenerate_join_code.sql ============
-- Regenerating the join code is how a leaked invitation is invalidated.
--
-- The code is the only invitation identifier (DD-12), so there is nothing else
-- to revoke: issuing a new code retires the old one by replacing it. Membership,
-- matches and registrations are untouched — the code controls who may *join*,
-- not who already has.
--
-- One statement, so there is never a moment where the community has no code or
-- two. The row lock is for the read-then-write inside generate_join_code, which
-- checks the new value is unused before returning it.

create or replace function public.regenerate_join_code(p_community_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Owner and admin both share invitations, so both can retire one.
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform 1 from communities where id = p_community_id for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  update communities
  set join_code = generate_join_code()
  where id = p_community_id
  returning join_code into v_code;

  return v_code;
end;
$$;

revoke execute on function public.regenerate_join_code(uuid) from anon, public;
grant execute on function public.regenerate_join_code(uuid) to authenticated;

-- ============ migrations/0016_join_policy.sql ============
-- Visibility and joining were the same switch; they are two questions.
--
-- `is_private` hid a community from discovery *and* forced the join code. From
-- here a community is always visible, and the only setting is how someone is
-- allowed to join:
--
--   OPEN           anyone who can see it can join it
--   CODE_REQUIRED  joining needs the join code
--
-- The invitation link is unchanged and keeps working under both: it carries the
-- join code, and join_community_by_code accepts it either way. That is the point
-- of a code — it is the credential, not the policy.
--
-- This reverses DD-11 (private by default). Communities that were private become
-- CODE_REQUIRED, which preserves how people join them but not their obscurity:
-- their names and descriptions are now visible to every signed-in user. That is
-- the approved intent of "do not hide communities from discovery", and it is the
-- one user-visible consequence worth naming.

-- 1) The setting ---------------------------------------------------------------
alter table public.communities
  add column if not exists join_policy text not null default 'OPEN';

update public.communities
set join_policy = case when is_private then 'CODE_REQUIRED' else 'OPEN' end;

alter table public.communities
  drop constraint if exists communities_join_policy_check;
alter table public.communities
  add constraint communities_join_policy_check
  check (join_policy in ('OPEN', 'CODE_REQUIRED'));

-- 2) Everything is visible -----------------------------------------------------
-- The policy no longer asks whether the caller is a member: an inactive
-- community is still hidden, and nothing else is.
drop policy if exists "communities_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (is_active);

-- 3) is_private has no meaning left --------------------------------------------
-- Dropped rather than left behind: a column that no policy reads and no screen
-- writes is a trap for whoever reads this schema next.
alter table public.communities drop column if exists is_private;

-- 4) Joining -------------------------------------------------------------------
-- OPEN only. CODE_REQUIRED keeps its name honest: the code is the way in, and
-- this function refuses without it rather than quietly accepting.
create or replace function public.join_community(p_community_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select join_policy into v_policy
  from communities
  where id = p_community_id and is_active;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;
  if v_policy <> 'OPEN' then
    raise exception 'JOIN_CODE_REQUIRED';
  end if;
  if is_community_member(p_community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (p_community_id, auth.uid(), 'player');

  return p_community_id;
end;
$$;

revoke execute on function public.join_community(uuid) from anon, public;
grant execute on function public.join_community(uuid) to authenticated;

-- 5) Creating a community ------------------------------------------------------
-- Same shape as before, one argument renamed. The old signature is dropped so
-- there is no stale overload for a client to reach.
drop function if exists public.create_community(text, text, boolean);

create or replace function public.create_community(
  p_name text,
  p_description text,
  p_join_policy text
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
  if p_join_policy not in ('OPEN', 'CODE_REQUIRED') then
    raise exception 'INVALID_JOIN_POLICY';
  end if;

  insert into communities (owner_id, name, description, join_policy)
  values (auth.uid(), p_name, p_description, p_join_policy)
  returning id into v_id;

  insert into community_members (community_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

revoke execute on function public.create_community(text, text, text)
  from anon, public;
grant execute on function public.create_community(text, text, text)
  to authenticated;

-- 6) The invitation preview ----------------------------------------------------
-- Unchanged behaviour; it never read is_private.

-- ============ migrations/0017_system_admin.sql ============
-- A minimal internal administration role.
--
-- System Admin is not a community role and never appears in community_members:
-- has_community_role knows nothing about it, and it grants nothing inside any
-- community. It exists to remove things — users, communities, matches — when
-- support needs to, and that is all it can do.
--
-- Membership of this table is managed by hand in SQL. There is deliberately no
-- RPC and no screen for granting or revoking it: the app must not be able to
-- create its own administrators.
--
-- Deletion reuses the existing cascades rather than restating them. The three
-- purge_* helpers below hold the bodies that delete_community, delete_match and
-- remove_member already had; those functions keep their authorization checks and
-- now delegate. One cascade, two callers, no chance of the admin path drifting
-- from the member path.

-- 1) The role ------------------------------------------------------------------
create table if not exists public.system_admins (
  user_id uuid primary key references public.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.system_admins enable row level security;
-- No policies at all: the table is reachable only through the definer functions
-- below. Not even an administrator can read it from the client.

create or replace function public.is_system_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from system_admins where user_id = auth.uid()
  );
$$;

revoke execute on function public.is_system_admin() from anon, public;
grant execute on function public.is_system_admin() to authenticated;

-- 2) Shared cascades -----------------------------------------------------------
-- No authorization checks in here on purpose: each caller does its own. These
-- are the bodies the public functions already ran.

create or replace function public.purge_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      'تم حذف المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

create or replace function public.purge_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from communities where id = p_community_id for update;
  -- Notifications first: match_id is ON DELETE SET NULL, so they would outlive
  -- their matches and be orphaned rather than removed (DD-08).
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);
  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- Withdrawing a member from one community's matches, promoting reserves as it
-- goes. This is the part of remove_member that is a business rule rather than a
-- permission check (DD-01, and the promotion rule that goes with it).
create or replace function public.purge_membership(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_promoted uuid;
begin
  for r in
    select mr.id, mr.status, mr.match_id
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id and mr.user_id = p_user_id
  loop
    perform 1 from matches where id = r.match_id for update;
    delete from match_registrations where id = r.id;
    if r.status = 'confirmed' then
      update match_registrations set status = 'confirmed'
      where id = (select id from match_registrations
                  where match_id = r.match_id and status = 'reserve'
                  order by registration_order limit 1)
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

revoke execute on function public.purge_match(uuid) from anon, authenticated, public;
revoke execute on function public.purge_community(uuid) from anon, authenticated, public;
revoke execute on function public.purge_membership(uuid, uuid)
  from anon, authenticated, public;

-- 3) The existing functions now delegate ---------------------------------------
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform purge_community(p_community_id);
end;
$$;

create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform purge_match(p_match_id);
end;
$$;

create or replace function public.remove_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_target_role text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then raise exception 'CANNOT_REMOVE_SELF'; end if;

  select role into v_target_role from community_members
  where community_id = p_community_id and user_id = p_user_id;
  if not found then raise exception 'MEMBER_NOT_FOUND'; end if;
  if v_target_role = 'owner' then raise exception 'CANNOT_REMOVE_OWNER'; end if;
  if v_target_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform purge_membership(p_community_id, p_user_id);
end;
$$;

-- 4) Reading ---------------------------------------------------------------------
-- Search is a plain case-insensitive contains over the obvious field, capped at
-- 100 rows. Enough to find a record to delete, which is the only reason these
-- screens exist.

create or replace function public.admin_list_users(p_search text default null)
returns table (
  id uuid,
  full_name text,
  phone text,
  email text,
  created_at timestamptz,
  is_system_admin boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select u.id, u.full_name, u.phone, au.email::text, u.created_at,
           exists (select 1 from system_admins sa where sa.user_id = u.id)
    from users u
    join auth.users au on au.id = u.id
    where p_search is null or trim(p_search) = ''
       or u.full_name ilike '%' || trim(p_search) || '%'
       or au.email::text ilike '%' || trim(p_search) || '%'
    order by u.created_at desc
    limit 100;
end;
$$;

create or replace function public.admin_list_communities(p_search text default null)
returns table (
  id uuid,
  name text,
  join_policy text,
  created_at timestamptz,
  owner_name text,
  member_count bigint,
  match_count bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select c.id, c.name, c.join_policy, c.created_at, o.full_name,
           (select count(*) from community_members cm where cm.community_id = c.id),
           (select count(*) from matches m where m.community_id = c.id)
    from communities c
    left join users o on o.id = c.owner_id
    where p_search is null or trim(p_search) = ''
       or c.name ilike '%' || trim(p_search) || '%'
    order by c.created_at desc
    limit 100;
end;
$$;

create or replace function public.admin_list_matches(p_search text default null)
returns table (
  id uuid,
  title text,
  location text,
  start_at timestamptz,
  status text,
  community_name text,
  registration_count bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select m.id, m.title, m.location, m.start_at, m.status, c.name,
           (select count(*) from match_registrations r where r.match_id = m.id)
    from matches m
    join communities c on c.id = m.community_id
    where p_search is null or trim(p_search) = ''
       or m.title ilike '%' || trim(p_search) || '%'
       or m.location ilike '%' || trim(p_search) || '%'
       or c.name ilike '%' || trim(p_search) || '%'
    order by m.start_at desc
    limit 100;
end;
$$;

-- 5) Deleting ------------------------------------------------------------------

create or replace function public.admin_delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  perform purge_match(p_match_id);
end;
$$;

create or replace function public.admin_delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  perform purge_community(p_community_id);
end;
$$;

-- Removes the account and everything that would otherwise outlive it.
--
-- Order matters. Communities the user owns go whole, because a community
-- without an owner has no one who can manage or delete it. Elsewhere the user
-- is only a member, so they are withdrawn the way remove_member withdraws
-- anyone — reserves promoted, rosters recomputed — and matches they created in
-- someone else's community are deleted, since created_by does not cascade.
create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_DELETE_SELF';
  end if;
  -- System Admin accounts are managed outside the app, so the app cannot
  -- remove one. Otherwise the last administrator could be deleted from a phone.
  if exists (select 1 from system_admins where user_id = p_user_id) then
    raise exception 'CANNOT_DELETE_SYSTEM_ADMIN';
  end if;
  perform 1 from users where id = p_user_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;

  for r in select id from communities where owner_id = p_user_id loop
    perform purge_community(r.id);
  end loop;

  for r in select cm.community_id from community_members cm
           where cm.user_id = p_user_id loop
    perform purge_membership(r.community_id, p_user_id);
  end loop;

  for r in select id from matches where created_by = p_user_id loop
    perform purge_match(r.id);
  end loop;

  -- Anything addressed to them, and anything they still hold.
  delete from notifications where user_id = p_user_id;
  delete from match_registrations where user_id = p_user_id;
  delete from community_members where user_id = p_user_id;
  delete from users where id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

revoke execute on function public.admin_list_users(text) from anon, public;
revoke execute on function public.admin_list_communities(text) from anon, public;
revoke execute on function public.admin_list_matches(text) from anon, public;
revoke execute on function public.admin_delete_user(uuid) from anon, public;
revoke execute on function public.admin_delete_community(uuid) from anon, public;
revoke execute on function public.admin_delete_match(uuid) from anon, public;

grant execute on function public.admin_list_users(text) to authenticated;
grant execute on function public.admin_list_communities(text) to authenticated;
grant execute on function public.admin_list_matches(text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
grant execute on function public.admin_delete_community(uuid) to authenticated;
grant execute on function public.admin_delete_match(uuid) to authenticated;

-- ============ migrations/0018_btge_schema.sql ============
-- KB-D3: the schema the Balanced Team Generation Engine needs.
--
-- Two additions and nothing else. The player profile gains the three Core
-- Player Inputs the engine reads (Engineering Specification §4.1), and a new
-- table records which players actually played together, which is the only data
-- Diversity is permitted to consult (§4.2.1, KB-016).
--
-- Nothing is wired to the engine here. Reading these columns, writing a lineup
-- and generating teams belong to the adapter and integration milestones; this
-- migration only makes the data expressible.
--
-- Backward compatible throughout: no column is dropped or renamed, every
-- existing row stays valid, and no existing policy changes.

-- 1) Core Player Inputs on the profile -----------------------------------------
-- overall_rating carries the approved OP-1 scale: 0.0 to 10.0 to one decimal
-- place, default 5.0. NOT NULL with a constant default is a metadata-only
-- change in PostgreSQL 11 and later, so adding it does not rewrite the table.
--
-- date_of_birth and secondary_position are nullable. Existing players have
-- neither, and the database must not invent them: §4.3 is explicit that the
-- engine rejects a missing input rather than substituting a default, and that
-- judgement belongs above the schema. A missing secondary is ordinary input in
-- any case (BTGE-SC-6).
alter table public.users
  add column if not exists overall_rating numeric(3,1) not null default 5.0,
  add column if not exists date_of_birth date,
  add column if not exists secondary_position text;

alter table public.users
  drop constraint if exists users_overall_rating_range;
alter table public.users
  add constraint users_overall_rating_range
    check (overall_rating >= 0.0 and overall_rating <= 10.0);

-- Same vocabulary as primary_position (BTGE-HC-5), but nullable.
alter table public.users
  drop constraint if exists users_secondary_position_valid;
alter table public.users
  add constraint users_secondary_position_valid
    check (
      secondary_position is null
      or secondary_position in ('GK', 'DEF', 'MID', 'FWD')
    );

-- 2) The played lineup ---------------------------------------------------------
-- One row per player per match: the team they were on and the position they
-- played.
--
-- KB-017 decides what belongs here: the lineup that ACTUALLY played, including
-- any manual change the organizer made after generation. That is a record of
-- reality, not of the engine's proposal, and it is not learning — nothing about
-- the override itself is retained.
--
-- out_of_position is deliberately absent: §5.1 defines it as exactly
-- assignment_basis = 'TRANSITION', and storing a derived value invites the two
-- to disagree.
create table if not exists public.match_team_assignments (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  team text not null check (team in ('A', 'B')),
  assigned_position text not null
    check (assigned_position in ('GK', 'DEF', 'MID', 'FWD')),
  assignment_basis text not null
    check (assignment_basis in ('PRIMARY', 'SECONDARY', 'TRANSITION')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- BTGE-HC-1 and BTGE-HC-2: every player assigned exactly once, never twice.
  unique (match_id, user_id)
);

-- BTGE-HC-6: no team holds more than one goalkeeper. A partial unique index
-- states the rule where it cannot be worked around.
create unique index if not exists match_team_assignments_one_gk_idx
  on public.match_team_assignments (match_id, team)
  where assigned_position = 'GK';

-- Match History reads by person across recent matches; the unique constraint
-- already covers lookups by match.
create index if not exists match_team_assignments_user_id_idx
  on public.match_team_assignments (user_id);

drop trigger if exists match_team_assignments_set_updated_at
  on public.match_team_assignments;
create trigger match_team_assignments_set_updated_at
  before update on public.match_team_assignments
  for each row
  execute function public.set_updated_at();

-- 3) Authorization -------------------------------------------------------------
-- Reading a lineup is a member's business. Writing one is match management,
-- which PD-06 and PD-07 already placed with the owner and admins.
--
-- The admin predicate mirrors is_match_community_member, which exists for
-- exactly this reason: a policy that reached into matches directly would have
-- that subquery evaluated under the matches table's own RLS.
create or replace function public.is_match_community_admin(
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
    where m.id = p_match_id
      and public.has_community_role(m.community_id, p_user_id, 'admin')
  );
$$;

revoke execute on function public.is_match_community_admin(uuid, uuid)
  from anon, public;
grant execute on function public.is_match_community_admin(uuid, uuid)
  to authenticated;

alter table public.match_team_assignments enable row level security;

drop policy if exists "match_team_assignments_select_members"
  on public.match_team_assignments;
create policy "match_team_assignments_select_members"
  on public.match_team_assignments
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

drop policy if exists "match_team_assignments_insert_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_insert_admins"
  on public.match_team_assignments
  for insert
  to authenticated
  with check (public.is_match_community_admin(match_id, auth.uid()));

drop policy if exists "match_team_assignments_update_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_update_admins"
  on public.match_team_assignments
  for update
  to authenticated
  using (public.is_match_community_admin(match_id, auth.uid()))
  with check (public.is_match_community_admin(match_id, auth.uid()));

drop policy if exists "match_team_assignments_delete_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_delete_admins"
  on public.match_team_assignments
  for delete
  to authenticated
  using (public.is_match_community_admin(match_id, auth.uid()));
