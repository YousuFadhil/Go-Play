-- ============================================================================
-- 0104 -- Leaving a community, and what ending a membership leaves behind
-- ============================================================================
-- Until now a membership could end in one way only: an owner or an admin
-- removed somebody (`remove_member`, 0009/0065). A member who had joined an
-- open community had no way out of it. This migration adds that way out and
-- corrects two things the existing ending got wrong.
--
-- ## 1. `leave_community` -- the member ends their own membership
--
-- Any member except the owner. A community always has exactly one owner, so the
-- owner leaves by transferring ownership first (`transfer_ownership`) or by
-- deleting the community; asked directly, the answer is `OWNER_CANNOT_LEAVE`.
-- The rest mirrors the rules every other self-service write already follows:
-- a suspended account performs no new activity (`ACCOUNT_SUSPENDED`, 0065) and
-- a suspended community is frozen for it (`COMMUNITY_INACTIVE`, 0065). Leaving
-- reorders other people's rosters -- a reserve is promoted into the seat -- so it
-- is new activity, not merely the absence of it.
--
-- No lock is taken on the membership row up front. `purge_membership` locks each
-- match before it deletes the membership, and `remove_member` reaches it the
-- same way; taking the membership first here would be the opposite order, and a
-- leave racing a removal of the same member could deadlock. Whichever finishes
-- second simply finds nothing left to delete.
--
-- ## 2. Ending a membership withdraws from matches NOT YET PLAYED only
--
-- `purge_membership` (0017, last 0053) deleted the member's registration in
-- EVERY match of the community, played ones included. Nothing has exercised that
-- yet -- no member with a played match has been removed -- but it would have
-- rewritten history that belongs to other people too: a lineup, a team's result,
-- a teammate's record. The approved policy (Product Owner, 2026-10-15) is that a
-- played match is history and stays exactly as it is when a member leaves or is
-- removed. "Not yet played" is the application's rule everywhere, the one the
-- account deletion engine (0102) uses: status is not 'completed' and the end
-- has not passed.
--
-- ## 3. The empty statistics row goes with the membership
--
-- Joining creates an all-zero 'overall' row in `community_statistics`
-- (`create_community_statistics_on_join`, 0028) so that a member appears on the
-- boards before playing. Ending the membership never removed it, so a removed
-- member who had never played went on appearing in the community's statistics
-- (`v_football_community_player_stats` reads that table, not the membership).
-- The row is now removed when -- and only when -- every counter in it is zero.
-- A row holding a played match is history and stays; rejoining finds it again
-- (the join trigger is `on conflict do nothing`). Removing an all-zero row is
-- invisible to `reconcile_community_statistics`, which reads a missing row as
-- zeros, and `rebuild_community_statistics` recreates zero rows for members
-- only.
--
-- The rows already left behind this way are removed once, below: all-zero
-- statistics of somebody who is no longer a member of that community.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- purge_membership -- effective definition from `0053`.
-- CHANGED (0104): the loop visits matches not yet played only, and an all-zero
-- statistics row is removed with the membership. Every other line is
-- byte-preserved.
create or replace function public.purge_membership(p_community_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_promoted uuid;
begin
  for r in
    select mr.id, mr.status, mr.match_id, m.title
    from match_registrations mr
    join matches m on m.id = mr.match_id
    where m.community_id = p_community_id and mr.user_id = p_user_id
      -- CHANGED (0104): a played match is history and is left as it is.
      and m.status <> 'completed' and m.end_at > now()
  loop
    perform 1 from matches where id = r.match_id for update;
    delete from match_registrations where id = r.id;
    if r.status = 'confirmed' then
      -- CHANGED (0053): the authoritative order.
      update match_registrations set status = 'confirmed'
      where id = next_reserve_registration(r.match_id)
      returning user_id into v_promoted;
      if v_promoted is not null then
        perform create_notification(v_promoted, r.match_id, 'promoted',
            coalesce(r.title, ''));
      end if;
    end if;
    perform recompute_match_status(r.match_id);
  end loop;

  delete from community_members
  where community_id = p_community_id and user_id = p_user_id;

  -- CHANGED (0104): the row joining created, when nothing was ever counted in it.
  delete from community_statistics
  where community_id = p_community_id and user_id = p_user_id
    and matches_played = 0 and wins = 0 and losses = 0
    and draws = 0 and goals = 0 and mvp_count = 0;
end;
$$;

revoke execute on function public.purge_membership(uuid, uuid)
  from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- leave_community -- new.
create or replace function public.leave_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_role text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;

  select role into v_role from community_members
  where community_id = p_community_id and user_id = auth.uid();
  if not found then raise exception 'MEMBER_NOT_FOUND'; end if;
  if v_role = 'owner' then raise exception 'OWNER_CANNOT_LEAVE'; end if;

  if not exists (
    select 1 from communities c where c.id = p_community_id and c.is_active
  ) then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  perform purge_membership(p_community_id, auth.uid());
end;
$$;

revoke execute on function public.leave_community(uuid) from anon, public;
grant execute on function public.leave_community(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- One-time: the empty rows already left behind by removals before this one.
delete from public.community_statistics cs
where cs.matches_played = 0 and cs.wins = 0 and cs.losses = 0
  and cs.draws = 0 and cs.goals = 0 and cs.mvp_count = 0
  and not exists (
    select 1 from public.community_members cm
    where cm.community_id = cs.community_id and cm.user_id = cs.user_id
  );
