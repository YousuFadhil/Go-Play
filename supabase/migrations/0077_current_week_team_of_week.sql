-- ============ migrations/0077_current_week_team_of_week.sql ====================
-- Team of the Week is the CURRENT week. Team of the Month is unchanged.
--
-- ## What changes
--
-- `0070` resolved both awards through `last_completed_statistics_period`, so on
-- Sunday 13 September 2026 Team of the Week still described 31 August --
-- 6 September: the week that had finished, never the one being played. The
-- Product Owner has changed the weekly contract:
--
--   weekly    the ISO week containing now, Monday -> Sunday, Asia/Muscat
--   monthly   the last fully completed calendar month -- exactly as before
--
--   Sunday 13 September 2026 (Muscat)   ->  7 September -- 13 September
--   Monday 14 September 2026 (Muscat)   ->  14 September -- 20 September
--
-- The week rolls over by itself at Monday 00:00 in Muscat, because nothing is
-- stored: the period is resolved from `now()` on every read. A week with no
-- qualifying match is still that week, with `qualifying_match_count = 0`; it
-- never falls back to the previous week.
--
-- ## How
--
-- Two helpers, and the three `0070` read paths pointed at the second:
--
--   current_statistics_week_at(p_at)       the ISO week containing an instant.
--                                           Pure in its argument, so the
--                                           Sunday/Monday boundary can be
--                                           checked at any instant rather than
--                                           only at the one the clock shows.
--
--   team_of_period_statistics_period(type) the award period. weekly asks the
--                                           helper above about now(); monthly
--                                           calls `0070`'s
--                                           last_completed_statistics_period
--                                           ('monthly') -- the same function,
--                                           not a copy of its arithmetic.
--
-- The week is computed the way `0070` computes it -- `date_trunc('week')` over
-- the Muscat wall clock, with the zone taken from `statistics_period_zone()` and
-- the key from `statistics_period_key` -- so the award week and the week the
-- statistics counters are bucketed by cannot be different weeks.
--
-- `community_period_xi_matches`, `community_period_xi_window` and
-- `community_period_xi_evidence` are recreated from `0070`'s bodies with ONE
-- change each: the period CTE reads `team_of_period_statistics_period` instead
-- of `last_completed_statistics_period`. Every other line of each body --
-- authentication, membership, the six qualifying conditions, guests, shape
-- evidence, the evidence timestamp, form, eligibility, position resolution and
-- ordering -- is `0070`'s byte for byte, and the `0072` participation bar is
-- called exactly as it was. Their function comments now name the period they
-- actually resolve.
--
-- ## Why the current week is dynamic without anything new
--
-- The award was always a read model over evidence: no stored award, no selected
-- XI, no snapshot, no trigger. So inside the running week the XI follows the
-- evidence as it changes -- a match completing with a result, a corrected score,
-- goal or MVP, a corrected lineup or assigned position, and a historical match
-- entered today whose `start_at` falls in this week. A match is placed in a week
-- by `start_at`, never by when it was written, exactly as before. Nothing about
-- that needed changing, and nothing is added to make it happen.
--
-- ## What does not change
--
-- `last_completed_statistics_period` is not edited, and monthly still calls it.
-- No table, column, view, policy, trigger or stored award is added. Signatures,
-- SECURITY DEFINER, the pinned `search_path`, and every privilege are as `0070`
-- left them: the two public read paths are executable by `authenticated` only,
-- and both new helpers are revoked from every client role. The rating engine,
-- Period Form Score v1, the `0072` threshold and the selection contract are
-- untouched, and so is every error token.
--
-- Append-only: `0070`, `0071` and `0072` are not edited. Idempotent: every
-- statement is `create or replace`, `comment on`, `revoke` or `grant`.

-- 1) The ISO week containing an instant ----------------------------------------
-- Half-open, [start, end): the instant the week ends -- Monday 00:00 in Muscat --
-- is already the next week. Muscat keeps no daylight saving, and the interval is
-- added on the wall clock before converting back, so a week is seven wall-clock
-- days whatever the zone does.
--
-- Not client-callable: it is called by the award-period resolver below, which is
-- called by the gated read paths, which run as their owner.
create or replace function public.current_statistics_week_at(
  p_at timestamptz
)
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_zone text;
  v_week timestamp;
  v_start timestamptz;
begin
  v_zone := public.statistics_period_zone();
  -- Monday 00:00 of the week containing p_at, on the Muscat wall clock.
  v_week := date_trunc('week', p_at at time zone v_zone);
  v_start := v_week at time zone v_zone;

  return query
  select
    'weekly'::text,
    public.statistics_period_key(v_start, 'weekly'),
    v_start,
    (v_week + interval '7 days') at time zone v_zone;
end;
$$;

comment on function public.current_statistics_week_at(timestamptz) is
  'The ISO week (Monday to Sunday, Asia/Muscat) containing p_at, as '
  '(period_type, period_key, period_start, period_end) with a half-open '
  '[start, end) interval. Derived with the zone and key functions the '
  'statistics counters use, so it names the same week they bucket into. '
  'Internal to Team of Period -- see migration 0077.';

revoke execute on function public.current_statistics_week_at(timestamptz)
  from anon, authenticated, public;

-- 2) Which period a Team of Period award is about ------------------------------
-- The single interpretation both read paths share, as `0070`'s function was:
-- the window and the candidate list still resolve the period in one place, so
-- they cannot describe different weeks.
--
--   weekly    the running week, resolved at now()
--   monthly   last_completed_statistics_period('monthly'), unchanged
--
-- `overall` is refused with the token `0070` already uses: there is no All Time
-- Period XI.
create or replace function public.team_of_period_statistics_period(
  p_period_type text
)
returns table (
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz
)
language plpgsql
stable
set search_path = public
as $$
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  if p_period_type = 'weekly' then
    return query
    select w.period_type, w.period_key, w.period_start, w.period_end
    from public.current_statistics_week_at(now()) w;
  else
    return query
    select m.period_type, m.period_key, m.period_start, m.period_end
    from public.last_completed_statistics_period('monthly') m;
  end if;
end;
$$;

comment on function public.team_of_period_statistics_period(text) is
  'The period a Team of Period award describes: for weekly, the CURRENT ISO '
  'week in Asia/Muscat, resolved from now() on every read, so it rolls over on '
  'its own at Monday 00:00 and an empty week is still that week; for monthly, '
  'the last COMPLETED calendar month, through last_completed_statistics_period '
  'exactly as before. overall is refused. Both read paths call it so the '
  'window and the candidates always describe the same period -- see migration '
  '0077.';

revoke execute on function public.team_of_period_statistics_period(text)
  from anon, authenticated, public;

-- 3) The three read paths, pointed at the award period -------------------------
-- `0070`'s bodies, comments on the functions, and privileges, with the single
-- change marked `CHANGED (0077)` in each. Restated in full because
-- `create or replace` replaces a whole body; nothing else in them moves.

create or replace function public.community_period_xi_matches(
  p_community_id uuid,
  p_period_type text
)
returns table (match_id uuid, start_at timestamptz)
language sql
security definer
stable
set search_path = public
as $$
  with period as (
    select p.period_key
    -- CHANGED (0077): the current week, or the last completed month.
    from public.team_of_period_statistics_period(p_period_type) p
  )
  select c.match_id, c.start_at
  from v_completed_matches c
  join match_results r on r.match_id = c.match_id
  cross join period pk
  -- Isolation as well as filter: with RLS bypassed this is what keeps another
  -- community's football out of the answer entirely.
  where c.community_id = p_community_id
    and public.statistics_period_key(c.start_at, p_period_type) = pk.period_key
    and exists (
      select 1 from match_team_assignments a
      where a.match_id = c.match_id and a.user_id is not null
    );
$$;

comment on function public.community_period_xi_matches(uuid, text) is
  'The matches a Team of Period award is decided from: this community, inside '
  'the award period -- the current week, or the last completed month -- '
  'completed, with a result, and with at least one '
  'real Go Play user on the stored lineup. A guest-only match is excluded '
  'entirely -- it raises no threshold, dilutes no participation rate and '
  'contributes no shape evidence. Internal: both public read paths call it so '
  'they cannot count different matches -- see migrations 0070 and 0077.';

revoke execute on function public.community_period_xi_matches(uuid, text)
  from anon, authenticated, public;

create or replace function public.community_period_xi_window(
  p_community_id uuid,
  p_period_type text
)
returns table (
  -- Which period was evaluated. Available whether or not anybody played it, so
  -- the screen can always name the range it is showing.
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz,
  -- How much football was in it, and what that asks of a candidate.
  qualifying_match_count int,
  required_matches int,
  -- The most recent authoritative change to the evidence inside this period.
  -- Null when the period has no qualifying evidence at all.
  evidence_last_changed_at timestamptz,
  -- One entry per played side of every qualifying match: guests included,
  -- because they actually played. Cycle 2 takes the median of these, rounds a
  -- .5 upward and caps at 11.
  team_size_observations int[],
  -- The same sides, with their positional make-up. **This is the positional
  -- evidence Cycle 2 must use.** One side is one observation whether it fielded
  -- five players or eleven; the aggregate below cannot say that, which is why
  -- it is not the slot-allocation source.
  position_shape_observations jsonb,
  -- Diagnostic only: every played lineup row of the period counted by position.
  -- An 11-a-side match contributes twenty-two rows here and two observations
  -- above, so this over-weights big matches and must not be treated as final
  -- slot evidence.
  position_shape jsonb
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  -- Stated here rather than left to the base tables, because this function does
  -- not run under the caller's policies. Both questions are asked before a
  -- single row is read, and they are the same two the candidate function asks.
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_community_member(p_community_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return query
  with period as (
    select p.period_type, p.period_key, p.period_start, p.period_end
    -- CHANGED (0077): the current week, or the last completed month.
    from public.team_of_period_statistics_period(p_period_type) p
  ),
  qualifying as (
    select m.match_id, m.start_at
    from public.community_period_xi_matches(p_community_id, p_period_type) m
  ),
  lineup as (
    -- Every stored played row of every qualifying match, real players and
    -- Professional Guests alike. A guest actually played, so they count toward
    -- how big a side was and how it was filled.
    select a.match_id, a.team, a.assigned_position, q.start_at
    from match_team_assignments a
    join qualifying q on q.match_id = a.match_id
  ),
  sides as (
    -- One row per played side. A side with no stored row did not play and is
    -- not an observation of zero.
    select
      l.match_id,
      l.team,
      min(l.start_at) as start_at,
      count(*)::int as team_size,
      (count(*) filter (where l.assigned_position = 'GK'))::int as gk,
      (count(*) filter (where l.assigned_position = 'DEF'))::int as def,
      (count(*) filter (where l.assigned_position = 'MID'))::int as mid,
      (count(*) filter (where l.assigned_position = 'FWD'))::int as fwd,
      -- A guest whose position was never recorded is counted as unassigned
      -- rather than guessed at. A real player always has one (`0051`).
      (count(*) filter (where l.assigned_position is null))::int as unassigned
    from lineup l
    group by l.match_id, l.team
  ),
  shape as (
    select
      coalesce(
        array_agg(
          s.team_size order by s.team_size, s.start_at, s.match_id, s.team),
        '{}'::int[]
      ) as team_size_observations,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'team', s.team,
            'team_size', s.team_size,
            'GK', s.gk,
            'DEF', s.def,
            'MID', s.mid,
            'FWD', s.fwd,
            'unassigned', s.unassigned
          )
          -- Deterministic, and by when the football happened rather than by
          -- when a row was written. No match id is exposed: the caller is
          -- entitled to the shape, not to a manifest of the fixtures.
          order by s.start_at, s.match_id, s.team
        ),
        '[]'::jsonb
      ) as position_shape_observations
    from sides s
  ),
  aggregate_shape as (
    select jsonb_build_object(
      'GK',  count(*) filter (where l.assigned_position = 'GK'),
      'DEF', count(*) filter (where l.assigned_position = 'DEF'),
      'MID', count(*) filter (where l.assigned_position = 'MID'),
      'FWD', count(*) filter (where l.assigned_position = 'FWD'),
      'unassigned', count(*) filter (where l.assigned_position is null)
    ) as position_shape
    from lineup l
  ),
  counted as (
    select count(*)::int as qualifying_matches from qualifying
  ),
  changed as (
    -- The strongest authoritative timestamp each source actually has, taken
    -- over the qualifying matches and no others -- so evidence belonging to a
    -- later period cannot advance this period's figure.
    --
    -- `matches`, `match_results` and `match_team_assignments` each carry an
    -- `updated_at` maintained by a `set_updated_at` trigger (`0003`, `0022`,
    -- `0018`), so a correction moves it. `match_goals` has only `created_at`
    -- and needs nothing more: every result correction deletes the rows and
    -- reinserts them (`0022`, and every later revision of that path), so the
    -- insert time *is* the time the goals last changed. No column is invented
    -- and none is assumed.
    --
    -- A legitimate historical match entered today with a date inside the period
    -- arrives with a fresh `updated_at`, so the timestamp advances -- which is
    -- the intended behaviour, not a leak: that match is evidence about this
    -- period.
    --
    -- `greatest` ignores nulls and is null only when every source is, which is
    -- what an empty period returns.
    select greatest(
      (select max(m.updated_at) from matches m
        join qualifying q on q.match_id = m.id),
      (select max(r.updated_at) from match_results r
        join qualifying q on q.match_id = r.match_id),
      (select max(a.updated_at) from match_team_assignments a
        join qualifying q on q.match_id = a.match_id),
      (select max(g.created_at) from match_goals g
        join qualifying q on q.match_id = g.match_id)
    ) as evidence_last_changed_at
  )
  select
    p.period_type,
    p.period_key,
    p.period_start,
    p.period_end,
    c.qualifying_matches,
    public.period_xi_required_matches(p_period_type, c.qualifying_matches),
    ch.evidence_last_changed_at,
    sh.team_size_observations,
    sh.position_shape_observations,
    ag.position_shape
  from period p
  cross join counted c
  cross join shape sh
  cross join aggregate_shape ag
  cross join changed ch;
end;
$$;

comment on function public.community_period_xi_window(uuid, text) is
  'Team of Period, the period itself: exactly one row naming the CURRENT ISO '
  'week or the last completed calendar month in Asia/Muscat, how many '
  'qualifying '
  'matches it held, what that asks of a candidate, when its evidence last '
  'changed, and the per-side team-size and positional observations Cycle 2 '
  'sizes and shapes the squad from. Returned even when the period is empty, so '
  'the screen can always name the range it is showing -- which is why no '
  'null-user candidate row exists. Cycle 2 must use '
  'position_shape_observations, one entry per played side, rather than the '
  'position_shape aggregate, which over-weights large matches. Same '
  'authorization as the candidate read path -- see migrations 0070 and 0077.';

revoke execute on function
  public.community_period_xi_window(uuid, text) from anon, public;
grant execute on function
  public.community_period_xi_window(uuid, text) to authenticated;

create or replace function public.community_period_xi_evidence(
  p_community_id uuid,
  p_period_type text
)
returns table (
  -- Which period this is evidence about. Repeated from the window so a
  -- candidate row is self-describing; both come from the same resolution.
  period_type text,
  period_key text,
  period_start timestamptz,
  period_end timestamptz,
  -- The community's football in it, and what it asks of a candidate. The same
  -- match set the window counted, because both call the same function.
  qualifying_match_count int,
  required_matches int,
  matches_played int,
  participation_rate numeric,
  eligible boolean,
  -- Results.
  wins int,
  draws int,
  losses int,
  -- Production. Raw and uncapped, for presentation.
  goals int,
  goals_per_match numeric,
  mvp_count int,
  -- Efficiency.
  win_rate numeric,
  points_per_game numeric,
  -- Form, and the capped goal evidence the fourth tie-break reads. The total is
  -- the *same* capped contribution the form score is built from, summed across
  -- the period -- never the raw goal count, which would let one nine-goal
  -- afternoon outrank a season of them.
  period_form_score numeric,
  goal_form_contribution_total numeric,
  -- Where they actually played, and the historical evidence that decided it.
  period_primary_position text,
  period_secondary_position text,
  position_appearances jsonb,
  position_basis_evidence jsonb,
  -- **Presentation only.** `current_overall_rating` is the player's Global
  -- Rating as it stands *today* -- a live, mutable, period-less number, which
  -- is what the Statistics screens already show it as. The Team of Period card
  -- may display it, labelled as current. It MUST NOT participate in Period XI
  -- selection, eligibility, form, position ranking or slot allocation: ranking
  -- on it would let a match played in September change August's XI, which is
  -- the one thing a closed award may not do.
  current_overall_rating numeric,
  -- The deterministic final tie-break of the selection, and the order these
  -- rows come back in.
  user_id uuid
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_community_member(p_community_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return query
  with period as (
    select p.period_type, p.period_key, p.period_start, p.period_end
    -- CHANGED (0077): the current week, or the last completed month.
    from public.team_of_period_statistics_period(p_period_type) p
  ),
  qualifying as (
    select m.match_id, m.start_at
    from public.community_period_xi_matches(p_community_id, p_period_type) m
  ),
  lineup as (
    select
      a.match_id,
      a.team,
      a.user_id as player_id,
      a.assigned_position,
      -- Carried because the position tie-break is decided from it.
      --
      -- What it honestly guarantees: it is historical lineup evidence stored on
      -- the row, and a later profile edit does not touch it. It is *not* a
      -- snapshot of the profile at kick-off -- if the lineup row is rewritten
      -- by a correction, the basis written then may reflect whatever profile
      -- state that correction path used. That is acceptable here, because
      -- rewriting the lineup is exactly the kind of in-period correction the
      -- award is allowed to follow. `assignment_basis` is not redesigned by
      -- this migration.
      a.assignment_basis,
      -- When the football happened. The position recency tie-break is about
      -- when the player last *played* there, so it reads the match start and
      -- never `match_team_assignments.updated_at`, which is when a row was last
      -- edited.
      q.start_at
    from match_team_assignments a
    join qualifying q on q.match_id = a.match_id
  ),
  appearances as (
    -- `match_result_contribution`'s arithmetic (0023, 0046), in the shape this
    -- read model needs: one row per real player per qualifying match they were
    -- on the lineup of. The guest predicate is the same one, in the same place.
    select
      l.player_id,
      l.match_id,
      l.assigned_position,
      l.assignment_basis,
      l.start_at,
      case
        when (l.team = 'A' and r.team_a_score > r.team_b_score)
          or (l.team = 'B' and r.team_b_score > r.team_a_score)
        then 1 else 0 end as won,
      case
        when (l.team = 'A' and r.team_a_score < r.team_b_score)
          or (l.team = 'B' and r.team_b_score < r.team_a_score)
        then 1 else 0 end as lost,
      case when r.team_a_score = r.team_b_score then 1 else 0 end as drawn,
      coalesce(g.goals, 0) as goals,
      case when l.player_id = r.mvp_user_id then 1 else 0 end as mvp
    from lineup l
    join match_results r on r.match_id = l.match_id
    left join match_goals g
      on g.match_id = l.match_id and g.user_id = l.player_id
    where l.player_id is not null
  ),
  totals as (
    select
      a.player_id,
      count(*)::int as matches_played,
      sum(a.won)::int as wins,
      sum(a.drawn)::int as draws,
      sum(a.lost)::int as losses,
      sum(a.goals)::int as goals,
      sum(a.mvp)::int as mvp_count,
      -- The period score is the **average** of the per-match contributions, so
      -- a player who played twice is measured by how they played and not by how
      -- often. `avg` over numeric keeps full scale: nothing is rounded here,
      -- and presentation is the caller's business.
      avg(public.period_form_score_v1(a.won, a.lost, a.drawn, a.goals, a.mvp))
        as period_form_score,
      -- The same capped contribution, summed instead of averaged -- so five
      -- goals in each of two matches is 0.20 and not 0.10. Summed because it
      -- breaks ties between players already level on form and participation,
      -- where total production is the honest next question.
      sum(public.period_goal_form_v1(a.goals))
        as goal_form_contribution_total
    from appearances a
    group by a.player_id
  ),
  by_position as (
    -- Where the player actually stood, counted -- with the basis recorded
    -- beside each appearance and the last time they played there.
    --
    -- **Every column here is historical.** `users.primary_position` and
    -- `users.secondary_position` are not read, in this branch or anywhere else
    -- in this migration, so a player editing their profile in October cannot
    -- reshuffle the XI of a week that closed in August.
    --
    -- The `is not null` is the constraint `0051` already guarantees for a row
    -- naming a user; it is written so that a position that somehow went missing
    -- is absent from the ranking rather than winning it.
    select
      a.player_id,
      a.assigned_position as played_position,
      count(*)::int as appearance_count,
      (count(*) filter (where a.assignment_basis = 'PRIMARY'))::int
        as primary_basis_count,
      (count(*) filter (where a.assignment_basis = 'SECONDARY'))::int
        as secondary_basis_count,
      -- Counted and returned, but never ranked on: a move to fill a gap is
      -- evidence about the match and not a claim about the player's role, so
      -- TRANSITION must not outrank PRIMARY or SECONDARY.
      (count(*) filter (where a.assignment_basis = 'TRANSITION'))::int
        as transition_basis_count,
      -- The most recent match in this period in which they played this
      -- position. `matches.start_at`, so recording an old fixture today does
      -- not make it the most recent thing they did.
      max(a.start_at) as most_recent_at
    from appearances a
    where a.assigned_position is not null
    group by a.player_id, a.assigned_position
  ),
  position_counts as (
    select
      b.player_id,
      jsonb_object_agg(b.played_position, b.appearance_count)
        as position_appearances,
      -- The same positions, with everything the tie-break looked at. Only
      -- positions actually played appear, no guest is in it, and the key order
      -- is jsonb's own, so two reads of an unchanged period are identical.
      jsonb_object_agg(
        b.played_position,
        jsonb_build_object(
          'appearances', b.appearance_count,
          'primary', b.primary_basis_count,
          'secondary', b.secondary_basis_count,
          'transition', b.transition_basis_count,
          'most_recent_at', b.most_recent_at
        )
      ) as position_basis_evidence
    from by_position b
    group by b.player_id
  ),
  ranked_positions as (
    -- Most-played first; then the historical basis recorded for those
    -- appearances, PRIMARY before SECONDARY; then the most recent time they
    -- actually played there; and finally the project's position axis (GK, DEF,
    -- MID, FWD), which makes the answer deterministic when nothing else
    -- separates two positions.
    --
    -- This keeps the approved principle -- prefer the player's natural role --
    -- while taking that role from the match record rather than from a profile
    -- field they can edit after the period has closed.
    --
    -- Rank 1 is the Period Primary Position and rank 2 the Period Secondary.
    -- Only positions actually played are in here, so a player who stood in one
    -- place all period has no rank 2 -- nothing manufactures one for them.
    select
      b.player_id,
      b.played_position,
      row_number() over (
        partition by b.player_id
        order by
          b.appearance_count desc,
          b.primary_basis_count desc,
          b.secondary_basis_count desc,
          b.most_recent_at desc,
          case b.played_position
            when 'GK' then 0
            when 'DEF' then 1
            when 'MID' then 2
            when 'FWD' then 3
          end asc
      ) as position_rank
    from by_position b
  ),
  counted as (
    select count(*)::int as qualifying_matches from qualifying
  ),
  requirement as (
    -- The same function the window publishes, over the same match set: both
    -- count through `community_period_xi_matches` and both ask
    -- `period_xi_required_matches`, so a candidate's `eligible` flag cannot
    -- disagree with the bar the screen displays beside it.
    select
      c.qualifying_matches,
      public.period_xi_required_matches(p_period_type, c.qualifying_matches)
        as required_matches
    from counted c
  )
  select
    p.period_type,
    p.period_key,
    p.period_start,
    p.period_end,
    q.qualifying_matches,
    q.required_matches,
    t.matches_played,
    -- No division by zero is reachable: a row exists only for a player with at
    -- least one appearance, and an appearance is in a qualifying match, so both
    -- denominators are at least one.
    t.matches_played::numeric / q.qualifying_matches,
    t.matches_played >= q.required_matches,
    t.wins,
    t.draws,
    t.losses,
    t.goals,
    t.goals::numeric / t.matches_played,
    t.mvp_count,
    t.wins::numeric / t.matches_played,
    -- Football scoring: a win is three points, a draw one, a loss none.
    (t.wins * 3 + t.draws)::numeric / t.matches_played,
    t.period_form_score,
    t.goal_form_contribution_total,
    pp.played_position,
    ps.played_position,
    pc.position_appearances,
    pc.position_basis_evidence,
    -- Presentation only, and the only thing `users` is read for. Nothing above
    -- ranks on it and nothing in Cycle 2 may.
    u.overall_rating,
    t.player_id
  from totals t
  cross join period p
  cross join requirement q
  join users u on u.id = t.player_id
  join position_counts pc on pc.player_id = t.player_id
  join ranked_positions pp
    on pp.player_id = t.player_id and pp.position_rank = 1
  left join ranked_positions ps
    on ps.player_id = t.player_id and ps.position_rank = 2
  -- Deliberately **not** the selection order -- see the selection contract
  -- above. Ordering by the player is what makes two reads of an unchanged
  -- period identical, and it is also the last tie-break of that selection, so
  -- the deterministic answer is already the one these rows arrive in when
  -- everything before it is level.
  order by t.player_id;
end;
$$;

comment on function public.community_period_xi_evidence(uuid, text) is
  'Team of the Week / Team of the Month candidates: one row per real player '
  'who played in the CURRENT ISO week or the last COMPLETED calendar month, '
  'and zero rows '
  'when nobody did -- the period itself is described by '
  'community_period_xi_window, so no null-user metadata row exists. Carries '
  'participation, results, goals per match, win rate, points per game, Period '
  'Form Score v1, the capped goal-form total, and the position actually played '
  'with the assignment_basis and most-recent-appearance evidence that decided '
  'it. Professional Guests are never candidates; a guest-only match is not '
  'even a qualifying match. Cycle 2 selection ranks on period_form_score desc, '
  'participation_rate desc, mvp_count desc, goal_form_contribution_total desc, '
  'then user_id, and on nothing else: current_overall_rating is PRESENTATION '
  'EVIDENCE ONLY and MUST NOT participate in Period XI selection, because it '
  'is a live global figure that a later match would move. Position is decided '
  'from assigned_position, assignment_basis and matches.start_at alone; '
  'users.primary_position and users.secondary_position are read nowhere, so '
  'editing a profile cannot reshape a closed period. Current membership is not '
  'consulted either -- a player who has left keeps what they earned. A read '
  'model over existing evidence: no stored award, no selected XI, no trigger, '
  'so correcting a score, a goal, an MVP, a lineup or a position inside the '
  'period changes the answer -- and nothing that happens outside it does '
  '-- see migrations 0070 and 0077.';

-- Default privileges on a new function include EXECUTE for PUBLIC, which for a
-- definer function would mean anybody. Revoked first, then granted to exactly
-- the role the client uses -- the same shape 0060 sets for the sibling read
-- model, and the same audience `community_statistics_select_members` already
-- serves. The two public functions carry identical grants because they carry
-- identical gates; the four helpers above are granted to nobody.
revoke execute on function
  public.community_period_xi_evidence(uuid, text) from anon, public;
grant execute on function
  public.community_period_xi_evidence(uuid, text) to authenticated;
