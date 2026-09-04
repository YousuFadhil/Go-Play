-- ============ migrations/0065_platform_admin_community_suspension_enforcement.sql ============
-- Platform Admin, suspension: COMMUNITY suspension, and the last piece of the
-- database-side package.
--
-- ## PACKAGE CONTRACT
--
-- `0062`, `0063`, `0064` and this file form **one Platform Admin suspension
-- package**. `0065` completes database enforcement, and the package is still
--
--     NOT APPROVED FOR REMOTE APPLICATION
--
-- until every one of the following has happened:
--
--   1. Chief Architect review of `0065`;
--   2. full-package static review;
--   3. a live Supabase READ-ONLY precheck;
--   4. verification of the live function and policy signatures against what
--      this package was built from;
--   5. backup / recovery consideration;
--   6. explicit Product Owner approval.
--
-- No SQL from `0062`-`0065` is applied remotely in this cycle.
--
-- ## THE BOUNDARY THIS FILE DRAWS
--
-- One rule, applied to every normal mutation that is scoped to a community or
-- to one of its matches:
--
--     the CALLER must be active
--     AND the TARGET COMMUNITY must be active
--     AND the EXISTING ownership / role / business predicate must still pass.
--
-- Two instruments, and they are deliberately not the same:
--
--   * `is_current_user_active()` (`0062`), raising `ACCOUNT_SUSPENDED` (`0064`)
--     wherever a function can speak. A policy cannot raise, so there it is a
--     conjunct and a suspended caller's write simply matches nothing.
--   * `has_active_community_role(...)` (`0062`), which asks the user-active and
--     community-active questions and **delegates the role ranking to the
--     untouched `has_community_role`**. There is still one role model, in one
--     place.
--
-- Where a function already distinguishes an inactive community with a stable
-- code, that code is preserved and still fires -- `create_match`'s
-- `COMMUNITY_INACTIVE` (`0054`), `set_community_logo`'s `COMMUNITY_NOT_FOUND`
-- (`0061`), and the `is_active` lookups inside `join_community` (`0016`) and
-- `join_community_by_code` (`0007`). Those functions get the caller guard and
-- nothing else. Nowhere is a new error code invented: `ACCOUNT_SUSPENDED` comes
-- from `0064` and `COMMUNITY_INACTIVE` from `0026`.
--
-- `regenerate_join_code` (`0015`) looks like it belongs in that list and does
-- not. It locks the community row but never reads `is_active`, and its
-- `COMMUNITY_NOT_FOUND` only ever meant "no such row" -- so it needed the
-- community test adding, not preserving. See its own section below.
--
-- ## WHAT IS DELIBERATELY NOT DONE
--
--   * **`has_community_role` is not modified**, and neither is
--     `is_match_community_admin`. Every call site of the latter was enumerated
--     first: three `match_team_assignments` write policies and two RPCs, all
--     mutations, no read path. Even so the helper is left alone and the
--     enforcement is put in those five callers, because that is the narrower
--     change and it does not alter what a generic authorization helper means.
--   * **No read semantics change.** Not one SELECT policy, view or read RPC is
--     touched; `0063` owns the approved read model.
--   * **No new write privilege and no new write policy.** Every policy below
--     replaces one that already exists. `match_registrations`, `match_results`,
--     `match_goals`, `match_professional_guests`, `community_statistics`,
--     `rating_history` and `player_statistics` have no client write policy
--     today and gain none: their writes go through the RPCs above.
--   * **No cleanup, cascade, backfill or trigger.** Suspending a user or a
--     community deletes and rewrites nothing -- memberships, registrations,
--     team assignments, guests, results, goals, ratings, statistics, matches
--     and communities all stay exactly where they are, and reactivation
--     restores normal behaviour from those preserved rows.
--   * **No session change.** No Auth session is revoked, no `auth.users` row is
--     banned, no Auth Admin API is called, no Edge Function is added and no
--     service-role credential goes near a client. A suspended user may retain a
--     valid JWT; the database is what refuses their writes.
--   * `admin_delete_user`, `admin_delete_community` and `admin_delete_match`
--     are untouched in definition and in privilege.
--
-- Every function below is its current effective definition from tracked
-- migrations `0001`-`0061`, reproduced unchanged except for the guards its own
-- comment names. No signature, return type, validation, notification, rating,
-- statistics, lineup, guest or historical-match behaviour is altered anywhere
-- in this file.
--
-- Idempotent throughout: `create or replace function`, and a guarded
-- `drop policy` before each `create policy`.



-- ============================================================================
-- 1) admin_suspend_community()
-- ============================================================================
-- The community mirror of `admin_suspend_user` (`0064`), following the same
-- conventions: `is_system_admin()` as the first statement, `for update` to make
-- read-then-write atomic, and the state change and the audit event in one
-- transaction with **no exception handler between them** -- so a failed audit
-- rolls the suspension back rather than leaving a change nobody can account for.
--
-- There is no self-check and no System Admin exclusion here: a community has
-- neither relationship, and `0064`'s two refusals have no counterpart.
--
-- **The no-op precedes the reason**, exactly as `0064` was corrected to do.
-- Asking to suspend a community that is already inactive is asking for a state
-- it is already in, and a desired-state call is not refused for the shape of an
-- argument it never needed. So a null, empty or whitespace reason returns
-- success on that path rather than `REASON_REQUIRED`, nothing is written, the
-- existing metadata is left alone, no audit row is created, and no attempt is
-- made to classify whether the inactive row is a suspension or a legacy
-- deactivation.
create or replace function public.admin_suspend_community(
  p_community_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
  v_reason text;
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_community
  from communities c where c.id = p_community_id for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  -- Already inactive. Success, and nothing moves.
  if not v_community.is_active then
    return;
  end if;

  -- Only an active community reaches this line, so `REASON_REQUIRED` can only
  -- ever be raised by a call that would really have suspended something.
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'REASON_REQUIRED';
  end if;

  update communities set
    is_active         = false,
    suspended_at      = now(),
    suspended_by      = auth.uid(),
    suspension_reason = v_reason
  where id = p_community_id;

  -- One event, in this transaction. The label is read from the row locked
  -- before the update, so it is the community the action was taken against.
  perform record_admin_audit(
    'COMMUNITY_SUSPENDED',
    'COMMUNITY',
    p_community_id,
    v_community.name,
    v_reason
  );
end;
$$;

comment on function public.admin_suspend_community(uuid, text) is
  'Platform Admin: suspends a community by setting communities.is_active false '
  'and recording who acted, when and why. System Admin only. Idempotent: '
  'suspending an already inactive community succeeds, writes nothing, does not '
  'validate the reason and creates no second audit event (migration 0065).';



-- ============================================================================
-- 2) admin_reactivate_community()
-- ============================================================================
-- The mirror, following `admin_reactivate_user` (`0064`) exactly -- including
-- its audit convention: the suspension metadata is cleared, so the audit event
-- becomes the only surviving record of the suspension that just ended, and it is
-- therefore written from the row image captured before the clear and carries
-- both the name and the reason being reversed.
create or replace function public.admin_reactivate_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_community
  from communities c where c.id = p_community_id for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  -- Already active. Success, no write, no metadata change, no audit event.
  if v_community.is_active then
    return;
  end if;

  update communities set
    is_active         = true,
    suspended_at      = null,
    suspended_by      = null,
    suspension_reason = null
  where id = p_community_id;

  perform record_admin_audit(
    'COMMUNITY_REACTIVATED',
    'COMMUNITY',
    p_community_id,
    v_community.name,
    v_community.suspension_reason
  );
end;
$$;

comment on function public.admin_reactivate_community(uuid) is
  'Platform Admin: restores a community by setting communities.is_active true '
  'and clearing the suspension metadata, after the audit event has preserved '
  'it. System Admin only. Idempotent: reactivating an active community '
  'succeeds and writes no audit event (migration 0065).';

-- Privileges, matching `0064`'s two user RPCs and `0017`'s six. Authorization is
-- not the grant: an ordinary account holder reaches these functions and is
-- refused by `is_system_admin()` inside them. `record_admin_audit` is reached
-- from inside both because a `security definer` function runs as its owner --
-- its own grant is untouched and it remains executable by no client role.
revoke execute on function public.admin_suspend_community(uuid, text)
  from anon, public;
revoke execute on function public.admin_reactivate_community(uuid)
  from anon, public;

grant execute on function public.admin_suspend_community(uuid, text)
  to authenticated;
grant execute on function public.admin_reactivate_community(uuid)
  to authenticated;



-- ============================================================================
-- 3) Community and membership write policies
-- ============================================================================
-- Each policy is rebuilt with its original rule intact and the active-aware
-- predicate substituted or added as a strict AND. Names, commands and roles are
-- preserved exactly; nothing is widened and no policy is created on a table that
-- did not already have one.

-- `communities_update_owner` (`0008`). Owner-only becomes active-Owner-only in
-- an active community. Combined with `0063`'s column grant, a valid direct
-- update needs all four: an active caller, an active community, the caller
-- being its Owner, and a statement touching only `join_policy` -- because that
-- is the only column `authenticated` may write. **No column is added to that
-- grant here**: `logo_url` is still written only through `set_community_logo`,
-- and `is_active` and the `0062` suspension metadata are still writable by no
-- client at all.
drop policy if exists "communities_update_owner" on public.communities;
create policy "communities_update_owner"
  on public.communities
  for update
  to authenticated
  using (public.has_active_community_role(id, auth.uid(), 'owner'))
  with check (public.has_active_community_role(id, auth.uid(), 'owner'));

-- `community_members_delete_self` (`0008`) -- leaving a community. The original
-- rule is preserved in full: a member may delete only their own row, and an
-- Owner may not leave this way (`role <> 'owner'`). Two requirements are added:
-- a suspended user cannot leave, and nobody can leave a suspended community.
-- The membership row is preserved in either case, which is what the approved
-- model means by suspension not deleting membership.
drop policy if exists "community_members_delete_self" on public.community_members;
create policy "community_members_delete_self"
  on public.community_members
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and role <> 'owner'
    and public.is_current_user_active()
    and exists (
      select 1 from public.communities c
      where c.id = community_id and c.is_active
    )
  );

-- `matches_insert_community_admins` (`0008`). `created_by = auth.uid()` is kept:
-- it keeps the audit field honest and is not what grants the insert.
drop policy if exists "matches_insert_community_admins" on public.matches;
create policy "matches_insert_community_admins"
  on public.matches
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.has_active_community_role(community_id, auth.uid(), 'admin')
  );

-- `matches_update_community_admins` (`0008`), both clauses.
drop policy if exists "matches_update_community_admins" on public.matches;
create policy "matches_update_community_admins"
  on public.matches
  for update
  to authenticated
  using (public.has_active_community_role(community_id, auth.uid(), 'admin'))
  with check (public.has_active_community_role(community_id, auth.uid(), 'admin'));



-- ============================================================================
-- 4) match_team_assignments write policies
-- ============================================================================
-- The three write policies from `0018` ask `is_match_community_admin(match_id,
-- auth.uid())`. That helper is **not** modified -- see the header -- so each
-- policy instead asks the same question through the active-aware predicate,
-- with the same match lookup and the same minimum role (`admin`) the helper
-- uses. The ranking is still `has_community_role`'s, reached via
-- `has_active_community_role`; nothing is duplicated and no role is widened.
--
-- `match_team_assignments_select_members` is not touched: it asks
-- `is_match_community_member`, a different function, and reads are not this
-- file's business.
drop policy if exists "match_team_assignments_insert_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_insert_admins"
  on public.match_team_assignments
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.matches m
      where m.id = match_id
        and public.has_active_community_role(m.community_id, auth.uid(), 'admin')
    )
  );

drop policy if exists "match_team_assignments_update_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_update_admins"
  on public.match_team_assignments
  for update
  to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = match_id
        and public.has_active_community_role(m.community_id, auth.uid(), 'admin')
    )
  )
  with check (
    exists (
      select 1 from public.matches m
      where m.id = match_id
        and public.has_active_community_role(m.community_id, auth.uid(), 'admin')
    )
  );

drop policy if exists "match_team_assignments_delete_admins"
  on public.match_team_assignments;
create policy "match_team_assignments_delete_admins"
  on public.match_team_assignments
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.matches m
      where m.id = match_id
        and public.has_active_community_role(m.community_id, auth.uid(), 'admin')
    )
  );



-- ============================================================================
-- 5) Community-logo Storage write policies
-- ============================================================================
-- The three organizer policies from `0061`, rebuilt with their exact bucket and
-- path predicates -- `bucket_id = 'community-logos'` and
-- `public.community_logo_folder(name)`, which reads the community out of the
-- object's first folder -- and the same minimum role (`admin`). Only the
-- authorization predicate becomes active-aware.
--
-- A suspended user performs no logo mutation, and neither does anybody in a
-- suspended community. `community_logos_read_all` is **not** touched: a
-- community's picture stays publicly readable, which is what `0061` decided and
-- what the approved read model keeps.
drop policy if exists "community_logos_insert_organizer" on storage.objects;
create policy "community_logos_insert_organizer"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'community-logos'
    and public.has_active_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );

drop policy if exists "community_logos_update_organizer" on storage.objects;
create policy "community_logos_update_organizer"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'community-logos'
    and public.has_active_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  )
  with check (
    bucket_id = 'community-logos'
    and public.has_active_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );

drop policy if exists "community_logos_delete_organizer" on storage.objects;
create policy "community_logos_delete_organizer"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'community-logos'
    and public.has_active_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );



-- ============================================================================
-- 6) The community- and match-scoped RPCs
-- ============================================================================
-- Each function below is its current effective definition from tracked
-- migrations `0001`-`0061`, reproduced unchanged except for the guards named in
-- its own comment. Privileges are preserved by `create or replace`, which is
-- what this schema already relies on (`0038` says so beside
-- `register_push_token`), so no function gains or loses a caller here.
--
-- Three treatments, and each function's comment says which it got:
--
--   * **caller + active role** -- the `has_community_role(...)` authorization
--     becomes `has_active_community_role(...)`, which asks the community
--     question too. One line changes per role check.
--   * **caller only** -- the function already refuses an inactive community with
--     its own stable error, which is preserved untouched.
--   * **caller + explicit community** -- there is no role predicate to make
--     active-aware, so the community's state is asked directly with
--     `COMMUNITY_INACTIVE`, placed after the existing `MATCH_NOT_FOUND` (or
--     `NOT_AUTHORIZED`) test so no existing error semantic is displaced.

-- ---------------------------------------------------------------------------
-- transfer_ownership -- effective definition from `0009`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.transfer_ownership(
  p_community_id uuid,
  p_new_owner_id uuid
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if not has_active_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_new_owner_id = auth.uid() then
    raise exception 'ALREADY_OWNER';
  end if;

  -- Serializes concurrent transfers of the same community.
  perform 1 from communities where id = p_community_id for update;

  if not exists (
    select 1 from community_members
    where community_id = p_community_id and user_id = p_new_owner_id
  ) then
    raise exception 'MEMBER_NOT_FOUND';
  end if;

  update community_members set role = 'admin'
  where community_id = p_community_id and user_id = auth.uid();

  update community_members set role = 'owner'
  where community_id = p_community_id and user_id = p_new_owner_id;

  update communities set owner_id = p_new_owner_id where id = p_community_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- set_member_role -- effective definition from `0008`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.set_member_role(
  p_community_id uuid,
  p_user_id uuid,
  p_role text
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if p_role not in ('admin', 'player') then
    raise exception 'INVALID_ROLE';
  end if;
  if not has_active_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;

  update community_members
  set role = p_role
  where community_id = p_community_id
    and user_id = p_user_id
    and role <> 'owner';

  if not found then
    raise exception 'MEMBER_NOT_FOUND';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- remove_member -- effective definition from `0017`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.remove_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_target_role text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if not has_active_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then raise exception 'CANNOT_REMOVE_SELF'; end if;

  select role into v_target_role from community_members
  where community_id = p_community_id and user_id = p_user_id;
  if not found then raise exception 'MEMBER_NOT_FOUND'; end if;
  if v_target_role = 'owner' then raise exception 'CANNOT_REMOVE_OWNER'; end if;
  if v_target_role = 'admin'
     and not has_active_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform purge_membership(p_community_id, p_user_id);
end;
$$;


-- ---------------------------------------------------------------------------
-- update_match -- effective definition from `0045`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.update_match(
  p_match_id uuid, p_title text, p_location text,
  p_start_at timestamptz, p_end_at timestamptz,
  p_starting_players integer, p_description text
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- CHANGED: the MATCH_COMPLETED and MATCH_LOCKED gates are gone. Owner/admin
  -- administration is allowed in every match state. Whether the match has been
  -- played decides what happens to the roster below, never whether the caller
  -- may act.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  -- Guests are part of `v_total`: the capacity a new starting count has to fit
  -- is every participant, which is the same rule registration applies.
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if p_starting_players + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;
  update matches set
    title = trim(p_title),
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;
  -- CHANGED: a played match keeps the roster it played with, and the status it
  -- earned. Re-cutting the roster would demote players out of a recorded lineup
  -- and notify them about a match that is already over; recomputing the status
  -- from the new `end_at` would reopen it for registration.
  --
  -- The statement below is the one `recompute_match_status` runs in its own
  -- completed branch, so a match that finished without anything having touched it
  -- still gets the stored status it was owed. An Open or Full match takes the
  -- unchanged path and is recomputed exactly as before.
  if v_played then
    update matches set status = 'completed'
    where id = p_match_id and status <> 'completed';
  else
    perform rebalance_roster(p_match_id);
    perform recompute_match_status(p_match_id);
  end if;
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      trim(p_title))
  -- CHANGED: guests have nobody to notify, and notifications.user_id is NOT NULL.
  from match_registrations mr
  where mr.match_id = p_match_id and mr.user_id is not null;
end;
$$;


-- ---------------------------------------------------------------------------
-- delete_match -- effective definition from `0017`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform purge_match(p_match_id);
end;
$$;


-- ---------------------------------------------------------------------------
-- remove_player -- effective definition from `0053`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
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


-- ---------------------------------------------------------------------------
-- admin_add_player_to_match -- effective definition from `0045`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.admin_add_player_to_match(
  p_match_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- CHANGED: false. Owner/admin management is allowed in every match state.
  return register_player_in_match(p_match_id, p_user_id, false);
end;
$$;


-- ---------------------------------------------------------------------------
-- set_completed_match_player -- effective definition from `0044`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
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


-- ---------------------------------------------------------------------------
-- set_match_roster_order -- effective definition from `0053`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- The same lock, taken in the same place, as every other operation that
  -- depends on this match's capacity or ordering.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
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


-- ---------------------------------------------------------------------------
-- swap_match_participants -- effective definition from `0053`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
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


-- ---------------------------------------------------------------------------
-- add_professional_guest -- effective definition from `0047`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.add_professional_guest(
  p_match_id uuid,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_order int;
  v_guest_id uuid;
  v_played boolean;
  v_seat text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- Serializes every capacity and ordering decision for this match, exactly as
  -- registration and withdrawal already do.
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- The same bounds the table's own check states. Asked here as well so the
  -- caller gets a named refusal instead of a constraint violation.
  if p_name is null or char_length(trim(p_name)) < 2
     or char_length(trim(p_name)) > 60 then
    raise exception 'INVALID_GUEST_NAME';
  end if;

  -- Guests do not create capacity, they consume it: community registrations and
  -- guests share one maximum.
  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  insert into match_professional_guests (match_id, display_name, created_by)
  values (p_match_id, trim(p_name), auth.uid())
  returning id into v_guest_id;

  -- One sequence per match, shared with community registrations, so
  -- `(user_id is null), registration_order` orders every participant of the
  -- match against every other.
  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  -- **A played match has no reserve: everyone in the record played.** Migration
  -- `0029` states that where it first mattered, and it decides the seat here.
  --
  -- Re-cutting the roster of a finished match would be actively wrong, not
  -- merely pointless. `set_completed_match_player` confirms a corrected player
  -- without regard to `starting_players`, so a completed match can legitimately
  -- hold more confirmed players than it has starting slots -- and
  -- `rebalance_roster` would demote the excess and send them a "you have been
  -- moved to the reserve" notification about a match that has already been
  -- played. So a guest added to a played match simply joins it, and the roster
  -- is left as the record it is.
  v_played := v_match.status = 'completed' or v_match.end_at <= now();
  v_seat := case when v_played then 'confirmed' else 'reserve' end;

  insert into match_registrations
    (match_id, professional_guest_id, status, registration_order)
  values (p_match_id, v_guest_id, v_seat, v_order);

  -- Placement belongs to the one function that knows the ordering. A guest that
  -- lands in a starting slot is promoted here, silently.
  if not v_played then
    perform rebalance_roster(p_match_id);
  end if;
  perform recompute_match_status(p_match_id);

  return v_guest_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- remove_professional_guest -- effective definition from `0047`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.remove_professional_guest(
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
  v_has_history boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- Both halves matter: the guest must exist, and it must belong to *this*
  -- match. A guest is match-scoped, so an id from another match is not a guest
  -- this caller has any business naming.
  if not exists (
    select 1 from match_professional_guests
    where id = p_guest_id and match_id = p_match_id
  ) then
    raise exception 'GUEST_NOT_FOUND';
  end if;

  -- The roster seat, always.
  delete from match_registrations
  where match_id = p_match_id and professional_guest_id = p_guest_id;

  -- Everything the completed match needs in order to still be true about them.
  v_has_history :=
    exists (select 1 from match_team_assignments
            where match_id = p_match_id and professional_guest_id = p_guest_id)
    or exists (select 1 from match_goals
               where match_id = p_match_id
                 and professional_guest_id = p_guest_id)
    or exists (select 1 from match_results
               where match_id = p_match_id
                 and mvp_professional_guest_id = p_guest_id);

  -- Nothing to preserve: the guest never played, so the identity goes with the
  -- seat and the match keeps no trace of an addition that was a mistake.
  if not v_has_history then
    delete from match_professional_guests
    where id = p_guest_id and match_id = p_match_id;
  end if;

  -- A freed starting slot goes to the first community reserve, and only to
  -- another guest when there is none.
  --
  -- Not on a played match, for the same reason `add_professional_guest` does
  -- not: there is no reserve to promote out of, and re-cutting the roster would
  -- rewrite the record of a match that has already happened.
  if not (v_match.status = 'completed' or v_match.end_at <= now()) then
    perform rebalance_roster(p_match_id);
  end if;
  perform recompute_match_status(p_match_id);
end;
$$;


-- ---------------------------------------------------------------------------
-- rename_professional_guest -- effective definition from `0047`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
create or replace function public.rename_professional_guest(
  p_match_id uuid,
  p_guest_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_name is null or char_length(trim(p_name)) < 2
     or char_length(trim(p_name)) > 60 then
    raise exception 'INVALID_GUEST_NAME';
  end if;

  update match_professional_guests
  set display_name = trim(p_name)
  where id = p_guest_id and match_id = p_match_id;

  if not found then raise exception 'GUEST_NOT_FOUND'; end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- remove_played_professional_guest -- effective definition from `0059`.
-- Caller guard, and the role check becomes has_active_community_role, which
-- asks the community question too. Every other rule is byte-preserved.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_active_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- The match must actually have been played. This is a correction to a
  -- record, and a match still to come has no record to correct: taking a guest
  -- off one is the roster's operation, `remove_professional_guest`, which frees
  -- the seat and lets the reserve move up.
  --
  -- The condition is `set_completed_match_player`'s, character for character
  -- (0029, 0044): stored `completed`, or an end time that has passed. The
  -- screen only offers this on a played match, but the screen is not what
  -- decides -- the function is callable directly, and a state rule that lives
  -- only in the client is not a rule.
  if v_match.status <> 'completed' and v_match.end_at > now() then
    raise exception 'MATCH_NOT_COMPLETED';
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

  -- **And nothing else happens.** Three things this deliberately does not do,
  -- each of which would make it something other than a correction about one
  -- participant:
  --
  --   * **No `assign_professional_guest_teams`.** It recomputes A, B, A, B from
  --     the *current* registration order, so removing the first of three guests
  --     re-alternates the two who are left -- and this function would then have
  --     changed the historical side of somebody it was never asked about. On a
  --     match with a recorded result that call returns early and the bug is
  --     invisible; on a played match with no result yet it silently rewrites the
  --     record. Saying "this guest did not play" must alter the target and
  --     nobody else, so every surviving row keeps its team, its position and its
  --     `team_manually_overridden` exactly as they were.
  --
  --   * **No `rebalance_roster`.** There is no reserve to promote out of on a
  --     match that has been played, and re-cutting the roster would rewrite the
  --     record of who was in it.
  --
  --   * **No `recompute_match_status`.** A correction to who played is not a
  --     lifecycle event, and recomputing could take a match that has ended back
  --     to `open` or `full` because a seat is now free. `set_completed_match_
  --     player` -- the same correction for a community player, and the
  --     authoritative one -- does not call it either. The lifecycle is left
  --     exactly where it was.
  --
  -- No `detach_match_effects` / `attach_match_effects` either: migration `0046`
  -- gives a guest no rating, no player counter and no community figure, so
  -- there is nothing of theirs to take back and nothing to reapply.
end;
$$;


-- ---------------------------------------------------------------------------
-- create_match -- effective definition from `0054`.
-- Caller guard only: this function already refuses an inactive community with
-- its own stable error, which is preserved untouched.
create or replace function public.create_match(
  p_community_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players integer,
  p_description text default null,
  p_is_historical boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
  v_match_id uuid;
  v_historical boolean := coalesce(p_is_historical, false);
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select * into v_community from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if not v_community.is_active then raise exception 'COMMUNITY_INACTIVE'; end if;

  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_location is null or char_length(trim(p_location)) < 2 then
    raise exception 'INVALID_LOCATION';
  end if;
  if p_start_at is null or p_end_at is null then
    raise exception 'INVALID_TIME_RANGE';
  end if;

  -- Unchanged and unconditional: a match ends after it starts, whenever it was
  -- played. The historical path relaxes *when* a match may be, never whether
  -- its own two ends are the right way round.
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;

  -- THE TEMPORAL BRANCH ---------------------------------------------------------
  -- Two rules, and a match is under exactly one of them.
  --
  -- A normal match must still be entirely ahead of the caller: the refusal is
  -- the same statement, in the same place, with the same error name, so nothing
  -- about creating an ordinary fixture changes and an accidental past date is
  -- still refused.
  --
  -- A historical match must be entirely behind them. That second half is not
  -- symmetry for its own sake: without it "historical" would be a flag a client
  -- could set on a fixture next Friday, and the match would then be a record of
  -- something that has not happened — readable as completed by
  -- `v_completed_matches` the moment it was written, and closed to the
  -- registration its players were waiting for. `end_at` is the one that is
  -- tested because `end_at > start_at` was just established, so a match that has
  -- ended is a match that has wholly happened.
  if v_historical then
    if p_end_at > now() then raise exception 'HISTORICAL_NOT_PAST'; end if;
  else
    if p_start_at <= now() then raise exception 'START_IN_PAST'; end if;
  end if;
  -- END OF THE TEMPORAL BRANCH ---------------------------------------------------

  if p_starting_players is null
     or p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  -- max_registration is omitted on purpose: matches_set_capacity fills it.
  --
  -- It is left alone for a historical match too, though the reserve allowance it
  -- derives can never be used by one. Capacity is what `add_professional_guest`
  -- checks when an admin adds a stand-in who actually played, and narrowing it
  -- here would cap the recorded squad at the starting count for no reason the
  -- product asked for.
  insert into matches (
    community_id, created_by, title, location,
    start_at, end_at, starting_players, description, is_historical
  )
  values (
    p_community_id,
    auth.uid(),
    trim(p_title),
    trim(p_location),
    p_start_at,
    p_end_at,
    p_starting_players,
    case
      when p_description is null or trim(p_description) = '' then null
      else trim(p_description)
    end,
    v_historical
  )
  returning id into v_match_id;

  -- Announce it to the community, every member except the admin who just made
  -- it. `0039`'s statement, now with one condition on it.
  --
  -- **A historical match announces nothing.** The notice exists to reach people
  -- who have not acted yet, so they can come and register — and there is nothing
  -- for them to act on here. The fixture was played; the guard below makes sure
  -- nobody can register for it; and 'مباراة جديدة' would be false about a match
  -- that already finished. Suppressing it is the notice's own rule, so it lives
  -- with the notice.
  if not v_historical then
    perform create_notification(
        cm.user_id,
        v_match_id,
        'match_created',
        trim(p_title) || ' — ' || trim(p_location)
    )
    from community_members cm
    where cm.community_id = p_community_id
      and cm.user_id <> auth.uid();
  end if;

  return v_match_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- join_community -- effective definition from `0016`.
-- Caller guard only: this function already refuses an inactive community with
-- its own stable error, which is preserved untouched.
create or replace function public.join_community(p_community_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select join_policy into v_policy
  from communities
  where id = p_community_id and is_active;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;
  if v_policy <> 'OPEN' then
    raise exception 'JOIN_CODE_REQUIRED';
  end if;
  if is_community_member(p_community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (p_community_id, auth.uid(), 'player');

  return p_community_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- join_community_by_code -- effective definition from `0007`.
-- Caller guard only: this function already refuses an inactive community with
-- its own stable error, which is preserved untouched.
create or replace function public.join_community_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select id into v_community_id
  from communities
  where join_code = upper(trim(p_code))
    and is_active;

  if v_community_id is null then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  if is_community_member(v_community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (v_community_id, auth.uid(), 'player');

  return v_community_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- regenerate_join_code -- effective definition from `0015`.
-- Caller guard, plus the community test this function never had. `0015` locks
-- the row and raises COMMUNITY_NOT_FOUND when there is none, but it does not
-- read `is_active` -- so without this an active organizer could reissue the
-- join code of a suspended community. The existing admin-or-owner check is
-- unchanged and still runs first.
create or replace function public.regenerate_join_code(p_community_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_community_active boolean;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  -- Owner and admin both share invitations, so both can retire one.
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- Added by migration 0065. `0015` locked this row but never asked whether the
  -- community was active, and `COMMUNITY_NOT_FOUND` only ever meant "no such
  -- row". Reissuing a join code is join administration, and a suspended
  -- community admits none of that until a Platform Admin reactivates it -- so
  -- the same statement that takes the lock now also reads the state, and the
  -- refusal happens before a code is generated or written.
  select c.is_active
    into v_community_active
    from communities c
   where c.id = p_community_id
     for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;
  if not v_community_active then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  update communities
  set join_code = generate_join_code()
  where id = p_community_id
  returning join_code into v_code;

  return v_code;
end;
$$;


-- ---------------------------------------------------------------------------
-- register_for_match -- effective definition from `0045`.
-- Caller guard only: this function already refuses an inactive community with
-- its own stable error, which is preserved untouched.
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  -- A player registering themselves is refused once the match has started. That
  -- rule is untouched by the administrative unlock below.
  return register_player_in_match(p_match_id, auth.uid(), true);
end;
$$;


-- ---------------------------------------------------------------------------
-- set_community_logo -- effective definition from `0061`.
-- Caller guard only: this function already refuses an inactive community with
-- its own stable error, which is preserved untouched.
create or replace function public.set_community_logo(
  p_community_id uuid,
  p_logo_url text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stored text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- Asked before the row is touched, so a refusal never depends on what was
  -- found. 'admin' is the *minimum*: has_community_role orders owner above
  -- admin above player, so this authorizes an owner and an admin, and refuses a
  -- player and anybody who is not a member at all.
  if not public.has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  update public.communities c
     set logo_url = p_logo_url,
         updated_at = now()
   where c.id = p_community_id and c.is_active
  returning c.logo_url into v_stored;

  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  return v_stored;
end;
$$;


-- ---------------------------------------------------------------------------
-- withdraw_from_match -- effective definition from `0053`.
-- Caller guard, plus an explicit COMMUNITY_INACTIVE test placed after the
-- existing MATCH_NOT_FOUND so no current error semantic is displaced. There is
-- no role predicate here to make active-aware.
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype; v_registration match_registrations%rowtype; v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
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


-- ---------------------------------------------------------------------------
-- replace_match_lineup -- effective definition from `0059`.
-- Caller guard, plus an explicit COMMUNITY_INACTIVE test placed after the
-- existing MATCH_NOT_FOUND so no current error semantic is displaced. There is
-- no role predicate here to make active-aware.
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
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  perform 1 from matches where id = p_match_id for update;
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


-- ---------------------------------------------------------------------------
-- record_match_result -- effective definition from `0049`.
-- Caller guard, plus an explicit COMMUNITY_INACTIVE test placed after the
-- existing MATCH_NOT_FOUND so no current error semantic is displaced. There is
-- no role predicate here to make active-aware.
create or replace function public.record_match_result(
  p_match_id uuid,
  p_team_a_score int,
  p_team_b_score int,
  p_mvp_user_id uuid,
  p_goals jsonb default '[]'::jsonb,
  p_mvp_professional_guest_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participants int;
  v_total_goals int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  -- Added by migration 0065: a suspended community is frozen for new activity.
  if not exists (
    select 1 from matches m
    join communities c on c.id = m.community_id
    where m.id = p_match_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  -- Management is a community role (PD-07, PD-16): the same predicate that gates
  -- the lineup gates its result. Who created the match is attribution.
  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_team_a_score < 0 or p_team_b_score < 0 then
    raise exception 'INVALID_SCORE';
  end if;

  -- NEW: one best player, or none. Two would be two answers to one question.
  if p_mvp_user_id is not null and p_mvp_professional_guest_id is not null then
    raise exception 'INVALID_MVP';
  end if;

  -- Who played is the stored lineup. Without one there is no side for a player
  -- to have been on, so there is no winner to reward and no loser to charge --
  -- the rating engine has nothing to work from and the result cannot be taken.
  select count(*) into v_participants
  from match_team_assignments where match_id = p_match_id;
  if v_participants = 0 then
    raise exception 'LINEUP_REQUIRED';
  end if;

  if p_goals is null or jsonb_typeof(p_goals) <> 'array' then
    raise exception 'INVALID_GOALS';
  end if;

  -- A scorer's entry says they scored, so nothing and less than nothing are both
  -- refused rather than quietly dropped.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where coalesce((e->>'goals')::int, 0) <= 0
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- NEW: exactly one identity per entry, which is `match_goals`' own XOR asked
  -- before the insert so the caller gets a named refusal. Equality on the two
  -- booleans is true when they agree -- both set, or neither.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where (nullif(e->>'user_id', '') is not null)
        = (nullif(e->>'professional_guest_id', '') is not null)
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- Two entries for one participant is not a bigger number, it is the same fact
  -- recorded twice, and which of them counted would be arbitrary. Compared over
  -- the identity pair so a user and a guest are never confused for each other.
  if (
    select count(*) from (
      select distinct
        nullif(e->>'user_id', ''),
        nullif(e->>'professional_guest_id', '')
      from jsonb_array_elements(p_goals) as e
    ) d
  ) <> jsonb_array_length(p_goals) then
    raise exception 'INVALID_GOALS';
  end if;

  select coalesce(sum((e->>'goals')::int), 0) into v_total_goals
  from jsonb_array_elements(p_goals) as e;

  if v_total_goals <> p_team_a_score + p_team_b_score then
    raise exception 'GOALS_DO_NOT_MATCH_SCORE';
  end if;

  if p_mvp_user_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id = p_mvp_user_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- NEW: the same rule for a guest. A best player has to have played.
  if p_mvp_professional_guest_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id
      and professional_guest_id = p_mvp_professional_guest_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- A goal is credited to somebody who played it. Otherwise a rating could be
  -- raised for a player who was never in the match.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'user_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.user_id = (e->>'user_id')::uuid
      )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- NEW: and the same for a guest scorer.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'professional_guest_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.professional_guest_id
              = (e->>'professional_guest_id')::uuid
      )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- Nothing has been written yet: everything above refuses before the previous
  -- result is disturbed. From here the old result comes apart and the new one
  -- goes on, in one transaction.
  perform reverse_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, -1);

  delete from match_goals where match_id = p_match_id;

  insert into match_results (
    match_id, team_a_score, team_b_score, mvp_user_id,
    mvp_professional_guest_id, recorded_by
  )
  values (
    p_match_id, p_team_a_score, p_team_b_score, p_mvp_user_id,
    p_mvp_professional_guest_id, auth.uid()
  )
  -- NEW: both MVP columns are assigned, never one. Setting a user MVP over a
  -- stored guest MVP without clearing the guest would leave both non-null and
  -- violate `match_results_mvp_identity_check`.
  on conflict (match_id) do update set
    team_a_score = excluded.team_a_score,
    team_b_score = excluded.team_b_score,
    mvp_user_id = excluded.mvp_user_id,
    mvp_professional_guest_id = excluded.mvp_professional_guest_id,
    recorded_by = excluded.recorded_by;

  insert into match_goals
    (match_id, user_id, professional_guest_id, goals)
  select
    p_match_id,
    nullif(e->>'user_id', '')::uuid,
    nullif(e->>'professional_guest_id', '')::uuid,
    (e->>'goals')::int
  from jsonb_array_elements(p_goals) as e;

  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;


-- ---------------------------------------------------------------------------
-- delete_community -- effective definition from `0017`.
-- Caller guard, plus an explicit COMMUNITY_INACTIVE test placed after the
-- existing owner authorization, so a suspended community must be reactivated by
-- a Platform Admin before its Owner can delete it.
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- Added by migration 0065: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- Added by migration 0065: a suspended community must be reactivated by a
  -- Platform Admin before it can be deleted.
  if not exists (
    select 1 from communities c
    where c.id = p_community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;
  perform purge_community(p_community_id);
end;
$$;


-- ---------------------------------------------------------------------------
-- register_player_in_match -- effective definition from `0054a`.
-- Community and target-player guards only. This overload is service_role-only,
-- so the caller guard lives in its two authenticated wrappers; what is added
-- here is what stops a suspended player being newly registered by either.
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

  -- Added by migration 0065.
  --
  -- A suspended community takes no new registrations, and a suspended player is
  -- not entered into one. Both are about NEW participation only: registrations
  -- that already exist are left exactly where they are.
  if not exists (
    select 1 from communities c
    where c.id = v_match.community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;
  if not exists (
    select 1 from users u
    where u.id = p_user_id and u.is_active
  ) then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- THE ONLY ADDITION.
  --
  -- Outside `p_enforce_time_lock` on purpose. That flag says whether the caller
  -- may register somebody into a match that has started, which is an organizer's
  -- privilege over a live fixture. This is not that: a recorded match has no
  -- registration to make at all, for anybody, and no caller may turn it off.
  if v_match.is_historical then raise exception 'MATCH_HISTORICAL'; end if;

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
  if v_match.roster_order_mode = 'manual' then
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



-- ============================================================================
-- 7) register_player_in_match: both overloads, and why only one is guarded
-- ============================================================================
-- The privilege model was re-inspected against the tracked migrations rather
-- than assumed, and it says something worth recording plainly:
--
--   `register_player_in_match(uuid, uuid)`          -- `0041`, re-created `0054`
--   `register_player_in_match(uuid, uuid, boolean)` -- `0045` -> `0053` -> `0054a`
--
-- **Both are `service_role` only.** Every migration that grants either one does
-- `revoke execute ... from anon, authenticated, public` followed by
-- `grant execute ... to service_role`. Neither overload is client-executable,
-- and neither privilege scope is changed here.
--
-- The 3-argument overload is nevertheless the enforcement surface that matters,
-- because it is the single registration implementation both authenticated
-- wrappers reach -- `register_for_match(m)` calls it with `(m, auth.uid(), true)`
-- and `admin_add_player_to_match(m, u)` with `(m, u, false)`, which is what
-- `0054a`'s own header records. Guarding it there is what makes a suspended
-- target unable to be newly registered by either path, without a second
-- registration implementation.
--
-- The 2-argument overload is left **entirely unchanged**, deliberately: it is
-- `service_role` only, and nothing in the schema calls it -- the only callers
-- were the `0041` versions of the two wrappers, which `0045` replaced. Changing
-- a dormant server-only function would be a change with no caller to justify it,
-- and no existing server-only invariant requires one.



-- ============================================================================
-- 8) What this migration did not touch
-- ============================================================================
-- Stated so a later reader can confirm the contract from the file itself rather
-- than from a diff.
--
-- **Reads -- the whole of the `0063` model.** Not one SELECT policy, view or
-- read function is altered: `my_profile`, `player_profile`,
-- `communities_select_visible`, `v_public_communities`,
-- `v_public_upcoming_matches`, all five `0057` football views including
-- `v_football_community_player_stats` as `0063` left it, `v_community_members`,
-- `community_statistics_recency`, `community_join_code`,
-- `preview_community_invite`, every match / team / registration / result / goal
-- / rating / statistics SELECT policy, and both the avatar and community-logo
-- read policies.
--
-- **Authorization helpers.** `has_community_role`, `is_community_member`,
-- `is_match_community_member` and `is_match_community_admin` are all unmodified.
-- The ranking lives in exactly one place, as it always has.
--
-- **History.** Nothing is deleted or rewritten because of a suspension. There is
-- no cleanup trigger, no cascade and no backfill anywhere in this package. The
-- only DML in this file is inside function bodies, and it writes what those
-- functions already wrote plus, for the two Platform Admin RPCs, one
-- `communities` row and one `admin_audit_log` row. Memberships, registrations,
-- team assignments, professional guests, results, goals, ratings, statistics,
-- matches and communities are all preserved, and reactivation restores normal
-- behaviour from those rows.
--
-- **The historical-correction exceptions**, both explicit and both approved:
-- `set_completed_match_player` guards the caller and the community but **not the
-- target player**, so a suspended player may still be selected or restored as
-- the historical participant of a completed match; and `record_match_result`
-- likewise never asks whether the players its result refers to are active,
-- because somebody may have played and then been suspended before the organizer
-- recorded or corrected the score. `remove_played_professional_guest` keeps its
-- `0059` historical-survival body untouched but for the two guards.
--
-- **Hard delete.** `admin_delete_user`, `admin_delete_community` and
-- `admin_delete_match` are unchanged in definition and in privilege. The normal
-- Owner path, `delete_community`, is separately guarded above and now refuses a
-- suspended community with `COMMUNITY_INACTIVE` -- it must be reactivated by a
-- Platform Admin first.
--
-- **Also untouched:** `system_admins` and `is_system_admin()`; the three
-- `admin_list_*` RPCs; `admin_suspend_user` and `admin_reactivate_user`
-- (`0064`); `admin_audit_log`'s RLS and privileges; `record_admin_audit`'s
-- grant, which still admits no client role; `create_community` and
-- `register_push_token`, which `0064` already guards; the avatar write policies,
-- which `0064` already guards; the `users` write policy and the notification and
-- push policies, likewise `0064`'s; the 2-argument
-- `register_player_in_match`; and `auth.users` with every session, which this
-- MVP deliberately leaves valid.
