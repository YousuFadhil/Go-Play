-- ===== migrations/0102_account_deletion_engine.sql =====
-- Permanent account deletion: ONE shared transactional engine, TWO authorized entry points.
--
--   admin_delete_account(user)          a System Admin deletes a selected user
--   delete_my_account()                 a signed-in user deletes their own account
--   delete_account_core(user)           the engine both call (internal; no client can reach it)
--   admin_preview_account_deletion      the existing preview, redefined for this behaviour
--   preview_my_account_deletion()       the same question for the signed-in user
--
-- Not applied by this commit. Forward-only: no applied migration is edited. 0101 is live; this is
-- the next unoccupied number. The `delete-account` Edge Function (supabase/functions) removes the
-- profile picture through the Storage API and then calls one of the two entry points; apply this
-- migration first, deploy the function second.
--
-- ## WHAT "DELETE" MEANS HERE (the approved behaviour)
--
-- IDENTITY. The account's `auth.users` row, its sign-in identities and its sessions are deleted
-- for good, in the same transaction as everything below. What is left of `public.users` is not a
-- profile: it is one row that carries the UUID, the name "لاعب محذوف / Deleted Player", no phone,
-- no date of birth, no picture, no location, `is_active = false` (so every guard that refuses a
-- suspended user refuses it) and `deleted_at`. It cannot sign in, appears in no list of users, and
-- has no suspension fields set: it is not a suspended account.
--
-- FOOTBALL HISTORY IS KEPT, UNDER THAT NAME. Completed matches and scores, participation, goals, MVP
-- awards, lineups and rating evidence stay exactly as they are and keep naming the same UUID, which
-- the public views already resolve with LEFT JOIN users to the placeholder name. Nothing is moved to
-- another player; the engine fingerprints the results, goal totals and every other player's
-- statistics and ratings before and after and rolls back if one moved.
--
-- ## THE ONE STRUCTURAL CHANGE, AND WHY IT IS THE SMALLEST THAT WORKS
--
-- Football evidence references `public.users` with `ON DELETE CASCADE` (registrations, lineups, goals,
-- the MVP award of a result, rating history, statistics) and `public.users.id` references `auth.users`
-- with `ON DELETE CASCADE`. Deleting the Auth row therefore erases the history. The alternatives are
-- to detach every one of those foreign keys (six constraints, plus PostgREST relationships the app
-- embeds, plus every view and function that INNER JOINs users) or to keep the profile row. This
-- migration keeps ONE anonymised row and drops the single constraint `users_id_fkey`, so that the row
-- may outlive its Auth user. Every other foreign key, view, function and mapper is untouched.
--
-- What dropping `users_id_fkey` takes away is the cascade from Auth to the profile. The two places that
-- relied on it are handled here: `admin_merge_accounts` (redefined, one added statement: it deletes the
-- source's profile itself), and a profile left behind by deleting an Auth user some other way (the
-- dashboard, the legacy `admin_delete_user`) -- an AFTER DELETE trigger on `auth.users` anonymises it.
--
-- ## WHAT ELSE A DELETION DOES
--
-- * BLOCKED while the account owns a community (`OWNS_COMMUNITIES`): the existing ownership transfer
--   comes first. Blocked for a System Admin (`TARGET_IS_SYSTEM_ADMIN`): their protection is unchanged.
-- * Registrations and lineup places in matches NOT yet played are withdrawn exactly as a cancellation
--   is (the lifecycle triggers record it, a reserve is promoted). Memberships are removed.
-- * Matches the account created stay, with the same `created_by`.
-- * Notifications, push tokens and preferences, and the last-seen marker are deleted.
-- * AUDIT: the e-mail snapshot of entries BY the account and the name snapshot of entries ABOUT it are
--   emptied, in the same statement 0101 uses; nothing else of an entry changes and none is deleted.
-- * STORAGE: the profile picture is removed through the Storage API BEFORE this runs (the Edge
--   Function). A picture still stored when the engine runs is refused (`SOURCE_FILES_REMAIN`), and
--   the last look refuses it again.
-- * MERGE HISTORY: `account_merge_map` is untouched. An account that absorbed others keeps being the
--   target of their old UUIDs; after its deletion they all read as the same deleted player.
--
-- ## WHAT THE ENGINE REFUSES TO TOUCH
--
-- No trigger is disabled, no setting changes the session, no RLS policy changes, the immutable rating
-- archives and the audit log are not deleted from, and no other player's row is written.
--
-- Run `tool/0102_..._verify.sql` after applying. Roll back with `rollback/0102_..._rollback.sql`, which
-- refuses once any account has been deleted.


-- ============================================================================
-- 1) The profile row may outlive its Auth user -- and says so
-- ============================================================================
-- `deleted_at` is what tells a deleted player from a live one. NULL for every account that exists.
alter table public.users
  add column if not exists deleted_at timestamptz;

comment on column public.users.deleted_at is
  'Set when the account was deleted (migration 0102): the row is then an anonymised stand-in for '
  'football history, with no Auth user, no profile data and is_active = false. NULL for every live '
  'account.';

-- The cascade from Auth to the profile is what would erase the history on a delete. Everything that
-- referenced this constraint by name is in this migration.
alter table public.users
  drop constraint if exists users_id_fkey;


-- ============================================================================
-- 2) The audit trail gains the one event an administrator's deletion writes
-- ============================================================================
-- The same statement pair 0095 and 0101 used. It changes which action names are accepted and nothing
-- else.
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED',
    'USER_PROFILE_UPDATED',
    'USER_ACCOUNTS_MERGED',
    'USER_ACCOUNT_DELETED'
  ));


-- ============================================================================
-- 3) Internal helpers (no client role can call any of them)
-- ============================================================================

-- The name every surface shows for a deleted player. Both languages in one string: the name is read
-- from `users.full_name` by every view and in 24 places in the app, and a locale cannot be chosen there.
create or replace function public.deleted_player_name()
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select 'لاعب محذوف / Deleted Player'::text;
$$;

-- What stops an account being deleted. Two things, both existing protections:
--   TARGET_IS_SYSTEM_ADMIN   System Admins are managed outside the app
--   OWNS_COMMUNITIES         ownership is transferred first, through the existing flow
-- The previews report it and the engine asks again inside its own transaction.
create or replace function public.account_deletion_blockers(p_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select array_remove(array[
    case when exists (select 1 from public.system_admins sa
                       where sa.user_id = p_user_id)
         then 'TARGET_IS_SYSTEM_ADMIN' end,
    case when exists (select 1 from public.communities c
                       where c.owner_id = p_user_id)
         then 'OWNS_COMMUNITIES' end
  ], null);
$$;

-- The football record of one account, in numbers and hashes. The engine takes it before and after and
-- rolls back if it moved: deletion must change who the record is shown as, never the record.
create or replace function public.account_football_evidence(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'registrations_completed', (
      select count(*) from public.match_registrations r
        join public.matches m on m.id = r.match_id
       where r.user_id = p_user_id and (m.status = 'completed' or m.end_at <= now())),
    'lineup_completed', (
      select count(*) from public.match_team_assignments t
        join public.matches m on m.id = t.match_id
       where t.user_id = p_user_id and (m.status = 'completed' or m.end_at <= now())),
    'goal_rows', (select count(*) from public.match_goals g where g.user_id = p_user_id),
    'goals_total', (select coalesce(sum(g.goals), 0) from public.match_goals g where g.user_id = p_user_id),
    'mvp_awards', (select count(*) from public.match_results r where r.mvp_user_id = p_user_id),
    'recorded_results', (select count(*) from public.match_results r where r.recorded_by = p_user_id),
    'created_matches', (select count(*) from public.matches m where m.created_by = p_user_id),
    'rating_history', (select md5(coalesce(string_agg(h.id::text, ',' order by h.entry_no), ''))
                         from public.rating_history h where h.user_id = p_user_id),
    'player_statistics', (select md5(coalesce(string_agg(t::text, ',' order by t.user_id), ''))
                            from public.player_statistics t where t.user_id = p_user_id),
    'community_statistics', (select md5(coalesce(string_agg(t::text, ',' order by t.community_id, t.period_type, t.period_key), ''))
                               from public.community_statistics t where t.user_id = p_user_id),
    'overall_rating', (select u.overall_rating from public.users u where u.id = p_user_id)
  );
$$;

-- Turns a profile into the anonymised stand-in. Idempotent, and only ever applied to a live profile
-- (`deleted_at is null`). Returns whether it changed one.
--
-- No identifying column survives. The primary position is not one (it is football data, and the rosters
-- of old matches show it), the rating stays as football evidence, and `profile_visibility` is set to
-- the narrower value so that nothing opens the row to non-members.
create or replace function public.anonymize_user_profile(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n bigint;
begin
  update public.users u
     set full_name = public.deleted_player_name(),
         phone = '',
         date_of_birth = null,
         secondary_position = null,
         avatar_path = null,
         default_wilayat_code = null,
         profile_visibility = 'COMMUNITY_MEMBERS',
         age_visible = false,
         suspended_at = null,
         suspended_by = null,
         suspension_reason = null,
         is_active = false,
         deleted_at = now()
   where u.id = p_user_id
     and u.deleted_at is null;
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

-- A profile whose Auth user is deleted by any route other than the engine -- the dashboard, the legacy
-- `admin_delete_user`, a future tool -- would otherwise be left whole, with its name and phone, because
-- the cascade that used to remove it is gone. It is anonymised instead. The engine and the merge both
-- finish with the profile already gone or already anonymised, so for them this does nothing.
create or replace function public.handle_auth_user_deleted()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.anonymize_user_profile(old.id);
  return old;
end;
$$;

drop trigger if exists auth_user_deleted_anonymize_profile on auth.users;
create trigger auth_user_deleted_anonymize_profile
  after delete on auth.users
  for each row
  execute function public.handle_auth_user_deleted();

revoke execute on function public.deleted_player_name()
  from anon, authenticated, public;
revoke execute on function public.account_deletion_blockers(uuid)
  from anon, authenticated, public;
revoke execute on function public.account_football_evidence(uuid)
  from anon, authenticated, public;
revoke execute on function public.anonymize_user_profile(uuid)
  from anon, authenticated, public;
revoke execute on function public.handle_auth_user_deleted()
  from anon, authenticated, public;

comment on function public.deleted_player_name() is
  'Account deletion (0102): the name shown for a deleted player, in both languages.';
comment on function public.account_deletion_blockers(uuid) is
  'Account deletion (0102), INTERNAL: TARGET_IS_SYSTEM_ADMIN and OWNS_COMMUNITIES, the two things that '
  'stop an account being deleted. Shared by the previews and the engine.';
comment on function public.account_football_evidence(uuid) is
  'Account deletion (0102), INTERNAL: the football record of one account as counts and hashes, '
  'compared before and after a deletion.';
comment on function public.anonymize_user_profile(uuid) is
  'Account deletion (0102), INTERNAL: turns a live profile into the anonymised stand-in. Idempotent.';
comment on function public.handle_auth_user_deleted() is
  'Account deletion (0102), INTERNAL: anonymises the profile of an Auth user deleted by any other route.';


-- ============================================================================
-- 4) delete_account_core() -- the engine
-- ============================================================================
-- INTERNAL: callable by no client role. The two entry points below decide WHO may ask; this decides
-- WHETHER the account may go and does it, in ONE transaction. Every statement either happens or none
-- does, and the last write is the deletion of the Auth user.
--
-- ## ORDER OF WORK
--
--   1.  one advisory lock shared with the merge, then the profile row `for update`
--   2.  the blockers, again, and the picture: neither may be there
--   3.  fingerprints: this account's football record, and everything of everybody else's that must not move
--   4.  registrations and lineup places in matches not yet played are withdrawn, as a cancellation is
--   5.  memberships are removed
--   6.  notifications, push tokens and preferences, the last-seen marker are deleted
--   7.  the audit snapshots that identify the account are emptied
--   8.  the profile becomes the anonymised stand-in
--   9.  fingerprints again; a last look that nothing identifying remains
--   10. the Auth user is deleted (identities and sessions go with it), and its tokens by name
create or replace function public.delete_account_core(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_blockers text[];
  v_evidence_before jsonb;
  v_evidence_after jsonb;
  v_others_before jsonb;
  v_others_after jsonb;
  v_match uuid;
  v_restore uuid[] := '{}';
  v_i int;
  v_n bigint;
  c_upcoming_registrations bigint := 0;
  c_upcoming_lineup_places bigint := 0;
  c_memberships bigint := 0;
  c_notifications bigint := 0;
  c_push_tokens bigint := 0;
  c_audit_redacted bigint := 0;
begin
  -- ---- 1. serialise with every merge and deletion, then lock the profile ---------------------
  perform pg_advisory_xact_lock(hashtextextended('goplay.account_lifecycle', 0));

  perform 1
    from public.users u
   where u.id = p_user_id
     and u.deleted_at is null
     for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- ---- 2. nothing may stand in the way ---------------------------------------------------------
  v_blockers := public.account_deletion_blockers(p_user_id);
  if cardinality(v_blockers) > 0 then
    raise exception 'DELETE_BLOCKED' using detail = array_to_string(v_blockers, ',');
  end if;
  -- The picture is removed through the Storage API BEFORE this runs (the `delete-account` Edge
  -- Function). Still there means not called through it: refuse rather than leave a public file
  -- behind a deleted account.
  if cardinality(public.merge_source_stored_files(p_user_id)) > 0 then
    raise exception 'SOURCE_FILES_REMAIN';
  end if;

  -- ---- 3. what must not change -----------------------------------------------------------------
  v_evidence_before := public.account_football_evidence(p_user_id);
  v_others_before := public.merge_invariants(p_user_id, p_user_id);

  -- ---- 4. matches not yet played: the player withdraws -----------------------------------------
  -- Completed means status 'completed' or the end has passed, the application's rule everywhere.
  for v_match in
    select x.match_id from (
      select r.match_id from public.match_registrations r
        join public.matches m on m.id = r.match_id
       where r.user_id = p_user_id and m.status <> 'completed' and m.end_at > now()
      union
      select t.match_id from public.match_team_assignments t
        join public.matches m on m.id = t.match_id
       where t.user_id = p_user_id and m.status <> 'completed' and m.end_at > now()
    ) x
  loop
    v_restore := v_restore || v_match;
  end loop;

  delete from public.match_team_assignments t
   using public.matches m
   where m.id = t.match_id and t.user_id = p_user_id
     and m.status <> 'completed' and m.end_at > now();
  get diagnostics c_upcoming_lineup_places = row_count;

  delete from public.match_registrations r
   using public.matches m
   where m.id = r.match_id and r.user_id = p_user_id
     and m.status <> 'completed' and m.end_at > now();
  get diagnostics c_upcoming_registrations = row_count;

  -- The places they leave are filled exactly as a withdrawal fills them.
  for v_i in 1 .. coalesce(cardinality(v_restore), 0) loop
    perform public.rebalance_roster(v_restore[v_i]);
    perform public.recompute_match_status(v_restore[v_i]);
  end loop;

  -- ---- 5. memberships ----------------------------------------------------------------------------
  delete from public.community_members where user_id = p_user_id;
  get diagnostics c_memberships = row_count;

  -- ---- 6. personal operational data --------------------------------------------------------------
  delete from public.notification_push_tokens where user_id = p_user_id;
  get diagnostics c_push_tokens = row_count;
  delete from public.notification_push_preferences where user_id = p_user_id;
  delete from public.notifications where user_id = p_user_id;
  get diagnostics c_notifications = row_count;
  delete from public.product_activity_last_seen where user_id = p_user_id;

  -- ---- 7. audit snapshots ------------------------------------------------------------------------
  -- The same statement migration 0101 uses for a merged-away account. The entries stay, with their id,
  -- actor and target UUIDs, action, reason, metadata and date; only the actor's e-mail (entries BY the
  -- account) and the target's name (entries ABOUT it) are emptied.
  update public.admin_audit_log a
     set actor_email_snapshot = case when a.actor_user_id = p_user_id
                                     then null else a.actor_email_snapshot end,
         target_label_snapshot = case when a.target_type = 'USER'
                                           and a.target_id = p_user_id
                                      then null else a.target_label_snapshot end
   where a.actor_user_id = p_user_id
      or (a.target_type = 'USER' and a.target_id = p_user_id);
  get diagnostics c_audit_redacted = row_count;

  -- ---- 8. the profile ----------------------------------------------------------------------------
  perform public.anonymize_user_profile(p_user_id);

  -- ---- 9. nothing moved, and nothing identifying is left ---------------------------------------
  v_evidence_after := public.account_football_evidence(p_user_id);
  if v_evidence_after is distinct from v_evidence_before then
    raise exception 'DELETE_EVIDENCE_CHANGED'
      using detail = (select string_agg(k, ',' order by k)
                        from jsonb_object_keys(v_evidence_before) k
                       where v_evidence_before->k is distinct from v_evidence_after->k);
  end if;
  v_others_after := public.merge_invariants(p_user_id, p_user_id);
  if v_others_after is distinct from v_others_before then
    raise exception 'DELETE_INVARIANT_BROKEN'
      using detail = (select string_agg(k, ',' order by k)
                        from jsonb_object_keys(v_others_before) k
                       where v_others_before->k is distinct from v_others_after->k);
  end if;

  if exists (select 1 from public.community_members where user_id = p_user_id)
     or exists (select 1 from public.match_registrations r
                  join public.matches m on m.id = r.match_id
                 where r.user_id = p_user_id and m.status <> 'completed' and m.end_at > now())
     or exists (select 1 from public.match_team_assignments t
                  join public.matches m on m.id = t.match_id
                 where t.user_id = p_user_id and m.status <> 'completed' and m.end_at > now())
     or exists (select 1 from public.notifications where user_id = p_user_id)
     or exists (select 1 from public.notification_push_tokens where user_id = p_user_id)
     or exists (select 1 from public.notification_push_preferences where user_id = p_user_id)
     or exists (select 1 from public.product_activity_last_seen where user_id = p_user_id)
     or exists (select 1 from public.admin_audit_log a
                 where (a.actor_user_id = p_user_id and a.actor_email_snapshot is not null)
                    or (a.target_type = 'USER' and a.target_id = p_user_id
                        and a.target_label_snapshot is not null))
     or exists (select 1 from public.users u
                 where u.id = p_user_id
                   and (u.deleted_at is null
                        or u.full_name <> public.deleted_player_name()
                        or u.phone <> ''
                        or u.date_of_birth is not null
                        or u.secondary_position is not null
                        or u.avatar_path is not null
                        or u.default_wilayat_code is not null
                        or u.is_active
                        or u.suspended_at is not null
                        or u.suspended_by is not null
                        or u.suspension_reason is not null))
     or cardinality(public.merge_source_stored_files(p_user_id)) > 0 then
    raise exception 'DELETE_RESIDUAL_DATA';
  end if;

  -- ---- 10. the Auth user ---------------------------------------------------------------------------
  -- Cascades to the identities, sessions and one-time tokens. Two Auth tables name the user WITHOUT a
  -- foreign key (checked on the live project for 0101): `refresh_tokens` (text) and `flow_state`.
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.flow_state where user_id = p_user_id;

  delete from auth.users where id = p_user_id;
  get diagnostics v_n = row_count;
  if v_n <> 1
     or exists (select 1 from auth.identities where user_id = p_user_id)
     or exists (select 1 from auth.sessions where user_id = p_user_id)
     or exists (select 1 from auth.refresh_tokens where user_id = p_user_id::text)
     or exists (select 1 from auth.flow_state where user_id = p_user_id) then
    raise exception 'AUTH_DELETE_INCOMPLETE';
  end if;

  return jsonb_build_object(
    'deleted', true,
    'user_id', p_user_id,
    'withdrawn', jsonb_build_object(
      'registrations', c_upcoming_registrations,
      'lineup_places', c_upcoming_lineup_places),
    'memberships_removed', c_memberships,
    'notifications_deleted', c_notifications,
    'push_tokens_deleted', c_push_tokens,
    'audit_entries_redacted', c_audit_redacted,
    'kept', jsonb_build_object(
      'registrations_completed', v_evidence_before->'registrations_completed',
      'lineup_completed', v_evidence_before->'lineup_completed',
      'goal_rows', v_evidence_before->'goal_rows',
      'mvp_awards', v_evidence_before->'mvp_awards',
      'created_matches', v_evidence_before->'created_matches'));
end;
$$;

revoke execute on function public.delete_account_core(uuid)
  from anon, authenticated, public;

comment on function public.delete_account_core(uuid) is
  'Account deletion (0102), INTERNAL: removes personal data and the Auth user, keeps the football '
  'record under the anonymised stand-in, in one transaction. Callable by no client role; the two '
  'entry points decide who may ask.';


-- ============================================================================
-- 5) The previews: what a deletion would do, for an administrator and for the account itself
-- ============================================================================
-- `admin_preview_account_deletion` keeps its name, signature, gate and document shape; its content
-- changes because the behaviour does. Football history is no longer erased, so nothing about it
-- blocks. The blockers are the two the engine asks again (`account_deletion_blockers`), plus the
-- administrator's own account. Everything else is told: what is kept, what is removed, what is
-- redacted. STABLE and read-only; it writes no audit event.
create or replace function public.admin_preview_account_deletion(p_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_limit constant int := 25;
  v_snapshot jsonb;
  v_counts jsonb;
  v_flags record;
  v_owned_total bigint;
  v_owned_items jsonb;
  v_created_total bigint;
  v_created_by_status jsonb;
  v_created_items jsonb;
  v_personal jsonb;
  v_historical jsonb;
  v_preserved jsonb;
  v_findings jsonb;
  v_history_evidence bigint;
  v_identities bigint;
  v_upcoming_registrations bigint;
  v_upcoming_lineup bigint;
  v_completed_registrations bigint;
  v_completed_lineup bigint;
  v_files bigint;
begin
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- A deleted account is no longer an account.
  if exists (select 1 from public.users u
              where u.id = p_user_id and u.deleted_at is not null) then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_snapshot := public.admin_preview_account_snapshot(p_user_id);
  v_counts := v_snapshot->'counts';

  select (u.avatar_path is not null) as has_avatar,
         (u.date_of_birth is not null) as has_dob,
         (u.default_wilayat_code is not null) as has_location,
         (btrim(u.phone) <> '') as has_phone
    into v_flags
    from public.users u
   where u.id = p_user_id;

  select count(*) into v_identities
    from auth.identities i
   where i.user_id = p_user_id;

  v_files := cardinality(public.merge_source_stored_files(p_user_id));

  -- ---- communities the account owns: ownership must be transferred first ---------------------
  select count(*) into v_owned_total
    from public.communities c
   where c.owner_id = p_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_owned_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'is_active', c.is_active,
                   'member_count',
                     (select count(*) from public.community_members cm
                       where cm.community_id = c.id),
                   'other_admin_count',
                     (select count(*) from public.community_members cm
                       where cm.community_id = c.id and cm.role = 'admin'
                         and cm.user_id <> p_user_id),
                   'match_count',
                     (select count(*) from public.matches m
                       where m.community_id = c.id)) as item,
                 row_number() over (order by c.name, c.id) as rn
            from public.communities c
           where c.owner_id = p_user_id) s
   where s.rn <= v_limit;

  -- ---- matches the account created: they stay --------------------------------------------------
  select count(*) into v_created_total
    from public.matches m
   where m.created_by = p_user_id;

  select coalesce(jsonb_object_agg(g.status, g.n), '{}'::jsonb)
    into v_created_by_status
    from (select m.status, count(*) as n
            from public.matches m
           where m.created_by = p_user_id
           group by m.status) g;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_created_items
    from (select jsonb_build_object(
                   'match_id', m.id,
                   'title', m.title,
                   'community_name', c.name,
                   'status', m.status,
                   'start_at', m.start_at,
                   'is_historical', m.is_historical,
                   'has_result',
                     exists (select 1 from public.match_results mr
                              where mr.match_id = m.id)) as item,
                 row_number() over (order by m.start_at desc, m.id) as rn
            from public.matches m
            join public.communities c on c.id = m.community_id
           where m.created_by = p_user_id) s
   where s.rn <= v_limit;

  -- ---- the split of participation between matches played and matches to come -------------------
  select count(*) into v_upcoming_registrations
    from public.match_registrations r
    join public.matches m on m.id = r.match_id
   where r.user_id = p_user_id and m.status <> 'completed' and m.end_at > now();
  select count(*) into v_completed_registrations
    from public.match_registrations r
    join public.matches m on m.id = r.match_id
   where r.user_id = p_user_id and (m.status = 'completed' or m.end_at <= now());
  select count(*) into v_upcoming_lineup
    from public.match_team_assignments t
    join public.matches m on m.id = t.match_id
   where t.user_id = p_user_id and m.status <> 'completed' and m.end_at > now();
  select count(*) into v_completed_lineup
    from public.match_team_assignments t
    join public.matches m on m.id = t.match_id
   where t.user_id = p_user_id and (m.status = 'completed' or m.end_at <= now());

  -- ---- personal data this account holds: all of it is removed ----------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n) order by f.code),
           '[]'::jsonb)
    into v_personal
    from (values
      ('PROFILE', 1::bigint),
      ('EMAIL_ADDRESS',
         case when nullif(v_snapshot->'account'->>'email', '') is not null then 1 else 0 end),
      ('SIGN_IN_IDENTITIES', v_identities),
      ('PHONE_NUMBER', case when v_flags.has_phone then 1 else 0 end),
      ('DATE_OF_BIRTH', case when v_flags.has_dob then 1 else 0 end),
      ('AVATAR', case when v_flags.has_avatar or v_files > 0 then 1 else 0 end),
      ('DEFAULT_LOCATION', case when v_flags.has_location then 1 else 0 end),
      ('PUSH_TOKENS', (v_counts->>'push_tokens')::bigint),
      ('PUSH_PREFERENCES', (v_counts->>'push_preferences')::bigint),
      ('NOTIFICATIONS', (v_counts->>'notifications')::bigint),
      ('ACTIVITY_EVENTS', (v_counts->>'product_events')::bigint)
    ) as f(code, n)
   where f.n > 0;

  -- ---- football history, and what a deletion does to each part ---------------------------------
  --   KEPT         stays as it is and is shown as the deleted player
  --   REMOVED      is removed (memberships, and participation in matches not yet played)
  --   RETAINED_ID  a bare uuid with no foreign key: the row stays and names no one
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n, 'treatment', f.treatment)
           order by f.rank, f.code), '[]'::jsonb)
    into v_historical
    from (values
      ('COMMUNITY_MEMBERSHIPS',    (v_counts->>'memberships')::bigint,               'REMOVED',     1),
      ('UPCOMING_REGISTRATIONS',   v_upcoming_registrations,                         'REMOVED',     1),
      ('UPCOMING_LINEUP_PLACES',   v_upcoming_lineup,                                'REMOVED',     1),
      ('MATCH_REGISTRATIONS',      v_completed_registrations,                        'KEPT',        2),
      ('LINEUP_ASSIGNMENTS',       v_completed_lineup,                               'KEPT',        2),
      ('GOAL_RECORDS',             (v_counts->>'goal_rows')::bigint,                 'KEPT',        2),
      ('MVP_RESULTS',              (v_counts->>'mvp_awards')::bigint,                'KEPT',        2),
      ('PLAYER_STATISTICS',        (v_counts->>'player_statistics_rows')::bigint,    'KEPT',        2),
      ('COMMUNITY_STATISTICS',     (v_counts->>'community_statistics_rows')::bigint, 'KEPT',        2),
      ('RATING_HISTORY',           (v_counts->>'rating_entries')::bigint,            'KEPT',        2),
      ('RECORDED_RESULTS',         (v_counts->>'recorded_results')::bigint,          'KEPT',        2),
      ('PROFESSIONAL_GUESTS_ADDED',(v_counts->>'professional_guests_created')::bigint,'KEPT',       2),
      ('TEAM_OF_PERIOD_AWARDS',    (v_counts->>'team_of_period_awards')::bigint,     'RETAINED_ID', 3),
      ('REGISTRATION_EVENTS',      (v_counts->>'registration_events')::bigint,       'RETAINED_ID', 3),
      ('MEMBERSHIP_EVENTS',        (v_counts->>'membership_events')::bigint,         'RETAINED_ID', 3),
      ('GENERATION_RUNS',          (v_counts->>'generation_runs')::bigint,           'RETAINED_ID', 3),
      ('CONFIRMED_LINEUPS',        (v_counts->>'confirmed_lineups')::bigint,         'RETAINED_ID', 3),
      ('ACTIVITY_EVENTS',          (v_counts->>'product_events')::bigint,            'RETAINED_ID', 3)
    ) as f(code, n, treatment, rank)
   where f.n > 0;

  -- ---- records nobody can change ------------------------------------------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'records', f.n) order by f.code),
           '[]'::jsonb)
    into v_preserved
    from (values
      ('RATING_HISTORY_ARCHIVE', (v_counts->>'rating_archive_rows')::bigint),
      ('USER_RATING_ARCHIVE',    (v_counts->>'user_rating_archive_rows')::bigint)
    ) as f(code, n)
   where f.n > 0;

  -- Historical match evidence: a confirmed registration, a lineup place, a goal or a rating entry of a
  -- COMPLETED match. Told, not blocking: the engine keeps all of it.
  v_history_evidence :=
      (select count(*) from public.match_registrations r
         join public.matches m on m.id = r.match_id
        where r.user_id = p_user_id
          and r.status = 'confirmed'
          and (m.status = 'completed' or m.end_at <= now()))
    + v_completed_lineup
    + (select count(*) from public.match_goals g
         join public.matches m on m.id = g.match_id
        where g.user_id = p_user_id
          and (m.status = 'completed' or m.end_at <= now()))
    + (select count(*) from public.rating_history h
         join public.matches m on m.id = h.match_id
        where h.user_id = p_user_id
          and (m.status = 'completed' or m.end_at <= now()));

  -- ---- findings ------------------------------------------------------------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'severity', f.severity,
                              'category', f.category, 'count', f.n)
           order by f.rank, f.code), '[]'::jsonb)
    into v_findings
    from (values
      ('TARGET_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_snapshot->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('TARGET_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_snapshot->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('OWNS_COMMUNITIES', 'BLOCKER', 'OWNERSHIP', v_owned_total, 1),
      ('UPCOMING_REGISTRATIONS', 'CONFLICT', 'MATCH', v_upcoming_registrations, 2),
      ('HISTORY_KEPT', 'CONSTRAINT', 'HISTORY', v_history_evidence, 3),
      ('CREATED_MATCHES_KEPT', 'CONSTRAINT', 'MATCH', v_created_total, 3),
      ('RATING_ARCHIVE_KEPT', 'CONSTRAINT', 'ARCHIVE',
         (v_counts->>'rating_archive_rows')::bigint
           + (v_counts->>'user_rating_archive_rows')::bigint, 3),
      ('AUDIT_LOG_REDACTED', 'CONSTRAINT', 'AUDIT', (v_counts->>'audit_entries')::bigint, 3),
      ('STORED_FILES_REMOVED', 'CONSTRAINT', 'STORAGE', v_files, 3),
      ('EVENT_LOGS_NAME_ACCOUNT', 'CONSTRAINT', 'HISTORY',
         (v_counts->>'registration_events')::bigint
           + (v_counts->>'membership_events')::bigint, 3)
    ) as f(code, severity, category, n, rank)
   where f.n > 0;

  return jsonb_build_object(
    'version', 2,
    'limit', v_limit,
    'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e
                             where e->>'severity' = 'BLOCKER'),
    'account', v_snapshot,
    'personal_data', v_personal,
    'owned_communities', jsonb_build_object(
      'total', v_owned_total,
      'items', v_owned_items),
    'created_matches', jsonb_build_object(
      'total', v_created_total,
      'by_status', v_created_by_status,
      'items', v_created_items),
    'historical_records', v_historical,
    'preserved_records', v_preserved,
    'findings', v_findings,
    'coverage_notes', jsonb_build_array(
      'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED',
      'AUTH_SESSIONS_NOT_INSPECTED')
  );
end;
$$;

comment on function public.admin_preview_account_deletion(uuid) is
  'Platform Admin: what deleting one account would do. Football history is kept under the deleted '
  'player; the blockers are owning a community and being a System Admin or the caller. STABLE, '
  'writes nothing, no audit event. System Admin only (NOT_AUTHORIZED). Migrations 0096, 0099, 0102.';

revoke execute on function public.admin_preview_account_deletion(uuid)
  from anon, public;
grant execute on function public.admin_preview_account_deletion(uuid)
  to authenticated;
grant execute on function public.admin_preview_account_deletion(uuid)
  to service_role;


-- The same question, asked by the signed-in user about their own account. Only what the person needs
-- to decide: whether anything blocks, and which communities they must hand over first.
create or replace function public.preview_my_account_deletion()
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_limit constant int := 25;
  v_uid uuid := auth.uid();
  v_owned_total bigint;
  v_owned_items jsonb;
  v_is_admin boolean;
  v_active boolean;
  v_upcoming bigint;
  v_findings jsonb;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not exists (select 1 from public.users u
                  where u.id = v_uid and u.deleted_at is null) then
    raise exception 'USER_NOT_FOUND';
  end if;

  select count(*) into v_owned_total
    from public.communities c
   where c.owner_id = v_uid;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_owned_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'member_count',
                     (select count(*) from public.community_members cm
                       where cm.community_id = c.id)) as item,
                 row_number() over (order by c.name, c.id) as rn
            from public.communities c
           where c.owner_id = v_uid) s
   where s.rn <= v_limit;

  v_is_admin := exists (select 1 from public.system_admins sa where sa.user_id = v_uid);
  select u.is_active into v_active from public.users u where u.id = v_uid;

  select count(*) into v_upcoming
    from public.match_registrations r
    join public.matches m on m.id = r.match_id
   where r.user_id = v_uid and m.status <> 'completed' and m.end_at > now();

  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'severity', f.severity, 'count', f.n)
           order by f.rank, f.code), '[]'::jsonb)
    into v_findings
    from (values
      ('TARGET_IS_SYSTEM_ADMIN', 'BLOCKER', case when v_is_admin then 1 else 0 end, 1),
      -- a suspended account cannot delete itself (delete_my_account refuses it); said here so that
      -- the Edge Function stops BEFORE it removes the picture
      ('ACCOUNT_SUSPENDED', 'BLOCKER', case when v_active then 0 else 1 end, 1),
      ('OWNS_COMMUNITIES', 'BLOCKER', v_owned_total, 1),
      ('UPCOMING_REGISTRATIONS', 'CONFLICT', v_upcoming, 2)
    ) as f(code, severity, n, rank)
   where f.n > 0;

  return jsonb_build_object(
    'version', 1,
    'limit', v_limit,
    -- the database's own answer to "who am I", for the Edge Function that removes the picture
    'user_id', v_uid,
    'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e
                             where e->>'severity' = 'BLOCKER'),
    'findings', v_findings,
    'owned_communities', jsonb_build_object(
      'total', v_owned_total,
      'items', v_owned_items),
    'upcoming_registrations', v_upcoming);
end;
$$;

comment on function public.preview_my_account_deletion() is
  'Account deletion (0102): whether anything blocks the signed-in user deleting their own account, '
  'and which communities they own. STABLE, writes nothing.';

revoke execute on function public.preview_my_account_deletion()
  from anon, public;
grant execute on function public.preview_my_account_deletion()
  to authenticated;
grant execute on function public.preview_my_account_deletion()
  to service_role;


-- ============================================================================
-- 6) The two entry points
-- ============================================================================
-- Authorization is decided HERE, on the server, and never by the app: who is asking, and about whom.
-- The engine (`delete_account_core`) is the same for both.

-- A System Admin deletes a selected user. Refused for the administrator's own account (the self route
-- exists for that, and refuses System Admins) and for every System Admin (the engine's blocker).
create or replace function public.admin_delete_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_result jsonb;
  v_audit uuid;
begin
  if v_caller is null
     or not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = v_caller) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id is null then
    raise exception 'USER_NOT_FOUND';
  end if;
  if p_user_id = v_caller then
    raise exception 'CANNOT_DELETE_SELF';
  end if;

  v_result := public.delete_account_core(p_user_id);

  -- One event, naming the administrator and the deleted UUID and nothing about the person: no label,
  -- and the counts say what was done.
  v_audit := public.record_admin_audit(
    'USER_ACCOUNT_DELETED', 'USER', p_user_id, null, null,
    jsonb_build_object(
      'withdrawn', v_result->'withdrawn',
      'memberships_removed', v_result->'memberships_removed',
      'audit_entries_redacted', v_result->'audit_entries_redacted',
      'kept', v_result->'kept'));

  return v_result || jsonb_build_object('mode', 'admin', 'audit_id', v_audit);
end;
$$;

comment on function public.admin_delete_account(uuid) is
  'Platform Admin: permanently deletes one account (Auth user, profile data, personal records) and '
  'keeps its football history under the deleted player, in one transaction. Refuses the caller '
  '(CANNOT_DELETE_SELF), a System Admin and an owner of a community (DELETE_BLOCKED). Writes one '
  'USER_ACCOUNT_DELETED audit event. System Admin only (NOT_AUTHORIZED). Migration 0102.';

revoke execute on function public.admin_delete_account(uuid)
  from anon, public;
grant execute on function public.admin_delete_account(uuid)
  to authenticated;
grant execute on function public.admin_delete_account(uuid)
  to service_role;


-- A signed-in user deletes their own account. There is no parameter: the account is auth.uid(), so
-- nobody can name another. A suspended account cannot use this to leave a suspension behind.
create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not exists (select 1 from public.users u
                  where u.id = v_caller and u.deleted_at is null) then
    raise exception 'USER_NOT_FOUND';
  end if;
  if not exists (select 1 from public.users u
                  where u.id = v_caller and u.is_active) then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  return public.delete_account_core(v_caller) || jsonb_build_object('mode', 'self');
end;
$$;

comment on function public.delete_my_account() is
  'Account deletion (0102): the signed-in user permanently deletes their own account. No argument: '
  'the account is auth.uid(). Refuses a System Admin and an owner of a community (DELETE_BLOCKED) and '
  'a suspended account (ACCOUNT_SUSPENDED). Migration 0102.';

revoke execute on function public.delete_my_account()
  from anon, public;
grant execute on function public.delete_my_account()
  to authenticated;
grant execute on function public.delete_my_account()
  to service_role;


-- ============================================================================
-- 7) admin_merge_accounts(): 0101's merge, with the three changes this migration needs
-- ============================================================================
-- `users_id_fkey` is gone, so the merge deletes the source's profile itself, before the Auth user
-- (which still cascades to the identities and sessions). It also refuses a deleted profile, and takes
-- the advisory lock the deletion engine takes. Everything else is 0101, byte for byte.
create or replace function public.admin_merge_accounts(
  p_retained_user_id uuid,
  p_source_user_id uuid,
  p_resolutions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_doc jsonb;
  v_blockers text[];
  v_res_ids uuid[] := '{}';
  v_res_keep text[] := '{}';
  v_entry jsonb;
  v_mid uuid;
  v_dropped uuid;
  v_norm jsonb := '[]'::jsonb;
  v_shared_ids uuid[];
  v_missing uuid[];
  v_unknown uuid[];
  v_codes text[];
  v_ref record;
  v_c record;
  v_m record;
  v_before jsonb;
  v_after jsonb;
  v_n bigint;
  v_i int;
  v_name text;
  v_rating_before numeric;
  v_rating_after numeric;
  v_rating_reset numeric;
  v_replayed int := 0;
  v_drop_rank int;
  v_keep_rank int;
  v_reversed int := 0;
  v_audit uuid;
  v_restore_ids uuid[] := '{}';
  -- what the merge reports, and writes into the one audit event
  c_dropped_registrations bigint := 0;
  c_dropped_lineup_places bigint := 0;
  c_moved_registrations bigint := 0;
  c_moved_lineup_places bigint := 0;
  c_moved_goal_rows bigint := 0;
  c_moved_mvp_awards bigint := 0;
  c_communities_transferred bigint := 0;
  c_memberships_moved bigint := 0;
  c_memberships_merged bigint := 0;
  c_roles_upgraded bigint := 0;
  c_matches_reattributed bigint := 0;
  c_team_awards_moved bigint := 0;
  c_push_tokens_invalidated bigint := 0;
  c_audit_redacted bigint := 0;
begin
  -- ---- 1. who may ask -------------------------------------------------------
  if v_caller is null
     or not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = v_caller) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- ---- 2. arguments ---------------------------------------------------------
  if p_retained_user_id is null or p_source_user_id is null then
    raise exception 'USER_NOT_FOUND';
  end if;
  if p_retained_user_id = p_source_user_id then
    raise exception 'SAME_ACCOUNT';
  end if;
  if p_retained_user_id = v_caller or p_source_user_id = v_caller then
    raise exception 'CANNOT_MERGE_SELF';
  end if;

  if p_resolutions is null or jsonb_typeof(p_resolutions) <> 'array'
     or jsonb_array_length(p_resolutions) > 100 then
    raise exception 'RESOLUTIONS_INVALID';
  end if;
  for v_entry in select e from jsonb_array_elements(p_resolutions) e loop
    if jsonb_typeof(v_entry) <> 'object'
       or (v_entry->>'keep') is null
       or (v_entry->>'keep') not in ('retained', 'source') then
      raise exception 'RESOLUTIONS_INVALID';
    end if;
    begin
      v_mid := (v_entry->>'match_id')::uuid;
    exception when others then
      raise exception 'RESOLUTIONS_INVALID';
    end;
    if v_mid is null or v_mid = any (v_res_ids) then
      raise exception 'RESOLUTIONS_INVALID';
    end if;
    v_res_ids := v_res_ids || v_mid;
    v_res_keep := v_res_keep || (v_entry->>'keep');
    v_norm := v_norm || jsonb_build_array(
      jsonb_build_object('match_id', v_mid, 'keep', v_entry->>'keep'));
  end loop;

  -- One merge or deletion at a time, anywhere (0102: the account deletion engine takes the same
  -- lock): rare administrative acts, and the cheapest way to rule out two that share a
  -- community or a match deadlocking.
  perform pg_advisory_xact_lock(hashtextextended('goplay.account_lifecycle', 0));

  -- ---- 3. lock, in a fixed order -------------------------------------------
  perform 1
    from public.users u
   where u.id in (p_retained_user_id, p_source_user_id)
   order by u.id
     for update;
  -- Both must still exist AFTER the lock: a second request for the same source,
  -- queued behind the first, finds the source gone and stops here.
  if (select count(*) from public.users u
       where u.id in (p_retained_user_id, p_source_user_id)
         and u.deleted_at is null) <> 2 then
    raise exception 'USER_NOT_FOUND';
  end if;

  perform 1
    from public.communities c
   where c.owner_id = p_source_user_id
      or c.id in (select cm.community_id from public.community_members cm
                   where cm.user_id in (p_retained_user_id, p_source_user_id))
   order by c.id
     for update;

  perform 1
    from public.matches m
   where m.created_by = p_source_user_id
      or m.id in (
           select r.match_id from public.match_registrations r
            where r.user_id in (p_retained_user_id, p_source_user_id)
           union
           select t.match_id from public.match_team_assignments t
            where t.user_id in (p_retained_user_id, p_source_user_id)
           union
           select g.match_id from public.match_goals g
            where g.user_id in (p_retained_user_id, p_source_user_id)
           union
           select mr.match_id from public.match_results mr
            where mr.mvp_user_id in (p_retained_user_id, p_source_user_id)
           union
           select h.match_id from public.rating_history h
            where h.user_id in (p_retained_user_id, p_source_user_id))
   order by m.id
     for update;

  -- ---- 4. the switches, bound to this transaction and to these two accounts ---
  perform set_config('goplay.account_merge', 'tx:' || txid_current()::text, true);
  perform set_config('goplay.account_merge_users',
                     p_retained_user_id::text || ',' || p_source_user_id::text, true);

  -- ---- 5. a reference this function does not know about ---------------------
  -- Deleting the source cascades through every foreign key to `users`. If a later
  -- migration adds one this function has never heard of, a merge must refuse
  -- rather than let that cascade take rows nobody decided about.
  for v_ref in
    select cl.relname::text as tbl, a.attname::text as col
      from pg_constraint k
      join pg_class cl on cl.oid = k.conrelid
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
     where k.contype = 'f'
       and k.confrelid = 'public.users'::regclass
       and cl.relnamespace = 'public'::regnamespace
  loop
    if (v_ref.tbl || '.' || v_ref.col) not in (
         'communities.owner_id', 'community_members.user_id',
         'community_statistics.user_id', 'match_goals.user_id',
         'match_professional_guests.created_by', 'match_registrations.user_id',
         'match_results.mvp_user_id', 'match_results.recorded_by',
         'match_team_assignments.user_id', 'matches.created_by',
         'notification_push_preferences.user_id', 'notification_push_tokens.user_id',
         'notifications.user_id', 'player_statistics.user_id',
         'rating_history.user_id', 'system_admins.user_id') then
      raise exception 'MERGE_UNHANDLED_REFERENCE'
        using detail = v_ref.tbl || '.' || v_ref.col;
    end if;
  end loop;

  -- ---- 6. the preview, again, in this transaction ----------------------------
  v_doc := public.admin_preview_account_merge(p_retained_user_id, p_source_user_id);
  v_blockers := array(
    select e->>'code'
      from jsonb_array_elements(v_doc->'findings') e
     where e->>'severity' = 'BLOCKER'
     order by 1);
  if cardinality(v_blockers) > 0 then
    raise exception 'MERGE_BLOCKED' using detail = array_to_string(v_blockers, ',');
  end if;
  -- The picture is removed through the Storage API BEFORE this runs (the
  -- `admin-merge-accounts` Edge Function). Not removed means not called through it: refuse
  -- rather than leave a public file behind a deleted account.
  if cardinality(public.merge_source_stored_files(p_source_user_id)) > 0 then
    raise exception 'SOURCE_FILES_REMAIN';
  end if;

  -- ---- 7. the admin's explicit choices ------------------------------------------
  v_shared_ids := array(
    select s.match_id
      from public.merge_shared_matches(p_retained_user_id, p_source_user_id) s
     order by 1);
  v_missing := array(select x from unnest(v_shared_ids) x where x <> all (v_res_ids));
  if cardinality(v_missing) > 0 then
    raise exception 'RESOLUTION_REQUIRED'
      using detail = array_to_string(v_missing[1:25], ',');
  end if;
  v_unknown := array(select x from unnest(v_res_ids) x where x <> all (v_shared_ids));
  if cardinality(v_unknown) > 0 then
    raise exception 'RESOLUTION_UNKNOWN_MATCH'
      using detail = array_to_string(v_unknown[1:25], ',');
  end if;
  for v_i in 1 .. coalesce(cardinality(v_res_ids), 0) loop
    -- keeping the retained account's side removes the source's, and vice versa
    v_codes := public.merge_participation_blockers(
      v_res_ids[v_i],
      case when v_res_keep[v_i] = 'retained' then p_source_user_id
           else p_retained_user_id end);
    if cardinality(v_codes) > 0 then
      raise exception 'RESOLUTION_BLOCKED'
        using detail = v_res_ids[v_i]::text || ':' || array_to_string(v_codes, '+');
    end if;
  end loop;

  -- ---- 8. what must not change ---------------------------------------------------
  v_before := public.merge_invariants(p_retained_user_id, p_source_user_id);
  select u.overall_rating into v_rating_before
    from public.users u where u.id = p_retained_user_id;
  select u.full_name into v_name
    from public.users u where u.id = p_retained_user_id;

  -- ---- 9a. remove the dropped side of every shared match -------------------------
  for v_i in 1 .. coalesce(cardinality(v_res_ids), 0) loop
    v_mid := v_res_ids[v_i];
    -- the account whose participation goes
    v_dropped := case when v_res_keep[v_i] = 'retained'
                      then p_source_user_id else p_retained_user_id end;

    delete from public.match_registrations r
     where r.match_id = v_mid and r.user_id = v_dropped;
    get diagnostics v_n = row_count;
    c_dropped_registrations := c_dropped_registrations + v_n;
    if v_n > 0 and exists (select 1 from public.matches m
                            where m.id = v_mid and m.end_at > now()
                              and m.status <> 'completed') then
      v_restore_ids := v_restore_ids || v_mid;
    end if;

    delete from public.match_team_assignments t
     where t.match_id = v_mid and t.user_id = v_dropped;
    get diagnostics v_n = row_count;
    c_dropped_lineup_places := c_dropped_lineup_places + v_n;
    if v_n > 0 and exists (select 1 from public.matches m
                            where m.id = v_mid and m.end_at > now()
                              and m.status <> 'completed')
       and not (v_mid = any (v_restore_ids)) then
      v_restore_ids := v_restore_ids || v_mid;
    end if;
  end loop;

  -- ---- 9b. move every other football record from the source to the retained ------
  update public.match_registrations
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_registrations = row_count;

  update public.match_team_assignments
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_lineup_places = row_count;

  update public.match_goals
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_moved_goal_rows = row_count;

  update public.match_results
     set mvp_user_id = p_retained_user_id
   where mvp_user_id = p_source_user_id;
  get diagnostics c_moved_mvp_awards = row_count;

  update public.team_of_period_awards
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_team_awards_moved = row_count;

  -- who did it, who confirmed it, who generated it: attribution follows the person
  update public.matches
     set created_by = p_retained_user_id
   where created_by = p_source_user_id;
  get diagnostics c_matches_reattributed = row_count;

  update public.match_results
     set recorded_by = p_retained_user_id
   where recorded_by = p_source_user_id;
  update public.match_professional_guests
     set created_by = p_retained_user_id
   where created_by = p_source_user_id;
  update public.match_participation_state
     set confirmed_by = p_retained_user_id
   where confirmed_by = p_source_user_id;
  update public.btge_generation_runs
     set generated_by = p_retained_user_id
   where generated_by = p_source_user_id;
  update public.users
     set suspended_by = p_retained_user_id
   where suspended_by = p_source_user_id and id <> p_source_user_id;
  update public.communities
     set suspended_by = p_retained_user_id
   where suspended_by = p_source_user_id;

  -- ---- 10. communities: ownership passes, memberships merge, the higher role stays
  update public.communities
     set owner_id = p_retained_user_id
   where owner_id = p_source_user_id;
  get diagnostics c_communities_transferred = row_count;

  for v_c in
    select a.id as keep_id, a.role as keep_role, b.id as drop_id, b.role as drop_role
      from public.community_members a
      join public.community_members b
        on b.community_id = a.community_id and b.user_id = p_source_user_id
     where a.user_id = p_retained_user_id
     order by a.community_id
  loop
    v_drop_rank := case v_c.drop_role when 'owner' then 3 when 'admin' then 2 else 1 end;
    v_keep_rank := case v_c.keep_role when 'owner' then 3 when 'admin' then 2 else 1 end;
    if v_drop_rank > v_keep_rank then
      update public.community_members set role = v_c.drop_role where id = v_c.keep_id;
      c_roles_upgraded := c_roles_upgraded + 1;
    end if;
    delete from public.community_members where id = v_c.drop_id;
    c_memberships_merged := c_memberships_merged + 1;
  end loop;

  update public.community_members
     set user_id = p_retained_user_id
   where user_id = p_source_user_id;
  get diagnostics c_memberships_moved = row_count;

  -- ---- 11. the retained player's ratings, recalculated chronologically -----------
  -- Only the retained player moves: the engine's one write path stands aside for
  -- everyone else while this is set (section 3). First every entry still in effect
  -- is reversed, newest first, with the engine's own reversal -- an append-only
  -- trail, nothing is deleted -- then every recorded result the retained player
  -- now has evidence in is replayed oldest first, exactly as the one-time rebase
  -- of 0082 did, through the engine itself.
  perform set_config('goplay.rating_replay_user', p_retained_user_id::text, true);

  for v_m in
    select h.match_id
      from public.rating_history h
     where h.user_id = p_retained_user_id
       and h.reverses_id is null
       and not exists (select 1 from public.rating_history x where x.reverses_id = h.id)
     group by h.match_id
     order by max(h.entry_no) desc
  loop
    perform public.reverse_match_rating_effects(v_m.match_id);
    v_reversed := v_reversed + 1;
  end loop;

  select u.overall_rating into v_rating_reset
    from public.users u where u.id = p_retained_user_id;
  if v_rating_reset is distinct from 5.000 then
    raise exception 'RATING_BASELINE_MISMATCH'
      using detail = coalesce(v_rating_reset::text, 'null');
  end if;

  for v_m in
    select m.id
      from public.matches m
      join public.match_results r on r.match_id = m.id
     where exists (select 1 from public.match_team_assignments a
                    where a.match_id = m.id and a.user_id = p_retained_user_id)
        or exists (select 1 from public.match_goals g
                    where g.match_id = m.id and g.user_id = p_retained_user_id)
        or r.mvp_user_id = p_retained_user_id
     order by m.start_at, m.id
  loop
    perform public.apply_match_rating_effects(v_m.id);
    v_replayed := v_replayed + 1;
  end loop;

  perform set_config('goplay.rating_replay_user', '', true);

  select u.overall_rating into v_rating_after
    from public.users u where u.id = p_retained_user_id;

  -- The replayed chain has to be one unbroken chain from the baseline to the rating.
  if exists (
       select 1
         from (select h.rating_before, h.rating_after,
                      lag(h.rating_after) over (order by h.entry_no) as prev_after,
                      row_number() over (order by h.entry_no) as rn
                 from public.rating_history h
                where h.user_id = p_retained_user_id
                  and h.entry_no > (select coalesce(max(x.entry_no), 0)
                                      from public.rating_history x
                                     where x.user_id = p_retained_user_id
                                       and x.reverses_id is not null)) c
        where c.rn > 1 and c.rating_before is distinct from c.prev_after) then
    raise exception 'RATING_CHAIN_BROKEN';
  end if;

  -- ---- 12. the retained player's statistics, from the evidence -----------------
  -- Player statistics have a rebuild scoped to one player. Community statistics
  -- are rebuilt per community for EVERYONE, which would rewrite other players'
  -- rows; this does the same work for the retained player alone.
  perform public.rebuild_player_statistics(p_retained_user_id);

  update public.community_statistics cs
     set matches_played = 0, wins = 0, losses = 0, draws = 0, goals = 0, mvp_count = 0
   where cs.user_id = p_retained_user_id
     and (cs.matches_played, cs.wins, cs.losses, cs.draws, cs.goals, cs.mvp_count)
         is distinct from (0, 0, 0, 0, 0, 0);

  insert into public.community_statistics as cs (
    community_id, period_type, period_key, user_id,
    matches_played, wins, losses, draws, goals, mvp_count
  )
  select e.community_id, e.period_type, e.period_key, e.user_id,
         e.played, e.won, e.lost, e.drawn, e.scored, e.mvp
    from (select c.community_id, c.period_type, c.period_key, c.user_id,
                 sum(c.played)::int as played, sum(c.won)::int as won,
                 sum(c.lost)::int as lost, sum(c.drawn)::int as drawn,
                 sum(c.scored)::int as scored, sum(c.mvp)::int as mvp
            from public.matches m
            cross join lateral public.match_community_contribution(m.id) c
           where c.user_id = p_retained_user_id
             and m.id in (select a.match_id from public.match_team_assignments a
                           where a.user_id = p_retained_user_id)
           group by c.community_id, c.period_type, c.period_key, c.user_id) e
  on conflict (community_id, period_type, period_key, user_id) do update set
    matches_played = excluded.matches_played,
    wins           = excluded.wins,
    losses         = excluded.losses,
    draws          = excluded.draws,
    goals          = excluded.goals,
    mvp_count      = excluded.mvp_count;

  insert into public.community_statistics (community_id, period_type, period_key, user_id)
  select cm.community_id, 'overall', 'overall', cm.user_id
    from public.community_members cm
   where cm.user_id = p_retained_user_id
  on conflict (community_id, period_type, period_key, user_id) do nothing;

  delete from public.community_statistics cs
   where cs.user_id = p_retained_user_id
     and cs.period_type <> 'overall'
     and cs.matches_played = 0 and cs.wins = 0 and cs.losses = 0
     and cs.draws = 0 and cs.goals = 0 and cs.mvp_count = 0;

  -- ---- a roster that lost a registration is a roster like any other -------------
  -- For a match that has not been played, removing a registration may let a reserve
  -- in. That is a real change to other people's places and is captured and notified
  -- exactly as a cancellation would be, so the switch is off while it runs.
  perform set_config('goplay.account_merge', '', true);
  for v_i in 1 .. coalesce(cardinality(v_restore_ids), 0) loop
    perform public.rebalance_roster(v_restore_ids[v_i]);
    perform public.recompute_match_status(v_restore_ids[v_i]);
  end loop;
  perform set_config('goplay.account_merge', 'tx:' || txid_current()::text, true);

  -- ---- 13. the source's personal operational data, the mapping, the one event ----
  -- Push preferences: the retained account's stay as they are, and the source's go
  -- with it. Tokens are invalidated first, by name, rather than left to the cascade.
  delete from public.notification_push_tokens where user_id = p_source_user_id;
  get diagnostics c_push_tokens_invalidated = row_count;
  delete from public.product_activity_last_seen where user_id = p_source_user_id;

  -- The audit entries that name the source stay, with their id, actor and target UUIDs,
  -- action, reason, metadata and date. Only the e-mail of the actor and the name of the
  -- target -- the two columns that identify a person -- are emptied.
  update public.admin_audit_log a
     set actor_email_snapshot = case when a.actor_user_id = p_source_user_id
                                     then null else a.actor_email_snapshot end,
         target_label_snapshot = case when a.target_type = 'USER'
                                           and a.target_id = p_source_user_id
                                      then null else a.target_label_snapshot end
   where a.actor_user_id = p_source_user_id
      or (a.target_type = 'USER' and a.target_id = p_source_user_id);
  get diagnostics c_audit_redacted = row_count;

  insert into public.account_merge_map (source_user_id, retained_user_id)
  values (p_source_user_id, p_retained_user_id);

  v_audit := public.record_admin_audit(
    'USER_ACCOUNTS_MERGED', 'USER', p_retained_user_id, v_name, null,
    jsonb_build_object(
      'source_user_id', p_source_user_id,
      'resolutions', v_norm,
      'dropped', jsonb_build_object(
        'registrations', c_dropped_registrations,
        'lineup_places', c_dropped_lineup_places),
      'moved', jsonb_build_object(
        'registrations', c_moved_registrations,
        'lineup_places', c_moved_lineup_places,
        'goal_rows', c_moved_goal_rows,
        'mvp_awards', c_moved_mvp_awards,
        'team_awards', c_team_awards_moved,
        'communities_transferred', c_communities_transferred,
        'memberships_moved', c_memberships_moved,
        'memberships_merged', c_memberships_merged,
        'roles_upgraded', c_roles_upgraded,
        'created_matches', c_matches_reattributed),
      'rating', jsonb_build_object(
        'before', v_rating_before,
        'after', v_rating_after,
        'matches_reversed', v_reversed,
        'matches_replayed', v_replayed),
      'push_tokens_invalidated', c_push_tokens_invalidated,
      'audit_entries_redacted', c_audit_redacted));

  -- ---- 14. nothing of the source may be left, then the source goes ---------------
  if exists (select 1 from public.communities where owner_id = p_source_user_id)
     or exists (select 1 from public.community_members where user_id = p_source_user_id)
     or exists (select 1 from public.match_registrations where user_id = p_source_user_id)
     or exists (select 1 from public.match_team_assignments where user_id = p_source_user_id)
     or exists (select 1 from public.match_goals where user_id = p_source_user_id)
     or exists (select 1 from public.match_results
                 where mvp_user_id = p_source_user_id or recorded_by = p_source_user_id)
     or exists (select 1 from public.matches where created_by = p_source_user_id)
     or exists (select 1 from public.match_professional_guests
                 where created_by = p_source_user_id)
     or exists (select 1 from public.admin_audit_log a
                 where (a.actor_user_id = p_source_user_id
                        and a.actor_email_snapshot is not null)
                    or (a.target_type = 'USER' and a.target_id = p_source_user_id
                        and a.target_label_snapshot is not null))
     or cardinality(public.merge_source_stored_files(p_source_user_id)) > 0 then
    raise exception 'MERGE_RESIDUAL_REFERENCE';
  end if;

  v_after := public.merge_invariants(p_retained_user_id, p_source_user_id);
  if v_after is distinct from v_before then
    raise exception 'MERGE_INVARIANT_BROKEN'
      using detail = (select string_agg(k, ',' order by k)
                        from jsonb_object_keys(v_before) k
                       where v_before->k is distinct from v_after->k);
  end if;

  -- The Auth deletion and everything above are one transaction. The source's profile is
  -- deleted explicitly (0102 removed the cascade from Auth to it, so that a deleted
  -- account's football history can outlive its Auth user); deleting the Auth row then
  -- cascades to the source's identities, sessions and one-time tokens. A failure here
  -- undoes the whole merge.
  --
  -- Two Auth tables name the user WITHOUT a foreign key (checked on the live
  -- project): `refresh_tokens.user_id` (text) and `flow_state.user_id`. A refresh
  -- token normally goes with its session, but one with no session would outlive the
  -- user, and a pending sign-in flow carries an authorisation code. Both are removed
  -- by name, first, so nothing that could still sign the source in is left behind.
  delete from auth.refresh_tokens where user_id = p_source_user_id::text;
  delete from auth.flow_state where user_id = p_source_user_id;

  delete from public.users where id = p_source_user_id;
  delete from auth.users where id = p_source_user_id;
  get diagnostics v_n = row_count;
  if v_n <> 1
     or exists (select 1 from public.users where id = p_source_user_id)
     or exists (select 1 from auth.identities where user_id = p_source_user_id)
     or exists (select 1 from auth.sessions where user_id = p_source_user_id)
     or exists (select 1 from auth.refresh_tokens where user_id = p_source_user_id::text)
     or exists (select 1 from auth.flow_state where user_id = p_source_user_id) then
    raise exception 'AUTH_DELETE_INCOMPLETE';
  end if;

  perform set_config('goplay.account_merge', '', true);
  perform set_config('goplay.account_merge_users', '', true);

  return jsonb_build_object(
    'merged', true,
    'retained_user_id', p_retained_user_id,
    'source_user_id', p_source_user_id,
    'audit_id', v_audit,
    'dropped', jsonb_build_object(
      'registrations', c_dropped_registrations,
      'lineup_places', c_dropped_lineup_places),
    'moved', jsonb_build_object(
      'registrations', c_moved_registrations,
      'lineup_places', c_moved_lineup_places,
      'goal_rows', c_moved_goal_rows,
      'mvp_awards', c_moved_mvp_awards,
      'team_awards', c_team_awards_moved,
      'communities_transferred', c_communities_transferred,
      'memberships_moved', c_memberships_moved,
      'memberships_merged', c_memberships_merged,
      'roles_upgraded', c_roles_upgraded,
      'created_matches', c_matches_reattributed),
    'rating', jsonb_build_object(
      'before', v_rating_before,
      'after', v_rating_after,
      'matches_replayed', v_replayed),
    'audit_entries_redacted', c_audit_redacted);
end;
$$;

comment on function public.admin_merge_accounts(uuid, uuid, jsonb) is
  'Platform Admin: folds a source account into a retained one and removes the '
  'source for good -- from public.users and auth.users, with its identities and '
  'sessions -- in ONE transaction. Needs the admin''s explicit choice for every '
  'match both accounts took part in. Refuses (MERGE_BLOCKED, RESOLUTION_*) rather '
  'than discard goals, an MVP award, a result or a confirmed lineup. Recalculates '
  'the retained player''s ratings chronologically and rebuilds their statistics; '
  'touches no other player''s. Empties the name and e-mail snapshots of the audit '
  'entries that name the source, writes one USER_ACCOUNTS_MERGED audit event and one '
  'row of account_merge_map. Refuses while the source still has a stored profile '
  'picture (SOURCE_FILES_REMAIN): the admin-merge-accounts Edge Function removes it '
  'first. System Admin only (NOT_AUTHORIZED). Migrations 0101, 0102.';
