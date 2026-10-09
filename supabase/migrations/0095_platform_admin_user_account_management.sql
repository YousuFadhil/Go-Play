-- ===== migrations/0095_platform_admin_user_account_management.sql =====
-- Platform Admin: view and edit an account's data and settings (Phase 1).
--
-- A System Admin can already list, inspect, suspend and reactivate an account.
-- What the console cannot do is show the account's own data in one place or
-- correct it. This migration adds exactly that: one read and five writes, one
-- write per operation the account holder already has. **Nothing is deleted, no
-- existing function changes, and no policy or column grant is touched.**
--
--   1. `admin_audit_log_action_check`            -- gains `USER_PROFILE_UPDATED`
--   2. `admin_get_user_account(uuid)`            -- one row for one account
--   3. `admin_update_user_account(...)`          -- full name, phone
--      `admin_update_user_player_profile(...)`   -- date of birth, positions
--      `admin_update_user_privacy(...)`          -- visibility, age visibility
--      `admin_update_user_default_wilayat(...)`  -- Default Location
--      `admin_update_user_push_preferences(...)` -- the three push switches
--
-- ## WHAT THE FIVE WRITES SHARE
--
-- There is deliberately **no generic patch RPC**: each function sets one whole
-- group, and a null argument is invalid input rather than "leave unchanged". The
-- only nulls that mean something are the three the schema allows to be empty --
-- `p_date_of_birth`, `p_secondary_position`, `p_wilayat_code` -- where null
-- clears the value.
--
-- Every write runs the same checks in the same order, so a refusal never
-- depends on what was found:
--
--   1. `is_system_admin()`                     else NOT_AUTHORIZED
--   2. target is the caller                    CANNOT_MODIFY_SELF
--   3. target is in `system_admins`            CANNOT_MODIFY_SYSTEM_ADMIN
--   4. lock and load the target row            USER_NOT_FOUND
--   5. normalise and validate the arguments
--   6. work out which columns would change; **if none, return** -- no UPDATE and
--      no audit row, because the log must not carry an event for an act that did
--      not happen
--   7. apply the update (an upsert for push preferences)
--   8. `record_admin_audit('USER_PROFILE_UPDATED', ...)` in the same transaction,
--      with no exception handler: if the audit write fails the edit fails with it
--
-- The writes behave the same whether the target is active or suspended.
--
-- **The audit metadata is `{"changed_fields": [...]}` and nothing else.** Field
-- names are column names. No before value, no after value: a phone number or a
-- date of birth is not something the audit trail should hold a copy of.
--
-- ## VALIDATION
--
-- The rules are `complete_my_player_profile`'s (`0092`) wherever it has one --
-- full name at least two characters once trimmed, phone `+968` and eight digits,
-- date of birth not before 1900-01-01 and not after today in `Asia/Muscat`,
-- positions from GK / DEF / MID / FWD with a secondary that differs from the
-- primary -- with one deliberate difference: **a null date of birth is valid**,
-- because `users.date_of_birth` is nullable and an account that never gave one
-- must stay editable. The Wilayat is checked for existence only, which is what
-- the owner's own write (a foreign key on the column) does.
--
-- Error codes are the existing ones wherever one exists. Three are new:
-- `CANNOT_MODIFY_SELF`, `CANNOT_MODIFY_SYSTEM_ADMIN` (the `0064` guards, worded
-- for an edit) and `INVALID_SETTINGS` (a visibility that is not one of the two
-- tokens, or a null boolean, in the privacy and push-preference writes -- no
-- existing code describes either).
--
-- ## PUSH PREFERENCES WITH NO ROW
--
-- `notification_push_preferences` has no row until the player first saves. The
-- read returns the column defaults (`true`, `true`, `false`) for such an account.
-- The write compares against the **same effective values**, so asking for the
-- defaults on an account with no row is a no-op: no row is created and no audit
-- event is written.
--
-- ## WHAT THE READ RETURNS FROM `auth`
--
-- `email`, `email_confirmed_at`, `last_sign_in_at`, and the **names** of the
-- sign-in providers aggregated from `auth.identities` -- one row per account,
-- whatever the number of identities. No token, no identity payload, no other
-- column of either `auth` table. Nothing in `auth` or `storage` is written.
--
-- ## PRIVILEGES
--
-- All six are `security definer` with `search_path = public`, revoked from
-- `anon` and `public`, and granted to `authenticated` and `service_role` exactly
-- as `0066` and `0068` grant the existing admin RPCs. Authorization is not the
-- grant: an ordinary account reaches these functions and is refused inside them.
-- `record_admin_audit` is reached from inside, as it is from `0064`; its own
-- grant is untouched and it remains executable by no client role.


-- ============================================================================
-- 1) The audit action
-- ============================================================================
-- One value added to the four of `0062`. The CHECK is replaced rather than
-- altered in place, because PostgreSQL has no ALTER for a CHECK expression; the
-- drop is `if exists`, so the statement pair can be run again.
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED',
    'USER_PROFILE_UPDATED'
  ));



-- ============================================================================
-- 2) admin_get_user_account() -- one account, in full
-- ============================================================================
-- Gate first, existence second, then a single `select`. It writes nothing and
-- has no self or System Admin restriction: reading an account is not editing it.
--
-- Every column reference below is qualified, without exception. The output
-- columns share names with real columns -- `id`, `phone`, `created_at`,
-- `is_active`, `is_system_admin`, `match_push` -- and in plpgsql an output
-- column is a variable, so an unqualified reference is ambiguous at run time.
--
-- The provider names are a scalar subquery, which is what guarantees exactly one
-- row however many identities the account has. The three push columns fall back
-- to the column defaults when the account has no preferences row.
create or replace function public.admin_get_user_account(p_user_id uuid)
returns table (
  id uuid,
  full_name text,
  phone text,
  email text,
  date_of_birth date,
  primary_position text,
  secondary_position text,
  profile_visibility text,
  age_visible boolean,
  default_wilayat_code smallint,
  avatar_path text,
  is_active boolean,
  suspended_at timestamptz,
  suspension_reason text,
  is_system_admin boolean,
  match_push boolean,
  community_push boolean,
  mute_all boolean,
  sign_in_providers text[],
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;

  if not exists (select 1 from users u where u.id = p_user_id) then
    raise exception 'USER_NOT_FOUND';
  end if;

  return query
    select u.id,
           u.full_name,
           u.phone,
           au.email::text,
           u.date_of_birth,
           u.primary_position,
           u.secondary_position,
           u.profile_visibility,
           u.age_visible,
           u.default_wilayat_code,
           u.avatar_path,
           u.is_active,
           u.suspended_at,
           u.suspension_reason,
           exists (select 1 from system_admins sa where sa.user_id = u.id),
           coalesce(np.match_push, true),
           coalesce(np.community_push, true),
           coalesce(np.mute_all, false),
           (select coalesce(array_agg(distinct i.provider::text
                                      order by i.provider::text),
                            array[]::text[])
              from auth.identities i
             where i.user_id = u.id),
           au.email_confirmed_at,
           au.last_sign_in_at,
           u.created_at
    from users u
    join auth.users au on au.id = u.id
    left join notification_push_preferences np on np.user_id = u.id
    where u.id = p_user_id;
end;
$$;

comment on function public.admin_get_user_account(uuid) is
  'Platform Admin: one account''s data and settings -- profile, privacy, '
  'Default Location, suspension state, push preferences (column defaults when '
  'the account has no row) and, from auth, the email, its confirmation time, '
  'the last sign-in and the NAMES of the sign-in providers. One row per '
  'account. Gated on is_system_admin(); USER_NOT_FOUND for an unknown id. '
  'Writes nothing; no self or System Admin restriction on reading. Migration '
  '0095.';

revoke execute on function public.admin_get_user_account(uuid)
  from anon, public;
grant execute on function public.admin_get_user_account(uuid) to authenticated;
grant execute on function public.admin_get_user_account(uuid) to service_role;



-- ============================================================================
-- 3) admin_update_user_account() -- full name and phone
-- ============================================================================
-- The audit label is the name **after** the update, because it is the identity
-- the account carries from now on; the other four write RPCs do not touch the
-- name, so for them the locked row's name is the same thing.
create or replace function public.admin_update_user_account(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_name text := btrim(coalesce(p_full_name, ''));
  v_phone text := btrim(coalesce(p_phone, ''));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_changed text[] := array[]::text[];
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if char_length(v_name) < 2 then
    raise exception 'INVALID_FULL_NAME';
  end if;
  if v_phone !~ '^\+968[0-9]{8}$' then
    raise exception 'INVALID_PHONE';
  end if;

  if v_name is distinct from v_user.full_name then
    v_changed := array_append(v_changed, 'full_name');
  end if;
  if v_phone is distinct from v_user.phone then
    v_changed := array_append(v_changed, 'phone');
  end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  update users set
    full_name = v_name,
    phone     = v_phone
  where id = p_user_id;

  perform record_admin_audit(
    'USER_PROFILE_UPDATED',
    'USER',
    p_user_id,
    v_name,
    v_reason,
    jsonb_build_object('changed_fields', to_jsonb(v_changed))
  );
end;
$$;

comment on function public.admin_update_user_account(uuid, text, text, text) is
  'Platform Admin: sets an account''s full name and phone as one group. System '
  'Admin only; refuses the caller (CANNOT_MODIFY_SELF) and any System Admin '
  '(CANNOT_MODIFY_SYSTEM_ADMIN). Unchanged values are a no-op: no UPDATE and no '
  'audit event. Otherwise one USER_PROFILE_UPDATED event whose metadata is '
  'changed_fields only. Migration 0095.';

revoke execute on function public.admin_update_user_account(uuid, text, text, text)
  from anon, public;
grant execute on function public.admin_update_user_account(uuid, text, text, text)
  to authenticated;
grant execute on function public.admin_update_user_account(uuid, text, text, text)
  to service_role;



-- ============================================================================
-- 4) admin_update_user_player_profile() -- date of birth and positions
-- ============================================================================
-- Null date of birth and null secondary position both clear the column; the
-- primary position is required. "Today" is today in Oman and only that, the
-- calendar `complete_my_player_profile` (`0092`) uses, with no slack.
create or replace function public.admin_update_user_player_profile(
  p_user_id uuid,
  p_date_of_birth date,
  p_primary_position text,
  p_secondary_position text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_primary text := btrim(coalesce(p_primary_position, ''));
  v_secondary text := nullif(btrim(coalesce(p_secondary_position, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_today date := (now() at time zone 'Asia/Muscat')::date;
  v_changed text[] := array[]::text[];
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_date_of_birth is not null
     and (p_date_of_birth < date '1900-01-01' or p_date_of_birth > v_today) then
    raise exception 'INVALID_DATE_OF_BIRTH';
  end if;
  if v_primary not in ('GK', 'DEF', 'MID', 'FWD') then
    raise exception 'INVALID_POSITION';
  end if;
  if v_secondary is not null
     and (v_secondary not in ('GK', 'DEF', 'MID', 'FWD')
          or v_secondary = v_primary) then
    raise exception 'INVALID_POSITION';
  end if;

  if p_date_of_birth is distinct from v_user.date_of_birth then
    v_changed := array_append(v_changed, 'date_of_birth');
  end if;
  if v_primary is distinct from v_user.primary_position then
    v_changed := array_append(v_changed, 'primary_position');
  end if;
  if v_secondary is distinct from v_user.secondary_position then
    v_changed := array_append(v_changed, 'secondary_position');
  end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  update users set
    date_of_birth      = p_date_of_birth,
    primary_position   = v_primary,
    secondary_position = v_secondary
  where id = p_user_id;

  perform record_admin_audit(
    'USER_PROFILE_UPDATED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_reason,
    jsonb_build_object('changed_fields', to_jsonb(v_changed))
  );
end;
$$;

comment on function public.admin_update_user_player_profile(uuid, date, text, text, text) is
  'Platform Admin: sets an account''s date of birth and primary and secondary '
  'positions as one group. A null date of birth or secondary position clears '
  'it; the primary is required. System Admin only; refuses the caller and any '
  'System Admin. Unchanged values are a no-op: no UPDATE and no audit event. '
  'Otherwise one USER_PROFILE_UPDATED event whose metadata is changed_fields '
  'only. Migration 0095.';

revoke execute on function public.admin_update_user_player_profile(uuid, date, text, text, text)
  from anon, public;
grant execute on function public.admin_update_user_player_profile(uuid, date, text, text, text)
  to authenticated;
grant execute on function public.admin_update_user_player_profile(uuid, date, text, text, text)
  to service_role;



-- ============================================================================
-- 5) admin_update_user_privacy() -- visibility and age visibility
-- ============================================================================
-- Both arguments are required. The visibility is matched against the two tokens
-- exactly, as `users_profile_visibility_check` (`0043`) does, so a value the
-- column would refuse is refused here with a code rather than as a constraint
-- violation.
create or replace function public.admin_update_user_privacy(
  p_user_id uuid,
  p_profile_visibility text,
  p_age_visible boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_changed text[] := array[]::text[];
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_profile_visibility is null
     or p_profile_visibility not in ('EVERYONE', 'COMMUNITY_MEMBERS')
     or p_age_visible is null then
    raise exception 'INVALID_SETTINGS';
  end if;

  if p_profile_visibility is distinct from v_user.profile_visibility then
    v_changed := array_append(v_changed, 'profile_visibility');
  end if;
  if p_age_visible is distinct from v_user.age_visible then
    v_changed := array_append(v_changed, 'age_visible');
  end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  update users set
    profile_visibility = p_profile_visibility,
    age_visible        = p_age_visible
  where id = p_user_id;

  perform record_admin_audit(
    'USER_PROFILE_UPDATED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_reason,
    jsonb_build_object('changed_fields', to_jsonb(v_changed))
  );
end;
$$;

comment on function public.admin_update_user_privacy(uuid, text, boolean, text) is
  'Platform Admin: sets an account''s profile visibility (EVERYONE or '
  'COMMUNITY_MEMBERS) and age visibility as one group; a null or unknown value '
  'is INVALID_SETTINGS. System Admin only; refuses the caller and any System '
  'Admin. Unchanged values are a no-op: no UPDATE and no audit event. Otherwise '
  'one USER_PROFILE_UPDATED event whose metadata is changed_fields only. '
  'Migration 0095.';

revoke execute on function public.admin_update_user_privacy(uuid, text, boolean, text)
  from anon, public;
grant execute on function public.admin_update_user_privacy(uuid, text, boolean, text)
  to authenticated;
grant execute on function public.admin_update_user_privacy(uuid, text, boolean, text)
  to service_role;



-- ============================================================================
-- 6) admin_update_user_default_wilayat() -- the Default Location
-- ============================================================================
-- Null clears it. A code must exist in `wilayats`; whether it is still offered
-- for new choices (`is_active`) is not asked, because the owner's own write is a
-- plain foreign key and an account must stay editable if its Wilayat is retired.
create or replace function public.admin_update_user_default_wilayat(
  p_user_id uuid,
  p_wilayat_code smallint,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_wilayat_code is not null
     and not exists (select 1 from wilayats w where w.code = p_wilayat_code) then
    raise exception 'INVALID_WILAYAT';
  end if;

  if p_wilayat_code is not distinct from v_user.default_wilayat_code then
    return;
  end if;

  update users set default_wilayat_code = p_wilayat_code where id = p_user_id;

  perform record_admin_audit(
    'USER_PROFILE_UPDATED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_reason,
    jsonb_build_object(
      'changed_fields', to_jsonb(array['default_wilayat_code']::text[])
    )
  );
end;
$$;

comment on function public.admin_update_user_default_wilayat(uuid, smallint, text) is
  'Platform Admin: sets or clears (null) an account''s Default Location. The '
  'code must exist in wilayats (INVALID_WILAYAT). System Admin only; refuses the '
  'caller and any System Admin. An unchanged value is a no-op: no UPDATE and no '
  'audit event. Otherwise one USER_PROFILE_UPDATED event whose metadata is '
  'changed_fields only. Migration 0095.';

revoke execute on function public.admin_update_user_default_wilayat(uuid, smallint, text)
  from anon, public;
grant execute on function public.admin_update_user_default_wilayat(uuid, smallint, text)
  to authenticated;
grant execute on function public.admin_update_user_default_wilayat(uuid, smallint, text)
  to service_role;



-- ============================================================================
-- 7) admin_update_user_push_preferences() -- the three push switches
-- ============================================================================
-- All three are required. An account with no preferences row is compared
-- against the column defaults of `0036` (`true`, `true`, `false`) -- the same
-- values `admin_get_user_account` shows for it -- so asking for exactly those
-- creates no row and no audit event. Anything else is an upsert, which is also
-- how a row comes to exist; `on conflict` keeps it safe against a player saving
-- their own preferences at the same moment.
create or replace function public.admin_update_user_push_preferences(
  p_user_id uuid,
  p_match_push boolean,
  p_community_push boolean,
  p_mute_all boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_prefs notification_push_preferences%rowtype;
  v_has_row boolean;
  v_current_match boolean;
  v_current_community boolean;
  v_current_mute boolean;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_changed text[] := array[]::text[];
begin
  if not is_system_admin() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select * into v_user from users u where u.id = p_user_id for update;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_match_push is null or p_community_push is null or p_mute_all is null then
    raise exception 'INVALID_SETTINGS';
  end if;

  select * into v_prefs
    from notification_push_preferences np
   where np.user_id = p_user_id
   for update;
  v_has_row := found;

  -- The effective values: the row's, or the column defaults when there is none.
  v_current_match     := case when v_has_row then v_prefs.match_push else true end;
  v_current_community := case when v_has_row then v_prefs.community_push else true end;
  v_current_mute      := case when v_has_row then v_prefs.mute_all else false end;

  if p_match_push is distinct from v_current_match then
    v_changed := array_append(v_changed, 'match_push');
  end if;
  if p_community_push is distinct from v_current_community then
    v_changed := array_append(v_changed, 'community_push');
  end if;
  if p_mute_all is distinct from v_current_mute then
    v_changed := array_append(v_changed, 'mute_all');
  end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  insert into notification_push_preferences (
    user_id, match_push, community_push, mute_all
  )
  values (p_user_id, p_match_push, p_community_push, p_mute_all)
  on conflict (user_id) do update set
    match_push     = excluded.match_push,
    community_push = excluded.community_push,
    mute_all       = excluded.mute_all;

  perform record_admin_audit(
    'USER_PROFILE_UPDATED',
    'USER',
    p_user_id,
    v_user.full_name,
    v_reason,
    jsonb_build_object('changed_fields', to_jsonb(v_changed))
  );
end;
$$;

comment on function public.admin_update_user_push_preferences(uuid, boolean, boolean, boolean, text) is
  'Platform Admin: sets an account''s three push switches as one group; a null '
  'is INVALID_SETTINGS. An account with no preferences row is compared against '
  'the column defaults (true, true, false), so asking for those is a no-op. '
  'System Admin only; refuses the caller and any System Admin. Otherwise an '
  'upsert and one USER_PROFILE_UPDATED event whose metadata is changed_fields '
  'only. Migration 0095.';

revoke execute on function public.admin_update_user_push_preferences(uuid, boolean, boolean, boolean, text)
  from anon, public;
grant execute on function public.admin_update_user_push_preferences(uuid, boolean, boolean, boolean, text)
  to authenticated;
grant execute on function public.admin_update_user_push_preferences(uuid, boolean, boolean, boolean, text)
  to service_role;



-- ============================================================================
-- 8) What this migration did not touch
-- ============================================================================
--   * `is_system_admin`, `record_admin_audit` (`0062`), `admin_suspend_user`,
--     `admin_reactivate_user` (`0064`), `admin_list_users` (`0066`),
--     `admin_list_audit_log` (`0068`) and every other existing function --
--     unchanged in body and in privilege. In particular `admin_list_audit_log`
--     still withholds `metadata`, so the console shows the new action's label
--     and not its field names;
--   * every RLS policy, every column grant on `users`, and the privileges on
--     `admin_audit_log` and `notification_push_preferences`;
--   * `auth` and `storage`: read in section 2, written nowhere;
--   * `users.avatar_path`: returned for display only; there is no write;
--   * `setup_all.sql` -- not kept in step with recent migrations, as before.
