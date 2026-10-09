-- ===== migrations/0098_harden_is_system_admin_search_path.sql =====
-- Security-only hardening of the existing System Admin predicate (0017).
--
-- LIVE BASELINE (read-only audit, 2026-10-09):
--   public.is_system_admin() is postgres-owned, STABLE, SECURITY DEFINER,
--   with search_path=public, an unqualified system_admins relation, and
--   EXECUTE for authenticated and service_role (not anon or PUBLIC).
--
-- In SECURITY DEFINER code an implicit pg_temp schema can take precedence for
-- relation resolution even with search_path=public. A caller able to create a
-- temporary system_admins table can therefore spoof the legacy predicate.
--
-- Preserve function name/signature, BOOLEAN result, SQL language, STABLE,
-- SECURITY DEFINER, owner and current EXECUTE roles. Fully qualify the table
-- and auth.uid(), and use an empty search_path so neither caller nor temporary
-- schemas can change what is checked.
--
-- CREATE OR REPLACE avoids DROP FUNCTION and preserves OID/owner/dependencies.
-- Does not alter any application data, table, policy, or other RPC.
-- Reapply is safe. Review/approve separately before running against live DB.
--
-- IMPORTANT: This migration is independent of 0097 (WhatsApp support), which
-- remains unapplied in production; do not deploy all pending migrations as a
-- batch without separate Product Owner authorization.

create or replace function public.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.system_admins sa
    where sa.user_id = auth.uid()
  );
$$;

-- Reassert the existing production EXECUTE contract without widening it.
-- CREATE OR REPLACE preserves the current ACL; these operations are idempotent.
revoke execute on function public.is_system_admin() from public, anon;
grant execute on function public.is_system_admin()
  to authenticated, service_role;
