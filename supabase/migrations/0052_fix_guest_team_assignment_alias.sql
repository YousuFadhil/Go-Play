-- Fix: "Create Teams" fails on any match holding a Professional Guest.
--
-- ## The bug
--
-- `assign_professional_guest_teams` declares a PL/pgSQL record variable named
-- `r` for its loop, and the DELETE above that loop used `r` as a **table alias**
-- for `match_registrations` in a correlated subquery:
--
--     declare r record;                      -- the loop variable
--     ...
--     delete from match_team_assignments a
--     where ...
--       and not exists (
--         select 1 from match_registrations r      -- the alias
--         where r.match_id = p_match_id            -- resolved as the VARIABLE
--       );
--
-- PL/pgSQL substitutes its own variables before the statement reaches the SQL
-- parser, and a qualified reference like `r.match_id` against a declared record
-- is read as a *field of that record*, not as a column of the alias. At that
-- point in the function `r` has not been assigned by any loop iteration, so the
-- statement fails with:
--
--     55000  record "r" is not assigned yet
--     DETAIL: The tuple structure of a not-yet-assigned record is indeterminate.
--
-- This is a runtime error, not a parse error: the function was created
-- successfully by `0050` and again by `0051`, and the fault only appears when
-- that DELETE is actually reached.
--
-- ## Why it looked like a team-generation bug
--
-- The DELETE sits after an early return. When a match has **no community
-- lineup**, the function clears any leftover guest rows and returns before ever
-- reaching it — which is exactly the path `add_professional_guest` takes, so
-- adding a guest always worked. The DELETE is reached only once a community
-- lineup exists, and the first thing that creates one is `replace_match_lineup`
-- — the save at the end of "Create Teams". So the failure presented as team
-- generation breaking, on precisely those matches that had a guest.
--
-- Every caller is affected, not only generation: `reconcile_match_lineup` runs
-- from `recompute_match_status`, so a withdrawal, a removal or a match edit on a
-- match that has both a stored lineup and a guest would raise the same error.
-- One fix covers all of them, because they all reach this one function.
--
-- ## The fix
--
-- Rename the subquery's alias. `seat` is what a `match_registrations` row is
-- here — the seat a guest holds — and it collides with nothing. Nothing else
-- about the function changes: the alternating assignment, the three guards, the
-- NULL position and the `do update set team` that never overwrites a chosen
-- position are all exactly as `0051` left them.
--
-- Renaming the alias rather than the loop variable is the smaller change and
-- the clearer one: the variable is referenced in five places inside the loop,
-- the alias in three inside one statement.
--
-- Verified against the live database before this migration was written, by
-- running `replace_match_lineup` for the affected match inside a transaction
-- that was rolled back: unpatched it raised `55000`; with the alias renamed it
-- wrote 13 community rows and placed the guest on team A with a NULL position.
--
-- Idempotent: one `create or replace function`. No table, column, constraint,
-- index, policy or grant changes.
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
  --
  -- CHANGED (0052): the alias is `seat`, not `r`. `r` is the loop record
  -- declared above, and PL/pgSQL resolves `r.match_id` against that variable
  -- rather than against this alias -- which failed at runtime with
  -- "record r is not assigned yet" every time this statement was reached.
  delete from match_team_assignments a
  where a.match_id = p_match_id
    and a.professional_guest_id is not null
    and not exists (
      select 1 from match_registrations seat
      where seat.match_id = p_match_id
        and seat.professional_guest_id = a.professional_guest_id
        and seat.status = 'confirmed'
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
      -- A guest is placed on a side, and nothing here claims to know where on
      -- the pitch they stood (migration 0051).
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
