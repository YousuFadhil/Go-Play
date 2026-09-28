-- == rollback/0092_auth_modernization_rollback.sql ==
-- Puts sign-up back to what it was before `0092`: `handle_new_user()` creates a
-- `public.users` row for every new account, from whatever the sign-up carried,
-- and the two functions `0092` added are gone.
--
-- **Nothing historical is edited.** `0021` stays exactly as it was written; this
-- file restates its function body through `create or replace`, which is the only
-- way a forward-only migration history can be undone.
--
-- ## WHAT THIS DOES NOT UNDO
--
-- No row is created, changed or deleted here. Any account that signed up while
-- `0092` was live and has no profile row keeps having none -- the old trigger
-- only acts on *new* accounts. Under the previous client such an account reads
-- as "not active" and is shown the suspension screen, which is wrong for it.
-- Before rolling back, look for them:
--
--     select id, email from auth.users u
--      where not exists (select 1 from public.users p where p.id = u.id);
--
-- and either have their owners complete a profile first or decide what to do
-- with them. That is a product decision, not something a rollback script takes.
--
-- Roll the client back first (or with this): the current client asks
-- `get_my_account_state()`, which this file removes, and fails closed without it.

-- The trigger body as `0021` left it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (
    id,
    phone,
    full_name,
    primary_position,
    date_of_birth,
    secondary_position
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'primary_position', 'MID'),
    nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
    nullif(new.raw_user_meta_data ->> 'secondary_position', '')
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user()
  from anon, authenticated, public;

drop function if exists public.complete_my_player_profile(text, text, date, text, text);
drop function if exists public.get_my_account_state();
