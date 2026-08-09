-- Results, ratings and player statistics.
--
-- What a played match leaves behind: the score, who scored it, who was best on
-- the pitch, what that did to every participant's rating, and the counters that
-- follow from it.
--
-- Four tables, one entry point. `record_match_result` is the only way any of
-- this is written, because the six things it does are one thing: a result whose
-- ratings were applied but whose statistics were not is not a partial success,
-- it is corruption. A plpgsql body is a single transaction, so the whole of it
-- lands or none of it does.
--
-- The rating arithmetic lives here rather than in the client. `OP-1` makes the
-- rating system-managed, so no policy lets a client write `users.overall_rating`
-- and no client is trusted to say what a win is worth. The approved constants
-- are restated in Dart as `ratingRules` so the rule is unit-testable, and the
-- integration suite asserts the two agree.
--
-- Backward compatible: no table is dropped, no column is renamed, every existing
-- row stays valid, and no existing policy or function changes. Idempotent: every
-- statement is `if not exists`, `or replace`, or guarded.

-- 1) Rating precision ----------------------------------------------------------
-- The approved engine moves a rating by 0.05 for a goal. `numeric(3,1)` cannot
-- hold that: a single goal would round to nothing or to a tenth, two goals would
-- be indistinguishable from one, and — worse — rounding is not reversible, which
-- the modification rules require it to be.
--
-- So the stored scale widens to two decimal places. Every existing value is a
-- tenth and survives unchanged, the approved 0.0-10.0 range is untouched, and
-- `OP-1`'s one-decimal *presentation* is a display question this does not touch.
-- The guard keeps a re-run from rewriting the table for nothing.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'overall_rating'
      and numeric_scale <> 2
  ) then
    alter table public.users
      alter column overall_rating type numeric(4,2);
    alter table public.users
      alter column overall_rating set default 5.00;
  end if;
end $$;

-- 1b) The rating is system-managed, stated where it holds -----------------------
-- `OP-1` says the rating is system-managed, and until now nothing enforced it.
-- `users_update_own_profile` allows a signed-in player to update their own row,
-- and a policy cannot restrict which *columns* an update touches — so a client
-- could set its own `overall_rating` to 10.0, and the engine below would read it
-- as if it had been earned. An engine whose input any client may write is
-- decoration, so the privilege is narrowed to the columns a player owns.
--
-- What a player may still write is exactly what they could write before, minus
-- the rating: the profile fields the registration and profile screens send.
-- `is_active` is left out because soft deletion is administrative, and
-- `overall_rating` because this migration is what earns it.
--
-- `security definer` functions are unaffected: they run as the owner, which is
-- how `record_match_result` moves a rating that nothing else can.
revoke update on public.users from authenticated;
grant update (phone, full_name, primary_position, secondary_position,
  date_of_birth) on public.users to authenticated;

-- 2) The result ----------------------------------------------------------------
-- One row per match, which is how "exactly one MVP per match" is stated: the
-- MVP is a NOT NULL column of a row that is unique per match, so there is no
-- shape in which a match has two of them or none.
--
-- `recorded_by` is attribution, never authorization — the same reading
-- `matches.created_by` gets (PD-16). It is nullable and clears itself when the
-- account goes, so recording a result can never be the reason a user cannot be
-- deleted.
create table if not exists public.match_results (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique
    references public.matches (id) on delete cascade,
  team_a_score int not null check (team_a_score >= 0),
  team_b_score int not null check (team_b_score >= 0),
  mvp_user_id uuid not null references public.users (id) on delete cascade,
  recorded_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists match_results_set_updated_at on public.match_results;
create trigger match_results_set_updated_at
  before update on public.match_results
  for each row
  execute function public.set_updated_at();

-- 3) The goals -----------------------------------------------------------------
-- One row per scorer per match, carrying how many they scored. A hat-trick is
-- one row saying three, not three rows saying one: no approved document asks for
-- the minute a goal was scored or the order of them, and rows that recorded
-- neither would be three copies of the same fact.
--
-- `goals > 0` because the row asserts that this player scored. Nobody scoring
-- nothing is the absence of a row, and a match with no goals has none at all.
--
-- The reference is to the *result*, not to the match: a goal is part of a
-- recorded score, and one belonging to a match that has no result would be a
-- number nothing adds up. A deleted match still takes them with it, one cascade
-- further along.
create table if not exists public.match_goals (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null
    references public.match_results (match_id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  goals int not null check (goals > 0),
  created_at timestamptz not null default now(),
  unique (match_id, user_id)
);

create index if not exists match_goals_user_id_idx
  on public.match_goals (user_id);

-- 4) The rating audit ----------------------------------------------------------
-- Every rating change, immutable, forever.
--
-- `delta` is the change that was *applied*, which is what makes reversal exact.
-- It equals the approved constant except at the ends of the 0.0-10.0 range,
-- where a player at 10.00 who wins gains nothing — and subtracting the constant
-- from them later would invent a rating they never held.
--
-- `reverses_id` is how a reversal is recorded without touching what it reverses.
-- An original entry has none; a reversal names the row it undoes. "Still in
-- effect" is therefore a query, not a flag somebody has to keep up to date, and
-- no historical row is ever written twice.
--
-- `entry_no` orders entries within a transaction, where `created_at` cannot: a
-- reversal walks a player's changes backwards so that no intermediate rating
-- falls outside the range, and `now()` is the same instant for all of them.
create table if not exists public.rating_history (
  id uuid primary key default gen_random_uuid(),
  entry_no bigint generated always as identity,
  user_id uuid not null references public.users (id) on delete cascade,
  match_id uuid not null references public.matches (id) on delete cascade,
  change_reason text not null
    check (change_reason in ('WIN', 'LOSS', 'GOAL', 'MVP', 'REVERSAL')),
  delta numeric(4,2) not null,
  rating_before numeric(4,2) not null,
  rating_after numeric(4,2) not null,
  reverses_id uuid references public.rating_history (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists rating_history_user_id_idx
  on public.rating_history (user_id);
create index if not exists rating_history_match_id_idx
  on public.rating_history (match_id);

-- A row may be reversed once. Two reversals of one entry would subtract a change
-- that was only ever applied once.
create unique index if not exists rating_history_reverses_id_idx
  on public.rating_history (reverses_id)
  where reverses_id is not null;

-- Immutability, stated where it cannot be worked around. The policies below
-- grant no UPDATE and no DELETE, which settles it for every client; this settles
-- it for the `security definer` functions too, which run past RLS. Deletion is
-- deliberately not blocked: a deleted match takes its own audit with it, the way
-- every other row under a match does.
create or replace function public.reject_rating_history_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'RATING_HISTORY_IMMUTABLE';
end;
$$;

drop trigger if exists rating_history_immutable on public.rating_history;
create trigger rating_history_immutable
  before update on public.rating_history
  for each row
  execute function public.reject_rating_history_update();

-- 5) The counters --------------------------------------------------------------
-- One row per player, across every community they play in — the same scope the
-- rating already has. A per-community split would be a second answer to "how
-- good is this player" sitting next to `users.overall_rating`, and no approved
-- document asks for one.
--
-- The current rating is deliberately absent. It is `users.overall_rating`, which
-- this migration's own functions maintain; a copy here would be a second
-- number for the same thing, free to disagree. The application reads it by
-- joining, exactly as §5.1's out-of-position marker is derived rather than
-- stored.
create table if not exists public.player_statistics (
  user_id uuid primary key references public.users (id) on delete cascade,
  matches_played int not null default 0 check (matches_played >= 0),
  wins int not null default 0 check (wins >= 0),
  losses int not null default 0 check (losses >= 0),
  draws int not null default 0 check (draws >= 0),
  goals int not null default 0 check (goals >= 0),
  mvp_count int not null default 0 check (mvp_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists player_statistics_set_updated_at
  on public.player_statistics;
create trigger player_statistics_set_updated_at
  before update on public.player_statistics
  for each row
  execute function public.set_updated_at();

-- 6) Applying one rating change ------------------------------------------------
-- The single place a rating moves. It clamps to the approved range, records what
-- it actually did, and writes the audit row in the same statement — so a rating
-- that changed without an audit entry is not a state this schema can reach.
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

-- 7) Reversing what a match did ------------------------------------------------
-- Undoes every rating change this match still has in effect, newest first.
--
-- Newest first is the guarantee, not a preference. Walking back through the
-- states a player actually held means every intermediate value is one the range
-- already accepted, so no clamp fires on the way out and the player lands on the
-- rating they had before the match was recorded.
--
-- Nothing is edited or removed. Each reversal is a new row pointing at the one
-- it undoes, so the audit after a correction says what was recorded, that it was
-- taken back, and what replaced it.
create or replace function public.reverse_match_rating_effects(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select h.id, h.user_id, h.delta
    from rating_history h
    where h.match_id = p_match_id
      and h.reverses_id is null
      and not exists (
        select 1 from rating_history x where x.reverses_id = h.id
      )
    order by h.entry_no desc
  loop
    perform apply_rating_delta(r.user_id, p_match_id, 'REVERSAL', -r.delta, r.id);
  end loop;
end;
$$;

-- Adds this match's contribution to every participant's counters, or takes it
-- away again when [p_sign] is -1.
--
-- The participants are the stored lineup — `KB-017` makes that the record of who
-- actually played, and a win belongs to the side a player was on. Reversal reads
-- the same lineup and the result rows that are still there, so it subtracts
-- exactly what was added.
create or replace function public.apply_match_statistics(
  p_match_id uuid,
  p_sign int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result match_results%rowtype;
begin
  select * into v_result from match_results where match_id = p_match_id;
  if not found then return; end if;

  insert into player_statistics as ps (
    user_id, matches_played, wins, losses, draws, goals, mvp_count
  )
  select
    a.user_id,
    p_sign,
    p_sign * (case
      when (a.team = 'A' and v_result.team_a_score > v_result.team_b_score)
        or (a.team = 'B' and v_result.team_b_score > v_result.team_a_score)
      then 1 else 0 end),
    p_sign * (case
      when (a.team = 'A' and v_result.team_a_score < v_result.team_b_score)
        or (a.team = 'B' and v_result.team_b_score < v_result.team_a_score)
      then 1 else 0 end),
    p_sign * (case
      when v_result.team_a_score = v_result.team_b_score
      then 1 else 0 end),
    p_sign * coalesce(g.goals, 0),
    p_sign * (case when a.user_id = v_result.mvp_user_id then 1 else 0 end)
  from match_team_assignments a
  left join match_goals g
    on g.match_id = a.match_id and g.user_id = a.user_id
  where a.match_id = p_match_id
  on conflict (user_id) do update set
    matches_played = ps.matches_played + excluded.matches_played,
    wins = ps.wins + excluded.wins,
    losses = ps.losses + excluded.losses,
    draws = ps.draws + excluded.draws,
    goals = ps.goals + excluded.goals,
    mvp_count = ps.mvp_count + excluded.mvp_count;
end;
$$;

-- Applies the approved rating engine to a match whose result and goals are
-- already stored.
--
--   winner  +0.10   loser  -0.10   goal  +0.05 each   MVP  +0.20
--
-- A draw produces neither a win nor a loss, so drawn sides get no entry from the
-- outcome — the goals and the MVP still count. This is the only statement of
-- these constants in the database; `ratingRules` in Dart is the same statement
-- for the application, and the integration suite holds them to each other.
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
  if v_result.team_a_score <> v_result.team_b_score then
    for r in
      select a.user_id,
        case
          when (a.team = 'A' and v_result.team_a_score > v_result.team_b_score)
            or (a.team = 'B' and v_result.team_b_score > v_result.team_a_score)
          then 'WIN' else 'LOSS' end as outcome
      from match_team_assignments a
      where a.match_id = p_match_id
      order by a.team, a.user_id
    loop
      perform apply_rating_delta(
        r.user_id, p_match_id, r.outcome,
        case when r.outcome = 'WIN' then 0.10 else -0.10 end
      );
    end loop;
  end if;

  for r in
    select g.user_id, g.goals
    from match_goals g
    where g.match_id = p_match_id
    order by g.user_id
  loop
    perform apply_rating_delta(
      r.user_id, p_match_id, 'GOAL', 0.05 * r.goals
    );
  end loop;

  perform apply_rating_delta(
    v_result.mvp_user_id, p_match_id, 'MVP', 0.20
  );
end;
$$;

revoke execute on function public.apply_rating_delta(uuid, uuid, text, numeric,
  uuid) from anon, authenticated, public;
revoke execute on function public.reverse_match_rating_effects(uuid)
  from anon, authenticated, public;
revoke execute on function public.apply_match_statistics(uuid, int)
  from anon, authenticated, public;
revoke execute on function public.apply_match_rating_effects(uuid)
  from anon, authenticated, public;

-- 8) Recording a result --------------------------------------------------------
-- The only entry point, and the only one there should be: recording a result for
-- the first time and correcting one already recorded are the same operation with
-- the same rules, and two functions would be two chances for them to drift.
--
-- What it does, in order:
--   1. checks the caller may manage this match
--   2. checks the result against the approved rules
--   3. reverses the rating changes the previous result made, if there was one
--   4. reverses the statistics it produced
--   5. replaces the stored result and its goals
--   6. applies the new rating changes, recording each one
--   7. applies the new statistics
--
-- Steps 3 and 4 are skipped when there is nothing to reverse, which is what
-- makes the first recording and a correction the same call.
--
-- `p_goals` is `[{"user_id": "...", "goals": 2}, ...]`, one entry per scorer.
create or replace function public.record_match_result(
  p_match_id uuid,
  p_team_a_score int,
  p_team_b_score int,
  p_mvp_user_id uuid,
  p_goals jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participants int;
  v_total_goals int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform 1 from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  -- Management is a community role (PD-07, PD-16): the same predicate that gates
  -- the lineup gates its result. Who created the match is attribution.
  if not public.is_match_community_admin(p_match_id, auth.uid()) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_team_a_score < 0 or p_team_b_score < 0 then
    raise exception 'INVALID_SCORE';
  end if;

  -- Who played is the stored lineup. Without one there is no side for a player
  -- to have been on, so there is no winner to reward and no loser to charge —
  -- the rating engine has nothing to work from and the result cannot be taken.
  select count(*) into v_participants
  from match_team_assignments where match_id = p_match_id;
  if v_participants = 0 then
    raise exception 'LINEUP_REQUIRED';
  end if;

  if p_goals is null or jsonb_typeof(p_goals) <> 'array' then
    raise exception 'INVALID_GOALS';
  end if;

  -- A scorer's entry says they scored, so nothing and less than nothing are both
  -- refused rather than quietly dropped.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where coalesce((e->>'goals')::int, 0) <= 0
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- Two entries for one player is not a bigger number, it is the same fact
  -- recorded twice, and which of them counted would be arbitrary.
  if (
    select count(distinct e->>'user_id') from jsonb_array_elements(p_goals) as e
  ) <> jsonb_array_length(p_goals) then
    raise exception 'INVALID_GOALS';
  end if;

  select coalesce(sum((e->>'goals')::int), 0) into v_total_goals
  from jsonb_array_elements(p_goals) as e;

  if v_total_goals <> p_team_a_score + p_team_b_score then
    raise exception 'GOALS_DO_NOT_MATCH_SCORE';
  end if;

  if not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id = p_mvp_user_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- A goal is credited to somebody who played it. Otherwise a rating could be
  -- raised for a player who was never in the match.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where not exists (
      select 1 from match_team_assignments a
      where a.match_id = p_match_id
        and a.user_id = (e->>'user_id')::uuid
    )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- Nothing has been written yet: everything above refuses before the previous
  -- result is disturbed. From here the old result comes apart and the new one
  -- goes on, in one transaction.
  perform reverse_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, -1);

  delete from match_goals where match_id = p_match_id;

  insert into match_results (
    match_id, team_a_score, team_b_score, mvp_user_id, recorded_by
  )
  values (
    p_match_id, p_team_a_score, p_team_b_score, p_mvp_user_id, auth.uid()
  )
  on conflict (match_id) do update set
    team_a_score = excluded.team_a_score,
    team_b_score = excluded.team_b_score,
    mvp_user_id = excluded.mvp_user_id,
    recorded_by = excluded.recorded_by;

  insert into match_goals (match_id, user_id, goals)
  select p_match_id, (e->>'user_id')::uuid, (e->>'goals')::int
  from jsonb_array_elements(p_goals) as e;

  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;

revoke execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb) from anon, public;
grant execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb) to authenticated;

-- 9) A deleted match takes its effects with it ---------------------------------
-- Deleting a match already removes its result, its goals and its audit by
-- cascade. Without this it would leave the ratings and the counters that result
-- produced standing, credited to a match that no longer exists and with nothing
-- left to explain them.
--
-- It runs `before delete on matches`, which is the only point where all of it is
-- still there: the referential actions that clear the children are performed
-- after this fires, so the reversal reads a complete picture. The deliberate
-- consequence is that deletion stays time-independent, as `delete_match` says it
-- is — a recorded result makes a match no harder to remove, only tidier to.
create or replace function public.reverse_match_effects_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform apply_match_statistics(old.id, -1);
  perform reverse_match_rating_effects(old.id);
  return old;
end;
$$;

drop trigger if exists matches_reverse_result_effects on public.matches;
create trigger matches_reverse_result_effects
  before delete on public.matches
  for each row
  execute function public.reverse_match_effects_before_delete();

-- 10) Authorization ------------------------------------------------------------
-- Reading a result, its goals and the lineup's ratings is a member's business,
-- the same way reading the lineup is. Writing any of it is not a client
-- operation at all: `record_match_result` is the only writer, it runs
-- `security definer`, and the absence of an insert, update or delete policy is
-- what says so.
--
-- `rating_history` gets select and nothing else, which is the immutability the
-- audit promises. `player_statistics` is world-readable to members of the app —
-- counters are not private to their owner, and a leaderboard is the obvious next
-- reader — while remaining unwritable from any client.
alter table public.match_results enable row level security;
alter table public.match_goals enable row level security;
alter table public.rating_history enable row level security;
alter table public.player_statistics enable row level security;

drop policy if exists "match_results_select_members" on public.match_results;
create policy "match_results_select_members"
  on public.match_results
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

drop policy if exists "match_goals_select_members" on public.match_goals;
create policy "match_goals_select_members"
  on public.match_goals
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

drop policy if exists "rating_history_select_members" on public.rating_history;
create policy "rating_history_select_members"
  on public.rating_history
  for select
  to authenticated
  using (public.is_match_community_member(match_id, auth.uid()));

drop policy if exists "player_statistics_select_authenticated"
  on public.player_statistics;
create policy "player_statistics_select_authenticated"
  on public.player_statistics
  for select
  to authenticated
  using (true);
