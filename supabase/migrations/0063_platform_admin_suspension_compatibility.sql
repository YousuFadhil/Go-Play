-- ============ migrations/0063_platform_admin_suspension_compatibility.sql ============
-- Platform Admin, suspension: compatibility and read semantics.
--
-- ## PACKAGE CONTRACT -- DO NOT APPLY THIS MIGRATION REMOTELY BY ITSELF
--
-- `0062` and every later Platform Admin suspension migration, this file
-- included, form **one package**. `0063` is **not independently approved for
-- remote application**.
--
-- No migration in this package may be applied to the live Supabase project
-- before all four of:
--
--   * the package is complete;
--   * the package has been reviewed as one unit;
--   * a live Supabase precheck has confirmed the real schema matches what the
--     package was built against;
--   * the Product Owner and Chief Architect have explicitly approved it.
--
-- ## WHAT THIS DOES
--
-- Four changes. Suspension itself is still performed by nothing -- there is no
-- suspend RPC yet -- so these exist so that when it arrives it does not break
-- things that must keep working:
--
--   1) `public.communities` loses its table-wide UPDATE privilege. The client
--      gets exactly one column back: `join_policy`. This is what stops an owner
--      writing `is_active`, or `0062`'s suspension metadata, on their own
--      community.
--   2) `communities_select_visible` stops hiding a community from its own
--      members. Public discovery is untouched and stays active-only.
--   3) `my_profile()` stops filtering the caller's own row by `is_active`.
--   4) `player_profile()` stops refusing an inactive player.
--   5) `v_football_community_player_stats` (`0057`) stops dropping an inactive
--      player out of a community's all-time football record. Its community
--      test is untouched, so a suspended community stays hidden.
--
-- The last three share one product statement: **a suspended player is not a
-- deleted player.** Their account, their identity and their football history
-- exist, and the read paths that answer for them must go on saying so.
--
-- ## WHAT THIS DELIBERATELY DOES NOT DO
--
--   * No enforcement. `is_current_user_active()` and
--     `has_active_community_role()` (`0062`) are still wired into nothing --
--     no policy, no RPC.
--   * No suspension RPC. `admin_suspend_user`, `admin_reactivate_user`,
--     `admin_suspend_community` and `admin_reactivate_community` do not exist
--     yet, and no suspension metadata is written anywhere in this file.
--   * No mutation policy is altered. The only policy touched is a SELECT one.
--   * `admin_delete_user`, `admin_delete_community` and `admin_delete_match`
--     are untouched, in definition and in privilege.
--   * The `0061`-era surface is untouched: `set_community_logo`,
--     `community_logo_folder`, the four `community_logos_*` storage policies,
--     `preview_community_invite`, `v_public_communities`,
--     `community_statistics_recency` (`0060`),
--     `remove_played_professional_guest` and `replace_match_lineup` (`0059`),
--     both `register_player_in_match` overloads (`0054`, `0054a`), the
--     professional-guest RPCs (`0047`) and the four `0057` football views other
--     than `v_football_community_player_stats`, which section 5 recreates.
--   * `v_community_members`, `v_public_upcoming_matches`, `community_join_code`
--     and every match / team / result / rating / statistics SELECT policy are
--     untouched.
--   * `0062` is not modified.
--
-- Idempotent throughout: revoke/grant, a guarded `drop policy` before its
-- `create policy`, and `create or replace function` for both functions -- whose
-- return types are unchanged, which is what makes `replace` legal here where
-- `0056` had to drop and recreate.



-- ============================================================================
-- 1) public.communities: UPDATE narrows to one column
-- ============================================================================
-- `0056` closed the read half of this table -- `revoke select` plus a named
-- column grant -- and `0061` had to add `logo_url` to that list by name for the
-- client to see it at all. The write half was never closed: no migration from
-- `0002` to `0062` revokes table-level UPDATE on this table.
--
-- That matters now because `0062` added `suspended_at`, `suspended_by` and
-- `suspension_reason` here, and a table-level UPDATE grant extends
-- automatically to columns added after it. `0062` recorded the consequence and
-- deliberately left it, because closing it changes existing UPDATE semantics
-- and that was not a foundation migration's business. It is this one's.
--
-- Without this section an owner could, through PostgREST and under the existing
-- `communities_update_owner` policy, set `is_active = true` on their own
-- community and undo a Platform Admin suspension, or forge the metadata
-- describing it. A policy cannot prevent that: a policy decides *rows*, and
-- this is a question about *columns*. The instrument is the one `0022`
-- established on `users` and `0056` reused here for SELECT.
--
-- `public` is revoked alongside the two client roles. Supabase's default
-- privileges grant to `anon` and `authenticated` by name, so PUBLIC is not
-- expected to hold anything -- but a privilege held by PUBLIC is held by every
-- role, which would silently defeat the column list below, and a revoke costs
-- nothing to state.
revoke update on public.communities from anon, authenticated, public;

-- The one column the application actually writes directly.
--
-- `SupabaseCommunityAdapter.setJoinPolicy`
-- (`app/lib/infrastructure/supabase/supabase_community_adapter.dart`) issues
-- `.from('communities').update({'join_policy': ...}).eq('id', ...).select('id')`
-- and it is the **only** direct write to this table anywhere in the client.
-- That statement needs three things and has all three after this migration:
-- UPDATE on `join_policy`, granted here; SELECT on `id` for the `.eq` filter
-- and the `RETURNING`, granted by `0056`; and the row itself, which
-- `communities_update_owner` (`0008`) decides exactly as before.
--
-- **`logo_url` is deliberately absent from this grant.** It is not written by a
-- direct UPDATE and must not become writable by one: the client uploads the
-- object to the `community-logos` bucket and then calls
-- `set_community_logo(uuid, text)` (`0061`), which is the narrow authority that
-- exists because generic UPDATE on this table is owner-only while an *admin*
-- may also change the picture. `0061` grants `select (logo_url)` and no UPDATE
-- at all, and that stays exactly as it is. `set_community_logo` itself is not
-- modified here; making it suspension-aware belongs with the enforcement work.
--
-- Every other write to this table goes through a `security definer` function
-- and is unaffected by anything in this section, because a definer function
-- runs as its owner rather than as the caller: `create_community` (`0016`)
-- inserts the row, `transfer_ownership` (`0009`) writes `owner_id`,
-- `regenerate_join_code` (`0015`) writes `join_code`, `set_community_logo`
-- (`0061`) writes `logo_url`, `delete_community` (`0017`) removes it -- and the
-- future suspension RPCs will write `is_active` and the `0062` metadata the
-- same way. That is the point of taking the privilege from the client rather
-- than from the product.
--
-- Not granted, deliberately: `id`, `owner_id`, `name`, `description`,
-- `join_code`, `logo_url`, `is_active`, `created_at`, `updated_at`,
-- `suspended_at`, `suspended_by`, `suspension_reason`. `name` and `description`
-- are on that list because no approved feature edits them -- the app sets them
-- once at creation and never updates them -- and granting a privilege nothing
-- uses is how the previous hole was left open.
grant update (join_policy) on public.communities to authenticated;

-- INSERT, DELETE and SELECT are untouched by this migration. `0056` and `0061`
-- settled SELECT between them; INSERT and DELETE are reached only through the
-- definer functions listed above.



-- ============================================================================
-- 2) A suspended community stays readable to its own members
-- ============================================================================
-- `communities_select_visible` has said `using (is_active)` since `0016`, and
-- that single predicate has been doing two jobs: keeping a soft-deleted
-- community out of sight, and -- as a side effect nobody needed until now --
-- keeping it out of sight of the people already inside it.
--
-- The approved behaviour separates them. A suspended community is hidden from
-- public and discovery surfaces, and its existing members can still read what
-- they were part of: the community row, and through it the matches, results,
-- teams and statistics whose own policies already admit them.
--
-- **Discovery does not run through this policy and is not affected.** The
-- public read models are `v_public_communities` (`0061`) and
-- `v_public_upcoming_matches` (`0033`), and neither is `security_invoker`: both
-- execute with the view owner's privileges, so no policy on `communities`
-- reaches them, and both carry their own `where c.is_active`. Neither view is
-- touched by this migration. `preview_community_invite` (`0061`),
-- `join_community` (`0016`), `join_community_by_code` (`0007`) and
-- `community_join_code` (`0055`) each test `is_active` inside their own bodies
-- and are likewise untouched, so an inactive community still cannot be
-- previewed, joined, or have its code read.
--
-- `is_community_member` is called rather than restated. It is `security
-- definer` (`0008`), which is what keeps this from recursing: the predicate
-- reads `community_members`, whose own SELECT policy asks `is_community_member`
-- in turn, and an invoker-rights version would send the policy back through
-- itself. `0002` recorded that trap when the first membership helper was
-- written and `0043` restated it. The function is not modified here.
--
-- Command and role are preserved exactly: `for select`, `to authenticated`.
-- Nothing about who evaluates this policy changes -- only what it admits.
drop policy if exists "communities_select_visible" on public.communities;
create policy "communities_select_visible"
  on public.communities
  for select
  to authenticated
  using (
    is_active
    or public.is_community_member(id, auth.uid())
  );

-- No other read policy is altered. The member-scoped policies on
-- `community_members`, `matches`, `match_registrations`, `match_results`,
-- `match_goals`, `rating_history`, `match_team_assignments`,
-- `match_professional_guests` and `community_statistics` all ask
-- `is_community_member` / `is_match_community_member` already, and so already
-- admit a member whose community has been suspended. This one policy was the
-- only thing standing in front of them. No Storage policy is touched.



-- ============================================================================
-- 3) my_profile(): the caller's own row, suspended or not
-- ============================================================================
-- `0055` created this function with `and u.is_active` in its WHERE clause. For
-- a suspended account that returns no rows, and the client
-- (`supabase_profile_adapter.dart`) turns an empty result into a
-- `NotFoundFailure` -- so a suspended player opening their own account screen
-- would be told their profile does not exist. It does exist. Suspension does
-- not delete an account, and the one read path a person has to their own record
-- must not claim otherwise.
--
-- The predicate is the only thing that changes. Everything that makes this
-- function safe is preserved exactly:
--
--   * **Still strictly self-only.** There is no user-id parameter, so there is
--     no argument to point at somebody else -- which is `0055`'s entire
--     authorization argument and is untouched. It has not become a general
--     user lookup.
--   * **Same return shape** -- ten columns, same names, same types, same
--     order. That is what makes `create or replace` legal and means no caller
--     and no mapper changes.
--   * **No suspension metadata.** `suspended_at`, `suspended_by` and
--     `suspension_reason` are not in the column list and are not added: they
--     are not part of the approved self-profile contract, and what the client
--     will later use to know its own state is `is_current_user_active()`
--     (`0062`), not this.
--   * **No widening.** `phone` is here only because `0055` put it here and it
--     is the owner's own number; nothing else is added.
--   * Same `security definer`, `stable`, `set search_path = public`, same
--     session requirement, same grants.
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
  -- `is_active` is deliberately absent. A suspended account still has a
  -- profile, and this is its owner asking for it (migration 0063).
  where u.id = auth.uid();
end;
$$;

comment on function public.my_profile() is
  'The signed-in player''s own account row, phone included. Takes no user id, '
  'so it cannot be pointed at anybody else -- see migration 0055. Returns the '
  'row whether or not the account is active: suspension does not delete a '
  'profile (migration 0063). Carries no suspension metadata.';

-- `create or replace` preserves privileges; restated so this file says what
-- must be true when it finishes, in `0055`'s words.
revoke execute on function public.my_profile() from anon, public;
grant execute on function public.my_profile() to authenticated;



-- ============================================================================
-- 4) player_profile(): a suspended player is not a missing player
-- ============================================================================
-- `0056` looks the player up with `and u.is_active` and raises `USER_NOT_FOUND`
-- when the row does not come back. Once suspension exists that turns every
-- suspended player into a 404 for everybody else -- and the approved behaviour
-- is that their identity, statistics and historical records stay readable. A
-- record that cannot be opened is not preserved in any sense a reader would
-- recognise.
--
-- One predicate is removed. `USER_NOT_FOUND` keeps its exact meaning for an id
-- that names nobody, which is the case it was written for.
--
-- **The `0056` privacy projection is preserved in full**, and the column list
-- below is the proof: it is byte-for-byte the one `0056` established. Nothing
-- it removed comes back -- no `phone`, no email, no auth identifier, no
-- `date_of_birth`, and neither retired privacy column. The `COMMUNITY_MEMBERS`
-- gate is not restored: `shares_active_community` is still called by nothing
-- and its execute privilege, revoked by `0056`, is not restored either.
-- Authentication is unchanged -- `anon` has no execute and the body still
-- refuses without `auth.uid()`. `is_self` still reports on the caller.
--
-- Statistics, ratings, `v_community_members` and every historical match, team
-- and result view are untouched by this section. The one football view this
-- migration does recreate is handled separately in section 5.
--
-- `create or replace` rather than drop-and-create: `0056` had to drop because
-- it was changing the return type, and this migration is not -- the signature
-- and the return table are identical to `0056`'s, which keeps every caller
-- working across the change and leaves no window in which the function is
-- absent.
create or replace function public.player_profile(p_user_id uuid)
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

  -- `is_active` is deliberately absent (migration 0063). USER_NOT_FOUND now
  -- means what it says: no such player. A suspended one is still a player, and
  -- their football record is the thing this function exists to show.
  select * into v_user from users u where u.id = p_user_id;
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
  'whatever communities either of them is in, and whether or not the player is '
  'active -- a suspended player is not a missing one (migration 0063). Never '
  'the phone, the email, an auth identifier or the date of birth -- see '
  'migration 0056.';

-- Restated, in `0056`'s words, for the same reason as section 3.
revoke execute on function public.player_profile(uuid) from anon, public;
grant execute on function public.player_profile(uuid) to authenticated;



-- ============================================================================
-- 5) v_football_community_player_stats: a suspended player keeps their record
-- ============================================================================
-- `0057` built this view with two active tests, and only one of them survives
-- the suspension model:
--
--     join public.users u       on u.id = cs.user_id and u.is_active
--     join public.communities c on c.id = cs.community_id and c.is_active
--
-- The community test is right and stays. A suspended community is hidden from
-- the public surface, which is what every other view in `0057` and both
-- discovery views already say.
--
-- The **user** test is the one that conflicts. `0057` wrote it on the reasoning
-- that "ranking somebody who is gone would be publishing a record with nobody
-- attached to it" -- and against `0057`'s own world, where `is_active = false`
-- meant a deactivated account, that held. Suspension changes what the flag
-- means. A suspended player is not gone: their account exists, `player_profile`
-- still answers for them (section 4), and the approved model preserves their
-- identity, their statistics and their historical participation. Dropping them
-- out of a community's all-time record the moment an administrator acts would
-- rewrite history that the same model promises to keep.
--
-- So one predicate is removed and nothing else. The output shape is identical
-- to `0057`'s, column for column and expression for expression, which is what
-- makes `create or replace view` legal here -- no reader and no mapper changes.
-- `period_type = 'overall'` is unchanged, the `community_statistics` source is
-- unchanged, and no column is added: no phone, no email, no date of birth, no
-- auth identifier and none of `0062`'s suspension metadata.
create or replace view public.v_football_community_player_stats as
select
  cs.community_id,
  cs.user_id,
  u.full_name                             as display_name,
  u.avatar_path,
  u.primary_position,
  u.secondary_position,
  coalesce(u.overall_rating, 5.0)::numeric(4,2) as overall_rating,
  cs.matches_played,
  cs.wins,
  cs.draws,
  cs.losses,
  cs.goals,
  cs.mvp_count
from public.community_statistics cs
join public.users u       on u.id = cs.user_id
join public.communities c on c.id = cs.community_id and c.is_active
where cs.period_type = 'overall';

comment on view public.v_football_community_player_stats is
  'Cycle 2 read model: one row per player with an all-time record in a '
  'community -- the counters the leaderboards rank on, plus the Global Rating. '
  'A preserved record, not a roster: an account suspension does not erase the '
  'player''s football identity or statistics, so a suspended player still '
  'appears here. Inactive communities remain excluded from the public surface. '
  'See migrations 0057 and 0063.';

-- Privileges, in `0057`'s own terms and for `0057`'s own reason: Supabase's
-- default-privileges rule grants ALL on a new object in `public` before a
-- migration's grant is reached, so `revoke all` closes it and the named revoke
-- records which privileges that covered. `create or replace view` replaces in
-- place and preserves what the view already held, so this is a re-assertion
-- rather than a repair -- and it is stated anyway, because the file should say
-- what must be true when it finishes. `anon` is revoked rather than merely not
-- granted: football history is for people with an account.
revoke all on public.v_football_community_player_stats
  from anon, authenticated, public;
revoke insert, update, delete, truncate, references, trigger
  on public.v_football_community_player_stats
  from anon, authenticated;
grant select on public.v_football_community_player_stats to authenticated;

-- The other four `0057` views are deliberately not recreated here.
-- `v_football_completed_matches`, `v_football_match_participants`,
-- `v_football_match_lineup` and `v_football_community_stats` already preserve
-- user identity and history while requiring an active community, so the
-- suspension model asks nothing of them.



-- ============================================================================
-- 6) What this migration did not touch
-- ============================================================================
-- Stated so a later reader can confirm the contract from the file itself rather
-- than from a diff:
--
--   * **Discovery and public reads** -- `v_public_communities` (`0061`),
--     `v_public_upcoming_matches` (`0033`) and the other four `0057` football
--     views are unmodified, so an inactive community and its matches stay out
--     of public discovery. `v_football_community_player_stats` is recreated in
--     section 5 and keeps its `c.is_active` test, so that remains true of it
--     too;
--   * **Member and history reads** -- `v_community_members` (`0025`) keeps its
--     INNER join, and every match, registration, team, result, goal, rating and
--     statistics SELECT policy is unmodified;
--   * **Community credentials and logo** -- `community_join_code` (`0055`),
--     `preview_community_invite` (`0061`), `set_community_logo` (`0061`),
--     `community_logo_folder` (`0061`) and the four `community_logos_*` Storage
--     policies are unmodified, and `0061`'s `grant select (logo_url)` stands;
--   * **Guests, lineups and statistics** -- `replace_match_lineup` (`0059`),
--     both `register_player_in_match` overloads (`0054`, `0054a`),
--     `remove_played_professional_guest` (`0059`),
--     `add_/remove_/rename_professional_guest` (`0047`) and
--     `community_statistics_recency` (`0060`) are unmodified;
--   * **Authorization** -- `has_community_role`, `is_community_member`,
--     `is_match_community_member` and `is_match_community_admin` are
--     unmodified, and `is_current_user_active` / `has_active_community_role`
--     (`0062`) are still called by nothing;
--   * **Mutation** -- not one mutation policy and not one mutation RPC is
--     altered; no suspension RPC exists yet;
--   * **Hard delete** -- `admin_delete_user`, `admin_delete_community` and
--     `admin_delete_match` are unchanged in definition and in privilege;
--   * no row was written, nothing was backfilled, and no suspension metadata
--     was set.
