-- ============ migrations/0043_profile_visibility.sql ============
-- A player's profile, as other players may see it.
--
-- Two Product Owner decisions and the one read path that enforces them:
--
--   1) **Profile visibility.** `EVERYONE` (the default) or
--      `COMMUNITY_MEMBERS` — a profile the viewer may open only if the two of
--      them share an active community. The owner always sees their own, and a
--      shared active community always opens a profile whatever the setting says,
--      because that is what "community members only" means.
--
--   2) **Age visibility.** Visible by default; a player may hide it. Hidden
--      means the *date of birth does not leave the database* for anybody but its
--      owner — not that the application declines to draw it. Age itself is still
--      never stored: `KB-C7` derives it from the date, and this migration adds no
--      column that would let it be written.
--
-- Nothing about matches, teams, ratings or the engine is touched. The BTGE input
-- read (`users.date_of_birth`, read by the lineup generator) is untouched and
-- deliberately so: age balance is an internal engine metric, not a profile
-- disclosure, and narrowing that read is a different subject from this one.
--
-- Idempotent throughout: `add column if not exists`, `create or replace`,
-- guarded constraint drops.


-- ============================================================================
-- 1) The two preferences
-- ============================================================================
-- Both carry the permissive default, so every account that predates this
-- migration keeps behaving exactly as it did: a profile anyone signed in may
-- read, with an age on it.
alter table public.users
  add column if not exists profile_visibility text not null default 'EVERYONE',
  add column if not exists age_visible boolean not null default true;

alter table public.users
  drop constraint if exists users_profile_visibility_check;
alter table public.users
  add constraint users_profile_visibility_check
    check (profile_visibility in ('EVERYONE', 'COMMUNITY_MEMBERS'));

comment on column public.users.profile_visibility is
  'Who may open this profile: EVERYONE (default) or COMMUNITY_MEMBERS -- see '
  'migration 0043. Enforced by player_profile(); never read by the client to '
  'decide access.';
comment on column public.users.age_visible is
  'Whether other players receive this player date of birth. False withholds '
  'it at the source; the owner always receives their own.';

-- `0022` revoked the blanket UPDATE and grants named columns instead, because a
-- policy cannot restrict which columns a statement touches. These two join that
-- list; `users_update_own_profile` (migration `0001`) is what still confines the
-- write to the row's owner.
grant update (profile_visibility, age_visible) on public.users to authenticated;


-- ============================================================================
-- 2) Do these two players share an active community?
-- ============================================================================
-- `security definer` for the same reason `is_community_member` is: the predicate
-- reads `community_members` from inside a call that is itself subject to
-- policies on `community_members`, and an invoker-rights version would recurse.
--
-- Active only. A community that has been soft-deleted is not a community two
-- people are in together, and letting one keep a profile open would make
-- deletion decorative.
create or replace function public.shares_active_community(
  p_viewer uuid,
  p_target uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from community_members viewer
    join community_members target
      on target.community_id = viewer.community_id
    join communities c on c.id = viewer.community_id
    where viewer.user_id = p_viewer
      and target.user_id = p_target
      and c.is_active
  );
$$;

comment on function public.shares_active_community(uuid, uuid) is
  'Whether two players are both in the same active community -- the predicate '
  'behind COMMUNITY_MEMBERS profile visibility (migration 0043).';

revoke execute on function public.shares_active_community(uuid, uuid)
  from anon, public;
grant execute on function public.shares_active_community(uuid, uuid)
  to authenticated;


-- ============================================================================
-- 3) The one read path for another player's profile
-- ============================================================================
-- `security definer`, so the decision is this function's and not a policy's, and
-- so that what it returns is a fixed column list rather than a row of `users`.
-- That column list is the whole point:
--
--   * **`phone` is absent.** It is a contact detail, and no approved document
--     asks for it to be published to other players.
--   * **the email and every auth identifier are absent.** They live in
--     `auth.users`, which this function does not read and has no reason to.
--   * **`date_of_birth`** comes back only for the owner, or when the player has
--     left their age visible. A hidden age is withheld here, at the source,
--     rather than dropped by whoever is drawing the screen.
--
-- The counters and the rating are included because they are the profile: the
-- career record is what the screen is for, and a second call for them would be a
-- second authorization decision about the same profile.
--
-- Three outcomes, in the project's own vocabulary. `USER_NOT_FOUND` for an id
-- that names nobody active; `PROFILE_NOT_VISIBLE` for a profile the caller may
-- not open, which the application maps to an authorization failure and words for
-- itself; a row otherwise.
create or replace function public.player_profile(p_user_id uuid)
returns table (
  user_id uuid,
  full_name text,
  primary_position text,
  secondary_position text,
  avatar_path text,
  date_of_birth date,
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
  v_self boolean;
  v_age_visible boolean;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_user from users u where u.id = p_user_id and u.is_active;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  v_self := v_user.id = auth.uid();

  -- The owner first, then the setting. A player is never refused their own
  -- profile, whatever they have set.
  if not v_self
     and v_user.profile_visibility = 'COMMUNITY_MEMBERS'
     and not shares_active_community(auth.uid(), v_user.id) then
    raise exception 'PROFILE_NOT_VISIBLE';
  end if;

  v_age_visible := v_self or v_user.age_visible;

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
    case when v_age_visible then v_user.date_of_birth end,
    v_user.overall_rating,
    coalesce(v_stats.matches_played, 0),
    coalesce(v_stats.wins, 0),
    coalesce(v_stats.losses, 0),
    coalesce(v_stats.draws, 0),
    coalesce(v_stats.goals, 0),
    coalesce(v_stats.mvp_count, 0),
    v_self;
end;
$$;

comment on function public.player_profile(uuid) is
  'One player profile as another player may see it: identity, playing '
  'positions, picture, career counters, and a date of birth only when the age '
  'is visible. Never the phone, the email or any auth identifier -- see '
  'migration 0043.';

revoke execute on function public.player_profile(uuid) from anon, public;
grant execute on function public.player_profile(uuid) to authenticated;


-- ============================================================================
-- 4) The owner's own preferences, on the read model they already read
-- ============================================================================
-- Appended, never reordered: `create or replace view` may add trailing columns
-- and may not touch the existing ones. Every column below is `0031`'s, in
-- `0031`'s order, with the two new preferences after the last of them.
--
-- The view stays `security_invoker = on`, so it remains
-- `authenticated_select_active_users` deciding what comes back. That is
-- unchanged on purpose: this view is the *owner's* profile read and the
-- statistics read, and the visibility rule belongs to `player_profile` above,
-- which is the path another player's profile is opened by.
create or replace view public.v_user_profile
with (security_invoker = on) as
select
  u.id                as user_id,
  u.full_name,
  u.phone,
  u.primary_position,
  u.secondary_position,
  u.date_of_birth,
  u.overall_rating,
  u.is_active,
  u.created_at,
  u.updated_at,
  ps.matches_played,
  ps.wins,
  ps.losses,
  ps.draws,
  ps.goals,
  ps.mvp_count,
  ps.updated_at      as statistics_updated_at,
  u.avatar_path,
  u.profile_visibility,
  u.age_visible
from public.users u
left join public.player_statistics ps on ps.user_id = u.id;

comment on view public.v_user_profile is
  'Read model: a player profile -- users joined to the global career counters '
  'in player_statistics. Counters are null until the first recorded result. '
  'avatar_path is a path inside the avatars bucket, null when none was set. '
  'profile_visibility and age_visible are the owner own preferences (0043).';
