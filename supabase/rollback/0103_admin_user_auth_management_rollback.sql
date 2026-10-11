-- == rollback/0103_admin_user_auth_management_rollback.sql ==
-- Puts the database back to what it was before 0103: the five functions gone and the audit action list
-- back to the seven it held after 0102.
--
-- **It refuses once an event of the three new kinds exists.** The audit log is append-only, and the
-- CHECK cannot be put back over rows that its list no longer allows; deleting those rows would erase
-- the administrative record of what was done to an account's sign-in. With none, it loses nothing:
-- 0103 added functions and widened a list.
--
-- Roll the client and the Edge Function back with it: the current client's account screen calls the
-- `admin-user-auth` function, which calls these functions. Remove the function with
-- `supabase functions delete admin-user-auth`.
--
-- Safe to run again.

do $$
begin
  if exists (select 1 from public.admin_audit_log
              where action in ('USER_EMAIL_CHANGED', 'USER_RECOVERY_SENT', 'USER_PASSWORD_SET')) then
    raise exception 'ROLLBACK_REFUSED_AUTH_EVENTS_EXIST';
  end if;
end
$$;

drop function if exists public.admin_record_user_password_set(uuid, text);
drop function if exists public.admin_record_user_recovery_sent(uuid, text, boolean);
drop function if exists public.admin_record_user_email_changed(uuid, text);
drop function if exists public.admin_check_user_auth_action(uuid, text, text);
drop function if exists public.admin_user_auth_guard(uuid);

-- the list as 0102 left it
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
