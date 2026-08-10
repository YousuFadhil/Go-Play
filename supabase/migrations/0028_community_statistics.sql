-- Community Statistics — Level 2 counters, per player, per community, per period.
--
-- Builds `public.community_statistics` exactly as
-- `Docs/engineering/Community_Statistics_Table_Specification.md` v1.0 designs
-- it, and works through that document's §20 build instruction. Level 1
-- (`player_statistics`) is a career across every community; this is the same six
-- measures cut by two dimensions a career refuses — the community, and the
-- period. Neither derives from the other (DP-10): both derive from the same
-- evidence, which is what makes §16.3's reconciliation possible at all.
--
-- The eight build requirements and where each is met:
--
--   1. `CS-D2` settled          — resolved 2026-08-02; no rating column here
--   2. `A1` fixed in one place  — §1, `statistics_period_zone()`, FROZEN
--   3. reconciliation with the table, not after it — §9
--   4. rebuild operation        — §8
--   5. backfill every existing membership — §11
--   6. extend the shared helper — §5, over `match_result_contribution`
--   7. apply and reverse as separate statements — §6, `CS-C10`
--   8. read rule scoped to membership — §10, `CS-R4`
--
-- Backward compatible: no table is dropped, no column renamed, no existing
-- policy changed. One existing function is replaced — `apply_match_statistics`,
-- §7 — so that both levels move in one call and cannot diverge. Idempotent:
-- every statement is `if not exists`, `or replace`, or guarded.

-- 1) The period constant, stated once -------------------------------------------
-- `A1`. Every period this schema will ever derive reads it from here, which is
-- §16.5's first mitigation and the reason `CS-R2` is closed rather than open.
--
-- FROZEN. Changing this value silently re-buckets every figure already computed
-- into different weeks and months — no error, no warning, and nothing afterwards
-- can tell that it happened. It must not change while any row exists in
-- `community_statistics`. If a change is ever genuinely required, the only safe
-- route is to change it and immediately run `rebuild_community_statistics()`,
-- which recomputes every counter from the evidence under the new zone.
create or replace function public.statistics_period_zone()
returns text
language sql
immutable
set search_path = public
as $$
  select 'Asia/Muscat'::text;
$$;

comment on function public.statistics_period_zone() is
  'A1: the time zone every statistics period is derived in. FROZEN — changing '
  'it re-buckets existing figures silently. Change only together with a full '
  'rebuild_community_statistics() run.';

-- Which period of each kind a match falls in. `CS-C15`: derived from the match's
-- start (`A3`), in the zone above, in the formats `A2` fixes.
--
--   overall -> 'overall'          a period like any other, with a fixed key
--   weekly  -> '2026-W31'         ISO-8601 week, so it sorts chronologically
--   monthly -> '2026-08'          likewise
--
-- STABLE rather than IMMUTABLE: `timestamptz at time zone` depends on the
-- server's time-zone database, so it is not immutable in the strict sense. That
-- is honest and costs nothing here, because no index is built on this.
create or replace function public.statistics_period_key(
  p_start_at timestamptz,
  p_period_type text
)
returns text
language sql
stable
set search_path = public
as $$
  select case p_period_type
    when 'overall' then 'overall'
    when 'weekly'  then to_char(
      p_start_at at time zone public.statistics_period_zone(), 'IYYY-"W"IW')
    when 'monthly' then to_char(
      p_start_at at time zone public.statistics_period_zone(), 'YYYY-MM')
  end;
$$;

-- 2) The table -------------------------------------------------------------------
-- Twelve columns, four of them the key. One row is one player's counters, in one
-- community, over one period — not a community's summary and not a rating.
--
-- No surrogate `id`: nothing references this table, so one would have zero
-- consumers (§8.1). No rating column (item 11) — the Community Rating is one
-- value per (player, community) with no period, and carrying it here would
-- duplicate it across every period, each copy free to disagree. No eligibility
-- flag (§2.5): departure changes eligibility, not data, and a flag on a past
-- week would have to mean "is a member now", which is not a property of that
-- week. No period start/end dates: the key names the period and `A1`/`A2` define
-- its boundaries, so storing them would be a second answer that can drift.
--
-- The key order is community-first, player-last, and it is chosen for the
-- dominant read (§8.1): every leaderboard and dashboard figure fixes the
-- community and the period and wants all players, which is three equality
-- columns then the population. A key led by `user_id` would force every board to
-- scan.
create table if not exists public.community_statistics (
  community_id uuid not null
    references public.communities (id) on delete cascade,
  period_type text not null
    check (period_type in ('overall', 'weekly', 'monthly')),
  period_key text not null,
  user_id uuid not null references public.users (id) on delete cascade,
  matches_played int not null default 0 check (matches_played >= 0),
  wins int not null default 0 check (wins >= 0),
  losses int not null default 0 check (losses >= 0),
  draws int not null default 0 check (draws >= 0),
  goals int not null default 0 check (goals >= 0),
  mvp_count int not null default 0 check (mvp_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (community_id, period_type, period_key, user_id),
  -- `CS-C5`. Nothing in the approved documents states this and greenfield design
  -- has to supply it: without it `('overall', '2026-W31')` is storable, and a
  -- record naming a kind of period it does not cover is incoherent to the
  -- dashboard, to every board, and to the reconciliation alike — none of which
  -- would detect it. It would simply produce a figure nobody could explain, in a
  -- table with no history to explain it from.
  constraint community_statistics_period_coherent check (
    (period_type = 'overall' and period_key = 'overall')
    or (period_type = 'weekly'
        and period_key ~ '^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$')
    or (period_type = 'monthly'
        and period_key ~ '^\d{4}-(0[1-9]|1[0-2])$')
  )
);

comment on table public.community_statistics is
  'Level 2: one player''s six counters, in one community, over one period. '
  'Written only as a consequence of a result being recorded, corrected or '
  'removed. Never keyed by, referenced to, or cascaded from community_members '
  '(A7): a record outlives a departure and is found again on return (SL-4).';

-- `CS-X2`. Two uses that the primary key cannot serve, both real: a player's own
-- records in a community (the personal view, and `SL-4`'s rejoin lookup), and a
-- player's records across communities — which is what §16.3's check 1 needs to
-- compare the two levels. It also backs the cascade from `users`.
create index if not exists community_statistics_user_id_community_id_idx
  on public.community_statistics (user_id, community_id);

drop trigger if exists community_statistics_set_updated_at
  on public.community_statistics;
create trigger community_statistics_set_updated_at
  before update on public.community_statistics
  for each row
  execute function public.set_updated_at();

-- 3) The `overall` record appears when the player first joins ---------------------
-- `SL-4` and ERD §3.7: created on the first ever join, carrying zeros. A record
-- that asserts nothing is created deliberately — "created once, ever" is a
-- statement about a moment if creation happens at join, and a rule every result
-- would have to re-check if it did not.
--
-- A trigger rather than a write added to each join path. There are six places
-- that insert a membership — creating a community, joining by code, joining an
-- open community, accepting an invite, and two more — and adding the same write
-- to each would be six chances to miss one, now and for every join path added
-- later. The trigger makes "a member has an overall record" true by
-- construction. `DP-3` conforms either way: "the player's record in this
-- community begins" is genuinely part of what joining means, and `SL-4` treats
-- it as one event.
--
-- `on conflict do nothing` is `CS-C7` and `CS-C19`: a player who left and
-- rejoined must find their record, never receive a second one. The write is
-- create-if-absent, never insert — so `created_at` still marks the first ever
-- join, which `community_members.created_at` cannot after a rejoin recreates
-- that row.
--
-- This creates no foreign key and no cascade. `CS-C8` holds: deleting a
-- membership still does nothing at all to these records.
create or replace function public.create_community_statistics_on_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into community_statistics (
    community_id, period_type, period_key, user_id
  )
  values (new.community_id, 'overall', 'overall', new.user_id)
  on conflict (community_id, period_type, period_key, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists community_members_create_statistics
  on public.community_members;
create trigger community_members_create_statistics
  after insert on public.community_members
  for each row
  execute function public.create_community_statistics_on_join();

-- 4) What a result is worth, per community and period ----------------------------
-- `DP-6` and build requirement 6: extend the shared helper, never write a second
-- one. `match_result_contribution` already decides what a result is worth to
-- each player who played it — who won, who lost, who drew, who scored, who was
-- MVP. That arithmetic is not restated here. This function takes those rows and
-- adds the two dimensions Level 2 needs.
--
-- Two contributions computed separately would be two chances to disagree, and
-- `SL-2` §2.5's "the two levels agree by construction" would become a hope.
-- Stated this way it is a fact: there is one piece of arithmetic and both levels
-- read it.
--
-- Each participant yields exactly three rows — `CS-C12`. The community comes
-- from the match and is never a parameter (`CS-C14`): isolation cannot be
-- something a caller passes in.
--
-- A match with no recorded result yields no rows, which is what both callers
-- below rely on instead of checking for themselves.
create or replace function public.match_community_contribution(p_match_id uuid)
returns table (
  community_id uuid,
  period_type text,
  period_key text,
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
    m.community_id,
    p.period_type,
    p.period_key,
    c.user_id,
    c.played, c.won, c.lost, c.drawn, c.scored, c.mvp
  from matches m
  cross join match_result_contribution(p_match_id) c
  cross join lateral (
    values
      ('overall', public.statistics_period_key(m.start_at, 'overall')),
      ('weekly',  public.statistics_period_key(m.start_at, 'weekly')),
      ('monthly', public.statistics_period_key(m.start_at, 'monthly'))
  ) as p(period_type, period_key)
  where m.id = p_match_id;
$$;

-- 5) Applying and reversing, as the two statements they are -----------------------
-- `CS-C10`, and §16.1 is why it is specified rather than remembered. Migration
-- `0023` had to fix exactly this at Level 1: reversing through
-- `insert ... on conflict do update` with negative values fails, because
-- PostgreSQL validates the proposed row's CHECK constraints *before* it looks
-- for the conflict — so `matches_played = -1` is rejected by the non-negative
-- check even though the row exists and the statement would have taken the
-- `do update` branch.
--
-- The mistake is *more* likely here than it was at Level 1, not less: three
-- records per participant instead of one, and the weekly and monthly records
-- genuinely do not exist yet on the first result of every new period. That
-- frequent create-if-absent need is exactly what makes a single sign-flagged
-- upsert look correct. So applying is an upsert and reversing is an update.
--
-- Reversing subtracts from rows that already exist. A participant with no record
-- for a period is left alone rather than created at zero and decremented: there
-- is nothing of theirs recorded to take away.
create or replace function public.apply_community_statistics(
  p_match_id uuid,
  p_sign int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_sign < 0 then
    update community_statistics cs set
      matches_played = cs.matches_played - c.played,
      wins           = cs.wins - c.won,
      losses         = cs.losses - c.lost,
      draws          = cs.draws - c.drawn,
      goals          = cs.goals - c.scored,
      mvp_count      = cs.mvp_count - c.mvp
    from match_community_contribution(p_match_id) c
    where cs.community_id = c.community_id
      and cs.period_type  = c.period_type
      and cs.period_key   = c.period_key
      and cs.user_id      = c.user_id;

    -- A periodic record that has just gone to zero is a record of a period the
    -- player no longer has any appearance in, and §2.3 is explicit that those do
    -- not exist: periodic records are created for periods actually played in,
    -- because one carrying only zeros asserts nothing.
    --
    -- Without this the incremental path and `rebuild_community_statistics`
    -- disagree — the rebuild's step (d) removes exactly these rows — and the
    -- disagreement is silent, because §8's evidence check compares a stored zero
    -- against an absent contribution of zero and finds them equal. It would
    -- surface instead as a period's board or player count including people who
    -- did not play in it.
    --
    -- Only periodic records. An `overall` record at zero is the one created at
    -- join, where the zero is the fact (§2.2), and `SL-4` preserves it.
    delete from community_statistics cs
    where cs.period_type <> 'overall'
      and cs.matches_played = 0 and cs.wins = 0 and cs.losses = 0
      and cs.draws = 0 and cs.goals = 0 and cs.mvp_count = 0
      and exists (
        select 1 from match_community_contribution(p_match_id) c
        where c.community_id = cs.community_id
          and c.period_type  = cs.period_type
          and c.period_key   = cs.period_key
          and c.user_id      = cs.user_id
      );
    return;
  end if;

  insert into community_statistics as cs (
    community_id, period_type, period_key, user_id,
    matches_played, wins, losses, draws, goals, mvp_count
  )
  select
    c.community_id, c.period_type, c.period_key, c.user_id,
    c.played, c.won, c.lost, c.drawn, c.scored, c.mvp
  from match_community_contribution(p_match_id) c
  on conflict (community_id, period_type, period_key, user_id) do update set
    matches_played = cs.matches_played + excluded.matches_played,
    wins           = cs.wins + excluded.wins,
    losses         = cs.losses + excluded.losses,
    draws          = cs.draws + excluded.draws,
    goals          = cs.goals + excluded.goals,
    mvp_count      = cs.mvp_count + excluded.mvp_count;
end;
$$;

-- 6) Both levels move in one call ------------------------------------------------
-- `DP-2`, and it is the reason this is a replacement rather than a second call
-- added beside the first in three places.
--
-- Level 1 and Level 2 must move together or not at all. Adding
-- `apply_community_statistics` next to each of the three existing
-- `apply_match_statistics` calls — the reversal and the application inside
-- `record_match_result`, and the one in the before-delete trigger — would leave
-- three places where a future edit could move one level and not the other, and
-- nothing short of §9's reconciliation could detect it afterwards.
--
-- Making the Level 1 entry point apply both levels makes "they move together" a
-- property of the code rather than a discipline every caller has to keep. The
-- three existing call sites are unchanged and are not touched by this migration:
-- `record_match_result` and `reverse_match_effects_before_delete` keep the
-- bodies `0022` gave them.
--
-- Both levels therefore land inside the recording operation's transaction, under
-- the match row lock `record_match_result` already takes — which is `CS-C16`.
-- The Level 1 half of this function is `0023`'s, unchanged, restructured only so
-- that the early `return` no longer skips the Level 2 call.
create or replace function public.apply_match_statistics(
  p_match_id uuid,
  p_sign int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_sign < 0 then
    update player_statistics ps set
      matches_played = ps.matches_played - c.played,
      wins           = ps.wins - c.won,
      losses         = ps.losses - c.lost,
      draws          = ps.draws - c.drawn,
      goals          = ps.goals - c.scored,
      mvp_count      = ps.mvp_count - c.mvp
    from match_result_contribution(p_match_id) c
    where ps.user_id = c.user_id;
  else
    insert into player_statistics as ps (
      user_id, matches_played, wins, losses, draws, goals, mvp_count
    )
    select c.user_id, c.played, c.won, c.lost, c.drawn, c.scored, c.mvp
    from match_result_contribution(p_match_id) c
    on conflict (user_id) do update set
      matches_played = ps.matches_played + excluded.matches_played,
      wins           = ps.wins + excluded.wins,
      losses         = ps.losses + excluded.losses,
      draws          = ps.draws + excluded.draws,
      goals          = ps.goals + excluded.goals,
      mvp_count      = ps.mvp_count + excluded.mvp_count;
  end if;

  perform apply_community_statistics(p_match_id, p_sign);
end;
$$;

-- 7) Rebuild -----------------------------------------------------------------------
-- Build requirement 4, and §16.3's check 3 in executable form. It recomputes
-- every counter in scope from the evidence, which makes it three things at once:
-- the honest backfill for §11 below, the repair for any drift the reconciliation
-- finds, and the only safe response if `A1` ever changes.
--
-- It sets counters rather than deleting and re-inserting rows, because
-- `created_at` on an `overall` record is the only place the player's first ever
-- join is recorded (§6.2) and a delete would destroy it.
--
-- Returns the number of records the evidence produced.
create or replace function public.rebuild_community_statistics(
  p_community_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int;
begin
  -- (a) Zero the scope, so a record whose evidence has gone away is corrected
  --     rather than left holding its last value.
  update community_statistics cs set
    matches_played = 0, wins = 0, losses = 0,
    draws = 0, goals = 0, mvp_count = 0
  where (p_community_id is null or cs.community_id = p_community_id)
    and (cs.matches_played, cs.wins, cs.losses, cs.draws, cs.goals, cs.mvp_count)
        is distinct from (0, 0, 0, 0, 0, 0);

  -- (b) Set the counters from the evidence. `do update` assigns rather than
  --     accumulates — this is a rebuild, not an application.
  insert into community_statistics as cs (
    community_id, period_type, period_key, user_id,
    matches_played, wins, losses, draws, goals, mvp_count
  )
  select e.community_id, e.period_type, e.period_key, e.user_id,
         e.played, e.won, e.lost, e.drawn, e.scored, e.mvp
  from (
    select c.community_id, c.period_type, c.period_key, c.user_id,
           sum(c.played)::int  as played,
           sum(c.won)::int     as won,
           sum(c.lost)::int    as lost,
           sum(c.drawn)::int   as drawn,
           sum(c.scored)::int  as scored,
           sum(c.mvp)::int     as mvp
    from matches m
    cross join lateral match_community_contribution(m.id) c
    where p_community_id is null or m.community_id = p_community_id
    group by c.community_id, c.period_type, c.period_key, c.user_id
  ) e
  on conflict (community_id, period_type, period_key, user_id) do update set
    matches_played = excluded.matches_played,
    wins           = excluded.wins,
    losses         = excluded.losses,
    draws          = excluded.draws,
    goals          = excluded.goals,
    mvp_count      = excluded.mvp_count;

  get diagnostics v_rows = row_count;

  -- (c) Every current membership has its `overall` record (§2.2).
  insert into community_statistics (
    community_id, period_type, period_key, user_id
  )
  select cm.community_id, 'overall', 'overall', cm.user_id
  from community_members cm
  where p_community_id is null or cm.community_id = p_community_id
  on conflict (community_id, period_type, period_key, user_id) do nothing;

  -- (d) A periodic record with nothing in it asserts nothing (§2.3): periodic
  --     records exist for periods the player actually played in. `overall`
  --     records are kept at zero, because there the zero is the fact.
  delete from community_statistics cs
  where cs.period_type <> 'overall'
    and (p_community_id is null or cs.community_id = p_community_id)
    and cs.matches_played = 0 and cs.wins = 0 and cs.losses = 0
    and cs.draws = 0 and cs.goals = 0 and cs.mvp_count = 0;

  return v_rows;
end;
$$;

-- 8) Reconciliation ----------------------------------------------------------------
-- `CS-C17`, `DP-11`, build requirement 3 — built with the table, not after it.
--
-- Four tables determine every value here and none of them is referenced, so no
-- cascade can keep the counters honest and no constraint can express consistency
-- with the source (§12.2). This function is the only mechanism that could ever
-- detect that a figure is wrong, and it is what would make `CS-R3`'s three
-- inherited evidence-destruction cases visible.
--
-- Returns one row per discrepancy. An empty result is the pass condition.
--
--   evidence — stored counters vs recomputed from the evidence. Exact, and the
--              only check that survives a Level 1 defect.
--   periodic — a periodic figure exceeding its own `overall` record. Catches a
--              misplaced period or a missed reversal, and would catch an `A1`
--              change re-bucketing history (§16.5).
--   career   — a player's Level 1 career vs the sum of their `overall` records
--              across communities. The strongest cross-level check, and it
--              exists only because both levels carry the same six measures.
create or replace function public.reconcile_community_statistics()
returns table (
  check_name text,
  community_id uuid,
  user_id uuid,
  period_type text,
  period_key text,
  measure text,
  expected bigint,
  actual bigint
)
language sql
security definer
stable
set search_path = public
as $$
  with evidence as (
    select c.community_id, c.period_type, c.period_key, c.user_id,
           sum(c.played)::bigint  as played,
           sum(c.won)::bigint     as won,
           sum(c.lost)::bigint    as lost,
           sum(c.drawn)::bigint   as drawn,
           sum(c.scored)::bigint  as scored,
           sum(c.mvp)::bigint     as mvp
    from matches m
    cross join lateral match_community_contribution(m.id) c
    group by c.community_id, c.period_type, c.period_key, c.user_id
  ),
  cmp as (
    select
      coalesce(s.community_id, e.community_id) as community_id,
      coalesce(s.period_type,  e.period_type)  as period_type,
      coalesce(s.period_key,   e.period_key)   as period_key,
      coalesce(s.user_id,      e.user_id)      as user_id,
      coalesce(e.played, 0) as e_played, coalesce(s.matches_played, 0)::bigint as s_played,
      coalesce(e.won,    0) as e_won,    coalesce(s.wins,      0)::bigint as s_won,
      coalesce(e.lost,   0) as e_lost,   coalesce(s.losses,    0)::bigint as s_lost,
      coalesce(e.drawn,  0) as e_drawn,  coalesce(s.draws,     0)::bigint as s_drawn,
      coalesce(e.scored, 0) as e_scored, coalesce(s.goals,     0)::bigint as s_scored,
      coalesce(e.mvp,    0) as e_mvp,    coalesce(s.mvp_count, 0)::bigint as s_mvp
    from community_statistics s
    full join evidence e
      on  e.community_id = s.community_id
      and e.period_type  = s.period_type
      and e.period_key   = s.period_key
      and e.user_id      = s.user_id
  ),
  -- Check 1: stored against the evidence, measure by measure.
  check_evidence as (
    select 'evidence'::text as check_name, cmp.community_id, cmp.user_id,
           cmp.period_type, cmp.period_key, v.measure, v.expected, v.actual
    from cmp
    cross join lateral (values
      ('matches_played', cmp.e_played, cmp.s_played),
      ('wins',           cmp.e_won,    cmp.s_won),
      ('losses',         cmp.e_lost,   cmp.s_lost),
      ('draws',          cmp.e_drawn,  cmp.s_drawn),
      ('goals',          cmp.e_scored, cmp.s_scored),
      ('mvp_count',      cmp.e_mvp,    cmp.s_mvp)
    ) as v(measure, expected, actual)
    where v.expected <> v.actual
  ),
  -- Check 2: a periodic figure may never exceed its own `overall` record.
  check_periodic as (
    select 'periodic'::text, p.community_id, p.user_id,
           p.period_type, p.period_key, v.measure, v.expected, v.actual
    from community_statistics p
    join community_statistics o
      on  o.community_id = p.community_id
      and o.user_id      = p.user_id
      and o.period_type  = 'overall'
    cross join lateral (values
      ('matches_played', o.matches_played::bigint, p.matches_played::bigint),
      ('wins',           o.wins::bigint,           p.wins::bigint),
      ('losses',         o.losses::bigint,         p.losses::bigint),
      ('draws',          o.draws::bigint,          p.draws::bigint),
      ('goals',          o.goals::bigint,          p.goals::bigint),
      ('mvp_count',      o.mvp_count::bigint,      p.mvp_count::bigint)
    ) as v(measure, expected, actual)
    where p.period_type <> 'overall'
      and v.actual > v.expected
  ),
  -- Check 3: Level 1's career against the sum of Level 2's `overall` records.
  check_career as (
    select 'career'::text, null::uuid, u.user_id,
           null::text, null::text, v.measure, v.expected, v.actual
    from (
      select coalesce(ps.user_id, l2.user_id) as user_id,
             coalesce(ps.matches_played, 0)::bigint as c_played,
             coalesce(ps.wins, 0)::bigint      as c_won,
             coalesce(ps.losses, 0)::bigint    as c_lost,
             coalesce(ps.draws, 0)::bigint     as c_drawn,
             coalesce(ps.goals, 0)::bigint     as c_scored,
             coalesce(ps.mvp_count, 0)::bigint as c_mvp,
             coalesce(l2.played, 0)  as l_played,
             coalesce(l2.won, 0)     as l_won,
             coalesce(l2.lost, 0)    as l_lost,
             coalesce(l2.drawn, 0)   as l_drawn,
             coalesce(l2.scored, 0)  as l_scored,
             coalesce(l2.mvp, 0)     as l_mvp
      from player_statistics ps
      full join (
        select cs.user_id,
               sum(cs.matches_played)::bigint as played,
               sum(cs.wins)::bigint           as won,
               sum(cs.losses)::bigint         as lost,
               sum(cs.draws)::bigint          as drawn,
               sum(cs.goals)::bigint          as scored,
               sum(cs.mvp_count)::bigint      as mvp
        from community_statistics cs
        where cs.period_type = 'overall'
        group by cs.user_id
      ) l2 on l2.user_id = ps.user_id
    ) u
    cross join lateral (values
      ('matches_played', u.l_played, u.c_played),
      ('wins',           u.l_won,    u.c_won),
      ('losses',         u.l_lost,   u.c_lost),
      ('draws',          u.l_drawn,  u.c_drawn),
      ('goals',          u.l_scored, u.c_scored),
      ('mvp_count',      u.l_mvp,    u.c_mvp)
    ) as v(measure, expected, actual)
    where v.expected <> v.actual
  )
  select * from check_evidence
  union all select * from check_periodic
  union all select * from check_career;
$$;

comment on function public.reconcile_community_statistics() is
  'CS-C17 / DP-11: three checks over community_statistics — stored vs evidence, '
  'periodic vs overall, and Level 2 overall vs Level 1 career. One row per '
  'discrepancy; an empty result is the pass condition.';

-- 9) Privileges --------------------------------------------------------------------
-- None of these is reachable through the API. `record_match_result` remains the
-- only entry point, and the trigger function follows `0024`'s rule that no role
-- may reach a trigger function through PostgREST.
--
-- Rebuild and reconcile are system operations (§10.3). They are deliberately not
-- granted to `authenticated`: reconciliation is not a capability a person in a
-- community has, and rebuild is not a write anybody may invoke.
revoke execute on function public.statistics_period_zone()
  from anon, authenticated, public;
revoke execute on function public.statistics_period_key(timestamptz, text)
  from anon, authenticated, public;
revoke execute on function public.match_community_contribution(uuid)
  from anon, authenticated, public;
revoke execute on function public.apply_community_statistics(uuid, int)
  from anon, authenticated, public;
revoke execute on function public.create_community_statistics_on_join()
  from anon, authenticated, public;
revoke execute on function public.rebuild_community_statistics(uuid)
  from anon, authenticated, public;
revoke execute on function public.reconcile_community_statistics()
  from anon, authenticated, public;

-- 10) Authorization ------------------------------------------------------------------
-- §10.2 and `CS-R4`. Membership of the community is what grants sight of its
-- statistics, and nothing else does.
--
-- Scoped from the start, deliberately. `PS-R1` records Level 1's unscoped read
-- as a Medium-High finding — `player_statistics` is readable by any signed-in
-- account — and an unscoped read here would let any account enumerate every
-- player who has played anywhere, with figures attached, reintroducing at
-- Level 2 exactly the hole being closed at Level 1. It would also make this a
-- second broadly-readable table, which `SUPABASE_OPERATIONAL_GUIDELINES.md` §4
-- permits only once and with recorded approval.
--
-- Departed members' records stay readable by current members: they are part of
-- the community's history, and hiding them would make the dashboard's community
-- totals unexplainable. The converse is `CS-D3` and is accepted — a player who
-- has left cannot read their own preserved record, because the read is scoped by
-- current membership.
--
-- Select and nothing else. `CS-C9`: a counter a client wrote has no contribution
-- behind it and could never be reversed. The absence of an insert, update or
-- delete policy is what says so, and the revoke below says it a second time
-- because Supabase's default privileges grant those to `authenticated` on new
-- tables in `public`. The `security definer` functions above are unaffected —
-- they run as the owner.
alter table public.community_statistics enable row level security;

revoke all on public.community_statistics from anon, authenticated, public;
grant select on public.community_statistics to authenticated;

drop policy if exists "community_statistics_select_members"
  on public.community_statistics;
create policy "community_statistics_select_members"
  on public.community_statistics
  for select
  to authenticated
  using (public.is_community_member(community_id, auth.uid()));

-- 11) Backfill -------------------------------------------------------------------------
-- Build requirement 5, done the way §16.3 requires: through the rebuild, not
-- through an insert of zeros.
--
-- Every current member of every community predates this table. Giving them all
-- an empty `overall` record would be a lie wherever a result has already been
-- recorded — the counters would say the player has played nothing while the
-- evidence says otherwise. `rebuild_community_statistics()` creates the same
-- records and then fills them from the evidence, so the table is correct from
-- its first moment rather than correct from the next result onwards.
select public.rebuild_community_statistics();
