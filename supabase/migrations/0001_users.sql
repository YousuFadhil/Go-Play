-- Sprint 1: Authentication
-- Creates the public.users profile table linked to Supabase Auth,
-- per Docs/07-Database-Design.md (MVP scope per Docs/01-PRD.md).

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text not null unique,
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
-- full_name and primary_position arrive via auth signUp metadata.
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
    coalesce(new.phone, ''),
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
