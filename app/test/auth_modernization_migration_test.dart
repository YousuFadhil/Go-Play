import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract for migration 0092 (authentication modernization).
///
/// The migration is reviewed before it is applied to the shared live project, so
/// what it may and may not do is pinned here against the file itself. The
/// behaviour of the SQL was also exercised against a disposable Postgres; what
/// this file keeps true from then on is the *shape* that behaviour depends on:
/// the grants, the search paths, the parameters that are not there, and the
/// tokens the application maps.
void main() {
  const path = '../supabase/migrations/0092_auth_modernization.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // Comment lines stripped: the prose may name what the SQL refuses to do.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  // Whitespace collapsed, so a multi-line statement can be asserted whole.
  final flat = statements.replaceAll(RegExp(r'\s+'), ' ');

  String functionBody(String name) {
    final start =
        statements.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('$name is not created');
    final end = statements.indexOf('\n\$\$;', start);
    if (end < 0) throw StateError('$name body is not closed');
    return statements.substring(start, end);
  }

  String flatFunction(String name) =>
      functionBody(name).replaceAll(RegExp(r'\s+'), ' ');

  Set<String> parametersOf(String name) {
    final body = functionBody(name);
    final open = body.indexOf('(');
    final close = body.indexOf(')\nreturns');
    return RegExp(r'\b(p_[a-z_]+)\b')
        .allMatches(body.substring(open, close))
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// The column list of the one `insert into ... users (...)` in [body].
  List<String> insertedColumns(String body) {
    final match = RegExp(r'insert into (?:public\.)?users \(([^)]*)\)')
        .firstMatch(body.replaceAll(RegExp(r'\s+'), ' '));
    if (match == null) throw StateError('no insert into users');
    return match.group(1)!.split(',').map((c) => c.trim()).toList();
  }

  test('0092 is the one auth migration, and the CLI name was reconciled', () {
    final names = Directory('../supabase/migrations')
        .listSync()
        .map((entry) => entry.uri.pathSegments.last)
        .toList();

    expect(names.where((n) => n.startsWith('0092')),
        ['0092_auth_modernization.sql']);
    expect(names.where((n) => RegExp(r'^\d{14}_').hasMatch(n)), isEmpty,
        reason: 'the CLI\'s timestamp name was renamed into the 4-digit '
            'sequence, not kept beside it');
    expect(names.where((n) => n.startsWith('0091')), isNotEmpty,
        reason: 'appended after 0091, not written over it');
  });

  test('it changes no schema, no policy and no existing row', () {
    for (final forbidden in [
      'alter table',
      'create table',
      'drop table',
      'drop function',
      'drop policy',
      'create policy',
      'alter policy',
      'truncate',
      'delete from',
      'update users',
      'update public.users',
    ]) {
      expect(flat.toLowerCase(), isNot(contains(forbidden)),
          reason: forbidden);
    }
  });

  test('the two-way suspension predicate is not touched', () {
    expect(flat, isNot(contains('function public.is_current_user_active')));
    expect(flat, isNot(contains('is_current_user_active()')),
        reason: 'not even called: the new function answers a different '
            'question and gates nothing');
  });

  group('handle_new_user()', () {
    test('is still a security definer trigger function with a pinned path', () {
      final body = flatFunction('handle_new_user');
      expect(body, contains('returns trigger'));
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    });

    test('stays unreachable through the API', () {
      expect(
        flat,
        contains('revoke execute on function public.handle_new_user() '
            'from anon, authenticated, public;'),
      );
      expect(flat, isNot(contains('grant execute on function public.handle_new_user')));
    });

    test('creates a profile only from a complete, valid set of metadata', () {
      final body = flatFunction('handle_new_user');

      // Every input is checked, and the row is written only after all of them.
      expect(body, contains("v_name = ''"));
      expect(body, contains(r"v_phone !~ '^\+968[0-9]{8}$'"));
      expect(body, contains("v_primary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains("v_secondary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains('v_secondary = v_primary'));
      expect(body, contains("v_dob_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}\$'"));
      expect(body, contains("date '1900-01-01'"));
      expect(body, contains('current_date + 1'));
      expect(body.indexOf('insert into'),
          greaterThan(body.indexOf("date '1900-01-01'")),
          reason: 'the insert comes after every check');
    });

    test('no longer invents a position, a phone, a name or a date', () {
      final body = flatFunction('handle_new_user');

      // The three defaults the old trigger wrote: '' for phone, '' for name and
      // 'MID' for position, each behind a coalesce.
      expect(body, isNot(matches(RegExp(r"coalesce\([^)]*'MID'\)"))));
      expect(body, isNot(contains("'phone', ''), '')")));
      // Absent still reads as '' so the checks can run on it, but '' fails
      // them: nothing that was missing is ever *written*. The date in
      // particular is only ever the result of a cast that was validated.
      expect(body, contains('v_dob := v_dob_text::date'));
      expect(body, isNot(matches(RegExp(r'v_dob\s*:=\s*coalesce'))));
    });

    test('never fails the sign-up: it returns instead of raising', () {
      final body = flatFunction('handle_new_user');

      expect(body, isNot(contains('raise exception')));
      expect(body, contains('return new;'));
      // The one cast that can raise is contained.
      expect(body, contains('exception when others then'));
    });

    test('is keyed to the metadata, not to a provider', () {
      final body = flatFunction('handle_new_user').toLowerCase();

      for (final provider in [
        'google',
        'provider',
        'app_metadata',
        'identities',
        'oauth',
      ]) {
        expect(body, isNot(contains(provider)), reason: provider);
      }
    });

    test('writes exactly the columns it always wrote, and no rating', () {
      final columns = insertedColumns(functionBody('handle_new_user'));

      expect(columns, [
        'id',
        'phone',
        'full_name',
        'primary_position',
        'date_of_birth',
        'secondary_position',
      ]);
      expect(columns, isNot(contains('overall_rating')),
          reason: 'OP-1: the column default sets it');
      expect(columns, isNot(contains('is_active')));
    });
  });

  group('get_my_account_state()', () {
    test('takes no argument, so it cannot be asked about anybody else', () {
      expect(flat, contains('function public.get_my_account_state() returns text'));
    });

    test('is security definer, stable, and pins its search path', () {
      final body = flatFunction('get_my_account_state');
      expect(body, contains('security definer'));
      expect(body, contains(' stable '));
      expect(body, contains('set search_path = public'));
    });

    test('answers about the caller only, and raises with no session', () {
      final body = flatFunction('get_my_account_state');

      expect(body, contains('auth.uid()'));
      expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(body, contains('where u.id = auth.uid()'));
    });

    test('has exactly three answers', () {
      final body = flatFunction('get_my_account_state');

      expect(body, contains("'PROFILE_REQUIRED'"));
      expect(body, contains("'ACTIVE'"));
      expect(body, contains("'SUSPENDED'"));
      expect(body, contains('when v_active then'));
    });

    test('reads and writes nothing else', () {
      final body = flatFunction('get_my_account_state');

      expect(body, isNot(contains('insert ')));
      expect(body, isNot(contains('update ')));
      expect(body, isNot(contains('delete ')));
    });

    test('is executable by signed-in users only', () {
      expect(flat, contains('revoke execute on function public.get_my_account_state() from anon, public;'));
      expect(flat, contains('grant execute on function public.get_my_account_state() to authenticated;'));
      expect(flat, isNot(matches(RegExp(
          r'grant execute on function public\.get_my_account_state\(\) to [^;]*\b(anon|public)\b'))));
    });
  });

  group('complete_my_player_profile(...)', () {
    const signature = 'public.complete_my_player_profile(text, text, date, text, text)';

    test('takes the profile and nothing that names a user, a rating, a role or '
        'a state', () {
      expect(parametersOf('complete_my_player_profile'), {
        'p_full_name',
        'p_phone',
        'p_date_of_birth',
        'p_primary_position',
        'p_secondary_position',
      });
    });

    test('acts only for the caller', () {
      final body = flatFunction('complete_my_player_profile');

      expect(body, contains('v_uid uuid := auth.uid()'));
      expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
      // The id it writes is the caller's, never a parameter.
      expect(body, contains('values ( v_uid,'));
    });

    test('is security definer with a pinned search path', () {
      final body = flatFunction('complete_my_player_profile');
      expect(body, contains('returns void'));
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    });

    test('writes only the profile, leaving rating, state and privacy to the '
        'column defaults', () {
      final columns = insertedColumns(functionBody('complete_my_player_profile'));

      expect(columns, [
        'id',
        'phone',
        'full_name',
        'primary_position',
        'date_of_birth',
        'secondary_position',
      ]);
      for (final system in [
        'overall_rating',
        'is_active',
        'suspended_at',
        'suspended_by',
        'suspension_reason',
        'profile_visibility',
        'age_visible',
        'avatar_path',
      ]) {
        expect(columns, isNot(contains(system)), reason: system);
      }
    });

    test('refuses a second profile, atomically', () {
      final body = flatFunction('complete_my_player_profile');

      expect(body, contains("raise exception 'PROFILE_ALREADY_EXISTS'"));
      expect(body, contains('on conflict (id) do nothing'));
      expect(body, contains('if not found then'));
      expect(body, isNot(contains('do update')),
          reason: 'a creation path: it never overwrites a row');
    });

    test('validates every input it is given', () {
      final body = flatFunction('complete_my_player_profile');

      expect(body, contains('char_length(v_name) < 2'));
      expect(body, contains("raise exception 'INVALID_FULL_NAME'"));
      expect(body, contains(r"v_phone !~ '^\+968[0-9]{8}$'"));
      expect(body, contains("raise exception 'INVALID_PHONE'"));
      expect(body, contains('p_date_of_birth is null'));
      expect(body, contains("date '1900-01-01'"));
      expect(body, contains('current_date + 1'));
      expect(body, contains("raise exception 'INVALID_DATE_OF_BIRTH'"));
      expect(body, contains("v_primary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains("v_secondary not in ('GK', 'DEF', 'MID', 'FWD')"));
      expect(body, contains('v_secondary = v_primary'),
          reason: 'BTGE-SC-6: a secondary position is a different position');
      expect(body, contains("raise exception 'INVALID_POSITION'"));
    });

    test('is executable by signed-in users only', () {
      expect(flat, contains('revoke execute on function $signature from anon, public;'));
      expect(flat, contains('grant execute on function $signature to authenticated;'));
      expect(flat, isNot(matches(RegExp(
          r'grant execute on function public\.complete_my_player_profile\([^)]*\) to [^;]*\b(anon|public)\b'))));
    });
  });

  test('every outcome the SQL raises is one the application maps', () {
    final mapper = File(
            'lib/infrastructure/supabase/supabase_failure_mapper.dart')
        .readAsStringSync();
    final raised = RegExp(r"raise exception '([A-Z_]+)'")
        .allMatches(statements)
        .map((m) => m.group(1)!)
        .toSet();

    expect(raised, {
      'NOT_AUTHENTICATED',
      'PROFILE_ALREADY_EXISTS',
      'INVALID_FULL_NAME',
      'INVALID_PHONE',
      'INVALID_DATE_OF_BIRTH',
      'INVALID_POSITION',
    });
    for (final token in raised) {
      expect(mapper, contains("'$token':"), reason: token);
    }
  });

  test('the application calls exactly what the SQL defines', () {
    final adapter =
        File('lib/infrastructure/supabase/supabase_auth_adapter.dart')
            .readAsStringSync();

    expect(adapter, contains("rpc('get_my_account_state')"));
    expect(adapter, contains("rpc('complete_my_player_profile'"));
    final sent = RegExp(r"'(p_[a-z_]+)':")
        .allMatches(adapter)
        .map((m) => m.group(1)!)
        .toSet();
    expect(sent, parametersOf('complete_my_player_profile'),
        reason: 'the client sends every parameter and no other');
  });

  group('rollback', () {
    final rollback =
        File('../supabase/rollback/0092_auth_modernization_rollback.sql')
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
    final rollbackStatements = rollback
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n')
        .replaceAll(RegExp(r'\s+'), ' ');

    test('restores the trigger body as 0021 left it', () {
      final original = File(
              '../supabase/migrations/0021_signup_profile_inputs.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n')
          .replaceAll(RegExp(r'\s+'), ' ');

      final body = RegExp(r'create or replace function public\.handle_new_user\(\).*?\$\$;')
          .firstMatch(original)!
          .group(0)!;
      expect(rollbackStatements, contains(body));
    });

    test('removes the two functions and touches no row', () {
      expect(rollbackStatements, contains(
          'drop function if exists public.complete_my_player_profile(text, text, date, text, text);'));
      expect(rollbackStatements,
          contains('drop function if exists public.get_my_account_state();'));
      for (final forbidden in ['delete from', 'update ', 'truncate', 'alter table']) {
        expect(rollbackStatements.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });
  });
}
