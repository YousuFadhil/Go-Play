-- delete_community still deleted from the invitations table that 0012 dropped,
-- so every call raised "relation does not exist" and no community could be
-- deleted at all. Same function, one line shorter.
--
-- Found because the integration suite's teardown uses this RPC: communities
-- leaked between tests and later registrations tripped OVERLAPPING_MATCH. The
-- teardown swallows its own errors, which is why the symptom surfaced far from
-- the cause.

create or replace function public.delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;
  perform 1 from communities where id = p_community_id for update;
  -- Notifications first: match_id is ON DELETE SET NULL, so they would survive
  -- the matches and be orphaned rather than removed (DD-08).
  delete from notifications
  where match_id in (select id from matches where community_id = p_community_id);
  delete from match_registrations
  where match_id in (select id from matches where community_id = p_community_id);
  delete from matches where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;
