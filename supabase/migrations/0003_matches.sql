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
