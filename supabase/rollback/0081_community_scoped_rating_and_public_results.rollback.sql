-- == rollback/0081_community_scoped_rating_and_public_results.rollback.sql ==
-- Undoes migration `0081` by removing the five read models it created.
--
-- **Non-destructive by construction.** `0081` created no table, wrote no row,
-- altered no column and changed no privilege on anything that existed before
-- it; every function in it derives its answer from evidence it only reads. So
-- undoing it is five `drop function` statements and nothing else, and no data
-- can be lost by running this.
--
-- What a front end built against `0081` loses if the database is rolled back:
-- the Community/Period Rating (Highest Rated has no figure to rank), the public
-- Latest Results lists, and the multi-card Recent Achievements. Each read fails
-- as an ordinary missing-function failure and is reported as one; nothing
-- silently falls back to the Global Rating or to an older award.
--
-- Run the whole file in one transaction.

drop function if exists public.public_player_recent_achievements(uuid, int);
drop function if exists public.player_recent_achievements(uuid, int);
drop function if exists public.public_community_recent_results(uuid, int);
drop function if exists public.public_recent_results(int);
drop function if exists public.community_scoped_rating(uuid, text, text);
