-- A minimal internal administration role.
--
-- System Admin is not a community role and never appears in community_members:
-- has_community_role knows nothing about it, and it grants nothing inside any
-- community. It exists to remove things — users, communities, matches — when
-- support needs to, and that is all it can do.
--
-- Membership of this table is managed by hand in SQL. There is deliberately no
-- RPC and no screen for granting or revoking it: the app must not be able to
-- create its own administrators.
--
-- Deletion reuses the existing cascades rather than restating them. The three
-- purge_* helpers below hold the bodies that delete_community, delete_match and
-- remove_member already had; those functions keep their authorization checks and
-- now delegate. One cascade, two callers, no chance of the admin path drifting
-- from the member path.

-- 1) The role ------------------------------------------------------------------
create table if not exists public.system_admins (
  user_id uuid primary key references public.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.system_admins enable row level security;
-- No policies at all: the table is reachable only through the definer functions
-- below. Not even an administrator can read it from the client.

create or replace function public.is_system_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from system_admins where user_id = auth.uid()
  );
$$;

revoke execute on function public.is_system_admin() from anon, public;
grant execute on function public.is_system_admin() to authenticated;

-- 2) Shared cascades -----------------------------------------------------------
-- No authorization checks in here on purpose: each caller does its own. These
-- are the bodies the public functions already ran.

create or replace function public.purge_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      'تم حذف المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

create or replace function public.purge_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from communities where id = p_community_id for update;
  -- Notifications first: match_id is ON DELETE SET NULL, so they would outlive
  -- their matches and be orphaned rather than removed (DD-08).
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);
  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- Withdrawing a member from one community's matches, promoting reserves as it
-- goes. This is the part of remove_member that is a business rule rather than a
-- permission check (DD-01, and the promotion rule that goes with it).
create or replace function public.purge_membership(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_promoted uuid;
begin
  for r in
    select mr.id, mr.status, mr.match_id
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id and mr.user_id = p_user_id
  loop
    perform 1 from matches where id = r.match_id for update;
    delete from match_registrations where id = r.id;
    if r.status = 'confirmed' then
      update match_registrations set status = 'confirmed'
      where id = (select id from match_registrations
                  where match_id = r.match_id and status = 'reserve'
                  order by registration_order limit 1)
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

revoke execute on function public.purge_match(uuid) from anon, authenticated, public;
revoke execute on function public.purge_community(uuid) from anon, authenticated, public;
revoke execute on function public.purge_membership(uuid, uuid)
  from anon, authenticated, public;

-- 3) The existing functions now delegate ---------------------------------------
create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform purge_community(p_community_id);
end;
$$;

create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform purge_match(p_match_id);
end;
$$;

create or replace function public.remove_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_target_role text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_user_id = auth.uid() then raise exception 'CANNOT_REMOVE_SELF'; end if;

  select role into v_target_role from community_members
  where community_id = p_community_id and user_id = p_user_id;
  if not found then raise exception 'MEMBER_NOT_FOUND'; end if;
  if v_target_role = 'owner' then raise exception 'CANNOT_REMOVE_OWNER'; end if;
  if v_target_role = 'admin'
     and not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform purge_membership(p_community_id, p_user_id);
end;
$$;

-- 4) Reading ---------------------------------------------------------------------
-- Search is a plain case-insensitive contains over the obvious field, capped at
-- 100 rows. Enough to find a record to delete, which is the only reason these
-- screens exist.

create or replace function public.admin_list_users(p_search text default null)
returns table (
  id uuid,
  full_name text,
  phone text,
  email text,
  created_at timestamptz,
  is_system_admin boolean
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
           exists (select 1 from system_admins sa where sa.user_id = u.id)
    from users u
    join auth.users au on au.id = u.id
    where p_search is null or trim(p_search) = ''
       or u.full_name ilike '%' || trim(p_search) || '%'
       or au.email::text ilike '%' || trim(p_search) || '%'
    order by u.created_at desc
    limit 100;
end;
$$;

create or replace function public.admin_list_communities(p_search text default null)
returns table (
  id uuid,
  name text,
  join_policy text,
  created_at timestamptz,
  owner_name text,
  member_count bigint,
  match_count bigint
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
           (select count(*) from matches m where m.community_id = c.id)
    from communities c
    left join users o on o.id = c.owner_id
    where p_search is null or trim(p_search) = ''
       or c.name ilike '%' || trim(p_search) || '%'
    order by c.created_at desc
    limit 100;
end;
$$;

create or replace function public.admin_list_matches(p_search text default null)
returns table (
  id uuid,
  title text,
  location text,
  start_at timestamptz,
  status text,
  community_name text,
  registration_count bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  return query
    select m.id, m.title, m.location, m.start_at, m.status, c.name,
           (select count(*) from match_registrations r where r.match_id = m.id)
    from matches m
    join communities c on c.id = m.community_id
    where p_search is null or trim(p_search) = ''
       or m.title ilike '%' || trim(p_search) || '%'
       or m.location ilike '%' || trim(p_search) || '%'
       or c.name ilike '%' || trim(p_search) || '%'
    order by m.start_at desc
    limit 100;
end;
$$;

-- 5) Deleting ------------------------------------------------------------------

create or replace function public.admin_delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  perform purge_match(p_match_id);
end;
$$;

create or replace function public.admin_delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  perform purge_community(p_community_id);
end;
$$;

-- Removes the account and everything that would otherwise outlive it.
--
-- Order matters. Communities the user owns go whole, because a community
-- without an owner has no one who can manage or delete it. Elsewhere the user
-- is only a member, so they are withdrawn the way remove_member withdraws
-- anyone — reserves promoted, rosters recomputed — and matches they created in
-- someone else's community are deleted, since created_by does not cascade.
create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  if not is_system_admin() then raise exception 'NOT_AUTHORIZED'; end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_DELETE_SELF';
  end if;
  -- System Admin accounts are managed outside the app, so the app cannot
  -- remove one. Otherwise the last administrator could be deleted from a phone.
  if exists (select 1 from system_admins where user_id = p_user_id) then
    raise exception 'CANNOT_DELETE_SYSTEM_ADMIN';
  end if;
  perform 1 from users where id = p_user_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;

  for r in select id from communities where owner_id = p_user_id loop
    perform purge_community(r.id);
  end loop;

  for r in select cm.community_id from community_members cm
           where cm.user_id = p_user_id loop
    perform purge_membership(r.community_id, p_user_id);
  end loop;

  for r in select id from matches where created_by = p_user_id loop
    perform purge_match(r.id);
  end loop;

  -- Anything addressed to them, and anything they still hold.
  delete from notifications where user_id = p_user_id;
  delete from match_registrations where user_id = p_user_id;
  delete from community_members where user_id = p_user_id;
  delete from users where id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

revoke execute on function public.admin_list_users(text) from anon, public;
revoke execute on function public.admin_list_communities(text) from anon, public;
revoke execute on function public.admin_list_matches(text) from anon, public;
revoke execute on function public.admin_delete_user(uuid) from anon, public;
revoke execute on function public.admin_delete_community(uuid) from anon, public;
revoke execute on function public.admin_delete_match(uuid) from anon, public;

grant execute on function public.admin_list_users(text) to authenticated;
grant execute on function public.admin_list_communities(text) to authenticated;
grant execute on function public.admin_list_matches(text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
grant execute on function public.admin_delete_community(uuid) to authenticated;
grant execute on function public.admin_delete_match(uuid) to authenticated;
