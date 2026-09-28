-- ============ migrations/0089_wave3_evidence_capture.sql ============
-- Wave 3: Evidence capture.
--
-- Design authority: Docs/engineering/WAVE3_EVIDENCE_DESIGN.md (approved).
--
-- Two additive evidence contracts, and nothing else:
--
--   1. BTGE generation evidence -- `btge_generation_runs`, one immutable row
--      per successful generated-lineup save, written atomically with the
--      lineup by `save_generated_lineup_v1`.
--   2. Anonymous public-link acquisition -- `product_events` stays the one
--      analytics table. It gains a nullable `acquisition_id`, a constrained
--      anonymous `public_link_opened` shape and one event,
--      `public_link_signup_completed`, each written by its own narrow RPC.
--
-- What does not change:
--
--   * `replace_match_lineup` -- definition and privileges untouched. Legacy
--     clients and every manual/correction path keep calling it directly.
--   * `record_product_event` -- untouched. It restates its own eleven event
--     names, so it can never write `public_link_signup_completed`, and it still
--     refuses `anon`.
--   * `match_team_assignments` remains the only current/final lineup.
--   * No historical backfill of any kind: no generation run and no acquisition
--     row is reconstructed. Both start empty when this migration is applied.


-- ============================================================================
-- 1) btge_generation_runs -- what BTGE proposed, before any human edit
-- ============================================================================
-- Append-only evidence. It is never a lineup source: nothing reads it to decide
-- who plays, and the lineup the product shows is still `match_team_assignments`.
--
-- **No foreign keys, deliberately.** `product_events` (0067) and the Wave 2
-- lifecycle logs (0088) set the rule: evidence must survive the later deletion
-- or correction of the business rows it describes.
--
-- **No derived BTGE quality metric is stored** -- no distribution score, rating
-- delta, out-of-position count/cost/imbalance, age delta/imbalance, repeat-pair
-- count, candidate count or timing. Every one of them can be recomputed from
-- the captured inputs, configuration and proposal.
--
-- JSON contents (validated by `save_generated_lineup_v1`):
--
--   player_inputs     [{user_id, overall_rating, age_at_match,
--                       primary_position, secondary_position}]
--                     -- no name, email, phone, avatar, date of birth or auth
--                        metadata; age is the engine's age at the match date.
--   history_context   {history_lookback, teammate_pairs}
--                     -- the played-lineup fetch bound and the exact teammate
--                        pair set priority 5 was given.
--   configuration     the exact BtgeConfiguration values used.
--   generated_lineup  [{user_id, team, assigned_position, assignment_basis}]
--                     -- account players only; Professional Guests never
--                        reach BTGE and never appear here.
create table public.btge_generation_runs (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  community_id uuid not null,
  generated_by uuid not null,
  generation_sequence bigint not null
    constraint btge_generation_runs_sequence_check
      check (generation_sequence >= 1),
  generated_at timestamptz not null default now(),
  variant_index integer not null
    constraint btge_generation_runs_variant_check
      check (variant_index >= 0),
  configuration jsonb not null
    constraint btge_generation_runs_configuration_check
      check (jsonb_typeof(configuration) = 'object'),
  player_inputs jsonb not null
    constraint btge_generation_runs_player_inputs_check
      check (jsonb_typeof(player_inputs) = 'array'),
  history_context jsonb not null
    constraint btge_generation_runs_history_context_check
      check (jsonb_typeof(history_context) = 'object'),
  generated_lineup jsonb not null
    constraint btge_generation_runs_generated_lineup_check
      check (jsonb_typeof(generated_lineup) = 'array'),
  constraint btge_generation_runs_match_sequence_key
    unique (match_id, generation_sequence)
);

create index btge_generation_runs_community_time_idx
  on public.btge_generation_runs (community_id, generated_at desc);

comment on table public.btge_generation_runs is
  'Wave 3 (migration 0089): one immutable row per successful BTGE generated '
  'lineup save, captured before any manual edit. Append-only evidence, not a '
  'lineup source. No foreign keys, no derived quality metric, no personal '
  'data beyond account ids. Written only by save_generated_lineup_v1.';

-- RLS on with no policy, and no client privilege: the `product_events` (0067)
-- and Wave 2 (0088) pattern. Supabase's default privileges grant ALL on a new
-- table to anon, authenticated and service_role before these statements run,
-- so they are taken back here rather than left unreachable.
alter table public.btge_generation_runs enable row level security;

revoke all on table public.btge_generation_runs
  from anon, authenticated, public;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.btge_generation_runs
  from anon, authenticated, public;

-- service_role keeps exactly what an internal analysis job needs: reading.
-- Nothing may update or delete evidence through an API role.
revoke all on table public.btge_generation_runs from service_role;
grant select on table public.btge_generation_runs to service_role;


-- ============================================================================
-- 2) save_generated_lineup_v1 -- lineup save + evidence, one transaction
-- ============================================================================
-- The generation-only write. It validates the evidence, then saves the
-- generated account lineup through the existing authoritative writer,
-- `replace_match_lineup(..., p_from_generation => true,
-- p_completed_correction => false)`, then appends the evidence row.
--
-- **One transaction.** A PostgREST RPC call is one statement in one
-- transaction, and any exception raised here -- by validation, by
-- `replace_match_lineup`, or by the evidence insert -- aborts all of it. A
-- failed lineup save leaves no evidence; a failed evidence insert leaves no
-- lineup change.
--
-- **The server decides the facts it owns.** `generated_by` is `auth.uid()`,
-- `community_id` comes from the match row, and `generation_sequence` is
-- assigned here under the match row lock that serialises generations of the
-- same match. A regeneration appends the next sequence and never overwrites.
--
-- Manual moves, swaps, position edits and completed-match corrections never
-- come here: they keep calling `replace_match_lineup` with
-- `p_from_generation => false`, so they create no generation run.
create or replace function public.save_generated_lineup_v1(
  p_match_id uuid,
  p_generated_lineup jsonb,
  p_variant_index integer,
  p_configuration jsonb,
  p_player_inputs jsonb,
  p_history_context jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_match public.matches%rowtype;
  v_uuid constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_positions constant text[] := array['GK', 'DEF', 'MID', 'FWD'];
  v_element jsonb;
  v_pair jsonb;
  v_keys text[];
  v_lineup_ids text[] := array[]::text[];
  v_input_ids text[] := array[]::text[];
  v_sequence bigint;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  -- The same lock `replace_match_lineup` takes, taken first so the sequence
  -- assigned below cannot race another generation of this match.
  select * into v_match
  from public.matches
  where id = p_match_id
  for update;
  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  if not exists (
    select 1 from public.communities c
    where c.id = v_match.community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  -- Owner/admin of the match community, through the same predicate
  -- `replace_match_lineup` asks (role-derived, 0018).
  if not public.is_match_community_admin(p_match_id, v_actor) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- The product's completion rule (0071): stored status or the clock. A
  -- generation is never a correction of a played match.
  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_COMPLETED';
  end if;

  -- --- Evidence shape ------------------------------------------------------
  if p_variant_index is null or p_variant_index < 0 then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  -- generated_lineup: account assignments only.
  if p_generated_lineup is null
     or jsonb_typeof(p_generated_lineup) <> 'array'
     or jsonb_array_length(p_generated_lineup) = 0
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  for v_element in select value from jsonb_array_elements(p_generated_lineup)
  loop
    if jsonb_typeof(v_element) <> 'object' then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    -- Professional Guests never reach BTGE, so a guest row is refused outright
    -- rather than captured as if the engine had placed it.
    if v_element ? 'professional_guest_id' then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    select array_agg(k order by k collate "C") into v_keys
    from jsonb_object_keys(v_element) as k;
    if v_keys is distinct from
       array['assigned_position', 'assignment_basis', 'team', 'user_id']
    then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    if jsonb_typeof(v_element->'user_id') <> 'string'
       or (v_element->>'user_id') !~ v_uuid
       or jsonb_typeof(v_element->'team') <> 'string'
       or (v_element->>'team') not in ('A', 'B')
       or jsonb_typeof(v_element->'assigned_position') <> 'string'
       or not ((v_element->>'assigned_position') = any (v_positions))
       or jsonb_typeof(v_element->'assignment_basis') <> 'string'
       or (v_element->>'assignment_basis')
            not in ('PRIMARY', 'SECONDARY', 'TRANSITION')
    then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    -- An account, not a Professional Guest id smuggled into `user_id`: guests
    -- have no `users` row.
    if not exists (
      select 1 from public.users u
      where u.id = (v_element->>'user_id')::uuid
    ) then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    v_lineup_ids := v_lineup_ids || lower(v_element->>'user_id');
  end loop;

  -- player_inputs: the minimal engine input per account player, nothing more.
  if p_player_inputs is null
     or jsonb_typeof(p_player_inputs) <> 'array'
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  for v_element in select value from jsonb_array_elements(p_player_inputs)
  loop
    if jsonb_typeof(v_element) <> 'object' then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    -- Exactly these keys: a name, contact detail, avatar, date of birth or any
    -- other field is refused rather than stored.
    select array_agg(k order by k collate "C") into v_keys
    from jsonb_object_keys(v_element) as k;
    if v_keys is distinct from array[
      'age_at_match',
      'overall_rating',
      'primary_position',
      'secondary_position',
      'user_id'
    ] then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    if jsonb_typeof(v_element->'user_id') <> 'string'
       or (v_element->>'user_id') !~ v_uuid
       or jsonb_typeof(v_element->'overall_rating') <> 'number'
       or jsonb_typeof(v_element->'age_at_match') <> 'number'
       or (v_element->>'age_at_match')::numeric < 0
       or (v_element->>'age_at_match')::numeric
            <> trunc((v_element->>'age_at_match')::numeric)
       or jsonb_typeof(v_element->'primary_position') <> 'string'
       or not ((v_element->>'primary_position') = any (v_positions))
       or not (
         jsonb_typeof(v_element->'secondary_position') = 'null'
         or (
           jsonb_typeof(v_element->'secondary_position') = 'string'
           and (v_element->>'secondary_position') = any (v_positions)
         )
       )
    then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;

    v_input_ids := v_input_ids || lower(v_element->>'user_id');
  end loop;

  -- Same players on both sides, each exactly once: the proposal places every
  -- input and nobody else.
  if cardinality(v_lineup_ids) <> cardinality(v_input_ids)
     or cardinality(v_lineup_ids)
          <> (select count(distinct x) from unnest(v_lineup_ids) as x)
     or cardinality(v_input_ids)
          <> (select count(distinct x) from unnest(v_input_ids) as x)
     or not (v_lineup_ids @> v_input_ids and v_input_ids @> v_lineup_ids)
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  -- configuration: exactly the BtgeConfiguration fields.
  if p_configuration is null
     or jsonb_typeof(p_configuration) <> 'object'
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;
  select array_agg(k order by k collate "C") into v_keys
  from jsonb_object_keys(p_configuration) as k;
  if v_keys is distinct from array[
    'age_band',
    'assign_emergency_goalkeeper',
    'distribution_band',
    'diversity_last_n_matches',
    'diversity_within_seconds',
    'min_players',
    'odd_count_rule',
    'out_of_position_band',
    'rating_band',
    'transition_cost_by_distance'
  ] then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  -- history_context: the fetch bound and the priority-5 pair set, nothing
  -- else -- no names, no derived repeat count.
  if p_history_context is null
     or jsonb_typeof(p_history_context) <> 'object'
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;
  select array_agg(k order by k collate "C") into v_keys
  from jsonb_object_keys(p_history_context) as k;
  if v_keys is distinct from array['history_lookback', 'teammate_pairs']
     or jsonb_typeof(p_history_context->'history_lookback')
          not in ('null', 'number')
     or jsonb_typeof(p_history_context->'teammate_pairs') <> 'array'
  then
    raise exception 'INVALID_GENERATION_EVIDENCE';
  end if;

  for v_pair in
    select value from jsonb_array_elements(p_history_context->'teammate_pairs')
  loop
    if jsonb_typeof(v_pair) <> 'array'
       or jsonb_array_length(v_pair) <> 2
       or jsonb_typeof(v_pair->0) <> 'string'
       or jsonb_typeof(v_pair->1) <> 'string'
       or (v_pair->>0) !~ v_uuid
       or (v_pair->>1) !~ v_uuid
    then
      raise exception 'INVALID_GENERATION_EVIDENCE';
    end if;
  end loop;

  -- --- The lineup, through the existing authoritative writer ---------------
  -- Unchanged semantics: guests keep their seats and re-alternate around the
  -- generated teams, ratings/effects are detached and reattached, and the
  -- Wave 2 revision trigger advances the lineup revision as for any save.
  perform public.replace_match_lineup(
    p_match_id,
    p_generated_lineup,
    true,
    false
  );

  -- --- The evidence --------------------------------------------------------
  select coalesce(max(r.generation_sequence), 0) + 1
  into v_sequence
  from public.btge_generation_runs r
  where r.match_id = p_match_id;

  insert into public.btge_generation_runs (
    match_id,
    community_id,
    generated_by,
    generation_sequence,
    variant_index,
    configuration,
    player_inputs,
    history_context,
    generated_lineup
  )
  values (
    p_match_id,
    v_match.community_id,
    v_actor,
    v_sequence,
    p_variant_index,
    p_configuration,
    p_player_inputs,
    p_history_context,
    p_generated_lineup
  );
end;
$$;

comment on function public.save_generated_lineup_v1(
  uuid, jsonb, integer, jsonb, jsonb, jsonb
) is
  'Wave 3 (migration 0089): saves a BTGE-generated account lineup through '
  'replace_match_lineup(p_from_generation => true, p_completed_correction => '
  'false) and appends one immutable btge_generation_runs row, in one '
  'transaction. Owner/admin only, active account, active community, never '
  'on a completed match. generated_by, community_id and generation_sequence '
  'are derived on the server. Raises INVALID_GENERATION_EVIDENCE for any '
  'evidence shape it does not accept, including Professional Guest rows.';

revoke execute on function public.save_generated_lineup_v1(
  uuid, jsonb, integer, jsonb, jsonb, jsonb
) from public, anon;
grant execute on function public.save_generated_lineup_v1(
  uuid, jsonb, integer, jsonb, jsonb, jsonb
) to authenticated, service_role;


-- ============================================================================
-- 3) product_events -- the constrained anonymous acquisition shape
-- ============================================================================
-- Still the one analytics table. Three additive changes:
--
--   * `acquisition_id` -- a server-generated random id joining one anonymous
--     public-link open to one later signup completion. Not a device id, not a
--     cookie: the client holds it in memory only.
--   * `user_id` may be null -- but only for the anonymous open shape below.
--   * `public_link_signup_completed` -- the twelfth event name, written only by
--     `record_public_link_signup_completed`.
--
-- Every historical row stays valid unchanged: all carry a user_id and no
-- acquisition_id.
alter table public.product_events
  add column if not exists acquisition_id uuid;

alter table public.product_events
  alter column user_id drop not null;

alter table public.product_events
  drop constraint product_events_event_name_check;
alter table public.product_events
  add constraint product_events_event_name_check
    check (event_name in (
      'session_started',
      'community_viewed',
      'community_created',
      'community_joined',
      'match_viewed',
      'match_registered',
      'match_withdrawn',
      'teams_viewed',
      'result_viewed',
      'share_used',
      'public_link_opened',
      'public_link_signup_completed'
    ));

-- (1) A row without an actor is legal only as the anonymous public-link open.
-- `source is not null` is spelled out because a CHECK passes on NULL: without
-- it, `source in (...)` would be unknown for a null source and admit the row.
alter table public.product_events
  add constraint product_events_anonymous_shape_check
    check (
      user_id is not null
      or (
        event_name = 'public_link_opened'
        and acquisition_id is not null
        and source is not null
        and source in (
          'public_link_player',
          'public_link_community',
          'public_link_match'
        )
      )
    );

-- (2) A signup completion is always an account's, and always joins an open.
alter table public.product_events
  add constraint product_events_signup_completed_shape_check
    check (
      event_name <> 'public_link_signup_completed'
      or (user_id is not null and acquisition_id is not null)
    );

-- (3) acquisition_id belongs to exactly those two shapes.
alter table public.product_events
  add constraint product_events_acquisition_scope_check
    check (
      acquisition_id is null
      or (event_name = 'public_link_opened' and user_id is null)
      or event_name = 'public_link_signup_completed'
    );

-- Acquisition lookup: one anonymous open per acquisition id.
create unique index if not exists product_events_anonymous_open_acquisition_key
  on public.product_events (acquisition_id)
  where event_name = 'public_link_opened' and user_id is null;

-- Idempotent completion: at most one completion per acquisition id.
create unique index if not exists product_events_signup_completed_acquisition_key
  on public.product_events (acquisition_id)
  where event_name = 'public_link_signup_completed';

comment on column public.product_events.user_id is
  'Who acted, always taken from auth.uid() by a writer and never from an '
  'argument. No FK: the row must survive the account being deleted. Null only '
  'for the anonymous public_link_opened shape (migration 0089), which '
  'product_events_anonymous_shape_check enforces.';
comment on column public.product_events.acquisition_id is
  'Wave 3 (migration 0089): server-generated random id joining one anonymous '
  'public_link_opened to at most one public_link_signup_completed in the same '
  'running app session. Not a device, cookie or browser identifier; the client '
  'keeps it in memory only. Null on every other event.';

-- Unchanged posture, restated: RLS on, no policy, no client privilege.
alter table public.product_events enable row level security;
revoke all on public.product_events from anon, authenticated, public;


-- ============================================================================
-- 4) record_anonymous_public_link_open -- the one anonymous writer
-- ============================================================================
-- An intentional public API endpoint: callable by `anon`, and therefore owning
-- exactly one narrow insert shape.
--
--   * refuses any signed-in caller -- they keep `record_product_event`;
--   * accepts a link kind, a platform word and a version string, nothing else:
--     no user id, no target/community/match id, no contact detail, no IP, no
--     user agent, no device id, no metadata;
--   * stores the kind as a bounded source, never the target uuid;
--   * generates the acquisition id itself and returns only that;
--   * reads no row of any table.
--
-- `search_path` is empty and every relation is schema-qualified, so the
-- function cannot be redirected by an object in a writable schema.
create or replace function public.record_anonymous_public_link_open(
  p_kind text,
  p_platform text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text;
  v_acquisition_id uuid;
begin
  if auth.uid() is not null then
    raise exception 'ANONYMOUS_ONLY';
  end if;

  v_source := case p_kind
    when 'player' then 'public_link_player'
    when 'community' then 'public_link_community'
    when 'match' then 'public_link_match'
  end;
  if v_source is null then
    raise exception 'INVALID_PUBLIC_LINK_KIND';
  end if;

  if p_platform is not null and p_platform not in ('web', 'android') then
    raise exception 'INVALID_ANALYTICS_PLATFORM';
  end if;

  v_acquisition_id := gen_random_uuid();

  insert into public.product_events (
    user_id,
    event_name,
    acquisition_id,
    source,
    platform,
    app_version
  )
  values (
    null,
    'public_link_opened',
    v_acquisition_id,
    v_source,
    p_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 64), '')
  );

  return v_acquisition_id;
end;
$$;

comment on function public.record_anonymous_public_link_open(text, text, text) is
  'Wave 3 (migration 0089): records one anonymous public_link_opened for a '
  'signed-out reader and returns its server-generated acquisition_id. Accepts '
  'only the link kind (player/community/match), platform (web/android/null) '
  'and app version. Stores no target id and no personal or device data. '
  'Raises ANONYMOUS_ONLY, INVALID_PUBLIC_LINK_KIND or '
  'INVALID_ANALYTICS_PLATFORM; the client swallows all three.';

-- Functions are created with EXECUTE for PUBLIC, and Supabase's default
-- privileges add anon/authenticated/service_role: every one is stated here.
revoke execute on function
  public.record_anonymous_public_link_open(text, text, text)
  from public, authenticated;
grant execute on function
  public.record_anonymous_public_link_open(text, text, text)
  to anon, service_role;


-- ============================================================================
-- 5) record_public_link_signup_completed -- the conversion
-- ============================================================================
-- Called by the new account's client, in the same running session, with the
-- acquisition id its anonymous open returned.
--
--   * the actor is `auth.uid()`, never an argument;
--   * the acquisition must be an existing anonymous `public_link_opened`;
--   * the account must have been created at or after that open, so an older
--     account signing in cannot manufacture a signup conversion;
--   * source, platform and app version are copied from the open;
--   * one completion per acquisition id -- a repeat call is a no-op;
--   * the anonymous open row is read, never modified, and never returned.
create or replace function public.record_public_link_signup_completed(
  p_acquisition_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_open public.product_events%rowtype;
  v_account_created_at timestamptz;
begin
  if v_actor is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  if p_acquisition_id is null then
    raise exception 'INVALID_ACQUISITION';
  end if;

  select * into v_open
  from public.product_events pe
  where pe.acquisition_id = p_acquisition_id
    and pe.event_name = 'public_link_opened'
    and pe.user_id is null;
  if not found then
    raise exception 'INVALID_ACQUISITION';
  end if;

  select u.created_at into v_account_created_at
  from public.users u
  where u.id = v_actor;
  if v_account_created_at is null
     or v_account_created_at < v_open.created_at
  then
    raise exception 'ACQUISITION_NOT_ELIGIBLE';
  end if;

  insert into public.product_events (
    user_id,
    event_name,
    acquisition_id,
    source,
    platform,
    app_version
  )
  values (
    v_actor,
    'public_link_signup_completed',
    p_acquisition_id,
    v_open.source,
    v_open.platform,
    v_open.app_version
  )
  on conflict (acquisition_id)
    where event_name = 'public_link_signup_completed'
    do nothing;
end;
$$;

comment on function public.record_public_link_signup_completed(uuid) is
  'Wave 3 (migration 0089): records public_link_signup_completed for the '
  'authenticated, active account against an anonymous public_link_opened. '
  'The account must have been created at or after the open. Idempotent per '
  'acquisition id. Raises NOT_AUTHENTICATED, ACCOUNT_SUSPENDED, '
  'INVALID_ACQUISITION or ACQUISITION_NOT_ELIGIBLE; the client swallows all.';

revoke execute on function
  public.record_public_link_signup_completed(uuid)
  from public, anon;
grant execute on function
  public.record_public_link_signup_completed(uuid)
  to authenticated, service_role;
