-- ============ migrations/0058_professional_guest_manual_team_override.sql ============
-- A side an organizer chose for a Professional Guest, and what it takes for it
-- to still be there afterwards.
--
-- ## The defect
--
-- A guest is not an engine input. The Balanced Team Generation Engine takes
-- community players only (§4.1 has nothing to read for somebody with no
-- profile), so nothing *generates* a side for a guest:
-- `assign_professional_guest_teams` (0050, 0051, 0052) alternates them A, B,
-- A, B by `registration_order`, and it re-runs that alternation at the end of
-- every `replace_match_lineup` and every `reconcile_match_lineup`.
--
-- Its upsert ends `do update set team = excluded.team`. So a guest moved to the
-- other side was moved back by the very call that saved the move. The move was
-- never offered in the client, which is why nothing had caught it.
--
-- ## What decides it
--
-- The alternation cannot tell a side it chose from a side a person chose,
-- because the row does not record the difference. This migration records it.
--
--   `match_team_assignments.team_manually_overridden boolean not null
--    default false`
--
-- A dedicated column, and deliberately not `assignment_basis`. That column
-- answers §5.1's question -- which rule produced the *position* -- and it
-- already carries `GUEST` for every guest row. Overloading it would make one
-- field answer two unrelated questions and would lose the guest marker to say
-- so.
--
-- ## The rule the column buys
--
--   * `team_manually_overridden = false` -- the alternation owns this row and
--     places it, exactly as it does today.
--   * `team_manually_overridden = true`  -- a person owns this row. The
--     alternation counts it, so the guests around it keep alternating in
--     order, and leaves its side alone.
--
-- Counting it rather than skipping it is the point: the sequence is over the
-- guests who are starting now, and dropping one from the numbering would move
-- everybody after them. A pinned guest holds its seat in the order and only its
-- side stops being derived.
--
-- ## Generate is still a fresh search
--
-- `BTGE-MO-2` makes Generate/Regenerate discard what was adjusted around the
-- previous teams. A guest's chosen side is such an adjustment, so it does not
-- survive one. `replace_match_lineup` gains `p_from_generation`, defaulted
-- false: the client passes true only on the save that follows a generation, and
-- that is the only call that clears the flags. An ordinary manual save -- a
-- move, a swap, a position change, a community player being rearranged --
-- passes false and every chosen side stands.
--
-- The default is what makes this safe to deploy ahead of the client: an
-- existing build calls the function with two arguments, gets `false`, and keeps
-- every override. Nothing is cleared by a client that has not been taught to
-- ask for it.
--
-- ## Forward-only and additive
--
-- One column with a default, and three function bodies replaced. No table is
-- rewritten, no row is deleted, no constraint is dropped, no policy is touched,
-- and no existing grant changes. Every existing row becomes `false`, which is
-- true of all of them: before this migration no side could be chosen by hand.
--
-- The three bodies below are the **current** definitions --
-- `assign_professional_guest_teams` from `0052`, `replace_match_lineup` and
-- `reconcile_match_lineup` from `0050` -- restated with only the changes named
-- here. `create or replace function` replaces the whole body, so restating the
-- rest verbatim is what keeps it.

-- 1) The marker ----------------------------------------------------------------
alter table public.match_team_assignments
  add column if not exists team_manually_overridden boolean not null
    default false;

comment on column public.match_team_assignments.team_manually_overridden is
  'True when an organizer chose this row''s team by hand. It exists for '
  'Professional Guests, whose side is otherwise re-derived by '
  'assign_professional_guest_teams on every lineup write; a community player '
  'carries false because the column is not nullable. Cleared by a save that '
  'follows Generate/Regenerate -- see migration 0058.';

-- 2) The alternation, taught to leave a chosen side alone -----------------------------
-- `0052`'s body with one change: the upsert no longer overwrites the team of a
-- row somebody has pinned.
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
  -- The alias is `seat`, not `r` (migration 0052): `r` is the loop record
  -- declared above, and PL/pgSQL resolves `r.match_id` against that variable
  -- rather than against this alias.
  --
  -- A pinned row is removed here too, on purpose. This is about whether they
  -- are starting at all, which a chosen side has no authority over -- somebody
  -- who is no longer on the roster is not on the pitch either way.
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
  --
  -- A pinned guest is still counted by this sequence rather than skipped: the
  -- numbering is what decides everybody else's side, and dropping one from it
  -- would shift every guest added after them.
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
    -- CHANGED (0058): the side, and only when nobody has chosen one. A
    -- position an administrator has chosen already survived every
    -- re-alternation; now the side does too.
    --
    -- The `where` is on the stored row, so the alternation simply does not
    -- touch a pinned one -- which is what makes a chosen side survive
    -- reopening Teams, another manual save, and an ordinary reconcile.
    do update set team = excluded.team
      where match_team_assignments.team_manually_overridden = false;
  end loop;
end;
$$;

revoke execute on function public.assign_professional_guest_teams(uuid)
  from anon, authenticated, public;

-- 3) Reconciliation ------------------------------------------------------------------
-- `0050`'s body, unchanged in substance. It is restated because the function it
-- calls has changed underneath it and this file is where that is written down:
-- the guests it re-places are now only the ones nobody has placed by hand.
create or replace function public.reconcile_match_lineup(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stale boolean;
begin
  -- A recorded result names the lineup it was scored on: it is history, and
  -- history is not reconciled against a roster that has since changed.
  if exists (select 1 from match_results where match_id = p_match_id) then
    return;
  end if;

  -- Nothing stored, nothing stale. Guests still need placing if a lineup
  -- appears later, which the call below handles on its own terms.
  if exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id is not null
  ) then
    v_stale := exists (
      select r.user_id
      from match_registrations r
      where r.match_id = p_match_id
        and r.user_id is not null
        and r.status = 'confirmed'
      except
      select a.user_id
      from match_team_assignments a
      where a.match_id = p_match_id and a.user_id is not null
    ) or exists (
      select a.user_id
      from match_team_assignments a
      where a.match_id = p_match_id and a.user_id is not null
      except
      select r.user_id
      from match_registrations r
      where r.match_id = p_match_id
        and r.user_id is not null
        and r.status = 'confirmed'
    );

    -- Completely, not partially. A lineup is a balanced whole: removing the
    -- players who left would leave the sides the engine chose around them, and
    -- the approved rule asks for a regeneration rather than a repair.
    --
    -- The guest rows go with it, and their chosen sides with them. That is the
    -- same rule as Generate: the teams a side was chosen against no longer
    -- exist.
    if v_stale then
      delete from match_team_assignments where match_id = p_match_id;
    end if;
  end if;

  perform assign_professional_guest_teams(p_match_id);
end;
$$;

-- 4) The lineup write ----------------------------------------------------------------
-- `0050`'s body with two changes:
--
--   * `p_from_generation`, defaulted false. True only on the save that follows
--     a generation, and the only thing that clears a chosen side.
--   * the insert carries `team_manually_overridden` from the payload, so a move
--     or a swap can record that a person chose the side it is writing.
--
-- Everything else is `0050` statement for statement: the authorization, the
-- payload identity split, the guest-preserving delete, the result guard, the
-- detach/attach of match effects and the guest alternation at the end.
--
-- The two-argument version is dropped first, exactly as `0049` dropped the
-- five-argument `record_match_result` before adding a defaulted parameter to
-- it. A default does not replace a signature, it adds an overload -- and
-- leaving both would make the two-argument call every deployed client makes
-- *ambiguous* rather than convenient, which fails at the call rather than here.
-- Dropping it means that call resolves to the function below with
-- `p_from_generation => false`.
drop function if exists public.replace_match_lineup(uuid, jsonb);

create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb,
  p_from_generation boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_ids uuid[];
  v_payload_guest_ids uuid[];
  v_surviving_guest_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_assignments is null or jsonb_typeof(p_assignments) <> 'array' then
    v_user_ids := array[]::uuid[];
    v_payload_guest_ids := array[]::uuid[];
  else
    select
      coalesce(array_agg((a->>'user_id')::uuid)
               filter (where nullif(a->>'user_id', '') is not null),
               array[]::uuid[]),
      coalesce(array_agg((a->>'professional_guest_id')::uuid)
               filter (where nullif(a->>'professional_guest_id', '') is not null),
               array[]::uuid[])
      into v_user_ids, v_payload_guest_ids
      from jsonb_array_elements(p_assignments) as a;
  end if;

  -- ADDED (0058): a generation is a fresh search, and `BTGE-MO-2` makes it
  -- discard what was adjusted around the teams it replaces. The sides chosen
  -- for the guests are such an adjustment, so they are given up here -- before
  -- the alternation below runs, so it places every guest again.
  --
  -- Only here. An ordinary manual save passes false and every chosen side
  -- stands, which is the whole distinction this argument exists to draw.
  if p_from_generation then
    update match_team_assignments
       set team_manually_overridden = false
     where match_id = p_match_id
       and professional_guest_id is not null
       and team_manually_overridden;
  end if;

  -- No guest is ever removed here, so every guest currently in the lineup
  -- survives, along with any the payload adds.
  select coalesce(array_agg(distinct a.professional_guest_id), array[]::uuid[])
    into v_surviving_guest_ids
    from match_team_assignments a
    where a.match_id = p_match_id and a.professional_guest_id is not null;
  v_surviving_guest_ids := v_surviving_guest_ids || v_payload_guest_ids;

  -- Refused before anything is written, so a rejected edit leaves the stored
  -- lineup and its effects exactly as they were.
  perform assert_result_survives_lineup(
    p_match_id, v_user_ids, v_surviving_guest_ids);

  perform detach_match_effects(p_match_id);

  -- The user half is the payload, whole. Clearing it is a user-lineup of
  -- nobody, not a no-op.
  delete from match_team_assignments
  where match_id = p_match_id and user_id is not null;

  -- The guest half only where the payload speaks for it.
  if array_length(v_payload_guest_ids, 1) is not null then
    delete from match_team_assignments
    where match_id = p_match_id
      and professional_guest_id = any(v_payload_guest_ids);
  end if;

  if p_assignments is not null and jsonb_typeof(p_assignments) = 'array' then
    insert into match_team_assignments
      (match_id, user_id, professional_guest_id, team, assigned_position,
       assignment_basis, team_manually_overridden)
    select
      p_match_id,
      nullif(assignment->>'user_id', '')::uuid,
      nullif(assignment->>'professional_guest_id', '')::uuid,
      assignment->>'team',
      assignment->>'assigned_position',
      case
        when nullif(assignment->>'professional_guest_id', '') is not null
        then 'GUEST'
        else assignment->>'assignment_basis'
      end,
      -- ADDED (0058): carried from the payload, so a move or a swap records
      -- that a person chose this side. Absent reads as false, which is what a
      -- client older than this migration means by not sending it.
      coalesce((assignment->>'team_manually_overridden')::boolean, false)
    from jsonb_array_elements(p_assignments) as assignment;
  end if;

  -- The engine has produced the community teams; the guests take alternating
  -- sides around them, in the order they were added -- except the ones a person
  -- has placed, which it now leaves where they are (0050, 0058).
  perform assign_professional_guest_teams(p_match_id);

  perform attach_match_effects(p_match_id);
end;
$$;

-- The two-argument signature is what every deployed client calls today, and
-- PostgREST resolves a call by the arguments it is given. A default parameter
-- keeps that call working -- it resolves to this same function with
-- `p_from_generation => false` -- so nothing needs to be deployed in step with
-- this migration, and no old client can clear an override by accident.
revoke execute on function
  public.replace_match_lineup(uuid, jsonb, boolean) from anon, public;
grant execute on function
  public.replace_match_lineup(uuid, jsonb, boolean) to authenticated;
