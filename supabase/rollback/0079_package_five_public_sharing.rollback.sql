-- ============================================================================
-- ROLLBACK for migrations/0079_package_five_public_sharing.sql
-- ============================================================================
-- NOT a migration. Kept outside supabase/migrations/ so no tool applies it.
-- Run only on an explicit Product Owner decision, as one transaction.
--
-- Generated from the exact text of 0067 and 0077, so every restored function
-- is the definition that was live before 0079.
--
-- DEFAULT (non-destructive) rollback -- sections A to D:
--   * removes every function and table 0079 added;
--   * restores 0067's five-argument record_product_event and 0077's three Team
--     of Period read paths;
--   * LEAVES product_events.share_type, product_events.source and the
--     eleven-name CHECK in place. They are additive, nullable and a superset of
--     what the pre-0079 app writes, so the old app is unaffected, and removing
--     them would destroy analytics rows.
--
-- DATA LOST by the default rollback: any Team of Period snapshots written after
-- 0079 (tables dropped). No user, match, result or statistics row is touched.
--
-- Section E (full schema restore) is commented out on purpose: it DELETES
-- product_events rows named public_link_opened.

begin;

-- A) Public and internal read functions added by 0079 ---------------------------
drop function if exists public.public_match_lineup(uuid);
drop function if exists public.public_match_detail(uuid);
drop function if exists public.public_player_recent_highlight(uuid);
drop function if exists public.public_player_recent_form(uuid, int);
drop function if exists public.public_player_profile(uuid);
drop function if exists public.player_recent_highlights(uuid);
drop function if exists public.player_recent_form(uuid, int);

-- B) Team of Period snapshots --------------------------------------------------
drop function if exists public.record_team_of_period_snapshot(
  uuid, text, text, timestamptz, timestamptz, text, int, timestamptz, text, jsonb);
drop function if exists public.community_period_xi_closed_evidence(uuid, text);
drop function if exists public.community_period_xi_closed_window(uuid, text);
drop table if exists public.team_of_period_awards;
drop table if exists public.team_of_period_snapshots;

-- C) The three Team of Period read paths, exactly as 0077 left them --------------
-- `create or replace` with an unchanged signature keeps their privileges.
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

-- The moved bodies are unused once the originals are restored.
drop function if exists public.community_period_xi_evidence_in(
  uuid, text, text, timestamptz, timestamptz);
drop function if exists public.community_period_xi_window_in(
  uuid, text, text, timestamptz, timestamptz);
drop function if exists public.community_period_xi_matches_in(uuid, text, text);

-- D) record_product_event, exactly as 0067 left it -------------------------------
-- Dropped and recreated because the signature changes back. A caller that sends
-- only the five original named arguments (the pre-0079 app) works throughout.
drop function if exists public.record_product_event(
  text, uuid, uuid, text, text, text, text);

create or replace function public.record_product_event(
  p_event_name text,
  p_community_id uuid default null,
  p_match_id uuid default null,
  p_platform text default null,
  p_app_version text default null
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

  -- Restated here rather than left to the CHECK constraint. The constraint is
  -- the guarantee; this is the stable error, so a rejected event name arrives
  -- as INVALID_ANALYTICS_EVENT rather than as a raw constraint violation.
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
    'share_used'
  ) then
    raise exception 'INVALID_ANALYTICS_EVENT';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  -- `created_at` is left to the column default, which is database `now()`. A
  -- client clock must not decide which calendar day a metric falls in.
  --
  -- `app_version` is bounded rather than validated. It is a free string from
  -- the client and the only thing that matters about it is that it cannot grow
  -- without limit; 64 characters is far more than `0.4.1-public-beta+2` needs,
  -- and truncating cannot reject a legitimate write the way a CHECK could.
  insert into product_events (
    user_id, event_name, community_id, match_id, platform, app_version
  )
  values (
    v_user_id,
    p_event_name,
    p_community_id,
    p_match_id,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), '')
  );
end;
$$;

comment on function public.record_product_event(text, uuid, uuid, text, text) is
  'The one writer for product_events (migration 0067). Records the event '
  'against auth.uid() -- there is deliberately no user-id argument -- after '
  'checking that the caller is signed in, active, and naming an approved event '
  'and platform. Raises NOT_AUTHENTICATED, ACCOUNT_SUSPENDED, '
  'INVALID_ANALYTICS_EVENT or INVALID_ANALYTICS_PLATFORM; the client swallows '
  'all four, because analytics never blocks a product flow.';

-- `authenticated` executes it, because every event is an authenticated
-- player's. `anon` has none: an event belongs to a session, and `anon` has no
-- session to belong to.
--
-- `service_role` is granted **by name**, which is `0066`'s lesson written down
-- rather than remembered. `create or replace` keeps an existing ACL, so these
-- grants are additive today -- but the day one of these functions changes its
-- signature it will have to be dropped, and a drop takes the whole ACL with it
-- including the grant Supabase's default rule made and no migration mentioned.
-- Naming it here means the next author reads it in the file instead of finding
-- out from production.
revoke execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  from anon, public;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  to authenticated;
grant execute on function
  public.record_product_event(text, uuid, uuid, text, text)
  to service_role;

commit;

-- E) OPTIONAL full schema restore -- DESTRUCTIVE, Product Owner approval only ----
-- begin;
-- delete from public.product_events where event_name = 'public_link_opened';
-- alter table public.product_events drop constraint product_events_event_name_check;
-- alter table public.product_events add constraint product_events_event_name_check
--   check (event_name in ('session_started','community_viewed','community_created',
--     'community_joined','match_viewed','match_registered','match_withdrawn',
--     'teams_viewed','result_viewed','share_used'));
-- alter table public.product_events drop constraint if exists product_events_share_type_check;
-- alter table public.product_events drop column if exists share_type;
-- alter table public.product_events drop column if exists source;
-- commit;
--
-- After any rollback, remove the version from supabase_migrations.schema_migrations
-- only if the Product Owner wants 0079 re-applied later under the same name.
