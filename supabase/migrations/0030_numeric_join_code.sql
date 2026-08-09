-- The join code becomes a number.
--
-- Product Owner decision: a community's join code is a unique numeric code of
-- up to four digits. It replaces the twelve-character base32 token migration
-- `0012` introduced.
--
-- What that costs, stated rather than discovered later: `0012` widened the code
-- specifically because six characters were guessable, and this narrows it much
-- further — **9,000 codes**, over an endpoint an unauthenticated caller may
-- reach through `preview_community_invite`. At that size the code is not a
-- secret at all: the whole space can be walked in a few thousand requests, so
-- every community using `CODE_REQUIRED` should be assumed discoverable and
-- joinable by anyone who cares to try. It also caps the product at 9,000 live
-- communities, after which `generate_join_code` cannot find a free code and its
-- loop does not terminate.
--
-- What still holds is that knowing a code reveals only a community's name and
-- lets the caller join it; it does not authenticate anyone, grant a role, or
-- expose a roster, a match or a member. Communities that do not want to be
-- joinable by a guessed code use the `INVITE_ONLY` join policy of `0016`, which
-- ignores codes entirely.
--
-- Four digits with no leading zero, so a code is the same length however it is
-- written down, copied, or read out loud — a leading zero is exactly the
-- character a person drops when typing a number they were told.
--
-- BREAKING: every existing code stops working and is reissued. That is
-- unavoidable — the old codes contain letters, which the new constraint refuses.

-- 1) Generation ------------------------------------------------------------------
-- Retries on collision rather than assuming one will not happen — with only
-- 9,000 codes a collision is ordinary rather than remarkable, so the loop is the
-- working path and not an edge case.
--
-- The attempt count is bounded. An unbounded loop over a space this small spins
-- forever once every code is taken, holding a connection and taking the request
-- with it; raising says what actually happened instead.
create or replace function public.generate_join_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
  v_attempts int := 0;
begin
  loop
    v_code := (1000 + floor(random() * 9000)::int)::text;
    exit when not exists (select 1 from communities where join_code = v_code);

    v_attempts := v_attempts + 1;
    if v_attempts >= 10000 then
      raise exception 'JOIN_CODE_SPACE_EXHAUSTED';
    end if;
  end loop;
  return v_code;
end;
$$;

-- 2) The column ------------------------------------------------------------------
-- The default is re-pointed at the same function name, so nothing that inserts a
-- community changes. The constraint is dropped before the existing rows are
-- rewritten and added afterwards: the old values would fail it.
alter table public.communities
  alter column join_code set default public.generate_join_code();

alter table public.communities
  drop constraint if exists communities_join_code_length_check;
alter table public.communities
  drop constraint if exists communities_join_code_numeric_check;

update public.communities set join_code = public.generate_join_code();

alter table public.communities
  add constraint communities_join_code_numeric_check
  check (join_code ~ '^[0-9]{1,4}$');
