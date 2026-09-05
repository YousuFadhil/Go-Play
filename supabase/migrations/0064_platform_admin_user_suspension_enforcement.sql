-- ============ migrations/0064_platform_admin_user_suspension_enforcement.sql ============
-- Platform Admin, suspension: USER suspension, activated.
--
-- ## PACKAGE CONTRACT -- DO NOT APPLY THIS MIGRATION REMOTELY BY ITSELF
--
-- `0062` through `0065` form **one suspension activation package**. `0064` is
-- not independently approved for remote application, and no suspension
-- operation may be used against the live project until the entire package is
-- built, reviewed, live-prechecked and explicitly approved by the Product Owner
-- and the Chief Architect.
--
-- ## 0064 IS INTENTIONALLY INCOMPLETE WITHOUT 0065
--
-- This is the most important sentence in the file. A database left after `0064`
-- and before the community enforcement in `0065` is a **partial-enforcement
-- state**: a suspended user's own writes are refused, but a suspended Owner or
-- Admin still commands their community. Every community-scoped path -- match
-- creation and editing, rosters, lineups, results, guests, role management,
-- ownership transfer, community deletion, the community logo -- is gated by
-- `has_community_role` or `is_match_community_admin`, and swapping those for
-- the active-aware predicate is `0065`'s work, not this file's.
--
-- That gap is deliberate and is safe only because of the package contract
-- above: `0064` is never served on its own.
--
-- ## WHAT THIS DOES
--
--   1) `admin_suspend_user` and `admin_reactivate_user` -- the two Platform
--      Admin actions. System Admin only, idempotent, each writing exactly one
--      audit event through `0062`'s writer in the same transaction as the state
--      change.
--   2) Six RLS policies and three avatar Storage policies gain an active-user
--      requirement, as an AND. Ownership semantics are preserved exactly.
--   3) `create_community` and `register_push_token` gain an early caller guard.
--
-- ## THE ERROR CODE
--
-- `ACCOUNT_SUSPENDED`, and it is new. The schema was searched first: the only
-- existing code in this family is `COMMUNITY_INACTIVE` (`0026`, `0039`,
-- `0054`), which is about a community and not about the caller's account.
--
-- It is deliberately not raised by the policies in sections 3-6. A policy
-- cannot raise; it filters. A suspended user's write matches no row and the
-- statement affects nothing, which is what a policy refusing looks like. The
-- code exists for the two functions in section 7, which can speak.
--
-- ## SESSIONS
--
-- No Supabase Auth session is revoked, no `auth.users` row is banned, no Auth
-- Admin API is called, no Edge Function is added and no service-role credential
-- is involved. A suspended user may technically retain a valid JWT; the
-- database is what refuses their mutations. Placing such an account into an
-- Account Suspended state in the client is later Flutter work.
--
-- Idempotent throughout: `create or replace function`, and a guarded
-- `drop policy` before each `create policy`.



-- ============================================================================
-- 1) admin_suspend_user()
-- ============================================================================
-- System Admin only, and the check is the first statement, exactly as the six
-- `admin_*` functions in `0017` do it. `is_system_admin()` is false for a null
-- `auth.uid()`, so an unauthenticated caller is refused by the same line --
-- which is why `0017`'s admin functions carry no separate session test and this
-- one does not either.
--
-- **Idempotency is a true no-op, not a refusal.** Suspending an account that is
-- already inactive succeeds and changes nothing at all: `users` is not written,
-- the existing `suspended_at` / `suspended_by` / `suspension_reason` are left
-- exactly as they are, and no second audit row is created. The function
-- deliberately does **not** try to work out whether an inactive row is a
-- suspension or a legacy deactivation -- it has no way to know, and guessing
-- would either overwrite a real record or invent one.
--
-- Guard order follows the approved specification: authorization, existence,
-- self, System Admin, **the idempotent no-op**, and only then the reason. The
-- no-op comes before the reason on purpose: the refusals above it are about who
-- may be suspended and are asked whatever the target's state, while the reason
-- is an input to an act that, past this point, is not going to happen. A call
-- naming an already-inactive account succeeds whatever it passes as a reason.
--
-- `for update` locks the target row for the rest of the transaction, which is
-- what makes read-then-write atomic here and what makes two concurrent
-- administrators safe (section 5). It is the same device `delete_community`,
-- `update_match` and `remove_player` already use.
create or replace function public.admin_suspend_user(
  p_user_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_reason text;
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'CANNOT_SUSPEND_SELF';
  end if;

  -- A System Admin account is managed outside the app, exactly as
  -- `admin_delete_user` (`0017`) has it. Otherwise the last administrator could
  -- be locked out from a phone.
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_SUSPEND_SYSTEM_ADMIN';
  end if;

  -- Already inactive. Success, and nothing moves: not the row, not the
  -- metadata, and not the audit log, which must not carry an event for an act
  -- that did not happen.
  --
  -- The reason is deliberately not looked at on this path, and that ordering is
  -- the whole of the idempotency contract. Asking to suspend an account that is
  -- already suspended is asking for a state it is already in; a desired-state
  -- call is not refused for the shape of an argument it never needed. So a null,
  -- empty or whitespace reason returns success here rather than
  -- `REASON_REQUIRED`.
  if not v_user.is_active then
    return;
  end if;

  -- Only an active target reaches this line, so `REASON_REQUIRED` can only ever
  -- be raised by a call that would really have suspended somebody.
  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'REASON_REQUIRED';
  end if;

  update users set
    is_active         = false,
    suspended_at      = now(),
    suspended_by      = auth.uid(),
    suspension_reason = v_reason
  where id = p_user_id;

  -- One event, in this transaction. There is deliberately **no exception
  -- handler** around this call: if the audit write fails, the suspension above
  -- must fail with it. A state change nobody can account for is worse than a
  -- refused request. The label is read from the row locked before the update,
  -- so it is the identity the action was taken against.
  perform record_admin_audit(
    'USER_SUSPENDED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_reason
  );
end;
$$;

comment on function public.admin_suspend_user(uuid, text) is
  'Platform Admin: suspends an account by setting users.is_active false and '
  'recording who acted, when and why. System Admin only. Refuses the caller '
  'themselves and any System Admin, and requires a reason. Idempotent: '
  'suspending an already inactive account succeeds, writes nothing and creates '
  'no second audit event (migration 0064).';



-- ============================================================================
-- 2) admin_reactivate_user()
-- ============================================================================
-- The mirror, with three deliberate absences. `CANNOT_SUSPEND_SELF`,
-- `CANNOT_SUSPEND_SYSTEM_ADMIN` and `REASON_REQUIRED` do not apply to
-- reactivation: the approved contract imposes none of them, and inventing a
-- refusal the product did not ask for is a product decision this migration is
-- not entitled to make. An administrator may reactivate themselves, and may
-- reactivate a System Admin.
--
-- Suspension metadata is cleared, so the audit event becomes the only surviving
-- record of the suspension that just ended. It is therefore written from values
-- captured **before** the clear, and in the same transaction: if the audit
-- fails, the reactivation rolls back with it and the metadata stays.
create or replace function public.admin_reactivate_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- Already active. Success, no write, no metadata change, no audit event.
  if v_user.is_active then
    return;
  end if;

  update users set
    is_active         = true,
    suspended_at      = null,
    suspended_by      = null,
    suspension_reason = null
  where id = p_user_id;

  -- `v_user` still holds the row as it was before the clear, which is where
  -- both the label and the reason being reversed come from.
  perform record_admin_audit(
    'USER_REACTIVATED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_user.suspension_reason
  );
end;
$$;

comment on function public.admin_reactivate_user(uuid) is
  'Platform Admin: restores an account by setting users.is_active true and '
  'clearing the suspension metadata, after the audit event has preserved it. '
  'System Admin only; no self or System Admin restriction applies. Idempotent: '
  'reactivating an active account succeeds and writes no audit event '
  '(migration 0064).';

-- Privileges, matching the six `admin_*` functions in `0017`. Authorization is
-- not the grant: an ordinary account holder reaches these functions and is
-- refused by `is_system_admin()` inside them.
--
-- `record_admin_audit` is reached from inside both, which is legitimate because
-- a `security definer` function runs as its owner -- exactly how
-- `delete_community` reaches `purge_community`. Its own grant is untouched and
-- it remains executable by no client role.
revoke execute on function public.admin_suspend_user(uuid, text)
  from anon, public;
revoke execute on function public.admin_reactivate_user(uuid) from anon, public;

grant execute on function public.admin_suspend_user(uuid, text) to authenticated;
grant execute on function public.admin_reactivate_user(uuid) to authenticated;



-- ============================================================================
-- 3) The account holder's own profile
-- ============================================================================
-- `users_update_own_profile` (`0001`) recreated with its original rule intact
-- and `public.is_current_user_active()` (`0062`) added as a further AND in both
-- clauses. Nothing is widened: it still admits only the row's owner, under the
-- same name, command and role. A suspended caller simply matches no row.
--
-- Both USING and WITH CHECK are rebuilt, because an UPDATE that could be aimed
-- at a row the caller may no longer touch is only half refused otherwise.
--
-- `is_current_user_active()` is `security definer`, which is what makes it
-- usable in a policy on `public.users`: an invoker-rights predicate reading
-- `users` from inside a policy on `users` would recurse. `0062` created it for
-- this position, and no migration in this schema sets FORCE ROW LEVEL SECURITY,
-- so the definer owner genuinely bypasses RLS.
--
-- The column-level UPDATE grants from `0022`, `0031` and `0043` are untouched:
-- this policy decides rows, those grants decide columns, and only the row rule
-- changes here. No SELECT policy on `users` is altered.
drop policy if exists "users_update_own_profile" on public.users;
create policy "users_update_own_profile"
  on public.users
  for update
  to authenticated
  using (auth.uid() = id and public.is_current_user_active())
  with check (auth.uid() = id and public.is_current_user_active());



-- ============================================================================
-- 4) Notifications
-- ============================================================================
-- `notifications_update_own` and `notifications_delete_own` (`0006`), rebuilt
-- with the same ownership predicate and the active requirement added. Marking a
-- notice read and deleting one are both writes, and a suspended account
-- performs neither.
--
-- `notifications_select_own` is deliberately not touched: a suspended reader may
-- still read their own notices. Only writing stops.
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using (user_id = auth.uid() and public.is_current_user_active())
  with check (user_id = auth.uid() and public.is_current_user_active());

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid() and public.is_current_user_active());



-- ============================================================================
-- 5) Push preferences
-- ============================================================================
-- `push_prefs_insert_own` and `push_prefs_update_own` (`0036`). INSERT carries
-- only a WITH CHECK and UPDATE carries both, which is how they were written and
-- how they are rebuilt. `push_prefs_select_own` is not touched.
drop policy if exists "push_prefs_insert_own" on public.notification_push_preferences;
create policy "push_prefs_insert_own"
  on public.notification_push_preferences for insert to authenticated
  with check (user_id = auth.uid() and public.is_current_user_active());

drop policy if exists "push_prefs_update_own" on public.notification_push_preferences;
create policy "push_prefs_update_own"
  on public.notification_push_preferences for update to authenticated
  using (user_id = auth.uid() and public.is_current_user_active())
  with check (user_id = auth.uid() and public.is_current_user_active());



-- ============================================================================
-- 6) Push tokens
-- ============================================================================
-- `push_tokens_delete_own` (`0036`) is the only write policy on this table --
-- registration goes through `register_push_token`, which section 7 guards.
-- `push_tokens_select_own` is not touched.
drop policy if exists "push_tokens_delete_own" on public.notification_push_tokens;
create policy "push_tokens_delete_own"
  on public.notification_push_tokens for delete to authenticated
  using (user_id = auth.uid() and public.is_current_user_active());



-- ============================================================================
-- 7) The two account-level RPCs
-- ============================================================================
-- These are the only client-callable mutating functions that belong to a *user*
-- rather than to a community, so they are the only two in scope for this cycle.
-- Each gains one guard, placed immediately after the session check and before
-- anything is validated or written. Nothing else about either changes: same
-- signature, same return type, same business rules, same inserts, same token
-- semantics, same privileges. Neither body was retyped -- each was extracted
-- from its current effective definition and the guard inserted at one computed
-- line.

-- `create_community` (`0016`). Guarded before the join-policy validation so a
-- suspended caller is told why they were refused rather than being sent to
-- correct an argument that was never the problem. No community-is-active logic
-- is added here: creating a community has no community to test.
create or replace function public.create_community(
  p_name text,
  p_description text,
  p_join_policy text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0064: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if p_join_policy not in ('OPEN', 'CODE_REQUIRED') then
    raise exception 'INVALID_JOIN_POLICY';
  end if;

  insert into communities (owner_id, name, description, join_policy)
  values (auth.uid(), p_name, p_description, p_join_policy)
  returning id into v_id;

  insert into community_members (community_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

revoke execute on function public.create_community(text, text, text)
  from anon, public;
grant execute on function public.create_community(text, text, text)
  to authenticated;

-- `register_push_token` (`0038`). The body below is that migration's, unchanged
-- but for the guard -- including the delete that takes a token away from
-- whoever held it before, which is a privacy rule and not something this
-- migration has any business touching. No Firebase or push architecture
-- changes.
create or replace function public.register_push_token(
  p_token text, p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Added by migration 0064: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'INVALID_PLATFORM';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'INVALID_TOKEN';
  end if;

  -- A phone that was somebody else's, sold or handed over, keeps its Firebase
  -- token. Without this the previous owner keeps receiving the new owner's
  -- notices, which is a privacy failure rather than a duplicate row.
  --
  -- A shared browser profile is the same problem with a shorter fuse: two
  -- accounts signing in from one browser produce the *same* web token, so the
  -- second sign-in has to take it from the first. That is what this delete
  -- does, and it is why signing out removes the row (`PushService.signOut`)
  -- rather than leaving it to be overwritten later.
  delete from notification_push_tokens
  where token = p_token and user_id <> v_user;

  insert into notification_push_tokens (user_id, token, platform)
  values (v_user, p_token, p_platform)
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

revoke execute on function public.register_push_token(text, text)
  from anon, public;
grant execute on function public.register_push_token(text, text)
  to authenticated;



-- ============================================================================
-- 8) The profile picture
-- ============================================================================
-- Three Storage policies (`0031`), rebuilt with the same bucket test and the
-- same folder-ownership rule, plus the active-account requirement. The function
-- is schema-qualified because these policies are evaluated in the `storage`
-- schema, where `public` is not on the search path.
--
-- `avatars_read_all` is not touched: a suspended player's picture must go on
-- rendering beside the football history `0063` keeps readable.
--
-- **The community-logo Storage policies are deliberately not touched here.**
-- `community_logos_insert_organizer`, `community_logos_update_organizer` and
-- `community_logos_delete_organizer` (`0061`) authorize on
-- `has_community_role`, which makes them community-scoped -- and community
-- scope is `0065`.
drop policy if exists "avatars_write_own" on storage.objects;
create policy "avatars_write_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_current_user_active()
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_current_user_active()
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_current_user_active()
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_current_user_active()
  );



-- ============================================================================
-- 9) What this migration did not touch
-- ============================================================================
-- Stated so a later reader can confirm the Cycle 1E-3 contract from the file
-- itself rather than from a diff.
--
-- **Community-scoped enforcement, all deferred to `0065`.** None of the
-- following is modified here, and each remains reachable by a suspended user
-- until `0065` lands -- which is why `0064` is not deployed alone:
--
--   `communities_update_owner`, `community_members_delete_self`, the `matches`
--   write policies, the `match_team_assignments` write policies,
--   `join_community`, `join_community_by_code`, `regenerate_join_code`,
--   `transfer_ownership`, `set_member_role`, `remove_member`,
--   `delete_community`, `create_match`, `update_match`, `delete_match`,
--   `register_for_match`, both `register_player_in_match` overloads,
--   `withdraw_from_match`, `remove_player`, `admin_add_player_to_match`,
--   `replace_match_lineup`, `set_completed_match_player`,
--   `set_match_roster_order`, `swap_match_participants`,
--   `add_professional_guest`, `remove_professional_guest`,
--   `rename_professional_guest`, `remove_played_professional_guest`,
--   `record_match_result`, `set_community_logo`, the community-logo Storage
--   policies, and `is_match_community_admin`.
--
-- **Reads.** Not one SELECT policy is altered, on any table or in any schema.
-- `my_profile()` and `player_profile()` keep the `0063` behaviour that makes a
-- suspended player readable; `communities_select_visible` keeps `0063`'s
-- member-read rule; `v_community_members`, the public football views (`0057`),
-- both public discovery views and every match, team, result, rating and
-- statistics read model are untouched.
--
-- **History.** Nothing is deleted or rewritten because of a suspension. There
-- is no DML in this file outside the two admin function bodies, and what those
-- write is one row of `users` and one row of `admin_audit_log`. No membership,
-- registration, team assignment, result, goal, rating, statistic, community or
-- match is touched.
--
-- **Hard delete.** `admin_delete_user`, `admin_delete_community` and
-- `admin_delete_match` are unchanged in definition and in privilege.
--
-- **Also untouched:** `system_admins` and `is_system_admin()`; the three
-- `admin_list_*` RPCs; `admin_audit_log`'s privileges and RLS;
-- `record_admin_audit`'s grant, which still admits no client role;
-- `has_community_role`, `is_community_member`, `is_match_community_member`;
-- `has_active_community_role` (`0062`), which is still called by nothing and is
-- `0065`'s instrument; and `auth.users` with every session, which this MVP
-- deliberately leaves valid.
