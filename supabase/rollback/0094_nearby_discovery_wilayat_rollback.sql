-- == rollback/0094_nearby_discovery_wilayat_rollback.sql ==
-- Puts the database back to what it was before `0094`: no Wilayat tables, no
-- location column on `communities` or `users`, `create_community` with three
-- arguments, `my_profile()` with ten columns, and the two public views without
-- the columns `0094` appended.
--
-- **THIS ROLLBACK DELETES DATA.** Dropping `communities.wilayat_code` and
-- `users.default_wilayat_code` discards every community's Wilayat and every
-- player's Default Location, and dropping the two reference tables discards the
-- 11 + 63 seeded rows. Nothing in `0094` can be undone without that. Keep what
-- you may want before running it:
--
--     select id, wilayat_code from public.communities where wilayat_code is not null;
--     select id, default_wilayat_code from public.users where default_wilayat_code is not null;
--
-- The reference rows are reproducible from `0094` itself.
--
-- Roll the client back first (or with this): the current client selects
-- `communities.wilayat_code`, reads `v_public_*.wilayat_code` and calls
-- `set_community_wilayat`, and fails without them. The previous client is
-- unaffected by both directions, which is the point of how `0094` was written.
--
-- **Nothing historical is edited.** `0033`, `0061`, `0063` and `0064` stay as they
-- were written; this file restates their objects, which is the only way a
-- forward-only migration history can be undone.

-- A) The setter, and the three-argument create_community ------------------------
drop function if exists public.set_community_wilayat(uuid, smallint);

drop function if exists public.create_community(text, text, text, smallint);

-- `0064`'s body.
create function public.create_community(
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
  -- Added by migration 0064: a suspended account performs no new activity.
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
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

-- B) my_profile, as `0063` left it ----------------------------------------------
drop function if exists public.my_profile();

create function public.my_profile()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  primary_position text,
  secondary_position text,
  date_of_birth date,
  avatar_path text,
  overall_rating numeric,
  profile_visibility text,
  age_visible boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  return query
  select
    u.id,
    u.full_name,
    u.phone,
    u.primary_position,
    u.secondary_position,
    u.date_of_birth,
    u.avatar_path,
    u.overall_rating,
    u.profile_visibility,
    u.age_visible
  from users u
  -- `is_active` is deliberately absent. A suspended account still has a
  -- profile, and this is its owner asking for it (migration 0063).
  where u.id = auth.uid();
end;
$$;

comment on function public.my_profile() is
  'The signed-in player''s own account row, phone included. Takes no user id, '
  'so it cannot be pointed at anybody else -- see migration 0055. Returns the '
  'row whether or not the account is active (migration 0063). Carries no '
  'suspension metadata.';

revoke execute on function public.my_profile() from anon, public;
grant execute on function public.my_profile() to authenticated;

-- C) The two public views, without the appended columns -------------------------
-- `create or replace view` cannot remove a column, so both are dropped and
-- created again. Neither has a dependent object (`public_match_detail` is a SQL
-- function over the view's named columns, which are all still there). A view
-- created in `public` is given every privilege by Supabase's defaults, which is
-- the state `0034` and `0056` exist to undo, so the same revokes follow.
drop view public.v_public_communities;
drop view public.v_public_upcoming_matches;

-- `0033`.
create view public.v_public_upcoming_matches as
select
  m.id,
  m.community_id,
  c.name                                  as community_name,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.starting_players,
  greatest(m.starting_players - coalesce(reg.confirmed_count, 0), 0)::int
                                          as open_slots
from public.matches m
join public.communities c on c.id = m.community_id
left join lateral (
  select count(*) filter (where r.status = 'confirmed') as confirmed_count
  from public.match_registrations r
  where r.match_id = m.id
) reg on true
where c.is_active
  and m.end_at > now()
  and m.status <> 'completed';

comment on view public.v_public_upcoming_matches is
  'Public read model: matches that have not ended, with remaining places. '
  'Readable without a session. Unordered by design -- the caller sorts.';

-- `0061`.
create view public.v_public_communities as
select
  c.id,
  c.name,
  c.description,
  (
    select count(*)
    from public.community_members cm
    where cm.community_id = c.id
  )::int                                  as member_count,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and m.end_at > now()
      and m.status <> 'completed'
  )::int                                  as upcoming_match_count,
  c.created_at,
  c.logo_url
from public.communities c
where c.is_active;

comment on view public.v_public_communities is
  'Public community discovery. Migration 0061 appended logo_url and changed '
  'nothing else about the projection, its filter or its grants.';

revoke all on public.v_public_communities      from public, anon, authenticated;
revoke all on public.v_public_upcoming_matches from public, anon, authenticated;
grant select on public.v_public_communities      to anon, authenticated;
grant select on public.v_public_upcoming_matches to anon, authenticated;

-- D) The columns and the reference data -----------------------------------------
-- Last, because the columns reference the tables and the views above read them.
revoke select (wilayat_code) on public.communities from authenticated;
revoke update (default_wilayat_code) on public.users from authenticated;

drop index if exists public.communities_wilayat_code_idx;
alter table public.communities drop column if exists wilayat_code;
alter table public.users drop column if exists default_wilayat_code;

drop table if exists public.wilayats;
drop table if exists public.governorates;
