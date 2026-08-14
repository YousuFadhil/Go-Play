-- Notification messages name the match they are about.
--
-- The defect: five of the six live notice types carried a message that never
-- said *which* match. A player in a community with three fixtures received
-- «تم تعديل تفاصيل المباراة.» and could not tell which one changed, on the
-- phone or in the Notification Center.
--
-- The fix is one expression per producer. `notifications.message` becomes the
-- match's title and nothing else, because of where that string is actually
-- read:
--
--   * push **body** — the push *title* already names the event, from
--     `notification_types.push_title` («تم تحديث المباراة»). Repeating the
--     event in the body wasted the one line that could have carried context.
--   * Notification Center **subtitle** — the tile's primary line is the
--     reader's own localized label, so the message is free to be the context.
--
-- So the pair reads «تم تحديث المباراة» / «مباراة الجمعة» in both places, and
-- the explanatory wording is not lost: it lives in the localized label, which
-- is the only one of the three that is translated.
--
-- `match_created` is deliberately untouched. 0039 already gives it
-- `title — location`, which is right for a notice whose job is to make someone
-- register somewhere they have not been told about yet.
--
-- **Every function below is reproduced verbatim from its live definition**
-- (`pg_get_functiondef`, read from production before writing this), because a
-- function has no partial redefinition. Diff each against the live source and
-- the message expression is the whole of the change. Nothing else moves: not
-- the signature, not `security definer`, not `search_path`, not an
-- authorization check, not a capacity or ordering or locking rule, not the
-- recipient set, not the notification type.
--
-- Two ACL shapes exist among these and are preserved separately: the three
-- caller-facing RPCs keep `authenticated`, while `purge_match`,
-- `purge_membership` and `rebalance_roster` are internal helpers reachable by
-- `service_role` only and **must not gain `authenticated`**.

-- 1) update_match --------------------------------------------------------------
-- `p_title` is already validated and is what the row was just set to, so the
-- notice names the match by its new title rather than the one it had.
create or replace function public.update_match(
  p_match_id uuid, p_title text, p_location text,
  p_start_at timestamptz, p_end_at timestamptz,
  p_starting_players integer, p_description text
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
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if p_starting_players + (select reserve_players from app_settings limit 1) < v_total then
    raise exception 'MAX_BELOW_REGISTERED';
  end if;
  update matches set
    title = trim(p_title),
    location = trim(p_location),
    start_at = p_start_at,
    end_at = p_end_at,
    starting_players = p_starting_players,
    description = case when p_description is null or trim(p_description) = '' then null else trim(p_description) end
  where id = p_match_id;
  perform rebalance_roster(p_match_id);
  perform recompute_match_status(p_match_id);
  perform create_notification(mr.user_id, p_match_id, 'match_updated',
      -- CHANGED: was 'تم تعديل تفاصيل المباراة.'
      trim(p_title))
  from match_registrations mr where mr.match_id = p_match_id;
end;
$$;

revoke execute on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) from anon, public;
grant execute on function public.update_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) to authenticated;

-- 2) purge_match ---------------------------------------------------------------
-- The title has to be read **before** the delete, which is the only structural
-- addition in this migration. Everything about the existing ordering is kept:
-- the notices are written first, then the registrations go, then the match —
-- so `notifications.match_id` is still nulled by `on delete set null` and the
-- notice still routes to the Notification Center rather than at a match that
-- no longer exists.
--
-- `coalesce(v_title, '')` rather than a substitute wording: a missing match has
-- no registrations to notify (the foreign key guarantees it), so the blank is
-- unreachable. It is written anyway because `message` is NOT NULL, and a blank
-- one degrades cleanly at both readers — `push_dispatch_payload` already falls
-- back to the push title, and the Center simply shows no subtitle.
create or replace function public.purge_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  -- ADDED: captured before the delete below, which is the only chance to.
  select title into v_title from matches where id = p_match_id;
  perform create_notification(mr.user_id, p_match_id, 'match_deleted',
      -- CHANGED: was 'تم حذف المباراة.'
      coalesce(v_title, ''))
  from match_registrations mr where mr.match_id = p_match_id;
  delete from match_registrations where match_id = p_match_id;
  delete from matches where id = p_match_id;
end;
$$;

revoke execute on function public.purge_match(uuid) from anon, authenticated, public;

-- 3) remove_player -------------------------------------------------------------
-- `v_match` is already loaded and locked, so the title costs nothing to read.
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
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  select * into v_registration from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (select id from match_registrations
                where match_id = p_match_id and status = 'reserve'
                order by registration_order limit 1)
    returning user_id into v_promoted;
    if v_promoted is not null then
      perform create_notification(v_promoted, p_match_id, 'promoted',
          -- CHANGED: was 'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.'
          v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
  perform create_notification(p_user_id, p_match_id, 'removed',
      -- CHANGED: was 'قام المنظم بإزالتك من المباراة.'
      v_match.title);
end;
$$;

revoke execute on function public.remove_player(uuid, uuid) from anon, public;
grant execute on function public.remove_player(uuid, uuid) to authenticated;

-- 4) rebalance_roster ----------------------------------------------------------
-- The existing select already reads the match; it now reads one more column of
-- the same row.
create or replace function public.rebalance_roster(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_starting int; v_title text; r record;
begin
  -- CHANGED: `title` added to the existing select. No extra query.
  select starting_players, title into v_starting, v_title
  from matches where id = p_match_id;
  for r in
    select mr.id, mr.user_id, mr.status,
           case when row_number() over (order by mr.registration_order) <= v_starting then 'confirmed' else 'reserve' end as desired
    from match_registrations mr where mr.match_id = p_match_id
  loop
    if r.status <> r.desired then
      update match_registrations set status = r.desired where id = r.id;
      if r.desired = 'reserve' then
        -- CHANGED: was 'تم نقلك إلى قائمة الاحتياط بسبب تعديل عدد اللاعبين.'
        perform create_notification(r.user_id, p_match_id, 'moved_to_reserve', coalesce(v_title, ''));
      else
        -- CHANGED: was 'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.'
        perform create_notification(r.user_id, p_match_id, 'promoted', coalesce(v_title, ''));
      end if;
    end if;
  end loop;
end;
$$;

revoke execute on function public.rebalance_roster(uuid) from anon, authenticated, public;

-- 5) withdraw_from_match -------------------------------------------------------
create or replace function public.withdraw_from_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_match matches%rowtype; v_registration match_registrations%rowtype; v_promoted uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.status = 'completed' or v_match.end_at <= now() then raise exception 'MATCH_CLOSED'; end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  select * into v_registration from match_registrations where match_id = p_match_id and user_id = auth.uid();
  if not found then raise exception 'NOT_REGISTERED'; end if;
  delete from match_registrations where id = v_registration.id;
  if v_registration.status = 'confirmed' then
    update match_registrations set status = 'confirmed'
    where id = (select id from match_registrations where match_id = p_match_id and status = 'reserve' order by registration_order limit 1)
    returning user_id into v_promoted;
    if v_promoted is not null then
      -- CHANGED: was 'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.'
      perform create_notification(v_promoted, p_match_id, 'promoted', v_match.title);
    end if;
  end if;
  perform recompute_match_status(p_match_id);
end;
$$;

revoke execute on function public.withdraw_from_match(uuid) from anon, public;
grant execute on function public.withdraw_from_match(uuid) to authenticated;

-- 6) purge_membership ----------------------------------------------------------
-- The loop already joins `matches`; it now selects one more column from that
-- join, so each notice names its own match — this producer touches several.
create or replace function public.purge_membership(p_community_id uuid, p_user_id uuid)
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
    -- CHANGED: `m.title` added to the existing join. No extra query.
    select mr.id, mr.status, mr.match_id, m.title
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
            -- CHANGED: was 'تمت ترقيتك من قائمة الاحتياط إلى الأساسيين.'
            coalesce(r.title, ''));
      end if;
    end if;
    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;
end;
$$;

revoke execute on function public.purge_membership(uuid, uuid) from anon, authenticated, public;
