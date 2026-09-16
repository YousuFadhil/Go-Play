-- ============ migrations/0078_package_five_public_sharing.sql ============
-- Package 5: the Player Profile's football record, and the public surface a
-- shared link lands on.
--
-- Four things are added and nothing existing is loosened:
--
--   1. `player_recent_form`      -- the player's last N completed matches
--   2. `player_recent_mvp`       -- the player's most recent MVP award
--   3. the `public_*` contracts  -- the only relations `anon` gains here
--   4. share metadata on `product_events`, plus one new event name
--
-- ## THE BOUNDARY THIS MIGRATION KEEPS
--
-- `0057` drew the line that football *history* is for people with an account,
-- and `0056` drew the line that account data belongs to its owner. Neither
-- moves. In particular this migration does **not**:
--
--   * grant `anon` execute on `player_profile(uuid)`;
--   * grant `anon` select on `v_football_completed_matches` or on any other
--     view `0057`/`0073` restricted to `authenticated`;
--   * grant `anon` anything on a base table;
--   * create any path by which an unauthenticated caller can WRITE.
--
-- What `anon` gains is four functions with hand-written column lists. They are
-- `security definer`, so they see past RLS -- which is exactly why the column
-- list rather than the policy is what bounds them, the same argument
-- `player_profile` is built on. A caller cannot ask for a column that is not
-- written out below, so there is no phone number, no email, no authentication
-- identifier, no date of birth, no `owner_id`, no `created_by`, no `join_code`
-- and no administrative field to be had through any of them, whatever is
-- asked for.
--
-- ## COMPLETED MATCHES STAY BEHIND A SESSION
--
-- `public_match_detail` answers for a match that is **already public** and for
-- no other: it reads `v_public_upcoming_matches`, so its filter is that view's
-- filter by construction rather than by a second copy of it that could drift.
-- A completed match returns no rows there to anybody -- a guest who opens a
-- link to one is asked to sign in, and the authenticated surfaces are
-- untouched. Widening that is a product decision and is not taken here.
--
-- `public_player_recent_form` is the same argument applied to a player: it
-- returns the *shape* of the last five results and the player's own goals in
-- them, and deliberately no `match_id`, no `community_id` and no kick-off
-- time. A W-D-W-W-L sequence is the player's record; which fixtures produced
-- it is football history and stays where `0057` put it.
--
-- ## ANALYTICS STAYS AUTHENTICATED
--
-- `product_events.user_id` remains `not null`, `record_product_event` still
-- takes its actor from `auth.uid()` and still refuses `anon`, and no second
-- writer is created. A link opened by a signed-out visitor is therefore not
-- recorded, which is a deliberate and approved trade: measuring it would mean
-- an unauthenticated INSERT path, and that is a larger surface than the metric
-- is worth. The event is recorded when a signed-in reader opens a public link.
--
-- Append-only. Nothing in `0022`-`0077` is edited.



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
  'public_player_recent_form -- see migration 0078.';

revoke execute on function public.player_recent_form(uuid, int)
  from anon, public;
grant execute on function public.player_recent_form(uuid, int)
  to authenticated;
grant execute on function public.player_recent_form(uuid, int)
  to service_role;



-- ============================================================================
-- 2) player_recent_mvp() -- the most recent MVP award
-- ============================================================================
-- The MVP half of Recent Highlight, and the only half a database can answer.
--
-- **Team of Period is deliberately absent, and that is not an omission to be
-- fixed here.** A Period XI is *selected* by `TeamOfPeriodSelector` in the
-- Flutter client from the evidence `community_period_xi_evidence` (`0070`,
-- `0077`) returns; the database stores no XI and decides no seat. Answering
-- "was this player in a Team of Period" in SQL would mean a second
-- implementation of that selection, which is precisely the duplicate source of
-- truth the approved scope forbids. So this function answers MVP, the client
-- resolves the highlight between MVP and any XI it has actually selected, and
-- the tie rule lives in one place above.
--
-- `occurred_at` is the match's kick-off, which is how every other statistics
-- surface dates football (`0060`: a match is placed by `start_at`, never by
-- when the row was written).
create or replace function public.player_recent_mvp(p_user_id uuid)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  occurred_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    m.id,
    m.community_id,
    c.name,
    m.start_at
  from match_results r
  join matches m     on m.id = r.match_id
  join communities c on c.id = m.community_id and c.is_active
  where r.mvp_user_id = p_user_id
    and (m.status = 'completed' or m.end_at <= now())
  order by m.start_at desc, m.id desc
  limit 1;
$$;

comment on function public.player_recent_mvp(uuid) is
  'The player''s most recent MVP award, or no row. Dated by the match''s '
  'start_at, as every other statistics surface dates football. Team of Period '
  'is not here because no XI is stored: it is selected client-side from '
  'community_period_xi_evidence, and a SQL re-implementation would be a second '
  'source of truth -- see migration 0078.';

revoke execute on function public.player_recent_mvp(uuid) from anon, public;
grant execute on function public.player_recent_mvp(uuid) to authenticated;
grant execute on function public.player_recent_mvp(uuid) to service_role;



-- ============================================================================
-- 3) The public contracts -- the only thing `anon` gains in this migration
-- ============================================================================
-- Three functions for a player and one for a match. Each writes out every
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
  '-- see migration 0078.';

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
  'without disclosing the fixtures behind it -- see migration 0078.';

revoke execute on function public.public_player_recent_form(uuid, int)
  from public;
grant execute on function public.public_player_recent_form(uuid, int)
  to anon, authenticated, service_role;

-- --- 3c) The public Recent Highlight ------------------------------------------
-- At most one row, and only the MVP kind -- see section 2 for why Team of
-- Period is not answerable here. The community's name is carried because a
-- community's name is already public (`v_public_communities`, `0033`); the
-- match behind the award is not.
create or replace function public.public_player_recent_highlight(p_user_id uuid)
returns table (
  highlight_type text,
  occurred_at timestamptz,
  community_name text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    'MVP'::text,
    h.occurred_at,
    h.community_name
  from public.player_recent_mvp(p_user_id) h
  join users u on u.id = p_user_id and u.is_active;
$$;

comment on function public.public_player_recent_highlight(uuid) is
  'The public Recent Highlight: at most one row, MVP only, for an active '
  'player. Team of Period is selected client-side and is therefore resolved '
  'above this function rather than inside it -- see migration 0078.';

revoke execute on function public.public_player_recent_highlight(uuid)
  from public;
grant execute on function public.public_player_recent_highlight(uuid)
  to anon, authenticated, service_role;

-- --- 3d) The public match ------------------------------------------------------
-- One publicly visible match, by id.
--
-- **Its filter is `v_public_upcoming_matches`, not a copy of it.** Selecting
-- from the view is what guarantees this function can never answer for a match
-- the public discovery surface would not already list: change the view's rule
-- and this changes with it, in one edit rather than two.
--
-- So a completed match, a match in a deactivated community and a match that has
-- finished all return no rows, to everybody. That is `0057`'s boundary, and a
-- guest who opens a link to a played match is asked to sign in rather than
-- shown a score.
create or replace function public.public_match_detail(p_match_id uuid)
returns table (
  match_id uuid,
  community_id uuid,
  community_name text,
  title text,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  status text,
  starting_players int,
  open_slots int
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
    v.title,
    v.location,
    v.start_at,
    v.end_at,
    v.status,
    v.starting_players,
    v.open_slots
  from v_public_upcoming_matches v
  where v.id = p_match_id;
$$;

comment on function public.public_match_detail(uuid) is
  'One publicly visible match by id, for the /match/{id} link. Reads '
  'v_public_upcoming_matches, so it can only ever answer for a match public '
  'discovery already lists -- a completed match, a finished match or a match '
  'in an inactive community returns no rows. No roster, no result, no '
  'organiser -- see migration 0078.';

revoke execute on function public.public_match_detail(uuid) from public;
grant execute on function public.public_match_detail(uuid)
  to anon, authenticated, service_role;

-- A community needs no function of its own. `/community/{id}` is answered by
-- `v_public_communities`, which `0033` already granted to `anon` and `0061`
-- already extended with the logo -- a second public model of the same thing
-- would be a second place the public community surface is decided.



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
  'Null on every event that is not a share -- see migration 0078.';
comment on column public.product_events.source is
  'The screen or context a share or a public-link open came from, bounded to '
  '64 characters by the writer. A free string deliberately: the list of '
  'screens grows with the product -- see migration 0078.';

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
  'The one writer for product_events (migrations 0067, 0078). Records the '
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
