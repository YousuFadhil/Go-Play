-- Phase 3 (AMS v1.2), second part: the three community-management operations
-- whose behaviour the Product Owner ruled on after 0008 was applied.
--
-- All three are authorized through has_community_role, like everything else
-- since 0008; owner_id and created_by remain non-authorization fields.

-- 1) Ownership transfer ---------------------------------------------------------
-- Owner only. Demote-and-promote happen in one transaction, so the community is
-- never observable with zero or two owners. owner_id is the derived reporting
-- field (PD-15) and is re-pointed here, the one place ownership can move.
create or replace function public.transfer_ownership(
  p_community_id uuid,
  p_new_owner_id uuid
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
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_new_owner_id = auth.uid() then
    raise exception 'ALREADY_OWNER';
  end if;

  -- Serializes concurrent transfers of the same community.
  perform 1 from communities where id = p_community_id for update;

  if not exists (
    select 1 from community_members
    where community_id = p_community_id and user_id = p_new_owner_id
  ) then
    raise exception 'MEMBER_NOT_FOUND';
  end if;

  update community_members set role = 'admin'
  where community_id = p_community_id and user_id = auth.uid();

  update community_members set role = 'owner'
  where community_id = p_community_id and user_id = p_new_owner_id;

  update communities set owner_id = p_new_owner_id where id = p_community_id;
end;
$$;

-- 2) Member removal --------------------------------------------------------------
-- Owner removes admins and players; an admin removes players only (PD-11). The
-- owner can never be removed. Removal also takes the member out of every match
-- in the community -- confirmed and reserve alike -- freeing each confirmed seat
-- through the existing promotion path so the roster stays correct.
create or replace function public.remove_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_role text;
  r record;
  v_promoted uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_REMOVE_SELF';
  end if;

  select role into v_target_role
  from community_members
  where community_id = p_community_id and user_id = p_user_id;
  if not found then
    raise exception 'MEMBER_NOT_FOUND';
  end if;
  if v_target_role = 'owner' then
    raise exception 'CANNOT_REMOVE_OWNER';
  end if;
  -- Removing an admin changes the role structure, which is owner territory.
  if v_target_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  for r in
    select mr.id, mr.status, mr.match_id
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id
      and mr.user_id = p_user_id
  loop
    -- Same lock order as every other roster write: match row first.
    perform 1 from matches where id = r.match_id for update;

    delete from match_registrations where id = r.id;

    if r.status = 'confirmed' then
      update match_registrations set status = 'confirmed'
      where id = (
        select id from match_registrations
        where match_id = r.match_id and status = 'reserve'
        order by registration_order
        limit 1
      )
      returning user_id into v_promoted;

      if v_promoted is not null then
        perform create_notification(v_promoted, r.match_id, 'promoted',
            'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.');
      end if;
    end if;

    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

-- 3) Community deletion ----------------------------------------------------------
-- Owner only. Everything scoped to the community goes with it; no archive and no
-- soft delete at this stage.
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform 1 from communities where id = p_community_id for update;

  -- Notifications point at the match with ON DELETE SET NULL, so they have to go
  -- first: once the matches are gone there is no way left to tell which
  -- notifications belonged to this community.
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);

  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from invitations where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- Grants ---------------------------------------------------------------------------
revoke execute on function public.transfer_ownership(uuid, uuid) from anon, public;
revoke execute on function public.remove_member(uuid, uuid) from anon, public;
revoke execute on function public.delete_community(uuid) from anon, public;
grant execute on function public.transfer_ownership(uuid, uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.delete_community(uuid) to authenticated;
