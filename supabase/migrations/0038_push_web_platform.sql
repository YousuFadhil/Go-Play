-- Web push: let a browser register as a device.
--
-- Two lines of actual change, and nothing else. `notification_push_tokens`
-- accepted `android` and `ios` because those were the only builds that could
-- produce a token; a web build now can, and both the column constraint and
-- `register_push_token` reject it. This migration widens exactly those two
-- checks and touches nothing else.
--
-- Nothing downstream needs to know. `push_dispatch_payload` selects tokens
-- without reading `platform`, and the Edge Function sends to a token without
-- asking what kind it is — FCM decides that from the token itself. The column
-- is there to make a row legible, not to route one.
--
-- Backward compatible: every existing row still satisfies the wider check, and
-- Android and iOS registration is unchanged in both places.

-- 1) The column ----------------------------------------------------------------
-- The constraint was written inline in 0036, so PostgreSQL named it
-- `<table>_<column>_check`. Dropped by that name and re-added, because a check
-- constraint cannot be altered in place.
alter table public.notification_push_tokens
  drop constraint if exists notification_push_tokens_platform_check;

alter table public.notification_push_tokens
  add constraint notification_push_tokens_platform_check
  check (platform in ('android', 'ios', 'web'));

-- 2) The registration function ---------------------------------------------------
-- Re-created verbatim from 0036 apart from the platform list. The body is
-- restated rather than patched because a function has no partial redefinition,
-- and the comments are kept so this file is readable without the previous one.
create or replace function public.register_push_token(
  p_token text, p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'INVALID_PLATFORM';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'INVALID_TOKEN';
  end if;

  -- A phone that was somebody else's, sold or handed over, keeps its Firebase
  -- token. Without this the previous owner keeps receiving the new owner's
  -- notices, which is a privacy failure rather than a duplicate row.
  --
  -- A shared browser profile is the same problem with a shorter fuse: two
  -- accounts signing in from one browser produce the *same* web token, so the
  -- second sign-in has to take it from the first. That is what this delete
  -- does, and it is why signing out removes the row (`PushService.signOut`)
  -- rather than leaving it to be overwritten later.
  delete from notification_push_tokens
  where token = p_token and user_id <> v_user;

  insert into notification_push_tokens (user_id, token, platform)
  values (v_user, p_token, p_platform)
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

-- `create or replace` keeps the existing privileges. Restated anyway, matching
-- 0036, so the grant is a property of the function's definition rather than of
-- the order the migrations happened to run in.
revoke execute on function public.register_push_token(text, text)
  from anon, public;
grant execute on function public.register_push_token(text, text)
  to authenticated;
