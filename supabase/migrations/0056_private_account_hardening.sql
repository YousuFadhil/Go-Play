-- ============ migrations/0056_private_account_hardening.sql ============
-- Cycle 1, phase two of two: the boundary itself.
--
-- `0055_private_account_compatibility.sql` added the two paths the new client
-- reads through -- `community_join_code` and `my_profile` -- and deliberately
-- took nothing away, so that it could be applied to the shared project while
-- the previous release was still the one being served. This is the half that
-- takes things away, and it is therefore the half with a precondition.
--
-- ## DO NOT APPLY THIS UNTIL THE NEW CLIENT IS THE ONE BEING SERVED
--
-- Staging and production share one Supabase project, so "the deployed client"
-- is not a hypothetical. Two statements below break the release built from
-- `main`:
--
--   * `revoke select on public.communities` -- `main`'s
--     `SupabaseCommunityAdapter._columns` names `join_code` in every community
--     read, so its Communities list and Community Details both start failing.
--   * `revoke select on public.users` plus the rebuilt `v_user_profile` --
--     `main`'s profile adapter projects `phone` and `date_of_birth` off that
--     view for the account screen.
--
-- Neither is a bug in this migration. They are what closing the leak means, and
-- they are the reason the split exists: apply this only once the Cycle 1 build
-- is deployed, and the same statements are invisible to every caller.
--
-- ## WHAT THIS CLOSES
--
-- Two leaks, one instrument. `communities_select_visible` (`0016`) and
-- `authenticated_select_active_users` (`0001`) both say `using (is_active)`, and
-- a policy decides *rows*. It cannot decide columns. So every account holder
-- could read every active community's `join_code` -- the credential
-- `join_community_by_code` accepts, which made `CODE_REQUIRED` decorative --
-- and every active player's `phone`.
--
-- The fix is where the granularity is: `revoke select on <table>`, then
-- `grant select (<the columns that are not credentials>)`. This is the pattern
-- migration `0022` already established on this schema when it took the blanket
-- UPDATE off `users` and granted the writable columns back by name. What
-- legitimately still needs a withheld column reads it through one of `0055`'s
-- two functions rather than through a wider grant.
--
-- Idempotent: every statement is `revoke`, `grant`, `create or replace`, or a
-- guarded `drop ... if exists` followed by a create.



-- ============================================================================
-- 1) The join code stops being a column anybody may select
-- ============================================================================
-- The revoke is the whole of the fix. After it, `select join_code from
-- communities` is refused by the server for both client roles, whatever the
-- caller's membership, whatever the row, and whether the request comes from
-- this application or from a hand-written call carrying the publishable key.
-- Hiding the value in Flutter would have left the API answering it.
--
-- `anon` is revoked as well. It has no policy on `communities` and therefore
-- reads no rows today, but a grant that is only unreachable is not the same
-- thing as a grant that is absent, and the public discovery path does not need
-- it: `v_public_communities` (`0033`) is deliberately NOT `security_invoker`,
-- so it executes with the view owner's privileges and is untouched by anything
-- in this section.
revoke select on public.communities from anon, authenticated;

-- Everything that is not the credential, by name. This is the whole column list
-- of `communities` minus `join_code`:
--
--   * `id`, `name`, `description`, `join_policy` -- what a community is.
--   * `owner_id` -- reporting only (PD-15). It is not a credential and it is
--     already published by nothing; narrowing it is a separate decision from
--     this one and is not made here.
--   * `is_active` -- the soft delete the policy itself reads.
--   * `created_at`, `updated_at` -- ordering and audit. The community list is
--     ordered by `created_at`, and ordering by a column requires selecting it.
--
-- UPDATE privileges are untouched. `set_join_policy` writes through
-- `communities_update_owner`, which is a row rule and stays exactly as it was.
-- Note that an owner can no longer read the code back through
-- `update ... returning join_code` either: `returning` needs SELECT on the
-- column, and there is no longer one. The owner's path is `community_join_code`, added by `0055`.
grant select (
  id,
  owner_id,
  name,
  description,
  join_policy,
  is_active,
  created_at,
  updated_at
) on public.communities to authenticated;



-- ============================================================================
-- 2) The phone number stops being a column anybody but its owner may read
-- ============================================================================
-- Same instrument as section 1, same reason: the policy on `users` decides
-- which rows, and every active row is every row. The column list below is the
-- whole of `public.users` minus `phone`.
--
-- `date_of_birth` stays granted, and that is deliberate rather than an
-- oversight. The Balanced Team Generation Engine reads it as a Core Player
-- Input (§4.1) through `match_registrations -> users`, which migration `0043`
-- recorded as untouched by the visibility work and untouched for the same
-- reason here: narrowing it means moving the engine's input read behind a
-- function, which is a change to team generation and not to this boundary. What
-- section 4 does do is stop the date leaving through the *football profile*,
-- which is what the approved rule asks of this cycle.
--
-- `profile_visibility` and `age_visible` stay granted so that no existing read
-- of `users` breaks; both are retired as controls by section 4.
revoke select on public.users from anon, authenticated;

grant select (
  id,
  full_name,
  primary_position,
  secondary_position,
  date_of_birth,
  overall_rating,
  avatar_path,
  is_active,
  created_at,
  updated_at,
  profile_visibility,
  age_visible
) on public.users to authenticated;

-- UPDATE is untouched. Migration `0022` narrowed it to named columns and `0043`
-- added two more; `phone` is among them and stays among them, because a player
-- writing their own number is exactly what `users_update_own_profile` allows
-- and what the account screen does. Writing a column is not reading it: an
-- update with no `returning` needs no SELECT privilege, which is why taking
-- SELECT away does not take the account screen's save away.



-- ============================================================================
-- 3) `v_user_profile`, without the account columns
-- ============================================================================
-- The view is `security_invoker = on`, so it now inherits section 2's column
-- privileges and a `phone` in its body would make every read of it fail. It is
-- rebuilt without one.
--
-- Three more columns go with it, and none of them is needed by anything that
-- reads this view:
--
--   * `date_of_birth` -- the view's only reader for it was the owner's own
--     profile, which `my_profile()` (migration `0055`) now answers. Leaving it here
--     would have published every player's birth date to every account holder
--     through a view whose whole purpose is now the career record.
--   * `profile_visibility`, `age_visible` -- the owner's own preferences. They
--     belong to the owner's own read, which is `my_profile()`.
--
-- What remains is what the view is for: who a player is, their Global Rating,
-- and their career counters, LEFT-joined so a player who has finished no match
-- reads as an absence of counters rather than as a missing player. Its three
-- readers -- the greeting, the career statistics read and the avatar clear --
-- all ask for columns that are still here.
--
-- Dropped and recreated rather than replaced: `create or replace view` may
-- append columns and may not remove them.
drop view if exists public.v_user_profile;

create view public.v_user_profile
with (security_invoker = on) as
select
  u.id                as user_id,
  u.full_name,
  u.primary_position,
  u.secondary_position,
  u.overall_rating,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.avatar_path,
  ps.matches_played,
  ps.wins,
  ps.losses,
  ps.draws,
  ps.goals,
  ps.mvp_count,
  ps.updated_at       as statistics_updated_at
from public.users u
left join public.player_statistics ps on ps.user_id = u.id;

comment on view public.v_user_profile is
  'Read model: a player identity joined to the global career counters in '
  'player_statistics. Counters are null until the first recorded result. '
  'Carries no phone, no date of birth and no privacy preference -- those are '
  'the owner''s own and are answered by my_profile() (migration 0055).';

-- Privileges, restated because the view was dropped and recreated.
--
-- This is migration `0034`'s hazard, and it applies to every object created in
-- schema `public`: Supabase ships a default-privileges rule that grants ALL to
-- `anon` and `authenticated` on creation, before a migration's own grant is
-- reached. The named revoke below is what takes the other six back. It is not
-- redundant with `revoke all` above it -- it is the audit trail that says which
-- six, in the same words `0034` used.
revoke all on public.v_user_profile from anon, public, authenticated;

revoke insert, update, delete, truncate, references, trigger
  on public.v_user_profile
  from anon, authenticated;

grant select on public.v_user_profile to authenticated;



-- ============================================================================
-- 4) `player_profile()`: the football profile
-- ============================================================================
-- Two approved changes, and the column list is the whole of the first.
--
--   * **The date of birth leaves.** It is account data, and the approved rule
--     puts account data on the owner's side of the boundary. The age it was
--     derived from is not shown on another player's profile any more, which is
--     the point rather than a side effect: `age_visible` was a control over
--     something that no longer happens.
--
--   * **The membership gate leaves.** `COMMUNITY_MEMBERS` said a profile could
--     be opened only by somebody who shares an active community, and the
--     approved discovery direction says a football profile is football data.
--     The two cannot both hold. The setting is retired rather than honoured:
--     every active player's football profile is now readable by every signed-in
--     player.
--
-- What does NOT change: a session is still required (`anon` has no execute and
-- the body refuses without `auth.uid()`), the target must still be active, and
-- the returned columns are still a fixed list rather than a row of `users` --
-- so there is no phone, no email, no authentication identifier and now no date
-- of birth to be had here, whatever the caller asks for.
--
-- `is_self` stays. It is a fact about the caller rather than about the player
-- being looked at, it discloses nothing, and it is what tells the screen
-- whether it is drawing somebody's own record.
--
-- Dropped and recreated rather than replaced: the return type changes, and
-- `create or replace function` may not change one.
drop function if exists public.player_profile(uuid);

create function public.player_profile(p_user_id uuid)
returns table (
  user_id uuid,
  full_name text,
  primary_position text,
  secondary_position text,
  avatar_path text,
  overall_rating numeric,
  matches_played int,
  wins int,
  losses int,
  draws int,
  goals int,
  mvp_count int,
  is_self boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_user users%rowtype;
  v_stats player_statistics%rowtype;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_user from users u where u.id = p_user_id and u.is_active;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- A player with no recorded result has no statistics row. That is the
  -- ordinary state of a new account, so the counters read as zero rather than
  -- as an absence the caller has to interpret.
  select * into v_stats
  from player_statistics ps where ps.user_id = v_user.id;

  return query select
    v_user.id,
    v_user.full_name,
    v_user.primary_position,
    v_user.secondary_position,
    v_user.avatar_path,
    v_user.overall_rating,
    coalesce(v_stats.matches_played, 0),
    coalesce(v_stats.wins, 0),
    coalesce(v_stats.losses, 0),
    coalesce(v_stats.draws, 0),
    coalesce(v_stats.goals, 0),
    coalesce(v_stats.mvp_count, 0),
    v_user.id = auth.uid();
end;
$$;

comment on function public.player_profile(uuid) is
  'One player''s football profile: identity, playing positions, picture, '
  'Global Rating and career counters. Readable by any signed-in player, '
  'whatever communities either of them is in. Never the phone, the email, an '
  'auth identifier or the date of birth -- see migration 0056.';

revoke execute on function public.player_profile(uuid) from anon, public;
grant execute on function public.player_profile(uuid) to authenticated;

-- The two columns behind the retired controls are left in place. Dropping a
-- column is destructive and irreversible, and neither is read to decide
-- anything now: `profile_visibility` is no longer consulted by the function
-- above, and `age_visible` guarded a date that no longer leaves through it. The
-- comments are corrected so the schema does not go on claiming an effect the
-- code no longer has.
comment on column public.users.profile_visibility is
  'RETIRED by migration 0056. A football profile is readable by any signed-in '
  'player, so this column is no longer consulted by player_profile(). Kept '
  'because dropping a column is irreversible; written by nothing.';
comment on column public.users.age_visible is
  'RETIRED by migration 0056. The date of birth no longer leaves through '
  'player_profile(), so there is no disclosure for this to withhold. Kept '
  'because dropping a column is irreversible; written by nothing.';



-- ============================================================================
-- 5) `shares_active_community()` stops being callable by a client
-- ============================================================================
-- Migration `0043` created it as the predicate behind `COMMUNITY_MEMBERS`, and
-- section 4 just removed its only caller. What is left is a `security definer`
-- function, granted to every account holder, that answers "are these two people
-- in a community together" for any pair of user ids -- a relationship oracle
-- with nothing asking it anything.
--
-- The function is kept (something may want the predicate server-side again) and
-- the grant is not. Nothing in the application calls it.
revoke execute on function public.shares_active_community(uuid, uuid)
  from anon, authenticated, public;



-- ============================================================================
-- 6) The public discovery views stay exactly as they were
-- ============================================================================
-- Neither is recreated here, so neither's privileges have moved. The revokes
-- below are re-asserted rather than assumed: `0034` exists because these two
-- views once carried six privileges nobody intended, and a boundary migration
-- that leaves that unchecked is taking the previous migration's word for the
-- state of the database. REVOKE is idempotent, so this costs nothing and says
-- plainly what must be true when this migration finishes.
--
-- Both remain readable, both remain read-only, and both remain the only objects
-- in this schema a signed-out visitor can read. Nothing above narrows them:
-- neither is `security_invoker`, so both execute with the view owner's
-- privileges and sections 1 and 3 do not reach them.
revoke insert, update, delete, truncate, references, trigger
  on public.v_public_communities
  from anon, authenticated;

revoke insert, update, delete, truncate, references, trigger
  on public.v_public_upcoming_matches
  from anon, authenticated;

grant select on public.v_public_communities      to anon, authenticated;
grant select on public.v_public_upcoming_matches to anon, authenticated;
