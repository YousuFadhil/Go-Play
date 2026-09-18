-- == rollback/0082_rating_engine_0078_historical_rebase_rollback.sql ==
-- Puts the ratings and their audit back exactly as they stood before the
-- rebase, from the archive the rebase wrote.
--
-- **The archive is not dropped.** It is what this file restores from, and it
-- stays afterwards as the evidence that the rebase happened and was undone.
-- Retiring an archive is a separate, deliberate act.
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
-- **Rows whose operational row is gone are skipped, and counted.** A user or a
-- match deleted after the rebase cannot have history restored against it --
-- `rating_history` has foreign keys to both and the archive deliberately does
-- not. The function reports how many rows that was; the archive keeps them.
--
-- Run the whole file in one transaction.

create or replace function public.rollback_rating_rebase(
  p_rebase_version text default '0082_engine_0078'
)
returns table (
  restored_history_rows int,
  skipped_history_rows int,
  restored_user_rows int,
  removed_rebuilt_rows int
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
  v_removed int;
  v_max_entry bigint;
begin
  select * into v_run
  from rating_rebase_runs
  where rebase_version = p_rebase_version;
  if not found then
    raise exception 'REBASE_NOT_FOUND';
  end if;
  if v_run.completed_at is null then
    raise exception 'REBASE_NOT_COMPLETED';
  end if;
  if v_run.rolled_back_at is not null then
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

  -- 1) the rebuilt operational history goes
  delete from rating_history;
  get diagnostics v_removed = row_count;

  -- 2) the archived history comes back, oldest entry first -- which is what
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

  select count(*) into v_skipped
  from rating_history_archive a
  where a.rebase_version = p_rebase_version
    and (
      not exists (select 1 from users u where u.id = a.user_id)
      or not exists (select 1 from matches m where m.id = a.match_id)
    );

  -- 3) the identity sequence, so the next entry_no is not one already used
  select coalesce(max(entry_no), 0) into v_max_entry from rating_history;
  perform setval(
    pg_get_serial_sequence('public.rating_history', 'entry_no'),
    greatest(v_max_entry, 1),
    v_max_entry > 0
  );

  -- 4) the ratings
  update users u
     set overall_rating = a.overall_rating
    from user_rating_archive a
   where a.rebase_version = p_rebase_version
     and a.user_id = u.id;
  get diagnostics v_users = row_count;

  update rating_rebase_runs
     set rolled_back_at = now()
   where rebase_version = p_rebase_version;

  restored_history_rows := v_restored;
  skipped_history_rows := v_skipped;
  restored_user_rows := v_users;
  removed_rebuilt_rows := v_removed;
  return next;
end;
$$;

comment on function public.rollback_rating_rebase(text) is
  'Undoes a rating rebase from its own archive: the rebuilt operational '
  'history is removed, every archived row is restored with its original id and '
  'entry_no, the identity sequence is set past them, and every archived Global '
  'Rating is put back. The archive is kept. service_role only -- see the '
  'rollback for migration 0082.';

revoke execute on function public.rollback_rating_rebase(text)
  from anon, authenticated, public;
grant execute on function public.rollback_rating_rebase(text) to service_role;

select public.rollback_rating_rebase('0082_engine_0078');

-- The rebase's own objects are left in place: the archive is evidence, and the
-- marker row now says the rebase was made and undone. To remove the machinery
-- entirely -- only once the archive has been retired deliberately -- run:
--
--   drop function if exists public.rollback_rating_rebase(text);
--   drop function if exists public.rebase_ratings_to_0078(text);
--   drop table if exists public.user_rating_archive;
--   drop table if exists public.rating_history_archive;
--   drop table if exists public.rating_rebase_runs;
--   drop function if exists public.reject_rating_archive_update();
