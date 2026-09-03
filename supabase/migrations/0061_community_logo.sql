-- ============ migrations/0061_community_logo.sql ============
-- A community may have a picture.
--
-- The approved product rule, in one sentence:
--
--     A community's logo is optional, publicly readable, and changed or removed
--     by an owner or an admin — and by nobody else.
--
-- Four things are needed for that and nothing else is here: a nullable column,
-- a bucket of its own, storage policies that ask about the *community* rather
-- than about the uploader, and one narrow function that is the only way the
-- column is ever written.
--
-- THE ONE DESIGN DECISION WORTH READING
--
-- Generic UPDATE on `communities` is owner-only and stays that way.
-- `communities_update_owner` (migration `0016`) is
-- `has_community_role(id, auth.uid(), 'owner')`, and widening it to admins so
-- that an admin could set a logo would hand admins every other column too —
-- the name, the description, the join policy. That is not the approved change.
--
-- So the logo is written through `set_community_logo` instead: a
-- `security definer` function whose entire body updates one column, after
-- checking the caller's community role itself. An admin gets exactly the
-- authority the product grants them and no more, and the table policy is
-- untouched.


-- ============================================================================
-- 1) The column
-- ============================================================================
-- A URL and not a storage path, unlike `users.avatar_path`. The two are stored
-- differently on purpose: an avatar's path is resolved to a URL by the client
-- that reads it, which works because every avatar lives at a path derived from
-- the player's id. A community logo is versioned — a new object name on every
-- replacement, so that caches cannot serve the previous picture — and a
-- versioned name is not derivable from the community's id. What is stored is
-- therefore the address itself.
--
-- Nullable, with no default. A community without a picture is the ordinary
-- case, not a missing one: every community that exists today has null here and
-- goes on showing its initials.
alter table public.communities
  add column if not exists logo_url text;

comment on column public.communities.logo_url is
  'Public URL of the community''s logo in the community-logos bucket, or null '
  'when it has none — which is the initials crest. Written only through '
  'set_community_logo(); generic UPDATE on this table remains owner-only.';

-- Migration `0056` revoked SELECT on this table and granted eight columns back
-- by name, so a column added afterwards is invisible to the client until it is
-- named here. Nothing else about that grant changes: this adds one column to a
-- list, and takes nothing off it.
grant select (logo_url) on public.communities to authenticated;


-- ============================================================================
-- 2) Reading a community id out of an object path, safely
-- ============================================================================
-- The storage policies below authorize against the community named by the
-- object's first folder. That means casting a piece of a caller-supplied string
-- to `uuid`, and a cast that raises inside a policy is a request that fails
-- with a type error rather than a refusal.
--
-- This returns null for anything that is not a uuid — no folder, an empty
-- folder, a name somebody made up — and null flows into
-- `has_community_role` as a community that matches no membership row. A
-- malformed path is therefore *unauthorized*, which is the behaviour a policy
-- wants, rather than an error the caller can distinguish.
create or replace function public.community_logo_folder(p_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  begin
    v_id := ((storage.foldername(p_name))[1])::uuid;
  exception when others then
    return null;
  end;
  return v_id;
end;
$$;

comment on function public.community_logo_folder(text) is
  'The community uuid a community-logos object path is scoped by, or null when '
  'the path does not begin with one. Null is unauthorized, never an error.';

revoke execute on function public.community_logo_folder(text) from anon, public;
grant execute on function public.community_logo_folder(text) to authenticated;


-- ============================================================================
-- 3) The bucket
-- ============================================================================
-- Its own bucket, not `avatars`. The two hold different kinds of thing with
-- different owners and different write rules — an avatar belongs to the person
-- whose id names its folder, a logo belongs to a community and may be replaced
-- by any of its organizers — and one bucket cannot carry both rules without one
-- of them becoming the other's special case.
--
-- Public for reading, for the reason the avatars bucket is: a community's crest
-- appears on Discover, in the communities list, on its own page and beside its
-- matches, and signing every one of those reads would cost a round trip for a
-- picture that is already shown to anyone who can see the community at all.
-- What is not public is writing.
--
-- The same five-megabyte ceiling and the same three formats as avatars: the
-- client resizes before uploading, and a limit the client already respects is
-- one less thing for the two to disagree about.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-logos', 'community-logos', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


-- ============================================================================
-- 4) Who may write into it
-- ============================================================================
-- **The folder is the community, not the uploader.** This is the whole
-- difference from the avatars policies, and it is deliberate: an avatar's
-- authority is personal, so `(storage.foldername(name))[1] = auth.uid()::text`
-- is exactly right there. A logo's authority belongs to a *role in a
-- community* — so an admin must be able to replace a picture the owner
-- uploaded, and the owner must be able to remove one an admin uploaded.
-- Object ownership cannot express that, and `auth.uid()` in the path would
-- express the wrong thing entirely.
--
-- The same predicate governs insert, update and delete, so replacing a picture
-- is the same permission as setting one — and Storage's upsert, which needs
-- all three, is satisfied by one rule rather than by three that might drift.

-- Public read, matching the bucket.
drop policy if exists "community_logos_read_all" on storage.objects;
create policy "community_logos_read_all"
  on storage.objects
  for select
  to public
  using (bucket_id = 'community-logos');

drop policy if exists "community_logos_insert_organizer" on storage.objects;
create policy "community_logos_insert_organizer"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'community-logos'
    and public.has_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );

drop policy if exists "community_logos_update_organizer" on storage.objects;
create policy "community_logos_update_organizer"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'community-logos'
    and public.has_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  )
  with check (
    bucket_id = 'community-logos'
    and public.has_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );

drop policy if exists "community_logos_delete_organizer" on storage.objects;
create policy "community_logos_delete_organizer"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'community-logos'
    and public.has_community_role(
      public.community_logo_folder(name), auth.uid(), 'admin'
    )
  );


-- ============================================================================
-- 5) The one way `logo_url` is written
-- ============================================================================
-- `security definer` for one stated reason: an admin is allowed to change a
-- community's logo and is *not* allowed generic UPDATE on the community. The
-- function is the narrow grant that difference requires. It updates one column,
-- it never reads a role from its caller, and the authorization is decided here
-- against `auth.uid()` rather than anywhere a client can reach.
--
-- `p_logo_url` null is a reset, and it is the same call: removing a picture and
-- setting one are the same authority over the same column, so they are one
-- function rather than two that could be granted differently by accident.
--
-- An inactive community answers `COMMUNITY_NOT_FOUND`. A soft-deleted community
-- is not one anybody is still decorating.
--
-- Returns the value it stored, which is what the caller then shows: the same
-- shape `regenerate_join_code` uses, so a repository reads one row back rather
-- than making a second read to learn what it just wrote.
--
-- `search_path = ''` and not `= public`. A `security definer` function runs as
-- its owner, so an empty search path is what stops any name inside it being
-- resolved against a schema a caller controls: every relation and every
-- function below is written out in full, and there is nothing left for a search
-- path to decide. `now()` is the one exception and needs none — `pg_catalog` is
-- always searched first and cannot be shadowed.
create or replace function public.set_community_logo(
  p_community_id uuid,
  p_logo_url text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stored text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Asked before the row is touched, so a refusal never depends on what was
  -- found. 'admin' is the *minimum*: has_community_role orders owner above
  -- admin above player, so this authorizes an owner and an admin, and refuses a
  -- player and anybody who is not a member at all.
  if not public.has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  update public.communities c
     set logo_url = p_logo_url,
         updated_at = now()
   where c.id = p_community_id and c.is_active
  returning c.logo_url into v_stored;

  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  return v_stored;
end;
$$;

comment on function public.set_community_logo(uuid, text) is
  'Sets or clears a community''s logo_url, for an owner or an admin and nobody '
  'else. security definer because generic UPDATE on communities is owner-only '
  'and must stay so: this is the narrow authority an admin is granted over one '
  'column, rather than a widening of communities_update_owner.';

-- Nobody signed out, and nothing granted to the world. An anonymous caller
-- cannot execute it at all, which is a second refusal behind the auth.uid()
-- check inside it.
revoke execute on function public.set_community_logo(uuid, text) from anon, public;
grant execute on function public.set_community_logo(uuid, text) to authenticated;


-- ============================================================================
-- 6) The picture reaches the surfaces that already show a community
-- ============================================================================
-- A community's logo is its public identity: the approved rule is that it
-- replaces the initials *wherever the crest is drawn*, which includes the
-- pages a visitor sees without signing in. Two existing read paths carry a
-- community's identity to those pages, and each needs the one extra field.
--
-- **Nothing else about either is touched.** No filter, no ordering, no other
-- column, no grant. The exposure that changes is exactly one: a community's
-- logo URL, which is an object in a public bucket and is already readable by
-- anyone who has the address.

-- --- 6a) The public community projection --------------------------------------
--
-- `create or replace view` may append columns to the end of a view's list and
-- may not reorder or retype the ones already there — which is precisely the
-- change wanted here, and is why this is a replace rather than a drop. The
-- existing grants survive it, because the view is never dropped.
--
-- **The security_definer advisory on this view is left exactly as it is.** It
-- predates this migration and is a separate decision; the projection below is
-- character-for-character the `0033` one with a single column added.
create or replace view public.v_public_communities as
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

-- --- 6b) The invitation preview ------------------------------------------------
--
-- **This one is a signature change, and it has to be.** The function
-- `returns table (...)`, so its return type is part of its identity and
-- `create or replace` refuses to add a column to it — Postgres answers "cannot
-- change return type of existing function". The only way to extend it is to
-- drop and recreate, which is done here in one transaction with the grants
-- re-applied immediately.
--
-- Nothing about what it answers changes otherwise: the same four values in the
-- same order, plus the community's logo at the end. Callers reading by name are
-- unaffected, and a client that has not been updated simply does not ask for the
-- new field.
--
-- Recreated rather than replaced also means the privileges are gone with it, so
-- they are restated below exactly as `0012` set them.
--
-- **Recreating it is also the chance to harden it, and that is taken here.**
-- The `0012` form ran `security definer` with `search_path = public`; this one
-- runs with `search_path = ''` and writes out `public.communities`,
-- `public.is_community_member` and `auth.uid()` in full, so nothing inside it
-- resolves against a schema a caller controls. `upper()` and `trim()` need no
-- qualification — `pg_catalog` is always searched first and cannot be shadowed.
--
-- Nothing about what it answers changes: the same join-code matching, the same
-- membership test, the same four values.
drop function if exists public.preview_community_invite(text);

create function public.preview_community_invite(p_code text)
returns table (
  state text,
  community_id uuid,
  community_name text,
  is_member boolean,
  community_logo_url text
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_community public.communities%rowtype;
begin
  select * into v_community
  from public.communities c
  where c.join_code = upper(trim(p_code)) and c.is_active;

  if not found then
    return query select 'not_found'::text, null::uuid, null::text, false,
      null::text;
    return;
  end if;

  return query select
    'valid'::text,
    v_community.id,
    v_community.name,
    auth.uid() is not null
      and public.is_community_member(v_community.id, auth.uid()),
    v_community.logo_url;
end;
$$;

comment on function public.preview_community_invite(text) is
  'What a shared invitation offers, readable without a session. Migration 0061 '
  'appended community_logo_url; the four values before it are unchanged.';

-- Stated one role at a time rather than in a list, because the two grants are
-- here for different reasons and only one of them is unusual.
--
-- PUBLIC first: a freshly created function carries an implicit EXECUTE for
-- PUBLIC, so without this revoke every later grant would be decoration.
revoke execute on function public.preview_community_invite(text) from public;

-- **The anon grant is deliberate, and it is the point of an invitation link.**
-- Somebody following one has no session yet — they are deciding whether to
-- install the app at all — so the landing page has to be able to name the
-- community and now to show its picture. This is the same grant `0012` gave the
-- function, restated because dropping it took the privileges with it.
grant execute on function public.preview_community_invite(text) to anon;
grant execute on function public.preview_community_invite(text) to authenticated;
