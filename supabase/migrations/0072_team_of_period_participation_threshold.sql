-- ============ migrations/0072_team_of_period_participation_threshold.sql ============
-- One participation bar for the Team of Period, whatever the period is.
--
-- ## What changes
--
-- `0070` set two different bars: a week asked for one played match and a month
-- asked for half of its own, rounded up. Staging showed what that means in
-- practice -- a community playing five times in a week put its whole roster in
-- contention on one appearance, while the same five matches spread over a
-- month required three. The same football, two answers, and the weaker one
-- produced an award that read as a list of everyone who turned up once.
--
-- The Product Owner has replaced both with a single rule:
--
--     n = qualifying matches in the resolved period
--
--     n = 0  ->  0
--     n > 0  ->  ceil(40% of n)
--
--         1 -> 1     2 -> 1     3 -> 2     4 -> 2     5 -> 2
--         6 -> 3     7 -> 3    10 -> 4    14 -> 6    30 -> 12
--
-- **Deliberately blind to the kind of period.** Five matches ask for two
-- whether they were played across a week or across a month; how long the
-- community took to play them is not evidence about who took part in them.
-- `p_period_type` therefore stays in the signature -- every caller passes it
-- and the contract is not worth churning for a parameter that has become
-- unread -- but nothing branches on it any more.
--
-- ## The arithmetic
--
-- `(2 * n + 4) / 5` in integer arithmetic, which is exactly `ceil(2n/5)`:
-- adding four before a truncating division by five rounds any remainder up.
--
-- `ceil(0.4 * n)` is deliberately not written that way. `0.4` is not
-- representable in binary floating point, so `ceil(0.4 * 5)` is one `ceil` away
-- from returning 3 on a value that is 2.0000000000000004 -- and a threshold
-- that is silently one too high excludes a player who qualified, which nothing
-- downstream would ever report. Integers cannot drift.
--
-- ## What does not change
--
-- Eligibility, and eligibility only. The selection ranking is untouched --
-- period form score, then participation rate, then MVP count, then the capped
-- goal-form total, then user id -- as are PFS v1, every `0070` evidence query,
-- both read-path signatures, and every table, policy and trigger. The function
-- keeps its signature, its immutability, its pinned search path and its
-- revocations, so nothing above it needs to know this happened.
--
-- Append-only: `0070` is not edited. Idempotent: `create or replace`.

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
    -- An empty period has no award population for a bar to apply to. Tested
    -- first, which also leaves the arithmetic below reachable only with a
    -- positive count.
    when coalesce(p_qualifying_matches, 0) <= 0 then 0
    -- ceil(2n/5) == ceil(40% of n), in integers, for every n this can hold.
    -- `p_period_type` is not consulted: the bar is the same for a week and a
    -- month, which is the whole of this migration.
    else (2 * p_qualifying_matches + 4) / 5
  end;
$$;

comment on function public.period_xi_required_matches(text, int) is
  'How many qualifying matches a Team of Period candidate must have played: 0 '
  'when the period held no qualifying match at all, and otherwise ceil(40%% of '
  'n) -- written as integer (2n + 4) / 5 so that neither a truncating division '
  'nor a binary float can move the bar. ONE rule for weekly and monthly alike: '
  'five matches ask for two however long the community took to play them, so '
  'p_period_type is accepted and deliberately unread. Eligibility only -- the '
  'selection ranking is unchanged. Stated once because both read paths publish '
  'it -- see migration 0072.';

-- The function was replaced rather than dropped, so its privileges survive.
-- They are restated anyway, because a reader checking who may call this should
-- find the answer here rather than three migrations back.
revoke execute on function public.period_xi_required_matches(text, int)
  from anon, authenticated, public;
