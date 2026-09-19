-- == rollback/0082_rating_engine_0078_historical_rebase_rollback.sql ==
-- Puts the ratings and their audit back exactly as they stood before the
-- rebase, from the archive the rebase wrote.
--
-- **The archive is not dropped.** It is what this file restores from, and it
-- stays afterwards as the evidence that the rebase happened and was undone.
-- Retiring an archive is a separate, deliberate act -- and since `0082` the
-- archive refuses deletion as well as update, so retiring one means dropping
-- its guard first. See the foot of this file.
--
-- What is restored:
--
--   * every archived `rating_history` row, with its original `id`, `entry_no`,
--     `reverses_id`, deltas, ratings and `created_at`;
--   * the identity sequence behind `entry_no`, so the next row written
--     continues where the restored history left off;
--   * every archived `users.overall_rating`.
--
-- What is not touched: results, goals, lineups, match status, counters, Team of
-- Period data. The rebase did not change them and neither does this.
--
-- ## IT RESTORES EVERYTHING, OR IT RESTORES NOTHING
--
-- A rollback that puts back most of the evidence is not a rollback; it is a
-- third state nobody asked for, and the worst time to discover it is after the
-- transaction has committed. So the restorable rows are counted **before**
-- anything is written, and a single unrestorable row raises
-- `REBASE_ROLLBACK_INCOMPLETE` and leaves the database as it was.
--
-- A row can be unrestorable for one reason only: the user or the match it
-- belongs to was deleted after the rebase. `rating_history` has foreign keys to
-- both and the archive deliberately does not, so that evidence survives -- but
-- it cannot be put back against a row that no longer exists.
--
-- `p_allow_partial => true` is the deliberate override, for the disaster
-- recovery where football has been deleted since and restoring what is left is
-- better than restoring nothing. It is never the default, it reports what it
-- could not restore, and **it does not set `rolled_back_at`**: the run is
-- marked `rolled_back_partial_at` instead, so no later reader can mistake a
-- partial restoration for a completed one -- and the rebase, which treats an
-- un-rolled-back completed run as final, stays refused until somebody looks.
--
-- Run the whole file in one transaction.

create or replace function public.rollback_rating_rebase(
  p_rebase_version text default '0082_engine_0078',
  p_allow_partial boolean default false
)
returns table (
  restored_history_rows int,
  skipped_history_rows int,
  restored_user_rows int,
  skipped_user_rows int,
  missing_users int,
  missing_matches int,
  removed_rebuilt_rows int,
  partial boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run rating_rebase_runs%rowtype;
  v_restored int;
  v_skipped int;
  v_users int;
  v_skipped_users int;
  v_missing_users int;
  v_missing_matches int;
  v_removed int;
  v_max_entry bigint;
  v_partial boolean;
begin
  -- The same evidence set the rebase locks, taken the same way and in the same
  -- alphabetical order: this rewrites the operational history and every rating,
  -- so a result being recorded against it half way through is the same hazard
  -- it is during the rebase. Readers are not blocked, and the wait is bounded --
  -- a refused lock aborts the transaction with nothing restored and nothing
  -- removed.
  set local lock_timeout = '15s';

  lock table
    public.match_goals,
    public.match_results,
    public.match_team_assignments,
    public.matches,
    public.rating_history,
    public.users
    in share row exclusive mode;

  select * into v_run
  from rating_rebase_runs
  where rebase_version = p_rebase_version;
  if not found then
    raise exception 'REBASE_NOT_FOUND';
  end if;
  if v_run.completed_at is null then
    raise exception 'REBASE_NOT_COMPLETED';
  end if;
  if v_run.rolled_back_at is not null
     or v_run.rolled_back_partial_at is not null then
    raise exception 'REBASE_ALREADY_ROLLED_BACK';
  end if;
  if not exists (
    select 1 from rating_history_archive a
    where a.rebase_version = p_rebase_version
  ) then
    -- Refusing rather than clearing: without the archive this would delete the
    -- rebuilt history and restore nothing at all.
    raise exception 'REBASE_ARCHIVE_MISSING';
  end if;

  -- 1) **Before anything is written:** can every archived row go back?
  select
    count(*) filter (
      where not exists (select 1 from users u where u.id = a.user_id)
         or not exists (select 1 from matches m where m.id = a.match_id)
    ),
    count(distinct a.user_id) filter (
      where not exists (select 1 from users u where u.id = a.user_id)
    ),
    count(distinct a.match_id) filter (
      where not exists (select 1 from matches m where m.id = a.match_id)
    )
    into v_skipped, v_missing_users, v_missing_matches
  from rating_history_archive a
  where a.rebase_version = p_rebase_version;

  select count(*) into v_skipped_users
  from user_rating_archive a
  where a.rebase_version = p_rebase_version
    and not exists (select 1 from users u where u.id = a.user_id);

  v_partial := (v_skipped > 0 or v_skipped_users > 0);

  if v_partial and not p_allow_partial then
    -- Nothing has been written yet; raising here leaves the rebased state
    -- intact rather than half of each.
    raise exception 'REBASE_ROLLBACK_INCOMPLETE'
      using detail = format(
        '%s archived history row(s) and %s archived rating(s) cannot be '
        'restored: %s user(s) and %s match(es) no longer exist. Pass '
        'p_allow_partial => true to restore what is left.',
        v_skipped, v_skipped_users, v_missing_users, v_missing_matches),
        hint = 'The archive is kept either way; nothing was changed.';
  end if;

  -- 2) the rebuilt operational history goes
  delete from rating_history;
  get diagnostics v_removed = row_count;

  -- 3) the archived history comes back, oldest entry first -- which is what
  -- makes a reversal's `reverses_id` target already present when it lands.
  insert into rating_history (
    id, entry_no, user_id, match_id, change_reason,
    delta, rating_before, rating_after, reverses_id, created_at
  )
  overriding system value
  select
    a.id, a.entry_no, a.user_id, a.match_id, a.change_reason,
    a.delta, a.rating_before, a.rating_after, a.reverses_id, a.created_at
  from rating_history_archive a
  where a.rebase_version = p_rebase_version
    and exists (select 1 from users u where u.id = a.user_id)
    and exists (select 1 from matches m where m.id = a.match_id)
  order by a.entry_no;
  get diagnostics v_restored = row_count;

  -- 4) the identity sequence, so the next entry_no is not one already used
  select coalesce(max(entry_no), 0) into v_max_entry from rating_history;
  perform setval(
    pg_get_serial_sequence('public.rating_history', 'entry_no'),
    greatest(v_max_entry, 1),
    v_max_entry > 0
  );

  -- 5) the ratings
  update users u
     set overall_rating = a.overall_rating
    from user_rating_archive a
   where a.rebase_version = p_rebase_version
     and a.user_id = u.id;
  get diagnostics v_users = row_count;

  -- 6) the marker, and only `rolled_back_at` when it really was rolled back
  if v_partial then
    update rating_rebase_runs
       set rolled_back_partial_at = now(),
           rollback_skipped_rows = v_skipped + v_skipped_users
     where rebase_version = p_rebase_version;
  else
    update rating_rebase_runs
       set rolled_back_at = now(),
           rollback_skipped_rows = 0
     where rebase_version = p_rebase_version;
  end if;

  restored_history_rows := v_restored;
  skipped_history_rows := v_skipped;
  restored_user_rows := v_users;
  skipped_user_rows := v_skipped_users;
  missing_users := v_missing_users;
  missing_matches := v_missing_matches;
  removed_rebuilt_rows := v_removed;
  partial := v_partial;
  return next;
end;
$$;

comment on function public.rollback_rating_rebase(text, boolean) is
  'Undoes a rating rebase from its own archive: the rebuilt operational '
  'history is removed, every archived row is restored with its original id and '
  'entry_no, the identity sequence is set past them, and every archived Global '
  'Rating is put back. Refuses with REBASE_ROLLBACK_INCOMPLETE, before writing '
  'anything, unless every archived row can be restored; p_allow_partial is the '
  'deliberate disaster-recovery override and records rolled_back_partial_at '
  'instead of rolled_back_at. The archive is kept. service_role only -- see '
  'the rollback for migration 0082.';

revoke execute on function public.rollback_rating_rebase(text, boolean)
  from anon, authenticated, public;
grant execute on function public.rollback_rating_rebase(text, boolean)
  to service_role;

select public.rollback_rating_rebase('0082_engine_0078');

-- The rebase's own objects are left in place: the archive is evidence, and the
-- marker row now says the rebase was made and undone. To remove the machinery
-- entirely -- only once the archive has been retired deliberately, which is
-- what dropping its guards below means -- run:
--
--   drop function if exists public.rollback_rating_rebase(text, boolean);
--   drop function if exists public.rebase_ratings_to_0078(text);
--   drop trigger if exists rating_history_archive_undeletable
--     on public.rating_history_archive;
--   drop trigger if exists user_rating_archive_undeletable
--     on public.user_rating_archive;
--   drop table if exists public.user_rating_archive;
--   drop table if exists public.rating_history_archive;
--   drop table if exists public.rating_rebase_runs;
--   drop function if exists public.reject_rating_archive_delete();
--   drop function if exists public.reject_rating_archive_update();
