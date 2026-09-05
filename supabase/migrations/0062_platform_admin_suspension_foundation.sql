-- ============ migrations/0062_platform_admin_suspension_foundation.sql ============
-- Platform Admin, suspension: the foundation, and deliberately nothing that acts.
--
-- ## DO NOT APPLY THIS MIGRATION REMOTELY BY ITSELF
--
-- `0062` is the first file of the **Platform Admin suspension package**. It is
-- **not approved for remote application on its own**, and neither is any later
-- file of that package until all of them exist. Nothing here may reach the live
-- Supabase project until the whole package has been built, reviewed,
-- live-prechecked against the real schema, and explicitly approved by the
-- Product Owner and the Chief Architect.
--
-- ## WHAT THIS ADDS
--
--   1) Suspension *metadata* on `users` and `communities`. Not a status: the
--      status is `is_active`, which already exists and is untouched here.
--   2) `admin_audit_log` -- the administrative audit trail this product has
--      never had.
--   3) `record_admin_audit(...)` -- the internal writer, callable by no client.
--   4) `is_current_user_active()` and `has_active_community_role(...)` -- two
--      predicates, wired into nothing.
--
-- ## ZERO PRODUCT-BEHAVIOUR CHANGE, AND HOW THAT IS TRUE
--
-- Not one policy is created, dropped or altered. Not one existing function is
-- replaced. No row is written and nothing is backfilled. The new predicates are
-- called by nothing, and the audit log is reachable by nobody, so after this
-- file is applied every account, every community and every existing RPC behaves
-- exactly as it did before.
--
-- The new columns are invisible to clients without a single statement being
-- issued about them. `0022` revoked table-level UPDATE on `public.users` and
-- `0056` revoked table-level SELECT on both `public.users` and
-- `public.communities`, each granting named columns back; a role holding only
-- column-level privileges gains nothing when a column is added later. `0061`
-- relied on exactly that property when it had to name `logo_url` explicitly to
-- make it readable. Nothing below names any of the six new columns, so none of
-- them is readable, and on `users` none is writable either.
--
-- ## WHAT IS NOT HERE, ON PURPOSE
--
-- Listed because the absences are the design:
--
--   * No suspend or reactivate RPC, and no authorization check anywhere.
--   * No enforcement. `is_current_user_active()` and
--     `has_active_community_role(...)` are wired into no policy and no function.
--   * Nothing from the current `0061`-era surface is touched -- not
--     `communities.logo_url`, `set_community_logo`, the community-logo storage
--     policies, `community_statistics_recency`,
--     `remove_played_professional_guest`, `replace_match_lineup`, either
--     `register_player_in_match` overload, the professional-guest RPCs, the
--     public football views, or the profile functions.
--   * `admin_delete_user`, `admin_delete_community` and `admin_delete_match`
--     are untouched in definition and in privilege. The deployed Admin client
--     still calls all three.
--   * `has_community_role` is not modified. Section 7 calls it.
--
-- Idempotent throughout: `add column if not exists`, `create table if not
-- exists`, `create index if not exists`, `create or replace function`, and
-- revoke/grant, all of which may be re-run.



-- ============================================================================
-- 1) Suspension metadata on public.users
-- ============================================================================
-- **`is_active` remains the authoritative account state.** These three columns
-- do not answer "is this account suspended" -- `is_active` answers that, as it
-- has since `0001`. They answer "what does the Platform Admin record say about
-- the suspension", which is a different question and one nothing has been able
-- to answer until now.
--
-- A second flag was the obvious alternative and is the wrong one: a boolean and
-- an enum that must agree are two sources of truth that eventually will not,
-- and every read path in this schema already tests `is_active`.
--
-- All three are nullable, and that is load-bearing. Every account that predates
-- this migration gets null in all three, including any that is already
-- `is_active = false`. There is deliberately **no CHECK** tying these columns to
-- `is_active` in either direction, because such a constraint would be evaluated
-- against those rows and would refuse them.
--
-- `suspended_by` carries **no foreign key**. That is not an oversight. A
-- reference to `public.users` would have to choose a delete action and both
-- available choices are wrong: ON DELETE CASCADE would erase the record of who
-- acted, and NO ACTION / RESTRICT -- the default -- would make
-- `admin_delete_user` (`0017`) fail the moment the account being deleted had
-- ever suspended anybody. That is a behaviour change, and this migration is not
-- permitted one.
alter table public.users
  add column if not exists suspended_at timestamptz,
  add column if not exists suspended_by uuid,
  add column if not exists suspension_reason text;

comment on column public.users.suspended_at is
  'Platform Admin suspension metadata (migration 0062). When the suspension '
  'was recorded. NOT the authoritative state -- users.is_active is, and is '
  'unchanged by this migration. Null on every row that predates 0062.';
comment on column public.users.suspended_by is
  'Platform Admin suspension metadata (migration 0062). The System Admin who '
  'acted. Deliberately carries no foreign key: the record must outlive the '
  'actor, and a reference would either cascade the record away or block '
  'admin_delete_user.';
comment on column public.users.suspension_reason is
  'Platform Admin suspension metadata (migration 0062). Free text recorded by '
  'the acting System Admin. Never read to decide anything.';

-- No grant is issued for these three columns, and none is needed to keep them
-- from clients. `0022` revoked table-level UPDATE on this table and `0056`
-- revoked table-level SELECT, each granting named columns back; neither list
-- gains a name here. As of this statement `authenticated` can neither read nor
-- write any of the three. Adding them to either list is a later decision.



-- ============================================================================
-- 2) Suspension metadata on public.communities
-- ============================================================================
-- The same three columns, for the same reasons, with the same absence of a
-- foreign key on `suspended_by`: `admin_delete_user` deletes accounts, and an
-- account that has suspended a community must remain deletable.
--
-- Every column this table already carries is untouched, `logo_url` (`0061`)
-- included. This migration adds three names and changes nothing else about the
-- table, its privileges or its policies.
alter table public.communities
  add column if not exists suspended_at timestamptz,
  add column if not exists suspended_by uuid,
  add column if not exists suspension_reason text;

comment on column public.communities.suspended_at is
  'Platform Admin suspension metadata (migration 0062). When the suspension '
  'was recorded. NOT the authoritative state -- communities.is_active is, and '
  'is unchanged by this migration.';
comment on column public.communities.suspended_by is
  'Platform Admin suspension metadata (migration 0062). The System Admin who '
  'acted. Deliberately carries no foreign key -- see the same column on '
  'public.users.';
comment on column public.communities.suspension_reason is
  'Platform Admin suspension metadata (migration 0062). Free text recorded by '
  'the acting System Admin. Never read to decide anything.';

-- READ is closed by the same mechanism as on `users`: `0056` revoked
-- table-level SELECT here and granted named columns back, and `0061` had to
-- name `logo_url` explicitly for exactly that reason. These three are not
-- named, so they are not selectable.
--
-- WRITE IS A DIFFERENT MATTER, AND THIS MIGRATION IS NOT THE PLACE FOR IT.
--
-- Unlike `users`, `public.communities` has never had its table-level UPDATE
-- privilege revoked -- no migration from `0002` to `0061` does so -- and a
-- table-level UPDATE grant extends automatically to columns added later. So an
-- owner, whom `communities_update_owner` (`0008`) already admits, can write
-- these three columns through PostgREST.
--
-- In this foundation that is inert: nothing reads these columns, nothing
-- derives anything from them, and the owner cannot read back what they wrote
-- because SELECT is closed. It becomes real the moment a later migration reads
-- them. The fix is `revoke update on public.communities` followed by a
-- named-column grant -- the pattern `0022` established on `users` and `0056`
-- reused for SELECT -- and it belongs with the enforcement work, because it
-- changes existing UPDATE semantics on a live table and this file is required
-- to change none. Recorded here so it travels with the code.



-- ============================================================================
-- 3) public.admin_audit_log
-- ============================================================================
-- The administrative audit trail: what a System Admin did, to what, and when.
--
-- This is not business history. `rating_history` (`0022`) records what happened
-- to a rating; it has no actor and it cascades away with its subject. An audit
-- log that cascaded away with its subject would be erased by the very act it
-- exists to record, which is why every identifier below is a bare `uuid` and
-- **not a reference**:
--
--   * `actor_user_id` -- no FK. The System Admin may later be deleted.
--   * `target_id`     -- no FK. Deleting the target is itself an auditable act,
--                        and `admin_delete_user` / `admin_delete_community`
--                        (`0017`) do exactly that.
--
-- The two `*_snapshot` columns are what make that survivable. An id whose row
-- is gone is unreadable forever; the snapshot is what the record looked like
-- when the act happened, copied at write time. They are snapshots and are never
-- refreshed.
--
-- `gen_random_uuid()` for the key, which is this schema's convention throughout
-- (`0002`, `0003`, `0004`, `0006`, `0008`, `0018`, `0022`, `0036`, `0044`).
create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null,
  actor_email_snapshot text,
  action text not null
    constraint admin_audit_log_action_check check (action in (
      'USER_SUSPENDED',
      'USER_REACTIVATED',
      'COMMUNITY_SUSPENDED',
      'COMMUNITY_REACTIVATED'
    )),
  target_type text not null
    constraint admin_audit_log_target_type_check
      check (target_type in ('USER', 'COMMUNITY')),
  target_id uuid not null,
  target_label_snapshot text,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.admin_audit_log is
  'Platform Admin administrative audit trail (migration 0062). Append-only. '
  'Not business history: rating_history is that. Actor and target are bare '
  'uuids with no foreign key, so a record outlives the account or community it '
  'describes; the *_snapshot columns are what keep it legible afterwards. '
  'Unreachable by any client -- a System-Admin-gated read RPC comes later.';

comment on column public.admin_audit_log.actor_user_id is
  'The System Admin who acted. No FK, deliberately: the record must survive '
  'that account being deleted.';
comment on column public.admin_audit_log.actor_email_snapshot is
  'The actor''s email as it read at write time, copied from auth.users. Null '
  'when it could not be obtained; never refreshed afterwards.';
comment on column public.admin_audit_log.target_id is
  'The user or community acted upon. No FK, deliberately: deleting the target '
  'is itself an auditable act.';
comment on column public.admin_audit_log.target_label_snapshot is
  'The target''s name as it read at write time. The only thing that keeps an '
  'entry legible once the target is gone; never refreshed.';
comment on column public.admin_audit_log.metadata is
  'Structured detail for the action. Defaults to an empty object so a reader '
  'never has to distinguish "no detail" from "no value".';

-- Indexes: three, one per approved access path, and no others.
--
--   * the newest entries   -- the audit screen's default view;
--   * one target's history -- "what has been done to this community";
--   * one actor's history  -- "what has this administrator done".
--
-- `created_at desc` is in each so the ordering the reader always wants is
-- served by the index rather than by a sort. Nothing here is speculative.
create index if not exists admin_audit_log_created_at_idx
  on public.admin_audit_log (created_at desc);
create index if not exists admin_audit_log_target_idx
  on public.admin_audit_log (target_type, target_id, created_at desc);
create index if not exists admin_audit_log_actor_idx
  on public.admin_audit_log (actor_user_id, created_at desc);



-- ============================================================================
-- 4) The audit log is reachable by no client at all
-- ============================================================================
-- Two independent mechanisms, because `0034` is what happens when only one is
-- relied on.
--
-- **RLS with no policies.** This is the `system_admins` (`0017`) and
-- `push_config` (`0036`) pattern: row-level security on, and not a single
-- policy, so every client role is denied every row for every command. There is
-- deliberately no SELECT policy -- audit reads will go through a
-- `SECURITY DEFINER` RPC gated on `is_system_admin()`, not through a policy --
-- and deliberately no INSERT policy either, because the only writer is section
-- 5, which is `security definer` and runs past RLS.
alter table public.admin_audit_log enable row level security;

-- **And the privileges themselves.** Supabase ships a default-privileges rule
-- on schema `public` that grants ALL to `anon` and `authenticated` on every
-- newly created table, and it fires before a migration's own statements are
-- reached. `0034` exists because that rule turned a read-only view into an
-- anonymous DELETE against `public.communities`; `0056` re-asserted the same
-- revokes for the same reason. This table is created in that schema and arrives
-- carrying those privileges, so they are taken back here.
--
-- RLS would already deny a client that held them. That is not a reason to leave
-- them: a grant that is merely unreachable is one policy mistake away from
-- being reachable, and TRUNCATE in particular is **not filtered by RLS at all**
-- -- it is a table-level privilege, and a role holding it could empty an
-- append-only audit log in a single statement.
revoke all on public.admin_audit_log from anon, authenticated, public;

-- Named individually as well, in the manner `0034` established, so this file
-- states which privileges rather than leaving a reader to work out what `all`
-- covered. SELECT is included because, unlike `0034`'s read-only views, this
-- table must not be readable either.
revoke select, insert, update, delete, truncate, references, trigger
  on public.admin_audit_log
  from anon, authenticated, public;

-- No grant follows. That is the section.



-- ============================================================================
-- 5) record_admin_audit() -- the internal writer
-- ============================================================================
-- The one way a row reaches `admin_audit_log`. The suspend and reactivate RPCs
-- will call it; nothing else can, because it is granted to nobody.
--
-- **It does not decide who may act.** There is no `is_system_admin()` check in
-- here, deliberately. Authorization belongs to the top-level RPC, which knows
-- what is being attempted and can refuse before anything is written; a
-- predicate in both places is two rules that can drift. `0017` already settled
-- this shape when `purge_match` / `purge_community` / `purge_membership` were
-- split out with their authorization left in the callers.
--
-- **The actor is `auth.uid()` and is never a parameter.** `actor_user_id` is
-- NOT NULL, and a writer that let its caller name the actor would be a writer
-- that could be handed the wrong one. A missing session is refused with the
-- same `NOT_AUTHENTICATED` every other function in this schema raises -- which
-- is a statement about the session, not a permission decision.
--
-- The email snapshot is best-effort and must never be the reason an act goes
-- unrecorded. `auth.users` is readable here for the same reason
-- `admin_list_users` (`0017`) can join it: `security definer` runs as the
-- function owner. If the row is gone, the address is null, or the read raises
-- for any reason at all, the handler below discards it and the audit row is
-- written regardless. A record with no email is worth more than no record.
--
-- No dynamic SQL: every statement is static, and no identifier is interpolated.
create or replace function public.record_admin_audit(
  p_action text,
  p_target_type text,
  p_target_id uuid,
  p_target_label_snapshot text default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Best-effort, and the handler is the important half. See the header.
  begin
    select au.email::text into v_email
    from auth.users au
    where au.id = v_actor;
  exception when others then
    v_email := null;
  end;

  insert into public.admin_audit_log (
    actor_user_id,
    actor_email_snapshot,
    action,
    target_type,
    target_id,
    target_label_snapshot,
    reason,
    metadata
  )
  values (
    v_actor,
    v_email,
    p_action,
    p_target_type,
    p_target_id,
    p_target_label_snapshot,
    -- An empty reason and no reason are the same fact, stored as the absence.
    case when p_reason is null or trim(p_reason) = '' then null
         else trim(p_reason) end,
    -- A caller passing null means "no detail", which is the default rather than
    -- a null column: `metadata` is NOT NULL.
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.record_admin_audit(text, text, uuid, text, text, jsonb) is
  'Writes one row to admin_audit_log. Internal: revoked from every client '
  'role, called only by Platform Admin RPCs, which do their own authorization. '
  'The actor is auth.uid() and is never a parameter. The email snapshot is '
  'best-effort -- its absence never prevents the record (migration 0062).';

-- Revoked from every client role and granted to none, exactly as `purge_match`,
-- `purge_community` and `purge_membership` (`0017`) are, and
-- `apply_match_rating_effects` (`0033`) and `dispatch_push_notification`
-- (`0036`). PUBLIC is included because a function is executable by PUBLIC by
-- default, and revoking the two client roles alone would leave that standing.
revoke execute on function
  public.record_admin_audit(text, text, uuid, text, text, jsonb)
  from anon, authenticated, public;



-- ============================================================================
-- 6) is_current_user_active() -- the caller's own account state
-- ============================================================================
-- Answers one question about one account: does the signed-in caller have an
-- active row in `public.users`. It takes no argument, so like `is_system_admin`
-- (`0017`) and unlike `has_community_role`, it cannot be pointed at anybody
-- else and is not an oracle about other people.
--
-- **Fails closed.** No session, no profile row, or a row with `is_active` false
-- all produce false. `exists` gives that shape for free: the only way to get
-- true is for the row to be there and to be active.
--
-- `security definer` for two reasons, and the second is the one that matters.
-- The first is convention -- every predicate this schema uses in policy
-- evaluation is definer (`0002`, `0008`, `0043`). The second is recursion: a
-- policy on `public.users` that called an invoker-rights version of this would
-- send the policy back through `users` to evaluate itself. `0002` recorded that
-- trap when the first membership helper was written and `0043` restated it, and
-- this function will later be used in exactly the position that triggers it.
-- No migration in this schema sets FORCE ROW LEVEL SECURITY, so the definer
-- owner genuinely bypasses RLS here.
--
-- **Wired into nothing.** No policy and no function calls this today.
create or replace function public.is_current_user_active()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from users u
    where u.id = auth.uid()
      and u.is_active
  );
$$;

comment on function public.is_current_user_active() is
  'Whether the signed-in caller has an active public.users row. Fails closed: '
  'no session, no row, or is_active false all answer false. Takes no argument, '
  'so it cannot be asked about anybody else. Added by migration 0062 for later '
  'enforcement; wired into nothing.';

-- Granted to `authenticated` for the same reason `has_community_role` is
-- (`0008` section 6): a predicate that later work will name inside an RLS
-- policy or an RPC guard must be executable by the role whose statement is
-- being evaluated, or the policy raises instead of deciding. `anon` has no use
-- for it -- it answers about a session, and `anon` has none.
revoke execute on function public.is_current_user_active() from anon, public;
grant execute on function public.is_current_user_active() to authenticated;



-- ============================================================================
-- 7) has_active_community_role() -- the mutating-action predicate
-- ============================================================================
-- The line later enforcement needs, and this file only draws:
--
--     has_community_role        -- may this user act at this rank
--     has_active_community_role -- ...and are both parties still in good standing
--
-- True only when all three hold:
--
--   1. the named user is active      (`users.is_active`)
--   2. the named community is active (`communities.is_active`)
--   3. the user holds at least the requested role
--
-- Point 3 is **delegated, not restated**. The `owner=3 >= admin=2 >= player=1`
-- ranking lives in `has_community_role` (`0008`) and continues to live only
-- there; this function calls it. A second copy of that CASE expression would be
-- a second role model, and the first time the two disagreed the disagreement
-- would be a permission bug. `has_community_role` is not modified, not replaced
-- and not shadowed -- its signature, body and grants are exactly as `0008` left
-- them.
--
-- **This is not a read predicate and must not become one.** Reading a community
-- one already belongs to is not "new activity", and every existing read policy
-- keeps asking `is_community_member` / `has_community_role`. This file changes
-- no read semantics; the predicate exists so later work can gate *mutating*
-- operations without disturbing them.
--
-- **Wired into nothing.** No policy and no function calls this today.
create or replace function public.has_active_community_role(
  p_community_id uuid,
  p_user_id uuid,
  p_min_role text
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    exists (
      select 1 from users u
      where u.id = p_user_id and u.is_active
    )
    and exists (
      select 1 from communities c
      where c.id = p_community_id and c.is_active
    )
    and public.has_community_role(p_community_id, p_user_id, p_min_role);
$$;

comment on function public.has_active_community_role(uuid, uuid, text) is
  'Whether an active user holds at least p_min_role in an active community. '
  'The role ranking is not restated here -- it delegates to has_community_role '
  '(0008), which is unmodified. Added by migration 0062 for later enforcement '
  'of mutating operations only; read semantics are unchanged and no policy '
  'calls this.';

-- Same grant as `has_community_role`, and for the same reason: later work will
-- name it inside checks evaluated as `authenticated`. It discloses nothing that
-- `has_community_role` does not already disclose to the same role for the same
-- arguments, plus two `is_active` bits.
revoke execute on function
  public.has_active_community_role(uuid, uuid, text) from anon, public;
grant execute on function
  public.has_active_community_role(uuid, uuid, text) to authenticated;



-- ============================================================================
-- 8) What this migration did not touch
-- ============================================================================
-- Stated so a later reader can confirm the contract from the file itself rather
-- than from a diff:
--
--   * no policy was created, dropped or altered -- not one, on any table or in
--     any schema, `storage` included;
--   * no existing function was replaced. `has_community_role`,
--     `is_community_member`, `is_match_community_member`,
--     `is_match_community_admin`, `is_system_admin`, the three `admin_list_*`
--     and the three `admin_delete_*` RPCs are all exactly as they were;
--   * the current `0061`-era surface is untouched: `communities.logo_url`,
--     `set_community_logo`, `community_logo_folder`, the four
--     `community_logos_*` storage policies, `community_statistics_recency`
--     (`0060`), `remove_played_professional_guest` (`0059`),
--     `replace_match_lineup` (`0059`), both `register_player_in_match`
--     overloads (`0054`, `0054a`), `add_/remove_/rename_professional_guest`
--     (`0047`), the public football views (`0057`), `my_profile` (`0055`),
--     `player_profile` (`0056`) and `preview_community_invite` (`0061`);
--   * no `is_active` value was written and no row was backfilled;
--   * no existing table's privileges were widened or narrowed, and `0061`'s
--     `grant select (logo_url)` stands exactly as it is;
--   * the two new predicates are called by nothing.
