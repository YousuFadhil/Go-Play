-- ============ migrations/0042_match_membership_context.sql ============
-- Why a match would not load, when the reason is membership.
--
-- `matches_select_community_members` (migration `0007`) filters a match out of
-- every read for anybody who is not in its community. That is correct and is
-- **not changed here**: a non-member still receives no row, no roster, no
-- location, no time and no title. What was missing is the ability to tell the
-- two silences apart — a match that is not there, and a match that is there but
-- is not the caller's to read — so the application reported both as "failed to
-- load data".
--
-- This adds one read-only function that answers exactly that question and
-- nothing else. It is deliberately narrower than the public discovery views
-- migration `0033` already grants to every session:
--
--   * the community's id and name. `v_public_communities` publishes both to
--     `anon`, so naming the community a match belongs to reveals nothing that a
--     signed-out visitor cannot already list.
--   * its join policy, which `v_public_communities` implies by listing every
--     community as joinable-with-or-without-a-code, and which the join flow
--     needs so a CODE_REQUIRED community asks for its code rather than making a
--     round trip that is certain to be refused.
--   * whether the caller is a member, which is a fact about the caller.
--
-- Deliberately absent: the match's title, location, schedule, capacity, status,
-- creator and roster. Every one of those stays behind the policy. `match_exists`
-- is a boolean and not a row, so a caller learns that an id names something and
-- learns nothing about what.
--
-- Idempotent: `create or replace`, then the usual revoke/grant pair.

create or replace function public.match_membership_context(p_match_id uuid)
returns table (
  match_exists boolean,
  community_id uuid,
  community_name text,
  join_policy text,
  is_member boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_community communities%rowtype;
begin
  -- A session is required. This function exists to help a signed-in user who is
  -- not a member of one community; it is not a lookup service for the world.
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select c.* into v_community
  from matches m
  join communities c on c.id = m.community_id
  where m.id = p_match_id;

  if not found then
    return query select false, null::uuid, null::text, null::text, false;
    return;
  end if;

  return query select
    true,
    v_community.id,
    v_community.name,
    v_community.join_policy,
    is_community_member(v_community.id, auth.uid());
end;
$$;

comment on function public.match_membership_context(uuid) is
  'Why a match did not load: whether the id names one, which community it '
  'belongs to, and whether the caller is in it. Carries no match data -- see '
  'migration 0042.';

revoke execute on function public.match_membership_context(uuid)
  from anon, public;
grant execute on function public.match_membership_context(uuid)
  to authenticated;
