-- Authentication modernization: a player profile is no longer implied by an
-- account.
--
-- Until now every row in `auth.users` got a `public.users` row from the trigger
-- `handle_new_user`, whatever the sign-up carried: a blank phone, a blank name,
-- `MID` when no position was sent and a null date of birth. That was harmless
-- while email + password was the only way in, because the registration form
-- refuses to submit without all of them. It is not harmless for an account that
-- arrives some other way -- a Google account carries a name and an email and
-- nothing else, and would enter the product as a football player with a made-up
-- position and no age.
--
-- This migration makes the profile something a player provides, and gives the
-- application a way to tell "has not provided it yet" from "has been suspended":
--
--   1) `handle_new_user()`        -- creates the profile only when the sign-up
--                                    metadata is a complete, valid profile.
--   2) `get_my_account_state()`   -- the caller's own account state, three-way.
--   3) `complete_my_player_profile(...)` -- the one way a signed-in account with
--                                    no profile creates it.
--
-- ## WHAT IS NOT CHANGED, AND WHY THAT MATTERS
--
--   * **Email registration is unchanged.** The form sends full name, phone,
--     primary position and date of birth (and, optionally, a secondary
--     position) as Auth metadata, and the trigger still turns exactly that into
--     exactly the row it always did. Nothing about a *complete* sign-up differs.
--   * **Every existing account is untouched.** No row is read, written or
--     backfilled. Accounts whose profile is already there are `ACTIVE` or
--     `SUSPENDED` exactly as `is_current_user_active()` has always said.
--   * **`is_current_user_active()` is not modified.** It is wired into policies
--     and write guards (`0064`, `0065` and later) and stays a two-way, fail
--     closed predicate: no row and `is_active = false` both answer false. The
--     suspension model is not weakened -- an account with no profile has no
--     `is_active` to lift, and every write path that asks the predicate still
--     refuses it. The new function answers a *different* question, for the
--     screen that has to choose between three things, and gates nothing.
--
-- ## COMPATIBILITY WITH THE DEPLOYED CLIENT
--
-- Staging and production share one Supabase project, so this file is applied
-- while the previous client is still being served. That is safe: the previous
-- client only ever signs up with the full profile, so the trigger creates the
-- row for it as before, and it never calls either new function. The new client
-- needs this migration first -- it asks `get_my_account_state()` and would fail
-- closed without it.
--
-- Idempotent: `create or replace function` plus revoke/grant throughout.



-- ============================================================================
-- 1) handle_new_user(): create the profile only when it is a profile
-- ============================================================================
-- The rule is about the *metadata*, not the provider. Nothing here asks whether
-- the account came from Google or from a password: a sign-up either carried a
-- complete, valid profile or it did not, and a rule keyed to a provider name
-- would need editing for every provider added after it.
--
-- "Complete and valid" is what the registration form already guarantees, stated
-- again where it cannot be bypassed by calling the Auth API directly:
--
--   * `full_name`         not blank.
--   * `phone`             the stored form, `+968` and eight digits. Oman is the
--                         only market and the form composes exactly this.
--   * `primary_position`  one of GK, DEF, MID, FWD. Absent is no longer `MID`.
--   * `date_of_birth`     an ISO `YYYY-MM-DD` that is a real date, no earlier
--                         than the date picker's own floor (1900-01-01) and not
--                         after tomorrow. The one day of slack is time zones:
--                         the form validates against the device's date and the
--                         database against UTC, and a player in Oman is a day
--                         ahead for several hours of every day.
--   * `secondary_position`  optional; when present, one of the four and not the
--                         primary (`BTGE-SC-6`).
--
-- The name rule is "not blank" and not the two-character floor the profile
-- screen applies. The registration form has only ever asked for non-empty, and
-- "exactly as before" means a sign-up the form accepted is still a sign-up the
-- trigger accepts.
--
-- When any of it is missing or invalid the trigger writes nothing and returns.
-- It never raises: refusing here would fail the whole Auth sign-up, and for a
-- provider account that is the very step that must succeed for the player to
-- reach the profile screen. The row is then created later, by
-- `complete_my_player_profile`, from what the player types.
--
-- `overall_rating` is still absent from the insert. `OP-1` makes it
-- system-managed and the column default sets it; Auth metadata is
-- client-supplied.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_name text := btrim(coalesce(v_meta ->> 'full_name', ''));
  v_phone text := btrim(coalesce(v_meta ->> 'phone', ''));
  v_primary text := btrim(coalesce(v_meta ->> 'primary_position', ''));
  v_secondary text := nullif(btrim(coalesce(v_meta ->> 'secondary_position', '')), '');
  v_dob_text text := btrim(coalesce(v_meta ->> 'date_of_birth', ''));
  v_dob date;
begin
  if v_name = '' then
    return new;
  end if;
  if v_phone !~ '^\+968[0-9]{8}$' then
    return new;
  end if;
  if v_primary not in ('GK', 'DEF', 'MID', 'FWD') then
    return new;
  end if;
  if v_secondary is not null
     and (v_secondary not in ('GK', 'DEF', 'MID', 'FWD')
          or v_secondary = v_primary) then
    return new;
  end if;

  -- Strict ISO only, so the cast cannot depend on DateStyle and cannot accept
  -- `infinity` or `today`. A well-formed string can still be an impossible date
  -- (2020-02-30), which the cast raises on; that is caught rather than allowed
  -- to fail the sign-up.
  if v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    return new;
  end if;
  begin
    v_dob := v_dob_text::date;
  exception when others then
    return new;
  end;
  if v_dob < date '1900-01-01' or v_dob > current_date + 1 then
    return new;
  end if;

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
    v_phone,
    v_name,
    v_primary,
    v_dob,
    v_secondary
  );
  return new;
end;
$$;

-- Migration `0005` revoked this and `0021` restated it. `create or replace`
-- keeps a function's privileges, so this changes nothing -- it is here because
-- the rule is that no role may reach a trigger function through the API, and a
-- reader of this file should not have to check another one to know it holds.
revoke execute on function public.handle_new_user()
  from anon, authenticated, public;



-- ============================================================================
-- 2) get_my_account_state(): what the signed-in account is, in three answers
-- ============================================================================
-- `is_current_user_active()` says false for two different accounts: one that
-- has been suspended and one that has no player profile. The screen has to treat
-- those differently -- the first is shown a suspension notice, the second is
-- asked for the profile it has not given yet -- so it needs a question with
-- three answers:
--
--   ACTIVE            a `public.users` row exists and `is_active` is true.
--   SUSPENDED         a row exists and `is_active` is false.
--   PROFILE_REQUIRED  no row exists.
--
-- Answering about the caller only, and taking no argument, means it cannot be
-- pointed at anybody else and is not an oracle about other accounts -- the same
-- shape as `is_current_user_active()` (`0062`) and `my_profile()` (`0055`).
--
-- **It grants nothing.** No policy and no function calls it. `ACTIVE` does not
-- authorise any write; every write path still asks `is_current_user_active()`
-- or its own guard, so the worst a wrong answer here could do is show the wrong
-- screen.
--
-- No session raises `NOT_AUTHENTICATED`, like every other guarded read, rather
-- than answering. The application treats an error as "state unknown" and fails
-- closed, which is exactly right for a question it should never be asking
-- without a session.
--
-- `security definer` for the same reason `is_current_user_active()` is: the
-- caller's own row is invisible to them once `is_active` is false (the
-- `authenticated_select_active_users` policy), and a suspended account is
-- precisely the one that has to be able to hear that it is suspended.
create or replace function public.get_my_account_state()
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_active boolean;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select u.is_active
    into v_active
    from users u
   where u.id = auth.uid();

  if not found then
    return 'PROFILE_REQUIRED';
  end if;

  return case when v_active then 'ACTIVE' else 'SUSPENDED' end;
end;
$$;

comment on function public.get_my_account_state() is
  'The signed-in caller''s account state: ACTIVE, SUSPENDED or '
  'PROFILE_REQUIRED (no public.users row). Takes no argument, so it cannot be '
  'asked about anybody else; grants nothing. Migration 0092.';

revoke execute on function public.get_my_account_state() from anon, public;
grant execute on function public.get_my_account_state() to authenticated;



-- ============================================================================
-- 3) complete_my_player_profile(): the one way to a profile after sign-up
-- ============================================================================
-- For an account that exists and has no player profile. It creates that profile
-- from what the player entered, under the same rules registration holds.
--
-- What it can and cannot be made to do is fixed by its signature. There is no
-- user id parameter, so it can only act for `auth.uid()`. There is no rating,
-- role, active/suspended or visibility parameter, so none of them can be set
-- from a request: `overall_rating` takes its column default (5.0, `OP-1`),
-- `is_active` its default (true), and the privacy preferences theirs.
--
-- **It refuses a second profile.** The insert is `on conflict do nothing` and
-- the outcome is read from `found`, so two concurrent calls cannot both win and
-- neither can overwrite an existing row -- this is a creation path, not an edit
-- path. Editing a profile stays with the profile screen and its column grants.
-- A *suspended* player has a row, so they get `PROFILE_ALREADY_EXISTS` here
-- too; the function cannot be used to walk around a suspension.
--
-- `security definer`, because `public.users` has no insert policy and no client
-- privilege to insert (`0001`): the trigger has been its only writer. This
-- function is the second, and is as narrow as the first.
--
-- Outcomes raised, all tokens the application already maps or maps here:
--   NOT_AUTHENTICATED       no session.
--   PROFILE_ALREADY_EXISTS  a row exists for the caller, active or not.
--   INVALID_FULL_NAME       fewer than two characters once trimmed -- the same
--                           floor the profile screen applies to a name.
--   INVALID_PHONE           not `+968` and eight digits.
--   INVALID_DATE_OF_BIRTH   absent, impossible, before 1900-01-01 or after
--                           tomorrow (see section 1 for the day of slack).
--   INVALID_POSITION        primary not one of the four; secondary present and
--                           not one of the four, or equal to the primary.
create or replace function public.complete_my_player_profile(
  p_full_name text,
  p_phone text,
  p_date_of_birth date,
  p_primary_position text,
  p_secondary_position text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_full_name, ''));
  v_phone text := btrim(coalesce(p_phone, ''));
  v_primary text := btrim(coalesce(p_primary_position, ''));
  v_secondary text := nullif(btrim(coalesce(p_secondary_position, '')), '');
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Cheap and precise, and asked before validation so a caller who already has a
  -- profile hears that, not a complaint about a field they were not editing.
  if exists (select 1 from users u where u.id = v_uid) then
    raise exception 'PROFILE_ALREADY_EXISTS';
  end if;

  if char_length(v_name) < 2 then
    raise exception 'INVALID_FULL_NAME';
  end if;
  if v_phone !~ '^\+968[0-9]{8}$' then
    raise exception 'INVALID_PHONE';
  end if;
  if p_date_of_birth is null
     or p_date_of_birth < date '1900-01-01'
     or p_date_of_birth > current_date + 1 then
    raise exception 'INVALID_DATE_OF_BIRTH';
  end if;
  if v_primary not in ('GK', 'DEF', 'MID', 'FWD') then
    raise exception 'INVALID_POSITION';
  end if;
  if v_secondary is not null
     and (v_secondary not in ('GK', 'DEF', 'MID', 'FWD')
          or v_secondary = v_primary) then
    raise exception 'INVALID_POSITION';
  end if;

  insert into users (
    id,
    phone,
    full_name,
    primary_position,
    date_of_birth,
    secondary_position
  )
  values (
    v_uid,
    v_phone,
    v_name,
    v_primary,
    p_date_of_birth,
    v_secondary
  )
  on conflict (id) do nothing;

  -- The exists check above and this insert are two statements; a concurrent
  -- call that got in between has already created the row, and this one must say
  -- so rather than pretend it did.
  if not found then
    raise exception 'PROFILE_ALREADY_EXISTS';
  end if;
end;
$$;

comment on function public.complete_my_player_profile(text, text, date, text, text) is
  'Creates the signed-in caller''s player profile when none exists. Acts only '
  'for auth.uid(); accepts no rating, role, active state or user id; refuses a '
  'second profile. Migration 0092.';

revoke execute on function public.complete_my_player_profile(text, text, date, text, text)
  from anon, public;
grant execute on function public.complete_my_player_profile(text, text, date, text, text)
  to authenticated;
