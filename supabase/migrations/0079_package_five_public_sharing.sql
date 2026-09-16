-- ============ migrations/0079_package_five_public_sharing.sql ============
-- Package 5: the Player Profile's football record, and the public surface a
-- shared link lands on.
--
-- Five things are added and nothing existing is loosened:
--
--   1. `player_recent_form`          -- the player's last N completed matches
--   2. Team of Period awards         -- stored snapshots of the existing
--                                       selector's output, and the highlight
--                                       read over them and over MVP awards
--   3. the `public_*` contracts      -- the only relations `anon` gains here
--   4. share metadata on `product_events`, plus one new event name
--
-- Numbered 0079 because `0078_rating_goal_mvp_values` was applied to the live
-- project from `main`. Nothing here touches the object that one replaces.
--
-- ## THE BOUNDARY THIS MIGRATION KEEPS
--
-- `0056` drew the line that account data belongs to its owner and it does not
-- move. This migration does **not**:
--
--   * grant `anon` execute on `player_profile(uuid)`;
--   * grant `anon` select on any `v_football_*` view, or on any table;
--   * grant `anon` the Team of Period evidence functions;
--   * create any path by which an unauthenticated caller can WRITE.
--
-- What `anon` gains is five functions with hand-written column lists. They are
-- `security definer`, so they see past RLS -- which is exactly why the column
-- list rather than the policy is what bounds them, the same argument
-- `player_profile` is built on. A function may *read* an authenticated view
-- internally, running as its owner; what it returns is still only the columns
-- written out below. Reading the view rather than re-deriving its joins is what
-- keeps one definition of a lineup, a goal and an MVP.
--
-- ## COMMUNITY VISIBILITY (APPROVED FOR PACKAGE 5)
--
-- There is no private community. Since `0016` every active community is
-- discoverable and `join_policy` (`OPEN` / `CODE_REQUIRED`) decides how one is
-- joined, never whether it is seen. So the single visibility rule every public
-- function below applies is `communities.is_active`: an active community's
-- public matches and results are public, whatever its join policy, and an
-- inactive or suspended community's are not -- to anybody, through any of them.
--
-- ## COMPLETED MATCHES
--
-- `0057` kept completed-match history behind a session. Package 5 approves one
-- narrow exception: a match opened *by id* through `/match/{id}` shows its
-- result and lineup, because a shared result card must not lead to a dead link.
-- Browsing history, rosters of upcoming matches and every `v_football_*` view
-- stay authenticated.
--
-- `public_player_recent_form` is unchanged by that exception: it returns the
-- shape of the last five results and the player's own goals in them, with no
-- match id, community id or kick-off time.
--
-- ## ANALYTICS STAYS AUTHENTICATED
--
-- `product_events.user_id` remains `not null`, `record_product_event` still
-- takes its actor from `auth.uid()` and still refuses `anon`, and no second
-- writer is created. A link opened by a signed-out visitor is not recorded.
--
-- Append-only. Nothing in `0022`-`0078` is edited.



-- ============================================================================
-- 1) player_recent_form() -- the last N completed matches, newest first
-- ============================================================================
-- **It does not decide what a win is.** `match_result_contribution` (migrations
-- `0023`, `0046`) is what turns a result and a team assignment into
-- played/won/lost/drawn/scored/mvp for one player, and it is the same function
-- `apply_match_statistics` feeds the career counters from. Recent Form joins it
-- rather than restating its `case` expressions, so the five badges on a profile
-- and the totals above them cannot disagree about the same match.
--
-- **Bounded twice.** The window is chosen first, with a `limit`, and the
-- contribution is computed only for the rows that survived it -- so the lateral
-- runs five times and not once per match the player has ever played. `p_limit`
-- is clamped to 1..10 whatever is passed: this is a profile ornament, not a
-- history API, and an unbounded read is the thing the approved scope rules out.
--
-- A Professional Guest has no row here: `match_result_contribution` already
-- excludes a null `user_id`, and a guest has no profile to put form on.
create or replace function public.player_recent_form(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  start_at timestamptz,
  -- 'WIN', 'DRAW' or 'LOSS'. One of the three always applies: a recorded result
  -- has two scores, and the three cases are exhaustive over them.
  outcome text,
  goals int,
  is_mvp boolean
)
language sql
security definer
stable
set search_path = public
as $$
  with recent as (
    select
      m.id         as match_id,
      m.community_id,
      c.name       as community_name,
      m.start_at
    from match_team_assignments a
    join matches m       on m.id = a.match_id
    join communities c   on c.id = m.community_id and c.is_active
    join match_results r on r.match_id = m.id
    where a.user_id = p_user_id
      -- The project's own definition of completed (`0029`, `0037`).
      and (m.status = 'completed' or m.end_at <= now())
    order by m.start_at desc, m.id desc
    limit least(greatest(coalesce(p_limit, 5), 1), 10)
  )
  select
    recent.match_id,
    recent.community_id,
    recent.community_name,
    recent.start_at,
    case
      when k.won  = 1 then 'WIN'
      when k.lost = 1 then 'LOSS'
      else 'DRAW'
    end,
    k.scored,
    k.mvp = 1
  from recent
  join lateral match_result_contribution(recent.match_id) k
    on k.user_id = p_user_id
  order by recent.start_at desc, recent.match_id desc;
$$;

comment on function public.player_recent_form(uuid, int) is
  'One player''s last N completed matches, newest first, as outcome, goals and '
  'MVP. Derived from match_result_contribution -- the same function the career '
  'counters are applied from -- so form and totals describe one truth. p_limit '
  'is clamped to 1..10. Readable by any signed-in player, exactly as '
  'player_profile is; anon reaches the reduced form through '
  'public_player_recent_form -- see migration 0079.';

revoke execute on function public.player_recent_form(uuid, int)
  from anon, public;
grant execute on function public.player_recent_form(uuid, int)
  to authenticated;
grant execute on function public.player_recent_form(uuid, int)
  to service_role;



-- ============================================================================
-- 2) Team of Period awards -- the selector's output, stored once a period ends
-- ============================================================================
-- **The database stores an award; it never decides one.** A Period XI is
-- selected by `TeamOfPeriodSelector`, in Dart, from the evidence
-- `community_period_xi_evidence` returns. That remains the only selection
-- algorithm. What is added here is somewhere to keep its answer for a period
-- that has *ended*, so that "was this player in a Team of Period" is one
-- indexed lookup instead of a re-run of the selection for every community a
-- player belongs to.
--
-- Approved semantics (Package 5):
--
--   * one snapshot per community + period, and one award row per selected
--     player in it;
--   * a snapshot is written only for a closed period, and once written it is
--     final -- a later result correction does not rewrite it;
--   * nothing is backfilled here;
--   * the only writer is `service_role`; clients read awards only through the
--     bounded highlight functions below.

-- --- 2a) Storage -------------------------------------------------------------
create table if not exists public.team_of_period_snapshots (
  id uuid primary key default gen_random_uuid(),
  -- Cascades because `delete_community` hard-deletes, and an award for a
  -- community that no longer exists describes nothing.
  community_id uuid not null
    references public.communities (id) on delete cascade,
  period_type text not null
    constraint team_of_period_snapshots_period_type_check
      check (period_type in ('weekly', 'monthly')),
  -- The same key `statistics_period_key` gives the statistics counters, and the
  -- same half-open [start, end) bounds in Asia/Muscat the evidence reads use.
  period_key text not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  -- The selector's own three outcomes. A period with no team is still a period
  -- that was evaluated, which is why the header exists without awards.
  state text not null
    constraint team_of_period_snapshots_state_check
      check (state in (
        'SELECTED', 'NO_QUALIFYING_MATCHES', 'INSUFFICIENT_ELIGIBLE_PLAYERS'
      )),
  target_size int not null
    constraint team_of_period_snapshots_target_size_check
      check (target_size between 0 and 11),
  -- Diagnostics: what the evidence looked like and which selector produced
  -- this. Neither is read to decide anything.
  evidence_last_changed_at timestamptz,
  selector_version text not null,
  produced_at timestamptz not null default now(),
  constraint team_of_period_snapshots_period_bounds_check
    check (period_start < period_end),
  constraint team_of_period_snapshots_one_per_period
    unique (community_id, period_type, period_key)
);

create table if not exists public.team_of_period_awards (
  snapshot_id uuid not null
    references public.team_of_period_snapshots (id) on delete cascade,
  -- No foreign key to `users`, for the reason `product_events` has none: the
  -- legacy admin_delete_* RPCs hard-delete, and an FK would either block them
  -- or silently rewrite the record. Readers join `users` and require
  -- `is_active`, so an award for a removed player is simply never shown.
  user_id uuid not null,
  assigned_position text not null
    constraint team_of_period_awards_position_check
      check (assigned_position in ('GK', 'DEF', 'MID', 'FWD')),
  rank_in_role int not null
    constraint team_of_period_awards_rank_check check (rank_in_role >= 1),
  constraint team_of_period_awards_pkey primary key (snapshot_id, user_id)
);

-- "This player's most recent award" is the one question these tables answer.
create index if not exists team_of_period_awards_user_idx
  on public.team_of_period_awards (user_id);

-- No client reaches either table. RLS on with no policy denies every client
-- role every row; the privileges are revoked as well so the denial does not
-- rest on RLS alone.
alter table public.team_of_period_snapshots enable row level security;
alter table public.team_of_period_awards enable row level security;
revoke all on table public.team_of_period_snapshots
  from anon, authenticated, public;
revoke all on table public.team_of_period_awards
  from anon, authenticated, public;

comment on table public.team_of_period_snapshots is
  'One stored Team of Period evaluation per community and closed period, '
  'produced from the existing TeamOfPeriodSelector result by a service-role '
  'writer. Final once written. No client privileges -- see migration 0079.';
comment on table public.team_of_period_awards is
  'The players a stored Team of Period snapshot selected, one row each. Read '
  'only through player_recent_highlights / public_player_recent_highlight -- '
  'see migration 0079.';

-- --- 2b) The one writer --------------------------------------------------------
-- `service_role` only. It checks that what it is handed is a real, closed,
-- canonical period and an internally consistent award, and it refuses to write
-- a second snapshot for a period that already has one. It does **not** check
-- the ranking: that would mean re-running the selection in SQL, which is the
-- duplicate algorithm this design exists to avoid. The trust boundary is the
-- service-role key, which no client holds.
create or replace function public.record_team_of_period_snapshot(
  p_community_id uuid,
  p_period_type text,
  p_period_key text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_state text,
  p_target_size int,
  p_evidence_last_changed_at timestamptz,
  p_selector_version text,
  p_awards jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone text;
  v_expected_start timestamptz;
  v_expected_end timestamptz;
  v_award_count int;
  v_snapshot_id uuid;
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  -- The period must be the canonical one, not merely a pair of instants.
  v_zone := public.statistics_period_zone();
  if p_period_type = 'weekly' then
    select w.period_start, w.period_end
      into v_expected_start, v_expected_end
    from public.current_statistics_week_at(p_period_start) w;
  else
    v_expected_start :=
      date_trunc('month', p_period_start at time zone v_zone) at time zone v_zone;
    v_expected_end :=
      (date_trunc('month', p_period_start at time zone v_zone)
        + interval '1 month') at time zone v_zone;
  end if;

  if p_period_start is distinct from v_expected_start
     or p_period_end is distinct from v_expected_end
     or p_period_key is distinct from
          public.statistics_period_key(p_period_start, p_period_type) then
    raise exception 'PERIOD_IDENTITY_MISMATCH';
  end if;

  -- Closed periods only. A running week's XI changes every time a result is
  -- recorded, so it is never stored.
  if p_period_end > now() then
    raise exception 'PERIOD_NOT_CLOSED';
  end if;

  if not exists (select 1 from communities c where c.id = p_community_id) then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  if p_state is null or p_state not in (
    'SELECTED', 'NO_QUALIFYING_MATCHES', 'INSUFFICIENT_ELIGIBLE_PLAYERS'
  ) then
    raise exception 'INVALID_SNAPSHOT_STATE';
  end if;

  if p_awards is null or jsonb_typeof(p_awards) <> 'array' then
    raise exception 'INVALID_SNAPSHOT_AWARDS';
  end if;
  v_award_count := jsonb_array_length(p_awards);

  -- The selector's own invariants, restated as a consistency check: a team was
  -- chosen exactly when there are seats, and never more than eleven.
  if (p_state = 'SELECTED' and (v_award_count < 1 or v_award_count > 11))
     or (p_state <> 'SELECTED' and v_award_count <> 0)
     or v_award_count > coalesce(p_target_size, -1) then
    raise exception 'INVALID_SNAPSHOT_AWARDS';
  end if;

  if nullif(trim(coalesce(p_selector_version, '')), '') is null then
    raise exception 'INVALID_SELECTOR_VERSION';
  end if;

  -- Final once written. Checked before the insert for a stable error; the
  -- unique constraint is what guarantees it under concurrency.
  if exists (
    select 1 from team_of_period_snapshots s
    where s.community_id = p_community_id
      and s.period_type = p_period_type
      and s.period_key = p_period_key
  ) then
    raise exception 'SNAPSHOT_ALREADY_FINAL';
  end if;

  insert into team_of_period_snapshots (
    community_id, period_type, period_key, period_start, period_end,
    state, target_size, evidence_last_changed_at, selector_version
  )
  values (
    p_community_id, p_period_type, p_period_key, p_period_start, p_period_end,
    p_state, p_target_size, p_evidence_last_changed_at,
    left(trim(p_selector_version), 64)
  )
  returning id into v_snapshot_id;

  insert into team_of_period_awards (
    snapshot_id, user_id, assigned_position, rank_in_role
  )
  select v_snapshot_id, a.user_id, a.assigned_position, a.rank_in_role
  from jsonb_to_recordset(p_awards)
    as a(user_id uuid, assigned_position text, rank_in_role int);

  return v_snapshot_id;
end;
$$;

comment on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) is
  'The only writer of Team of Period snapshots. service_role only. Accepts the '
  'existing TeamOfPeriodSelector result for a closed, canonical period and '
  'refuses a second snapshot for the same period (SNAPSHOT_ALREADY_FINAL). '
  'Does not re-rank: there is one selection algorithm and it is not here -- '
  'see migration 0079.';

revoke execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) from anon, authenticated, public;
grant execute on function public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb
) to service_role;

-- --- 2c) The highlight candidates ---------------------------------------------
-- At most two rows: the player's most recent MVP award and their most recent
-- stored Team of Period award. **The choice between them is not made here.**
-- "Most recent wins, Team of Period breaks a same-day tie" is applied once, in
-- `RecentHighlight.mostRecent`, whichever function supplied the candidates.
--
-- Dated as approved: an MVP by its match's kick-off, a Team of Period by the
-- end of its period. The stored `period_end` is the half-open bound -- Monday
-- 00:00 for a week -- so the award is dated one millisecond before it, which
-- is the last instant of the period itself rather than the first of the next.
--
-- Both kinds require the community to be active: a suspended community's
-- awards, like its matches, are shown to nobody.
create or replace function public.player_recent_highlights(p_user_id uuid)
returns table (
  highlight_type text,
  occurred_at timestamptz,
  community_id uuid,
  community_name text,
  match_id uuid,
  period_type text
)
language sql
security definer
stable
set search_path = public
as $$
  (
    select
      'MVP'::text,
      m.start_at,
      m.community_id,
      c.name,
      m.id,
      null::text
    from match_results r
    join matches m     on m.id = r.match_id
    join communities c on c.id = m.community_id and c.is_active
    where r.mvp_user_id = p_user_id
      and (m.status = 'completed' or m.end_at <= now())
    order by m.start_at desc, m.id desc
    limit 1
  )
  union all
  (
    select
      'TEAM_OF_PERIOD'::text,
      s.period_end - interval '1 millisecond',
      s.community_id,
      c.name,
      null::uuid,
      s.period_type
    from team_of_period_awards a
    join team_of_period_snapshots s on s.id = a.snapshot_id
    join communities c on c.id = s.community_id and c.is_active
    where a.user_id = p_user_id
    order by s.period_end desc, s.period_type desc, s.id desc
    limit 1
  );
$$;

comment on function public.player_recent_highlights(uuid) is
  'A player''s highlight candidates for a signed-in reader: at most one MVP '
  '(dated by kick-off) and one stored Team of Period award (dated by period '
  'end), in active communities only. The client chooses between them -- see '
  'migration 0079.';

revoke execute on function public.player_recent_highlights(uuid)
  from anon, public;
grant execute on function public.player_recent_highlights(uuid)
  to authenticated;
grant execute on function public.player_recent_highlights(uuid)
  to service_role;



-- ============================================================================
-- 3) The public contracts -- the only thing `anon` gains in this migration
-- ============================================================================
-- Three functions for a player and two for a match. Each writes out every
-- column it can ever return; there is no `select *` and no row type from a
-- table anywhere below, which is what makes the disclosure reviewable by
-- reading this file rather than by reading `users`.
--
-- None of them consults `auth.uid()`, and that is the point: the answer a
-- visitor gets is the answer a signed-in reader gets for the same public URL,
-- so a link cannot show one person more than another. Everything a session
-- adds -- the richer form rows, the communities, the account controls -- is
-- reached through the authenticated functions, not by these returning more.

-- --- 3a) The public player profile --------------------------------------------
-- The identity half of `player_profile`, minus `is_self` (there is no session
-- to be self against) and minus nothing else: `player_profile` already carries
-- no date of birth, no phone, no email and no auth identifier, so the list
-- below is the same list and is written out again rather than delegated.
--
-- Delegating would have been the smaller file and the wrong one: it would put
-- `anon`'s disclosure at the mercy of a future edit to a function that was
-- approved for `authenticated`. Two lists that must be checked against each
-- other is the cost of the public one never widening by accident.
--
-- An inactive player has no public profile and no error either -- no rows, the
-- same answer a player who does not exist gets, so a guessed id cannot be used
-- to tell a suspended account from a fictional one.
create or replace function public.public_player_profile(p_user_id uuid)
returns table (
  user_id uuid,
  full_name text,
  primary_position text,
  secondary_position text,
  avatar_path text,
  overall_rating numeric,
  matches_played int,
  wins int,
  losses int,
  draws int,
  goals int,
  mvp_count int
)
language sql
security definer
stable
set search_path = public
as $$
  select
    u.id,
    u.full_name,
    u.primary_position,
    u.secondary_position,
    u.avatar_path,
    u.overall_rating,
    coalesce(ps.matches_played, 0),
    coalesce(ps.wins, 0),
    coalesce(ps.losses, 0),
    coalesce(ps.draws, 0),
    coalesce(ps.goals, 0),
    coalesce(ps.mvp_count, 0)
  from users u
  left join player_statistics ps on ps.user_id = u.id
  where u.id = p_user_id
    and u.is_active;
$$;

comment on function public.public_player_profile(uuid) is
  'The public Player Profile a /player/{id} link opens: name, positions, '
  'picture, Global Rating and career counters, for an active player. An '
  'explicit column list and nothing else -- no date of birth, phone, email or '
  'auth identifier can be reached through it. Executable by anon: this is the '
  'narrow public contract, and player_profile(uuid) remains authenticated-only '
  '-- see migration 0079.';

revoke execute on function public.public_player_profile(uuid) from public;
grant execute on function public.public_player_profile(uuid)
  to anon, authenticated, service_role;

-- --- 3b) The public Recent Form -----------------------------------------------
-- The reduced form: a sequence and what the player did in it. `position` is
-- 1 for the most recent match, so the caller need not carry a timestamp to
-- order five badges -- and cannot derive a fixture date from one either.
--
-- Nothing identifies the matches. `0057` keeps completed-match identity behind
-- a session and this does not go around it; a signed-in reader who wants to
-- know *which* matches calls `player_recent_form`.
create or replace function public.public_player_recent_form(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  -- `sequence_no`, not `position`: POSITION is a Postgres keyword and an OUT
  -- parameter named after one is a trap for whoever edits this next.
  sequence_no int,
  outcome text,
  goals int,
  is_mvp boolean
)
language sql
security definer
stable
set search_path = public
as $$
  select
    row_number() over (order by f.start_at desc, f.match_id desc)::int,
    f.outcome,
    f.goals,
    f.is_mvp
  from public.player_recent_form(p_user_id, p_limit) f
  join users u on u.id = p_user_id and u.is_active
  order by f.start_at desc, f.match_id desc;
$$;

comment on function public.public_player_recent_form(uuid, int) is
  'The public Recent Form: the last N results newest first, as sequence_no, '
  'outcome, goals and MVP, for an active player. Carries no match id, no '
  'community id and no kick-off time, so it discloses the player''s record '
  'without disclosing the fixtures behind it -- see migration 0079.';

revoke execute on function public.public_player_recent_form(uuid, int)
  from public;
grant execute on function public.public_player_recent_form(uuid, int)
  to anon, authenticated, service_role;

-- --- 3c) The public Recent Highlight ------------------------------------------
-- The same at most two candidates, reduced to what a visitor may see: the kind,
-- the date, the period type for a Team of Period, and the community's name.
-- No community id, no match id and no period key.
--
-- The name is shown only because `player_recent_highlights` already requires
-- the community to be active, and an active community's name is public
-- (`v_public_communities`, `0033`). A suspended community's name therefore
-- never reaches a visitor through this function.
create or replace function public.public_player_recent_highlight(p_user_id uuid)
returns table (
  highlight_type text,
  occurred_at timestamptz,
  community_name text,
  period_type text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    h.highlight_type,
    h.occurred_at,
    h.community_name,
    h.period_type
  from public.player_recent_highlights(p_user_id) h
  join users u on u.id = p_user_id and u.is_active;
$$;

comment on function public.public_player_recent_highlight(uuid) is
  'The public Recent Highlight candidates: at most one MVP and one stored Team '
  'of Period award, as kind, date, period type and community name, for an '
  'active player in active communities. No ids -- see migration 0079.';

revoke execute on function public.public_player_recent_highlight(uuid)
  from public;
grant execute on function public.public_player_recent_highlight(uuid)
  to anon, authenticated, service_role;

-- --- 3d) The public match ------------------------------------------------------
-- One match by id, upcoming or completed, in an active community.
--
-- **Two sources, and neither is re-derived.** An upcoming match is read from
-- `v_public_upcoming_matches`, which is already public. A completed one is read
-- from `v_football_completed_matches`, which is not -- the function reads it as
-- its owner and returns only the columns below; `anon` gains nothing on the
-- view. The two views' predicates are complements (`end_at > now() and status
-- <> 'completed'` against `status = 'completed' or end_at <= now()`), so a
-- match is at most one of them, and both require `communities.is_active`.
--
-- `public_state` says which it was, and the fields that belong to the other
-- state are null: an upcoming match has no score, and a completed match has no
-- open places.
create or replace function public.public_match_detail(p_match_id uuid)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  community_logo_url text,
  title text,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  public_state text,
  starting_players int,
  open_slots int,
  has_result boolean,
  team_a_score int,
  team_b_score int,
  mvp_display_name text,
  mvp_avatar_path text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    v.id,
    v.community_id,
    v.community_name,
    c.logo_url,
    v.title,
    v.location,
    v.start_at,
    v.end_at,
    'UPCOMING'::text,
    v.starting_players,
    v.open_slots,
    null::boolean,
    null::int,
    null::int,
    null::text,
    null::text
  from v_public_upcoming_matches v
  join communities c on c.id = v.community_id and c.is_active
  where v.id = p_match_id

  union all

  select
    f.match_id,
    f.community_id,
    f.community_name,
    c.logo_url,
    f.title,
    f.location,
    f.start_at,
    f.end_at,
    'COMPLETED'::text,
    null::int,
    null::int,
    f.has_result,
    f.team_a_score,
    f.team_b_score,
    f.mvp_display_name,
    f.mvp_avatar_path
  from v_football_completed_matches f
  join communities c on c.id = f.community_id and c.is_active
  where f.match_id = p_match_id;
$$;

comment on function public.public_match_detail(uuid) is
  'One match for the /match/{id} link, upcoming or completed, in an active '
  'community. Upcoming: when, where, capacity and open places. Completed: the '
  'score and the MVP''s name and picture. No roster of an upcoming match, no '
  'organiser, no join code -- see migration 0079.';

revoke execute on function public.public_match_detail(uuid) from public;
grant execute on function public.public_match_detail(uuid)
  to anon, authenticated, service_role;

-- --- 3e) The public lineup of a completed match --------------------------------
-- Completed matches only, by construction: `v_football_match_lineup` already
-- restricts itself to completed matches in active communities, so an upcoming
-- match returns no rows here and its roster is never public.
--
-- **`player_id` is the only identifier, and it is conditional.** It is the
-- participant's user id only when they are a registered player whose public
-- profile exists right now -- `users.is_active`, the same predicate
-- `public_player_profile` answers on. A Professional Guest, or a player whose
-- profile is not available, has a name and no id, so a visitor can follow a
-- name to `/player/{id}` exactly when that page would open.
create or replace function public.public_match_lineup(p_match_id uuid)
returns table (
  team text,
  assigned_position text,
  participant_type text,
  display_name text,
  avatar_path text,
  goals int,
  is_mvp boolean,
  player_id uuid
)
language sql
security definer
stable
set search_path = public
as $$
  select
    l.team,
    l.assigned_position,
    l.participant_type,
    l.display_name,
    l.avatar_path,
    l.goals::int,
    l.is_mvp,
    case when l.user_id is not null and u.is_active then l.user_id end
  from v_football_match_lineup l
  left join users u on u.id = l.user_id
  where l.match_id = p_match_id
  order by l.team, l.display_name;
$$;

comment on function public.public_match_lineup(uuid) is
  'The lineup of a completed match in an active community, for the /match/{id} '
  'link: side, position, name, picture, goals, MVP, and a player_id only for a '
  'registered player whose public profile is available. Upcoming matches '
  'return nothing -- see migration 0079.';

revoke execute on function public.public_match_lineup(uuid) from public;
grant execute on function public.public_match_lineup(uuid)
  to anon, authenticated, service_role;



-- ============================================================================
-- 4) Share analytics -- two columns and an eleventh event name
-- ============================================================================
-- The approved measurement is Share -> Public Link Open -> Signup, which needs
-- three things `0067` does not carry: what kind of thing was shared, where the
-- reader shared it from, and an event for a public link being opened.
--
-- **Both columns are nullable, and every existing row stays valid.** A
-- `session_started` has no share type; neither does a `share_used` recorded by
-- a build that predates this migration. Null means "not stated", which is the
-- honest reading of both.
--
-- **Neither column is a free-form bag.** `share_type` is a CHECK over the six
-- approved kinds, for the same reason `event_name` is: a client cannot invent a
-- seventh by typing one. `source` is a bounded string rather than a CHECK --
-- it names the screen a share started from, that list grows with the product,
-- and a constraint on it would make adding a screen a migration.
alter table public.product_events
  add column if not exists share_type text,
  add column if not exists source text;

alter table public.product_events
  drop constraint if exists product_events_share_type_check;
alter table public.product_events
  add constraint product_events_share_type_check
    check (share_type is null or share_type in (
      'player_profile',
      'player_statistics',
      'community',
      'match',
      'lineup',
      'result'
    ));

-- The eleventh name. Dropped and re-added rather than replaced, because a
-- CHECK constraint has no `or replace`; named deterministically so that a
-- constraint under a different name would fail here instead of at the first
-- write.
alter table public.product_events
  drop constraint product_events_event_name_check;
alter table public.product_events
  add constraint product_events_event_name_check
    check (event_name in (
      'session_started',
      'community_viewed',
      'community_created',
      'community_joined',
      'match_viewed',
      'match_registered',
      'match_withdrawn',
      'teams_viewed',
      'result_viewed',
      'share_used',
      'public_link_opened'
    ));

comment on column public.product_events.share_type is
  'What kind of thing a share_used event shared, from the six approved kinds. '
  'Null on every event that is not a share -- see migration 0079.';
comment on column public.product_events.source is
  'The screen or context a share or a public-link open came from, bounded to '
  '64 characters by the writer. A free string deliberately: the list of '
  'screens grows with the product -- see migration 0079.';

-- --- 4b) The one writer, extended ---------------------------------------------
-- `record_product_event` gains two parameters and keeps everything else:
-- `auth.uid()` is still the only source of the actor, a suspended account still
-- records nothing, `anon` still has no execute, and the event name is still
-- restated here so a rejected one arrives as INVALID_ANALYTICS_EVENT.
--
-- Dropped and recreated rather than replaced. Adding defaulted parameters would
-- create an *overload*, and a client that sends its arguments by name would
-- then match both signatures -- an ambiguity that fails at runtime, in the one
-- code path the product deliberately swallows every error from. Dropping the
-- old signature is also what stops an older build from writing rows with no
-- share metadata through a function nobody remembered was still there.
--
-- A drop takes the whole ACL with it, including the grant Supabase's default
-- rule made and no migration mentions, so every grant is restated below --
-- which is `0066`'s lesson and `0067`'s comment about it.
drop function if exists public.record_product_event(text, uuid, uuid, text, text);

create or replace function public.record_product_event(
  p_event_name text,
  p_community_id uuid default null,
  p_match_id uuid default null,
  p_platform text default null,
  p_app_version text default null,
  p_share_type text default null,
  p_source text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  if p_event_name is null or p_event_name not in (
    'session_started',
    'community_viewed',
    'community_created',
    'community_joined',
    'match_viewed',
    'match_registered',
    'match_withdrawn',
    'teams_viewed',
    'result_viewed',
    'share_used',
    'public_link_opened'
  ) then
    raise exception 'INVALID_ANALYTICS_EVENT';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  -- Restated for the same reason the event name is: a stable token rather than
  -- a raw constraint violation.
  if p_share_type is not null and p_share_type not in (
    'player_profile',
    'player_statistics',
    'community',
    'match',
    'lineup',
    'result'
  ) then
    raise exception 'INVALID_ANALYTICS_SHARE_TYPE';
  end if;

  insert into product_events (
    user_id, event_name, community_id, match_id, platform, app_version,
    share_type, source
  )
  values (
    v_user_id,
    p_event_name,
    p_community_id,
    p_match_id,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), ''),
    p_share_type,
    -- Bounded exactly as `app_version` is, and for the same reason: a free
    -- string from a client is fine as long as it cannot grow without limit.
    nullif(left(trim(coalesce(p_source, '')), 64), '')
  );
end;
$$;

comment on function public.record_product_event(
  text, uuid, uuid, text, text, text, text
) is
  'The one writer for product_events (migrations 0067, 0079). Records the '
  'event against auth.uid() -- there is still deliberately no user-id argument '
  '-- after checking that the caller is signed in, active, and naming an '
  'approved event, platform and share type. anon has no execute and there is '
  'no second writer: an unauthenticated link open is not recorded at all. '
  'Raises NOT_AUTHENTICATED, ACCOUNT_SUSPENDED, INVALID_ANALYTICS_EVENT, '
  'INVALID_ANALYTICS_PLATFORM or INVALID_ANALYTICS_SHARE_TYPE; the client '
  'swallows all five, because analytics never blocks a product flow.';

revoke execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text)
  from anon, public;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text)
  to authenticated;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text, text, text)
  to service_role;
