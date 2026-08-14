-- Announce a new match to the community.
--
-- `match_created` has existed as a *routing* decision since 0036 — registered in
-- `notification_types` as high/match with the push title 'مباراة جديدة', and
-- displayed in the app since the same release — but nothing ever wrote one.
-- 0036 said so in as many words: eleven registered types have no producer, and
-- the branch that adds a producer adds a producer and nothing else. This is that
-- branch for one of them.
--
-- **Nothing here is new machinery.** The notice goes through `create_notification`
-- like every other producer, the `after insert` trigger on `notifications` hands
-- it to `push-dispatch`, and the Edge Function sends it. No queue, no scheduler,
-- no platform branch: Android, iOS and the web differ only in which block of the
-- FCM message applies to their token, which the function already decides.
--
-- The only change to `create_match` is the statement at the end. Everything
-- above it — every authorisation check, every validation, the insert itself — is
-- reproduced verbatim from 0026, because a function has no partial redefinition.
-- Diff this against `0026_rpc_functions.sql` and the fan-out is the whole of it.
--
-- No change to `notification_types`: 0036 already registered the type, its
-- priority, its category and its push title, and re-deciding any of those here
-- would move the policy out of the file that owns it.

create or replace function public.create_match(
  p_community_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players integer,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_community communities%rowtype;
  v_match_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_community from communities where id = p_community_id;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if not v_community.is_active then raise exception 'COMMUNITY_INACTIVE'; end if;

  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_title is null or char_length(trim(p_title)) < 2 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_location is null or char_length(trim(p_location)) < 2 then
    raise exception 'INVALID_LOCATION';
  end if;
  if p_start_at is null or p_end_at is null then
    raise exception 'INVALID_TIME_RANGE';
  end if;
  if p_end_at <= p_start_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_start_at <= now() then raise exception 'START_IN_PAST'; end if;
  if p_starting_players is null
     or p_starting_players < 4 or p_starting_players > 30 then
    raise exception 'INVALID_STARTING_PLAYERS';
  end if;

  -- max_registration is omitted on purpose: matches_set_capacity fills it.
  insert into matches (
    community_id, created_by, title, location,
    start_at, end_at, starting_players, description
  )
  values (
    p_community_id,
    auth.uid(),
    trim(p_title),
    trim(p_location),
    p_start_at,
    p_end_at,
    p_starting_players,
    case
      when p_description is null or trim(p_description) = '' then null
      else trim(p_description)
    end
  )
  returning id into v_match_id;

  -- THE ONLY ADDITION -----------------------------------------------------------
  -- Announce it to the community, every member except the admin who just made it.
  --
  -- The recipient set is `community_members` rather than `match_registrations`:
  -- nobody is registered yet, and telling the already-registered is the opposite
  -- of the point. This is the one notice whose job is to reach people who have
  -- not acted.
  --
  -- The creator is excluded here rather than in `create_notification`, which has
  -- no opinion about actors and is used by producers that deliberately notify the
  -- person acting. Excluding them is this notice's rule, so it lives in this
  -- statement.
  --
  -- Membership is the only filter. `users.is_active` is deliberately not
  -- consulted, matching `update_match` and every other producer: a notice is
  -- written for a member and read when they can read it, and making this one
  -- statement the exception would make the rule harder to see, not the inbox
  -- cleaner.
  --
  -- `message` is the push *body*; the push title comes from the registry
  -- ('مباراة جديدة') and the Notification Center renders the reader's own
  -- localized label for a registered type. So the body carries the two facts a
  -- title cannot: which match, and where.
  --
  -- The `perform ... from` form is `update_match`'s, reused so the two producers
  -- read the same way.
  perform create_notification(
      cm.user_id,
      v_match_id,
      'match_created',
      trim(p_title) || ' — ' || trim(p_location)
  )
  from community_members cm
  where cm.community_id = p_community_id
    and cm.user_id <> auth.uid();
  -- END OF THE ADDITION ---------------------------------------------------------

  return v_match_id;
end;
$$;

-- `create or replace` keeps the existing privileges. Restated so the grant is a
-- property of the definition rather than of the order the migrations ran in.
revoke execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) from anon, public;
grant execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, integer, text
) to authenticated;
