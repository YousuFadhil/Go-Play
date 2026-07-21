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
