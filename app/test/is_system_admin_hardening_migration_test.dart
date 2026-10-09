import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract checks for migration 0098.
///
/// These tests inspect the SQL text; they do not prove PostgreSQL authorization
/// behavior. The release gate also requires an offline database execution test.
void main() {
  final sql =
      File('../supabase/migrations/0098_harden_is_system_admin_search_path.sql')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n')
          .toLowerCase();

  test('the existing System Admin predicate is replaced, not dropped', () {
    expect(
        sql, contains('create or replace function public.is_system_admin()'));
    expect(sql, contains('returns boolean'));
    expect(sql, contains('language sql'));
    expect(sql, contains('stable'));
    expect(sql, contains('security definer'));
    expect(sql, isNot(contains('drop function')));
  });

  test('only the fully qualified membership table may answer authorization',
      () {
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('from public.system_admins sa'));
    expect(sql, contains('sa.user_id = auth.uid()'));
    expect(sql, isNot(contains('from system_admins')));
  });

  test('the existing EXECUTE roles are preserved', () {
    expect(
      sql,
      contains(
          'revoke execute on function public.is_system_admin() from public, anon;'),
    );
    expect(
      sql,
      contains('grant execute on function public.is_system_admin()'),
    );
    expect(sql, contains('to authenticated, service_role;'));
    expect(sql, isNot(contains('to anon;')));
  });

  test('no tables, policies or account records are modified', () {
    for (final forbidden in [
      'alter table',
      'drop table',
      'create table',
      'create policy',
      'drop policy',
      'insert into',
      'update public.',
      'delete from',
      'truncate ',
      'alter default privileges',
    ]) {
      expect(sql, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
