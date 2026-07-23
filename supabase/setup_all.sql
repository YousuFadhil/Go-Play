-- Go Play: combined setup script (migrations 0001-0006, in order).
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
-- V2: Match management (organizer tools), extended status model, notifications.
-- Backward compatible: new columns are nullable; new statuses extend the
-- existing set; existing register/withdraw behaviour is preserved and only
-- gains automatic open/full transitions.

-- 1) New optional match fields -------------------------------------------------
alter table public.matches
  add column if not exists title text
    check (title is null or char_length(trim(title)) between 2 and 60);
alter table public.matches
  add column if not exists description text
    check (description is null or char_length(description) <= 300);

-- 2) Extend the status model: draft, full, postponed ---------------------------
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches
  add constraint matches_status_check
  check (status in ('draft', 'open', 'full', 'postponed', 'cancelled', 'completed'));

-- 3) Notifications -------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  match_id uuid references public.matches (id) on delete cascade,
  type text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

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

-- Internal helper: create one notification row.
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

-- Recomputes open/full for a match after its roster changes. Never touches
-- terminal states (cancelled/completed) or draft.
create or replace function public.recompute_match_fill(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed int;
begin
  select * into v_match from matches where id = p_match_id;
  if v_match.status not in ('open', 'full') then
    return;
  end if;
  select count(*) into v_confirmed
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';
  update matches
  set status = case when v_confirmed >= v_match.max_players then 'full' else 'open' end
  where id = p_match_id;
end;
$$;

-- 4) Registration: allow joining open/full/postponed; auto open<->full ----------
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

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  perform 1 from users where id = auth.uid() for update;

  -- Joinable while open, full (as reserve) or postponed (re-opened).
  if v_match.status not in ('open', 'full', 'postponed')
     or v_match.start_at <= now() then
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

  -- Overlap rule: no registration in another live match whose time range
  -- intersects this one (reserves count; they can be promoted anytime).
  if exists (
    select 1
    from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = auth.uid()
      and m.status in ('open', 'full', 'postponed')
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

  -- A postponed match becomes live again on the first registration.
  if v_match.status = 'postponed' then
    update matches set status = 'open' where id = p_match_id;
  end if;
  perform recompute_match_fill(p_match_id);

  return v_status;
end;
$$;

-- 5) Withdrawal: promote first reserve; auto full->open -------------------------
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

  if v_match.status not in ('open', 'full') or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations
    set status = 'confirmed'
    where id = (
      select id from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    );
  end if;

  perform recompute_match_fill(p_match_id);
end;
$$;

-- 6) Organizer: edit match (handles player-limit reduction) --------------------
create or replace function public.update_match(
  p_match_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_max_players int,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed int;
  r record;
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
  if v_match.status in ('cancelled', 'completed') then
    raise exception 'MATCH_READ_ONLY';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_max_players < 2 or p_max_players > 30 then
    raise exception 'INVALID_MAX_PLAYERS';
  end if;

  -- If the limit shrinks below the confirmed count, demote the latest
  -- confirmed players to reserve (registration order preserved).
  select count(*) into v_confirmed
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  if p_max_players < v_confirmed then
    for r in
      select id, user_id
      from match_registrations
      where match_id = p_match_id and status = 'confirmed'
      order by registration_order desc
      limit (v_confirmed - p_max_players)
    loop
      update match_registrations set status = 'reserve' where id = r.id;
      perform create_notification(
        r.user_id, p_match_id, 'moved_to_reserve',
        'تم نقلك إلى قائمة الاحتياط بسبب تعديل عدد اللاعبين.');
    end loop;
  end if;

  update matches set
    title = case when p_title is null or trim(p_title) = '' then null else trim(p_title) end,
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    max_players = p_max_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;

  perform recompute_match_fill(p_match_id);

  -- Notify every registered player that details changed. Players who were
  -- just demoted also received the reserve-move notice above.
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;
end;
$$;

-- 7) Organizer: remove a player -----------------------------------------------
create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
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
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;
  if v_match.status not in ('open', 'full') then
    raise exception 'MATCH_READ_ONLY';
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
    );
  end if;

  perform recompute_match_fill(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed',
      'قام المنظم بإزالتك من المباراة.');
end;
$$;

-- 8) Organizer: cancel (keeps registrations as history) ------------------------
create or replace function public.cancel_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status in ('cancelled', 'completed') then
    raise exception 'MATCH_READ_ONLY';
  end if;

  update matches set status = 'cancelled' where id = p_match_id;

  perform create_notification(mr.user_id, p_match_id, 'match_cancelled',
      'تم إلغاء المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
end;
$$;

-- 9) Organizer: postpone (clears registrations, re-opens) ----------------------
create or replace function public.postpone_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status not in ('open', 'full') then
    raise exception 'MATCH_READ_ONLY';
  end if;

  perform create_notification(mr.user_id, p_match_id, 'match_postponed',
      'تم تأجيل المباراة وإعادة فتح التسجيل.')
  from match_registrations mr where mr.match_id = p_match_id;

  delete from match_registrations where match_id = p_match_id;
  update matches set status = 'postponed' where id = p_match_id;
end;
$$;

-- 10) Organizer: delete (only with zero registrations, never completed) --------
create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_count int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status = 'completed' then raise exception 'MATCH_COMPLETED'; end if;

  select count(*) into v_count
  from match_registrations where match_id = p_match_id;
  if v_count > 0 then raise exception 'MATCH_HAS_PLAYERS'; end if;

  delete from matches where id = p_match_id;
end;
$$;

-- Grants: organizer/notification helpers are for authenticated callers only.
revoke execute on function public.create_notification(uuid, uuid, text, text) from anon, authenticated, public;
revoke execute on function public.recompute_match_fill(uuid) from anon, authenticated, public;
revoke execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text) from anon, public;
revoke execute on function public.remove_player(uuid, uuid) from anon, public;
revoke execute on function public.cancel_match(uuid) from anon, public;
revoke execute on function public.postpone_match(uuid) from anon, public;
revoke execute on function public.delete_match(uuid) from anon, public;
grant execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text) to authenticated;
grant execute on function public.remove_player(uuid, uuid) to authenticated;
grant execute on function public.cancel_match(uuid) to authenticated;
grant execute on function public.postpone_match(uuid) to authenticated;
grant execute on function public.delete_match(uuid) to authenticated;

