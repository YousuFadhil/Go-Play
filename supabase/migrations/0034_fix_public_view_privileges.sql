-- ============ migrations/0034_fix_public_view_privileges.sql ============
-- Sprint 1 follow-up: the repository catches up with production.
--
-- This migration adds no behaviour and no functionality. It exists because the
-- statements below were run directly against the project during the
-- verification of `0033`, and a fix that lives only in production is a fix that
-- the next environment does not get.
--
-- WHAT WENT WRONG
--
-- `0033` asks for exactly one privilege on its two read models:
--
--     grant select on public.v_public_communities      to anon, authenticated;
--     grant select on public.v_public_upcoming_matches to anon, authenticated;
--
-- It got seven. Supabase ships a default-privileges rule on schema `public`
-- that grants ALL on every newly created table or view to `anon` and
-- `authenticated`, and that rule fires before this migration's own grant is
-- reached. Both views therefore arrived carrying INSERT, UPDATE, DELETE,
-- TRUNCATE, REFERENCES and TRIGGER as well.
--
-- On an ordinary view that would be untidy. On these two it was a hole.
-- `v_public_communities` selects from a single table, which makes it
-- auto-updatable: Postgres will rewrite a DELETE against the view into a DELETE
-- against `public.communities`. And because the view is deliberately NOT
-- `security_invoker` -- the very property that lets a signed-out visitor read it
-- -- that rewritten statement runs with the view owner's privileges and does not
-- consult the policies on `communities` at all.
--
-- The two facts together meant an anonymous caller holding nothing but the
-- publishable key could delete or rename every community through
-- `/rest/v1/v_public_communities`. Verified against the project, inside a
-- transaction that was rolled back: DELETE was accepted, and UPDATE reached the
-- table and was stopped only by the `name` length CHECK.
--
-- WHAT THIS DOES
--
-- Takes those six privileges back, on both views, from both roles. SELECT is
-- untouched, so what a guest may read is exactly what `0033` intended and the
-- Discover screen is unaffected. Every statement is a REVOKE and REVOKE is
-- idempotent, so this is safe to re-run and is already a no-op against the
-- production project, where it has been applied.
--
-- NOT FIXED HERE, ON PURPOSE
--
-- The default-privileges rule itself is untouched. Changing it would alter how
-- every future object in `public` is created, which is a schema-wide decision
-- and not one to make inside a follow-up whose whole point is to change
-- nothing. What this does mean is that the next non-`security_invoker` view
-- added to this schema will arrive with the same seven privileges, and will
-- need the same revoke beside it. That is worth a backlog item rather than a
-- silent assumption.

revoke insert, update, delete, truncate, references, trigger
  on public.v_public_communities
  from anon, authenticated;

revoke insert, update, delete, truncate, references, trigger
  on public.v_public_upcoming_matches
  from anon, authenticated;
