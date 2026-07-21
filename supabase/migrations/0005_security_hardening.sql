-- Security hardening (from Supabase security advisor):
-- 1. Pin search_path on the trigger helper.
alter function public.set_updated_at() set search_path = public;

-- 2. handle_new_user is a trigger-only function; it must not be callable
--    through the API by any role.
revoke execute on function public.handle_new_user()
  from anon, authenticated, public;

-- 3. Membership helpers: needed by RLS policy evaluation for signed-in
--    users, but anon has no policies referencing them and should not be
--    able to probe membership.
revoke execute on function public.is_group_member(uuid, uuid)
  from anon, public;
revoke execute on function public.is_match_group_member(uuid, uuid)
  from anon, public;
grant execute on function public.is_group_member(uuid, uuid)
  to authenticated;
grant execute on function public.is_match_group_member(uuid, uuid)
  to authenticated;
