-- ===== migrations/0101_platform_admin_account_merge.sql =====
-- Platform Admin: merge one account into another, for good.
--
-- Not applied by this commit. Forward-only: nothing in 0001-0100 is edited. The
-- numbers 0097-0100 are taken (0097 and 0098 are applied live, 0100 is on
-- `develop`); this is the next unoccupied one.
--
-- ## WHAT IT ADDS
--
--   admin_merge_accounts(retained, source, resolutions)   the merge (section 8)
--   admin_preview_account_merge(retained, source)         the preview, graded for it
--   account_merge_map                                     source UUID -> retained UUID
--   helpers (all internal)                                shared by the two above; one of them,
--                                                         merge_source_stored_files, is for the
--                                                         service role (the Edge Function)
--
-- and changes four existing functions, each by ONE guard at the top of its body
-- (section 5), leaving every other line as it was and inert unless a merge is
-- running: the two lifecycle triggers for registrations and memberships, the
-- lineup revision trigger, and the rating engine's single write path.
--
-- ## THE CONTRACT THIS IMPLEMENTS
--
-- IDENTITY. The retained UUID stays. The source is removed from `public.users`
-- AND `auth.users`, with its sign-in identities and sessions, in the SAME
-- transaction as the football merge -- the last write of the function is
-- `delete from auth.users`, so either all of it happens or none of it does. There
-- is no suspended copy and no login-capable tombstone. The old UUID survives only
-- where history legitimately names it, and in `account_merge_map`, which holds the
-- two UUIDs and the time and nothing else.
--
-- FOOTBALL. Completed matches, participation, goals, MVP awards, results and
-- statistics are kept. Nothing is duplicated and no goal, MVP award or recorded
-- result is discarded: the merge fingerprints results and goal totals before and
-- after, and rolls back if either moved. A match both accounts took part in needs
-- the admin's explicit choice of which side survives, and the other side can go
-- only if it holds a bare registration (or a lineup place in a match with no
-- result and no confirmed lineup); anything else must be corrected through the
-- existing workflow first.
--
-- RATINGS. The retained player's rating is recalculated chronologically with the
-- rules already in force: every entry still in effect is reversed, newest first
-- (append-only, as the correction flow does it), and every recorded result the
-- player now has evidence in is replayed oldest first through
-- `apply_match_rating_effects` -- the engine itself, as the 0082 rebase did, not a
-- copy of it. Only the retained player moves; every other player's rating, rating
-- history and statistics are fingerprinted and must come out identical.
--
-- COMMUNITIES. Communities the source owns pass to the retained account; where both
-- are members the higher role stays (owner > admin > player) and the duplicate
-- membership is removed. Two awards in one Team of the Period block the merge
-- rather than lose one.
--
-- NOTIFICATIONS. The retained account's push preferences stay as they are; the
-- source's push tokens are invalidated. No registration or membership lifecycle
-- event is made up for the accounts' own rows, and exactly one audit event is
-- written, `USER_ACCOUNTS_MERGED`, whose payload carries UUIDs, counts and the
-- admin's match choices -- no name, no e-mail.
--
-- ## WHERE THE OLD UUID REMAINS, AND WHY THAT IS THE APPROVED EXCEPTION
--
--   kept as it is        rating_history_archive, user_rating_archive (immutable: UPDATE
--                        and DELETE are rejected by trigger), match_registration_events,
--                        community_membership_events, product_events,
--                        btge_generation_runs.player_inputs / generated_lineup (ids inside
--                        jsonb), auth.flow_state (short-lived)
--   repointed            every attribution column on a live football record: matches.created_by,
--                        match_results.recorded_by / mvp_user_id, match_professional_guests.created_by,
--                        match_participation_state.confirmed_by, btge_generation_runs.generated_by,
--                        users.suspended_by, communities.suspended_by, team_of_period_awards.user_id
--   deleted              the source's notifications, push tokens and preferences, last-seen marker,
--                        player and community statistics, rating history (operational rows), and
--                        its profile, identities and sessions
--
-- ## HOW THE TRANSACTION STAYS ONE TRANSACTION
--
-- Deleting from `auth.users` in SQL is how `admin_delete_user` (0017) already works
-- on this project, and was checked read-only against the live project on 2026-10-10:
--   * the function owner (`postgres`) holds DELETE on auth.users, auth.identities and
--     auth.sessions;
--   * every table that references `auth.users` cascades (identities, sessions, MFA,
--     one-time tokens, OAuth, WebAuthn; refresh tokens cascade from sessions), the one
--     exception being `auth.scim_users`, which is SET NULL;
--   * the only trigger on `auth.users` fires on INSERT, so a delete runs none;
--   * no table in `storage` references `auth.users`;
--   * two Auth tables hold the user id with NO foreign key (`refresh_tokens`, `flow_state`),
--     and `postgres` may delete from both, so the merge removes them by name.
-- There is no Auth Admin API call and no second round trip on the database or Auth side:
-- the Edge Function of decision 2 below only removes the picture BEFORE this transaction.
--
-- ## TWO DECISIONS THE PRODUCT OWNER HAS TAKEN (2026-10-10)
--
-- 1. AUDIT SNAPSHOTS. `admin_audit_log` keeps the e-mail of the administrator who
--    acted (`actor_email_snapshot`) and a name for the account acted on
--    (`target_label_snapshot`). When an account is merged away, the merge sets those two
--    columns to NULL on every entry that names it as actor or as target, in the same
--    transaction. Nothing else of an entry changes and no entry is deleted: its id, actor
--    and target UUIDs, action, reason, metadata (field names and UUIDs only) and date
--    stay, so the entry still reads "an administrator did this to this UUID, then", and
--    `account_merge_map` says whom the UUID became. An entry naming the source is a
--    constraint of the preview (`AUDIT_LOG_NAMES_SOURCE`), not a blocker. The
--    administrator's own free-text `reason` is kept as written.
-- 2. STORED FILES. A profile picture lives in Storage (bucket `avatars`, folder `<uuid>/`),
--    whose `protect_delete` trigger refuses any delete from SQL. It is removed through the
--    Storage API by the `admin-merge-accounts` Edge Function, which first proves the
--    caller is a System Admin and that the preview has no blocker, deletes only the
--    source's folder, and only then calls this merge. The merge itself makes no HTTP call.
--    If the merge then fails, the picture stays removed; both accounts and all football
--    record are untouched, and the function says so. A picture still present when the merge
--    runs is refused (`SOURCE_FILES_REMAIN`) instead of being left public behind a deleted
--    account. `SOURCE_HAS_STORED_FILES` is a constraint of the preview, not a blocker.
--
-- ## ORDER AND THE REST OF THE CHAIN
--
-- Needs 0062 (the audit log), 0088 (the lifecycle triggers), 0073/0078 (the rating
-- engine), 0096 (the preview it replaces) and 0099. Independent of 0097 and 0100. 0098
-- redefines `is_system_admin()`; this migration calls it and also checks `system_admins`
-- itself, so it behaves the same with or without it.
--
-- Apply it, then run `tool/0101_..._verify.sql`: every row true. Roll back with
-- `rollback/0101_..._rollback.sql`, which refuses once a merge has happened (a merge
-- cannot be undone, and the mapping is the only record of whom an old UUID became).
--
-- Review and approve separately before running against the live database. Do not
-- merge real accounts to test it.


-- ============================================================================
-- 1) The only thing that outlives the source account: who it became
-- ============================================================================
-- One row per merge: the retired UUID and the UUID it was folded into. Nothing
-- else -- no name, no e-mail, no phone, no provider, no credential. It exists so
-- that the places which legitimately keep the old UUID (the immutable rating
-- archives, the event logs, the analytics events, the lineup-generation
-- evidence) can still be read as the retained player's history.
--
-- No foreign key on either column, deliberately. The source row is gone by the
-- time this row is written, and a foreign key on the retained side would delete
-- this mapping when that account is itself merged away later (A -> B, then
-- B -> C), which would silently cut A's history off. A chain is read by following
-- it. The primary key is what makes a source mergeable once: a UUID is never
-- reused.
--
-- Like the event logs it is closed to every client role; only the service role
-- may read it, and only the merge function writes it.
create table if not exists public.account_merge_map (
  source_user_id uuid primary key,
  retained_user_id uuid not null,
  merged_at timestamptz not null default now(),
  constraint account_merge_map_distinct check (source_user_id <> retained_user_id)
);

create index if not exists account_merge_map_retained_idx
  on public.account_merge_map (retained_user_id);

comment on table public.account_merge_map is
  'Account merge (0101): the retired source UUID and the retained UUID it was '
  'folded into, and when. Deliberately minimal: no profile detail, name, e-mail '
  'or credential of the source is kept. Written only by admin_merge_accounts; '
  'readable by no client role.';

alter table public.account_merge_map enable row level security;
revoke all on table public.account_merge_map from anon, authenticated, public;
grant select on table public.account_merge_map to service_role;


-- ============================================================================
-- 2) The audit trail gains the one event a merge writes
-- ============================================================================
-- The same statement pair 0095 used for USER_PROFILE_UPDATED. It changes which
-- action names are accepted and nothing else: the log is still closed to every
-- client role by row level security and revoked privileges. (The one change a merge
-- makes to existing entries is to empty the two snapshot columns of those that name
-- the merged-away account; see section 8, step 13.)
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED',
    'USER_PROFILE_UPDATED',
    'USER_ACCOUNTS_MERGED'
  ));


-- ============================================================================
-- 3) Transaction-bound switches the merge uses -- and nothing else can
-- ============================================================================
-- A merge has to move the two accounts' own rows (a registration, a lineup place,
-- a membership) WITHOUT inventing history for them, and has to run the rating
-- engine for ONE player only. Three existing trigger functions and the engine's
-- single write path therefore ask these two helpers whether they are being called
-- from inside a merge.
--
-- What makes them safe:
--   * The switch is bound to the transaction: the merge sets it to `tx:<txid>`
--     with set_config(..., is_local => true), and the helpers compare it with
--     txid_current(). A value left over from another transaction, or set for the
--     whole session, does not match and does nothing.
--   * It names the two accounts. A change to anybody else's row -- the reserve a
--     registration's removal promotes, say -- is captured exactly as always.
--   * No trigger is disabled and nothing is altered: the triggers run, decide
--     "this row belongs to one of the two accounts being merged", and stand aside.
--   * Both helpers read settings only. No client role can reach them.
create or replace function public.merge_skips_lifecycle(p_user_id uuid)
returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_flag text := current_setting('goplay.account_merge', true);
  v_users text;
begin
  if v_flag is null or v_flag = '' then
    return false;
  end if;
  if v_flag <> 'tx:' || txid_current()::text then
    return false;
  end if;
  v_users := current_setting('goplay.account_merge_users', true);
  return p_user_id is not null
     and v_users is not null
     and p_user_id::text = any (string_to_array(v_users, ','));
end;
$$;

create or replace function public.merge_rating_scope_excludes(p_user_id uuid)
returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_flag text := current_setting('goplay.account_merge', true);
  v_only text;
begin
  if v_flag is null or v_flag = '' then
    return false;
  end if;
  if v_flag <> 'tx:' || txid_current()::text then
    return false;
  end if;
  v_only := nullif(current_setting('goplay.rating_replay_user', true), '');
  return v_only is not null and p_user_id::text is distinct from v_only;
end;
$$;

revoke execute on function public.merge_skips_lifecycle(uuid)
  from anon, authenticated, public;
revoke execute on function public.merge_rating_scope_excludes(uuid)
  from anon, authenticated, public;

comment on function public.merge_skips_lifecycle(uuid) is
  'Account merge (0101), INTERNAL: true only inside the merge transaction, and only '
  'for a row of one of the two accounts being merged. Lets the lifecycle triggers '
  'stand aside for those rows. Reads settings only.';
comment on function public.merge_rating_scope_excludes(uuid) is
  'Account merge (0101), INTERNAL: true only inside the merge transaction while one '
  'account''s ratings are being recalculated, for every other account. Reads '
  'settings only.';


-- ============================================================================
-- 4) Which matches both accounts took part in, and whether either may let go
-- ============================================================================
-- Evidence of taking part in a match is a registration, a lineup place, goals,
-- the MVP award, or a rating entry. A match both accounts have any of is SHARED,
-- and a retained account may have only one effective participation in it, so the
-- admin must choose which survives.
create or replace function public.merge_shared_matches(
  p_retained_user_id uuid,
  p_source_user_id uuid
)
returns table (match_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with ev as (
    select r.match_id, r.user_id
      from public.match_registrations r
     where r.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select t.match_id, t.user_id
      from public.match_team_assignments t
     where t.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select g.match_id, g.user_id
      from public.match_goals g
     where g.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select mr.match_id, mr.mvp_user_id
      from public.match_results mr
     where mr.mvp_user_id in (p_retained_user_id, p_source_user_id)
    union all
    select h.match_id, h.user_id
      from public.rating_history h
     where h.user_id in (p_retained_user_id, p_source_user_id)
  )
  select ev.match_id
    from ev
   group by ev.match_id
  having bool_or(ev.user_id = p_retained_user_id)
     and bool_or(ev.user_id = p_source_user_id);
$$;

-- What stops one account's participation in one match from being removed. Empty
-- means it may be: the account only holds a registration, or a lineup place in a
-- match with no result that nobody has confirmed. Anything else is football
-- record -- goals, the MVP award, a place in a lineup a result was recorded
-- from, a lineup an organizer confirmed, a rating that is still in effect -- and
-- is never discarded by a merge. It has to be corrected through the existing
-- workflow first.
create or replace function public.merge_participation_blockers(
  p_match_id uuid,
  p_user_id uuid
)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_remove(array[
    case when exists (select 1 from public.match_goals g
                       where g.match_id = p_match_id and g.user_id = p_user_id)
         then 'GOALS' end,
    case when exists (select 1 from public.match_results r
                       where r.match_id = p_match_id and r.mvp_user_id = p_user_id)
         then 'MVP' end,
    case when exists (select 1 from public.match_team_assignments a
                       where a.match_id = p_match_id and a.user_id = p_user_id)
          and exists (select 1 from public.match_results r
                       where r.match_id = p_match_id)
         then 'LINEUP_IN_RESULT' end,
    case when exists (select 1 from public.match_team_assignments a
                       where a.match_id = p_match_id and a.user_id = p_user_id)
          and exists (select 1 from public.match_participation_state s
                       where s.match_id = p_match_id
                         and s.confirmed_revision is not null)
         then 'CONFIRMED_LINEUP' end,
    case when exists (select 1 from public.rating_history h
                       where h.match_id = p_match_id and h.user_id = p_user_id
                         and h.reverses_id is null
                         and not exists (select 1 from public.rating_history x
                                          where x.reverses_id = h.id))
         then 'RATING_IN_EFFECT' end
  ], null), '{}'::text[]);
$$;

-- The source's stored profile picture(s): the object names in the `avatars` bucket whose
-- first path segment is the account's UUID (the folder the Storage policies give each
-- player, migration 0031). SQL cannot delete them -- Storage's `protect_delete` trigger
-- refuses -- so the `admin-merge-accounts` Edge Function reads this list with the service
-- role, removes exactly these objects through the Storage API, and reads it again. The
-- preview counts it and the merge refuses while it is not empty, so all three use one
-- definition of "the source's files".
create or replace function public.merge_source_stored_files(p_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(o.name order by o.name), '{}'::text[])
    from (select s.name
            from storage.objects s
           where s.bucket_id = 'avatars'
             and split_part(s.name, '/', 1) = p_user_id::text
           order by s.name
           limit 1000) o;
$$;

revoke execute on function public.merge_shared_matches(uuid, uuid)
  from anon, authenticated, public;
revoke execute on function public.merge_participation_blockers(uuid, uuid)
  from anon, authenticated, public;
revoke execute on function public.merge_source_stored_files(uuid)
  from anon, authenticated, public;
grant execute on function public.merge_source_stored_files(uuid) to service_role;

comment on function public.merge_shared_matches(uuid, uuid) is
  'Account merge (0101), INTERNAL: the matches both accounts have participation '
  'evidence in. Shared by the preview and the merge so they cannot disagree.';
comment on function public.merge_participation_blockers(uuid, uuid) is
  'Account merge (0101), INTERNAL: why one account''s participation in one match '
  'cannot be removed (GOALS, MVP, LINEUP_IN_RESULT, CONFIRMED_LINEUP, '
  'RATING_IN_EFFECT); empty when it can. Shared by the preview and the merge.';
comment on function public.merge_source_stored_files(uuid) is
  'Account merge (0101), INTERNAL: the names of the objects in the avatars bucket '
  'under an account''s UUID folder (at most 1000). Executable by the service role '
  'only, for the admin-merge-accounts Edge Function; read-only.';


-- ============================================================================
-- 5) Four existing functions, each with ONE guard, each otherwise as it is live
-- ============================================================================
-- `create or replace`, so the OIDs, owners, grants and trigger bindings stay. Each
-- body below is the body that runs on the live project (the hashes were compared
-- on 2026-10-10) plus the marked guard and nothing else.

create or replace function public.capture_match_registration_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id uuid;
  v_user_id uuid;
  v_registration_id uuid;
  v_community_id uuid;
  v_completed boolean;
  v_from_status text;
  v_to_status text;
  v_operation text;
begin
  -- (0101) Account merge. A merge moves the two accounts' own rows and must not
  -- invent history for them: see merge_skips_lifecycle(). Rows of anybody else, and
  -- every change made outside a merge, are handled exactly as before.
  if public.merge_skips_lifecycle(
       case when tg_op = 'DELETE' then old.user_id else new.user_id end) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.user_id is null then return new; end if;
    v_match_id := new.match_id;
    v_user_id := new.user_id;
    v_registration_id := new.id;
    v_operation := 'created';
    v_from_status := null;
    v_to_status := new.status;
  elsif tg_op = 'UPDATE' then
    if new.user_id is null or new.status is not distinct from old.status then
      return new;
    end if;
    v_match_id := new.match_id;
    v_user_id := new.user_id;
    v_registration_id := new.id;
    v_operation := 'status_changed';
    v_from_status := old.status;
    v_to_status := new.status;
  else
    if old.user_id is null then return old; end if;
    v_match_id := old.match_id;
    v_user_id := old.user_id;
    v_registration_id := old.id;
    v_operation := 'deleted';
    v_from_status := old.status;
    v_to_status := null;
  end if;

  select
    m.community_id,
    (m.status = 'completed' or m.end_at <= now())
  into v_community_id, v_completed
  from public.matches m
  where m.id = v_match_id;

  insert into public.match_registration_events (
    registration_id,
    match_id,
    community_id,
    user_id,
    actor_user_id,
    operation,
    from_status,
    to_status,
    match_was_completed
  )
  values (
    v_registration_id,
    v_match_id,
    v_community_id,
    v_user_id,
    auth.uid(),
    v_operation,
    v_from_status,
    v_to_status,
    v_completed
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.capture_community_membership_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- (0101) Account merge. A merge moves the two accounts' own rows and must not
  -- invent history for them: see merge_skips_lifecycle(). Rows of anybody else, and
  -- every change made outside a merge, are handled exactly as before.
  if public.merge_skips_lifecycle(
       case when tg_op = 'DELETE' then old.user_id else new.user_id end) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    insert into public.community_membership_events (
      membership_id,
      community_id,
      user_id,
      actor_user_id,
      operation,
      from_role,
      to_role
    )
    values (
      new.id,
      new.community_id,
      new.user_id,
      auth.uid(),
      'joined',
      null,
      new.role
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.role is not distinct from old.role then return new; end if;
    insert into public.community_membership_events (
      membership_id,
      community_id,
      user_id,
      actor_user_id,
      operation,
      from_role,
      to_role
    )
    values (
      new.id,
      new.community_id,
      new.user_id,
      auth.uid(),
      'role_changed',
      old.role,
      new.role
    );
    return new;
  end if;

  insert into public.community_membership_events (
    membership_id,
    community_id,
    user_id,
    actor_user_id,
    operation,
    from_role,
    to_role
  )
  values (
    old.id,
    old.community_id,
    old.user_id,
    auth.uid(),
    'deleted',
    old.role,
    null
  );
  return old;
end;
$$;

create or replace function public.advance_match_participation_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id uuid;
  v_community_id uuid;
  v_status text;
  v_end_at timestamptz;
  v_revision bigint;
  v_actor uuid;
begin
  -- (0101) Account merge. A merge moves the two accounts' own rows and must not
  -- invent history for them: see merge_skips_lifecycle(). Rows of anybody else, and
  -- every change made outside a merge, are handled exactly as before.
  if public.merge_skips_lifecycle(
       case when tg_op = 'DELETE' then old.user_id else new.user_id end) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select m.community_id, m.status, m.end_at
  into v_community_id, v_status, v_end_at
  from public.matches m
  where m.id = v_match_id;

  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  insert into public.match_participation_state (
    match_id,
    lineup_revision
  )
  values (v_match_id, 1)
  on conflict (match_id) do update
    set lineup_revision =
      public.match_participation_state.lineup_revision + 1
  returning lineup_revision into v_revision;

  v_actor := auth.uid();

  if (v_status = 'completed' or v_end_at <= now())
     and v_actor is not null
     and public.has_active_community_role(
       v_community_id,
       v_actor,
       'admin'
     )
  then
    update public.match_participation_state
    set confirmed_revision = v_revision,
        confirmed_at = now(),
        confirmed_by = v_actor
    where match_id = v_match_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.apply_rating_delta(
  p_user_id uuid,
  p_match_id uuid,
  p_reason text,
  p_delta numeric,
  p_reverses_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before numeric(5,3);
  v_after numeric(5,3);
begin
  -- (0101) Account merge: while ONE account's ratings are recalculated, the engine
  -- pays that account and nobody else: see merge_rating_scope_excludes(). Outside a
  -- merge this never fires.
  if public.merge_rating_scope_excludes(p_user_id) then
    return;
  end if;

  if p_user_id is null then return; end if;

  select overall_rating into v_before
  from users where id = p_user_id
  for update;
  if not found then return; end if;

  v_after := least(10.000, greatest(0.000, v_before + p_delta));

  update users set overall_rating = v_after where id = p_user_id;

  insert into rating_history (
    user_id, match_id, change_reason, delta,
    rating_before, rating_after, reverses_id
  )
  values (
    p_user_id, p_match_id, p_reason, v_after - v_before,
    v_before, v_after, p_reverses_id
  );
end;
$$;


-- ============================================================================
-- 6) admin_preview_account_merge(): the same preview, graded for a real merge
-- ============================================================================
-- Same signature, same gate, still STABLE and still read only; a preview writes
-- nothing. What changes is what it says, because there is now a merge to say it
-- about:
--
--   * `findings` holds only what needs attention. What the merge does by itself
--     -- transfer the communities the source owns, keep the higher role, move
--     the source's football records, re-attribute the matches it created, rebuild
--     the retained player's statistics and replay the retained player's ratings --
--     is no longer a finding; it is counted in `plan`.
--   * A match both accounts took part in is SHARED, and each side of it says what
--     would stop it being removed (`*_drop_blockers`) and so whether the admin may
--     keep the other side (`can_keep_retained`, `can_keep_source`).
--   * `has_blockers` is still exactly "some finding is a BLOCKER", and still says
--     nothing about whether a merge is authorised. The merge asks again for
--     itself, inside its own transaction.
--
-- The blockers, and why each is one:
--   SOURCE_IS_CALLER, RETAINED_IS_CALLER     an administrator cannot merge themselves
--   SOURCE_IS_SYSTEM_ADMIN, RETAINED_IS_...  System Admins are managed outside the app
--   SHARED_MATCH_NOT_RESOLVABLE              both sides hold football record that
--                                            cannot be discarded, so neither can go
--   SHARED_MATCH_LIMIT_EXCEEDED              more shared matches than one merge resolves
--   TEAM_AWARD_COLLISION                     both hold an award in one Team of the
--                                            Period; none is discarded silently
--   RETAINED_RATING_INCONSISTENT             the retained rating does not follow
--                                            from its own history, so a replay would
--                                            hide a fault instead of fixing it
-- and what is NOT a blocker: the immutable rating archives. They keep naming the old
-- UUID on purpose, and `account_merge_map` says whom it became. They are reported as
-- `RATING_ARCHIVE_MAPPED`, a code of their own, because the deletion preview's
-- `RATING_ARCHIVE_IMMUTABLE` means the opposite: there the archives BLOCK. Two more are
-- constraints, told to the administrator and done by the merge: the audit entries that
-- name the source lose their name and e-mail snapshots (`AUDIT_LOG_NAMES_SOURCE`), and the
-- source's profile picture is removed first (`SOURCE_HAS_STORED_FILES`).
create or replace function public.admin_preview_account_merge(
  p_retained_user_id uuid,
  p_source_user_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_limit constant int := 25;
  v_shared_limit constant int := 100;
  v_retained jsonb;
  v_source jsonb;
  v_overlap_total bigint;
  v_role_upgrades bigint;
  v_overlap_items jsonb;
  v_owned_total bigint;
  v_owned_items jsonb;
  v_shared jsonb;
  v_shared_total bigint;
  v_shared_unresolvable bigint;
  v_shared_ids uuid[];
  v_stat_collisions bigint;
  v_award_collisions bigint;
  v_stored_files bigint;
  v_retained_rating_bad boolean;
  v_plan jsonb;
  v_findings jsonb;
begin
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_retained_user_id is not distinct from p_source_user_id then
    raise exception 'SAME_ACCOUNT';
  end if;

  v_retained := public.admin_preview_account_snapshot(p_retained_user_id);
  v_source := public.admin_preview_account_snapshot(p_source_user_id);

  v_shared_ids := array(
    select s.match_id
      from public.merge_shared_matches(p_retained_user_id, p_source_user_id) s);

  -- ---- communities both belong to ------------------------------------------
  select count(*),
         count(*) filter (where
           case b.role when 'owner' then 3 when 'admin' then 2 else 1 end
           > case a.role when 'owner' then 3 when 'admin' then 2 else 1 end)
    into v_overlap_total, v_role_upgrades
    from public.community_members a
    join public.community_members b
      on b.community_id = a.community_id and b.user_id = p_source_user_id
   where a.user_id = p_retained_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_overlap_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'retained_role', a.role,
                   'source_role', b.role,
                   'role_conflict', a.role <> b.role,
                   'source_owns', c.owner_id = p_source_user_id,
                   'retained_owns', c.owner_id = p_retained_user_id) as item,
                 row_number() over (
                   order by (c.owner_id = p_source_user_id) desc,
                            (a.role <> b.role) desc, c.name, c.id) as rn
            from public.community_members a
            join public.community_members b
              on b.community_id = a.community_id and b.user_id = p_source_user_id
            join public.communities c on c.id = a.community_id
           where a.user_id = p_retained_user_id) s
   where s.rn <= v_limit;

  -- ---- communities the source owns: they pass to the retained account -------
  select count(*) into v_owned_total
    from public.communities c
   where c.owner_id = p_source_user_id;

  select coalesce(jsonb_agg(s.item order by s.rn), '[]'::jsonb)
    into v_owned_items
    from (select jsonb_build_object(
                   'community_id', c.id,
                   'name', c.name,
                   'retained_is_member', a.id is not null,
                   'retained_role', a.role) as item,
                 row_number() over (order by c.name, c.id) as rn
            from public.communities c
            left join public.community_members a
              on a.community_id = c.id and a.user_id = p_retained_user_id
           where c.owner_id = p_source_user_id) s
   where s.rn <= v_limit;

  -- ---- matches both appear in ------------------------------------------------
  with ev as (
    select r.match_id, 'REGISTRATION'::text as kind, r.user_id
      from public.match_registrations r
     where r.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select t.match_id, 'LINEUP', t.user_id
      from public.match_team_assignments t
     where t.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select g.match_id, 'GOALS', g.user_id
      from public.match_goals g
     where g.user_id in (p_retained_user_id, p_source_user_id)
    union all
    select mr.match_id, 'MVP', mr.mvp_user_id
      from public.match_results mr
     where mr.mvp_user_id in (p_retained_user_id, p_source_user_id)
    union all
    select h.match_id, 'RATING', h.user_id
      from public.rating_history h
     where h.user_id in (p_retained_user_id, p_source_user_id)
  ),
  kinds as (
    select ev.match_id,
           array_agg(distinct ev.kind order by ev.kind)
             filter (where ev.user_id = p_retained_user_id) as retained_kinds,
           array_agg(distinct ev.kind order by ev.kind)
             filter (where ev.user_id = p_source_user_id) as source_kinds
      from ev
     where ev.match_id = any (v_shared_ids)
     group by ev.match_id
  ),
  judged as (
    select k.match_id, k.retained_kinds, k.source_kinds,
           public.merge_participation_blockers(k.match_id, p_retained_user_id) as retained_blockers,
           public.merge_participation_blockers(k.match_id, p_source_user_id) as source_blockers
      from kinds k
  ),
  flagged as (
    select j.*,
           -- keeping the retained account's side removes the source's, and vice versa
           cardinality(j.source_blockers) = 0 as can_keep_retained,
           cardinality(j.retained_blockers) = 0 as can_keep_source
      from judged j
  )
  select jsonb_build_object(
           'total', count(*),
           'unresolvable_total', count(*) filter (
             where not f.can_keep_retained and not f.can_keep_source),
           'items', (
             select coalesce(jsonb_agg(i.item order by i.rn), '[]'::jsonb)
               from (select jsonb_build_object(
                              'match_id', m.id,
                              'title', m.title,
                              'community_name', c.name,
                              'start_at', m.start_at,
                              'status', m.status,
                              'is_historical', m.is_historical,
                              'retained_evidence', f2.retained_kinds,
                              'source_evidence', f2.source_kinds,
                              'retained_drop_blockers', f2.retained_blockers,
                              'source_drop_blockers', f2.source_blockers,
                              'can_keep_retained', f2.can_keep_retained,
                              'can_keep_source', f2.can_keep_source) as item,
                            row_number() over (
                              order by (not f2.can_keep_retained and not f2.can_keep_source) desc,
                                       m.start_at desc, m.id) as rn
                       from flagged f2
                       join public.matches m on m.id = f2.match_id
                       join public.communities c on c.id = m.community_id) i
              where i.rn <= v_shared_limit))
    into v_shared
    from flagged f;

  v_shared_total := coalesce((v_shared->>'total')::bigint, 0);
  v_shared_unresolvable := coalesce((v_shared->>'unresolvable_total')::bigint, 0);

  -- ---- statistics and awards ----------------------------------------------------
  -- Statistics are rebuilt from the evidence, so a collision of rows is not a
  -- problem; it is shown so the admin can see what is rebuilt. Awards are not
  -- derived from anything: two awards in one Team of the Period cannot both be
  -- kept under one UUID, and one is never discarded silently.
  select count(*) into v_stat_collisions
    from public.community_statistics a
    join public.community_statistics b
      on b.community_id = a.community_id
     and b.period_type = a.period_type
     and b.period_key = a.period_key
     and b.user_id = p_source_user_id
   where a.user_id = p_retained_user_id;

  select count(*) into v_award_collisions
    from public.team_of_period_awards a
    join public.team_of_period_awards b
      on b.snapshot_id = a.snapshot_id and b.user_id = p_source_user_id
   where a.user_id = p_retained_user_id;

  -- ---- what no SQL can erase ----------------------------------------------------
  -- Storage refuses a direct delete (storage.protect_delete), and the avatars bucket is
  -- public, so a picture left behind would stay reachable by a path that begins with the
  -- source's UUID. The admin-merge-accounts Edge Function removes it before the merge.
  v_stored_files := cardinality(public.merge_source_stored_files(p_source_user_id));

  -- ---- the retained rating must follow from its own history ----------------------
  -- A replay starts from the 5.000 baseline. If the stored rating is not what the
  -- history says it is, replaying would paper over a fault.
  select case
           when not exists (select 1 from public.rating_history h
                             where h.user_id = p_retained_user_id)
             then (select u.overall_rating from public.users u
                    where u.id = p_retained_user_id) <> 5.000
           else (select h.rating_before from public.rating_history h
                  where h.user_id = p_retained_user_id
                  order by h.entry_no asc limit 1) <> 5.000
             or (select h.rating_after from public.rating_history h
                  where h.user_id = p_retained_user_id
                  order by h.entry_no desc limit 1)
                <> (select u.overall_rating from public.users u
                     where u.id = p_retained_user_id)
         end
    into v_retained_rating_bad;

  -- ---- what the merge will do by itself -------------------------------------------
  select jsonb_build_object(
           'communities_transferred', v_owned_total,
           'memberships_merged', v_overlap_total,
           'roles_upgraded', v_role_upgrades,
           'memberships_moved', (
             select count(*) from public.community_members b
              where b.user_id = p_source_user_id
                and not exists (select 1 from public.community_members a
                                 where a.community_id = b.community_id
                                   and a.user_id = p_retained_user_id)),
           'registrations_moved', (
             select count(*) from public.match_registrations r
              where r.user_id = p_source_user_id and r.match_id <> all (v_shared_ids)),
           'lineup_places_moved', (
             select count(*) from public.match_team_assignments t
              where t.user_id = p_source_user_id and t.match_id <> all (v_shared_ids)),
           'goal_rows_moved', (
             select count(*) from public.match_goals g
              where g.user_id = p_source_user_id and g.match_id <> all (v_shared_ids)),
           'mvp_awards_moved', (
             select count(*) from public.match_results mr
              where mr.mvp_user_id = p_source_user_id and mr.match_id <> all (v_shared_ids)),
           'team_awards_moved', (
             select count(*) from public.team_of_period_awards w
              where w.user_id = p_source_user_id),
           'created_matches_reattributed',
             (v_source->'counts'->>'created_matches')::bigint,
           'shared_matches', v_shared_total)
    into v_plan;

  -- ---- findings ----------------------------------------------------------------
  select coalesce(jsonb_agg(
           jsonb_build_object('code', f.code, 'severity', f.severity,
                              'category', f.category, 'count', f.n)
           order by f.rank, f.code), '[]'::jsonb)
    into v_findings
    from (values
      ('SOURCE_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_source->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('RETAINED_IS_CALLER', 'BLOCKER', 'IDENTITY',
         case when (v_retained->'account'->>'is_caller')::boolean then 1 else 0 end, 1),
      ('SOURCE_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_source->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('RETAINED_IS_SYSTEM_ADMIN', 'BLOCKER', 'IDENTITY',
         case when (v_retained->'account'->>'is_system_admin')::boolean then 1 else 0 end, 1),
      ('SHARED_MATCH_NOT_RESOLVABLE', 'BLOCKER', 'MATCH', v_shared_unresolvable, 1),
      ('SHARED_MATCH_LIMIT_EXCEEDED', 'BLOCKER', 'MATCH',
         case when v_shared_total > v_shared_limit then v_shared_total else 0 end, 1),
      ('TEAM_AWARD_COLLISION', 'BLOCKER', 'STATISTICS', v_award_collisions, 1),
      ('RETAINED_RATING_INCONSISTENT', 'BLOCKER', 'RATING',
         case when v_retained_rating_bad then 1 else 0 end, 1),
      ('SHARED_MATCH_CHOICE_REQUIRED', 'CONFLICT', 'MATCH',
         v_shared_total - v_shared_unresolvable, 2),
      ('AUDIT_LOG_NAMES_SOURCE', 'CONSTRAINT', 'AUDIT',
         (v_source->'counts'->>'audit_entries')::bigint, 3),
      ('SOURCE_HAS_STORED_FILES', 'CONSTRAINT', 'STORAGE', v_stored_files, 3),
      ('RATING_ARCHIVE_MAPPED', 'CONSTRAINT', 'ARCHIVE',
         (v_source->'counts'->>'rating_archive_rows')::bigint
           + (v_source->'counts'->>'user_rating_archive_rows')::bigint, 3),
      ('EVENT_LOGS_NAME_SOURCE', 'CONSTRAINT', 'HISTORY',
         (v_source->'counts'->>'registration_events')::bigint
           + (v_source->'counts'->>'membership_events')::bigint
           + (v_source->'counts'->>'product_events')::bigint, 3)
    ) as f(code, severity, category, n, rank)
   where f.n > 0;

  return jsonb_build_object(
    'version', 2,
    'limit', v_limit,
    'shared_limit', v_shared_limit,
    'has_blockers', exists (select 1 from jsonb_array_elements(v_findings) e
                             where e->>'severity' = 'BLOCKER'),
    'retained', v_retained,
    'source', v_source,
    'overlapping_communities', jsonb_build_object(
      'total', v_overlap_total,
      'role_conflicts_total', (
        select count(*) from public.community_members a
          join public.community_members b
            on b.community_id = a.community_id and b.user_id = p_source_user_id
         where a.user_id = p_retained_user_id and a.role <> b.role),
      'ownership_conflicts_total', 0,
      'items', v_overlap_items),
    'source_owned_communities', jsonb_build_object(
      'total', v_owned_total,
      'items', v_owned_items),
    'shared_matches', v_shared,
    'statistics_overlap', jsonb_build_object(
      'community_statistics_collisions', v_stat_collisions,
      'team_award_collisions', v_award_collisions),
    'plan', v_plan,
    'findings', v_findings,
    'coverage_notes', jsonb_build_array(
      'EMBEDDED_GENERATION_EVIDENCE_NOT_SCANNED',
      'AUTH_SESSIONS_NOT_INSPECTED')
  );
end;
$$;

comment on function public.admin_preview_account_merge(uuid, uuid) is
  'Platform Admin, READ ONLY: what merging a source account into a retained one '
  'would do and what stands in its way -- identity and activity counts, '
  'community memberships and roles, the matches both accounts took part in (each '
  'side with what would stop it being removed), a plan of what the merge does by '
  'itself, and findings graded BLOCKER / CONFLICT / CONSTRAINT. has_blockers says '
  'nothing about whether a merge is authorised: admin_merge_accounts asks again '
  'for itself. Writes nothing and records no audit event. System Admin only '
  '(NOT_AUTHORIZED); SAME_ACCOUNT; USER_NOT_FOUND. Migrations 0096, 0101.';

revoke execute on function public.admin_preview_account_merge(uuid, uuid)
  from anon, public;
grant execute on function public.admin_preview_account_merge(uuid, uuid)
  to authenticated;
grant execute on function public.admin_preview_account_merge(uuid, uuid)
  to service_role;


-- ============================================================================
-- 7) What a merge must leave exactly as it found it
-- ============================================================================
-- Fingerprints of what the merge is forbidden to change, taken before and after
-- by the merge itself. If they differ the merge raises and rolls back: a mistake
-- in the merge logic becomes a refusal, not a silently altered result.
--   * every recorded result (score) and every goal total, per match;
--   * every other player's statistics, rating history and rating.
create or replace function public.merge_invariants(
  p_retained_user_id uuid,
  p_source_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'results', (select md5(coalesce(string_agg(
                  r.match_id::text || ':' || r.team_a_score || ':' || r.team_b_score,
                  ',' order by r.match_id), ''))
                from public.match_results r),
    'result_count', (select count(*) from public.match_results),
    'goals', (select md5(coalesce(string_agg(
                  x.match_id::text || ':' || x.total, ',' order by x.match_id), ''))
              from (select g.match_id, sum(g.goals) as total
                      from public.match_goals g group by g.match_id) x),
    'goal_rows', (select count(*) from public.match_goals),
    'others_player_statistics', (select md5(coalesce(string_agg(
                  t::text, ',' order by t.user_id), ''))
              from public.player_statistics t
             where t.user_id not in (p_retained_user_id, p_source_user_id)),
    'others_community_statistics', (select md5(coalesce(string_agg(
                  t::text, ',' order by t.community_id, t.period_type, t.period_key, t.user_id), ''))
              from public.community_statistics t
             where t.user_id not in (p_retained_user_id, p_source_user_id)),
    'others_rating_history', (select md5(coalesce(string_agg(
                  h.id::text, ',' order by h.entry_no), ''))
              from public.rating_history h
             where h.user_id not in (p_retained_user_id, p_source_user_id)),
    'others_ratings', (select md5(coalesce(string_agg(
                  u.id::text || ':' || u.overall_rating, ',' order by u.id), ''))
              from public.users u
             where u.id not in (p_retained_user_id, p_source_user_id))
  );
$$;

revoke execute on function public.merge_invariants(uuid, uuid)
  from anon, authenticated, public;

comment on function public.merge_invariants(uuid, uuid) is
  'Account merge (0101), INTERNAL: fingerprints of what a merge must not change '
  '(results, goal totals, every other player''s statistics and ratings). Taken '
  'before and after by admin_merge_accounts.';


-- ============================================================================
-- 8) admin_merge_accounts() -- the merge
-- ============================================================================
-- Folds the source account into the retained one and removes the source for
-- good, in ONE transaction: every statement below either all happens or none of
-- it does, and the last write is the deletion of the source from `auth.users`, so
-- the football record, the identity and the sign-in go together or not at all.
--
--   admin_merge_accounts(p_retained_user_id, p_source_user_id, p_resolutions)
--
-- `p_resolutions` is the admin's explicit choice for every match both accounts
-- took part in: a JSON array of {"match_id": <uuid>, "keep": "retained"|"source"}.
-- It must name exactly the shared matches. Keeping one side removes the other's
-- participation, which is allowed only if that side holds nothing but a
-- registration (or a lineup place in a match with no result and no confirmed
-- lineup); goals, the MVP award, a place in a lineup a result came from, a
-- confirmed lineup and a rating still in effect are never discarded.
--
-- ## ORDER OF WORK
--
--   1.  gate: System Admin, twice (the helper, and a `system_admins` row of its own)
--   2.  arguments, then ONE advisory lock so two merges never interleave
--   3.  lock both accounts, then the communities and matches that move, always in
--       key order; both accounts must still exist (a second request for the same
--       source finds nothing)
--   4.  arm the transaction-bound switches (see section 3)
--   5.  refuse if the schema has a reference to `users` this function does not know
--   6.  the preview, again, inside the transaction: any blocker refuses the merge, and
--       so does any stored file of the source (the Edge Function removes it first)
--   7.  the resolutions must cover exactly the shared matches, each side free to go
--   8.  take the fingerprints (section 7)
--   9.  remove the dropped sides, then move everything else from source to retained
--   10. communities: ownership passes, memberships merge, the higher role stays
--   11. the retained player's ratings: every entry still in effect is reversed, then
--       every recorded result is replayed oldest first through the rating engine,
--       which pays only the retained player
--   12. the retained player's statistics are rebuilt from the evidence
--   13. the name and e-mail snapshots of the audit entries that name the source are
--       emptied, push tokens are invalidated, last-seen is cleared, the mapping and
--       the one audit event are written
--   14. fingerprints again; then `delete from auth.users` -- which removes the
--       source from `public.users`, its identities, sessions and refresh tokens --
--       and a last look that nothing of the source remains
--
-- ## WHAT IT DOES NOT TOUCH
--
-- Other players' statistics, ratings and rating history; recorded results and goal
-- totals; the immutable rating archives (they keep the old UUID, and the mapping
-- says whom it became); the event logs, analytics events and lineup-generation
-- evidence (same); audit entries, but for the two snapshot columns (name, e-mail) of
-- the entries that name the source. No trigger is disabled and nothing is altered:
-- see section 3 for how the lifecycle triggers stand aside for the two accounts'
-- own rows, and only for those.
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

  -- One merge at a time, anywhere: a rare administrative act, and the cheapest
  -- way to rule out two merges that share a community or a match deadlocking.
  perform pg_advisory_xact_lock(hashtextextended('goplay.admin_merge_accounts', 0));

  -- ---- 3. lock, in a fixed order -------------------------------------------
  perform 1
    from public.users u
   where u.id in (p_retained_user_id, p_source_user_id)
   order by u.id
     for update;
  -- Both must still exist AFTER the lock: a second request for the same source,
  -- queued behind the first, finds the source gone and stops here.
  if (select count(*) from public.users u
       where u.id in (p_retained_user_id, p_source_user_id)) <> 2 then
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

  -- The Auth deletion and everything above are one transaction. Deleting the row
  -- cascades to `public.users` and to the source's identities, sessions and
  -- one-time tokens; a failure here undoes the whole merge.
  --
  -- Two Auth tables name the user WITHOUT a foreign key (checked on the live
  -- project): `refresh_tokens.user_id` (text) and `flow_state.user_id`. A refresh
  -- token normally goes with its session, but one with no session would outlive the
  -- user, and a pending sign-in flow carries an authorisation code. Both are removed
  -- by name, first, so nothing that could still sign the source in is left behind.
  delete from auth.refresh_tokens where user_id = p_source_user_id::text;
  delete from auth.flow_state where user_id = p_source_user_id;

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
  'first. System Admin only (NOT_AUTHORIZED). Migration 0101.';

revoke execute on function public.admin_merge_accounts(uuid, uuid, jsonb)
  from anon, public;
grant execute on function public.admin_merge_accounts(uuid, uuid, jsonb)
  to authenticated;
grant execute on function public.admin_merge_accounts(uuid, uuid, jsonb)
  to service_role;
