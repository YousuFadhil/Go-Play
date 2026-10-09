-- == rollback/0095_platform_admin_user_account_management_rollback.sql ==
-- Puts the database back to what it was before `0095`: the six account-management
-- functions gone, and `admin_audit_log_action_check` allowing the four actions of
-- `0062` again.
--
-- **THIS ROLLBACK NEVER DELETES AUDIT ROWS.** `admin_audit_log` is append-only, and
-- a record of what an administrator changed is not something to remove to make a
-- constraint easier to restore. So the script **stops with a clear message** if
-- any row with the action `USER_PROFILE_UPDATED` exists, and changes nothing. In
-- that case the rows are a decision for the Product Owner and the Architect --
-- export them, then decide -- and this file is not the place to make it.
--
-- Run it as one script. The guard comes first and raises, so nothing after it runs;
-- run statement by statement, the guard cannot stop the ones below it.
--
-- Roll the client back first (or with this): the current client calls these six
-- functions and fails without them. The previous client never called them, which
-- is the point of how `0095` was written -- it adds functions and widens one
-- constraint, and changes nothing a previous build reads.
--
-- **Nothing historical is edited.** `0062` stays as it was written; this file
-- restates its constraint, which is the only way a forward-only migration history
-- can be undone. No data in `users` or `notification_push_preferences` is
-- restored: edits an administrator made through these functions stand.

-- A) The guard -------------------------------------------------------------------
do $$
declare
  v_rows bigint;
begin
  select count(*) into v_rows
    from public.admin_audit_log
   where action = 'USER_PROFILE_UPDATED';

  if v_rows > 0 then
    raise exception
      'ROLLBACK_REFUSED: % admin_audit_log row(s) with action USER_PROFILE_UPDATED exist. This rollback never deletes audit rows. Nothing was changed.',
      v_rows;
  end if;
end;
$$;

-- B) The six functions ------------------------------------------------------------
drop function if exists public.admin_get_user_account(uuid);

drop function if exists public.admin_update_user_account(uuid, text, text, text);

drop function if exists public.admin_update_user_player_profile(uuid, date, text, text, text);

drop function if exists public.admin_update_user_privacy(uuid, text, boolean, text);

drop function if exists public.admin_update_user_default_wilayat(uuid, smallint, text);

drop function if exists public.admin_update_user_push_preferences(uuid, boolean, boolean, boolean, text);

-- C) The constraint ----------------------------------------------------------------
-- `0062`'s four values. Safe to add: the guard above has just established that no
-- row carries the fifth.
alter table public.admin_audit_log
  drop constraint if exists admin_audit_log_action_check;

alter table public.admin_audit_log
  add constraint admin_audit_log_action_check check (action in (
    'USER_SUSPENDED',
    'USER_REACTIVATED',
    'COMMUNITY_SUSPENDED',
    'COMMUNITY_REACTIVATED'
  ));
