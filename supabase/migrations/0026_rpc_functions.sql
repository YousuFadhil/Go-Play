-- Sprint DB-02: Core RPC Functions
--
-- This migration adds ONE function: `create_match`.
--
-- The other four operations in the DB-02 brief are already implemented and
-- approved, and this migration deliberately does not touch them:
--
--   create_community(p_name, p_description, p_join_policy) -> uuid   0012
--   join_community(p_community_id) -> uuid                           0016
--   register_for_match(p_match_id) -> text                           0004, 0006
--   withdraw_from_match(p_match_id) -> void                          0004, 0006
--     (this is the brief's `cancel_registration`, under the name the
--      approved schema and the Flutter adapter already use)
--
-- Re-issuing any of them here would duplicate approved business logic --
-- which the brief itself forbids -- and `create or replace function` would
-- silently overwrite tested behaviour. See the sprint report for the two
-- specific regressions that would follow.
--
-- Match creation is the one operation with no RPC. Today the client INSERTs
-- into `matches` directly (supabase_match_adapter.dart:63), relying on the
-- `matches_insert_community_admins` policy for authorization and on the
-- `matches_set_capacity` trigger to derive `max_registration`. That works,
-- but it leaves match creation as the only write in the product whose guards
-- live in the client rather than beside its siblings: `update_match` and
-- `delete_match` are both RPCs, and both validate before they write.
--
-- What this function does NOT do, because something else already does it:
--
--   max_registration   the `matches_set_capacity` trigger derives it from
--                      starting_players + app_settings.reserve_players. This
--                      function must not compute it -- two derivations of one
--                      value are free to disagree.
--   status             the column default is 'open', which is the correct
--                      state for a match with no registrations. There is no
--                      roster to recompute at creation.
--   notifications      excluded by the brief, and consistent with today:
--                      the direct-insert path sends none.
--   team generation, ratings, leaderboards   all excluded by the brief.

-- ============================================================================
-- create_match
-- ============================================================================
-- Creates a match in a community the caller administers, and returns its id.
--
-- Returning `uuid` follows `create_community` and `join_community`, which both
-- return the id of the row they created. The caller needs it to navigate to
-- the new match without a second read.
--
-- AUTHORIZATION mirrors `matches_insert_community_admins` exactly -- owner or
-- admin, and `created_by` is taken from `auth.uid()` rather than accepted as a
-- parameter. `security definer` runs past RLS, so the policy's condition is
-- restated here as a guard; this is the pattern every other RPC in this schema
-- uses, and the reason `has_community_role` exists as a shared predicate
-- rather than as inline SQL.
--
-- VALIDATION reproduces `update_match`'s guards and its error vocabulary, so
-- that creating and editing a match fail the same way on the same input. The
-- table's CHECK constraints are the backstop, not the message: a constraint
-- violation reaches Flutter as a Postgres error code, and the app's failure
-- mapper reads these names.
--
-- One guard has no counterpart in `update_match`: START_IN_PAST. It is not a
-- new rule but the consequence of an existing one -- `update_match` refuses
-- any match whose `start_at <= now()` (MATCH_LOCKED), so a match created in
-- that state could never be edited or cancelled by its organizer. The insert
-- path permits it today; this function does not.
--
-- CONCURRENCY: none is needed, and none is faked. Creation allocates nothing
-- shared -- no seat, no queue position, no counter -- so there is no row whose
-- read-then-write another session could interleave with. That is the whole
-- difference from `register_for_match`, which locks the match row precisely
-- because it reads a count and then writes against it. The foreign key to
-- `communities` already takes a row-share lock as part of enforcing itself,
-- which is what keeps a concurrently deleted community from being referenced.
-- Adding `for update` here would lock a row this function never modifies.
--
-- The function body is one statement inside the caller's transaction. A
-- plpgsql function is atomic by construction: any exception raised below
-- aborts the insert with it, and no partial match can be left behind.
create or replace function public.create_match(
  p_community_id uuid,
  p_title text,
  p_location text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_starting_players int,
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

  return v_match_id;
end;
$$;

comment on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, int, text
) is
  'Creates a match in a community the caller owns or administers and returns '
  'its id. Guards and error names mirror update_match; max_registration is '
  'left to the matches_set_capacity trigger.';

-- `anon` may not create a match, and `public` is revoked so the grant is
-- explicit rather than inherited -- the same shape every other RPC here uses.
revoke execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, int, text
) from anon, public;

grant execute on function public.create_match(
  uuid, text, text, timestamptz, timestamptz, int, text
) to authenticated;
