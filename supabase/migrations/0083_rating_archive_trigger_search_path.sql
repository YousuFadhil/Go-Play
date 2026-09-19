-- ===== migrations/0083_rating_archive_trigger_search_path.sql =====
-- Security hardening for the archive-protection trigger functions introduced
-- by 0082. The functions only raise fixed exceptions, but pinning search_path
-- removes the mutable-search-path advisory without changing behavior.

alter function public.reject_rating_archive_update()
  set search_path = public;

alter function public.reject_rating_archive_delete()
  set search_path = public;
