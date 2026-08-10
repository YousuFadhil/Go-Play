-- The profile a new account arrives with.
--
-- Registration now asks for the two Core Player Inputs (§4.1) the sign-up form
-- never collected: the date of birth the engine derives age from, and the
-- optional secondary position. Both travel the path the three existing fields
-- already take — Auth metadata read by this trigger — so the only change the
-- database needs is for the trigger to carry them across.
--
-- Nothing else moves. No column is added, altered or dropped: migration `0018`
-- created `date_of_birth`, `secondary_position` and `overall_rating` already,
-- and `date_of_birth` stays nullable because the accounts that predate this
-- have none. Inventing one for them is exactly what §4.3 forbids; they complete
-- their own profile through the application instead.
--
-- `overall_rating` is deliberately absent from the insert. `OP-1` makes it
-- system-managed at 5.0 and the column default is what sets it. Passing it
-- through Auth metadata would put a system-managed value in the hands of
-- whoever composes the sign-up request.

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
    -- Absent and empty both mean "not supplied", and neither may become a date
    -- the player never gave: the column is nullable for exactly this reason.
    nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
    nullif(new.raw_user_meta_data ->> 'secondary_position', '')
  );
  return new;
end;
$$;

-- Migration `0005` revoked this. `create or replace` keeps a function's
-- privileges, so restating it changes nothing — it is here because the rule is
-- that no role may reach a trigger function through the API, and a reader of
-- this file should not have to check another one to know it still holds.
revoke execute on function public.handle_new_user()
  from anon, authenticated, public;
