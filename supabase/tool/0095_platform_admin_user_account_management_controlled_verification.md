# 0095 — controlled verification against a designated test account

Run **after** migration `0095` has been applied (Architect review and Product Owner approval first), and **after** `0095_platform_admin_user_account_management_verify.sql` returns `ok = true` on every row.

Staging and production share one database, so this runs against production data. That is why it uses **one designated test account and never a real player**.

## Placeholders

Replace these in every block before running it. They are the only things to edit.

| Placeholder | What it is |
|---|---|
| `<ADMIN_ID>` | The `users.id` of the System Admin acting. Must be in `system_admins`. |
| `<TEST_USER_ID>` | The designated test account. Must **not** be a System Admin and must **not** be `<ADMIN_ID>`. |
| `<OTHER_SYSTEM_ADMIN_ID>` | Step 3 only: a second System Admin, if one exists. |

## How the blocks work

- Run each numbered block **on its own**, in the Supabase SQL editor, as the project's default role. Do not run them together.
- Each block is **one batch, and a batch is one transaction**: it succeeds as a whole or leaves nothing behind.
- A block makes the database believe the call came from `<ADMIN_ID>` (or another account) by setting the JWT claims for that transaction only. It does **not** switch role, so it exercises the gate inside each function — `is_system_admin()` reads `auth.uid()` — and not the grants. The grants are checked statically by `verify.sql`.
- A block collects its checks in a temporary table (`pg_temp._v`) and ends by showing it: columns `check_name`, `expected`, `actual`, `ok`. **Every `ok` must be `true`.**
- **If any check fails, the block raises an error that lists the failures, and nothing is kept.** That is intended: the error is how a failed block rolls itself back. Stop and report; do not continue.
- Blocks 1 to 5 write nothing by design. Block 6 writes, restores the test account to what it was, and only then commits.
- The audit log is append-only. Block 6 therefore leaves ten `USER_PROFILE_UPDATED` rows behind for the test account — five changes and five restores. That is the evidence, not a mess to clean up. Nothing in this procedure deletes an audit row.

## 0 — Before you start (read only)

Check the test account is what you think it is. Keep the output.

```sql
-- step:0
select u.id,
       u.full_name, u.phone, u.date_of_birth,
       u.primary_position, u.secondary_position,
       u.profile_visibility, u.age_visible, u.default_wilayat_code,
       u.is_active,
       (select row_to_json(p) from public.notification_push_preferences p
         where p.user_id = u.id)                                  as push_row,
       exists (select 1 from public.system_admins sa
                where sa.user_id = u.id)                           as test_user_is_system_admin,
       (u.id = '<ADMIN_ID>'::uuid)                                 as test_user_is_the_admin,
       exists (select 1 from public.system_admins sa
                where sa.user_id = '<ADMIN_ID>'::uuid)             as admin_is_system_admin,
       (select count(*) from public.system_admins)                 as system_admin_count,
       (select count(*) from public.admin_audit_log l
         where l.target_id = u.id
           and l.action = 'USER_PROFILE_UPDATED')                  as audit_rows_before
  from public.users u
 where u.id = '<TEST_USER_ID>'::uuid;
```

Expected: one row; `test_user_is_system_admin = false`; `test_user_is_the_admin = false`; `admin_is_system_admin = true`.

## 1 — A non-admin is refused, by the first check

The caller is the test account itself, an ordinary player. All six calls must raise `NOT_AUTHORIZED` — including a write aimed at the caller's own id, which proves the gate comes before the self check. A call with no session at all must also be refused.

```sql
-- step:1
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  r record;
  v_err text;
  v_actor text;
begin
  foreach v_actor in array array['<TEST_USER_ID>', ''] loop
    perform set_config('request.jwt.claim.sub', v_actor, true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', nullif(v_actor, ''), 'role', 'authenticated')::text, true);

    for r in
      select * from (values
        ('read',     'select * from public.admin_get_user_account(%L)'),
        ('account',  'select public.admin_update_user_account(%L, ''Verify Name'', ''+96890000000'')'),
        ('player',   'select public.admin_update_user_player_profile(%L, null, ''GK'', null)'),
        ('privacy',  'select public.admin_update_user_privacy(%L, ''EVERYONE'', true)'),
        ('location', 'select public.admin_update_user_default_wilayat(%L, null)'),
        ('push',     'select public.admin_update_user_push_preferences(%L, true, true, false)')
      ) as t(label, stmt)
    loop
      begin
        execute format(r.stmt, '<TEST_USER_ID>');
        v_err := 'no error';
      exception when others then
        v_err := sqlerrm;
      end;
      insert into _v values (
        case when v_actor = '' then 'no session: ' else 'non-admin: ' end || r.label,
        'NOT_AUTHORIZED', v_err, v_err = 'NOT_AUTHORIZED');
    end loop;
  end loop;
end $$;

do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

## 2 — An administrator cannot edit themselves

All five writes aimed at `<ADMIN_ID>` must raise `CANNOT_MODIFY_SELF`. The read is allowed and must return one row.

```sql
-- step:2
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  r record;
  v_err text;
  v_rows int;
begin
  perform set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);

  for r in
    select * from (values
      ('account',  'select public.admin_update_user_account(%L, ''Verify Name'', ''+96890000000'')'),
      ('player',   'select public.admin_update_user_player_profile(%L, null, ''GK'', null)'),
      ('privacy',  'select public.admin_update_user_privacy(%L, ''EVERYONE'', true)'),
      ('location', 'select public.admin_update_user_default_wilayat(%L, null)'),
      ('push',     'select public.admin_update_user_push_preferences(%L, true, true, false)')
    ) as t(label, stmt)
  loop
    begin
      execute format(r.stmt, '<ADMIN_ID>');
      v_err := 'no error';
    exception when others then
      v_err := sqlerrm;
    end;
    insert into _v values ('self: ' || r.label, 'CANNOT_MODIFY_SELF', v_err,
                           v_err = 'CANNOT_MODIFY_SELF');
  end loop;

  select count(*) into v_rows from public.admin_get_user_account('<ADMIN_ID>');
  insert into _v values ('self: read is allowed', '1 row', v_rows || ' row(s)', v_rows = 1);
end $$;

do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

## 3 — A System Admin cannot be edited (only if a second one exists)

With exactly one System Admin this refusal cannot be reached on the live database: the caller is that administrator, so the self check fires first. If `system_admin_count` in step 0 was `1`, **mark this step "not reachable" and skip it** — it is covered by the offline run described in the report. If a second System Admin exists, put its id in `<OTHER_SYSTEM_ADMIN_ID>`.

```sql
-- step:3
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  r record;
  v_err text;
  v_rows int;
begin
  perform set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);

  for r in
    select * from (values
      ('account',  'select public.admin_update_user_account(%L, ''Verify Name'', ''+96890000000'')'),
      ('player',   'select public.admin_update_user_player_profile(%L, null, ''GK'', null)'),
      ('privacy',  'select public.admin_update_user_privacy(%L, ''EVERYONE'', true)'),
      ('location', 'select public.admin_update_user_default_wilayat(%L, null)'),
      ('push',     'select public.admin_update_user_push_preferences(%L, true, true, false)')
    ) as t(label, stmt)
  loop
    begin
      execute format(r.stmt, '<OTHER_SYSTEM_ADMIN_ID>');
      v_err := 'no error';
    exception when others then
      v_err := sqlerrm;
    end;
    insert into _v values ('system admin: ' || r.label, 'CANNOT_MODIFY_SYSTEM_ADMIN', v_err,
                           v_err = 'CANNOT_MODIFY_SYSTEM_ADMIN');
  end loop;

  select count(*) into v_rows from public.admin_get_user_account('<OTHER_SYSTEM_ADMIN_ID>');
  insert into _v values ('system admin: read is allowed', '1 row', v_rows || ' row(s)', v_rows = 1);
end $$;

do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

## 4 — One invalid value per group is refused, and nothing is written

Also: an unknown account is `USER_NOT_FOUND` even when the values are bad (the lookup comes first), and the audit count does not move.

```sql
-- step:4
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  r record;
  v_err text;
  v_before bigint;
  v_after bigint;
begin
  select count(*) into v_before from public.admin_audit_log;

  perform set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);

  for r in
    select * from (values
      ('name too short',
       'select public.admin_update_user_account(%L, ''A'', ''+96890000000'')',
       'INVALID_FULL_NAME'),
      ('phone malformed',
       'select public.admin_update_user_account(%L, ''Verify Name'', ''90000000'')',
       'INVALID_PHONE'),
      ('date of birth before 1900',
       'select public.admin_update_user_player_profile(%L, date ''1899-12-31'', ''GK'', null)',
       'INVALID_DATE_OF_BIRTH'),
      ('date of birth in the future (Muscat)',
       'select public.admin_update_user_player_profile(%L, ((now() at time zone ''Asia/Muscat'')::date + 1), ''GK'', null)',
       'INVALID_DATE_OF_BIRTH'),
      ('primary position unknown',
       'select public.admin_update_user_player_profile(%L, null, ''STRIKER'', null)',
       'INVALID_POSITION'),
      ('secondary equals primary',
       'select public.admin_update_user_player_profile(%L, null, ''GK'', ''GK'')',
       'INVALID_POSITION'),
      ('visibility unknown',
       'select public.admin_update_user_privacy(%L, ''PRIVATE'', true)',
       'INVALID_SETTINGS'),
      ('age visibility null',
       'select public.admin_update_user_privacy(%L, ''EVERYONE'', null)',
       'INVALID_SETTINGS'),
      ('wilayat unknown',
       'select public.admin_update_user_default_wilayat(%L, 99::smallint)',
       'INVALID_WILAYAT'),
      ('push switch null',
       'select public.admin_update_user_push_preferences(%L, true, null, false)',
       'INVALID_SETTINGS')
    ) as t(label, stmt, expected)
  loop
    begin
      execute format(r.stmt, '<TEST_USER_ID>');
      v_err := 'no error';
    exception when others then
      v_err := sqlerrm;
    end;
    insert into _v values (r.label, r.expected, v_err, v_err = r.expected);
  end loop;

  begin
    perform public.admin_update_user_account(
      '00000000-0000-0000-0000-00000000dead'::uuid, 'A', 'bad');
    v_err := 'no error';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into _v values ('unknown account, bad values', 'USER_NOT_FOUND', v_err,
                         v_err = 'USER_NOT_FOUND');

  select count(*) into v_after from public.admin_audit_log;
  insert into _v values ('audit rows written by refusals', '0',
                         (v_after - v_before)::text, v_after = v_before);
end $$;

do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

## 5 — A write that changes nothing writes nothing

Each of the five RPCs is called with the account's **current** values, read at the start. None may write an audit row, none may touch `users` (its `updated_at` stays), and a push call with the defaults on an account that has no preferences row must not create one.

```sql
-- step:5
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  u public.users%rowtype;
  p public.notification_push_preferences%rowtype;
  v_has_prefs boolean;
  v_audit_before bigint;
  v_audit_after bigint;
  v_updated_after timestamptz;
  v_prefs_before bigint;
  v_prefs_after bigint;
begin
  select * into u from public.users where id = '<TEST_USER_ID>'::uuid;
  select * into p from public.notification_push_preferences
   where user_id = '<TEST_USER_ID>'::uuid;
  v_has_prefs := found;
  select count(*) into v_audit_before from public.admin_audit_log;
  select count(*) into v_prefs_before from public.notification_push_preferences
   where user_id = u.id;

  perform set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);

  perform public.admin_update_user_account(u.id, u.full_name, u.phone);
  perform public.admin_update_user_account(u.id, '  ' || u.full_name || '  ', u.phone,
                                           'a reason does not make a no-op a change');
  perform public.admin_update_user_player_profile(
    u.id, u.date_of_birth, u.primary_position, u.secondary_position);
  perform public.admin_update_user_privacy(u.id, u.profile_visibility, u.age_visible);
  perform public.admin_update_user_default_wilayat(u.id, u.default_wilayat_code);
  perform public.admin_update_user_push_preferences(
    u.id,
    case when v_has_prefs then p.match_push else true end,
    case when v_has_prefs then p.community_push else true end,
    case when v_has_prefs then p.mute_all else false end);

  select count(*) into v_audit_after from public.admin_audit_log;
  insert into _v values ('audit rows written by six no-op calls', '0',
                         (v_audit_after - v_audit_before)::text,
                         v_audit_after = v_audit_before);

  select updated_at into v_updated_after from public.users where id = u.id;
  insert into _v values ('users row not touched (updated_at unchanged)',
                         u.updated_at::text, v_updated_after::text,
                         v_updated_after = u.updated_at);

  select count(*) into v_prefs_after from public.notification_push_preferences
   where user_id = u.id;
  insert into _v values (
    case when v_has_prefs then 'preferences row still there'
         else 'defaults on an account with no row create no row' end,
    v_prefs_before::text, v_prefs_after::text, v_prefs_after = v_prefs_before);
end $$;

do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

## 6 — A real change writes exactly one audit row of the right shape, then is undone

For each of the five groups the block changes **one** field of the test account, checks that exactly one audit row appeared (found by the reason it was given, which carries a tag unique to the run), that its metadata is `{"changed_fields": [...]}` and **nothing else**, then puts the field back with a second call. At the end it compares the whole account with the values read at the start.

**This block commits, and only if every check passed.** The guard comes before the end of the batch: one failed check raises an error and the whole batch — changes, restores and audit rows alike — is rolled back.

If the test account had no push-preferences row, the block removes the one it created (a direct delete of that account's own row, as the project's default role), because the RPC can set the defaults but cannot un-create a row. Nothing else is deleted.

```sql
-- step:6
drop table if exists pg_temp._v;
create temp table _v (check_name text, expected text, actual text, ok boolean);

do $$
declare
  v_target uuid := '<TEST_USER_ID>';
  v_actor uuid := '<ADMIN_ID>';
  -- Unique to this run, so the block can be run again.
  v_tag text := 'verify-' || to_char(clock_timestamp() at time zone 'UTC', 'YYMMDDHH24MISSMS') || '-';
  u public.users%rowtype;
  p public.notification_push_preferences%rowtype;
  v_has_prefs boolean;
  v_match boolean;
  v_community boolean;
  v_mute boolean;
  v_wilayat smallint;
  v_now public.users%rowtype;
  v_p_now public.notification_push_preferences%rowtype;
  l public.admin_audit_log%rowtype;
  v_n int;
begin
  select * into u from public.users where id = v_target;
  select * into p from public.notification_push_preferences where user_id = v_target;
  v_has_prefs := found;
  v_match     := case when v_has_prefs then p.match_push else true end;
  v_community := case when v_has_prefs then p.community_push else true end;
  v_mute      := case when v_has_prefs then p.mute_all else false end;
  select min(w.code) into v_wilayat from public.wilayats w
   where w.is_active and w.code is distinct from u.default_wilayat_code;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);

  -- ---- 1. name and phone: change the name only ---------------------------
  perform public.admin_update_user_account(v_target, u.full_name || ' (verify)', u.phone, v_tag || '1');
  select count(*) into v_n from public.admin_audit_log where reason = v_tag || '1' and target_id = v_target;
  select * into l from public.admin_audit_log where reason = v_tag || '1' and target_id = v_target;
  insert into _v values ('account: exactly one audit row', '1', v_n::text, v_n = 1);
  insert into _v values ('account: action, target and actor',
    'USER_PROFILE_UPDATED / USER / ' || v_actor,
    l.action || ' / ' || l.target_type || ' / ' || l.actor_user_id,
    l.action = 'USER_PROFILE_UPDATED' and l.target_type = 'USER' and l.actor_user_id = v_actor);
  insert into _v values ('account: metadata is changed_fields only',
    '{"changed_fields": ["full_name"]}', l.metadata::text,
    l.metadata = '{"changed_fields": ["full_name"]}'::jsonb
      and (select count(*) from jsonb_object_keys(l.metadata)) = 1);
  insert into _v values ('account: label is the name after the update',
    u.full_name || ' (verify)', coalesce(l.target_label_snapshot, 'null'),
    l.target_label_snapshot = u.full_name || ' (verify)');
  insert into _v values ('account: the change is stored',
    u.full_name || ' (verify)',
    (select full_name from public.users where id = v_target),
    (select full_name from public.users where id = v_target) = u.full_name || ' (verify)');
  perform public.admin_update_user_account(v_target, u.full_name, u.phone, v_tag || '1-restore');

  -- ---- 2. date of birth and positions: change the date of birth only -----
  perform public.admin_update_user_player_profile(
    v_target,
    case when u.date_of_birth is null then date '2000-01-01' else null end,
    u.primary_position, u.secondary_position, v_tag || '2');
  select count(*) into v_n from public.admin_audit_log where reason = v_tag || '2' and target_id = v_target;
  select * into l from public.admin_audit_log where reason = v_tag || '2' and target_id = v_target;
  insert into _v values ('player: exactly one audit row', '1', v_n::text, v_n = 1);
  insert into _v values ('player: metadata is changed_fields only',
    '{"changed_fields": ["date_of_birth"]}', l.metadata::text,
    l.metadata = '{"changed_fields": ["date_of_birth"]}'::jsonb
      and (select count(*) from jsonb_object_keys(l.metadata)) = 1);
  perform public.admin_update_user_player_profile(
    v_target, u.date_of_birth, u.primary_position, u.secondary_position, v_tag || '2-restore');

  -- ---- 3. privacy: flip the age visibility only --------------------------
  perform public.admin_update_user_privacy(
    v_target, u.profile_visibility, not u.age_visible, v_tag || '3');
  select count(*) into v_n from public.admin_audit_log where reason = v_tag || '3' and target_id = v_target;
  select * into l from public.admin_audit_log where reason = v_tag || '3' and target_id = v_target;
  insert into _v values ('privacy: exactly one audit row', '1', v_n::text, v_n = 1);
  insert into _v values ('privacy: metadata is changed_fields only',
    '{"changed_fields": ["age_visible"]}', l.metadata::text,
    l.metadata = '{"changed_fields": ["age_visible"]}'::jsonb
      and (select count(*) from jsonb_object_keys(l.metadata)) = 1);
  perform public.admin_update_user_privacy(
    v_target, u.profile_visibility, u.age_visible, v_tag || '3-restore');

  -- ---- 4. Default Location: set it, or clear it -------------------------
  perform public.admin_update_user_default_wilayat(
    v_target, case when u.default_wilayat_code is null then v_wilayat else null end, v_tag || '4');
  select count(*) into v_n from public.admin_audit_log where reason = v_tag || '4' and target_id = v_target;
  select * into l from public.admin_audit_log where reason = v_tag || '4' and target_id = v_target;
  insert into _v values ('location: exactly one audit row', '1', v_n::text, v_n = 1);
  insert into _v values ('location: metadata is changed_fields only',
    '{"changed_fields": ["default_wilayat_code"]}', l.metadata::text,
    l.metadata = '{"changed_fields": ["default_wilayat_code"]}'::jsonb
      and (select count(*) from jsonb_object_keys(l.metadata)) = 1);
  perform public.admin_update_user_default_wilayat(v_target, u.default_wilayat_code, v_tag || '4-restore');

  -- ---- 5. push preferences: flip match notifications only ----------------
  perform public.admin_update_user_push_preferences(
    v_target, not v_match, v_community, v_mute, v_tag || '5');
  select count(*) into v_n from public.admin_audit_log where reason = v_tag || '5' and target_id = v_target;
  select * into l from public.admin_audit_log where reason = v_tag || '5' and target_id = v_target;
  insert into _v values ('push: exactly one audit row', '1', v_n::text, v_n = 1);
  insert into _v values ('push: metadata is changed_fields only',
    '{"changed_fields": ["match_push"]}', l.metadata::text,
    l.metadata = '{"changed_fields": ["match_push"]}'::jsonb
      and (select count(*) from jsonb_object_keys(l.metadata)) = 1);
  perform public.admin_update_user_push_preferences(
    v_target, v_match, v_community, v_mute, v_tag || '5-restore');

  -- ---- the account is what it was -------------------------------------
  select * into v_now from public.users where id = v_target;
  insert into _v values ('users row restored',
    'same name, phone, dob, positions, privacy, location',
    (v_now.full_name, v_now.phone, v_now.date_of_birth, v_now.primary_position,
     v_now.secondary_position, v_now.profile_visibility, v_now.age_visible,
     v_now.default_wilayat_code)::text,
    (v_now.full_name, v_now.phone, v_now.date_of_birth, v_now.primary_position,
     v_now.secondary_position, v_now.profile_visibility, v_now.age_visible,
     v_now.default_wilayat_code)
    is not distinct from
    (u.full_name, u.phone, u.date_of_birth, u.primary_position,
     u.secondary_position, u.profile_visibility, u.age_visible,
     u.default_wilayat_code));

  select * into v_p_now from public.notification_push_preferences where user_id = v_target;
  insert into _v values ('effective push preferences restored', 'same three switches',
    (coalesce(v_p_now.match_push, true), coalesce(v_p_now.community_push, true),
     coalesce(v_p_now.mute_all, false))::text,
    (coalesce(v_p_now.match_push, true), coalesce(v_p_now.community_push, true),
     coalesce(v_p_now.mute_all, false))
    is not distinct from (v_match, v_community, v_mute));

  -- The RPC can set the defaults but cannot un-create a row.
  if not v_has_prefs then
    delete from public.notification_push_preferences where user_id = v_target;
  end if;

  insert into _v values ('ten audit rows for this run', '10',
    (select count(*)::text from public.admin_audit_log
      where target_id = v_target and reason like v_tag || '%'),
    (select count(*) from public.admin_audit_log
      where target_id = v_target and reason like v_tag || '%') = 10);

  -- The rows themselves, so they are in the result grid.
  insert into _v
    select 'audit row ' || a.reason, 'USER_PROFILE_UPDATED',
           a.action || ' ' || a.metadata::text, a.action = 'USER_PROFILE_UPDATED'
      from public.admin_audit_log a
     where a.target_id = v_target and a.reason like v_tag || '%';
end $$;

-- The guard. One false and the whole batch, changes and audit rows included, is
-- rolled back; nothing is committed.
do $$
begin
  if exists (select 1 from _v where not ok) then
    raise exception E'VERIFICATION FAILED - nothing was kept:\n%',
      (select string_agg(check_name || ': expected ' || expected || ', got ' || actual, E'\n')
         from _v where not ok);
  end if;
end $$;

select * from _v order by check_name;
```

Expected: every `ok` is `true`; the grid ends with ten `audit row verify-…` lines, each `USER_PROFILE_UPDATED` with a single-field `changed_fields`, the `-restore` row naming the same field as its pair.

## 7 — The audit log reads it (read only)

The log's read RPC does not filter by action, so the new rows must come back. It returns no metadata, by design (`0068`), which is why the console shows the label and not the field names.

```sql
-- step:7
select set_config('request.jwt.claim.sub', '<ADMIN_ID>', true);
select set_config('request.jwt.claims',
  json_build_object('sub', '<ADMIN_ID>', 'role', 'authenticated')::text, true);

select action, target_label_snapshot, reason, created_at
  from public.admin_list_audit_log(20)
 where action = 'USER_PROFILE_UPDATED'
 order by created_at desc, reason;
```

Expected: the ten rows from step 6 (and any earlier real edits), action `USER_PROFILE_UPDATED`.

## 8 — Through the staging front end

After steps 0 to 7 pass, with the staging build pointed at this database, signed in as the System Admin:

1. Admin → Users → the test account → **Account data** shows every field, including sign-in method, email confirmed and last sign-in. An empty date of birth reads *Not set*.
2. **Edit account** is offered. Change the test account's phone in *Name and phone*, add a reason, Save. The section shows the new phone after returning. Change it back.
3. Open the System Admin's **own** account from the list: the section shows its data and **no edit entry**, with the sentence saying why.
4. Admin → Audit Log shows **Account updated** rows for the test account, with the reasons given.
5. Open the Users list and the Audit Log in Arabic once; the new labels read in Arabic.
6. With the network off, open an account: the rest of the screen loads or fails as it always did, and the Account data section, if it failed, offers Retry.

Record the result of each step in the report. Anything that is not `true` or not as described is a stop.
