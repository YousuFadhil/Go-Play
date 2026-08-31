-- The historical-match registration guard, on the overload that is actually
-- called.
--
-- **This migration exists because the database had drifted from this folder.**
-- `0054` put the guard on `register_player_in_match(uuid, uuid)`, which is the
-- signature migration `0041` defines and the only one any file here declares.
-- The live project has since grown a third parameter —
-- `register_player_in_match(uuid, uuid, boolean)` — and it is that overload both
-- callers use:
--
--   register_for_match(...)        -> register_player_in_match(m, auth.uid(), true)
--   admin_add_player_to_match(...) -> register_player_in_match(m, u,         false)
--
-- so `0054`'s guard protected nothing. This puts it where the calls go. The
-- two-argument version keeps its guard as well: it is unreachable today, and a
-- guard on an unreachable function costs nothing while an unguarded one waiting
-- to be reached costs a rule.
--
-- **It matters more than a tidy-up.** `admin_add_player_to_match` passes
-- `p_enforce_time_lock => false`, so the kickoff and end-time refusals are
-- deliberately skipped for an organizer adding somebody. A recorded match is in
-- the past by definition, which means that without this guard an organizer could
-- register a player into one through the ordinary registration path — giving a
-- fixture that has already been played a roster the reserve rules then apply to.
-- The guard is what makes "a recorded match takes no registration" a rule rather
-- than a side effect of a clock comparison that this caller turns off.
--
-- **The drift itself is left alone.** The three-argument overload, the
-- `p_enforce_time_lock` flag and the callers that pass it are not described by
-- any migration in this folder, and reconciling that is its own piece of work
-- with its own review. What is done here is the smallest thing that makes the
-- approved rule true in the database as it actually is.
--
-- The body below is the live definition, statement for statement, with one line
-- added. Nothing else about registration changes: the manual/registration order
-- split, the guest-aware confirmed count, `rebalance_roster` and the re-read of
-- the resulting status are all exactly as they were.
create or replace function public.register_player_in_match(
  p_match_id uuid,
  p_user_id uuid,
  p_enforce_time_lock boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_community int;
  v_status text;
  v_order int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;
  perform 1 from users where id = p_user_id for update;

  -- THE ONLY ADDITION.
  --
  -- Outside `p_enforce_time_lock` on purpose. That flag says whether the caller
  -- may register somebody into a match that has started, which is an organizer's
  -- privilege over a live fixture. This is not that: a recorded match has no
  -- registration to make at all, for anybody, and no caller may turn it off.
  if v_match.is_historical then raise exception 'MATCH_HISTORICAL'; end if;

  if p_enforce_time_lock then
    if v_match.status = 'completed' or v_match.end_at <= now() then
      raise exception 'MATCH_CLOSED';
    end if;
    if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;
  end if;
  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;
  if exists (select 1 from match_registrations
             where match_id = p_match_id and user_id = p_user_id) then
    raise exception 'ALREADY_REGISTERED';
  end if;
  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;
  if exists (
    select 1 from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = p_user_id
      and m.status in ('open', 'full')
      and m.end_at > now()
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;
  if v_match.roster_order_mode = 'manual' then
    v_status := case when v_total + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  else
    select count(*) into v_community
    from match_registrations
    where match_id = p_match_id and user_id is not null;
    v_status := case when v_community + 1 <= v_match.starting_players
                     then 'confirmed' else 'reserve' end;
  end if;
  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;
  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);
  perform rebalance_roster(p_match_id);
  select status into v_status from match_registrations
  where match_id = p_match_id and user_id = p_user_id;
  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

revoke execute on function public.register_player_in_match(uuid, uuid, boolean)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid, boolean)
  to service_role;
