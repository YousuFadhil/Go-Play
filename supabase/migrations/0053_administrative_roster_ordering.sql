-- Administrative roster ordering: the owner/admin arrangement of a match's
-- participants, and the point at which it takes over from arrival order.
--
-- ## The one thing this adds
--
-- Migration `0045` collapsed every approved priority rule into a single sort
-- key:
--
--     ORDER BY (user_id IS NULL), registration_order
--
-- That key is *derived*. It says what arrival order implies, and it is exactly
-- right until an administrator decides something arrival order cannot express --
-- that this Professional Guest is playing and that community player is not.
--
-- So the key gains one term in front of it:
--
--     ORDER BY admin_order NULLS LAST, (user_id IS NULL), registration_order
--
-- `admin_order` is null for every participant of a match nobody has arranged,
-- so every row ties on the first term and the derived key decides -- which is
-- migration `0045`'s behaviour, unchanged, and is why nothing about a match in
-- its default state moves. Once an administrator arranges the roster,
-- `admin_order` is non-null for **every** participant of that match and the
-- first term alone decides.
--
-- There is no second roster, no separate queue for guests, and no parallel
-- placement table. The starting/reserve cut is still made by
-- `rebalance_roster` at `starting_players` over one ordering of one list, which
-- is what keeps capacity impossible to exceed: a seat is never granted, it is
-- only ever *implied* by a position, and there are only ever `starting_players`
-- positions above the cut.
--
-- ## Why the mode is stored rather than inferred
--
-- The approved rule is that the first manual arrangement activates
-- administrative ordering **permanently for that match**, and that an
-- administrator who later happens to arrange the list back into arrival order
-- has not thereby returned it to default. Inferring the mode by comparing the
-- two orderings would get that case wrong, so it is not inferred:
-- `matches.roster_order_mode` records the decision, and a trigger refuses to
-- move it back. `admin_order` carries the arrangement; the mode carries the
-- fact that there is one.
--
-- The pair also survives a match emptying out. A match whose participants all
-- withdraw keeps `roster_order_mode = 'manual'`, so the next arrival is
-- appended to an administrative order rather than silently starting a fresh
-- default one.
--
-- ## Registration order is not touched
--
-- `registration_order` keeps its meaning, its uniqueness and its values. It is
-- the record of arrival, it is what the default ordering reads, and it is what
-- the administrative order is seeded from the first time one is created. A
-- match can always say who joined when, arranged or not.
--
-- ## What is deliberately *not* here
--
-- **BTGE.** No engine input, enum, balancing rule or package file is touched.
-- A Professional Guest is still not an engine input and is still placed by
-- `assign_professional_guest_teams` (migration `0050`) after the engine has
-- run. Every operation below ends at `recompute_match_status`, which is the one
-- call site `reconcile_match_lineup` hangs off -- so a manual arrangement that
-- changes the confirmed **community** set clears the stale lineup through the
-- existing approved mechanism, and one that only moves guests about does not.
-- That boundary is migration `0050`'s and is used here rather than restated.
--
-- **A new lock.** An owner or admin arranges the roster of a match in every
-- state, which is the approved rule these operations inherit from `0045` and
-- `0047`. A match that has been **played** keeps the roster it played with:
-- the arrangement is recorded, and the starting/reserve cut is not re-applied,
-- for the reason `0047` states -- everyone in the record played, and re-cutting
-- would demote people out of a recorded lineup and notify them about a match
-- that is over.
--
-- Idempotent throughout: guarded DDL, `create or replace` for every function
-- and the view.

-- 1) The mode, on the match ---------------------------------------------------------
alter table public.matches
  add column if not exists roster_order_mode text not null default 'registration';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'matches_roster_order_mode_check'
      and conrelid = 'public.matches'::regclass
  ) then
    alter table public.matches
      add constraint matches_roster_order_mode_check
      check (roster_order_mode in ('registration', 'manual'));
  end if;
end $$;

comment on column public.matches.roster_order_mode is
  'registration = participant order is derived from arrival (the default); '
  'manual = an owner/admin has arranged the roster and match_registrations.'
  'admin_order is authoritative. Activation is one-way for the life of the '
  'match, enforced by matches_roster_order_mode_locked.';

-- One-way, and said by the database rather than by convention.
--
-- `matches_update_community_admins` lets an admin write the `matches` row
-- directly, so "administrative ordering is never silently reverted" cannot be a
-- property of the RPCs alone. Nothing here refuses an update that leaves the
-- column alone, which is every update the schema makes: `update_match` names
-- its columns and this is not one of them.
create or replace function public.enforce_roster_order_mode_lock()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.roster_order_mode = 'manual'
     and new.roster_order_mode is distinct from 'manual' then
    raise exception 'ROSTER_ORDER_MODE_LOCKED';
  end if;
  return new;
end;
$$;

drop trigger if exists matches_roster_order_mode_locked on public.matches;
create trigger matches_roster_order_mode_locked
  before update on public.matches
  for each row
  execute function public.enforce_roster_order_mode_lock();

-- 2) The arrangement, on the participant --------------------------------------------
-- One column on the table that already holds every participant of a match,
-- community player and Professional Guest alike. A guest is ordered against a
-- community player by the same value in the same column, which is what "a
-- single participant order, not separate queues" means in storage.
alter table public.match_registrations
  add column if not exists admin_order integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'match_registrations_admin_order_positive'
      and conrelid = 'public.match_registrations'::regclass
  ) then
    alter table public.match_registrations
      add constraint match_registrations_admin_order_positive
      check (admin_order is null or admin_order > 0);
  end if;
end $$;

-- Deferrable, and that is the point rather than a precaution. Every arrangement
-- below rewrites the whole order as one statement, which permutes existing
-- values -- `1,2,3` becoming `1,3,2` passes through a moment where two rows
-- share a value. An immediate unique index would refuse it mid-statement; a
-- deferred one asks at commit, by which time the permutation is complete.
--
-- Nulls do not collide, so a match nobody has arranged holds as many null
-- `admin_order` rows as it has participants.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'match_registrations_admin_order_unique'
      and conrelid = 'public.match_registrations'::regclass
  ) then
    alter table public.match_registrations
      add constraint match_registrations_admin_order_unique
      unique (match_id, admin_order) deferrable initially deferred;
  end if;
end $$;

comment on column public.match_registrations.admin_order is
  'The owner/admin arrangement of this participant within the match: 1 is '
  'first. Null for every participant of a match still in registration order. '
  'Non-null for every participant of a match in manual order -- the invariant '
  'the match_registrations_admin_order trigger maintains for rows inserted '
  'after activation.';

-- 3) A participant added to an arranged match joins the end of the arrangement -------
-- A trigger rather than a line in each of the five functions that insert a
-- registration, because the sixth would eventually be written without it. This
-- is the same reasoning migration `0050` gives for hanging the lineup
-- reconciliation off `recompute_match_status`: the invariant belongs at the one
-- place that sees every change.
--
-- **The end, and not a computed position.** A new arrival cannot be placed
-- inside an arrangement without guessing what the administrator meant, and the
-- approved rule is that the administrative order stays authoritative. Appending
-- is the only placement that changes nothing about anybody already arranged; an
-- administrator who wants them higher moves them, which is the operation this
-- migration exists to provide.
create or replace function public.assign_admin_order_on_insert()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_mode text;
begin
  if new.admin_order is not null then
    return new;
  end if;

  select roster_order_mode into v_mode from matches where id = new.match_id;
  if v_mode <> 'manual' then
    return new;
  end if;

  select coalesce(max(admin_order), 0) + 1 into new.admin_order
  from match_registrations where match_id = new.match_id;

  return new;
end;
$$;

drop trigger if exists match_registrations_admin_order on public.match_registrations;
create trigger match_registrations_admin_order
  before insert on public.match_registrations
  for each row
  execute function public.assign_admin_order_on_insert();

-- 4) Activation ----------------------------------------------------------------------
-- The first arrangement of a match: the mode flips, and the arrangement is
-- seeded from the ordering that was in force a moment earlier, so an
-- administrator who moves one participant has moved one participant and not
-- reshuffled the rest.
--
-- A no-op on a match already in manual mode, which is what makes every caller
-- below able to state it unconditionally.
create or replace function public.activate_manual_roster_order(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
begin
  select roster_order_mode into v_mode from matches where id = p_match_id;
  if v_mode is null or v_mode = 'manual' then return; end if;

  update matches set roster_order_mode = 'manual' where id = p_match_id;

  -- Migration `0045`'s ordering, frozen into a column. Every row moves from
  -- null to a distinct value, so nothing collides even before the deferral.
  update match_registrations r
     set admin_order = s.seq
    from (
      select mr.id,
             row_number() over (
               order by (mr.user_id is null), mr.registration_order
             ) as seq
      from match_registrations mr
      where mr.match_id = p_match_id
    ) s
   where r.id = s.id;
end;
$$;

revoke execute on function public.activate_manual_roster_order(uuid)
  from anon, authenticated, public;

-- 5) The authoritative ordering, said once ---------------------------------------------
-- The reserve participant a freed starting seat goes to. Three functions
-- promote from the reserve -- `withdraw_from_match`, `remove_player` and
-- `purge_membership` -- and they must agree with `rebalance_roster` and with
-- each other, so the ordering is written here and read there.
create or replace function public.next_reserve_registration(p_match_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from match_registrations
  where match_id = p_match_id and status = 'reserve'
  order by admin_order nulls last, (user_id is null), registration_order
  limit 1;
$$;

revoke execute on function public.next_reserve_registration(uuid)
  from anon, authenticated, public;

-- 6) rebalance_roster ---------------------------------------------------------------------
-- Migration `0045`'s function with one term added to its ORDER BY, and nothing
-- else changed: the same single pass, the same update-only-if-changed test, the
-- same title-carrying notification, the same silence for a guest who has nobody
-- to notify.
--
-- This is still the only thing in the schema that decides who is confirmed, and
-- it still decides it by cutting one ordering at `starting_players`. That is
-- what makes "a full starting list never gains an additional participant" a
-- property of the design rather than a check somebody has to remember: there is
-- no operation that grants a seat, only operations that change positions.
create or replace function public.rebalance_roster(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_starting int; v_title text; r record;
begin
  select starting_players, title into v_starting, v_title
  from matches where id = p_match_id;
  for r in
    select mr.id, mr.user_id, mr.status,
           case when row_number() over (
                  -- CHANGED (0053): the administrative arrangement first, when
                  -- there is one. Null for every row of a match nobody has
                  -- arranged, so the two derived terms behind it decide exactly
                  -- as they did in `0045`.
                  order by mr.admin_order nulls last,
                           (mr.user_id is null), mr.registration_order
                ) <= v_starting
                then 'confirmed' else 'reserve' end as desired
    from match_registrations mr where mr.match_id = p_match_id
  loop
    if r.status <> r.desired then
      update match_registrations set status = r.desired where id = r.id;
      if r.user_id is not null then
        if r.desired = 'reserve' then
          perform create_notification(r.user_id, p_match_id, 'moved_to_reserve',
              coalesce(v_title, ''));
        else
          perform create_notification(r.user_id, p_match_id, 'promoted',
              coalesce(v_title, ''));
        end if;
      end if;
    end if;
  end loop;
end;
$$;

revoke execute on function public.rebalance_roster(uuid)
  from anon, authenticated, public;

-- 7) The shared registration transaction --------------------------------------------------
-- Migration `0045`'s function with one branch added, for one reason.
--
-- `0045` computes the seat over **community** registrations rather than over the
-- confirmed count, so that a guest sitting in a starting slot cannot send a
-- joining community player to the reserve. That is the right answer while
-- arrival order is in force, because a guest holding a starting slot then is
-- holding it only until somebody displaces them.
--
-- Under an administrative arrangement it is the wrong answer, and precisely the
-- wrong answer the approved rules single out: a Professional Guest an
-- administrator has deliberately placed in the starting lineup must **not** be
-- displaced by the next community player to register. Under manual mode the new
-- row is appended to the end of the arrangement, so its seat is decided by
-- whether the arrangement has a starting position left -- total participants
-- after the insert against `starting_players`, which is the same question the
-- cut asks.
--
-- The seat is still computed rather than left to `rebalance_roster`, for
-- `0045`'s reason: a row inserted as `reserve` and immediately promoted would
-- send an ordinary registrant a "you have been promoted from the reserve"
-- notification about a queue they were never in. Appending makes the computed
-- seat exact, so the rebalance below changes nothing and notifies nobody.
drop function if exists public.register_player_in_match(uuid, uuid);

create or replace function public.register_player_in_match(
  p_match_id uuid,
  p_user_id uuid,
  p_enforce_time_lock boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_community int;
  v_status text;
  v_order int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  perform 1 from users where id = p_user_id for update;

  if p_enforce_time_lock then
    if v_match.status = 'completed' or v_match.end_at <= now() then
      raise exception 'MATCH_CLOSED';
    end if;
    if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  end if;

  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  if exists (select 1 from match_registrations
             where match_id = p_match_id and user_id = p_user_id) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  if exists (
    select 1 from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = p_user_id
      and m.status in ('open', 'full')
      and m.end_at > now()
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  -- CHANGED (0053): which question decides the seat depends on which ordering
  -- is in force.
  if v_match.roster_order_mode = 'manual' then
    -- Appended to the end of the arrangement by the
    -- `match_registrations_admin_order` trigger, so the position this row will
    -- hold is `v_total + 1` and the cut is the whole of the answer. A guest an
    -- administrator placed in the starting lineup keeps their place.
    v_status := case when v_total + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  else
    select count(*) into v_community
    from match_registrations
    where match_id = p_match_id and user_id is not null;

    v_status := case when v_community + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  end if;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);

  perform rebalance_roster(p_match_id);

  select status into v_status from match_registrations
  where match_id = p_match_id and user_id = p_user_id;

  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

revoke execute on function public.register_player_in_match(uuid, uuid, boolean)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid, boolean)
  to service_role;

-- 8) The three promotions -------------------------------------------------------------
-- Each is migration `0045`'s function with its inline `order by` replaced by a
-- call to `next_reserve_registration`. Nothing else about any of them changes:
-- the same gates, the same exceptions in the same order, the same notification,
-- and the same silence when the participant promoted is a guest, which the
-- existing `is not null` guard already produced.
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype; v_registration match_registrations%rowtype; v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then raise exception 'MATCH_CLOSED'; end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  select * into v_registration from match_registrations where match_id = p_match_id and user_id = auth.uid();
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    -- CHANGED (0053): the authoritative order, whichever one is in force. The
    -- vacant seat is filled from the top of the current reserve, so a
    -- Professional Guest an administrator placed in the starting lineup is not
    -- disturbed by somebody else's withdrawal.
    update match_registrations set status = 'confirmed'
    where id = next_reserve_registration(p_match_id)
    returning user_id into v_promoted;
    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted', v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
end;
$$;

revoke execute on function public.withdraw_from_match(uuid) from anon, public;
grant execute on function public.withdraw_from_match(uuid) to authenticated;

create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
  v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select * into v_registration from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    -- CHANGED (0053): the authoritative order.
    update match_registrations set status = 'confirmed'
    where id = next_reserve_registration(p_match_id)
    returning user_id into v_promoted;
    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed', v_match.title);
end;
$$;

revoke execute on function public.remove_player(uuid, uuid) from anon, public;
grant execute on function public.remove_player(uuid, uuid) to authenticated;

create or replace function public.purge_membership(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_promoted uuid;
begin
  for r in
    select mr.id, mr.status, mr.match_id, m.title
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id and mr.user_id = p_user_id
  loop
    perform 1 from matches where id = r.match_id for update;
    delete from match_registrations where id = r.id;
    if r.status = 'confirmed' then
      -- CHANGED (0053): the authoritative order.
      update match_registrations set status = 'confirmed'
      where id = next_reserve_registration(r.match_id)
      returning user_id into v_promoted;
      if v_promoted is not null then
        perform create_notification(v_promoted, r.match_id, 'promoted',
            coalesce(r.title, ''));
      end if;
    end if;
    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

revoke execute on function public.purge_membership(uuid, uuid)
  from anon, authenticated, public;

-- 9) Arranging the roster ------------------------------------------------------------------
-- The authoritative participant order of a match, written whole.
--
-- **Why the whole order and not a move.** A "move participant X to position 4"
-- operation has to be interpreted against the order the caller was looking at,
-- and that order may have changed since they looked. Sending the resulting
-- order instead makes the caller's view part of the request: the array must be
-- an exact permutation of the match's participants, so a roster that moved
-- underneath -- somebody registered, somebody withdrew, another administrator
-- arranged it -- is refused with `ROSTER_MISMATCH` rather than silently applied
-- to a roster the caller never saw. That is the whole of the concurrency
-- story, and it costs one comparison.
--
-- **Why no seat travels in the request.** The array says positions and nothing
-- else. Starting and reserve are then derived by `rebalance_roster` cutting at
-- `starting_players`, so there is no input a caller could send that produces
-- more starting participants than the match has starting slots, and none that
-- puts the same participant in both lists. Capacity and exclusivity are not
-- validated here because they cannot be violated here.
create or replace function public.set_match_roster_order(
  p_match_id uuid,
  p_registration_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_played boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- The same lock, taken in the same place, as every other operation that
  -- depends on this match's capacity or ordering.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_registration_ids is null
     or array_position(p_registration_ids, null) is not null then
    raise exception 'ROSTER_MISMATCH';
  end if;

  select count(*) into v_total
  from match_registrations where match_id = p_match_id;

  -- Same length, no repeats, and every id a participant of *this* match. The
  -- three together are what "exact permutation" means, and an exact permutation
  -- is what makes the write below total: every participant gets a position and
  -- no position is shared.
  if coalesce(array_length(p_registration_ids, 1), 0) <> v_total then
    raise exception 'ROSTER_MISMATCH';
  end if;

  if exists (
    select 1 from unnest(p_registration_ids) as t(id)
    group by t.id having count(*) > 1
  ) then
    raise exception 'ROSTER_MISMATCH';
  end if;

  if exists (
    select 1 from unnest(p_registration_ids) as t(id)
    where not exists (
      select 1 from match_registrations r
      where r.id = t.id and r.match_id = p_match_id
    )
  ) then
    raise exception 'ROSTER_MISMATCH';
  end if;

  -- Arranging a roster *is* the activation, so this is stated before the write
  -- rather than inferred from it. A no-op on a match already arranged.
  perform activate_manual_roster_order(p_match_id);

  -- The permutation, in one statement. The deferred unique constraint is what
  -- allows two rows to hold the same value in the middle of it.
  update match_registrations r
     set admin_order = t.ord
    from (
      select u.id, u.ord::int as ord
      from unnest(p_registration_ids) with ordinality as u(id, ord)
    ) t
   where r.id = t.id and r.match_id = p_match_id;

  -- A played match keeps the roster it played with. The arrangement is recorded
  -- -- an administrator may put the record in the order they want it read --
  -- but the starting/reserve cut is not re-applied, for the reason migration
  -- `0047` states: everyone in the record played, and re-cutting would demote
  -- players out of a recorded lineup and notify them about a finished match.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  if not v_played then
    perform rebalance_roster(p_match_id);
  end if;

  -- Migration `0050`'s single call site: the lineup is checked against the
  -- roster that just changed, and the guests are re-alternated around whatever
  -- survives. No BTGE input is produced here and none is consumed.
  perform recompute_match_status(p_match_id);
end;
$$;

-- 10) Swapping two participants ---------------------------------------------------------
-- The approved mechanism for moving a participant between the starting lineup
-- and the reserve while the starting lineup is full: the two exchange
-- positions, so the number of participants above the cut is the number that was
-- above it a moment ago. There is no direction to the operation -- reserve onto
-- starting and starting onto reserve are the same exchange -- and no kind to
-- it: a Professional Guest is swapped with a community player exactly as two
-- community players are, because both are rows in one order.
--
-- Within a single list it is a swap of two positions, which is also useful and
-- is not refused.
--
-- What a swap cannot do is add a seat. It moves values between two rows and
-- creates none, so the cut still lands where it landed.
create or replace function public.swap_match_participants(
  p_match_id uuid,
  p_first_registration_id uuid,
  p_second_registration_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_first int;
  v_second int;
  v_played boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_first_registration_id is null
     or p_second_registration_id is null
     or p_first_registration_id = p_second_registration_id then
    raise exception 'INVALID_SWAP';
  end if;

  -- Activated before the positions are read, because activation is what gives a
  -- participant of a default-ordered match a position to exchange.
  perform activate_manual_roster_order(p_match_id);

  select admin_order into v_first from match_registrations
  where id = p_first_registration_id and match_id = p_match_id;
  if v_first is null then raise exception 'INVALID_SWAP'; end if;

  select admin_order into v_second from match_registrations
  where id = p_second_registration_id and match_id = p_match_id;
  if v_second is null then raise exception 'INVALID_SWAP'; end if;

  -- One statement, so the pair is never half-swapped, and the deferred
  -- constraint is what lets the two values cross.
  update match_registrations
     set admin_order = case id when p_first_registration_id then v_second
                                                            else v_first end
   where match_id = p_match_id
     and id in (p_first_registration_id, p_second_registration_id);

  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  if not v_played then
    perform rebalance_roster(p_match_id);
  end if;

  perform recompute_match_status(p_match_id);
end;
$$;

-- Grants -----------------------------------------------------------------------------------
-- The shape every match-management RPC has: unreachable by `anon`, reachable by
-- `authenticated`, and the `has_community_role` check inside decides the rest.
-- An ordinary player reaches both and is refused by both.
--
-- `SECURITY DEFINER` is required for the same reason it is everywhere else in
-- this schema: `match_registrations` carries a select policy and no write
-- policy at all, so every write goes through a function and the rules are not
-- optional.
revoke execute on function public.set_match_roster_order(uuid, uuid[])
  from anon, public;
grant execute on function public.set_match_roster_order(uuid, uuid[])
  to authenticated;

revoke execute on function public.swap_match_participants(uuid, uuid, uuid)
  from anon, public;
grant execute on function public.swap_match_participants(uuid, uuid, uuid)
  to authenticated;

-- 11) The read model -------------------------------------------------------------------------
-- Migration `0048`'s view, with two columns appended and nothing else touched:
-- every existing column keeps its name, its position and its type, which is
-- what `create or replace view` allows.
--
-- `roster_position` is the authoritative order as a number a client can sort by
-- and print. It is the same expression `rebalance_roster` cuts, so "position 3
-- of a match with 3 starting players" and "the last starting participant" are
-- the same row by construction rather than by two implementations agreeing.
--
-- Putting it here is what keeps the ordering rule out of the client. A reader
-- asks for participants of a match ordered by `roster_position` and gets the
-- arrangement; it does not need to know that a null `admin_order` means
-- anything, or that guests follow users when there is no arrangement.
create or replace view public.v_match_registrations
with (security_invoker = on) as
select
  r.id                  as registration_id,
  r.match_id,
  m.community_id,
  r.user_id,
  r.status,
  r.registration_order,
  r.created_at          as registered_at,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  m.title               as match_title,
  m.start_at            as match_start_at,
  m.status              as match_status,
  -- Appended by migration 0048.
  r.professional_guest_id,
  case when r.professional_guest_id is not null
       then 'PROFESSIONAL' else 'USER' end::text  as participant_type,
  coalesce(u.full_name, g.display_name)           as display_name,
  -- Appended by migration 0053.
  r.admin_order,
  row_number() over (
    partition by r.match_id
    order by r.admin_order nulls last,
             (r.user_id is null), r.registration_order
  )::int                                          as roster_position
from public.match_registrations r
join public.matches m on m.id = r.match_id
left join public.users u on u.id = r.user_id
left join public.match_professional_guests g on g.id = r.professional_guest_id;

comment on view public.v_match_registrations is
  'Read model: match registrations (confirmed and reserve) for both kinds of '
  'participant. participant_type distinguishes USER from PROFESSIONAL; '
  'display_name is what to render, while full_name and the profile columns are '
  'null for a guest. registration_order is the queue position written by the '
  'RPC and is never recomputed here. roster_position is the authoritative '
  'participant order -- the owner/admin arrangement when the match has one, '
  'and arrival order otherwise -- and is the same expression rebalance_roster '
  'cuts at starting_players.';

revoke all on public.v_match_registrations from anon, public;
grant select on public.v_match_registrations to authenticated;
