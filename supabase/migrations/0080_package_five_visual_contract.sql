-- ============ migrations/0080_package_five_visual_contract.sql ============
-- Package 5, visual contract: the two facts the approved Player Profile needs
-- and `0079` does not return.
--
--   1. Recent Form gains the scoreline -- `score_for` and `score_against`, the
--      final score of the player's own team and of the other one. The approved
--      design writes it under each W / D / L, and the app cannot derive it: a
--      form row carries an outcome, not a score.
--
--   2. Recent Highlight gains `period_key` -- the stored snapshot's own period
--      identity ("2026-W37", "2026-09"). The approved design writes "Week 37",
--      and deriving a week number in the client from a timestamp would be a
--      second opinion about which week an award belongs to; the snapshot
--      already owns that answer, so it is returned rather than recomputed.
--
-- ## WHAT THIS DOES NOT DO
--
-- Nothing here loosens `0079`'s boundary, and nothing here is new data:
--
--   * no new table, no new column, no write path, no trigger;
--   * no new grant -- the four functions below are re-granted to exactly the
--     roles `0079` gave them, and `anon` still reaches only the two `public_*`
--     ones;
--   * the public Recent Form still carries no match id, no community id and no
--     kick-off time. A scoreline is the result of a match that the player's own
--     profile already says they won or lost; it names no fixture.
--
-- ## WHY DROP AND CREATE
--
-- Postgres cannot change a function's OUT columns in place ("cannot change
-- return type of existing function"), so each function is dropped and recreated
-- with its original signature. `0079` wrote every body as a quoted string, so
-- no dependency is tracked between them and nothing else has to be rebuilt; the
-- migration runs in one transaction, so no caller ever sees a missing function.
--
-- **Backward compatible by construction.** Every column `0079` returned is
-- still returned, with the same name, type and position; the new ones are
-- appended. A caller that selects by name -- which is every caller, PostgREST
-- included -- is unaffected, and the app build running in production today
-- keeps working against this.
--
-- Append-only. Nothing in `0022`-`0079` is edited.

-- ============================================================================
-- 1) player_recent_form() -- now with the scoreline
-- ============================================================================
-- The scores come from `match_results`, which the window already joins to
-- decide that the match has a result at all; the player's side comes from the
-- same `match_team_assignments` row the window is selected by. So the pair is
-- read from the two rows already in hand, and `match_result_contribution`
-- remains the only thing that decides what a win is -- the outcome below is
-- still its answer, not a comparison made here.
drop function if exists public.player_recent_form(uuid, int);

create function public.player_recent_form(
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
  is_mvp boolean,
  -- The final score of the team this player was assigned to, and of the other
  -- one. Always both or neither: a row is in this window only because a result
  -- exists for it.
  score_for int,
  score_against int
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
      m.start_at,
      case when a.team = 'A' then r.team_a_score else r.team_b_score end
                   as score_for,
      case when a.team = 'A' then r.team_b_score else r.team_a_score end
                   as score_against
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
    k.mvp = 1,
    recent.score_for,
    recent.score_against
  from recent
  join lateral match_result_contribution(recent.match_id) k
    on k.user_id = p_user_id
  order by recent.start_at desc, recent.match_id desc;
$$;

comment on function public.player_recent_form(uuid, int) is
  'One player''s last N completed matches, newest first, as outcome, goals, '
  'MVP and the scoreline from that player''s side. Derived from '
  'match_result_contribution -- the same function the career counters are '
  'applied from -- so form and totals describe one truth. p_limit is clamped '
  'to 1..10. Readable by any signed-in player, exactly as player_profile is; '
  'anon reaches the reduced form through public_player_recent_form -- see '
  'migrations 0079 and 0080.';

revoke execute on function public.player_recent_form(uuid, int)
  from anon, public;
grant execute on function public.player_recent_form(uuid, int)
  to authenticated;
grant execute on function public.player_recent_form(uuid, int)
  to service_role;

-- ============================================================================
-- 2) public_player_recent_form() -- the same scoreline, still no fixture
-- ============================================================================
-- What is added is two integers describing the result of a match this contract
-- already reports the outcome of. What is still absent is everything that would
-- name the match: no id, no community, no date. Two scores and a W do not
-- identify a fixture, and `0057`'s boundary -- completed-match history stays
-- behind a session -- is untouched.
drop function if exists public.public_player_recent_form(uuid, int);

create function public.public_player_recent_form(
  p_user_id uuid,
  p_limit int default 5
)
returns table (
  -- `sequence_no`, not `position`: POSITION is a Postgres keyword and an OUT
  -- parameter named after one is a trap for whoever edits this next.
  sequence_no int,
  outcome text,
  goals int,
  is_mvp boolean,
  score_for int,
  score_against int
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
    f.is_mvp,
    f.score_for,
    f.score_against
  from public.player_recent_form(p_user_id, p_limit) f
  join users u on u.id = p_user_id and u.is_active
  order by f.start_at desc, f.match_id desc;
$$;

comment on function public.public_player_recent_form(uuid, int) is
  'The public Recent Form: the last N results newest first, as sequence_no, '
  'outcome, goals, MVP and the scoreline from the player''s side, for an '
  'active player. Carries no match id, no community id and no kick-off time, '
  'so it discloses the player''s record and never a fixture -- see migrations '
  '0079 and 0080.';

revoke execute on function public.public_player_recent_form(uuid, int)
  from public;
grant execute on function public.public_player_recent_form(uuid, int)
  to anon, authenticated, service_role;

-- ============================================================================
-- 3) player_recent_highlights() -- now carrying the period it is about
-- ============================================================================
-- `period_key` is the snapshot's own column, written by
-- `record_team_of_period_snapshot` from `statistics_period_key` and checked
-- against the canonical window before the award was stored. It is null on an
-- MVP, which is a match rather than a period.
drop function if exists public.player_recent_highlights(uuid);

create function public.player_recent_highlights(p_user_id uuid)
returns table (
  highlight_type text,
  occurred_at timestamptz,
  community_id uuid,
  community_name text,
  match_id uuid,
  period_type text,
  period_key text
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
      null::text,
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
      s.period_type,
      s.period_key
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
  'end, and carrying that period''s stored key), in active communities only. '
  'The client chooses between them -- see migrations 0079 and 0080.';

revoke execute on function public.player_recent_highlights(uuid)
  from anon, public;
grant execute on function public.player_recent_highlights(uuid)
  to authenticated;
grant execute on function public.player_recent_highlights(uuid)
  to service_role;

-- ============================================================================
-- 4) public_player_recent_highlight() -- the same period identity
-- ============================================================================
-- A period key names a week or a month, not a fixture and not a community, so
-- it discloses nothing the period type and the date did not already say -- it
-- says it precisely enough to be printed.
drop function if exists public.public_player_recent_highlight(uuid);

create function public.public_player_recent_highlight(p_user_id uuid)
returns table (
  highlight_type text,
  occurred_at timestamptz,
  community_name text,
  period_type text,
  period_key text
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
    h.period_type,
    h.period_key
  from public.player_recent_highlights(p_user_id) h
  join users u on u.id = p_user_id and u.is_active;
$$;

comment on function public.public_player_recent_highlight(uuid) is
  'The public Recent Highlight candidates: at most one MVP and one stored Team '
  'of Period award, as kind, date, period type, period key and community name, '
  'for an active player in active communities. No ids -- see migrations 0079 '
  'and 0080.';

revoke execute on function public.public_player_recent_highlight(uuid)
  from public;
grant execute on function public.public_player_recent_highlight(uuid)
  to anon, authenticated, service_role;
