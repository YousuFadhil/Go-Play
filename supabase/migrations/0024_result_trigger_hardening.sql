-- Holding the result triggers to the rules the project already keeps.
--
-- Two omissions in `0022`, both caught by the database linter and both against
-- a rule this schema states elsewhere rather than against anything new:
--
--   * `reject_rating_history_update` was the one function in `0022` without
--     `set search_path`. Every other function it added has one, and so does
--     every function the migrations before it added.
--
--   * neither of the two trigger functions was revoked. Migration `0005` set the
--     rule for `handle_new_user` and `0021` restates it: no role may reach a
--     trigger function through the API. PostgREST exposes anything callable in
--     `public`, and while calling a trigger function directly only earns an
--     error, the rule is that it should not be reachable to try.
--
-- Behaviour is unchanged: same bodies, same triggers, same effects. `0022` and
-- `0023` are left exactly as they were applied.

create or replace function public.reject_rating_history_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'RATING_HISTORY_IMMUTABLE';
end;
$$;

revoke execute on function public.reject_rating_history_update()
  from anon, authenticated, public;
revoke execute on function public.reverse_match_effects_before_delete()
  from anon, authenticated, public;
