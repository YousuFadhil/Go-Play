-- A Professional Guest has no assigned position, and the schema now says so.
--
-- Migration `0050` placed a guest at `MID`. That was an assumption and not an
-- approved rule: nothing knows a guest is a midfielder, and `assigned_position`
-- means *the position they played*, so storing one invents a fact. The approved
-- representation is the absence of a position — NULL — with `assignment_basis`
-- already carrying `GUEST` to say why.
--
-- This is the same judgement migration `0018` made for the two Core Player
-- Inputs a profile may lack: `date_of_birth` and `secondary_position` are
-- nullable precisely because "the database must not invent them", and §4.3
-- rejects a missing input rather than substituting a default. A guest's
-- position is the same kind of absence.
--
-- ## What is deliberately preserved
--
--   * **The vocabulary.** GK, DEF, MID, FWD remain the only values the column
--     accepts. Nothing gains a fifth position, and in particular no `GUEST`
--     position value is introduced — `Position` is `package:btge`'s enum, and a
--     participant the engine never sees must not widen the engine's vocabulary.
--   * **The community-player guarantee.** A registered player must still have a
--     position. That was `NOT NULL` doing the work for everybody; it is now a
--     CHECK doing it for exactly the rows it was ever true of.
--   * **One goalkeeper per team.** `match_team_assignments_one_gk_idx` is
--     untouched. It indexes `where assigned_position = 'GK'`, so a NULL row is
--     simply not in it and the rule is unaffected.
--
-- ## No backfill
--
-- Nothing rewrites existing rows. There are no invented `MID` guests to correct
-- — the live project is at `0043` and `0050` has never been applied — and a
-- blanket update would be indistinguishable from erasing a position an
-- administrator had deliberately chosen. A guest **may** hold a real position;
-- what changes here is that they need not.
--
-- Idempotent: `drop constraint if exists` before each add, and
-- `create or replace function`. No index, policy or grant changes.

-- 1) The column ---------------------------------------------------------------------
alter table public.match_team_assignments
  alter column assigned_position drop not null;

-- 2) The vocabulary, restated ----------------------------------------------------------
-- Unchanged in what it admits. A bare `in (...)` already tolerates NULL — the
-- comparison is unknown and a CHECK passes on unknown — but the rule is written
-- out so that "a position, or none at all" is the constraint a reader sees
-- rather than something they have to infer from three-valued logic.
alter table public.match_team_assignments
  drop constraint if exists match_team_assignments_assigned_position_check;
alter table public.match_team_assignments
  add constraint match_team_assignments_assigned_position_check
    check (
      assigned_position is null
      or assigned_position in ('GK', 'DEF', 'MID', 'FWD')
    );

-- 3) A registered player still has one -------------------------------------------------
-- The half of `NOT NULL` that was always true and must stay true. A lineup row
-- naming a user is the record of where that user played, and the engine that
-- produced it always names a position; only a guest, who has no profile for one
-- to be derived against, may lack it.
--
-- Stated against `user_id` rather than against `professional_guest_id` on
-- purpose: the participant XOR (`0044`) already makes those two the same
-- question, and writing it this way says what the rule is *about* — the player,
-- not the absence of a guest.
alter table public.match_team_assignments
  drop constraint if exists match_team_assignments_user_position_check;
alter table public.match_team_assignments
  add constraint match_team_assignments_user_position_check
    check (user_id is null or assigned_position is not null);

comment on column public.match_team_assignments.assigned_position is
  'The position played: GK, DEF, MID or FWD. Required of a registered player '
  'and optional for a Professional Guest, who has no profile for one to be '
  'derived against. NULL is the absence of a position, never an unknown one '
  '-- see migration 0051.';

-- 4) Placing a guest without inventing one ------------------------------------------------
-- Migration `0050`'s function with one value changed: the insert writes NULL
-- where it wrote `'MID'`.
--
-- Everything else is as it was and is restated only because `create or replace
-- function` replaces the whole body: the alternation by addition order, the
-- three guards (a recorded result, no community lineup, a guest who has dropped
-- to reserve), and the `do update set team` that moves a guest between sides
-- **without touching their position**. That last part is what lets an
-- administrator choose a real position later and keep it: re-alternating never
-- overwrites one, and never supplies one.
create or replace function public.assign_professional_guest_teams(
  p_match_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  -- A recorded result names the lineup it was scored on.
  if exists (select 1 from match_results where match_id = p_match_id) then
    return;
  end if;

  -- No community lineup means nothing has been generated yet. Any guest rows
  -- left over from a lineup that has since been cleared go with it.
  if not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id is not null
  ) then
    delete from match_team_assignments
    where match_id = p_match_id and professional_guest_id is not null;
    return;
  end if;

  -- A guest who is no longer starting is no longer on the pitch.
  delete from match_team_assignments a
  where a.match_id = p_match_id
    and a.professional_guest_id is not null
    and not exists (
      select 1 from match_registrations r
      where r.match_id = p_match_id
        and r.professional_guest_id = a.professional_guest_id
        and r.status = 'confirmed'
    );

  -- A, B, A, B by addition order. `row_number()` is recomputed over the guests
  -- who are starting *now*, so removing one re-alternates the rest.
  for r in
    select mr.professional_guest_id as guest_id,
           row_number() over (order by mr.registration_order) as seq
    from match_registrations mr
    where mr.match_id = p_match_id
      and mr.professional_guest_id is not null
      and mr.status = 'confirmed'
  loop
    insert into match_team_assignments (
      match_id, professional_guest_id, team, assigned_position, assignment_basis
    )
    values (
      p_match_id,
      r.guest_id,
      case when r.seq % 2 = 1 then 'A' else 'B' end,
      -- CHANGED (0051): was 'MID'. A guest is placed on a side, and nothing
      -- here claims to know where on the pitch they stood.
      null,
      'GUEST'
    )
    on conflict (match_id, professional_guest_id)
      where professional_guest_id is not null
    -- The side, and only the side. A position an administrator has chosen
    -- survives every re-alternation.
    do update set team = excluded.team;
  end loop;
end;
$$;

revoke execute on function public.assign_professional_guest_teams(uuid)
  from anon, authenticated, public;
