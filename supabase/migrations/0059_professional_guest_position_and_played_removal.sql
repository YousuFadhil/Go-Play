-- ============ migrations/0059_professional_guest_position_and_played_removal.sql ============
-- Two more things an organizer can say about a Professional Guest from the
-- Teams screen: where they played, and that they did not play after all.
--
-- ## Where they played needs no schema change
--
-- Migration `0051` already settled this and this migration does not revisit it:
--
--     check (assigned_position is null
--            or assigned_position in ('GK', 'DEF', 'MID', 'FWD'))
--     check (user_id is null or assigned_position is not null)
--
-- A *user* must carry a position; a guest may carry one or carry none. So a
-- guest at MID is already a legal row, and `replace_match_lineup` already
-- writes whatever the payload says while forcing `assignment_basis` to `GUEST`
-- for any row naming a guest. Nothing about the position is new here.
--
-- What the position is **not** is equally unchanged: no primary or secondary is
-- written anywhere, no rating exists, and `fetchConfirmedPlayerInputs` still
-- selects `user_id is not null`, so a guest with a position is no more an
-- engine input than a guest without one.
--
-- ## What Generate gives back
--
-- `0058` made Generate a fresh search for the guests' **sides**: it clears
-- `team_manually_overridden` so the A/B alternation places them again.
-- `BTGE-MO-2` says the same thing about every manual adjustment, and a position
-- an organizer chose for a guest is one. So the same block gives it up as well,
-- and the guest returns to the representation `0051` calls normal: a side, and
-- nothing claiming to know where on the pitch they stood.
--
-- Only on a generation. An ordinary manual save keeps both, which is what makes
-- a chosen position survive a later move, a swap, or a community player being
-- rearranged.
--
-- ## Removing a guest from a played match is a different question
--
-- `remove_professional_guest` (0047) is deliberately **not** the function for
-- this, and wiring the Teams button to it would have been wrong in a way that
-- is easy to miss. It answers "take them off the roster", and it answers it by
-- keeping the lineup row, the goals and the MVP:
--
--     the seat in match_registrations  -- always removed
--     the lineup row, goals, MVP       -- kept whenever they exist
--
-- That is right for the roster screen. On a played match the lineup row is the
-- record of who was on the pitch, and losing it would leave the match unable to
-- say who played. So calling it from Teams would take a guest off the roster
-- and leave them standing on the pitch.
--
-- The Teams screen means the opposite: **this guest did not actually play**. So
-- that gets its own function, and `remove_professional_guest` keeps its
-- approved semantics untouched.
--
-- ## It refuses rather than editing a result
--
-- If the guest scored, the removal is refused. It is not made possible by
-- deleting their goals, and it is not made possible by changing the score:
-- `sum(goals) = final score` is the invariant the whole guest-goal feature
-- exists to keep strict, and a removal that quietly broke or "fixed" it would
-- be the one thing that could not be undone from the screen.
--
-- The refusal is not new vocabulary. `assert_result_survives_lineup` (0029,
-- 0044) is the guard every other lineup edit already passes through, it already
-- knows about guest scorers and a guest MVP, and it already raises
-- `RESULT_PARTICIPANT_REMOVED` -- which the failure mapper maps and the Teams
-- screen already words. Asking it is both the smallest implementation and the
-- one that cannot drift from the rule the rest of the lineup obeys.
--
-- No `detach_match_effects` / `attach_match_effects`. Migration `0046` made a
-- guest contribute to no rating, no player counter and no community figure, so
-- there is nothing of theirs to take back -- reversal logic here would be
-- reversing something that was never applied.
--
-- ## Forward-only
--
-- One new function and one replaced function. No table is altered, no column
-- added or dropped, no constraint or policy touched, and `0058` is not
-- rewritten -- `replace_match_lineup` is restated from `0058`'s definition with
-- one statement extended.

-- 1) Generate gives back the chosen position as well as the chosen side --------------
-- `0058`'s body, with the reset block extended by one column. Everything else
-- is statement for statement as `0058` left it.
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

revoke execute on function
  public.replace_match_lineup(uuid, jsonb, boolean) from anon, public;
grant execute on function
  public.replace_match_lineup(uuid, jsonb, boolean) to authenticated;

-- 2) This guest did not play after all ------------------------------------------------
-- The Teams correction. `remove_professional_guest` is untouched and still
-- means what it meant: the roster seat, keeping the record.
create or replace function public.remove_played_professional_guest(
  p_match_id uuid,
  p_guest_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_user_ids uuid[];
  v_guest_ids uuid[];
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- Both halves, as `remove_professional_guest` asks them: the guest must
  -- exist, and must belong to *this* match. A guest is match-scoped, so an id
  -- from another match is not one this caller may name.
  if not exists (
    select 1 from match_professional_guests
    where id = p_guest_id and match_id = p_match_id
  ) then
    raise exception 'GUEST_NOT_FOUND';
  end if;

  -- The lineup as it would be with this guest taken out of it, asked of the
  -- same guard every other lineup edit passes through. It raises
  -- `RESULT_PARTICIPANT_REMOVED` when the guest scored or was named best on the
  -- pitch, and it does so **before** anything is written, so a refused removal
  -- changes no goal, no score and no lineup.
  select
    coalesce(array_agg(a.user_id) filter (where a.user_id is not null),
             array[]::uuid[]),
    coalesce(array_agg(a.professional_guest_id)
             filter (where a.professional_guest_id is not null
                       and a.professional_guest_id <> p_guest_id),
             array[]::uuid[])
    into v_user_ids, v_guest_ids
    from match_team_assignments a
    where a.match_id = p_match_id;

  perform assert_result_survives_lineup(p_match_id, v_user_ids, v_guest_ids);

  -- They did not play: the lineup row goes, which is the whole of what this
  -- says and the whole of what `remove_professional_guest` will not do.
  delete from match_team_assignments
  where match_id = p_match_id and professional_guest_id = p_guest_id;

  -- And they hold no seat either. A guest who did not play is not somebody the
  -- roster is still expecting.
  delete from match_registrations
  where match_id = p_match_id and professional_guest_id = p_guest_id;

  -- The identity goes only when nothing points at it any more. The goals and
  -- the MVP are the two things that can, and reaching here means the guard
  -- found neither -- but it is asked rather than assumed, so a future change to
  -- the guard cannot quietly start orphaning a record. The `on delete no
  -- action` references migration `0044` puts on those tables refuse it outright
  -- either way.
  if not exists (
    select 1 from match_goals
    where match_id = p_match_id and professional_guest_id = p_guest_id
  ) and not exists (
    select 1 from match_results
    where match_id = p_match_id and mvp_professional_guest_id = p_guest_id
  ) then
    delete from match_professional_guests
    where id = p_guest_id and match_id = p_match_id;
  end if;

  -- No `detach_match_effects` / `attach_match_effects`: migration `0046` gives
  -- a guest no rating, no player counter and no community figure, so there is
  -- nothing of theirs to take back.
  --
  -- No `rebalance_roster` on a played match either, for the reason `0047`
  -- gives: there is no reserve to promote out of, and re-cutting the roster
  -- would rewrite the record of a match that has already happened. On a match
  -- still to come the roster screen's own removal is the path, and this one is
  -- offered only where the correction makes sense.
  if not (v_match.status = 'completed' or v_match.end_at <= now()) then
    perform rebalance_roster(p_match_id);
  end if;

  -- The guests left behind re-alternate around whoever is still starting, which
  -- is `assign_professional_guest_teams`'s own rule and not this function's.
  perform assign_professional_guest_teams(p_match_id);
  perform recompute_match_status(p_match_id);
end;
$$;

revoke execute on function
  public.remove_played_professional_guest(uuid, uuid) from anon, public;
grant execute on function
  public.remove_played_professional_guest(uuid, uuid) to authenticated;
