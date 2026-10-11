-- == rollback/0096_platform_admin_account_preflight_rollback.sql ==
-- Puts the database back to what it was before `0096`: the three preflight
-- functions gone.
--
-- **This rollback loses no data and cannot.** `0096` created three functions and
-- nothing else -- no table, column, index, policy, grant on an existing object, or
-- row -- and the functions it created write nothing. So there is nothing to
-- guard, nothing to export first, and no audit row, because a preview never wrote
-- one.
--
-- Roll the client back first (or with this): the current client calls
-- `admin_preview_account_merge` and `admin_preview_account_deletion` from the
-- merge and deletion preview screens, and shows "Failed to load data." with a
-- retry once they are gone. The previous client never called them.
--
-- The two previews are dropped before the helper they call. `if exists` makes the
-- script safe to run again.

drop function if exists public.admin_preview_account_merge(uuid, uuid);

drop function if exists public.admin_preview_account_deletion(uuid);

drop function if exists public.admin_preview_account_snapshot(uuid);
