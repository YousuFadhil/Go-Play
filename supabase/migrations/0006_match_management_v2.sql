-- V2: Match management (organizer tools), extended status model, notifications.
-- Backward compatible: new columns are nullable; new statuses extend the
-- existing set; existing register/withdraw behaviour is preserved and only
-- gains automatic open/full transitions.

-- 1) New optional match fields -------------------------------------------------
alter table public.matches
  add column if not exists title text
    check (title is null or char_length(trim(title)) between 2 and 60);
alter table public.matches
  add column if not exists description text
    check (description is null or char_length(description) <= 300);

-- 2) Extend the status model: draft, full, postponed ---------------------------
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches
  add constraint matches_status_check
  check (status in ('draft', 'open', 'full', 'postponed', 'cancelled', 'completed'));

-- 3) Notifications -------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  match_id uuid references public.matches (id) on delete cascade,
  type text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "notifications_select_own"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());

create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "notifications_delete_own"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid());
-- inserts happen only through the SECURITY DEFINER RPCs below.

-- Internal helper: create one notification row.
create or replace function public.create_notification(
  p_user_id uuid, p_match_id uuid, p_type text, p_message text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notifications (user_id, match_id, type, message)
  values (p_user_id, p_match_id, p_type, p_message);
$$;

-- Recomputes open/full for a match after its roster changes. Never touches
-- terminal states (cancelled/completed) or draft.
create or replace function public.recompute_match_fill(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed int;
begin
  select * into v_match from matches where id = p_match_id;
  if v_match.status not in ('open', 'full') then
    return;
  end if;
  select count(*) into v_confirmed
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';
  update matches
  set status = case when v_confirmed >= v_match.max_players then 'full' else 'open' end
  where id = p_match_id;
end;
$$;

-- 4) Registration: allow joining open/full/postponed; auto open<->full ----------
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

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  perform 1 from users where id = auth.uid() for update;

  -- Joinable while open, full (as reserve) or postponed (re-opened).
  if v_match.status not in ('open', 'full', 'postponed')
     or v_match.start_at <= now() then
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

  -- Overlap rule: no registration in another live match whose time range
  -- intersects this one (reserves count; they can be promoted anytime).
  if exists (
    select 1
    from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = auth.uid()
      and m.status in ('open', 'full', 'postponed')
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

  -- A postponed match becomes live again on the first registration.
  if v_match.status = 'postponed' then
    update matches set status = 'open' where id = p_match_id;
  end if;
  perform recompute_match_fill(p_match_id);

  return v_status;
end;
$$;

-- 5) Withdrawal: promote first reserve; auto full->open -------------------------
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

  if v_match.status not in ('open', 'full') or v_match.start_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;

  select * into v_registration
  from match_registrations
  where match_id = p_match_id and user_id = auth.uid();
  if not found then
    raise exception 'NOT_REGISTERED';
  end if;

  delete from match_registrations where id = v_registration.id;

  if v_registration.status = 'confirmed' then
    update match_registrations
    set status = 'confirmed'
    where id = (
      select id from match_registrations
      where match_id = p_match_id and status = 'reserve'
      order by registration_order
      limit 1
    );
  end if;

  perform recompute_match_fill(p_match_id);
end;
$$;

-- 6) Organizer: edit match (handles player-limit reduction) --------------------
create or replace function public.update_match(
  p_match_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_max_players int,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_confirmed int;
  r record;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;
  if v_match.status in ('cancelled', 'completed') then
    raise exception 'MATCH_READ_ONLY';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_max_players < 2 or p_max_players > 30 then
    raise exception 'INVALID_MAX_PLAYERS';
  end if;

  -- If the limit shrinks below the confirmed count, demote the latest
  -- confirmed players to reserve (registration order preserved).
  select count(*) into v_confirmed
  from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  if p_max_players < v_confirmed then
    for r in
      select id, user_id
      from match_registrations
      where match_id = p_match_id and status = 'confirmed'
      order by registration_order desc
      limit (v_confirmed - p_max_players)
    loop
      update match_registrations set status = 'reserve' where id = r.id;
      perform create_notification(
        r.user_id, p_match_id, 'moved_to_reserve',
        'تم نقلك إلى قائمة الاحتياط بسبب تعديل عدد اللاعبين.');
    end loop;
  end if;

  update matches set
    title = case when p_title is null or trim(p_title) = '' then null else trim(p_title) end,
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    max_players = p_max_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;

  perform recompute_match_fill(p_match_id);

  -- Notify every registered player that details changed. Players who were
  -- just demoted also received the reserve-move notice above.
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr
  where mr.match_id = p_match_id;
end;
$$;

-- 7) Organizer: remove a player -----------------------------------------------
create or replace function public.remove_player(p_match_id uuid, p_user_id uuid)
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
  if v_match.created_by <> auth.uid() then
    raise exception 'NOT_ORGANIZER';
  end if;
  if v_match.status not in ('open', 'full') then
    raise exception 'MATCH_READ_ONLY';
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
    );
  end if;

  perform recompute_match_fill(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed',
      'قام المنظم بإزالتك من المباراة.');
end;
$$;

-- 8) Organizer: cancel (keeps registrations as history) ------------------------
create or replace function public.cancel_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status in ('cancelled', 'completed') then
    raise exception 'MATCH_READ_ONLY';
  end if;

  update matches set status = 'cancelled' where id = p_match_id;

  perform create_notification(mr.user_id, p_match_id, 'match_cancelled',
      'تم إلغاء المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
end;
$$;

-- 9) Organizer: postpone (clears registrations, re-opens) ----------------------
create or replace function public.postpone_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status not in ('open', 'full') then
    raise exception 'MATCH_READ_ONLY';
  end if;

  perform create_notification(mr.user_id, p_match_id, 'match_postponed',
      'تم تأجيل المباراة وإعادة فتح التسجيل.')
  from match_registrations mr where mr.match_id = p_match_id;

  delete from match_registrations where match_id = p_match_id;
  update matches set status = 'postponed' where id = p_match_id;
end;
$$;

-- 10) Organizer: delete (only with zero registrations, never completed) --------
create or replace function public.delete_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_count int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.created_by <> auth.uid() then raise exception 'NOT_ORGANIZER'; end if;
  if v_match.status = 'completed' then raise exception 'MATCH_COMPLETED'; end if;

  select count(*) into v_count
  from match_registrations where match_id = p_match_id;
  if v_count > 0 then raise exception 'MATCH_HAS_PLAYERS'; end if;

  delete from matches where id = p_match_id;
end;
$$;

-- Grants: organizer/notification helpers are for authenticated callers only.
revoke execute on function public.create_notification(uuid, uuid, text, text) from anon, authenticated, public;
revoke execute on function public.recompute_match_fill(uuid) from anon, authenticated, public;
revoke execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text) from anon, public;
revoke execute on function public.remove_player(uuid, uuid) from anon, public;
revoke execute on function public.cancel_match(uuid) from anon, public;
revoke execute on function public.postpone_match(uuid) from anon, public;
revoke execute on function public.delete_match(uuid) from anon, public;
grant execute on function public.update_match(uuid, text, text, timestamptz, timestamptz, int, text) to authenticated;
grant execute on function public.remove_player(uuid, uuid) to authenticated;
grant execute on function public.cancel_match(uuid) to authenticated;
grant execute on function public.postpone_match(uuid) to authenticated;
grant execute on function public.delete_match(uuid) to authenticated;
