-- ============ migrations/0070_team_of_period_evidence.sql ============
-- The evidence a Team of the Week or Team of the Month is decided from.
--
-- ## What this is, and what it deliberately is not
--
-- This is **Cycle 1**: the authoritative read model behind the award, and
-- nothing else. It answers "which period was evaluated, who played in it, how
-- did they do, and what shape was the football" -- it does not pick eleven
-- players, it does not size a squad, and it allocates no positional slots.
-- Those are Cycle 2, and they read what is here rather than re-deriving it.
--
-- ## Two read paths, because a period is not a player
--
--   * `community_period_xi_window`   -- exactly one row: which period, how much
--     football was in it, and the shape evidence Cycle 2 sizes the squad from.
--   * `community_period_xi_evidence` -- zero or more rows, one per real
--     candidate.
--
-- The window exists because a period with no candidates still has to be
-- describable. A week in which nobody played is a fact the screen must be able
-- to state -- "Team of the Week, 25-31 August, no qualifying matches" -- and
-- the alternative was a candidate row with a null `user_id`, which is a lie
-- about the shape of the data: a metadata row is not a player, and every reader
-- would have had to remember to filter it out.
--
-- ## No stored award
--
-- There is **no team_of_week table, no team_of_month table, no selected-XI
-- row, no materialized award and no trigger.** The award is a function of
-- evidence that is already authoritative:
--
--     v_completed_matches x match_results x match_team_assignments x match_goals
--
-- Every one of those is a record of the period itself. `users` is read too, but
-- for one presentation column and for nothing the award is decided by -- see
-- the historical stability section below.
--
-- That is what makes a correction work with no code written for corrections.
-- Fix a score and the wins move; fix a lineup and the participation moves; take
-- an MVP away and the form score falls. Nothing has to be recomputed and no
-- backfill exists, because there is no stored answer to go stale.
--
-- ## The period is the database's decision, never the caller's
--
-- Both functions take `weekly` or `monthly` and **no timestamp**. The last
-- *fully completed* period is resolved once, by
-- `last_completed_statistics_period` (section 3), in
-- `statistics_period_zone()` -- Asia/Muscat, frozen by `0028` -- and keyed
-- through `statistics_period_key()`, the same call that bucketed every counter
-- in `community_statistics`. A running week is never the award week. There is
-- no All Time period XI, so `overall` is refused rather than silently accepted.
--
-- **One implementation, two callers.** The window and the candidate list must
-- describe the same week or they are describing different awards, so neither
-- computes a boundary of its own: both ask the same function, and the same is
-- true of which matches qualify (section 4).
--
-- ## Historical stability: what may change a closed period, and what may not
--
-- This is the invariant the whole design serves, and every field below is
-- chosen against it. The line is drawn around the **football event**, not
-- around when a row happened to be written.
--
-- A completed Period XI **may** change when authoritative evidence whose
-- football belongs to that period is corrected or added:
--
--   * a legitimate historical match dated inside the period, entered late;
--   * a lineup corrected, or a team assignment corrected;
--   * an assigned position corrected;
--   * a score corrected;
--   * goals corrected;
--   * an MVP corrected.
--
-- That is not instability; that is the award following the evidence, which is
-- exactly why nothing is stored. An award is not frozen by having been viewed
-- or shared.
--
-- A completed Period XI **must not** change because of anything that happened
-- outside it:
--
--   * the player played matches in a later period;
--   * their current Overall Rating moved;
--   * they edited their profile's Primary or Secondary position without any
--     historical lineup row being rewritten;
--   * the rating or form rules moved from v1 to some later version.
--
-- So no mutable present-tense value is allowed to decide anything:
--
--   * **Form** is `period_form_score_v1`, whose weights are its own and are
--     frozen (section 2), rather than the rating engine's, which may move.
--   * **Position** is decided entirely from the lineup rows of that period --
--     `assigned_position`, the `assignment_basis` stored beside it, and the
--     `start_at` of the match it was played in. The profile's
--     `primary_position` and `secondary_position` are read **nowhere in this
--     migration**: they are today's answer to a question the award asks about a
--     week that has closed.
--   * **The rating** is returned as `current_overall_rating` and is
--     presentation only. It is named `current_` precisely so that no later
--     cycle can mistake it for period evidence. See the column comment.
--
-- ## Why `security definer`
--
-- The award is one fact about a community, and every member of it must be shown
-- the same one. Two of the inputs make that impossible under the caller's own
-- policies:
--
--   * `users` is readable through `authenticated_select_active_users`, which is
--     `using (is_active)`. A player who played in the period and has since been
--     deactivated or suspended still played it -- the award is a record of that
--     week -- but under invoker rights their row disappears, and with it the
--     candidate, who would drop out of an award they earned for a reason that
--     is not about the football. The same is true of a player who has since
--     left the community: they earned it while they were here, so nothing in
--     this migration filters candidates by current membership.
--   * `v_completed_matches` is `security_invoker`, so the completed-match rule
--     would be applied against whatever the reader happens to see rather than
--     against the community's actual history.
--
-- So the public functions run as their owner and state their authorization
-- themselves, in the shape `community_statistics_recency` (0060) established
-- for the same reason:
--
--   * `auth.uid()` must exist -- no anonymous caller;
--   * the caller must be a **current member of `p_community_id`**, asked
--     directly through `is_community_member`;
--   * both run **before any row is read**, so a refusal never depends on what
--     was found.
--
-- Both public functions carry the identical gate. There is no second, weaker
-- way in: the helpers they call are revoked from every client role, so the two
-- gated entry points are the only doors.
--
-- **Visibility is unchanged, neither widened nor narrowed.** This is the same
-- population `community_statistics_select_members` already discloses to the
-- same readers: a member of a community may see who played in it and what they
-- did. No policy is created, dropped or altered by this migration, nothing is
-- readable through a base table that was not readable before, and the output
-- carries no match id, no community id and no profile field beyond the rating a
-- member can already read.
--
-- Backward compatible: no table, column, constraint, policy, grant or existing
-- function is changed. Seven functions are added -- two gated read paths and
-- five helpers, each of which exists so that a rule is written once and called
-- twice. Idempotent: `create or replace` throughout.

-- 1) The capped goal contribution, defined once ---------------------------------
-- What a player's goals in **one match** are worth to the award.
--
-- It is its own function because two things need it and they must not be able
-- to disagree: `period_form_score_v1` folds it into the form score, and
-- `goal_form_contribution_total` sums it across the period as a selection
-- tie-break. Writing the cap twice would let a later edit move one and not the
-- other, and the symptom would be a tie broken by arithmetic that no longer
-- matches the score it is breaking a tie for.
--
--     0 goals -> 0.00     1 -> 0.02     3 -> 0.06
--     5 -> 0.10           8 -> 0.10 (the cap is on the total, not on each goal)
--
-- FROZEN with `period_form_score_v1`, and versioned with it.
create or replace function public.period_goal_form_v1(p_goals int)
returns numeric
language sql
immutable
set search_path = public
as $$
  select least(0.10, 0.02 * greatest(coalesce(p_goals, 0), 0));
$$;

comment on function public.period_goal_form_v1(int) is
  'Period Form v1: what one player''s goals in one match are worth -- 0.02 '
  'each, capped at 0.10 for the match however many they scored. FROZEN. The '
  'single definition of the cap: period_form_score_v1 folds it into the form '
  'score and goal_form_contribution_total sums it across the period, so the '
  'tie-break and the score it breaks ties for cannot drift apart -- see '
  'migration 0070.';

revoke execute on function public.period_goal_form_v1(int)
  from anon, authenticated, public;

-- 2) Period Form Score v1 ------------------------------------------------------
-- The award's own measure of form, and the first immutable semantic version of
-- it.
--
-- **Why it carries its own numbers.** These five values are today also the
-- rating engine's (`0035`), and it would be tempting to reach for that function
-- instead. It must not: rating policy is allowed to change, and the day it
-- does, every past award period would silently be re-scored under rules that
-- did not exist when it was played. PFS v1 is therefore stated here, in full,
-- as literals. A future v2 is a **new function** beside this one, chosen
-- deliberately -- never an edit to this body.
--
--     win  +0.10    loss  -0.10    draw   0.00
--     goal +0.02 each, capped at +0.10 in one match  (section 1)
--     mvp  +0.05
--
-- **This is not a rating movement, and it must never be read from one.**
-- `rating_history.delta` records what a player's `overall_rating` could
-- actually absorb after the 0.00-10.00 clamp -- a winner already at 10.00 has a
-- delta of zero and a form contribution of +0.10 all the same. PFS measures
-- what the rules *asked for*, before any clamp, which is why it is computed
-- from the result and never from the audit.
--
-- The draw branch is written out rather than left to the `else`. A draw
-- contributing nothing is a rule, not an omission, and the rule is what a
-- reader should find here.
--
-- `immutable`: four constants, arithmetic, and one immutable call. No table, no
-- clock, no zone.
create or replace function public.period_form_score_v1(
  p_won int,
  p_lost int,
  p_drawn int,
  p_goals int,
  p_mvp int
)
returns numeric
language sql
immutable
set search_path = public
as $$
  select
      case
        when p_won   = 1 then  0.10
        when p_lost  = 1 then -0.10
        when p_drawn = 1 then  0.00
        else 0.00
      end
    + public.period_goal_form_v1(p_goals)
    + case when p_mvp = 1 then 0.05 else 0.00 end;
$$;

comment on function public.period_form_score_v1(int, int, int, int, int) is
  'Period Form Score v1: one player''s form contribution from one match. '
  'win +0.10, loss -0.10, draw 0.00, goal +0.02 each capped at +0.10, '
  'mvp +0.05. FROZEN -- these weights are the award''s own semantics and are '
  'deliberately not read from the rating engine, so that a future rating '
  'policy cannot re-score an award period that has already been played. A v2 '
  'is a new function beside this one, never an edit to this body. Computed '
  'from the result, never from rating_history.delta, which records only what '
  'the 0..10 clamp allowed through -- see migration 0070.';

revoke execute on function
  public.period_form_score_v1(int, int, int, int, int)
  from anon, authenticated, public;

-- 3) How much of the period a candidate has to have played ----------------------
-- The eligibility bar, stated once because both read paths publish it: the
-- window as the community's `required_matches`, the candidate rows as the
-- number their own `matches_played` is tested against. Two copies would let a
-- screen show a bar that its own eligible flags disagreed with.
--
--   * **An empty period asks for nothing at all.** No qualifying match means no
--     award population, so there is nobody for a bar to apply to. Returning 1
--     would make the window say "1 required" beside "0 matches", which is a
--     screen telling the truth about the football and a lie about the rule.
--   * **Weekly asks for one played match and nothing more.** A community that
--     played once that week still has a Team of the Week; the Product Owner
--     fixed this, and no two-match minimum may be imposed.
--   * **Monthly asks for half the community's month, rounded up:**
--     1->1, 2->1, 3->2, 4->2, 5->3, 6->3, 7->4.
--
-- `(n + 1) / 2` in integer arithmetic, which **is** ceil(n/2) over the
-- non-negative counts this can hold. `ceil(n / 2)` is deliberately not used:
-- `/` between two integers truncates in PostgreSQL, so the division would have
-- discarded the half before `ceil` ever saw it and three matches would have
-- asked for one. Casting first would fix that, but it leaves a correct
-- expression one deleted `::numeric` away from a silently wrong threshold --
-- and nothing downstream would notice, because a bar that is too low still
-- produces a perfectly plausible XI. The integer form cannot be broken that
-- way.
create or replace function public.period_xi_required_matches(
  p_period_type text,
  p_qualifying_matches int
)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    -- Tested first, and for both kinds of period: an empty period has no bar.
    -- It also leaves the monthly branch reachable only with a positive count,
    -- so `(n + 1) / 2` needs no guard of its own.
    when coalesce(p_qualifying_matches, 0) <= 0 then 0
    when p_period_type = 'weekly' then 1
    else (p_qualifying_matches + 1) / 2
  end;
$$;

comment on function public.period_xi_required_matches(text, int) is
  'How many qualifying matches a Team of Period candidate must have played: 0 '
  'when the period held no qualifying match at all, whatever its kind, because '
  'an empty period has no award population for a bar to apply to; otherwise 1 '
  'for a week, and ceil(n/2) of the community''s month -- written as integer '
  '(n + 1) / 2 so that no truncating division can lower the bar. Stated once '
  'because both read paths publish it -- see migration 0070.';

revoke execute on function public.period_xi_required_matches(text, int)
  from anon, authenticated, public;

-- 4) Which period the award is about -------------------------------------------
-- The last **completed** period of the requested kind, resolved once for both
-- read paths.
--
-- `date_trunc('week')` is ISO in PostgreSQL -- weeks begin on Monday -- which
-- is the same week `to_char(..., 'IYYY-"W"IW')` names inside
-- `statistics_period_key`. Truncating the Muscat wall clock gives the period
-- that is still running; stepping back one gives the one that has finished. The
-- bounds are half-open, [start, end), so the instant a period ends is already
-- the next one.
--
-- The key is derived from the start just computed, by the counters' own
-- function. One chain -- `date_trunc` -> start -> `statistics_period_key` --
-- so what the award filters on and what `community_statistics` was bucketed by
-- cannot be different weeks.
--
-- `overall` is refused rather than tolerated: there is no All Time Period XI,
-- and an award with no period is not something this read model can describe.
--
-- Not client-callable: it is called by the two gated functions below, which run
-- as their owner.
create or replace function public.last_completed_statistics_period(
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
declare
  v_zone text;
  v_muscat_now timestamp;
  v_start timestamptz;
  v_end timestamptz;
begin
  if p_period_type is null or p_period_type not in ('weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;

  v_zone := public.statistics_period_zone();
  v_muscat_now := now() at time zone v_zone;

  if p_period_type = 'weekly' then
    v_start := (date_trunc('week', v_muscat_now) - interval '7 days')
                 at time zone v_zone;
    v_end := date_trunc('week', v_muscat_now) at time zone v_zone;
  else
    v_start := (date_trunc('month', v_muscat_now) - interval '1 month')
                 at time zone v_zone;
    v_end := date_trunc('month', v_muscat_now) at time zone v_zone;
  end if;

  return query
  select
    p_period_type,
    public.statistics_period_key(v_start, p_period_type),
    v_start,
    v_end;
end;
$$;

comment on function public.last_completed_statistics_period(text) is
  'The last COMPLETED ISO week or calendar month, in Asia/Muscat, as '
  '(period_type, period_key, period_start, period_end). The single '
  'interpretation of the award period: both Team of Period read paths call it '
  'rather than computing a boundary each, so the window and the candidate list '
  'always describe the same week. A running period is never returned and '
  'overall is refused -- see migration 0070.';

revoke execute on function public.last_completed_statistics_period(text)
  from anon, authenticated, public;

-- 4) Which matches the award is decided from ------------------------------------
-- A match qualifies when **all six** hold:
--
--   1. it belongs to the requested community;
--   2. it falls in the completed period;
--   3. it is completed under `0029`'s rule;
--   4. it has a recorded result;
--   5. it has a stored played lineup;
--   6. **at least one real Go Play user is on that lineup.**
--
-- Completion is not restated here. `v_completed_matches` (0037) is the one
-- place that rule lives (status is completed **or** `end_at` has passed) and
-- reading it is what keeps this and the match list from reporting different
-- histories.
--
-- **Six is the one that is easy to lose.** A match played entirely by
-- Professional Guests is a real match, and it is deliberately not a Team of
-- Period match: it has no candidate in it, so counting it would raise the
-- monthly bar that real players are measured against and dilute every
-- participation rate in the community -- a squad of stand-ins would make the
-- regulars look like part-timers. It must not contribute squad-size or
-- positional-shape evidence either, because it describes football that the
-- award is not about. A **mixed** match is a qualifying match in full: the real
-- users in it are candidates, and the guests beside them still count toward the
-- actual size and shape of the side they played on.
--
-- Conditions 5 and 6 are one predicate rather than two. A lineup row naming a
-- user is a stored lineup row, so the real-user test strictly implies the
-- stored-lineup test; writing both would be two statements of one rule, and the
-- weaker one would go stale first.
--
-- Factored so that both read paths, and every figure inside them, count the
-- same matches. The window's `qualifying_match_count` and the candidates'
-- `participation_rate` are arithmetic over this one set; computing it twice
-- would let a window claim three matches while the rates were taken over four.
--
-- Not client-callable: `security definer`, and revoked, so the only way to it
-- is through one of the two gated functions.
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
    from public.last_completed_statistics_period(p_period_type) p
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
  'the last completed period, completed, with a result, and with at least one '
  'real Go Play user on the stored lineup. A guest-only match is excluded '
  'entirely -- it raises no threshold, dilutes no participation rate and '
  'contributes no shape evidence. Internal: both public read paths call it so '
  'they cannot count different matches -- see migration 0070.';

revoke execute on function public.community_period_xi_matches(uuid, text)
  from anon, authenticated, public;

-- 5) The window -----------------------------------------------------------------
-- Exactly one row for an authorized caller, always -- including for a period in
-- which the community played nothing at all. That is the point of it: the
-- screen can say *which* week it is showing and that the week was empty,
-- without a candidate row having to pretend to be a player.
--
-- It also carries the shape evidence, which is a fact about the community's
-- football rather than about any one player. It lived on every candidate row in
-- an earlier draft, which duplicated it N times and left it unreachable exactly
-- when the period had no candidates.
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
    from public.last_completed_statistics_period(p_period_type) p
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
  'Team of Period, the period itself: exactly one row naming the last '
  'completed ISO week or calendar month in Asia/Muscat, how many qualifying '
  'matches it held, what that asks of a candidate, when its evidence last '
  'changed, and the per-side team-size and positional observations Cycle 2 '
  'sizes and shapes the squad from. Returned even when the period is empty, so '
  'the screen can always name the range it is showing -- which is why no '
  'null-user candidate row exists. Cycle 2 must use '
  'position_shape_observations, one entry per played side, rather than the '
  'position_shape aggregate, which over-weights large matches. Same '
  'authorization as the candidate read path -- see migration 0070.';

revoke execute on function
  public.community_period_xi_window(uuid, text) from anon, public;
grant execute on function
  public.community_period_xi_window(uuid, text) to authenticated;

-- 6) The candidates -------------------------------------------------------------
-- One row per **real Go Play player** who appeared in the last completed
-- period, carrying that player's performance and the position they actually
-- played. Zero rows is a legitimate and complete answer: the period is still
-- fully described by the window.
--
-- **A Professional Guest is never a row here.** They have no account, so no
-- form score, no statistics, no eligibility and no rank -- `0046`'s boundary,
-- restated by the one predicate `l.player_id is not null` in `appearances`.
-- Their contribution to the size and shape of the sides they played on is real
-- and is carried by the window. Playing in the shape of a match and being
-- eligible for the award are different questions, answered in different places.
--
-- **Registration is not participation.** Every count below is taken from
-- `match_team_assignments` -- the lineup that actually played. A registration,
-- and a reserve seat, appear nowhere.
--
-- **Membership is not eligibility either.** A player who earned an award and
-- has since left the community keeps it: nothing here joins
-- `community_members`.
--
-- **The selection contract, for the cycle that will implement it.** Candidates
-- within an eligible position are ranked on exactly five things, in this order:
--
--     period_form_score           desc
--  -> participation_rate          desc
--  -> mvp_count                   desc
--  -> goal_form_contribution_total desc
--  -> user_id
--
-- and on nothing else. `current_overall_rating` is not among them, and neither
-- are `goals`, `goals_per_match`, `win_rate` or `points_per_game` -- those are
-- there to be shown and argued with, not scored twice. The rows come back
-- ordered by `user_id`, which is that last tie-break already applied and is
-- deliberately *not* the selection order: sorting by form here would be half of
-- Cycle 2's decision made in Cycle 1.
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
    from public.last_completed_statistics_period(p_period_type) p
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
  'who played in the last COMPLETED ISO week or calendar month, and zero rows '
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
  '-- see migration 0070.';

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
