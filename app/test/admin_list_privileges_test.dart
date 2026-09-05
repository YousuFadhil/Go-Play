import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0066 says about privileges — a static review, not a runtime
/// result.
///
/// It exists because of a real regression. `0066` drops and recreates both
/// Admin list functions so they can return the suspension columns, and
/// `DROP FUNCTION` takes the whole ACL with it — including grants no migration
/// ever wrote. `0017` granted only `authenticated`, so the migration history
/// makes `authenticated` look like the whole story; the live ACL also carries
/// `service_role`, put there by Supabase's default-privileges rule on schema
/// `public`. Restoring only `authenticated` silently removed it.
///
/// These assertions are what stops that happening again the next time somebody
/// changes one of these functions' return shape.
void main() {
  final sql =
      File('../supabase/migrations/0066_platform_admin_suspension_read_model.sql')
          .readAsStringSync();

  const functions = [
    'public.admin_list_users(text)',
    'public.admin_list_communities(text)',
  ];

  group('0066 restores every execute privilege it drops', () {
    for (final fn in functions) {
      test('$fn is dropped and recreated', () {
        expect(sql, contains('drop function if exists $fn;'));
        // Recreated as a plain `create function`: `create or replace` cannot
        // change a return type, which is the whole reason for the drop.
        expect(sql, contains('create function ${fn.replaceFirst('(text)', '(p_search text default null)')}'));
      });

      test('$fn grants authenticated', () {
        expect(sql, contains('grant execute on function $fn to authenticated;'));
      });

      test('$fn grants service_role — the privilege the drop would remove', () {
        expect(
          sql,
          contains('grant execute on function $fn to service_role;'),
          reason: 'DROP FUNCTION removes the ACL, and the live grant to '
              'service_role comes from Supabase default privileges rather than '
              'from any migration. Without this line, applying 0066 takes it '
              'away.',
        );
      });

      test('$fn revokes anon and PUBLIC, and grants neither', () {
        expect(sql, contains('revoke execute on function $fn from anon, public;'));
        expect(sql, isNot(contains('grant execute on function $fn to anon')));
        expect(sql, isNot(contains('grant execute on function $fn to public')));
      });
    }

    test('the gate, the definer model and the search path are untouched', () {
      // Counted in statement position only: the prose above uses several of
      // these words, and a comment saying "stable" is not a volatility marker.
      final statements = sql
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .map((line) => line.trim())
          .toList();

      int exactly(String token) =>
          statements.where((line) => line == token).length;

      // Two functions, each carrying all four properties.
      expect(
        statements
            .where((line) => line.contains('if not is_system_admin() then'))
            .length,
        2,
      );
      expect(exactly('security definer'), 2);
      expect(exactly('stable'), 2);
      expect(exactly('set search_path = public'), 2);
    });

    test('nothing outside the two list functions is written', () {
      // No suspension write, no delete, no policy, no storage rule, and no DML
      // against production rows.
      for (final forbidden in [
        'admin_suspend_',
        'admin_reactivate_',
        'admin_delete_',
        'create policy',
        'drop policy',
        'alter table',
        'insert into',
        'update ',
        'delete from',
      ]) {
        // Comments are allowed to name these; statements are not. Only
        // statement-position text is examined.
        final statements = sql
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('--'))
            .join('\n');
        expect(statements, isNot(contains(forbidden)),
            reason: '0066 is a read-model change only');
      }
    });
  });
}
