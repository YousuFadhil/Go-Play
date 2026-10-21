-- ============================================================================
-- 0107 -- Drag-to-swap on the pitch: a stored order inside each line
-- ============================================================================
-- Inside a line (a team's DEF, MID or FWD) the pitch has always ordered players
-- by display name, and that alone decided who is drawn on the right, in the
-- centre and on the left. Nothing was stored, so an organizer could not move
-- the right-side defender to the left, and a swap could not put two players in
-- each other's exact place. This migration stores that order. The Teams screen
-- writes it for a side swap (two players of one line), and after a position or
-- cross-team swap for the line(s) the two players arrived in.
--
--   1. `match_team_assignments.line_order` -- nullable, NULL for every existing
--      row, so every lineup renders exactly as before (by name) until somebody
--      swaps. Within a line the pitch sorts by it first, NULLs last, then by
--      name.
--   2. `set_match_lineup_line_order` -- the only writer. The client sends the
--      whole line (match + team + position) in its new order; the set must be
--      exactly the line's current members, and 1..n is written. Same audience
--      as every other lineup edit (`is_match_community_admin`, i.e.
--      `has_community_role(..., 'admin')`), on upcoming AND completed matches.
--      Presentation only: no rating or statistics effect is detached or
--      reattached, and `assignment_basis` / `team_manually_overridden` are not
--      touched.
--   3. Reset, in the database, whenever a player's team or position changes:
--        * a BEFORE UPDATE trigger clears `line_order` when `team` or
--          `assigned_position` changes -- every UPDATE path (guest
--          alternation, completed-match corrections, merges) is covered;
--        * `replace_match_lineup` deletes and re-inserts, so it now carries a
--          row's order across only when the participant keeps the same team
--          and position, and never on a generation (`p_from_generation`),
--          which is a fresh lineup. Every manual edit and regeneration of the
--          app goes through it (`save_generated_lineup_v1` calls it too).
--      A participant who is new to a line arrives with NULL and is drawn after
--      the ordered ones.
--   4. `advance_match_participation_revision` ignores an UPDATE that changes
--      only `line_order` (and the `updated_at` it stamps): who played did not
--      change, so the participation evidence (0088) must not advance -- nor be
--      auto-confirmed on a completed match by a side swap.
--   5. The read models that draw a match pitch return the order:
--      `v_football_match_lineup` (completed match, share card) gains the column
--      at the end, and `public_match_lineup` (public /match link) is recreated
--      with it -- a changed result type cannot be `create or replace`d.
--
-- Backward compatible: the deployed client selects named columns and maps
-- RPC rows by key, so an added column changes nothing for it, and nothing it
-- calls behaves differently on today's data.
-- ============================================================================


-- 1) The column ----------------------------------------------------------------

alter table public.match_team_assignments
  add column line_order smallint
    check (line_order is null or line_order >= 1);

comment on column public.match_team_assignments.line_order is
  'Order inside the line (same match, team and assigned_position), 1 first. '
  'NULL = no stored order: the pitch falls back to the name. Presentation '
  'only; cleared when the team or position changes -- see migration 0107.';


-- 2) Reset on a change of team or position -------------------------------------

create or replace function public.reset_lineup_line_order()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.team is distinct from old.team
     or new.assigned_position is distinct from old.assigned_position then
    new.line_order := null;
  end if;
  return new;
end;
$$;

revoke execute on function public.reset_lineup_line_order()
  from public, anon, authenticated;

create trigger match_team_assignments_reset_line_order
before update on public.match_team_assignments
for each row execute function public.reset_lineup_line_order();


-- 3) Participation evidence ignores an order-only update -----------------------
-- The 0101 body, unchanged except for the early return marked NEW (0107) and
-- the `pg_temp` in the search path. Privileges are kept by `create or replace`.

create or replace function public.advance_match_participation_revision()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match_id uuid;
  v_community_id uuid;
  v_status text;
  v_end_at timestamptz;
  v_revision bigint;
  v_actor uuid;
begin
  -- NEW (0107): the order inside a line is presentation, not participation.
  -- An update that changes nothing but `line_order` (and the `updated_at` the
  -- other trigger stamps) leaves the evidence exactly as it was.
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'line_order' - 'updated_at')
       = (to_jsonb(old) - 'line_order' - 'updated_at') then
    return new;
  end if;

  -- (0101) Account merge. A merge moves the two accounts' own rows and must not
  -- invent history for them: see merge_skips_lifecycle(). Rows of anybody else, and
  -- every change made outside a merge, are handled exactly as before.
  if public.merge_skips_lifecycle(
       case when tg_op = 'DELETE' then old.user_id else new.user_id end) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select m.community_id, m.status, m.end_at
  into v_community_id, v_status, v_end_at
  from public.matches m
  where m.id = v_match_id;

  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  insert into public.match_participation_state (
    match_id,
    lineup_revision
  )
  values (v_match_id, 1)
  on conflict (match_id) do update
    set lineup_revision =
      public.match_participation_state.lineup_revision + 1
  returning lineup_revision into v_revision;

  v_actor := auth.uid();

  if (v_status = 'completed' or v_end_at <= now())
     and v_actor is not null
     and public.has_active_community_role(
       v_community_id,
       v_actor,
       'admin'
     )
  then
    update public.match_participation_state
    set confirmed_revision = v_revision,
        confirmed_at = now(),
        confirmed_by = v_actor
    where match_id = v_match_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;


-- 4) replace_match_lineup carries the order of an unchanged row ----------------
-- The 0071 body, unchanged except for the parts marked NEW (0107) and the
-- `pg_temp` in the search path. Same signature, so `create or replace` keeps
-- its privileges (authenticated, as 0071 stated them).

create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb,
  p_from_generation boolean default false,
  p_completed_correction boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match matches%rowtype;
  v_completed boolean;
  v_user_ids uuid[];
  v_payload_guest_ids uuid[];
  v_surviving_guest_ids uuid[];
  v_previous_order jsonb;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- CHANGED (0071): the locked row is read rather than merely locked, because
  -- the guard below tests its `status` and `end_at`. The lock, the ordering
  -- and the MATCH_NOT_FOUND that follows it are exactly as they were.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  -- Added by migration 0065: a suspended community is frozen for new activity.
  if not exists (
    select 1 from matches m
    join communities c on c.id = m.community_id
    where m.id = p_match_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- NEW (0071): the intent guard ------------------------------------------------
  -- Placed after authorization so a caller with no business here still gets
  -- NOT_AUTHORIZED rather than being told about the match's state, and before
  -- every mutation -- the guest-override clearing, the result assertion, the
  -- detach, the deletes, the insert, the guest alternation and the reattach --
  -- so a refused write leaves the stored lineup and its effects exactly as
  -- they were.
  --
  -- Completion is the product's existing rule, the one `0029` tests and
  -- `v_completed_matches` (0037) projects: the stored status **or** the clock.
  -- Reading it from the locked row is what makes the answer stable for the
  -- rest of the transaction.
  v_completed := v_match.status = 'completed' or v_match.end_at <= now();

  -- `coalesce`, because these arrive from a client and a NULL is not a false:
  -- `if p_completed_correction then` would be unknown rather than true, and
  -- `if not p_completed_correction then` unknown rather than the refusal it
  -- has to be. A null intent is no intent, which is the ordinary case.
  if v_completed then
    -- A generation is never a correction, and saying both does not make it
    -- one. Tested first so the combination is refused on its own terms rather
    -- than admitted by the correction flag beside it.
    if coalesce(p_from_generation, false) then
      raise exception 'MATCH_COMPLETED';
    end if;

    -- An ordinary write onto a played match. This is the case the product was
    -- silently allowing.
    if not coalesce(p_completed_correction, false) then
      raise exception 'MATCH_COMPLETED';
    end if;
  else
    -- The mirror, and it matters as much: a caller must not label a live or
    -- future lineup write as historical correction. If that were tolerated,
    -- "correction" would become a flag clients set by habit, and the guard
    -- above would be protecting nothing within a release or two.
    if coalesce(p_completed_correction, false) then
      raise exception 'MATCH_NOT_COMPLETED';
    end if;
  end if;
  -- END OF THE INTENT GUARD -----------------------------------------------------

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

  -- A generation is a fresh search, and `BTGE-MO-2` makes it discard what was
  -- adjusted around the teams it replaces (0058). CHANGED (0059): the position
  -- an organizer chose for a guest is such an adjustment too, so it is given up
  -- with the side and the guest goes back to `0051`'s normal representation.
  --
  -- Only here. An ordinary manual save passes false and keeps both.
  if p_from_generation then
    update match_team_assignments
       set team_manually_overridden = false,
           assigned_position = null
     where match_id = p_match_id
       and professional_guest_id is not null
       and (team_manually_overridden or assigned_position is not null);
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

  -- NEW (0107): the order inside each line, read before the rows are deleted.
  -- A row re-inserted below keeps it only when the participant is on the same
  -- team at the same position; anybody who moved starts again from NULL. A
  -- generation is a fresh lineup and keeps none.
  select coalesce(jsonb_agg(jsonb_build_object(
           'participant_id', coalesce(a.user_id, a.professional_guest_id),
           'team', a.team,
           'assigned_position', a.assigned_position,
           'line_order', a.line_order)), '[]'::jsonb)
    into v_previous_order
    from match_team_assignments a
    where a.match_id = p_match_id and a.line_order is not null;

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
       assignment_basis, team_manually_overridden, line_order)
    select
      p_match_id,
      nullif(assignment->>'user_id', '')::uuid,
      nullif(assignment->>'professional_guest_id', '')::uuid,
      assignment->>'team',
      assignment->>'assigned_position',
      -- A row naming a guest is `GUEST`, whatever the payload says and whatever
      -- position it carries. The basis answers §5.1's question about a profile,
      -- and a guest has none -- which a position for this match does not
      -- change.
      case
        when nullif(assignment->>'professional_guest_id', '') is not null
        then 'GUEST'
        else assignment->>'assignment_basis'
      end,
      coalesce((assignment->>'team_manually_overridden')::boolean, false),
      -- NEW (0107): see above.
      case when not coalesce(p_from_generation, false) then (
        select (prev->>'line_order')::smallint
          from jsonb_array_elements(v_previous_order) as prev
         where prev->>'participant_id' = coalesce(
                 nullif(assignment->>'user_id', ''),
                 nullif(assignment->>'professional_guest_id', ''))
           and prev->>'team' = assignment->>'team'
           and prev->>'assigned_position' = assignment->>'assigned_position'
         limit 1)
      end
    from jsonb_array_elements(p_assignments) as assignment;
  end if;

  -- The engine has produced the community teams; the guests take alternating
  -- sides around them, in the order they were added -- except the ones a person
  -- has placed, which it leaves where they are (0050, 0058).
  perform assign_professional_guest_teams(p_match_id);

  perform attach_match_effects(p_match_id);
end;
$$;


-- 5) The one writer of the order -----------------------------------------------

create or replace function public.set_match_lineup_line_order(
  p_match_id uuid,
  p_team text,
  p_assigned_position text,
  p_participant_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_line uuid[];
begin
  -- The same gates, in the same order, as `replace_match_lineup`.
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- The lock every lineup writer takes, so a reorder never interleaves with a
  -- replace of the same lineup.
  perform 1 from public.matches m where m.id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not exists (
    select 1 from public.matches m
    join public.communities c on c.id = m.community_id
    where m.id = p_match_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- No intent guard: the order is presentation, so it is written the same way
  -- before and after the final whistle, and no match effect is detached or
  -- reattached.

  if p_team is null or p_team not in ('A', 'B') then
    raise exception 'INVALID_TEAM';
  end if;
  if p_assigned_position is null
     or p_assigned_position not in ('GK', 'DEF', 'MID', 'FWD') then
    raise exception 'INVALID_POSITION';
  end if;

  select coalesce(array_agg(coalesce(a.user_id, a.professional_guest_id)),
                  array[]::uuid[])
    into v_line
    from public.match_team_assignments a
   where a.match_id = p_match_id
     and a.team = p_team
     and a.assigned_position = p_assigned_position;

  -- Exactly the line as it is stored now: every member once, nobody else. A
  -- line that changed since the client read it is refused rather than half
  -- applied.
  if p_participant_ids is null
     or cardinality(v_line) = 0
     or array_position(p_participant_ids, null) is not null
     or cardinality(p_participant_ids) <> cardinality(v_line)
     or (select count(distinct id) from unnest(p_participant_ids) as id)
          <> cardinality(p_participant_ids)
     or not (p_participant_ids <@ v_line and v_line <@ p_participant_ids) then
    raise exception 'ROSTER_MISMATCH';
  end if;

  update public.match_team_assignments a
     set line_order = o.ord::smallint
    from unnest(p_participant_ids) with ordinality as o(participant_id, ord)
   where a.match_id = p_match_id
     and a.team = p_team
     and a.assigned_position = p_assigned_position
     and coalesce(a.user_id, a.professional_guest_id) = o.participant_id;
end;
$$;

comment on function public.set_match_lineup_line_order(uuid, text, text, uuid[]) is
  'Stores the order of one line (match, team, assigned position): the given '
  'participant ids, which must be exactly the line''s members, become 1..n. '
  'Admins of the match''s community, upcoming and completed matches alike; '
  'presentation only -- see migration 0107.';

revoke all on function
  public.set_match_lineup_line_order(uuid, text, text, uuid[]) from public, anon;
grant execute on function
  public.set_match_lineup_line_order(uuid, text, text, uuid[])
  to authenticated, service_role;


-- 6) The read models return the order ------------------------------------------
-- `v_football_match_lineup`: the 0073 definition, with `line_order` appended as
-- the last column (which `create or replace view` allows). It keeps its owner,
-- its privileges and its default (non-invoker) security.

create or replace view public.v_football_match_lineup as
select
  a.match_id,
  m.community_id,
  a.team,
  a.assigned_position,
  a.assignment_basis,
  (a.assignment_basis = 'TRANSITION')             as is_out_of_position,
  case when a.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end        as participant_type,
  a.user_id,
  a.professional_guest_id,
  coalesce(u.full_name, g.display_name)           as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  coalesce(gl.goals, 0)                           as goals,
  coalesce(
    (r.mvp_user_id is not null and r.mvp_user_id = a.user_id)
    or (r.mvp_professional_guest_id is not null
        and r.mvp_professional_guest_id = a.professional_guest_id),
    false)                                        as is_mvp,
  a.line_order
from public.match_team_assignments a
join public.matches m     on m.id = a.match_id
join public.communities c on c.id = m.community_id and c.is_active
left join public.users u                     on u.id = a.user_id
left join public.match_professional_guests g on g.id = a.professional_guest_id
left join public.match_goals gl
  on gl.match_id = a.match_id
 and ((gl.user_id is not null and gl.user_id = a.user_id)
   or (gl.professional_guest_id is not null
       and gl.professional_guest_id = a.professional_guest_id))
left join public.match_results r on r.match_id = a.match_id
where m.status = 'completed' or m.end_at <= now();

-- `public_match_lineup`: the 0079 function with `line_order` added to its
-- result. A different result type needs a drop; the privileges 0079 stated are
-- stated again below.
drop function public.public_match_lineup(uuid);

create function public.public_match_lineup(p_match_id uuid)
returns table (
  team text,
  assigned_position text,
  participant_type text,
  display_name text,
  avatar_path text,
  goals int,
  is_mvp boolean,
  player_id uuid,
  line_order smallint
)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select
    l.team,
    l.assigned_position,
    l.participant_type,
    l.display_name,
    l.avatar_path,
    l.goals::int,
    l.is_mvp,
    case when l.user_id is not null and u.is_active then l.user_id end,
    l.line_order
  from public.v_football_match_lineup l
  left join public.users u on u.id = l.user_id
  where l.match_id = p_match_id
  order by l.team, l.display_name;
$$;

comment on function public.public_match_lineup(uuid) is
  'The lineup of a completed match in an active community, for the /match/{id} '
  'link: side, position, name, picture, goals, MVP, a player_id only for a '
  'registered player whose public profile is available, and the order inside '
  'the line (0107). Upcoming matches return nothing -- see migration 0079.';

revoke execute on function public.public_match_lineup(uuid) from public;
grant execute on function public.public_match_lineup(uuid)
  to anon, authenticated, service_role;
