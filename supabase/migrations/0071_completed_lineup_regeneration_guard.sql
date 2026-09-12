-- ============ migrations/0071_completed_lineup_regeneration_guard.sql ============
-- Generation may not rewrite a match that has already been played.
--
-- ## The hole this closes
--
-- `replace_match_lineup` is one write serving two intents. A generation hands
-- it the engine's fresh teams; a manual adjustment hands it the stored lineup
-- with one thing moved. Migration `0058` taught it to tell those apart --
-- `p_from_generation` decides whether a guest's manually chosen side is given
-- up -- but neither intent was ever tested against *when* the match is.
--
-- So an organizer looking at a completed match was still offered Regenerate,
-- and taking it would replace the record of who actually played with a fresh
-- proposal about who might have. Everything downstream reads that record as
-- history: the result survives it, the ratings are detached and reattached
-- around it, and the Team of Period award (migration `0070`) is calculated
-- from it. A regeneration after the fact is not an edit to a plan; it is a
-- rewrite of what happened.
--
-- ## Three intents, and only the third may touch a completed match
--
--   A. **Generation / regeneration.** The engine proposing teams. Allowed only
--      while the match is not completed. Never a correction, however it is
--      labelled.
--   B. **Ordinary pre-completion adjustment.** Moving, swapping, repositioning
--      before the match is over. Unchanged.
--   C. **Explicit completed-match correction.** An owner or admin fixing the
--      factual record of who played, which side they were on and where they
--      stood. Still allowed, and now it has to say so.
--
-- The distinction cannot be inferred from the payload. A correction and a
-- regeneration can produce byte-identical assignments; what separates them is
-- what the caller meant, so the caller states it and the database holds them
-- to it.
--
-- ## The signature, and why the old one is dropped
--
-- The two-argument version was dropped by `0058` for this exact reason and this
-- migration does the same to the three-argument one: a default does not replace
-- a signature, it adds an overload, and leaving both would make every deployed
-- three-argument call *ambiguous* rather than convenient -- failing at the call
-- site rather than here.
--
-- Dropping it means old two- and three-argument clients resolve to the function
-- below with `p_completed_correction => false`. That is deliberate and it is
-- the safe direction: an obsolete client can still do everything it could do
-- before **except** rewrite a completed match, which is the thing it had no
-- business doing. Integrity wins over letting a stale build correct history.
--
-- ## What is not changed
--
-- The body below is `0065`'s, verbatim, apart from two mechanical changes the
-- guard requires: the locked row is now read into a variable so its `status`
-- and `end_at` can be tested, and the guard itself is inserted after
-- authorization and before anything is written. Guest preservation, the
-- `team_manually_overridden` clearing, `assert_result_survives_lineup`, the
-- detach/attach of match effects, the payload identity split, the guest
-- alternation and the atomic replacement are untouched.
--
-- No table, no trigger, no persisted state, no new helper and no new error
-- token: `MATCH_COMPLETED` and `MATCH_NOT_COMPLETED` are the vocabulary
-- `0006` and `0029` already established and the client already maps.

drop function if exists public.replace_match_lineup(uuid, jsonb, boolean);

create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb,
  p_from_generation boolean default false,
  p_completed_correction boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_completed boolean;
  v_user_ids uuid[];
  v_payload_guest_ids uuid[];
  v_surviving_guest_ids uuid[];
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
      -- A row naming a guest is `GUEST`, whatever the payload says and whatever
      -- position it carries. The basis answers §5.1's question about a profile,
      -- and a guest has none -- which a position for this match does not
      -- change.
      case
        when nullif(assignment->>'professional_guest_id', '') is not null
        then 'GUEST'
        else assignment->>'assignment_basis'
      end,
      coalesce((assignment->>'team_manually_overridden')::boolean, false)
    from jsonb_array_elements(p_assignments) as assignment;
  end if;

  -- The engine has produced the community teams; the guests take alternating
  -- sides around them, in the order they were added -- except the ones a person
  -- has placed, which it leaves where they are (0050, 0058).
  perform assign_professional_guest_teams(p_match_id);

  perform attach_match_effects(p_match_id);
end;
$$;

comment on function
  public.replace_match_lineup(uuid, jsonb, boolean, boolean) is
  'Replaces a match lineup atomically. Generation (p_from_generation) and '
  'explicit historical correction (p_completed_correction) are distinct '
  'intents and the caller states which: a completed match -- status '
  'completed OR end_at passed -- accepts a write only when it is declared a '
  'correction and is not a generation, and an uncompleted match refuses a '
  'write declared a correction. Both refusals happen before any mutation. '
  'MATCH_COMPLETED and MATCH_NOT_COMPLETED are the existing vocabulary. Old '
  'two- and three-argument clients default to p_completed_correction => '
  'false and are therefore blocked from completed matches by design -- see '
  'migration 0071.';

-- The drop above took the function's privileges with it, so they are stated
-- again rather than inherited: `create or replace` would have kept them, and a
-- dropped-and-recreated function starts with PostgreSQL's default of EXECUTE
-- for PUBLIC. Same audience as before -- `0058` set exactly this.
revoke execute on function
  public.replace_match_lineup(uuid, jsonb, boolean, boolean) from anon, public;
grant execute on function
  public.replace_match_lineup(uuid, jsonb, boolean, boolean) to authenticated;
