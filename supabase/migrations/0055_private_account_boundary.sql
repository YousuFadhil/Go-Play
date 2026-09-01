-- ============ migrations/0055_private_account_boundary.sql ============
-- Cycle 1 of Public Discovery: the security boundary, and nothing else.
--
-- The approved product rule this migration serves:
--
--     Football activity is discoverable; private account data is private;
--     participation still requires membership.
--
-- Nothing here makes any new football entity discoverable. No completed match,
-- no result, no lineup, no goal, no MVP and no leaderboard becomes readable to
-- anybody who could not read it yesterday. Every statement below either takes a
-- privilege away or replaces a read path with a narrower one. The one thing
-- that widens is `player_profile`, and it widens along an axis the Product
-- Owner has approved: a football profile no longer asks whether the two players
-- share a community.
--
-- THE TWO LEAKS THIS CLOSES
--
--   1) `communities.join_code`. `communities_select_visible` (migration `0016`)
--      is `for select to authenticated using (is_active)`, and no column
--      privilege ever narrowed it. Any account holder could therefore read
--      every active community's join code -- `GET /rest/v1/communities?
--      select=id,join_code` -- which made `CODE_REQUIRED` decorative: the code
--      is the credential `join_community_by_code` accepts. The application made
--      it worse by asking for the column: `SupabaseCommunityAdapter._columns`
--      listed `join_code`, so the Communities screen shipped every code to
--      every client that opened it.
--
--   2) `users.phone`. `authenticated_select_active_users` (migration `0001`) is
--      `using (is_active)`, and `v_user_profile` (`0025`, `0031`, `0043`)
--      republished the column through a `security_invoker` view. Any account
--      holder could read every active player's phone number.
--
-- WHY COLUMN PRIVILEGES AND NOT A POLICY
--
-- RLS decides rows. It cannot decide columns. A policy that lets a caller have
-- the community row is a policy that lets them have every column of it,
-- `join_code` included, and the same is true of `users` and `phone`. So the
-- fix is where the granularity is: `revoke select on <table>`, then
-- `grant select (<the columns that are not credentials>)`. This is the pattern
-- migration `0022` already established on this schema when it took the blanket
-- UPDATE off `users` and granted the writable columns back by name.
--
-- What legitimately still needs a withheld column gets a narrowly scoped
-- `security definer` function -- one question, one answer, one authorization
-- check -- rather than a wider grant:
--
--   * `community_join_code(uuid)` -> the code, to an owner or admin only.
--   * `my_profile()`              -> the caller's own account row, phone
--                                    included, self-only by construction.
--
-- Idempotent: every statement is `revoke`, `grant`, `create or replace`, or a
-- guarded `drop ... if exists` followed by a create. Re-running it is a no-op.


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
-- column, and there is no longer one. The owner's path is section 2's function.
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
-- 2) The one path to a join code
-- ============================================================================
-- An owner or an admin still has to be able to invite people, and inviting
-- people is showing them the code. That is a community-management action, so it
-- asks the community-management question: `has_community_role(..., 'admin')`,
-- the same predicate that gates every other organizer operation (PD-07, PD-16).
-- Being a member is not enough -- an ordinary Player has no administrative
-- reason to hold the credential that lets them hand the community to anybody.
--
-- `security definer`, because the caller no longer has the privilege to read
-- the column and this function is the reason that is survivable. The function
-- returns one text value and takes one id, so there is no projection a caller
-- could widen and no row they could reach past.
--
-- An inactive community answers `COMMUNITY_NOT_FOUND` rather than a code: a
-- soft-deleted community is not one anybody is being invited to.
create or replace function public.community_join_code(p_community_id uuid)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Asked before the row is read, so a refusal never depends on what was found.
  if not public.has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select c.join_code into v_code
  from communities c
  where c.id = p_community_id and c.is_active;

  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  return v_code;
end;
$$;

comment on function public.community_join_code(uuid) is
  'The community join code, to an owner or admin and to nobody else. The only '
  'read path that exists: migration 0055 revoked SELECT on the column itself.';

revoke execute on function public.community_join_code(uuid) from anon, public;
grant execute on function public.community_join_code(uuid) to authenticated;


-- ============================================================================
-- 3) The phone number stops being a column anybody but its owner may read
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
-- section 5 does do is stop the date leaving through the *football profile*,
-- which is what the approved rule asks of this cycle.
--
-- `profile_visibility` and `age_visible` stay granted so that no existing read
-- of `users` breaks; both are retired as controls by section 5.
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
-- 4) `v_user_profile`, without the account columns
-- ============================================================================
-- The view is `security_invoker = on`, so it now inherits section 3's column
-- privileges and a `phone` in its body would make every read of it fail. It is
-- rebuilt without one.
--
-- Three more columns go with it, and none of them is needed by anything that
-- reads this view:
--
--   * `date_of_birth` -- the view's only reader for it was the owner's own
--     profile, which section 5's `my_profile()` now answers. Leaving it here
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
-- 5) `my_profile()`: the caller's own account row
-- ============================================================================
-- Self-only by construction, not by policy: the function does not take a user
-- id, so there is no argument a caller could point at somebody else. It reads
-- `auth.uid()` and nothing else, which means "User A retrieving User B's phone"
-- is not a request this function can express.
--
-- `security definer` because `phone` is no longer selectable by the caller, and
-- because this is the one place the product has decided it should be.
--
-- The column list is the account screen's and the profile screen's, together:
-- identity, contact number, playing inputs, picture, rating and the two privacy
-- preferences. It is not a football profile and is never read for one --
-- section 6 is that path.
create or replace function public.my_profile()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  primary_position text,
  secondary_position text,
  date_of_birth date,
  avatar_path text,
  overall_rating numeric,
  profile_visibility text,
  age_visible boolean
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

  return query
  select
    u.id,
    u.full_name,
    u.phone,
    u.primary_position,
    u.secondary_position,
    u.date_of_birth,
    u.avatar_path,
    u.overall_rating,
    u.profile_visibility,
    u.age_visible
  from users u
  where u.id = auth.uid() and u.is_active;
end;
$$;

comment on function public.my_profile() is
  'The signed-in player''s own account row, phone included. Takes no user id, '
  'so it cannot be pointed at anybody else -- see migration 0055.';

revoke execute on function public.my_profile() from anon, public;
grant execute on function public.my_profile() to authenticated;


-- ============================================================================
-- 6) `player_profile()`: the football profile
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
  'auth identifier or the date of birth -- see migration 0055.';

revoke execute on function public.player_profile(uuid) from anon, public;
grant execute on function public.player_profile(uuid) to authenticated;

-- The two columns behind the retired controls are left in place. Dropping a
-- column is destructive and irreversible, and neither is read to decide
-- anything now: `profile_visibility` is no longer consulted by the function
-- above, and `age_visible` guarded a date that no longer leaves through it. The
-- comments are corrected so the schema does not go on claiming an effect the
-- code no longer has.
comment on column public.users.profile_visibility is
  'RETIRED by migration 0055. A football profile is readable by any signed-in '
  'player, so this column is no longer consulted by player_profile(). Kept '
  'because dropping a column is irreversible; written by nothing.';
comment on column public.users.age_visible is
  'RETIRED by migration 0055. The date of birth no longer leaves through '
  'player_profile(), so there is no disclosure for this to withhold. Kept '
  'because dropping a column is irreversible; written by nothing.';


-- ============================================================================
-- 7) `shares_active_community()` stops being callable by a client
-- ============================================================================
-- Migration `0043` created it as the predicate behind `COMMUNITY_MEMBERS`, and
-- section 6 just removed its only caller. What is left is a `security definer`
-- function, granted to every account holder, that answers "are these two people
-- in a community together" for any pair of user ids -- a relationship oracle
-- with nothing asking it anything.
--
-- The function is kept (something may want the predicate server-side again) and
-- the grant is not. Nothing in the application calls it.
revoke execute on function public.shares_active_community(uuid, uuid)
  from anon, authenticated, public;


-- ============================================================================
-- 8) The public discovery views stay exactly as they were
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
