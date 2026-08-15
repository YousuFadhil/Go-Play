-- The line a Professional Guest cannot cross.
--
-- A guest plays in a match, may score in it, and may be named its best player.
-- None of that may ever reach a career record: no `player_statistics` row, no
-- `rating_history` entry, no `community_statistics` figure. The guest has no
-- account to attach any of it to, and inventing one is the thing the product
-- rules refuse most explicitly.
--
-- Migration `0044` did most of this by leaving those three tables alone --
-- `user_id` there is still `NOT NULL` and still a foreign key to `users`, so a
-- guest is not a value they can hold. What remains is the handful of
-- **projections** that read a match-level table and write a user-level one.
-- Each of those now reads a nullable `user_id`, and a null flowing through would
-- not be silently ignored:
--
--   * `match_result_contribution` would emit a row keyed on a null user, which
--     `apply_match_statistics` inserts into `player_statistics` -- a not-null
--     violation on the primary key, taking the whole result recording with it.
--   * `player_statistics_evidence` would produce a null group, and
--     `rebuild_player_statistics` would try to write it.
--   * `apply_match_rating_effects` would hand a null to `apply_rating_delta`.
--
-- So this migration states the boundary once per projection: **only rows with a
-- `user_id` are projected into user-level statistics and ratings.** It is four
-- predicates and one guard, and together they are the whole guarantee.
--
-- What is deliberately *not* filtered: `match_results`, `match_goals` and
-- `match_team_assignments` themselves. A guest still appears in the score, in
-- the goals that add up to it, and in the lineup that played it. Match-level
-- data is exactly where a guest belongs -- it is the projection out of it that
-- stops.
--
-- Backward compatible: no table, column, constraint, policy or grant changes,
-- and for a match with no guests every function below returns precisely what it
-- returned before. Idempotent: `create or replace` throughout.

-- 1) The single piece of arithmetic both statistics levels read -------------------
-- Migration `0023`'s function. `match_community_contribution` (migration `0028`)
-- cross-joins this one, so the predicate added here reaches the community level
-- too -- and through it `rebuild_community_statistics` and
-- `reconcile_community_statistics`, which both read the contribution rather than
-- the lineup. One predicate, four consumers, no chance for them to disagree.
create or replace function public.match_result_contribution(p_match_id uuid)
returns table (
  user_id uuid,
  played int,
  won int,
  lost int,
  drawn int,
  scored int,
  mvp int
)
language sql
security definer
stable
set search_path = public
as $$
  select
    a.user_id,
    1,
    case
      when (a.team = 'A' and r.team_a_score > r.team_b_score)
        or (a.team = 'B' and r.team_b_score > r.team_a_score)
      then 1 else 0 end,
    case
      when (a.team = 'A' and r.team_a_score < r.team_b_score)
        or (a.team = 'B' and r.team_b_score < r.team_a_score)
      then 1 else 0 end,
    case when r.team_a_score = r.team_b_score then 1 else 0 end,
    coalesce(g.goals, 0),
    case when a.user_id = r.mvp_user_id then 1 else 0 end
  from match_results r
  join match_team_assignments a on a.match_id = r.match_id
  left join match_goals g
    on g.match_id = a.match_id and g.user_id = a.user_id
  -- CHANGED: a Professional Guest contributes to the match and to nothing
  -- beyond it. This is the whole of "no persistent player statistics" and, by
  -- way of match_community_contribution, of "no community statistics" as well.
  where r.match_id = p_match_id
    and a.user_id is not null;
$$;

revoke execute on function public.match_result_contribution(uuid)
  from anon, authenticated, public;

-- 2) The repair path's evidence ---------------------------------------------------
-- Migration `0032`'s function, which `rebuild_player_statistics` writes straight
-- into `player_statistics`. Without the predicate a match with guests would make
-- the repair produce a null-keyed group -- and the repair is precisely the thing
-- that has to be trustworthy when something else has already gone wrong.
create or replace function public.player_statistics_evidence(
  p_user_id uuid default null
)
returns table (
  user_id uuid,
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
    a.user_id,
    count(distinct a.match_id)::int,
    count(*) filter (
      where (a.team = 'A' and r.team_a_score > r.team_b_score)
         or (a.team = 'B' and r.team_b_score > r.team_a_score))::int,
    count(*) filter (
      where (a.team = 'A' and r.team_a_score < r.team_b_score)
         or (a.team = 'B' and r.team_b_score < r.team_a_score))::int,
    count(*) filter (where r.team_a_score = r.team_b_score)::int,
    coalesce(sum(g.goals), 0)::int,
    count(*) filter (where a.user_id = r.mvp_user_id)::int
  from match_results r
  join match_team_assignments a on a.match_id = r.match_id
  left join match_goals g
    on g.match_id = a.match_id and g.user_id = a.user_id
  -- CHANGED: guest lineup rows are not evidence of anybody's career.
  where a.user_id is not null
    and (p_user_id is null or a.user_id = p_user_id)
  group by a.user_id;
$$;

revoke execute on function public.player_statistics_evidence(uuid)
  from anon, authenticated, public;

-- 3) The rating engine --------------------------------------------------------------
-- Migration `0035`'s function and its approved values, unchanged:
--
--   winner +0.10   loser -0.10   draw nothing
--   goal   +0.02 each, capped at +0.10 in one match
--   MVP    +0.05
--
-- Two predicates are added and nothing else. A guest earns no rating because a
-- guest has no rating: `users.overall_rating` is the only rating there is, and
-- there is no `users` row.
--
-- The MVP branch needs no new guard. It reads `mvp_user_id`, which stays null
-- when the best player was a guest -- migration `0044` gave the guest MVP its
-- own column precisely so that the two cannot be confused, and the existing
-- `is not null` test already means "no user was named, so no user is awarded".
create or replace function public.apply_match_rating_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result match_results%rowtype;
  r record;
begin
  select * into v_result from match_results where match_id = p_match_id;
  if not found then return; end if;

  -- Outcome first, then goals, then the MVP. Any order reaches the same rating;
  -- a fixed one makes the audit read the same way every time.
  --
  -- A draw takes this branch not at all: it is the absence of a win and of a
  -- loss, so a drawn side gets no entry from the outcome.
  if v_result.team_a_score <> v_result.team_b_score then
    for r in
      select a.user_id,
        case
          when (a.team = 'A' and v_result.team_a_score > v_result.team_b_score)
            or (a.team = 'B' and v_result.team_b_score > v_result.team_a_score)
          then 'WIN' else 'LOSS' end as outcome
      from match_team_assignments a
      where a.match_id = p_match_id
        -- CHANGED: a guest wins and loses the match, and no rating moves.
        and a.user_id is not null
      order by a.team, a.user_id
    loop
      perform apply_rating_delta(
        r.user_id, p_match_id, r.outcome,
        case when r.outcome = 'WIN' then 0.10 else -0.10 end
      );
    end loop;
  end if;

  -- One entry per scorer, carrying the whole of what their goals were worth.
  -- `least` is the cap: five goals reach 0.10 exactly and a sixth adds nothing.
  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
      -- CHANGED: a guest's goals count towards the score and towards no rating.
      and g.user_id is not null
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', least(0.10, 0.02 * r.goals)
    );
  end loop;

  -- No MVP, no MVP award. The absence of a rating change is what "do not award"
  -- means here, and it is also what makes a later correction exact: there is no
  -- entry to reverse, so naming an MVP afterwards is an ordinary re-record.
  if v_result.mvp_user_id is not null then
    perform apply_rating_delta(
      v_result.mvp_user_id, p_match_id, 'MVP', 0.05
    );
  end if;
end;
$$;

revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;

-- 4) The last door, closed from the inside ---------------------------------------------
-- Migration `0022`'s function, with one guard added at the top.
--
-- Every predicate above stops a null before it reaches here, so this is
-- redundant by design -- and that is the point. `apply_rating_delta` is the
-- single place a rating moves and the single place a `rating_history` row is
-- written, so a caller that ever slips a null past the projections is refused by
-- the writer itself rather than by a foreign key several frames away.
--
-- It returns rather than raising, which is the behaviour the existing "the
-- account is gone" branch already has two lines below: there is no rating to
-- move and nothing to record against it.
create or replace function public.apply_rating_delta(
  p_user_id uuid,
  p_match_id uuid,
  p_reason text,
  p_delta numeric,
  p_reverses_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before numeric(4,2);
  v_after numeric(4,2);
begin
  -- CHANGED: there is no such thing as a guest's rating. Nothing should reach
  -- this with a null after migration 0046's predicates; this is the statement
  -- that it can never matter if something does.
  if p_user_id is null then return; end if;

  select overall_rating into v_before
  from users where id = p_user_id
  for update;
  -- The account is gone. There is no rating to move and nothing to record
  -- against it; the caller is reversing or applying a match it still remembers.
  if not found then return; end if;

  v_after := least(10.00, greatest(0.00, v_before + p_delta));

  update users set overall_rating = v_after where id = p_user_id;

  insert into rating_history (
    user_id, match_id, change_reason, delta,
    rating_before, rating_after, reverses_id
  )
  values (
    p_user_id, p_match_id, p_reason, v_after - v_before,
    v_before, v_after, p_reverses_id
  );
end;
$$;

revoke execute on function public.apply_rating_delta(uuid, uuid, text, numeric,
  uuid) from anon, authenticated, public;
