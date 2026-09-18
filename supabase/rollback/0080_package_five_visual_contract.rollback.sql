-- ======= rollback/0080_package_five_visual_contract.rollback.sql =======
-- Puts the four Package 5 read models back exactly as migration `0079` left
-- them: the scoreline columns and the period key disappear, and every other
-- column, grant and comment is the shipped 0079 text, extracted from that
-- migration rather than retyped.
--
-- Non-destructive by construction: `0080` created no table, wrote no row and
-- changed no privilege, so undoing it is four `drop function` / `create
-- function` pairs and nothing else. No data can be lost by running this.
--
-- A front end built against `0080` and pointed at a database rolled back to
-- `0079` loses the scorelines and the week number -- both are drawn only when
-- present, so it degrades to the 0079 presentation rather than failing.
--
-- Run the whole file in one transaction.


-- --- public.player_recent_form(uuid, int) ---
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


-- --- public.public_player_recent_form(uuid, int) ---
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


-- --- public.player_recent_highlights(uuid) ---
drop function if exists public.player_recent_highlights(uuid);

create function public.player_recent_highlights(p_user_id uuid)
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


-- --- public.public_player_recent_highlight(uuid) ---
drop function if exists public.public_player_recent_highlight(uuid);

create function public.public_player_recent_highlight(p_user_id uuid)
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
