-- Community-first simplification: one way into a community.
--
-- Before this migration there were three: a directed invitation naming a user,
-- a shareable link carrying its own 32-character token, and the community's
-- 6-character join code. They overlapped, and the link and the code were
-- separate identifiers for the same act of joining.
--
-- After it there is one: the community's join_code. It is the token. The
-- invitation link carries it, the join dialog accepts it, and
-- join_community_by_code redeems it — the function that already existed.
--
-- Removed here: the invitations table and its three RPCs, and the
-- community_invite_links table with its four RPCs and helper. Nothing else
-- referenced them; match registration was always self-service.

-- 1) Directed invitations ------------------------------------------------------
drop function if exists public.create_invitation(uuid, uuid, text);
drop function if exists public.revoke_invitation(uuid);
drop function if exists public.accept_invitation(uuid);
drop table if exists public.invitations cascade;

-- 2) Shareable invite links ----------------------------------------------------
-- Superseded by join_code. Match-attached links go with them: an organizer no
-- longer registers anyone, players register themselves.
drop function if exists public.create_invite_link(uuid, uuid);
drop function if exists public.revoke_invite_link(uuid);
drop function if exists public.preview_invite_link(text);
drop function if exists public.redeem_invite_link(text);
drop function if exists public.invite_link_state(public.community_invite_links);
drop table if exists public.community_invite_links cascade;

-- 3) The join code becomes the token -------------------------------------------
-- Twelve characters from a 31-symbol alphabet (Crockford-style base32 without
-- I, L, O, 0 and 1, which people mistype): about 59 bits. The old six
-- characters were guessable by brute force, which matters now that the code is
-- what an unauthenticated preview accepts.
create or replace function public.generate_join_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    select string_agg(
             substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1),
             '')
      into v_code
      from generate_series(1, 12);
    exit when not exists (select 1 from communities where join_code = v_code);
  end loop;
  return v_code;
end;
$$;

alter table public.communities
  alter column join_code set default public.generate_join_code();

-- Existing codes are six characters, which is the weakness this migration
-- closes, so they are reissued rather than left as a mixed-strength estate.
-- BREAKING: any six-character code already shared stops working.
update public.communities set join_code = public.generate_join_code();

alter table public.communities
  drop constraint if exists communities_join_code_length_check;
alter table public.communities
  add constraint communities_join_code_length_check
  check (char_length(join_code) between 6 and 32);

-- 4) Preview before signing in -------------------------------------------------
-- The landing screen has to show what a link offers to someone who has not
-- installed the app yet, let alone signed in. Deliberately narrow: the
-- community's name and whether the caller is already in it. Never the join
-- code itself, the roster, the matches, or who owns it.
create or replace function public.preview_community_invite(p_code text)
returns table (
  state text,
  community_id uuid,
  community_name text,
  is_member boolean
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_community communities%rowtype;
begin
  select * into v_community
  from communities c
  where c.join_code = upper(trim(p_code)) and c.is_active;

  if not found then
    return query select 'not_found'::text, null::uuid, null::text, false;
    return;
  end if;

  return query select
    'valid'::text,
    v_community.id,
    v_community.name,
    auth.uid() is not null and is_community_member(v_community.id, auth.uid());
end;
$$;

revoke execute on function public.generate_join_code() from anon, authenticated, public;
revoke execute on function public.preview_community_invite(text) from public;
grant execute on function public.preview_community_invite(text)
  to anon, authenticated;
