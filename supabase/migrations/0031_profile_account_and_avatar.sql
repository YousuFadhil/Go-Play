-- A profile a player can actually keep up to date.
--
-- Until now the profile screen wrote three columns — date of birth, primary and
-- secondary position — because that is what the engine reads (§4.1). The name,
-- the phone and the email were fixed at sign-up with no way to correct a typo,
-- and there was no picture at all.
--
-- Product Owner decision: a player may edit their full name, email, password,
-- phone number, and upload an avatar. Email and password are Auth credentials
-- and stay there — `auth.updateUser` is the only thing that may move them, and
-- nothing in this migration touches `auth.users`. What is here is the profile
-- half: the two `public.users` columns a player may now write, the avatar
-- column, and the storage the picture lives in.
--
-- `overall_rating` stays out of the player's reach, exactly as `0022` left it.
-- `OP-1` makes it system-managed; widening what a profile may write is not an
-- occasion to widen that.
--
-- Backward compatible: one nullable column added, one column list re-granted,
-- one view gaining a trailing column. Idempotent throughout.

-- 1) The avatar --------------------------------------------------------------
-- A path inside the `avatars` bucket rather than a URL: a stored URL would bake
-- in the project host and the signing scheme, and both are deployment details
-- that have changed before. The application composes the public URL from the
-- path, which is what the storage client already does.
--
-- Null means no picture, which is the ordinary state of a new account and never
-- an error. Nothing derives from it and nothing requires it.
alter table public.users
  add column if not exists avatar_path text;

-- 2) What a player may write on their own row --------------------------------
-- `0022` revoked the blanket UPDATE and granted named columns, because a policy
-- cannot restrict which columns an update touches and a player could otherwise
-- set their own rating. That reasoning is unchanged; the list grows by the two
-- fields the profile screen now edits and the avatar it now stores.
--
-- `full_name` and `phone` were already in the list — the sign-up path writes
-- them through the trigger, and the grant has always allowed the row's owner to
-- correct them. What was missing was a screen, not a privilege.
--
-- `is_active` stays out: soft deletion is administrative. `overall_rating`
-- stays out: it is earned.
grant update (phone, full_name, primary_position, secondary_position,
  date_of_birth, avatar_path) on public.users to authenticated;

-- 3) The read model gains the picture ----------------------------------------
-- Appended, never reordered: `create or replace view` may add trailing columns
-- and may not do anything else to the existing ones. Every column below is
-- `0025`'s, in `0025`'s order, with `avatar_path` after the last of them.
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
  u.avatar_path
from public.users u
left join public.player_statistics ps on ps.user_id = u.id;

comment on view public.v_user_profile is
  'Read model: a player profile -- users joined to the global career counters '
  'in player_statistics. Counters are null until the first recorded result. '
  'avatar_path is a path inside the avatars bucket, null when none was set.';

-- 4) Where the picture lives --------------------------------------------------
-- A public bucket. An avatar is shown beside a player''s name on every screen
-- that lists a roster, a lineup or a leaderboard, so it is read by everyone who
-- can see the player at all; signing each of those reads would buy nothing and
-- cost a round trip per face. What is *not* public is writing: the policies
-- below let a player write only inside a folder named after their own id.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- The folder is the owner. `storage.foldername(name)` splits the object path,
-- and requiring its first element to equal the caller''s id is what stops one
-- player overwriting another''s face. The same predicate governs insert, update
-- and delete, so replacing a picture is the same permission as setting one.
drop policy if exists "avatars_read_all" on storage.objects;
create policy "avatars_read_all"
  on storage.objects
  for select
  to public
  using (bucket_id = 'avatars');

drop policy if exists "avatars_write_own" on storage.objects;
create policy "avatars_write_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
