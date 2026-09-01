-- ============ migrations/0055_private_account_compatibility.sql ============
-- Cycle 1, phase one of two: the new paths, and nothing that could break the
-- old client.
--
-- WHY THIS MIGRATION IS SPLIT FROM ITS OWN HARDENING
--
-- Staging and production share one Supabase project. That is an accepted MVP
-- constraint, and it has a consequence that decides the shape of this file: a
-- migration is applied to *one* database that *two* clients talk to -- the
-- release currently deployed from `main`, and the Cycle 1 build that has not
-- shipped yet. There is no window in which only one of them exists.
--
-- The deployed `main` client reads `communities.join_code` in its ordinary
-- community list (`SupabaseCommunityAdapter._columns`) and reads
-- `v_user_profile.phone` for its own account screen. Revoking either privilege
-- in a single migration would therefore break the live product the moment the
-- migration landed, and would keep it broken until a new build reached every
-- user. The boundary would be closed and the application would be down.
--
-- So the work is split in two, along the only line that matters:
--
--   * `0055` (this file) is **purely additive**. It creates the two functions
--     the new client needs and changes nothing that exists. Applying it to the
--     shared project is safe with the old client still deployed, because from
--     the old client's point of view nothing has changed at all.
--
--   * `0056_private_account_hardening.sql` is the breaking half: the column
--     revokes, the rebuilt read model, the narrowed football profile. It is
--     applied only once a client that can live without those columns is the
--     one being served.
--
-- WHAT THIS MEANS, SAID PLAINLY
--
-- **After this migration the two leaks are still open.** `communities.join_code`
-- and `users.phone` remain selectable exactly as they are today. That is not an
-- oversight and not a partial fix -- it is the requirement this file is built
-- to meet. Nothing here should be read as closing anything; `0056` is what
-- closes them, and until it is applied Cycle 1 is not security-complete.
--
-- WHAT IS ADDED
--
--   1) `community_join_code(uuid)` -- the join code, to an owner or admin.
--   2) `my_profile()`             -- the caller's own account row, self-only.
--
-- Both are new names. Neither replaces, narrows or shadows an existing object,
-- so no query the deployed client makes can behave differently after this runs.
-- Both are `security definer` with an explicit `search_path`, and both are
-- revoked from `anon` and `public` before being granted to `authenticated`.
--
-- Idempotent: `create or replace` plus revoke/grant throughout.



-- ============================================================================
-- 1) The one path to a join code
-- ============================================================================
-- An owner or an admin still has to be able to invite people, and inviting
-- people is showing them the code. That is a community-management action, so it
-- asks the community-management question: `has_community_role(..., 'admin')`,
-- the same predicate that gates every other organizer operation (PD-07, PD-16).
-- Being a member is not enough -- an ordinary Player has no administrative
-- reason to hold the credential that lets them hand the community to anybody.
--
-- `security definer`, because once `0056` revokes the column privilege this
-- function is the reason that is survivable -- and because it must already work
-- before then, so the new client can ship first. The function returns one text
-- value and takes one id, so there is no projection a caller could widen and no
-- row they could reach past.
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
  'The community join code, to an owner or admin and to nobody else. Added by '
  'migration 0055; it becomes the *only* read path once 0056 revokes SELECT on '
  'the column itself.';

revoke execute on function public.community_join_code(uuid) from anon, public;
grant execute on function public.community_join_code(uuid) to authenticated;



-- ============================================================================
-- 2) `my_profile()`: the caller's own account row
-- ============================================================================
-- Self-only by construction, not by policy: the function does not take a user
-- id, so there is no argument a caller could point at somebody else. It reads
-- `auth.uid()` and nothing else, which means "User A retrieving User B's phone"
-- is not a request this function can express.
--
-- `security definer` because `0056` stops `phone` being selectable by the
-- caller, and because this is the one place the product has decided it should
-- be. It is created here, ahead of that revoke, so the new client has somewhere
-- to read its own number from before the old path goes.
--
-- The column list is the account screen's and the profile screen's, together:
-- identity, contact number, playing inputs, picture, rating and the two privacy
-- preferences. It is not a football profile and is never read for one --
-- `player_profile` is that path.
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
-- 3) What this migration deliberately does NOT do
-- ============================================================================
-- Listed rather than left to inference, because the absences are the design and
-- a reader who does not know that will "fix" them:
--
--   * `communities.join_code` keeps its SELECT privilege. The deployed client
--     asks for the column by name in every community read.
--   * `users.phone` keeps its SELECT privilege, and `v_user_profile` keeps
--     carrying it. The deployed account screen reads both.
--   * `v_user_profile` is not rebuilt. Its column list is what the deployed
--     client projects.
--   * `player_profile(uuid)` keeps its signature, its `date_of_birth` column
--     and its `COMMUNITY_MEMBERS` check. Changing a return type means dropping
--     and recreating the function, and a caller that arrives mid-swap gets an
--     error rather than a row.
--   * `shares_active_community` keeps its grant, because `player_profile` above
--     still calls it.
--
-- Every one of those moves to `0056`.
