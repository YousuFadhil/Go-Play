-- ===== migrations/0094_nearby_discovery_wilayat.sql =====
-- Nearby Discovery, by Wilayat: the reference data, the two location columns,
-- the owner's setter, and the columns Discover reads to put local football first.
--
-- **Nothing is deleted and no existing column changes meaning.** Two reference
-- tables and two nullable columns are added, two views gain columns at their end,
-- one function gains a defaulted parameter and one gains a column. The single
-- data change assigns the existing community to Sohar.
--
--   1. `governorates`, `wilayats`              -- the reference data (11 + 63 rows)
--   2. `communities.wilayat_code`              -- where a community plays, nullable
--      `users.default_wilayat_code`            -- a player's own Default Location
--   3. `set_community_wilayat(uuid, smallint)` -- the owner's one setter
--   4. `create_community(..., smallint)`       -- Wilayat parameter, DEFAULT NULL
--   5. `my_profile()`                          -- gains `default_wilayat_code`
--   6. `v_public_upcoming_matches`             -- gains `wilayat_code`
--      `v_public_communities`                  -- gains `wilayat_code`, `last_activity_at`
--
-- ## WHERE THE DATA COMES FROM
--
-- Ministry of Interior open data, dataset "محافظات وولايات سلطنة عُمان", page
-- https://www.moi.gov.om/ar-om/Page/open-data, file
-- "محافظات سلطنة عُمان والولايات التابعة لها.xlsx" (workbook created and modified
-- 2022-08-03), retrieved 2026-09-29, SHA-256
-- feb99264d496dbf9e2ff0e9a9abb8886f02cee06a102aba895fe890ae347def0. 11
-- Governorates (Region Code 1-11) and 63 Wilayats (Wilayat Code 1-63); every code
-- in both ranges is present once. Arabic names are the MOI spelling with the
-- orthography normalised as `Docs/reviews/Nearby_Discovery_Frozen_Spec.md` §2.2
-- sets out (tatweel stripped; ة for the ه that MOI wrote in «الباطنة» and
-- «الشرقية»; «الداخلية» for MOI's «الدخلية»; «الجبل الأخضر» with its hamza; the
-- prefix «محافظة» not stored). English names are the NCSI Statistical Year Book
-- 2026 table spelling; MOI publishes none.
--
-- **The codes are the MOI codes, and they are Go Play's keys from here on.** Sohar
-- is 7, North Al Batinah is 2. They are never shown in the UI and never
-- renumbered: if MOI ever renumbers, these stay as they are. `sort_order` is the
-- display order: Governorates by Region Code, Wilayats in the order of the
-- specification's Appendix B (by Governorate, then by code).
--
-- ## WHAT THIS DELIBERATELY DOES NOT DO
--
--   * **No column on `matches`.** A match's Wilayat is its Community's current
--     one; `matches.location` stays free display text.
--   * **`communities.wilayat_code` stays nullable.** The app requires a Wilayat
--     for a *new* community; the database still accepts none so that an
--     installed build calling the three-argument `create_community` keeps
--     working. A community with none is discovered as non-local.
--   * **`users.default_wilayat_code` is not readable through the table.** The
--     column-level SELECT grant on `users` (`0056`) is not touched, because the
--     row policy shows every active user to any signed-in user and a private
--     preference must not ride on it. The owner reads it through `my_profile()`,
--     which has no user-id argument, and writes it through a column-level UPDATE
--     grant confined to their own row by `users_update_own_profile`.
--   * **`handle_new_user` (`0092`) is not touched.** The optional initial
--     location is offered after sign-up, in Profile.
--   * **`public_recent_results` and the football views are not touched.** Latest
--     Results keeps its contract exactly.
--   * **No `create_community` overload.** A second function with a fourth
--     parameter would leave PostgREST unable to choose between them (PGRST203) and
--     installed builds would stop creating communities. The three-argument
--     function is dropped and replaced by one whose fourth parameter defaults to
--     null, so a three-argument call still resolves.
--
-- ## COMPATIBILITY
--
-- Every change is additive to a caller that does not know about it. The views
-- gain columns at their END, which `create or replace view` permits and which no
-- column-named read notices. `my_profile()` is a `returns table` function, so its
-- return type is part of its identity and an added column means drop and create
-- in this one transaction; callers read it by column name. Apply this migration
-- BEFORE the client that names `wilayat_code`: the new client selects that column
-- and would be refused by a database without it.

-- ============================================================================
-- 1) Reference data
-- ============================================================================
create table public.governorates (
  code       smallint primary key check (code > 0),
  name_ar    text     not null check (length(btrim(name_ar)) > 0),
  name_en    text     not null check (length(btrim(name_en)) > 0),
  sort_order smallint not null,
  constraint governorates_name_ar_key unique (name_ar),
  constraint governorates_name_en_key unique (name_en)
);

create table public.wilayats (
  code             smallint primary key check (code > 0),
  governorate_code smallint not null
    references public.governorates (code),
  name_ar          text     not null check (length(btrim(name_ar)) > 0),
  name_en          text     not null check (length(btrim(name_en)) > 0),
  -- Search aliases only: a village, a variant spelling. Never a place of its
  -- own and never shown as one.
  search_terms     text[]   not null default '{}',
  sort_order       smallint not null,
  is_active        boolean  not null default true,
  constraint wilayats_name_ar_key unique (name_ar),
  constraint wilayats_name_en_key unique (name_en)
);

create index wilayats_governorate_code_idx
  on public.wilayats (governorate_code);

comment on table public.governorates is
  'The 11 governorates of Oman, keyed by the Ministry of Interior Region Code. '
  'Reference data: readable by everyone, writable by no client role. Migration 0094.';
comment on table public.wilayats is
  'The 63 wilayats of Oman, keyed by the Ministry of Interior Wilayat Code (Sohar = 7). '
  'The only location unit Go Play uses; villages are search_terms of their wilayat. '
  'Reference data: readable by everyone, writable by no client role. Migration 0094.';

-- Public read, no client write. Supabase's default privileges would otherwise
-- hand `anon` and `authenticated` every privilege on a new table, so they are
-- revoked first and the one intended grant is then written out.
alter table public.governorates enable row level security;
alter table public.wilayats     enable row level security;

create policy "governorates_select_all"
  on public.governorates for select to anon, authenticated using (true);
create policy "wilayats_select_all"
  on public.wilayats for select to anon, authenticated using (true);

revoke all on public.governorates from public, anon, authenticated;
revoke all on public.wilayats     from public, anon, authenticated;
grant select on public.governorates to anon, authenticated;
grant select on public.wilayats     to anon, authenticated;

insert into public.governorates (code, name_ar, name_en, sort_order) values
  (1, 'مسقط', 'Muscat', 1),
  (2, 'شمال الباطنة', 'Al Batinah North', 2),
  (3, 'مسندم', 'Musandam', 3),
  (4, 'البريمي', 'Al Buraymi', 4),
  (5, 'الظاهرة', 'Adh Dhahirah', 5),
  (6, 'الداخلية', 'Ad Dakhiliyah', 6),
  (7, 'شمال الشرقية', 'Ash Sharqiyah North', 7),
  (8, 'الوسطى', 'Al Wusta', 8),
  (9, 'ظفار', 'Dhofar', 9),
  (10, 'جنوب الباطنة', 'Al Batinah South', 10),
  (11, 'جنوب الشرقية', 'Ash Sharqiyah South', 11);

insert into public.wilayats
  (code, governorate_code, name_ar, name_en, search_terms, sort_order)
values
  (1, 1, 'مسقط', 'Muscat', '{}'::text[], 1),
  (2, 1, 'السيب', 'As Seeb', '{}'::text[], 2),
  (3, 1, 'مطرح', 'Mutrah', '{}'::text[], 3),
  (4, 1, 'بوشر', 'Bawshar', '{}'::text[], 4),
  (5, 1, 'العامرات', 'Al Amrat', '{}'::text[], 5),
  (6, 1, 'قريات', 'Qurayyat', '{}'::text[], 6),
  (7, 2, 'صحار', 'Sohar', array['مجيس', 'Majees']::text[], 7),
  (9, 2, 'شناص', 'Shinas', '{}'::text[], 8),
  (10, 2, 'لوى', 'Liwa', '{}'::text[], 9),
  (11, 2, 'صحم', 'Saham', '{}'::text[], 10),
  (12, 2, 'الخابورة', 'Al Khaburah', array['Khabourah']::text[], 11),
  (13, 2, 'السويق', 'As Suwayq', array['Suwaiq']::text[], 12),
  (19, 3, 'خصب', 'Khasab', '{}'::text[], 13),
  (20, 3, 'بخاء', 'Bukha', '{}'::text[], 14),
  (21, 3, 'دبا', 'Daba', '{}'::text[], 15),
  (22, 3, 'مدحاء', 'Madha', '{}'::text[], 16),
  (23, 4, 'البريمي', 'Al Buraymi', '{}'::text[], 17),
  (25, 4, 'محضة', 'Mahdah', '{}'::text[], 18),
  (61, 4, 'السنينة', 'Al Sinainah', '{}'::text[], 19),
  (24, 5, 'عبري', 'Ibri', '{}'::text[], 20),
  (26, 5, 'ينقل', 'Yanqul', '{}'::text[], 21),
  (27, 5, 'ضنك', 'Dank', '{}'::text[], 22),
  (28, 6, 'نزوى', 'Nizwa', '{}'::text[], 23),
  (29, 6, 'سمائل', 'Samail', '{}'::text[], 24),
  (30, 6, 'بهلاء', 'Bahla', '{}'::text[], 25),
  (31, 6, 'أدم', 'Adam', '{}'::text[], 26),
  (32, 6, 'الحمراء', 'Al Hamra', '{}'::text[], 27),
  (33, 6, 'منح', 'Manah', '{}'::text[], 28),
  (34, 6, 'إزكي', 'Izki', '{}'::text[], 29),
  (35, 6, 'بدبد', 'Bid Bid', '{}'::text[], 30),
  (62, 6, 'الجبل الأخضر', 'Jabal Al-Akhdhar', array['Jebel Akhdar', 'Jabal Akhdar']::text[], 31),
  (37, 7, 'إبراء', 'Ibra', '{}'::text[], 32),
  (38, 7, 'بدية', 'Bidiyah', '{}'::text[], 33),
  (39, 7, 'القابل', 'Al Qabil', '{}'::text[], 34),
  (40, 7, 'المضيبي', 'Al Mudaybi', '{}'::text[], 35),
  (41, 7, 'دماء والطائيين', 'Dima Wa At Taiyyin', '{}'::text[], 36),
  (45, 7, 'وادي بني خالد', 'Wadi Bani Khalid', '{}'::text[], 37),
  (63, 7, 'سناو', 'Sinaw', '{}'::text[], 38),
  (47, 8, 'هيماء', 'Hayma', '{}'::text[], 39),
  (48, 8, 'محوت', 'Muhut', '{}'::text[], 40),
  (49, 8, 'الدقم', 'Ad Duqm', '{}'::text[], 41),
  (50, 8, 'الجازر', 'Al Jazer', '{}'::text[], 42),
  (51, 9, 'صلالة', 'Salalah', '{}'::text[], 43),
  (52, 9, 'ثمريت', 'Thumrayt', '{}'::text[], 44),
  (53, 9, 'طاقة', 'Taqah', '{}'::text[], 45),
  (54, 9, 'مرباط', 'Mirbat', '{}'::text[], 46),
  (55, 9, 'سدح', 'Sadh', array['Sadah']::text[], 47),
  (56, 9, 'رخيوت', 'Rakhyut', '{}'::text[], 48),
  (57, 9, 'ضلكوت', 'Dalkut', '{}'::text[], 49),
  (58, 9, 'مقشن', 'Muqshin', '{}'::text[], 50),
  (59, 9, 'شليم وجزر الحلانيات', 'Shalim Wa Juzur Al Hallaniyat', '{}'::text[], 51),
  (60, 9, 'المزيونة', 'Al Mazuna', '{}'::text[], 52),
  (8, 10, 'الرستاق', 'Ar Rustaq', '{}'::text[], 53),
  (14, 10, 'نخل', 'Nakhal', '{}'::text[], 54),
  (15, 10, 'وادي المعاول', 'Wadi Al Maawil', '{}'::text[], 55),
  (16, 10, 'العوابي', 'Al Awabi', '{}'::text[], 56),
  (17, 10, 'المصنعة', 'Al Musanaah', array['Musannah']::text[], 57),
  (18, 10, 'بركاء', 'Barka', '{}'::text[], 58),
  (36, 11, 'صور', 'Sur', '{}'::text[], 59),
  (42, 11, 'الكامل والوافي', 'Al Kamil Wa Al Wafi', '{}'::text[], 60),
  (43, 11, 'جعلان بني بو علي', 'Jaalan Bani Bu Ali', '{}'::text[], 61),
  (44, 11, 'جعلان بني بو حسن', 'Jaalan Bani Bu Hasan', array['Jaalan Bani Bu Hassan']::text[], 62),
  (46, 11, 'مصيرة', 'Masirah', '{}'::text[], 63);

-- ============================================================================
-- 2) Where a community plays, and a player's Default Location
-- ============================================================================
alter table public.communities
  add column wilayat_code smallint references public.wilayats (code);
alter table public.users
  add column default_wilayat_code smallint references public.wilayats (code);

create index communities_wilayat_code_idx
  on public.communities (wilayat_code) where wilayat_code is not null;

comment on column public.communities.wilayat_code is
  'The wilayat the community plays in. Nullable for backward compatibility: a '
  'community with none is discovered as non-local. Changed only by its owner '
  'through set_community_wilayat(), or by a System Admin in SQL. Migration 0094.';
comment on column public.users.default_wilayat_code is
  'The player''s optional Default Location. Private to its owner: not in the '
  'column-level SELECT grant on this table; read through my_profile(). '
  'Migration 0094.';

-- The one data change: the existing community plays in Sohar (7). At the time of
-- writing there is exactly one community, so "every community without a Wilayat"
-- is that one; no fixture and no other row is created.
update public.communities set wilayat_code = 7 where wilayat_code is null;

-- A community's Wilayat is public (both public views publish it), so the column
-- joins the authenticated SELECT list `0056` built column by column. The player's
-- own column is deliberately NOT added to the `users` list.
grant select (wilayat_code) on public.communities to authenticated;

-- A player writes their own Default Location directly, like the other profile
-- columns: this column grant says which column, and `users_update_own_profile`
-- confines the statement to the caller's own row.
grant update (default_wilayat_code) on public.users to authenticated;

-- ============================================================================
-- 3) set_community_wilayat -- the owner's one setter
-- ============================================================================
-- Modelled on `set_community_logo` (`0061`/`0065`) and `regenerate_join_code`
-- (`0065`): a session, an active account (`0064`), the role, then the community
-- row -- locked, and refused when suspended (`0065`). The role is asked before the
-- row is read, so a refusal never depends on what was found. `owner` is the
-- minimum: admins may change a community's picture but not where it plays.
--
-- An inactive or unknown code is refused with INVALID_WILAYAT, and so is null: a
-- community moves from one Wilayat to another, it does not lose its Wilayat here.
create or replace function public.set_community_wilayat(
  p_community_id uuid,
  p_wilayat_code smallint
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_community_active boolean;
  v_stored smallint;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if not public.has_community_role(p_community_id, auth.uid(), 'owner') then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select c.is_active
    into v_community_active
    from public.communities c
   where c.id = p_community_id
     for update;
  if not found then
    raise exception 'COMMUNITY_NOT_FOUND';
  end if;
  if not v_community_active then
    raise exception 'COMMUNITY_INACTIVE';
  end if;

  if p_wilayat_code is null or not exists (
    select 1 from public.wilayats w
     where w.code = p_wilayat_code and w.is_active
  ) then
    raise exception 'INVALID_WILAYAT';
  end if;

  update public.communities c
     set wilayat_code = p_wilayat_code,
         updated_at = now()
   where c.id = p_community_id
  returning c.wilayat_code into v_stored;

  return v_stored;
end;
$$;

comment on function public.set_community_wilayat(uuid, smallint) is
  'Owner only: moves a community to another active wilayat. Refuses a suspended '
  'account (ACCOUNT_SUSPENDED), a non-owner (NOT_AUTHORIZED), a missing or '
  'suspended community (COMMUNITY_NOT_FOUND / COMMUNITY_INACTIVE) and a null, '
  'unknown or inactive code (INVALID_WILAYAT). Migration 0094.';

revoke execute on function public.set_community_wilayat(uuid, smallint)
  from anon, public;
grant execute on function public.set_community_wilayat(uuid, smallint)
  to authenticated;

-- ============================================================================
-- 4) create_community -- the Wilayat parameter, optional
-- ============================================================================
-- Dropped and recreated rather than overloaded: see the header. The body is
-- `0064`'s, with the one added parameter and the one added check.
drop function public.create_community(text, text, text);

create function public.create_community(
  p_name text,
  p_description text,
  p_join_policy text,
  p_wilayat_code smallint default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_current_user_active() then
    raise exception 'ACCOUNT_SUSPENDED';
  end if;
  if p_join_policy not in ('OPEN', 'CODE_REQUIRED') then
    raise exception 'INVALID_JOIN_POLICY';
  end if;
  -- Added by migration 0094. Null is accepted: the app requires a Wilayat for a
  -- new community, and a build that predates it sends none.
  if p_wilayat_code is not null and not exists (
    select 1 from public.wilayats w
     where w.code = p_wilayat_code and w.is_active
  ) then
    raise exception 'INVALID_WILAYAT';
  end if;

  insert into communities (owner_id, name, description, join_policy, wilayat_code)
  values (auth.uid(), p_name, p_description, p_join_policy, p_wilayat_code)
  returning id into v_id;

  insert into community_members (community_id, user_id, role)
  values (v_id, auth.uid(), 'owner');

  return v_id;
end;
$$;

comment on function public.create_community(text, text, text, smallint) is
  'Creates a community with the caller as owner. The fourth parameter is '
  'optional so a three-argument call still resolves; an unknown or inactive '
  'code is INVALID_WILAYAT. Migration 0094 (previously 0064, three arguments).';

revoke execute on function public.create_community(text, text, text, smallint)
  from anon, public;
grant execute on function public.create_community(text, text, text, smallint)
  to authenticated;

-- ============================================================================
-- 5) my_profile -- the owner reads their own Default Location
-- ============================================================================
-- `0063`'s function with one column appended. A `returns table` function cannot
-- gain a column through `create or replace`, so it is dropped and created in this
-- transaction and its privileges are restated. No user-id argument: still
-- strictly self-only.
drop function public.my_profile();

create function public.my_profile()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  primary_position text,
  secondary_position text,
  date_of_birth date,
  avatar_path text,
  overall_rating numeric,
  profile_visibility text,
  age_visible boolean,
  default_wilayat_code smallint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  return query
  select
    u.id,
    u.full_name,
    u.phone,
    u.primary_position,
    u.secondary_position,
    u.date_of_birth,
    u.avatar_path,
    u.overall_rating,
    u.profile_visibility,
    u.age_visible,
    u.default_wilayat_code
  from users u
  where u.id = auth.uid();
end;
$$;

comment on function public.my_profile() is
  'The signed-in player''s own account row, phone and Default Location included. '
  'Takes no user id, so it cannot be pointed at anybody else -- see migration 0055. '
  'Returns the row whether or not the account is active (migration 0063). '
  'Migration 0094 appended default_wilayat_code.';

revoke execute on function public.my_profile() from anon, public;
grant execute on function public.my_profile() to authenticated;

-- ============================================================================
-- 6) The public read models
-- ============================================================================
-- Each is its earlier definition -- `0033` for the matches, `0061` for the
-- communities -- with columns appended at the end, which `create or replace view`
-- allows and which keeps the existing grants. Neither is `security_invoker`,
-- exactly as before, so a request with no session still answers.
--
-- `wilayat_code` is the community's CURRENT one: a match carries no Wilayat of its
-- own. `last_activity_at` is the community's latest completed match's `start_at`,
-- or its `created_at` when it has none; "completed" is the predicate of
-- `v_football_completed_matches` (`0057`): `status = 'completed' or end_at <= now()`.
create or replace view public.v_public_upcoming_matches as
select
  m.id,
  m.community_id,
  c.name                                  as community_name,
  m.title,
  m.location,
  m.start_at,
  m.end_at,
  m.status,
  m.starting_players,
  greatest(m.starting_players - coalesce(reg.confirmed_count, 0), 0)::int
                                          as open_slots,
  c.wilayat_code
from public.matches m
join public.communities c on c.id = m.community_id
left join lateral (
  select count(*) filter (where r.status = 'confirmed') as confirmed_count
  from public.match_registrations r
  where r.match_id = m.id
) reg on true
where c.is_active
  and m.end_at > now()
  and m.status <> 'completed';

comment on view public.v_public_upcoming_matches is
  'Public read model: matches that have not ended, with remaining places and the '
  'community''s current wilayat_code. Readable without a session. Unordered by '
  'design -- the caller sorts. Migration 0094 appended wilayat_code.';

create or replace view public.v_public_communities as
select
  c.id,
  c.name,
  c.description,
  (
    select count(*)
    from public.community_members cm
    where cm.community_id = c.id
  )::int                                  as member_count,
  (
    select count(*)
    from public.matches m
    where m.community_id = c.id
      and m.end_at > now()
      and m.status <> 'completed'
  )::int                                  as upcoming_match_count,
  c.created_at,
  c.logo_url,
  c.wilayat_code,
  coalesce(
    (
      select max(m.start_at)
      from public.matches m
      where m.community_id = c.id
        and (m.status = 'completed' or m.end_at <= now())
    ),
    c.created_at
  )                                       as last_activity_at
from public.communities c
where c.is_active;

comment on view public.v_public_communities is
  'Public community discovery. Migration 0094 appended wilayat_code and '
  'last_activity_at (latest completed match start, else created_at) and changed '
  'nothing else about the projection, its filter or its grants.';

-- Re-asserted, as `0056` does: both remain read-only and readable by both roles.
revoke insert, update, delete, truncate, references, trigger
  on public.v_public_communities from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.v_public_upcoming_matches from anon, authenticated;
grant select on public.v_public_communities      to anon, authenticated;
grant select on public.v_public_upcoming_matches to anon, authenticated;
