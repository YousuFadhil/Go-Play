-- Smart Community Invitation: shareable invite links.
--
-- A shareable link is a bearer token naming a community and, optionally, one
-- match. It is a sibling of `invitations`, not a replacement: a directed
-- invitation names an existing user, is single-use and may offer admin, while a
-- link has no named recipient, is multi-use and only ever grants player.
-- Nothing in this migration alters an existing table, policy or function.
--
-- Approved decisions:
--   * a community-only link never expires; it is valid until an admin revokes it
--   * a community+match link expires when the match starts, or is deleted
--   * redemption always grants the player role
--   * the preview is readable before authentication
--
-- Authorization is unchanged: has_community_role remains the only predicate,
-- and redemption composes the existing membership insert with the existing
-- register_for_match. No business rule is restated here.

-- 1) Table ---------------------------------------------------------------------
create table if not exists public.community_invite_links (
  id uuid primary key default gen_random_uuid(),
  -- 32 hex chars from a v4 UUID: unguessable, URL-safe, no extension needed.
  token text not null unique
    default replace(gen_random_uuid()::text, '-', ''),
  community_id uuid not null
    references public.communities (id) on delete cascade,
  -- Kept alongside match_id because the two disagree after a match is deleted:
  -- kind stays 'match' while match_id becomes null, which is precisely how an
  -- expired-by-deletion link is told apart from a community-only one.
  kind text not null check (kind in ('community', 'match')),
  match_id uuid references public.matches (id) on delete set null,
  created_by uuid not null references public.users (id),
  -- A link has no named recipient, so it can never confer more than the lowest
  -- role. Admin is offered only through a directed invitation (PD-10).
  role text not null default 'player' check (role = 'player'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invite_links_match_kind_agree check (
    (kind = 'community' and match_id is null) or kind = 'match'
  )
);

-- Sharing the same thing twice should hand back the same link rather than
-- breeding new ones, so at most one active link per community and per match.
create unique index if not exists invite_links_one_active_community_idx
  on public.community_invite_links (community_id)
  where is_active and kind = 'community';
create unique index if not exists invite_links_one_active_match_idx
  on public.community_invite_links (match_id)
  where is_active and match_id is not null;
create index if not exists invite_links_community_idx
  on public.community_invite_links (community_id);

drop trigger if exists invite_links_set_updated_at
  on public.community_invite_links;
create trigger invite_links_set_updated_at
  before update on public.community_invite_links
  for each row execute function public.set_updated_at();

-- 2) RLS -----------------------------------------------------------------------
alter table public.community_invite_links enable row level security;

-- Organizers can list and audit their own community's links. Everyone else
-- reaches a link only through preview_invite_link, which returns a fixed set of
-- fields and never the row. anon has no table access at all.
drop policy if exists "invite_links_select_admins"
  on public.community_invite_links;
create policy "invite_links_select_admins"
  on public.community_invite_links
  for select
  to authenticated
  using (public.has_community_role(community_id, auth.uid(), 'admin'));
-- No write policies: every change goes through the RPCs below.

-- 3) Validity ------------------------------------------------------------------
-- One place decides whether a token is usable, shared by preview and redeem so
-- the landing screen can never disagree with what redemption will do.
create or replace function public.invite_link_state(
  p_link public.community_invite_links
)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_link.id is null then 'not_found'
    when not p_link.is_active then 'revoked'
    when p_link.kind = 'community' then 'valid'
    when p_link.match_id is null then 'match_deleted'
    when (select m.start_at from matches m where m.id = p_link.match_id)
         <= now() then 'expired'
    else 'valid'
  end;
$$;

-- 4) Create and revoke ---------------------------------------------------------
create or replace function public.create_invite_link(
  p_community_id uuid,
  p_match_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := case when p_match_id is null then 'community' else 'match' end;
  v_match matches%rowtype;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_match_id is not null then
    select * into v_match from matches m where m.id = p_match_id;
    if not found then
      raise exception 'MATCH_NOT_FOUND';
    end if;
    if v_match.community_id <> p_community_id then
      raise exception 'MATCH_NOT_IN_COMMUNITY';
    end if;
    -- A link that expires at kick-off is pointless once kick-off has passed.
    if v_match.start_at <= now() then
      raise exception 'MATCH_LOCKED';
    end if;
  end if;

  select l.token into v_token
  from community_invite_links l
  where l.is_active
    and l.kind = v_kind
    and l.community_id = p_community_id
    and l.match_id is not distinct from p_match_id;
  if found then
    return v_token;
  end if;

  begin
    insert into community_invite_links (community_id, kind, match_id, created_by)
    values (p_community_id, v_kind, p_match_id, auth.uid())
    returning token into v_token;
  exception when unique_violation then
    -- Two organizers pressed share at the same moment; either link will do.
    select l.token into v_token
    from community_invite_links l
    where l.is_active
      and l.kind = v_kind
      and l.community_id = p_community_id
      and l.match_id is not distinct from p_match_id;
  end;

  return v_token;
end;
$$;

create or replace function public.revoke_invite_link(p_link_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_link
  from community_invite_links l where l.id = p_link_id for update;
  if not found then
    raise exception 'INVITE_NOT_FOUND';
  end if;
  if not has_community_role(v_link.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  update community_invite_links l set is_active = false where l.id = p_link_id;
end;
$$;

-- 5) Preview -------------------------------------------------------------------
-- Callable before sign-in, so it is deliberately narrow: the community's name,
-- the match's public face, and enough counts for the screen to be honest about
-- a reserve place. It never returns join_code, the roster, who created the link
-- or anything about other members. A caller who is signed in additionally
-- learns where they already stand.
--
-- A revoked or unknown token returns its state and nothing else: revoking a
-- link means it stops telling strangers what it used to point at.
create or replace function public.preview_invite_link(p_token text)
returns table (
  state text,
  community_id uuid,
  community_name text,
  match_id uuid,
  match_title text,
  match_location text,
  match_start_at timestamptz,
  match_end_at timestamptz,
  starting_players int,
  seats_remaining int,
  would_be_reserve boolean,
  is_member boolean,
  is_registered boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
  v_state text;
  v_community communities%rowtype;
  v_match matches%rowtype;
  v_total int := 0;
  v_confirmed int := 0;
begin
  select * into v_link
  from community_invite_links l where l.token = trim(p_token);

  v_state := invite_link_state(v_link);

  if v_state in ('not_found', 'revoked') then
    return query select v_state, null::uuid, null::text, null::uuid,
      null::text, null::text, null::timestamptz, null::timestamptz,
      null::int, null::int, null::boolean, false, false;
    return;
  end if;

  select * into v_community from communities c where c.id = v_link.community_id;

  if v_link.match_id is not null then
    select * into v_match from matches m where m.id = v_link.match_id;
    select count(*) into v_total
    from match_registrations r where r.match_id = v_link.match_id;
    select count(*) into v_confirmed
    from match_registrations r
    where r.match_id = v_link.match_id and r.status = 'confirmed';
  end if;

  return query select
    v_state,
    v_link.community_id,
    v_community.name,
    v_link.match_id,
    v_match.title,
    v_match.location,
    v_match.start_at,
    v_match.end_at,
    v_match.starting_players,
    case when v_link.match_id is null then null::int
         else greatest(v_match.max_registration - v_total, 0) end,
    -- The same expression register_for_match uses to allocate a seat, so the
    -- screen promises exactly what redemption will deliver.
    case when v_link.match_id is null then null::boolean
         else v_confirmed >= v_match.starting_players end,
    auth.uid() is not null
      and is_community_member(v_link.community_id, auth.uid()),
    v_link.match_id is not null
      and auth.uid() is not null
      and exists (
        select 1 from match_registrations r
        where r.match_id = v_link.match_id and r.user_id = auth.uid()
      );
end;
$$;

-- 6) Redeem --------------------------------------------------------------------
-- Joining and registering are separate outcomes on purpose: if registration
-- fails the membership stands and the caller is told why. The inner block is
-- what makes that true -- a caught exception rolls back to its savepoint, not
-- past the membership insert.
--
-- register_for_match is called unchanged, so capacity, the reserve queue, the
-- overlap rule, the lock and closure are all decided where they always were.
create or replace function public.redeem_invite_link(p_token text)
returns table (
  community_id uuid,
  match_id uuid,
  registration_status text,
  failure_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link community_invite_links%rowtype;
  v_state text;
  v_status text;
  v_failure text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_link
  from community_invite_links l where l.token = trim(p_token);

  v_state := invite_link_state(v_link);
  if v_state <> 'valid' then
    raise exception 'INVITE_%', upper(v_state);
  end if;

  if not is_community_member(v_link.community_id, auth.uid()) then
    begin
      insert into community_members (community_id, user_id, role)
      values (v_link.community_id, auth.uid(), v_link.role);
    exception when unique_violation then
      -- Someone redeemed the same link twice at once; membership is what
      -- matters and it now exists.
      null;
    end;
  end if;

  if v_link.match_id is not null then
    begin
      v_status := register_for_match(v_link.match_id);
    exception when others then
      v_failure := sqlerrm;
      v_status := null;
    end;

    -- Redeeming twice is expected of a link that lives in a group chat, so an
    -- existing registration is an outcome, not a failure.
    if v_failure = 'ALREADY_REGISTERED' then
      select r.status into v_status
      from match_registrations r
      where r.match_id = v_link.match_id and r.user_id = auth.uid();
      v_failure := null;
    end if;
  end if;

  return query select v_link.community_id, v_link.match_id, v_status, v_failure;
end;
$$;

-- 7) Grants --------------------------------------------------------------------
-- An internal helper, not an entry point: only the definer functions above call
-- it. Supabase's default privileges grant new functions to authenticated, so
-- that grant has to be taken back explicitly, not merely left ungranted.
revoke execute on function public.invite_link_state(public.community_invite_links)
  from anon, authenticated, public;
revoke execute on function public.create_invite_link(uuid, uuid)
  from anon, public;
revoke execute on function public.revoke_invite_link(uuid) from anon, public;
revoke execute on function public.redeem_invite_link(text) from anon, public;
revoke execute on function public.preview_invite_link(text) from public;

grant execute on function public.create_invite_link(uuid, uuid) to authenticated;
grant execute on function public.revoke_invite_link(uuid) to authenticated;
grant execute on function public.redeem_invite_link(text) to authenticated;
-- The one deliberately unauthenticated entry point in the system.
grant execute on function public.preview_invite_link(text)
  to anon, authenticated;
