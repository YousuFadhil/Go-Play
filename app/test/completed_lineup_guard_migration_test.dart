import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0071 says — a static review of the file, not a runtime
/// result.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so these assertions read the text. That limit is worth stating,
/// as 0069's and 0070's suites state it: this proves the file says the right
/// things, and a live precheck is what proves the database does them.
///
/// The subject is one rule with three cases, and the cases are what a reader
/// gets wrong: a completed match takes only an explicit correction, a
/// generation is never a correction however it is labelled, and an uncompleted
/// match refuses a write that claims to be one.
void main() {
  const path =
      '../supabase/migrations/0071_completed_lineup_regeneration_guard.sql';

  /// Line endings normalized. `core.autocrlf` is `true` here and no
  /// `.gitattributes` rule covers `*.sql`, so a committed migration is checked
  /// out with CRLF while a new one is still LF — and most assertions below span
  /// lines. Without this the suite would pass for whoever wrote the file and
  /// fail for everyone who cloned it, which is exactly what has happened to
  /// `community_logo_test.dart` against migration 0061.
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked, so a `comment on` body cannot
  /// satisfy an assertion about executable text.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// The function's own text, header through body.
  String functionBody() {
    final start =
        statements.indexOf('create or replace function public.replace_match_lineup');
    if (start < 0) throw StateError('0071 does not create replace_match_lineup');
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  final body = functionBody();

  group('the migration is 0071 and only 0071', () {
    test('the file exists under the number the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
    });

    test('exactly one migration file carries this number', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0071'))
          .toList();
      expect(numbered, hasLength(1));
    });

    test('it creates exactly one function and edits no earlier migration', () {
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        1,
      );
      expect(statements, contains('public.replace_match_lineup('));
    });

    test('it adds no table, trigger, view, index or persisted state', () {
      // The function's own inserts and deletes are the lineup write itself and
      // are preserved verbatim; what must not appear is any new schema object
      // for the guard to remember something in. The guard remembers nothing.
      for (final forbidden in [
        'create table',
        'create index',
        'alter table',
        'create type',
        'create view',
        'materialized view',
        'create trigger',
        'create or replace trigger',
        'create sequence',
        'truncate',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
      // Every write the function performs is to the lineup table it already
      // owned.
      final writes = RegExp(r'(?:insert into|delete from)\s+(\w+)')
          .allMatches(statements)
          .map((m) => m.group(1))
          .toSet();
      expect(writes, <String>{'match_team_assignments'});
    });

    test('it changes no policy and no RLS', () {
      expect(statements, isNot(contains('create policy')));
      expect(statements, isNot(contains('drop policy')));
      expect(statements, isNot(contains('row level security')));
    });

    test('it introduces no new helper and no new error token', () {
      // MATCH_COMPLETED and MATCH_NOT_COMPLETED are the vocabulary 0006 and
      // 0029 already established and the client already maps.
      final raised = RegExp("raise exception '([A-Z_]+)'")
          .allMatches(sql)
          .map((m) => m.group(1))
          .toSet();
      expect(
        raised,
        containsAll(<String>{'MATCH_COMPLETED', 'MATCH_NOT_COMPLETED'}),
      );
      expect(
        raised.difference(<String>{
          'NOT_AUTHENTICATED',
          'ACCOUNT_SUSPENDED',
          'MATCH_NOT_FOUND',
          'COMMUNITY_INACTIVE',
          'NOT_AUTHORIZED',
          'MATCH_COMPLETED',
          'MATCH_NOT_COMPLETED',
        }),
        isEmpty,
        reason: '0071 invents no error token',
      );
    });
  });

  group('the signature, and the overload it replaces', () {
    test('the old three-argument function is dropped first', () {
      expect(
        statements,
        contains(
            'drop function if exists public.replace_match_lineup(uuid, jsonb, boolean);'),
      );
      // Before the new one is created, or both would exist and every
      // three-argument call would be ambiguous rather than convenient.
      expect(
        statements.indexOf('drop function if exists'),
        lessThan(statements.indexOf('create or replace function')),
      );
    });

    test('the final signature takes four arguments', () {
      expect(
        statements,
        contains('create or replace function public.replace_match_lineup(\n'
            '  p_match_id uuid,\n'
            '  p_assignments jsonb,\n'
            '  p_from_generation boolean default false,\n'
            '  p_completed_correction boolean default false\n'
            ')'),
      );
    });

    test('old two- and three-argument clients default to non-correction', () {
      // Both new-ish parameters carry `default false`, so a client that names
      // neither resolves here with `p_completed_correction => false` — and is
      // therefore refused on a completed match. That is the safe direction and
      // it is deliberate: an obsolete build keeps everything it could do except
      // rewrite history.
      expect(body, contains('p_completed_correction boolean default false'));
      expect(body, contains('p_from_generation boolean default false'));
      expect(sql, contains('default to p_completed_correction'));
    });
  });

  group('the completed-match rule', () {
    test('completion is the stored status or the clock', () {
      expect(
        body,
        contains(
            "v_completed := v_match.status = 'completed' or v_match.end_at <= now();"),
      );
      // Read from the row the function already locked, so the answer is stable
      // for the rest of the transaction.
      expect(
        body,
        contains('select * into v_match from matches where id = p_match_id for update;'),
      );
    });

    test('an ordinary write onto a completed match is refused', () {
      expect(
        body,
        contains('if not coalesce(p_completed_correction, false) then\n'
            "      raise exception 'MATCH_COMPLETED';"),
      );
    });

    test('a generation onto a completed match is refused', () {
      expect(
        body,
        contains('if coalesce(p_from_generation, false) then\n'
            "      raise exception 'MATCH_COMPLETED';"),
      );
      // Tested before the correction flag, so declaring both does not admit it.
      final generation = body.indexOf('coalesce(p_from_generation, false) then');
      final correction =
          body.indexOf('if not coalesce(p_completed_correction, false) then');
      expect(generation, lessThan(correction));
    });

    test('a correction claimed on an uncompleted match is refused', () {
      expect(
        body,
        contains('if coalesce(p_completed_correction, false) then\n'
            "      raise exception 'MATCH_NOT_COMPLETED';"),
      );
    });

    test('a null flag is read as no intent, never as consent', () {
      // `if p_completed_correction then` would be unknown rather than true and
      // `if not p_completed_correction then` unknown rather than the refusal it
      // has to be, so a null would have slipped past the guard entirely.
      expect(
        RegExp(r'coalesce\(p_completed_correction, false\)')
            .allMatches(body)
            .length,
        2,
      );
      expect(
        RegExp(r'coalesce\(p_from_generation, false\)').allMatches(body).length,
        1,
      );
    });

    test('the guard runs before anything is mutated', () {
      final guard = body.indexOf('v_completed :=');
      for (final mutation in [
        'update match_team_assignments',
        'perform assert_result_survives_lineup',
        'perform detach_match_effects',
        'delete from match_team_assignments',
        'insert into match_team_assignments',
        'perform assign_professional_guest_teams',
        'perform attach_match_effects',
      ]) {
        final at = body.indexOf(mutation);
        expect(at, greaterThan(-1), reason: '$mutation is still performed');
        expect(guard, lessThan(at), reason: '$mutation must follow the guard');
      }
    });

    test('authorization still precedes the guard', () {
      // A caller with no business here learns nothing about the match's state.
      final authorized = body.indexOf('is_match_community_admin');
      expect(authorized, lessThan(body.indexOf('v_completed :=')));
      expect(body.indexOf('auth.uid() is null'), lessThan(authorized));
    });
  });

  group('everything else about the write is preserved', () {
    test('0058 and 0059 guest behaviour is intact', () {
      for (final preserved in [
        'if p_from_generation then',
        'set team_manually_overridden = false',
        'assigned_position = null',
        'perform assign_professional_guest_teams(p_match_id);',
      ]) {
        expect(body, contains(preserved));
      }
    });

    test('the result guard and the effect detach/attach are intact', () {
      expect(
        body,
        contains('perform assert_result_survives_lineup(\n'
            '    p_match_id, v_user_ids, v_surviving_guest_ids);'),
      );
      expect(body, contains('perform detach_match_effects(p_match_id);'));
      expect(body, contains('perform attach_match_effects(p_match_id);'));
    });

    test('0065 suspension guards are intact', () {
      expect(body, contains("raise exception 'ACCOUNT_SUSPENDED'"));
      expect(body, contains("raise exception 'COMMUNITY_INACTIVE'"));
    });
  });

  group('security characteristics are unchanged', () {
    test('it is a definer with a pinned search path', () {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, isNot(contains('security invoker')));
    });

    test('the recreated function is revoked and granted afresh', () {
      // The drop took the privileges with it: `create or replace` would have
      // kept them, and a dropped-and-recreated function starts with EXECUTE for
      // PUBLIC.
      expect(
        statements,
        contains('revoke execute on function\n'
            '  public.replace_match_lineup(uuid, jsonb, boolean, boolean) from anon, public;'),
      );
      expect(
        statements,
        contains('grant execute on function\n'
            '  public.replace_match_lineup(uuid, jsonb, boolean, boolean) to authenticated;'),
      );
    });

    test('no wider audience is granted', () {
      expect(executable, isNot(contains('to anon')));
      expect(executable, isNot(contains('to public')));
      expect(executable, isNot(contains('to service_role')));
      expect(
        RegExp('grant execute on function').allMatches(statements).length,
        1,
      );
    });
  });
}
