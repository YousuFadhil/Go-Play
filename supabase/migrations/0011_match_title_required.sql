-- Community-first simplification, part 1: every match has a name.
--
-- Rows with no title displayed their location, because Match.displayName fell
-- back to it. Copying the location into the title is therefore the backfill
-- that changes nothing a user can see. Approved as a one-off for existing rows;
-- new matches are never given a generated title, the organizer types one.

-- 1) Backfill ------------------------------------------------------------------
update public.matches
set title = left(trim(location), 60)
where title is null or trim(title) = '';

-- The title check requires at least two characters. Nothing in production has a
-- location that short, but an unusable location should not block the migration.
update public.matches
set title = 'Match'
where char_length(trim(title)) < 2;

-- 2) Require it from here on ---------------------------------------------------
alter table public.matches
  alter column title set not null;

alter table public.matches
  drop constraint if exists matches_title_check;
alter table public.matches
  add constraint matches_title_check
  check (char_length(trim(title)) between 2 and 60);

-- update_match still accepts a null title; with the column NOT NULL the update
-- would fail on the constraint. 0013 gives it a clear error code instead.
