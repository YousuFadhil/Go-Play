-- ============================================================================
-- 0109 -- Community Overall rating on the weighted Global formula (DD-31)
-- ============================================================================
-- `community_scoped_rating` (0081) re-derived every period from the legacy
-- additive values. The Global Rating has run on the weighted engine since the
-- 0108 activation, so a community's all-time (`'overall'`) rating no longer
-- matched it for a player who plays only there. This migration computes
-- `'overall'` with the same weighted formula, scoped to this community's
-- matches: for a single-community player it equals `users.overall_rating`.
--
-- `'weekly'` and `'monthly'` are unchanged, deliberately: a short window needs
-- a metric of its own, designed separately. Their code below is 0081's, line
-- for line.
--
-- Why this is one plain migration and not split like 0108: the function keeps
-- no state. Every call recomputes from the recorded results, so there is
-- nothing to rebase and nothing to activate; `create or replace` takes effect
-- on the next call, and the previous body is the rollback.
--
-- Population is unchanged (lineup, scorers and the MVP). A scorer or MVP
-- without a lineup row has no outcome, so the weighted engine cannot score
-- that match, here or in `replay_weighted_player_v1`; such a player keeps the
-- prior 5.000 with 0 matches if nothing else in scope counts.
create or replace function public.community_scoped_rating(
  p_community_id uuid,
  p_period_type text,
  p_period_key text
)
returns table (
  user_id uuid,
  rating numeric(5,3),
  matches_played int
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_player uuid;
  v_rating numeric(5,3);
  v_matches int;
  v_sum numeric;
  v_n integer;
  v_num numeric(50,24);
  v_den numeric(50,24);
  v_q constant numeric := 26::numeric / 27;
  r record;
  v_score numeric;
begin
  if p_period_type is null
     or p_period_type not in ('overall', 'weekly', 'monthly') then
    raise exception 'INVALID_PERIOD_TYPE';
  end if;
  if p_period_key is null then
    raise exception 'INVALID_PERIOD_KEY';
  end if;

  -- **Everybody `apply_match_rating_effects` would pay, and nobody else.** The
  -- engine pays participation and the outcome to the stored lineup, a goal
  -- award to every scorer in `match_goals`, and the MVP award to the result's
  -- own `mvp_user_id` -- and the last two do not require a lineup row. A
  -- population taken from the lineup alone would therefore differ from the
  -- Global Rating for a scorer or a best player who is not in it, which is a
  -- divergence this rating exists not to have.
  for v_player in
    select distinct e.user_id
    from (
      select a.user_id, a.match_id
      from match_team_assignments a
      where a.user_id is not null
      union
      select g.user_id, g.match_id
      from match_goals g
      where g.user_id is not null
      union
      select res.mvp_user_id, res.match_id
      from match_results res
      where res.mvp_user_id is not null
    ) e
    join matches m       on m.id = e.match_id
    join match_results x on x.match_id = m.id
    where m.community_id = p_community_id
      -- The project's own definition of completed (`0029`, `0037`).
      and (m.status = 'completed' or m.end_at <= now())
      and public.statistics_period_key(m.start_at, p_period_type) = p_period_key
  loop
    if p_period_type = 'overall' then
      -- The weighted Global formula. The seed (70/14 lifetime, 70/14 recency)
      -- and v_q MUST stay identical to public.replay_weighted_player_v1 (0108),
      -- the source of truth: if its constants change, change these with it.
      -- Per-match scores and storage come from the same functions it calls.
      v_sum := 70; v_n := 14;
      v_num := 70; v_den := 14;

      for r in
        select
          case when c.won = 1 then 'WIN' when c.lost = 1 then 'LOSS'
            else 'DRAW' end as outcome,
          c.scored,
          c.mvp = 1 as is_mvp
        from matches m
        join match_results res on res.match_id = m.id
        -- A lineup row is required: it is what gives the match an outcome.
        join lateral (
          select x.*
          from public.match_result_contribution(m.id) x
          where x.user_id = v_player
        ) c on true
        where m.community_id = p_community_id
          and (m.status = 'completed' or m.end_at <= now())
          and public.statistics_period_key(m.start_at, p_period_type)
                = p_period_key
        -- The Global rebase's order and tie-break.
        order by m.start_at, m.id
      loop
        v_score := public.weighted_match_score_v1(r.outcome, r.scored, r.is_mvp);
        v_sum := v_sum + v_score; v_n := v_n + 1;
        v_num := v_q * v_num + v_score; v_den := v_q * v_den + 1;
      end loop;

      user_id := v_player;
      rating := public.weighted_rating_storage_v1(
        (v_sum / v_n + v_num / v_den) / 2);
      matches_played := v_n - 14;
      return next;
      continue;
    end if;

    v_rating := 5.000;
    v_matches := 0;

    for r in
      select
        m.id as match_id,
        m.start_at,
        k.user_id is not null as played,
        coalesce(k.won, 0)  as won,
        coalesce(k.lost, 0) as lost,
        coalesce(g.goals, 0) as scored,
        res.mvp_user_id = v_player as is_mvp
      from matches m
      join match_results res on res.match_id = m.id
      -- The same function the Global engine decides a win from, for this
      -- player; absent when they were not in the lineup.
      left join lateral (
        select c.*
        from public.match_result_contribution(m.id) c
        where c.user_id = v_player
      ) k on true
      left join match_goals g
        on g.match_id = m.id and g.user_id = v_player
      where m.community_id = p_community_id
        and (m.status = 'completed' or m.end_at <= now())
        and public.statistics_period_key(m.start_at, p_period_type)
              = p_period_key
        and (
          k.user_id is not null
          or g.user_id is not null
          or res.mvp_user_id = v_player
        )
      -- Chronological, because the clamp makes the order matter -- and the
      -- same order, with the same tie-break, the Global rebase replays in.
      order by m.start_at, m.id
    loop
      v_matches := v_matches + 1;

      -- PARTICIPATION, then the outcome, then the goals, then the MVP --
      -- `0078`'s order, clamped after each, and each paid to exactly who
      -- `0078` pays it to.
      if r.played then
        v_rating := least(10.000, greatest(0.000, v_rating + 0.005));
        v_rating := least(10.000, greatest(0.000, v_rating + case
          when r.won  = 1 then 0.100
          when r.lost = 1 then -0.100
          else 0.010
        end));
      end if;
      if r.scored > 0 then
        v_rating := least(10.000, greatest(0.000,
          v_rating + least(0.070, 0.010 * r.scored)));
      end if;
      if r.is_mvp then
        v_rating := least(10.000, greatest(0.000, v_rating + 0.020));
      end if;
    end loop;

    user_id := v_player;
    rating := v_rating;
    matches_played := v_matches;
    return next;
  end loop;
end;
$$;

comment on function public.community_scoped_rating(uuid, text, text) is
  'The Community/Period Rating: one rating per player over the matches played '
  'in this community inside this statistics period, never stored, so a '
  'correction cannot leave it stale. ''overall'' uses the weighted Global '
  'formula (replay_weighted_player_v1, 0108) scoped to this community, so a '
  'player who plays only here gets their Global Rating; it requires a lineup '
  'row per match. ''weekly'' and ''monthly'' keep migration 0078''s additive '
  'values from 5.000, clamped at every step (0081). users.overall_rating and '
  'rating_history are untouched. See migrations 0081 and 0109.';
