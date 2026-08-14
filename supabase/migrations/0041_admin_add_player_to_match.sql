-- Owner/admin adds a community member to a match.
--
-- The product change is small: a player can now be put into a match by someone
-- who runs the community, instead of only by themselves. The engineering care
-- is entirely about *not* letting that become a second registration path with
-- its own drifting copy of the rules.
--
-- So this migration does three things and nothing else:
--
--   1. `register_player_in_match` — the existing registration transaction,
--      moved out of `register_for_match` verbatim, with one substitution: the
--      player being registered is a parameter rather than `auth.uid()`.
--   2. `register_for_match` — now two lines. Same signature, same return, same
--      errors in the same order, because the body it used to hold is the body
--      the helper now holds.
--   3. `admin_add_player_to_match` — authorizes the *actor*, then calls the
--      helper with the *target*.
--
-- **Actor and target are different things, and the split is the point.**
--
--   actor  = auth.uid(), never a parameter, never client-supplied
--   target = p_user_id, and only ever a registration subject
--
-- The helper knows only about a target. It performs no authorization at all,
-- which is exactly why it is not reachable by `authenticated`: it is the shared
-- *middle* of two flows whose ends differ, and the ends are where permission is
-- decided. `register_for_match` decides "you may register yourself";
-- `admin_add_player_to_match` decides "you run this community". Neither
-- decision belongs in the shared part, and putting one there would silently
-- give it to the other caller.
--
-- Nothing about registration semantics changes. Capacity, reserve, ordering,
-- overlap, lifecycle, membership and the duplicate rule are the same statements
-- in the same order — read from the live definition of `register_for_match`
-- before this was written, and reproduced below.
--
-- No notification is raised for an added player. That is a deliberate Cycle 1
-- decision, so `notification_types`, the producers and `push-dispatch` are all
-- untouched.

-- 1) The shared registration transaction ---------------------------------------
-- Every line below is `register_for_match`'s, in its original order, with
-- `auth.uid()` replaced by `p_user_id` in the four places where it meant *the
-- player being registered*:
--
--   * the row lock on `users`
--   * the community-membership check
--   * the duplicate check
--   * the overlap check
--   * the insert
--
-- The one place it meant *the caller* — the `NOT_AUTHENTICATED` guard — is not
-- here. It stayed with the callers, because a helper that asked about the
-- session would be asking about the actor, and this function has no opinion
-- about actors.
--
-- **The duplicate check has no status filter**, so a `reserve` row blocks a
-- second registration exactly as a `confirmed` one does. `UNIQUE (match_id,
-- user_id)` remains the final safeguard underneath it.
create or replace function public.register_player_in_match(
  p_match_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
  v_total int;
  v_confirmed int;
  v_status text;
  v_order int;
begin
  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  perform 1 from users where id = p_user_id for update;

  if v_match.status = 'completed' or v_match.end_at <= now() then
    raise exception 'MATCH_CLOSED';
  end if;
  if v_match.start_at <= now() then raise exception 'MATCH_LOCKED'; end if;

  if not is_community_member(v_match.community_id, p_user_id) then
    raise exception 'NOT_COMMUNITY_MEMBER';
  end if;

  if exists (select 1 from match_registrations
             where match_id = p_match_id and user_id = p_user_id) then
    raise exception 'ALREADY_REGISTERED';
  end if;

  select count(*) into v_total from match_registrations where match_id = p_match_id;
  if v_total >= v_match.max_registration then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  if exists (
    select 1 from match_registrations r
    join matches m on m.id = r.match_id
    where r.user_id = p_user_id
      and m.status in ('open', 'full')
      and m.end_at > now()
      and m.start_at < v_match.end_at
      and m.end_at > v_match.start_at
  ) then
    raise exception 'OVERLAPPING_MATCH';
  end if;

  select count(*) into v_confirmed from match_registrations
  where match_id = p_match_id and status = 'confirmed';

  v_status := case when v_confirmed < v_match.starting_players
                   then 'confirmed' else 'reserve' end;

  select coalesce(max(registration_order), 0) + 1 into v_order
  from match_registrations where match_id = p_match_id;

  insert into match_registrations (match_id, user_id, status, registration_order)
  values (p_match_id, p_user_id, v_status, v_order);

  perform recompute_match_status(p_match_id);
  return v_status;
end;
$$;

-- Internal. Not callable by a client under any role, because it registers
-- whoever it is told to and asks nobody's permission. Matches the privilege
-- shape of the other internal helpers (`rebalance_roster`, `recompute_match_
-- status`, `purge_match`): postgres and service_role only.
--
-- Its two callers are SECURITY DEFINER and owned by postgres, so they reach it
-- as the owner and need no grant of their own.
revoke execute on function public.register_player_in_match(uuid, uuid)
  from anon, authenticated, public;
grant execute on function public.register_player_in_match(uuid, uuid)
  to service_role;

-- 2) Self-registration ---------------------------------------------------------
-- Same signature, same return values, same exceptions in the same order. The
-- `NOT_AUTHENTICATED` guard stays here, ahead of everything, exactly where it
-- was; the rest of the body is now the helper's.
create or replace function public.register_for_match(p_match_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  return register_player_in_match(p_match_id, auth.uid());
end;
$$;

revoke execute on function public.register_for_match(uuid) from anon, public;
grant execute on function public.register_for_match(uuid) to authenticated;

-- 3) The admin operation -------------------------------------------------------
-- Authorizes the caller, then registers somebody else under the ordinary rules.
--
-- The match is read first because the community is what the role is checked
-- against, and only the match knows which community that is. That read is
-- deliberately unlocked: it decides permission, not outcome. The helper
-- immediately re-reads the same row `for update`, and every decision that
-- depends on the match's state — lifecycle, capacity, ordering — is taken there,
-- under the lock, exactly as it is for self-registration.
--
-- `has_community_role(..., 'admin')` is the existing gate, used the same way
-- `remove_player` and `update_match` use it, and it already admits owner
-- (rank 3) as well as admin (rank 2). No new role, no organizer special case:
-- `matches.created_by` is not consulted for permission anywhere in this schema
-- and is not consulted here.
--
-- What this function deliberately does **not** do is relax anything for the
-- player being added. An admin may add someone; an admin may not add someone to
-- a locked match, past capacity, twice, into a clash, or into a community they
-- do not belong to. All of that is the helper's, unchanged.
create or replace function public.admin_add_player_to_match(
  p_match_id uuid,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match matches%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_match from matches where id = p_match_id;
  if not found then raise exception 'MATCH_NOT_FOUND'; end if;

  if not has_community_role(v_match.community_id, auth.uid(), 'admin') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return register_player_in_match(p_match_id, p_user_id);
end;
$$;

revoke execute on function public.admin_add_player_to_match(uuid, uuid)
  from anon, public;
grant execute on function public.admin_add_player_to_match(uuid, uuid)
  to authenticated;
