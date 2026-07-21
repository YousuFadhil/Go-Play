-- Sprint 4: Match Registration & Reserve queue
-- All writes go through RPCs that lock the match row (FOR UPDATE), making
-- seat allocation, queue order, overlap checks and promotion race-safe.
-- Lock order is always: match row first, then user row.

create table public.match_registrations (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  status text not null check (status in ('confirmed', 'reserve')),
  registration_order int not null,
  created_at timestamptz not null default now(),
  unique (match_id, user_id),
  unique (match_id, registration_order)
);

create index match_registrations_queue_idx
  on public.match_registrations (match_id, status, registration_order);
create index match_registrations_user_id_idx
  on public.match_registrations (user_id);

-- Visibility helper: is the user a member of the match's group?
create or replace function public.is_match_group_member(
  p_match_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from matches m
    join group_members gm on gm.group_id = m.group_id
    where m.id = p_match_id
      and gm.user_id = p_user_id
  );
$$;

-- Registers the caller. Returns 'confirmed' or 'reserve'.
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed_count int;
  v_status text;
  v_order int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Serializes all registration activity for this match.
  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  -- Serializes this user's registrations across matches so the overlap
  -- check cannot race with itself.
  perform 1 from users where id = auth.uid() for update;

  if v_match.status <> 'open' or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;

  if not is_group_member(v_match.group_id, auth.uid()) then
    raise exception 'NOT_GROUP_MEMBER';
  end if;

  if exists (
    select 1 from match_registrations
    where match_id = p_match_id and user_id = auth.uid()
  ) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  -- Overlap rule: no registration (confirmed OR reserve) in another open
  -- match whose time range intersects this one. Reserves count because
  -- they can be promoted at any moment.
  if exists (
    select 1
    from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = auth.uid()
      and m.status = 'open'
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  select count(*) into v_confirmed_count
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  v_status := case
    when v_confirmed_count < v_match.max_players then 'confirmed'
    else 'reserve'
  end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations
  where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, auth.uid(), v_status, v_order);

  return v_status;
end;
$$;

-- Withdraws the caller. If a confirmed player leaves, the first reserve
-- (lowest registration_order) is promoted in the same transaction.
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_registration match_registrations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  if v_match.status <> 'open' or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  -- Withdrawal deletes the row (allows re-registration; no MVP feature
  -- consumes withdrawal history). See Docs/10-Design-Decisions.md (DD-01)
  -- before changing this to a soft-delete.
  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations
    set status = 'confirmed'
    where id = (
      select id
      from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    );
  end if;
end;
$$;

revoke execute on function public.register_for_match from anon, public;
revoke execute on function public.withdraw_from_match from anon, public;
grant execute on function public.register_for_match to authenticated;
grant execute on function public.withdraw_from_match to authenticated;

-- Row Level Security
alter table public.match_registrations enable row level security;

-- The roster is visible to members of the match's group.
create policy "match_registrations_select_group_members"
  on public.match_registrations
  for select
  to authenticated
  using (public.is_match_group_member(match_id, auth.uid()));

-- No insert/update/delete policies: all writes go through the RPCs above.
