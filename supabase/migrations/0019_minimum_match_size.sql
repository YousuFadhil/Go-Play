-- The minimum supported match is 4 players (2 v 2).
--
-- Product Owner decision, 2026-07-31, recorded as `OP-2` in §18.1.1 of
-- `Docs/engineering/BTGE_Engineering_Specification.md`. It supersedes the
-- earlier approval of 6 and the original schema range of 2, and it applies to
-- the product as a whole rather than to team generation alone: a match Go Play
-- does not support should not be creatable in the first place.
--
-- Two server-side rules still carried the old lower bound of 2 — the CHECK on
-- matches.starting_players from 0006, and the guard inside update_match, last
-- rewritten by 0013. Both move to 4. Nothing else changes.
--
-- Verified before applying: no row in public.matches has starting_players
-- below 4 (2 matches, minimum 4), so the constraint holds over existing data
-- and no row is rewritten.
--
-- Deliberately unchanged: reserve capacity. max_registration is still derived
-- as starting_players + app_settings.reserve_players by matches_set_capacity,
-- and matches_max_registration_check still spans 2 to 60 — that constraint
-- governs a derived value, not the product minimum, and narrowing it is not
-- part of this decision.

-- 1) The capacity constraint ---------------------------------------------------
alter table public.matches
  drop constraint if exists matches_starting_players_check;
alter table public.matches
  add constraint matches_starting_players_check
    check (starting_players between 4 and 30);

-- 2) The edit guard ------------------------------------------------------------
-- Reproduced from 0013 with one line changed: the lower bound of the
-- INVALID_STARTING_PLAYERS check. Every other guard, the update itself, the
-- roster rebalance, the status recomputation and the notification are byte for
-- byte what 0013 established.
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
      'تم تعديل تفاصيل المباراة.')
  from match_registrations mr where mr.match_id = p_match_id;
end;
$$;
