-- ============ migrations/0066_platform_admin_suspension_read_model.sql ============
-- Platform Admin: suspension state, visible to the Admin lists.
--
-- `0062`-`0065` gave the database everything it needs to suspend a user or a
-- community and to refuse what a suspension forbids. What they did not do is
-- let an administrator *see* the state they are administering: `admin_list_users`
-- and `admin_list_communities` (`0017`) return no `is_active`, so the console
-- cannot tell an active account from a suspended one and cannot decide whether
-- to offer Suspend or Reactivate.
--
-- This migration closes exactly that gap. It is a **read-model change only**:
--
--   * no suspension is performed and no suspension write is added;
--   * no policy, view, storage rule or read model outside these two functions
--     is touched;
--   * `admin_list_matches`, the four `admin_suspend_*` / `admin_reactivate_*`
--     RPCs, the `admin_delete_*` RPCs and `admin_audit_log` are all unchanged;
--   * there is no DML, no backfill and no data migration of any kind.
--
-- ## WHY DROP AND CREATE
--
-- Both functions gain columns, and PostgreSQL refuses to change the return type
-- of an existing function through `create or replace` -- "cannot change return
-- type of existing function". So each is dropped and recreated, which is the
-- same device `0056` used on `player_profile` for the same reason.
--
-- **Dropping a function drops its whole ACL, including grants no migration
-- ever wrote.** That is the trap here, and it is `0034`'s hazard pointing the
-- other way. `0017` granted only `authenticated` on these two functions, so
-- reading the migrations suggests `authenticated` is all there is to restore.
-- It is not: Supabase's default-privileges rule on schema `public` also grants
-- `service_role` on every function created there, and `0017`'s `revoke ... from
-- anon, public` never touched it. The live ACL is therefore
--
--     postgres  |  authenticated  |  service_role
--
-- and restoring only `authenticated` would silently take `service_role`'s
-- EXECUTE away. Both are re-granted below by name, and `anon` and `PUBLIC` stay
-- revoked, so the privilege state after this migration is exactly the state
-- before it.
--
-- ## WHAT IS APPENDED
--
-- Three columns on each, and they are **appended** rather than woven in, so
-- every existing column keeps its position and any caller reading by index is
-- unaffected:
--
--     is_active           boolean
--     suspended_at        timestamptz
--     suspension_reason   text
--
-- `suspended_by` is deliberately **not** exposed. A list needs to show that an
-- account is suspended and why; which administrator did it is audit-log
-- material, and the audit log has its own gated read path in a later cycle.
--
-- `phone` stays in `admin_list_users`. It is not needed by this cycle and
-- removing it would be a privacy change to a surface nobody asked me to touch;
-- narrowing the Admin list projection is its own decision, deferred.
--
-- Everything else about both functions is reproduced exactly: the same search
-- semantics, the same ordering, the same `limit 100`, the same
-- `security definer` / `stable` / `set search_path = public`, and the same
-- `is_system_admin()` gate as the first statement.



-- ============================================================================
-- 1) admin_list_users
-- ============================================================================
-- `0017`'s function, with three columns appended. The join to `auth.users` for
-- the email is unchanged and legitimate for the same reason it always was: a
-- `security definer` function runs as its owner.
drop function if exists public.admin_list_users(text);

create function public.admin_list_users(p_search text default null)
returns table (
  id uuid,
  full_name text,
  phone text,
  email text,
  created_at timestamptz,
  is_system_admin boolean,
  is_active boolean,
  suspended_at timestamptz,
  suspension_reason text
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select u.id, u.full_name, u.phone, au.email::text, u.created_at,
           exists (select 1 from system_admins sa where sa.user_id = u.id),
           u.is_active, u.suspended_at, u.suspension_reason
    from users u
    join auth.users au on au.id = u.id
    where p_search is null or trim(p_search) = ''
       or u.full_name ilike '%' || trim(p_search) || '%'
       or au.email::text ilike '%' || trim(p_search) || '%'
    order by u.created_at desc
    limit 100;
end;
$$;

comment on function public.admin_list_users(text) is
  'Platform Admin: accounts, searchable by name or email, newest first, capped '
  'at 100. Gated on is_system_admin(). Carries the suspension state -- '
  'is_active, suspended_at, suspension_reason -- so the console can tell an '
  'active account from a suspended one; suspended_by is deliberately absent '
  'and belongs to the audit log (migration 0066).';

-- Re-established because `drop function` took the old ones with it. Both
-- executing roles are named: `authenticated` is the console, `service_role` is
-- the privilege the platform's default rule granted and `0017` never mentioned.
-- `anon` and `PUBLIC` are revoked and are granted nothing.
revoke execute on function public.admin_list_users(text) from anon, public;
grant execute on function public.admin_list_users(text) to authenticated;
grant execute on function public.admin_list_users(text) to service_role;



-- ============================================================================
-- 2) admin_list_communities
-- ============================================================================
-- `0017`'s function, with the same three columns appended. The member and match
-- counts stay scalar subqueries and stay `bigint`; the owner join stays LEFT,
-- so a community whose owner row is gone still lists.
drop function if exists public.admin_list_communities(text);

create function public.admin_list_communities(p_search text default null)
returns table (
  id uuid,
  name text,
  join_policy text,
  created_at timestamptz,
  owner_name text,
  member_count bigint,
  match_count bigint,
  is_active boolean,
  suspended_at timestamptz,
  suspension_reason text
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select c.id, c.name, c.join_policy, c.created_at, o.full_name,
           (select count(*) from community_members cm where cm.community_id = c.id),
           (select count(*) from matches m where m.community_id = c.id),
           c.is_active, c.suspended_at, c.suspension_reason
    from communities c
    left join users o on o.id = c.owner_id
    where p_search is null or trim(p_search) = ''
       or c.name ilike '%' || trim(p_search) || '%'
    order by c.created_at desc
    limit 100;
end;
$$;

comment on function public.admin_list_communities(text) is
  'Platform Admin: communities, searchable by name, newest first, capped at '
  '100, with member and match counts. Gated on is_system_admin(). Carries the '
  'suspension state -- is_active, suspended_at, suspension_reason; '
  'suspended_by is deliberately absent and belongs to the audit log '
  '(migration 0066).';

-- The same two roles, for the same reason as above.
revoke execute on function public.admin_list_communities(text) from anon, public;
grant execute on function public.admin_list_communities(text) to authenticated;
grant execute on function public.admin_list_communities(text) to service_role;



-- ============================================================================
-- 3) What this migration did not touch
-- ============================================================================
--   * `admin_list_matches` (`0017`) -- unchanged, still read-only inspection;
--   * `admin_suspend_user`, `admin_reactivate_user` (`0064`),
--     `admin_suspend_community`, `admin_reactivate_community` (`0065`) --
--     unchanged; no suspension write is added or altered here;
--   * `admin_delete_user`, `admin_delete_community`, `admin_delete_match`
--     (`0017`) -- unchanged in definition and in privilege;
--   * `admin_audit_log` and `record_admin_audit` (`0062`) -- unchanged;
--   * every RLS policy, every Storage policy, every normal-user read model and
--     every public football view -- unchanged;
--   * `users` and `communities` themselves -- no column added, no privilege
--     changed, no row written.
