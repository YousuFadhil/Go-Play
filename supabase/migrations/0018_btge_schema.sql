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

-- 2) Rating is not self-service ------------------------------------------------
-- users_update_own_profile lets a player edit their own row, so without this a
-- player could set their own strength to 10.0 and the balance the engine
-- computes would mean nothing. The approved decision states that rating
-- adjustment is a separate business rule, so the column is withheld from
-- clients until that rule exists.
--
-- Column privileges are the precise tool: the rest of the profile stays
-- self-editable. A table-level grant would override a column-level revoke, so
-- the table-level UPDATE is replaced by an explicit column list. That list is
-- every column a client could update before this migration, plus the two new
-- profile fields, minus overall_rating.
revoke update on public.users from authenticated, anon;
grant update (
  phone,
  full_name,
  primary_position,
  is_active,
  date_of_birth,
  secondary_position
) on public.users to authenticated;

-- 3) The played lineup ---------------------------------------------------------
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

-- 4) Authorization -------------------------------------------------------------
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
