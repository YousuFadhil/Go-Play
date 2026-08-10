-- Push notifications: the delivery half of the notification system.
--
-- The Notification Center stays the source of truth. `notifications` is
-- unchanged — no column added, no column removed, no policy rewritten — and a
-- notice is still created by the business operation that caused it, inside that
-- operation's transaction. Everything here sits *after* that row exists and
-- decides one thing only: whether a copy of it should also leave the database
-- as a push.
--
-- Four pieces:
--
--   1. `notification_types`   — the registry. What kinds of notice exist, how
--                               urgent each is, and which preference governs
--                               it. This is where the priority policy lives.
--   2. `notification_push_tokens`      — the devices to send to.
--   3. `notification_push_preferences` — the three switches a player has.
--   4. `push_dispatch_payload()` + a trigger — the handover to the Edge
--                               Function, which carries no policy of its own.
--
-- The rule the whole design turns on: **a notification row is always written,
-- whatever the preferences say.** Preferences suppress the push, never the
-- notice. That is `Notifications_Table_Specification.md` §13.5's recommendation
-- — create it and hide it — applied to delivery rather than to storage.
--
-- No queue, no scheduler, no retry, no delivery log. A push that fails is a
-- push that did not arrive; the notice is still in the app, which is why losing
-- one costs nothing.
--
-- Backward compatible and idempotent throughout. Nothing in this migration is
-- reachable by an existing code path, so applying it changes no behaviour until
-- `push_config` is filled in (§5).

-- 1) The type registry ---------------------------------------------------------
-- `notifications.type` is still free text — deliberately, so the feature
-- branches that own the missing producers can add a type without also editing a
-- constraint here. This table is the *routing* vocabulary rather than the
-- storage vocabulary: a type absent from it is stored normally and never
-- pushed, which is the safe direction to fail in.
--
-- `priority` is the policy from the approved specification:
--
--   high    — always pushed. The player needs to know now.
--   medium  — pushed only if they left that category switched on.
--   low     — never pushed. Notification Center only.
--
-- `category` is which of the two category switches a medium notice answers to.
-- It is meaningless for high and low and is recorded anyway, because a type
-- that changes priority later should not also have to acquire a category.
create table if not exists public.notification_types (
  type text primary key,
  priority text not null check (priority in ('high', 'medium', 'low')),
  category text not null check (category in ('match', 'community')),
  -- The push title. The body is the notice's own `message`, which is Arabic by
  -- construction (§14.4 of the table specification), so this is Arabic too:
  -- a localized title over an Arabic body would read worse than neither.
  push_title text not null
);

alter table public.notification_types enable row level security;
-- No policy: the registry is read by the dispatch function, which is
-- SECURITY DEFINER, and by nothing on the client. RLS with no policy denies
-- every client role, which is the intent.

-- The five types that exist today, plus the eleven the approved specification
-- names. Registering a type is not the same as producing one — eleven of these
-- have no producer yet, and their feature branches will add it. Registering
-- them now is what lets those branches ship a producer and nothing else.
insert into public.notification_types (type, priority, category, push_title)
values
  -- HIGH — always pushed.
  ('promoted',                      'high',   'match',     'تمت ترقيتك للأساسيين'),
  -- The business event is **Match Cancelled**. The type is `match_deleted`,
  -- and it stays that way deliberately.
  --
  -- The product has no cancelled status (migration 0006 retired it): a match
  -- that will not be played is deleted, and this is the notice that reports it.
  -- Renaming the type to `match_cancelled` was considered and rejected, because
  -- the type string is written in three places and none of them is cheap:
  --
  --   * `delete_match`       — migration 0006, redefined in 0008
  --   * `admin_delete_match` — migration 0017
  --   * every historical row already stored as `match_deleted`
  --
  -- All three producers are large SECURITY DEFINER functions. Changing a string
  -- literal inside one means re-creating the whole body in a new migration, so
  -- the rename would rewrite two business RPCs and rewrite existing history —
  -- to change a value no player ever sees. The player-facing wording is
  -- `push_title` here and `notifMatchDeleted` in the app, and both already say
  -- *cancelled*.
  --
  -- **The naming that matters is already correct.** What is left is an internal
  -- identifier, and identifiers earn their names by being stable.
  ('match_deleted',                 'high',   'match',     'تم إلغاء المباراة'),
  ('match_created',                 'high',   'match',     'مباراة جديدة'),

  -- MEDIUM — pushed if the category is enabled.
  ('registration_opened',           'medium', 'match',     'فُتح التسجيل'),
  ('match_full',                    'medium', 'match',     'اكتمل عدد اللاعبين'),
  ('teams_regenerated',             'medium', 'match',     'تم إعادة توزيع الفرق'),
  -- No producer, and no scheduler to be its producer. Registered so that
  -- whatever eventually raises it routes correctly on the day.
  ('match_starting_soon',           'medium', 'match',     'المباراة تبدأ قريباً'),
  ('community_invitation',          'medium', 'community', 'دعوة لمجتمع'),
  ('community_join_accepted',       'medium', 'community', 'تم قبول انضمامك'),
  ('match_time_changed',            'medium', 'match',     'تغيّر موعد المباراة'),
  -- The three existing types the specification does not name. Medium rather
  -- than high, because high bypasses a preference the player set on purpose and
  -- the approved high list is explicit. `moved_to_reserve` is the mirror of
  -- `promoted` and is deliberately the quieter of the pair: losing a place needs
  -- to be known, gaining one needs to be acted on.
  ('moved_to_reserve',              'medium', 'match',     'انتقلت إلى الاحتياط'),
  ('removed',                       'medium', 'match',     'تمت إزالتك من المباراة'),
  ('match_updated',                 'medium', 'match',     'تم تحديث المباراة'),

  -- LOW — stored, never pushed.
  ('community_picture_updated',     'low',    'community', 'تم تحديث صورة المجتمع'),
  ('community_description_updated', 'low',    'community', 'تم تحديث وصف المجتمع'),
  ('community_settings_updated',    'low',    'community', 'تم تحديث إعدادات المجتمع')
on conflict (type) do update
  set priority   = excluded.priority,
      category   = excluded.category,
      push_title = excluded.push_title;

-- 2) Device tokens -------------------------------------------------------------
-- One row per device, so a player with a phone and a tablet is reached on both.
-- The token is unique across the table rather than per user: a device handed to
-- somebody else keeps its token and must change hands rather than appear twice,
-- or the previous owner keeps receiving the new owner's notices.
create table if not exists public.notification_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notification_push_tokens_user_idx
  on public.notification_push_tokens (user_id);

drop trigger if exists notification_push_tokens_set_updated_at
  on public.notification_push_tokens;
create trigger notification_push_tokens_set_updated_at
  before update on public.notification_push_tokens
  for each row execute function public.set_updated_at();

alter table public.notification_push_tokens enable row level security;

drop policy if exists "push_tokens_select_own" on public.notification_push_tokens;
drop policy if exists "push_tokens_insert_own" on public.notification_push_tokens;
drop policy if exists "push_tokens_update_own" on public.notification_push_tokens;
drop policy if exists "push_tokens_delete_own" on public.notification_push_tokens;

-- A device reads and forgets its own registrations. There is nothing here worth
-- reading about anybody else, and no role that has a reason to.
create policy "push_tokens_select_own"
  on public.notification_push_tokens for select to authenticated
  using (user_id = auth.uid());
create policy "push_tokens_delete_own"
  on public.notification_push_tokens for delete to authenticated
  using (user_id = auth.uid());

-- No insert or update policy: registering goes through the function below.
-- A row-level rule cannot express the one thing registration has to do —
-- take a token away from whoever held it before — because the previous holder's
-- row is invisible to the new one under exactly that rule.
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
  if p_platform not in ('android', 'ios') then
    raise exception 'INVALID_PLATFORM';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'INVALID_TOKEN';
  end if;

  -- A phone that was somebody else's, sold or handed over, keeps its Firebase
  -- token. Without this the previous owner keeps receiving the new owner's
  -- notices, which is a privacy failure rather than a duplicate row.
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

revoke execute on function public.register_push_token(text, text)
  from anon, public;
grant execute on function public.register_push_token(text, text)
  to authenticated;

-- 3) The three switches --------------------------------------------------------
-- Three, and no more. A per-type preference matrix is a settings screen nobody
-- reads; these are the three questions a player actually has.
--
-- A missing row means the defaults below, so an account that never opens the
-- screen is not a special case anywhere: the dispatch function coalesces.
create table if not exists public.notification_push_preferences (
  user_id uuid primary key references public.users (id) on delete cascade,
  -- Medium-priority match notices.
  match_push boolean not null default true,
  -- Medium-priority community notices.
  community_push boolean not null default true,
  -- The master switch. It outranks both of the above **and outranks high
  -- priority**: "mute all" that still pushes is not mute. The notices are all
  -- still written and all still appear in the Notification Center.
  mute_all boolean not null default false,
  updated_at timestamptz not null default now()
);

drop trigger if exists notification_push_preferences_set_updated_at
  on public.notification_push_preferences;
create trigger notification_push_preferences_set_updated_at
  before update on public.notification_push_preferences
  for each row execute function public.set_updated_at();

alter table public.notification_push_preferences enable row level security;

drop policy if exists "push_prefs_select_own" on public.notification_push_preferences;
drop policy if exists "push_prefs_insert_own" on public.notification_push_preferences;
drop policy if exists "push_prefs_update_own" on public.notification_push_preferences;

create policy "push_prefs_select_own"
  on public.notification_push_preferences for select to authenticated
  using (user_id = auth.uid());
create policy "push_prefs_insert_own"
  on public.notification_push_preferences for insert to authenticated
  with check (user_id = auth.uid());
create policy "push_prefs_update_own"
  on public.notification_push_preferences for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- No delete policy: clearing the row would silently reset three switches, and
-- turning them back on is what the switches are for.

-- 4) The dispatch payload ------------------------------------------------------
-- Everything the Edge Function needs, decided here.
--
-- This is the piece that keeps policy out of the function. The function does not
-- know what "high priority" means, does not read a preference, and does not
-- choose a recipient — it receives `should_push` already answered and either
-- calls Firebase or does not. Changing the policy is a migration, not a deploy.
create or replace function public.push_dispatch_payload(p_notification_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'notification_id', n.id,
    'user_id',         n.user_id,
    'type',            n.type,
    'match_id',        n.match_id,
    -- An unregistered type has no priority, and therefore no push.
    'priority',        coalesce(t.priority, 'unregistered'),
    'category',        t.category,
    -- Presentation comes from the registry, never from the notice.
    --
    -- `message` is written by the producing operation inside the transaction
    -- that raised the notice, in one language, for a reader it knows nothing
    -- about. Letting it drive the whole push would make every producer a
    -- presentation decision and every wording change a business migration.
    -- The registry says what kind of thing this is; the message says what
    -- happened, and only in the body.
    'title',           t.push_title,
    -- Blank messages are not reachable today — `message` is NOT NULL and every
    -- producer writes one — but a push with an empty body is worse than a
    -- terse one, so the registry answers for that too.
    'body',            coalesce(nullif(trim(n.message), ''), t.push_title),
    'should_push',
      t.type is not null
      and not coalesce(p.mute_all, false)
      and (
        t.priority = 'high'
        or (
          t.priority = 'medium'
          and case t.category
                when 'match'     then coalesce(p.match_push, true)
                when 'community' then coalesce(p.community_push, true)
              end
        )
      ),
    'tokens', coalesce(
      (select jsonb_agg(k.token order by k.updated_at desc)
       from notification_push_tokens k
       where k.user_id = n.user_id),
      '[]'::jsonb
    )
  )
  from notifications n
  left join notification_types t on t.type = n.type
  left join notification_push_preferences p on p.user_id = n.user_id
  where n.id = p_notification_id;
$$;

-- Reachable by the Edge Function's service role only. It reads another
-- account's notice and another account's device tokens by design, which is
-- exactly why no client role may call it.
revoke execute on function public.push_dispatch_payload(uuid)
  from anon, authenticated, public;
-- Stated rather than inherited: the Edge Function reaches this through
-- PostgREST as `service_role`, and the revoke above is broad enough that the
-- grant it depends on should not be left to a default privilege.
grant execute on function public.push_dispatch_payload(uuid) to service_role;

-- 5) The handover --------------------------------------------------------------
-- Where the Edge Function lives and the secret that proves the caller is this
-- database. One row, no policies, so no client can read either value.
--
-- Left empty on purpose. Until it is filled in, the trigger below returns
-- immediately and the system behaves exactly as it did before this migration —
-- which is what makes applying it safe ahead of the Firebase setup.
--
-- **Exactly one row is possible, and the key is what enforces it.** `id` is a
-- boolean primary key constrained to true: the primary key rules out null, the
-- check rules out false, so `true` is the only value the column can hold and
-- the key permits it once. A second configuration is not a rule anybody has to
-- remember — it is a unique-violation. The trigger below reads
-- `where id = true` rather than `limit 1` for the same reason: there is nothing
-- to choose between. This is `app_settings`' pattern from migration 0006,
-- reused because the shape of the problem is identical.
create table if not exists public.push_config (
  id boolean primary key default true check (id),
  function_url text,
  dispatch_secret text
);

insert into public.push_config (id) values (true)
on conflict (id) do nothing;

alter table public.push_config enable row level security;
-- Belt and braces. RLS with no policy already denies every client role; this
-- row holds a shared secret, so the privilege is taken away as well rather than
-- left to be the only thing a future policy has to remember not to open.
revoke all on public.push_config from anon, authenticated;

-- `pg_net` sends the request without holding the transaction open. Guarded
-- because a stack without the extension should still take the migration.
do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net unavailable; push dispatch will no-op until it is installed.';
end $$;

create or replace function public.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select function_url, dispatch_secret
    into v_url, v_secret
  from push_config
  where id = true;

  if v_url is null or v_secret is null then
    return null;
  end if;

  -- Best-effort, and the exception handler is the important half. This trigger
  -- runs inside `delete_match`, `remove_player` and four other business
  -- operations; a push that cannot be handed off must never be the reason one
  -- of them rolls back. The notice is committed either way.
  begin
    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', v_secret
      ),
      body    := jsonb_build_object('notification_id', new.id)
    );
  exception when others then
    null;
  end;

  return null;
end;
$$;

revoke execute on function public.dispatch_push_notification()
  from anon, authenticated, public;

drop trigger if exists notifications_dispatch_push on public.notifications;
create trigger notifications_dispatch_push
  after insert on public.notifications
  for each row execute function public.dispatch_push_notification();
