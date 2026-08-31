-- Recording a match that has already been played.
--
-- An owner or admin can now enter a fixture the community played last week and
-- never registered here. Everything after the creation step already existed:
-- `set_completed_match_player` (0029) selects who actually played,
-- `replace_match_lineup` (0020/0029) stores the two sides, and
-- `record_match_result` (0022/0033/0049) takes the score, the scorers and the
-- MVP. None of those three is touched by this migration, and none of them
-- needed to be — all three already operate on a match whose end time has
-- passed.
--
-- What was missing was the front door. `create_match` refuses any start in the
-- past, so the one thing that could not be done was to say the match happened.
--
-- This migration does three things and nothing else:
--
--   1. `matches.is_historical` — one column, defaulted, so a recorded match is
--      a fact about the row rather than an inference from its dates.
--   2. `create_match` — one new parameter, which selects between two temporal
--      rules. A normal match is validated exactly as it is today.
--   3. `register_player_in_match` — one new guard, so a historical match can
--      never take a registration through any path.
--
-- **No new lifecycle status.** `open | full | completed` is unchanged. A
-- historical match is `completed` for every purpose in the product already:
-- `v_completed_matches` (0037) selects `status = 'completed' or end_at <=
-- now()`, `v_upcoming_matches` (0025) requires `start_at > now()`, and
-- `Match.effectiveStatus` in the client derives completion from `end_at`. A
-- fourth status would be a second way of saying what the end time already says.
--
-- **No new RLS policy.** `is_historical` rides on the `matches` policies that
-- already decide who may read and write a match row. It grants nothing and
-- reveals nothing that `start_at` does not.
--
-- **Forward-safe.** The column is `not null default false`, so every existing
-- row becomes `false` — which is true of every one of them: before this
-- migration no match could be created in the past. Nothing is rewritten, no
-- result or lineup is touched, and no historical record is altered.

-- 1) The marker ----------------------------------------------------------------
-- Why a column rather than a derivation.
--
-- The dates almost say it: a match created in the past has `end_at <
-- created_at`, and a normal one cannot, because `create_match` refuses a start
-- that has passed. But "almost" is the problem. That inference is an artefact
-- of two other rules holding, it has to be re-derived by every reader that
-- cares, and it silently becomes wrong the moment either rule is relaxed. The
-- product needs to *state* which kind of match this is — the client labels it,
-- and the registration guard below refuses on it — so it is stated.
alter table public.matches
  add column if not exists is_historical boolean not null default false;

comment on column public.matches.is_historical is
  'True when this match is the record of a fixture that had already been '
  'played when it was created (migration 0054). It is the only match kind '
  'whose start and end times may be in the past, and it never takes a '
  'registration: see register_player_in_match.';

-- 2) Creating one --------------------------------------------------------------
-- `create_match` gains `p_is_historical` and nothing else changes.
--
-- **The old signature is dropped rather than replaced.** `create or replace`
-- with a different argument count creates an *overload*, and the seven-argument
-- version would stay callable — which would leave the past-date refusal
-- reachable by anyone who called the old shape, and, worse, would make which
-- rule applied depend on how many arguments a client happened to send. One
-- function, one rule. `0049` dropped `record_match_result` for the same reason.
--
-- The new parameter has a default, so every existing seven-argument caller —
-- including the current released client — keeps working and keeps getting
-- today's behaviour.
--
-- Everything else below is reproduced verbatim from `0039`, because a function
-- has no partial redefinition. Diff this against
-- `0039_match_created_notification.sql` and the temporal branch, the insert
-- column and the notification condition are the whole of it.
drop function if exists public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
);

create or replace function public.create_match(
  p_community_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players integer,
  p_description text default null,
  p_is_historical boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
  v_match_id uuid;
  v_historical boolean := coalesce(p_is_historical, false);
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_community from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if not v_community.is_active then raise exception 'COMMUNITY_INACTIVE'; end if;

  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_location is null or char_length(trim(p_location)) < 2 then
    raise exception 'INVALID_LOCATION';
  end if;
  if p_start_at is null or p_end_at is null then
    raise exception 'INVALID_TIME_RANGE';
  end if;

  -- Unchanged and unconditional: a match ends after it starts, whenever it was
  -- played. The historical path relaxes *when* a match may be, never whether
  -- its own two ends are the right way round.
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;

  -- THE TEMPORAL BRANCH ---------------------------------------------------------
  -- Two rules, and a match is under exactly one of them.
  --
  -- A normal match must still be entirely ahead of the caller: the refusal is
  -- the same statement, in the same place, with the same error name, so nothing
  -- about creating an ordinary fixture changes and an accidental past date is
  -- still refused.
  --
  -- A historical match must be entirely behind them. That second half is not
  -- symmetry for its own sake: without it "historical" would be a flag a client
  -- could set on a fixture next Friday, and the match would then be a record of
  -- something that has not happened — readable as completed by
  -- `v_completed_matches` the moment it was written, and closed to the
  -- registration its players were waiting for. `end_at` is the one that is
  -- tested because `end_at > start_at` was just established, so a match that has
  -- ended is a match that has wholly happened.
  if v_historical then
    if p_end_at > now() then raise exception 'HISTORICAL_NOT_PAST'; end if;
  else
    if p_start_at <= now() then raise exception 'START_IN_PAST'; end if;
  end if;
  -- END OF THE TEMPORAL BRANCH ---------------------------------------------------

  if p_starting_players is null
     or p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  -- max_registration is omitted on purpose: matches_set_capacity fills it.
  --
  -- It is left alone for a historical match too, though the reserve allowance it
  -- derives can never be used by one. Capacity is what `add_professional_guest`
  -- checks when an admin adds a stand-in who actually played, and narrowing it
  -- here would cap the recorded squad at the starting count for no reason the
  -- product asked for.
  insert into matches (
    community_id, created_by, title, location,
    start_at, end_at, starting_players, description, is_historical
  )
  values (
    p_community_id,
    auth.uid(),
    trim(p_title),
    trim(p_location),
    p_start_at,
    p_end_at,
    p_starting_players,
    case
      when p_description is null or trim(p_description) = '' then null
      else trim(p_description)
    end,
    v_historical
  )
  returning id into v_match_id;

  -- Announce it to the community, every member except the admin who just made
  -- it. `0039`'s statement, now with one condition on it.
  --
  -- **A historical match announces nothing.** The notice exists to reach people
  -- who have not acted yet, so they can come and register — and there is nothing
  -- for them to act on here. The fixture was played; the guard below makes sure
  -- nobody can register for it; and 'مباراة جديدة' would be false about a match
  -- that already finished. Suppressing it is the notice's own rule, so it lives
  -- with the notice.
  if not v_historical then
    perform create_notification(
        cm.user_id,
        v_match_id,
        'match_created',
        trim(p_title) || ' — ' || trim(p_location)
    )
    from community_members cm
    where cm.community_id = p_community_id
      and cm.user_id <> auth.uid();
  end if;

  return v_match_id;
end;
$$;

-- The drop above took the privileges with it, so these are the definition's
-- again rather than a leftover of the order the migrations ran in.
revoke execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text, boolean
) from anon, public;
grant execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text, boolean
) to authenticated;

-- 3) Registration, refused ------------------------------------------------------
-- One guard, in the one place both registration paths go through.
--
-- A historical match is already unreachable by registration today, because
-- every path refuses a match whose start has passed (`MATCH_LOCKED`) or whose
-- end has (`MATCH_CLOSED`), and a historical match is both. So this changes no
-- outcome. It changes what the refusal *means*: "you may not register for a
-- match that has been played" is the product's rule, and leaving it to be an
-- emergent consequence of two clock comparisons would make it true by accident.
-- It is also what keeps the rule authoritative in the one layer that can be —
-- the client's `isOpenForChanges` decides what to draw, never what is allowed.
--
-- `register_player_in_match` is where it goes because it is the shared middle of
-- both flows: `register_for_match` (a player registering themselves) and
-- `admin_add_player_to_match` (an owner or admin registering somebody else)
-- both call it, so one guard closes both, and no third path can be added later
-- that misses it.
--
-- The reserve queue needs no guard of its own. A reserve seat is a row this
-- function writes, `next_reserve_registration` and `rebalance_roster` only ever
-- promote rows that exist, and `set_completed_match_player` writes `confirmed`
-- directly. With this refusal in place a historical match cannot hold a reserve
-- row at all, so there is nothing for promotion to find.
--
-- Everything else is `0041`'s body, statement for statement.
create or replace function public.register_player_in_match(
  p_match_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_confirmed int;
  v_status text;
  v_order int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  perform 1 from users where id = p_user_id for update;

  -- THE ONLY ADDITION -----------------------------------------------------------
  -- Ahead of the lifecycle checks, because it is not a lifecycle fact. A
  -- historical match is not closed, or locked, or full: it is a record of
  -- something that already happened, and the reason it takes no registration is
  -- that there is nothing left to register for.
  if v_match.is_historical then raise exception 'MATCH_HISTORICAL'; end if;
  -- END OF THE ADDITION ---------------------------------------------------------

  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;

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

  select count(*) into v_confirmed from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  v_status := case when v_confirmed < v_match.starting_players
                   then 'confirmed' else 'reserve' end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);

  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

-- `create or replace` keeps the existing privileges. Restated for the same
-- reason `0041` states them: this helper asks nobody's permission, so it stays
-- unreachable by a client under any role.
revoke execute on function public.register_player_in_match(uuid, uuid)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid)
  to service_role;
