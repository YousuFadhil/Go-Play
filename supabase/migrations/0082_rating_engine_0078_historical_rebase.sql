-- ======= migrations/0082_rating_engine_0078_historical_rebase.sql =======
-- The approved one-time rebase: every Global Rating rebuilt from the current
-- final match evidence under the engine in force, migration `0078`.
--
-- **This changes ratings, deliberately.** The Product Owner approved it on
-- 2026-09-18 (`DD-18`). The stored Global Ratings accumulated under three
-- successive rule sets and carry the reversal bookkeeping of every correction
-- ever made; after this migration every rating is what the current rules say
-- the recorded football produced, and nothing else.
--
-- ## WHAT IT DOES, IN ORDER
--
--   1. archives the whole operational `rating_history` as immutable evidence;
--   2. archives every `users.overall_rating` as it stands;
--   3. clears the operational `rating_history`;
--   4. resets every Global Rating to the 5.000 baseline;
--   5. replays every match that currently has a recorded result, oldest first,
--      through `apply_match_rating_effects` -- **the engine itself**, not a
--      copy of it;
--   6. records the run, so it can never be done twice.
--
-- ## WHAT IT DOES NOT TOUCH
--
-- Results, goals, lineups, match status, `player_statistics`,
-- `community_statistics`, Team of Period snapshots and every other counter are
-- read at most and never written. The rebase is about the rating and the audit
-- of the rating, and nothing else in the product moves.
--
-- ## WHY THE AUDIT IS REBUILT TOO
--
-- A correction reverses the *stored* deltas of the result it replaces
-- (`reverse_match_rating_effects`). Rewriting ratings while leaving the old
-- audit in place would leave the correction flow reversing pre-`0078` deltas
-- against post-rebase ratings -- which is the one way this migration could
-- corrupt the system. So the operational history is rebuilt with the ratings,
-- and the old one is kept out of the operational path, in an archive no client
-- can read.
--
-- ## HOW IT IS UNDONE
--
-- `supabase/rollback/0082_rating_engine_0078_historical_rebase_rollback.sql`
-- restores the archived history row for row -- ids, entry numbers, deltas and
-- `reverses_id` links -- and the archived rating of every user. The archive is
-- never dropped by a rollback; it is the evidence the rollback is made of.
--
-- Append-only. Nothing in `0022`-`0081` is edited.

-- ============================================================================
-- 1) The marker: which rebase ran, when, and over what
-- ============================================================================
-- One row per rebase. It is what makes the migration refuse to run twice, and
-- what a rollback reads to know which archived generation to restore.
create table if not exists public.rating_rebase_runs (
  id uuid primary key default gen_random_uuid(),
  -- The version string every archived row carries. Unique, so a second attempt
  -- at the same rebase cannot start.
  rebase_version text not null unique,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  rolled_back_at timestamptz,
  archived_history_rows int not null default 0,
  archived_user_rows int not null default 0,
  replayed_matches int not null default 0,
  rebuilt_history_rows int not null default 0
);

comment on table public.rating_rebase_runs is
  'One row per historical rating rebase: the marker that makes it one-time, '
  'and what a rollback reads. System evidence -- no client reads it.';

alter table public.rating_rebase_runs enable row level security;
revoke all on public.rating_rebase_runs from anon, authenticated, public;

-- ============================================================================
-- 2) The archives
-- ============================================================================
-- **No foreign keys, on purpose.** Archived evidence must survive the operational
-- row it describes: a user or a match deleted later cascades through
-- `rating_history`, and the whole point of this table is to still hold what
-- that rating history said. The ids are recorded as values, not as references.
create table if not exists public.rating_history_archive (
  archive_id bigint generated always as identity primary key,
  rebase_version text not null,
  archived_at timestamptz not null default now(),
  -- The original row, exactly as it stood.
  id uuid not null,
  entry_no bigint not null,
  user_id uuid not null,
  match_id uuid not null,
  change_reason text not null,
  delta numeric(5,3) not null,
  rating_before numeric(5,3) not null,
  rating_after numeric(5,3) not null,
  reverses_id uuid,
  created_at timestamptz not null
);

create unique index if not exists rating_history_archive_row_idx
  on public.rating_history_archive (rebase_version, id);
create index if not exists rating_history_archive_entry_idx
  on public.rating_history_archive (rebase_version, entry_no);

comment on table public.rating_history_archive is
  'The operational rating_history as it stood before a rebase, row for row and '
  'id for id. Immutable archival evidence and the source a rollback restores '
  'from; carries no foreign keys so that deleting an operational user or match '
  'cannot destroy it. No client reads it -- see migration 0082.';

alter table public.rating_history_archive enable row level security;
revoke all on public.rating_history_archive from anon, authenticated, public;

create table if not exists public.user_rating_archive (
  archive_id bigint generated always as identity primary key,
  rebase_version text not null,
  archived_at timestamptz not null default now(),
  user_id uuid not null,
  overall_rating numeric(5,3) not null
);

create unique index if not exists user_rating_archive_user_idx
  on public.user_rating_archive (rebase_version, user_id);

comment on table public.user_rating_archive is
  'Every user''s Global Rating as it stood before a rebase -- what a rollback '
  'restores. No foreign key, for the reason rating_history_archive has none.';

alter table public.user_rating_archive enable row level security;
revoke all on public.user_rating_archive from anon, authenticated, public;

-- Nothing may edit archived evidence. Deletion is left possible so that an
-- archive can be retired deliberately once a rebase is accepted; changing a
-- row in place is what must never happen.
create or replace function public.reject_rating_archive_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'RATING_ARCHIVE_IMMUTABLE';
end;
$$;

drop trigger if exists rating_history_archive_immutable
  on public.rating_history_archive;
create trigger rating_history_archive_immutable
  before update on public.rating_history_archive
  for each row
  execute function public.reject_rating_archive_update();

drop trigger if exists user_rating_archive_immutable
  on public.user_rating_archive;
create trigger user_rating_archive_immutable
  before update on public.user_rating_archive
  for each row
  execute function public.reject_rating_archive_update();

-- ============================================================================
-- 3) The rebase itself
-- ============================================================================
-- **It delegates; it does not re-implement.** Every rating movement below is
-- made by `apply_match_rating_effects`, which is `0078` -- the same function
-- `record_match_result` calls. There is no second set of constants here, no
-- second clamp and no second order: participation, outcome, goals, MVP, each
-- clamped by `apply_rating_delta`, exactly as a result recorded today.
--
-- What this function adds is only *which matches, in what order*: every match
-- that currently has a result, oldest first, `match_id` breaking a tie.
--
-- `service_role` only, and not a client API. It is called once, by this
-- migration, inside the migration's own transaction.
create or replace function public.rebase_ratings_to_0078(
  p_rebase_version text default '0082_engine_0078'
)
returns table (
  archived_history_rows int,
  archived_user_rows int,
  replayed_matches int,
  rebuilt_history_rows int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run uuid;
  v_match record;
  v_archived_history int;
  v_archived_users int;
  v_replayed int := 0;
  v_rebuilt int;
begin
  -- **One-time, provably.** A completed run under this version means the
  -- operational history is already the rebuilt one; archiving it again would
  -- record a rebased history as though it were the legacy evidence, and that
  -- is the one mistake this migration could make that no rollback could undo.
  if exists (
    select 1 from rating_rebase_runs r
    where r.rebase_version = p_rebase_version
      and r.completed_at is not null
      and r.rolled_back_at is null
  ) then
    raise exception 'REBASE_ALREADY_COMPLETED';
  end if;
  if exists (
    select 1 from rating_rebase_runs r
    where r.rebase_version = p_rebase_version
      and r.completed_at is null
  ) then
    raise exception 'REBASE_IN_PROGRESS';
  end if;
  if exists (
    select 1 from rating_history_archive a
    where a.rebase_version = p_rebase_version
  ) then
    raise exception 'REBASE_ARCHIVE_ALREADY_PRESENT';
  end if;

  insert into rating_rebase_runs (rebase_version)
  values (p_rebase_version)
  returning id into v_run;

  -- 1) the legacy audit, row for row
  insert into rating_history_archive (
    rebase_version, id, entry_no, user_id, match_id, change_reason,
    delta, rating_before, rating_after, reverses_id, created_at
  )
  select
    p_rebase_version, h.id, h.entry_no, h.user_id, h.match_id, h.change_reason,
    h.delta, h.rating_before, h.rating_after, h.reverses_id, h.created_at
  from rating_history h;
  get diagnostics v_archived_history = row_count;

  -- 2) the ratings themselves, so a rollback needs nothing else
  insert into user_rating_archive (rebase_version, user_id, overall_rating)
  select p_rebase_version, u.id, u.overall_rating
  from users u;
  get diagnostics v_archived_users = row_count;

  -- 3) the operational audit is cleared -- and only it. A `delete` rather than
  -- a truncate: the table is referenced by itself and truncating would take
  -- the archive's source out from under a transaction that has not committed.
  delete from rating_history;

  -- 4) back to the approved baseline (`OP-1`). The rating is system-managed,
  -- so this is the only writer that ever sets it outside the engine.
  update users set overall_rating = 5.000;

  -- 5) the replay: every recorded result, once, oldest first.
  for v_match in
    select m.id
    from matches m
    join match_results r on r.match_id = m.id
    order by m.start_at, m.id
  loop
    perform apply_match_rating_effects(v_match.id);
    v_replayed := v_replayed + 1;
  end loop;

  select count(*) into v_rebuilt from rating_history;

  update rating_rebase_runs
     set completed_at = now(),
         archived_history_rows = v_archived_history,
         archived_user_rows = v_archived_users,
         replayed_matches = v_replayed,
         rebuilt_history_rows = v_rebuilt
   where id = v_run;

  archived_history_rows := v_archived_history;
  archived_user_rows := v_archived_users;
  replayed_matches := v_replayed;
  rebuilt_history_rows := v_rebuilt;
  return next;
end;
$$;

comment on function public.rebase_ratings_to_0078(text) is
  'The approved one-time rebase: archives the operational rating history and '
  'every Global Rating, clears the operational history, resets every rating to '
  '5.000 and replays every recorded result oldest first through '
  'apply_match_rating_effects -- migration 0078 itself, not a copy of it. '
  'Refuses to run twice. service_role only; no client may call it -- see '
  'migration 0082.';

revoke execute on function public.rebase_ratings_to_0078(text)
  from anon, authenticated, public;
grant execute on function public.rebase_ratings_to_0078(text) to service_role;

-- ============================================================================
-- 4) Run it
-- ============================================================================
-- Applying this migration performs the rebase, inside the migration's own
-- transaction: either every rating and every audit row is the rebuilt one, or
-- none of them is.
select public.rebase_ratings_to_0078('0082_engine_0078');
