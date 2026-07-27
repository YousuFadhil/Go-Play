-- Regenerating the join code is how a leaked invitation is invalidated.
--
-- The code is the only invitation identifier (DD-12), so there is nothing else
-- to revoke: issuing a new code retires the old one by replacing it. Membership,
-- matches and registrations are untouched — the code controls who may *join*,
-- not who already has.
--
-- One statement, so there is never a moment where the community has no code or
-- two. The row lock is for the read-then-write inside generate_join_code, which
-- checks the new value is unused before returning it.

create or replace function public.regenerate_join_code(p_community_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  -- Owner and admin both share invitations, so both can retire one.
  if not has_community_role(p_community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  perform 1 from communities where id = p_community_id for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;

  update communities
  set join_code = generate_join_code()
  where id = p_community_id
  returning join_code into v_code;

  return v_code;
end;
$$;

revoke execute on function public.regenerate_join_code(uuid) from anon, public;
grant execute on function public.regenerate_join_code(uuid) to authenticated;
