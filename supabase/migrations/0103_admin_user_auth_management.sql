-- ============================================================================
-- 0103 -- Admin authentication management: what the database decides and records
-- ============================================================================
-- Three operations on ANOTHER user's sign-in, all requested through the `admin-user-auth` Edge
-- Function (the Auth Admin API needs the service role, which never leaves the server):
--
--   CHANGE_EMAIL    set the account's email, effective at once, then send the standard recovery email
--                   to the NEW address;
--   SEND_RECOVERY   send the standard recovery email to the account's CURRENT address;
--   SET_PASSWORD    set the account's password directly.
--
-- **This migration changes no credential and calls no Auth API.** Postgres cannot (and must not)
-- write `auth.users` or send mail for this. What the database is responsible for is exactly two
-- things, both done AS THE CALLER so that `auth.uid()` is the real administrator and nothing the
-- request says can name another:
--
--   1. WHETHER the act may be attempted, and on whom (`admin_check_user_auth_action`): System Admin
--      (twice), not oneself, not a System Admin, not a deleted account, and for CHANGE_EMAIL: not an
--      account with a linked Google identity, a valid address, a different one, and one nobody else
--      uses. The Edge Function asks this before the Auth call AND again immediately before it.
--   2. THAT it happened (`admin_record_user_email_changed`, `..._recovery_sent`, `..._password_set`):
--      one audit event, written after the Auth call succeeded.
--
-- ## The audit writers are action-specific, not a generic audit writer
--
-- Three functions, one per event, each fixed to its own action name and its own metadata shape. There
-- is no action parameter and no free-form metadata, so a caller cannot write any event but these three,
-- nor put anything in them. Each re-runs the whole gate (the same one as the check), so only a System
-- Admin, for a valid target that is not themselves, can write one; and the actor of the row is
-- `auth.uid()` inside `record_admin_audit` (0062) -- never a parameter.
--
-- What a System Admin could still do is write one of these three events by calling the function
-- directly, without having performed the act. That event is attributed to them, by name, and changes
-- nothing; it cannot be attributed to anyone else. The alternative (a writer only the service role may
-- call, taking the actor as a parameter) would put the actor in a request, which is the one thing the
-- design must not do.
--
-- ## Privacy (compatible with 0102)
--
--   * No event contains an email address (old or new), a password, a token or a link. The metadata is
--     a fixed set of booleans.
--   * The one snapshot an event carries is the target's NAME as `target_label_snapshot`, exactly as
--     `USER_PROFILE_UPDATED` does (0095), because the audit screen shows nothing else about the
--     target. `delete_account_core` (0102) sets that column to NULL for every entry about a deleted
--     account, and `actor_email_snapshot` for every entry by one, so neither survives an account
--     deletion. The free-text reason is kept as written, as it is for every other event.
--
-- ## What this migration is not
--
-- No table, no column, no index and no trigger. `system_admins`, `auth.*`, the other audit actions and
-- every earlier function are untouched. The audit action list gains three names and keeps every
-- existing one.
--
-- Not applied by anyone: it is applied by the owner, after review, and the Edge Function is deployed
-- afterwards.


-- ============================================================================
-- 1) The audit trail gains three events
-- ============================================================================
-- The same statement pair 0095, 0101 and 0102 used: it changes which action names are accepted and
-- nothing else. Every existing name is kept.
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
    'USER_ACCOUNT_DELETED',
    'USER_EMAIL_CHANGED',
    'USER_RECOVERY_SENT',
    'USER_PASSWORD_SET'
  ));


-- ============================================================================
-- 2) The gate every function here shares (internal: no client role can call it)
-- ============================================================================
-- Order, as in 0095: session, System Admin (the helper AND the table, so a shadowing temp table or a
-- stale helper cannot answer for the other), then the target: not the caller, not a System Admin, a live
-- account with an Auth user. A deleted account (0102 keeps an anonymised stand-in profile) is NOT FOUND.
--
-- Returns what the callers need and nothing else: the target's name (for the audit label), the current
-- email, and which providers are linked. `auth.users` and `auth.identities` are READ here; nothing in
-- them is ever written by this migration.
create or replace function public.admin_user_auth_guard(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_name text;
  v_email text;
  v_providers text[];
begin
  if v_caller is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_system_admin()
     or not exists (select 1 from public.system_admins sa
                     where sa.user_id = v_caller) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id is null then
    raise exception 'USER_NOT_FOUND';
  end if;
  if p_user_id = v_caller then
    raise exception 'CANNOT_MODIFY_SELF';
  end if;
  if exists (select 1 from public.system_admins sa where sa.user_id = p_user_id) then
    raise exception 'CANNOT_MODIFY_SYSTEM_ADMIN';
  end if;

  select u.full_name, au.email::text
    into v_name, v_email
    from public.users u
    join auth.users au on au.id = u.id
   where u.id = p_user_id
     and u.deleted_at is null
     and au.deleted_at is null;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  select coalesce(array_agg(distinct i.provider::text order by i.provider::text), array[]::text[])
    into v_providers
    from auth.identities i
   where i.user_id = p_user_id;

  return jsonb_build_object(
    'full_name', v_name,
    'email', v_email,
    'providers', to_jsonb(v_providers),
    'has_google', 'google' = any (v_providers)
  );
end;
$$;

comment on function public.admin_user_auth_guard(uuid) is
  'Admin authentication management (0103), INTERNAL: the gate shared by the check and the audit '
  'writers. System Admin (helper and table), not the caller, not a System Admin, a live account with '
  'an Auth user. Reads auth.users and auth.identities, writes nothing. Granted to no client role.';

revoke execute on function public.admin_user_auth_guard(uuid)
  from anon, authenticated, public;


-- ============================================================================
-- 3) Whether the act may be attempted -- the Edge Function asks this twice
-- ============================================================================
-- STABLE and read-only. For CHANGE_EMAIL the address is validated and normalised HERE (trimmed,
-- lower-cased) and the normalised form is what the Edge Function sends to Auth, so the database and
-- Auth see the same string.
--
-- The duplicate test looks at `auth.users.email` (case-insensitively; its unique index is
-- case-sensitive, so a mixed-case twin would otherwise get through) and at the email identities of
-- every OTHER account. It is a pre-check, not a lock: Auth's own unique index is what finally refuses a
-- race, and the Edge Function reports that as a refusal, not as a change.
--
-- The address rule is the app's own (`AuthService.isValidEmail`) plus RFC 5321's 254 characters.
create or replace function public.admin_check_user_auth_action(
  p_user_id uuid,
  p_action text,
  p_new_email text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_guard jsonb;
  v_current text;
  v_new text;
begin
  v_guard := public.admin_user_auth_guard(p_user_id);

  if p_action is null
     or p_action not in ('CHANGE_EMAIL', 'SEND_RECOVERY', 'SET_PASSWORD') then
    raise exception 'INVALID_ACTION';
  end if;

  v_current := v_guard->>'email';

  if p_action = 'SEND_RECOVERY' then
    if v_current is null or btrim(v_current) = '' then
      raise exception 'NO_EMAIL';
    end if;
  end if;

  if p_action = 'CHANGE_EMAIL' then
    -- A linked Google identity keeps the address in its own right; changing the Auth email would
    -- leave the two disagreeing, and unlinking is a separate decision this feature does not make.
    if (v_guard->>'has_google')::boolean then
      raise exception 'GOOGLE_LINKED';
    end if;

    v_new := lower(btrim(coalesce(p_new_email, '')));
    if char_length(v_new) > 254
       or v_new !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      raise exception 'INVALID_EMAIL';
    end if;
    if v_new = lower(coalesce(v_current, '')) then
      raise exception 'EMAIL_UNCHANGED';
    end if;
    if exists (select 1 from auth.users x
                where lower(x.email::text) = v_new and x.id <> p_user_id)
       or exists (select 1 from auth.identities i
                   where lower(i.email) = v_new and i.user_id <> p_user_id) then
      raise exception 'EMAIL_TAKEN';
    end if;
  end if;

  return jsonb_build_object(
    'version', 1,
    'user_id', p_user_id,
    'action', p_action,
    'current_email', v_current,
    'has_google', (v_guard->>'has_google')::boolean,
    'providers', v_guard->'providers',
    'new_email', v_new
  );
end;
$$;

comment on function public.admin_check_user_auth_action(uuid, text, text) is
  'Admin authentication management (0103): whether the signed-in System Admin may CHANGE_EMAIL, '
  'SEND_RECOVERY or SET_PASSWORD for p_user_id, and the facts the Edge Function needs (current email, '
  'the validated and normalised new email). STABLE, writes nothing, changes no credential. Refuses: '
  'NOT_AUTHENTICATED, NOT_AUTHORIZED, CANNOT_MODIFY_SELF, CANNOT_MODIFY_SYSTEM_ADMIN, USER_NOT_FOUND, '
  'INVALID_ACTION, NO_EMAIL, GOOGLE_LINKED, INVALID_EMAIL, EMAIL_UNCHANGED, EMAIL_TAKEN.';

revoke execute on function public.admin_check_user_auth_action(uuid, text, text)
  from anon, public;
grant execute on function public.admin_check_user_auth_action(uuid, text, text)
  to authenticated;


-- ============================================================================
-- 4) That it happened -- one writer per event
-- ============================================================================
-- The reason is required for every event: trimmed, not empty, at most 500 characters (INVALID_REASON).
-- The Edge Function checks the same before it touches Auth.

create or replace function public.admin_record_user_email_changed(
  p_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_guard jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_guard := public.admin_user_auth_guard(p_user_id);
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  return public.record_admin_audit(
    'USER_EMAIL_CHANGED',
    'USER',
    p_user_id,
    v_guard->>'full_name',
    v_reason,
    '{}'::jsonb
  );
end;
$$;

comment on function public.admin_record_user_email_changed(uuid, text) is
  'Admin authentication management (0103): records USER_EMAIL_CHANGED for p_user_id, attributed to '
  'auth.uid(). Same gate as admin_check_user_auth_action; reason required. Metadata is empty: no '
  'address, old or new, is ever stored. Called by admin-user-auth AFTER the Auth update succeeded.';

create or replace function public.admin_record_user_recovery_sent(
  p_user_id uuid,
  p_reason text,
  p_after_email_change boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_guard jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_guard := public.admin_user_auth_guard(p_user_id);
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  return public.record_admin_audit(
    'USER_RECOVERY_SENT',
    'USER',
    p_user_id,
    v_guard->>'full_name',
    v_reason,
    jsonb_build_object('after_email_change', coalesce(p_after_email_change, false))
  );
end;
$$;

comment on function public.admin_record_user_recovery_sent(uuid, text, boolean) is
  'Admin authentication management (0103): records USER_RECOVERY_SENT for p_user_id, attributed to '
  'auth.uid(): the provider ACCEPTED the request to send the recovery email (delivery to the inbox is '
  'not known). Same gate as admin_check_user_auth_action; reason required. Metadata: after_email_change '
  'only. Called by admin-user-auth after a successful request to the provider.';

create or replace function public.admin_record_user_password_set(
  p_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_guard jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_guard := public.admin_user_auth_guard(p_user_id);
  if v_reason is null or char_length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  return public.record_admin_audit(
    'USER_PASSWORD_SET',
    'USER',
    p_user_id,
    v_guard->>'full_name',
    v_reason,
    '{}'::jsonb
  );
end;
$$;

comment on function public.admin_record_user_password_set(uuid, text) is
  'Admin authentication management (0103): records USER_PASSWORD_SET for p_user_id, attributed to '
  'auth.uid(). Same gate as admin_check_user_auth_action; reason required. Metadata is empty: the '
  'password, its length and its hash are never stored. Called by admin-user-auth AFTER the Auth update '
  'succeeded.';

revoke execute on function public.admin_record_user_email_changed(uuid, text)
  from anon, public;
grant execute on function public.admin_record_user_email_changed(uuid, text)
  to authenticated;
revoke execute on function public.admin_record_user_recovery_sent(uuid, text, boolean)
  from anon, public;
grant execute on function public.admin_record_user_recovery_sent(uuid, text, boolean)
  to authenticated;
revoke execute on function public.admin_record_user_password_set(uuid, text)
  from anon, public;
grant execute on function public.admin_record_user_password_set(uuid, text)
  to authenticated;
