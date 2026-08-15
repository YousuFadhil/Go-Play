-- Two rules the client cannot own: where a Professional Guest plays, and when a
-- lineup stops being true.
--
-- ## Why this is server-side at all
--
-- The Balanced Team Generation Engine is pure Dart and runs on the device. The
-- database cannot call it and this migration does not try to: **no community
-- player is placed here, and no engine input changes.** What the database *can*
-- own is everything the engine has no opinion about —
--
--   * a Professional Guest is not an engine input (§4.1 has no inputs to read
--     for somebody with no profile), so where they play is not the engine's
--     decision. It is a roster rule, and roster rules live here.
--   * whether a stored lineup still describes the current roster is a fact
--     about two tables, which is a question only the database can answer at the
--     moment the roster changes.
--
-- ## Rule 1 — guests alternate A, B, A, B
--
-- Ordered by when they were added, the starting guests take alternating sides.
-- `match_registrations.registration_order` is that order: it is one per-match
-- sequence shared with community registrations and assigned when the guest is
-- added, so the first guest added always has the lowest value.
--
-- Re-run whenever the roster or the lineup changes, so the alternation is a
-- property of the current state and not of the order operations happened in. A
-- guest removed from the middle re-alternates everyone after them, which is
-- what "distributed alternately" means once the set has changed.
--
-- ## Rule 2 — a lineup that no longer describes the roster is cleared
--
-- Stated as a **set comparison, not a count**: the lineup is stale when the
-- users in it are not exactly the confirmed community players. That is stricter
-- than "the number changed" — it also catches one player replacing another —
-- and it makes the rule self-correcting rather than dependent on catching every
-- mutation in the act.
--
-- It also settles the case the approved rules single out: a guest moving
-- between starting and reserve leaves the community set untouched, so nothing
-- is regenerated and the engine is not re-run. Only a change to the confirmed
-- **community** players clears the lineup.
--
-- Clearing is the whole of "regenerate". The database cannot produce the new
-- community teams, so it removes the stale ones and leaves the match with no
-- lineup; the next generation on the client is the regeneration, and the guests
-- are re-placed around it by rule 1. What this guarantees is the part that was
-- missing: **no stale lineup survives a change to the starting community
-- players.**
--
-- ## Where it hooks in
--
-- `recompute_match_status` is called by every roster-mutating RPC in the schema
-- — registration, withdrawal, removal, membership purge, match edit, and both
-- guest operations — and it already returns early for a match that has been
-- played. It is the one place that sees every roster change, which is why the
-- reconciliation is invoked from there rather than added to seven call sites
-- where the eighth would eventually be forgotten.
--
-- Idempotent: `create or replace` throughout. No table, column, constraint,
-- index, policy or grant changes.

-- 1) Where a Professional Guest plays ---------------------------------------------
-- Alternating sides for the **starting** guests, in the order they were added.
--
-- Three things this deliberately does not do:
--
--   * it does not place a guest when no community lineup exists. Guests are
--     added *after* the engine has run; a lineup of guests alone would be a
--     lineup nobody generated, and `record_match_result` would accept it as the
--     record of a match that was never picked.
--   * it does not keep a reserve guest on the pitch. A reserve is not part of
--     the playing teams, so their lineup row is removed when they lose their
--     seat and rebuilt when they get it back.
--   * it does not touch a match whose result is recorded. A played lineup is a
--     record: re-alternating it would move somebody after the fact, and could
--     take the recorded MVP or a scorer off the pitch they scored on.
--
-- `assigned_position` is `MID` for a guest this function places, and an existing
-- position is never overwritten — only the side is. MID is the neutral choice:
-- it is the one position with no structural consequence, where GK is limited to
-- one per team by `match_team_assignments_one_gk_idx`. No approved rule states a
-- position for a guest, so this is an assumption and is reported as one.
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
      'MID',
      'GUEST'
    )
    on conflict (match_id, professional_guest_id)
      where professional_guest_id is not null
    do update set team = excluded.team;
  end loop;
end;
$$;

revoke execute on function public.assign_professional_guest_teams(uuid)
  from anon, authenticated, public;

-- 2) When a lineup stops being true -------------------------------------------------
-- Clears the stored lineup when it no longer describes the confirmed community
-- roster, then re-places the guests around whatever is left.
--
-- The two `except` halves are the comparison in both directions: a confirmed
-- player missing from the lineup, or somebody in the lineup who is no longer
-- confirmed. Either makes the lineup a description of a roster that has moved
-- on, and the approved rule is that it is regenerated completely rather than
-- patched.
--
-- Guests are excluded from the comparison on purpose. Their coming and going is
-- governed by rule 1, which runs on every call regardless — a guest moving
-- between starting and reserve must not re-run the engine, and this is where
-- that is guaranteed.
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
    if v_stale then
      delete from match_team_assignments where match_id = p_match_id;
    end if;
  end if;

  perform assign_professional_guest_teams(p_match_id);
end;
$$;

revoke execute on function public.reconcile_match_lineup(uuid)
  from anon, authenticated, public;

-- 3) The one call site ----------------------------------------------------------------
-- Migration `0006`'s function, with one statement added.
--
-- Every roster-mutating RPC already ends here — `register_player_in_match`,
-- `withdraw_from_match`, `remove_player`, `purge_membership`, `update_match`,
-- `add_professional_guest` and `remove_professional_guest` — which is what makes
-- this the right place for a rule that has to hold after *any* of them.
--
-- The early return for a played match is unchanged and is doing real work here:
-- a match that has finished keeps its lineup, its sides and its record, and
-- nothing below runs for one.
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

  -- ADDED (0050): the roster has just changed, so the lineup is checked against
  -- it and the guests are re-alternated. A no-op when no lineup is stored and
  -- when the community set is unchanged.
  perform reconcile_match_lineup(p_match_id);
end;
$$;

revoke execute on function public.recompute_match_status(uuid)
  from anon, authenticated, public;

-- 4) Guests are placed after the engine has run ------------------------------------------
-- Migration `0044`'s function, with one statement added at the end.
--
-- This is the exact boundary the approved BTGE rule asks for. The client
-- generates teams for the **confirmed community players only** — the engine
-- never sees a guest, because `fetchConfirmedPlayerInputs` filters on
-- `user_id is not null` — and saves that lineup through here. The guests are
-- then placed around it, by the database, after the engine has finished.
--
-- Nothing about the community half changes: the payload is still the whole user
-- lineup, guests named in it are still replaced and guests absent from it are
-- still preserved, and the detach/attach pair still surrounds the write. The
-- added call sits inside that pair so the alternation lands in the same
-- transaction as the lineup it alternates against.
create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb
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
       assignment_basis)
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
      end
    from jsonb_array_elements(p_assignments) as assignment;
  end if;

  -- ADDED (0050): the engine has produced the community teams; the guests take
  -- alternating sides around them, in the order they were added.
  perform assign_professional_guest_teams(p_match_id);

  perform attach_match_effects(p_match_id);
end;
$$;

revoke execute on function public.replace_match_lineup(uuid, jsonb)
  from anon, public;
grant execute on function public.replace_match_lineup(uuid, jsonb)
  to authenticated;
