-- Replacing a stored lineup, atomically.
--
-- Why this exists: storing a lineup replaces the previous one, and the client
-- did that as two separate PostgREST statements — delete every row for the
-- match, then insert the new set. Those are two transactions. A failure between
-- them leaves the match with no lineup at all, having been told nothing was
-- wrong about the one it destroyed.
--
-- Generation could live with that: it writes a lineup that did not exist a
-- moment earlier, so the window is small and what is at risk is a result the
-- organizer can simply produce again. Manual Override cannot. Every manual
-- edit — a move, a swap, a position change — rewrites the whole lineup, so
-- the same window sits under a routine adjustment of a lineup that matters.
--
-- Scope is deliberately narrow. This makes the existing write atomic and states
-- its authorization; it changes no table, no constraint, and no policy. The
-- rules that decide what a valid lineup is were set by 0018 and still are:
--   * unique (match_id, user_id)          — BTGE-HC-1, BTGE-HC-2
--   * match_team_assignments_one_gk_idx   — BTGE-HC-6
--   * the team, position and basis CHECKs — BTGE-HC-5, §5.1
-- All of them are enforced against the state this function leaves behind, and
-- a breach rolls the whole replacement back rather than half-applying it.

-- 1) The atomic replacement ----------------------------------------------------
-- security definer, so the function's own check is the authorization — the same
-- shape every other RPC in this project uses. The predicate is
-- is_match_community_admin, which is what 0018 already gates the table's
-- insert, update and delete policies on: one rule, read from one place.
--
-- A plpgsql function body is a single transaction. The delete and the insert
-- below therefore either both take effect or neither does, which is the whole
-- point of the change.
create or replace function public.replace_match_lineup(
  p_match_id uuid,
  p_assignments jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  delete from match_team_assignments where match_id = p_match_id;

  -- Clearing a lineup is a lineup of nobody, not a no-op: the delete above is
  -- the whole operation, and there is nothing to insert.
  if p_assignments is null
     or jsonb_typeof(p_assignments) <> 'array'
     or jsonb_array_length(p_assignments) = 0 then
    return;
  end if;

  -- The match is taken from the argument, never from the payload, so a row
  -- cannot name a different match than the one being authorized.
  insert into match_team_assignments
    (match_id, user_id, team, assigned_position, assignment_basis)
  select
    p_match_id,
    (assignment->>'user_id')::uuid,
    assignment->>'team',
    assignment->>'assigned_position',
    assignment->>'assignment_basis'
  from jsonb_array_elements(p_assignments) as assignment;
end;
$$;

revoke execute on function public.replace_match_lineup(uuid, jsonb)
  from anon, public;
grant execute on function public.replace_match_lineup(uuid, jsonb)
  to authenticated;
