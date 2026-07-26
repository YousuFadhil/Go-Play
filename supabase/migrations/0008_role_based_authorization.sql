-- Phase 3 (AMS v1.2): authorization moves onto community_members.role.
--
-- has_community_role is the only authorization predicate from here on.
-- owner_id and created_by are never read to grant or deny anything: owner_id
-- is reporting only (PD-15) and created_by is audit metadata (PD-16).
--
-- Approved behaviour changes (PD-05, PD-06, PD-07):
--   * community settings: owner only, now resolved by role instead of owner_id
--   * create / edit / delete a match, and remove a player from one:
--     owner + admin, instead of whoever created the match
--
-- Roles are cumulative (PD-01): owner >= admin >= player.

-- 1) The authorization primitive ----------------------------------------------
create or replace function public.has_community_role(
  p_community_id uuid,
  p_user_id uuid,
  p_min_role text
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from community_members cm
    where cm.community_id = p_community_id
      and cm.user_id = p_user_id
      and case cm.role when 'owner' then 3 when 'admin' then 2 else 1 end
          >= case p_min_role when 'owner' then 3 when 'admin' then 2 else 1 end
  );
$$;

-- Membership is simply the lowest role, so it delegates rather than repeating
-- the lookup: one predicate, one place to get it wrong.
create or replace function public.is_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_community_role(p_community_id, p_user_id, 'player');
$$;

revoke execute on function public.has_community_role(uuid, uuid, text)
  from anon, public;
grant execute on function public.has_community_role(uuid, uuid, text)
  to authenticated;

-- 2) Policies -----------------------------------------------------------------
-- Visibility is unchanged (PD-14); the owner_id branch is dropped because the
-- owner is always a member, so the rule it expressed is already covered.
drop policy if exists "communities_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (
    is_active
    and (
      not is_private
      or public.is_community_member(id, auth.uid())
    )
  );

-- Settings stay owner-only (PD-05); the source of that fact changes.
drop policy if exists "communities_update_owner" on public.communities;
create policy "communities_update_owner"
  on public.communities
  for update
  to authenticated
  using (public.has_community_role(id, auth.uid(), 'owner'))
  with check (public.has_community_role(id, auth.uid(), 'owner'));

-- Match creation narrows from any member to owner + admin (PD-06).
-- created_by must still be the caller: that keeps the audit field honest, it
-- is not what grants the insert.
drop policy if exists "matches_insert_community_members" on public.matches;
create policy "matches_insert_community_admins"
  on public.matches
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.has_community_role(community_id, auth.uid(), 'admin')
  );

-- Editing a match is no longer the creator's privilege (PD-07).
drop policy if exists "matches_update_creator" on public.matches;
create policy "matches_update_community_admins"
  on public.matches
  for update
  to authenticated
  using (public.has_community_role(community_id, auth.uid(), 'admin'))
  with check (public.has_community_role(community_id, auth.uid(), 'admin'));

-- Admins may leave too; an owner must hand the community over first (PD-12).
drop policy if exists "community_members_delete_self" on public.community_members;
create policy "community_members_delete_self"
  on public.community_members
  for delete
  to authenticated
  using (user_id = auth.uid() and role <> 'owner');

-- 3) Invitations ---------------------------------------------------------------
create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null
    references public.communities (id) on delete cascade,
  invited_by uuid not null references public.users (id),
  invitee_id uuid not null references public.users (id) on delete cascade,
  -- An invitation can never confer ownership; that only moves by transfer.
  role text not null check (role in ('admin', 'player')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default now() + interval '14 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- At most one live invitation per person per community.
create unique index if not exists invitations_one_pending_idx
  on public.invitations (community_id, invitee_id)
  where status = 'pending';
create index if not exists invitations_invitee_idx
  on public.invitations (invitee_id, status);

drop trigger if exists invitations_set_updated_at on public.invitations;
create trigger invitations_set_updated_at
  before update on public.invitations
  for each row execute function public.set_updated_at();

alter table public.invitations enable row level security;

drop policy if exists "invitations_select_visible" on public.invitations;
create policy "invitations_select_visible"
  on public.invitations
  for select
  to authenticated
  using (
    invitee_id = auth.uid()
    or public.has_community_role(community_id, auth.uid(), 'admin')
  );
-- No write policies: every change goes through the RPCs below.

-- An admin may invite players; only an owner may offer the admin role (PD-10).
create or replace function public.create_invitation(
  p_community_id uuid,
  p_invitee_id uuid,
  p_role text
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
  if p_role not in ('admin', 'player') then
    raise exception 'INVALID_ROLE';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if is_community_member(p_community_id, p_invitee_id) then
    raise exception 'ALREADY_MEMBER';
  end if;

  begin
    insert into invitations (community_id, invited_by, invitee_id, role)
    values (p_community_id, auth.uid(), p_invitee_id, p_role)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'INVITATION_EXISTS';
  end;

  return v_id;
end;
$$;

create or replace function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_inv from invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if not has_community_role(v_inv.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;

  update invitations set status = 'revoked' where id = p_invitation_id;
end;
$$;

-- Only the named invitee can accept. The row lock makes a double accept a
-- no-op rather than a second membership.
create or replace function public.accept_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_inv from invitations where id = p_invitation_id for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_inv.invitee_id <> auth.uid() then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'INVITATION_EXPIRED';
  end if;
  if is_community_member(v_inv.community_id, auth.uid()) then
    raise exception 'ALREADY_MEMBER';
  end if;

  insert into community_members (community_id, user_id, role)
  values (v_inv.community_id, auth.uid(), v_inv.role);

  update invitations set status = 'accepted' where id = p_invitation_id;
  return v_inv.community_id;
end;
$$;

-- 4) Role assignment -----------------------------------------------------------
-- Owner only (PD-02, PD-03). Ownership itself is not settable here.
create or replace function public.set_member_role(
  p_community_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_role not in ('admin', 'player') then
    raise exception 'INVALID_ROLE';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;

  update community_members
  set role = p_role
  where community_id = p_community_id
    and user_id = p_user_id
    and role <> 'owner';

  if not found then
    raise exception 'MEMBER_NOT_FOUND';
  end if;
end;
$$;

-- 5) Organizer RPCs: creator check -> role check --------------------------------
-- Bodies are otherwise unchanged; only the guard and its error code differ.
create or replace function public.update_match(
  p_match_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players int,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_starting_players < 2 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  select count(*) into v_total
  from match_registrations where match_id = p_match_id;
  if p_starting_players
     + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;

  update matches set
    title = case when p_title is null or trim(p_title) = ''
                 then null else trim(p_title) end,
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = ''
                       then null else trim(p_description) end
  where id = p_match_id;

  perform rebalance_roster(p_match_id);
  perform recompute_match_status(p_match_id);

  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;
end;
$$;

create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
  v_promoted uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then
    raise exception 'MATCH_LOCKED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (
      select id from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    )
    returning user_id into v_promoted;

    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
    end if;
  end if;

  perform recompute_match_status(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed',
      'قام المنظم بإزالتك من المباراة.');
end;
$$;

create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      'تم حذف المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;

  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

-- 6) Grants ---------------------------------------------------------------------
revoke execute on function public.create_invitation(uuid, uuid, text)
  from anon, public;
revoke execute on function public.revoke_invitation(uuid) from anon, public;
revoke execute on function public.accept_invitation(uuid) from anon, public;
revoke execute on function public.set_member_role(uuid, uuid, text)
  from anon, public;

grant execute on function public.create_invitation(uuid, uuid, text)
  to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;
grant execute on function public.accept_invitation(uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text)
  to authenticated;
