-- Professional Guests: the schema.
--
-- A Professional Guest is a **match-scoped temporary participant**. They have no
-- `auth.users` account, no `users` row, no `community_members` row, no profile,
-- no persistent statistics and no rating history. Two guests with the same name
-- in different matches are unrelated records, and so are two guests with the
-- same name in the *same* match.
--
-- The whole feature rests on one boundary, and this migration is where it is
-- drawn:
--
--   * **match-level** tables -- `match_registrations`,
--     `match_team_assignments`, `match_goals`, and the MVP of `match_results` --
--     learn to name either a registered user **or** a guest, never both.
--
--   * **persistent** tables -- `player_statistics`, `rating_history`,
--     `community_statistics` -- are not touched. Their `user_id` stays
--     `NOT NULL` and stays a foreign key to `users`, which is what makes "a
--     guest never earns a career statistic" a property of the schema rather
--     than a rule somebody has to remember. Migration `0046` closes the two
--     projections that could otherwise carry a null across that line.
--
-- There is deliberately **no global Professionals table**, no `user_id` on the
-- guest, and no uniqueness on the name. A guest exists because a match needed a
-- body, and the record ends with the match: `on delete cascade` from `matches`
-- is the whole of the lifecycle.
--
-- Idempotent throughout: `if not exists`, `if exists`, guarded `do` blocks and
-- `create or replace`. A migration file runs in one transaction, so the
-- constraint/index transition in section 3 is atomic -- there is no instant in
-- which a duplicate registration could be written.

-- 1) The guest ------------------------------------------------------------------
-- `created_by` is attribution and never authorization, the same reading
-- `matches.created_by` and `match_results.recorded_by` already get (PD-16). It
-- clears itself when the account goes, so adding a guest can never be the reason
-- a user cannot be deleted.
--
-- `display_name` carries the name and nothing else. The approved presentation --
-- "محترف (Name)" -- is a Flutter concern and is deliberately not stored: a
-- stored prefix would be a second statement of the same thing, free to disagree
-- with the localized one, and it would be wrong the moment the app is read in
-- another language.
--
-- No unique constraint on `(match_id, display_name)`. Two guests called the same
-- thing in one match are two people, and refusing the second would be inventing
-- an identity the product explicitly does not have.
create table if not exists public.match_professional_guests (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  display_name text not null
    check (char_length(trim(display_name)) between 2 and 60),
  created_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- The roster read is always "the guests of this match, in the order they were
-- added". `created_at` is the tie-break a reader expects; the authoritative
-- ordering is `match_registrations.registration_order`, which section 3 gives
-- guests a share of.
create index if not exists match_professional_guests_match_id_idx
  on public.match_professional_guests (match_id, created_at);

comment on table public.match_professional_guests is
  'A match-scoped temporary participant with no account, no membership, no '
  'profile and no persistent statistics. Independent per match: the same name '
  'in another match is an unrelated record. See migration 0044.';

-- 2) Authorization ---------------------------------------------------------------
-- Reading the guests of a match is a member's business, exactly as reading the
-- roster is (`match_registrations_select_community_members`).
--
-- There is no insert, update or delete policy, and that absence is the rule:
-- every write goes through the SECURITY DEFINER RPCs of migration `0047`, which
-- is the same shape `match_registrations` has had since `0004`.
alter table public.match_professional_guests enable row level security;

drop policy if exists "match_professional_guests_select_members"
  on public.match_professional_guests;
create policy "match_professional_guests_select_members"
  on public.match_professional_guests
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

-- 3) Match-level participant identity --------------------------------------------
-- Three tables, one shape:
--
--   user_id                nullable, still -> users
--   professional_guest_id  nullable, -> match_professional_guests
--   CHECK  (user_id is not null) <> (professional_guest_id is not null)
--
-- The check is an exclusive or in the strict sense: exactly one, never both and
-- never neither. Every existing row satisfies it unchanged, because every
-- existing row has a `user_id` and no guest.
--
-- The uniqueness has to change shape with it. `unique (match_id, user_id)` over
-- a nullable column would stop constraining anything useful -- PostgreSQL treats
-- distinct nulls as distinct, so every guest row would pass it and nothing would
-- be said about guests at all. Two partial unique indexes say the two rules
-- separately and completely: one registration per user per match, one per guest
-- per match.
--
-- ## The delete action is not the same on all three, and the difference is the
-- ## whole of "history survives"
--
--   `match_registrations`      ON DELETE CASCADE
--   `match_team_assignments`   ON DELETE NO ACTION
--   `match_goals`              ON DELETE NO ACTION
--
-- A registration is the **current roster** -- a statement about who is expected.
-- It follows the identity, so it cascades.
--
-- A lineup row and a goal are **historical performance** -- statements about what
-- happened. They must outlive a roster change, because a match that has been
-- played is a record and not a plan. Cascading into them would mean that taking
-- a guest off the roster silently deleted the goals they scored, the side they
-- played on, and the participation the completed match needs in order to be
-- displayed at all.
--
-- NO ACTION rather than RESTRICT, deliberately. Both refuse to orphan a row;
-- they differ in *when* they check. RESTRICT is checked immediately and cannot
-- be deferred, so deleting a match -- which cascades into the guests, the lineup
-- and the goals all at once -- could fail depending on the order those cascades
-- happen to run. NO ACTION is checked at the end of the statement, by which time
-- the referencing rows are gone too, so `delete_match` and `purge_match` keep
-- working while an ordinary attempt to delete a guest who played is still
-- refused. The guarantee is the same; only NO ACTION survives the cascade.

do $$
declare
  v_table text;
  v_name  text;
  v_on_delete text;
begin
  foreach v_table in array
    array['match_registrations', 'match_team_assignments', 'match_goals']
  loop
    -- The current roster follows the identity; historical performance does not.
    v_on_delete := case v_table
      when 'match_registrations' then 'cascade'
      else 'no action'
    end;

    -- (a) the participant may now be a guest
    execute format(
      'alter table public.%I alter column user_id drop not null', v_table);

    execute format(
      'alter table public.%I add column if not exists professional_guest_id '
      'uuid references public.match_professional_guests (id) '
      'on delete %s', v_table, v_on_delete);

    -- (b) retire the old unique constraint, found by its columns rather than by
    --     a name this migration would otherwise be guessing at. Sorted on both
    --     sides so declaration order cannot make the match fail.
    select con.conname into v_name
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = v_table
      and con.contype = 'u'
      and (select array_agg(k order by k) from unnest(con.conkey) k)
          = (select array_agg(a.attnum order by a.attnum)
             from pg_attribute a
             where a.attrelid = rel.oid
               and a.attname in ('match_id', 'user_id')
               and not a.attisdropped);

    if v_name is not null then
      execute format('alter table public.%I drop constraint %I',
                     v_table, v_name);
      v_name := null;
    end if;

    -- (c) the two rules, stated separately
    execute format(
      'create unique index if not exists %I on public.%I (match_id, user_id) '
      'where user_id is not null', v_table || '_unique_user_idx', v_table);

    execute format(
      'create unique index if not exists %I '
      'on public.%I (match_id, professional_guest_id) '
      'where professional_guest_id is not null',
      v_table || '_unique_guest_idx', v_table);

    -- (d) exactly one participant, never both, never neither
    execute format(
      'alter table public.%I drop constraint if exists %I',
      v_table, v_table || '_participant_xor');
    execute format(
      'alter table public.%I add constraint %I check ('
      '(user_id is not null) <> (professional_guest_id is not null))',
      v_table, v_table || '_participant_xor');
  end loop;
end $$;

comment on column public.match_registrations.professional_guest_id is
  'Set when this seat belongs to a Professional Guest instead of a registered '
  'user. Exactly one of user_id / professional_guest_id is non-null.';
comment on column public.match_team_assignments.professional_guest_id is
  'Set when this lineup row belongs to a Professional Guest. Exactly one of '
  'user_id / professional_guest_id is non-null.';
comment on column public.match_goals.professional_guest_id is
  'Set when this tally belongs to a Professional Guest. Exactly one of '
  'user_id / professional_guest_id is non-null.';

-- 4) The assignment basis of a guest ----------------------------------------------
-- §5.1 defines `assignment_basis` as *which rule produced the assigned
-- position*: PRIMARY and SECONDARY name the profile field it came from, and
-- TRANSITION is exactly the out-of-position marker.
--
-- A guest has no profile, so none of the three is true of them. Deriving one
-- would be inventing a profile field the product says a guest does not have,
-- and reusing TRANSITION would mark every guest out of position on the pitch --
-- `v_match_teams.is_out_of_position` and `TeamAssignment.outOfPosition` both
-- read that value literally.
--
-- GUEST is therefore a fourth basis meaning "an administrator placed them, and
-- there was no profile to place them against". The existing three keep exactly
-- the semantics they had; nothing that reads TRANSITION changes meaning.
--
-- `assigned_position` is untouched: a guest is placed at GK, DEF, MID or FWD
-- like anyone else, and the one-goalkeeper-per-team index
-- (`match_team_assignments_one_gk_idx`) applies to them without amendment
-- because it constrains `(match_id, team)` and not the participant.
alter table public.match_team_assignments
  drop constraint if exists match_team_assignments_assignment_basis_check;
alter table public.match_team_assignments
  add constraint match_team_assignments_assignment_basis_check
    check (assignment_basis in ('PRIMARY', 'SECONDARY', 'TRANSITION', 'GUEST'));

-- 5) The MVP ----------------------------------------------------------------------
-- A guest may be the best player on the pitch, so the result needs to be able to
-- name one.
--
-- `on delete no action`, for the same reason the lineup and the goals have it:
-- who was best on the pitch is historical performance. Neither cascade nor set
-- null would do -- cascade would delete the whole result, and set null would
-- quietly erase the award, leaving a match that was recorded as having a best
-- player and now says it had none. Taking a guest off the roster must leave the
-- MVP reference exactly as it was, and a guest who *is* the recorded MVP cannot
-- be deleted outright at all.
--
-- The constraint is **mutual exclusion, not a strict XOR**, and the difference
-- is load-bearing. Migration `0033` made `mvp_user_id` nullable because "nobody
-- was named" is a complete result; requiring exactly one MVP identity would
-- refuse every result recorded since. So: at most one, possibly neither.
alter table public.match_results
  add column if not exists mvp_professional_guest_id uuid
    references public.match_professional_guests (id) on delete no action;

alter table public.match_results
  drop constraint if exists match_results_mvp_identity_check;
alter table public.match_results
  add constraint match_results_mvp_identity_check
    check (mvp_user_id is null or mvp_professional_guest_id is null);

comment on column public.match_results.mvp_professional_guest_id is
  'Set when the best player was a Professional Guest. At most one of '
  'mvp_user_id / mvp_professional_guest_id is non-null; both null means '
  'nobody was named (migration 0033).';

-- NOTE for the phase that enables guest MVP writes: `record_match_result` sets
-- `mvp_user_id` and does not mention `mvp_professional_guest_id`, so a stored
-- guest MVP followed by a user MVP would leave both columns set and violate the
-- constraint above. Nothing can reach that state today -- no function writes the
-- new column -- and the fix belongs with the writer that first does. It is
-- deliberately not made here: replacing a hundred-line result function to clear
-- a column nothing sets would be risk without benefit.

-- 6) The rule a recorded result puts on its participants ---------------------------
-- Migration `0029`'s function, which took the surviving lineup as a `uuid[]` of
-- users. A lineup can now hold guests, and a guest can be a scorer or the MVP,
-- so the question has two halves and the signature grows a second array.
--
-- The two-argument form is dropped rather than kept alongside: a caller that
-- passed only users would be asking half the question and getting a clean
-- answer, which is worse than not having the function at all.
--
-- `not (x = any(array))` is false-not-null only when `x` is non-null, so each
-- half is guarded explicitly. The old body relied on `null = any(...)` being
-- null to skip an absent MVP; stating it makes the same thing legible and keeps
-- it true now that there are two ways for an MVP to be absent.
drop function if exists public.assert_result_survives_lineup(uuid, uuid[]);

create or replace function public.assert_result_survives_lineup(
  p_match_id uuid,
  p_user_ids uuid[],
  p_guest_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mvp uuid;
  v_mvp_guest uuid;
begin
  select mvp_user_id, mvp_professional_guest_id into v_mvp, v_mvp_guest
  from match_results where match_id = p_match_id;
  if not found then return; end if;

  if v_mvp is not null and not (v_mvp = any(p_user_ids)) then
    raise exception 'RESULT_PARTICIPANT_REMOVED';
  end if;

  if v_mvp_guest is not null and not (v_mvp_guest = any(p_guest_ids)) then
    raise exception 'RESULT_PARTICIPANT_REMOVED';
  end if;

  if exists (
    select 1 from match_goals g
    where g.match_id = p_match_id
      and (
        (g.user_id is not null and not (g.user_id = any(p_user_ids)))
        or (g.professional_guest_id is not null
            and not (g.professional_guest_id = any(p_guest_ids)))
      )
  ) then
    raise exception 'RESULT_PARTICIPANT_REMOVED';
  end if;
end;
$$;

revoke execute on function
  public.assert_result_survives_lineup(uuid, uuid[], uuid[])
  from anon, authenticated, public;

-- 7) Replacing a lineup that may hold guests ----------------------------------------
-- Migration `0029`'s function, with the one change the guest makes necessary and
-- the one it makes unavoidable.
--
-- **The payload may now name either kind of participant.** An element carries a
-- `user_id` or a `professional_guest_id`, never both; the XOR check on the table
-- is what enforces that, so a malformed element is a refused transaction rather
-- than a row nobody can interpret.
--
-- **The two halves are replaced differently, and they have to be.** For users
-- the payload is the whole lineup, exactly as it always was -- the application
-- reads the stored lineup, changes it and writes all of it back, so an omitted
-- user means a user who is no longer in it. For guests it is not: the only
-- writer today is the team-generation screen, which assembles its payload from
-- the community roster and knows nothing about guests. Replacing the guest half
-- from a payload that never mentions guests would delete every guest lineup row
-- on the next regeneration -- which is precisely the silent deletion this is
-- correcting.
--
-- So: **users are replaced wholesale, guests only where the payload names them.**
-- A guest the payload does not mention keeps the place they had. That is also
-- what the approved BTGE boundary requires -- guests are added *after* the
-- engine has run, and re-running it over the community players must not disturb
-- them.
--
-- `assignment_basis` is forced to `GUEST` for a guest row rather than taken from
-- the payload. A guest has no profile, so none of PRIMARY, SECONDARY or
-- TRANSITION can be true of them, and accepting TRANSITION would mark every
-- guest out of position on the pitch.
--
-- Unchanged: `security definer` with its own `is_match_community_admin` check,
-- the match taken from the argument rather than the payload, the match row
-- locked first, one transaction, and the detach/attach pair around the write.
-- The one-goalkeeper-per-team index needs no amendment -- it constrains
-- `(match_id, team)` and says nothing about who the participant is.
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

  perform attach_match_effects(p_match_id);
end;
$$;

revoke execute on function public.replace_match_lineup(uuid, jsonb)
  from anon, public;
grant execute on function public.replace_match_lineup(uuid, jsonb)
  to authenticated;

-- 8) The one existing function the index transition requires ----------------------
-- `set_completed_match_player` (migration `0029`) upserts a lineup row with
-- `on conflict (match_id, user_id)`. That inference named the unique *constraint*
-- section 3 just dropped, and PostgreSQL cannot infer a **partial** index from a
-- bare column list -- the statement would fail with "no unique or exclusion
-- constraint matching the ON CONFLICT specification" for every completed-match
-- correction.
--
-- Adding the index predicate to the inference clause is the whole change. The
-- body is otherwise migration `0029`'s, restated only because
-- `create or replace function` replaces all of it. Every rule it carries is
-- unchanged: admin-only, completed-only, community membership, the basis derived
-- from the profile rather than taken from the caller, and the detach/attach pair
-- around the edit.
create or replace function public.set_completed_match_player(
  p_match_id uuid,
  p_user_id uuid,
  p_team text default null,
  p_assigned_position text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_user users%rowtype;
  v_basis text;
  v_user_ids uuid[];
  v_guest_ids uuid[];
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
  end if;

  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  -- CHANGED: `a.user_id is not null`. The lineup of a completed match may now
  -- hold guest rows, and this array is the *user* lineup that
  -- `assert_result_survives_lineup` asks its question about. A null in it would
  -- make `= any(...)` return null and quietly disable the check.
  select coalesce(array_agg(a.user_id), array[]::uuid[]) into v_user_ids
  from match_team_assignments a
  where a.match_id = p_match_id
    and a.user_id is not null
    and a.user_id <> p_user_id;
  if p_team is not null then
    v_user_ids := v_user_ids || p_user_id;
  end if;

  -- CHANGED: this function moves one *user* in or out, so every guest in the
  -- lineup survives it. They are collected rather than assumed so the assertion
  -- is asked about the lineup as it will actually be.
  select coalesce(array_agg(a.professional_guest_id), array[]::uuid[])
    into v_guest_ids
  from match_team_assignments a
  where a.match_id = p_match_id and a.professional_guest_id is not null;

  perform assert_result_survives_lineup(p_match_id, v_user_ids, v_guest_ids);

  perform detach_match_effects(p_match_id);

  if p_team is null then
    delete from match_team_assignments
    where match_id = p_match_id and user_id = p_user_id;
    delete from match_registrations
    where match_id = p_match_id and user_id = p_user_id;
  else
    if p_team not in ('A', 'B') then raise exception 'INVALID_TEAM'; end if;
    if p_assigned_position is null
       or p_assigned_position not in ('GK', 'DEF', 'MID', 'FWD') then
      raise exception 'INVALID_POSITION';
    end if;

    select * into v_user from users where id = p_user_id;
    if not found then raise exception 'MEMBER_NOT_FOUND'; end if;

    v_basis := case
      when v_user.primary_position = p_assigned_position then 'PRIMARY'
      when v_user.secondary_position = p_assigned_position then 'SECONDARY'
      else 'TRANSITION'
    end;

    if not exists (
      select 1 from match_registrations
      where match_id = p_match_id and user_id = p_user_id
    ) then
      select coalesce(max(registration_order), 0) + 1 into v_order
      from match_registrations where match_id = p_match_id;
      insert into match_registrations
        (match_id, user_id, status, registration_order)
      values (p_match_id, p_user_id, 'confirmed', v_order);
    else
      update match_registrations set status = 'confirmed'
      where match_id = p_match_id and user_id = p_user_id;
    end if;

    insert into match_team_assignments
      (match_id, user_id, team, assigned_position, assignment_basis)
    values (p_match_id, p_user_id, p_team, p_assigned_position, v_basis)
    -- CHANGED: the index predicate, so the partial unique index of section 3
    -- can be inferred. Nothing else about the upsert changes.
    on conflict (match_id, user_id) where user_id is not null do update set
      team = excluded.team,
      assigned_position = excluded.assigned_position,
      assignment_basis = excluded.assignment_basis;
  end if;

  perform attach_match_effects(p_match_id);
end;
$$;

revoke execute on function public.set_completed_match_player(uuid, uuid, text,
  text) from anon, public;
grant execute on function public.set_completed_match_player(uuid, uuid, text,
  text) to authenticated;
