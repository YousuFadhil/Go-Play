-- Visibility and joining were the same switch; they are two questions.
--
-- `is_private` hid a community from discovery *and* forced the join code. From
-- here a community is always visible, and the only setting is how someone is
-- allowed to join:
--
--   OPEN           anyone who can see it can join it
--   CODE_REQUIRED  joining needs the join code
--
-- The invitation link is unchanged and keeps working under both: it carries the
-- join code, and join_community_by_code accepts it either way. That is the point
-- of a code — it is the credential, not the policy.
--
-- This reverses DD-11 (private by default). Communities that were private become
-- CODE_REQUIRED, which preserves how people join them but not their obscurity:
-- their names and descriptions are now visible to every signed-in user. That is
-- the approved intent of "do not hide communities from discovery", and it is the
-- one user-visible consequence worth naming.

-- 1) The setting ---------------------------------------------------------------
alter table public.communities
  add column if not exists join_policy text not null default 'OPEN';

update public.communities
set join_policy = case when is_private then 'CODE_REQUIRED' else 'OPEN' end;

alter table public.communities
  drop constraint if exists communities_join_policy_check;
alter table public.communities
  add constraint communities_join_policy_check
  check (join_policy in ('OPEN', 'CODE_REQUIRED'));

-- 2) Everything is visible -----------------------------------------------------
-- The policy no longer asks whether the caller is a member: an inactive
-- community is still hidden, and nothing else is.
drop policy if exists "communities_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (is_active);

-- 3) is_private has no meaning left --------------------------------------------
-- Dropped rather than left behind: a column that no policy reads and no screen
-- writes is a trap for whoever reads this schema next.
alter table public.communities drop column if exists is_private;

-- 4) Joining -------------------------------------------------------------------
-- OPEN only. CODE_REQUIRED keeps its name honest: the code is the way in, and
-- this function refuses without it rather than quietly accepting.
create or replace function public.join_community(p_community_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select join_policy into v_policy
  from communities
  where id = p_community_id and is_active;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;
  if v_policy <> 'OPEN' then
    raise exception 'JOIN_CODE_REQUIRED';
  end if;
  if is_community_member(p_community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (p_community_id, auth.uid(), 'player');

  return p_community_id;
end;
$$;

revoke execute on function public.join_community(uuid) from anon, public;
grant execute on function public.join_community(uuid) to authenticated;

-- 5) Creating a community ------------------------------------------------------
-- Same shape as before, one argument renamed. The old signature is dropped so
-- there is no stale overload for a client to reach.
drop function if exists public.create_community(text, text, boolean);

create or replace function public.create_community(
  p_name text,
  p_description text,
  p_join_policy text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_join_policy not in ('OPEN', 'CODE_REQUIRED') then
    raise exception 'INVALID_JOIN_POLICY';
  end if;

  insert into communities (owner_id, name, description, join_policy)
  values (auth.uid(), p_name, p_description, p_join_policy)
  returning id into v_id;

  insert into community_members (community_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

revoke execute on function public.create_community(text, text, text)
  from anon, public;
grant execute on function public.create_community(text, text, text)
  to authenticated;

-- 6) The invitation preview ----------------------------------------------------
-- Unchanged behaviour; it never read is_private.
