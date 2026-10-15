-- ============================================================================
-- 0106 -- The three legacy hard-delete RPCs are closed in the repository too
-- ============================================================================
-- `admin_delete_user`, `admin_delete_community` and `admin_delete_match`
-- (0017) hard-delete, and in doing so erase football history that other people
-- share. Nothing in the application calls them: the console's permanent actions
-- are `admin_merge_accounts` (0101) and `admin_delete_account` (0102), which
-- keep that history. 0017 granted the three to `authenticated`, guarded inside
-- by `is_system_admin()`.
--
-- On the live database that grant is already gone: on 2026-10-15 EXECUTE was
-- held by `postgres` and `service_role` only. It was removed outside the
-- migrations, so the repository still said the opposite, and a database built
-- from these files would have reopened them to every signed-in client.
--
-- This migration writes the live state down. Against the live database it
-- changes nothing; against a database built from the files it closes the three.
-- The functions themselves, their bodies and the `service_role` grant are left
-- exactly as they are (Product Owner, 2026-10-15): removing them is a separate
-- decision.
-- ============================================================================

revoke execute on function public.admin_delete_user(uuid) from authenticated;
revoke execute on function public.admin_delete_community(uuid) from authenticated;
revoke execute on function public.admin_delete_match(uuid) from authenticated;
