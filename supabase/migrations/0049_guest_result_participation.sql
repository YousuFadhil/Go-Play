-- A Professional Guest in the result: the writer.
--
-- Migration `0044` gave `match_goals` a guest identity and `match_results` a
-- guest MVP column, and left it there -- structurally ready, with nothing able
-- to write either. That was defensible while nothing depended on it. It is not
-- any more: the approved correction requires that a guest's goal and a guest's
-- MVP award **survive being taken off the roster**, and a guarantee about data
-- that cannot be created is a guarantee about nothing.
--
-- So `record_match_result` learns the two things it was missing, and nothing
-- else changes. Every existing rule is restated verbatim -- authorization, the
-- score, the lineup requirement, the goals-match-the-score arithmetic, the
-- participation checks -- because `create or replace function` replaces the
-- whole body.
--
-- ## What is new
--
-- **`p_goals` entries may name a guest.** An entry carries `user_id` or
-- `professional_guest_id`, exactly one, which is the same shape the XOR check
-- on `match_goals` states. A hat-trick is still one entry saying three.
--
-- **`p_mvp_professional_guest_id`** names a guest as best on the pitch. At most
-- one of the two MVP arguments may be given; both is `INVALID_MVP`, and neither
-- is still a complete result (migration `0033`).
--
-- **The MVP columns are written as a pair.** Whichever is named is set and the
-- other is cleared, so the mutual-exclusion constraint holds through a
-- correction that changes an MVP from a guest to a user or back. This is the
-- gap migration `0044`'s closing note left open, closed here by the writer that
-- first needed it.
--
-- ## What deliberately does not change
--
-- A guest still earns nothing. `match_result_contribution`,
-- `player_statistics_evidence` and `apply_match_rating_effects` (migration
-- `0046`) all project only rows with a `user_id`, so a guest's goal counts
-- towards the score and towards no career total, and the MVP award moves no
-- rating. The goals arithmetic is the whole reason a guest's goal has to be
-- recordable at all: without it, a match a guest scored in could never be
-- entered, because the tallies would not add up to the score.
--
-- The signature gains one parameter with a default, so the five-argument call
-- the application already makes still resolves. The old five-argument function
-- is dropped first: leaving both would make that call ambiguous rather than
-- convenient.
drop function if exists public.record_match_result(uuid, int, int, uuid, jsonb);

create or replace function public.record_match_result(
  p_match_id uuid,
  p_team_a_score int,
  p_team_b_score int,
  p_mvp_user_id uuid,
  p_goals jsonb default '[]'::jsonb,
  p_mvp_professional_guest_id uuid default null
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

  -- NEW: one best player, or none. Two would be two answers to one question.
  if p_mvp_user_id is not null and p_mvp_professional_guest_id is not null then
    raise exception 'INVALID_MVP';
  end if;

  -- Who played is the stored lineup. Without one there is no side for a player
  -- to have been on, so there is no winner to reward and no loser to charge --
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

  -- NEW: exactly one identity per entry, which is `match_goals`' own XOR asked
  -- before the insert so the caller gets a named refusal. Equality on the two
  -- booleans is true when they agree -- both set, or neither.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where (nullif(e->>'user_id', '') is not null)
        = (nullif(e->>'professional_guest_id', '') is not null)
  ) then
    raise exception 'INVALID_GOALS';
  end if;

  -- Two entries for one participant is not a bigger number, it is the same fact
  -- recorded twice, and which of them counted would be arbitrary. Compared over
  -- the identity pair so a user and a guest are never confused for each other.
  if (
    select count(*) from (
      select distinct
        nullif(e->>'user_id', ''),
        nullif(e->>'professional_guest_id', '')
      from jsonb_array_elements(p_goals) as e
    ) d
  ) <> jsonb_array_length(p_goals) then
    raise exception 'INVALID_GOALS';
  end if;

  select coalesce(sum((e->>'goals')::int), 0) into v_total_goals
  from jsonb_array_elements(p_goals) as e;

  if v_total_goals <> p_team_a_score + p_team_b_score then
    raise exception 'GOALS_DO_NOT_MATCH_SCORE';
  end if;

  if p_mvp_user_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id and user_id = p_mvp_user_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- NEW: the same rule for a guest. A best player has to have played.
  if p_mvp_professional_guest_id is not null and not exists (
    select 1 from match_team_assignments
    where match_id = p_match_id
      and professional_guest_id = p_mvp_professional_guest_id
  ) then
    raise exception 'MVP_NOT_PARTICIPANT';
  end if;

  -- A goal is credited to somebody who played it. Otherwise a rating could be
  -- raised for a player who was never in the match.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'user_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.user_id = (e->>'user_id')::uuid
      )
  ) then
    raise exception 'SCORER_NOT_PARTICIPANT';
  end if;

  -- NEW: and the same for a guest scorer.
  if exists (
    select 1 from jsonb_array_elements(p_goals) as e
    where nullif(e->>'professional_guest_id', '') is not null
      and not exists (
        select 1 from match_team_assignments a
        where a.match_id = p_match_id
          and a.professional_guest_id
              = (e->>'professional_guest_id')::uuid
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
    match_id, team_a_score, team_b_score, mvp_user_id,
    mvp_professional_guest_id, recorded_by
  )
  values (
    p_match_id, p_team_a_score, p_team_b_score, p_mvp_user_id,
    p_mvp_professional_guest_id, auth.uid()
  )
  -- NEW: both MVP columns are assigned, never one. Setting a user MVP over a
  -- stored guest MVP without clearing the guest would leave both non-null and
  -- violate `match_results_mvp_identity_check`.
  on conflict (match_id) do update set
    team_a_score = excluded.team_a_score,
    team_b_score = excluded.team_b_score,
    mvp_user_id = excluded.mvp_user_id,
    mvp_professional_guest_id = excluded.mvp_professional_guest_id,
    recorded_by = excluded.recorded_by;

  insert into match_goals
    (match_id, user_id, professional_guest_id, goals)
  select
    p_match_id,
    nullif(e->>'user_id', '')::uuid,
    nullif(e->>'professional_guest_id', '')::uuid,
    (e->>'goals')::int
  from jsonb_array_elements(p_goals) as e;

  perform apply_match_rating_effects(p_match_id);
  perform apply_match_statistics(p_match_id, 1);
end;
$$;

revoke execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb, uuid) from anon, public;
grant execute on function public.record_match_result(uuid, int, int, uuid,
  jsonb, uuid) to authenticated;
