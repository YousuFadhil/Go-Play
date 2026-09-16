import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/analytics/analytics_models.dart';

/// What migration 0078 says — a static review of the file, not a runtime
/// result.
///
/// The migration cannot be executed from a widget test, so these assertions
/// read the text, exactly as `analytics_migration_test.dart` reads `0067`.
/// That is a real limit and worth stating plainly: this suite proves the file
/// says the right things, and a live precheck is what proves the database does
/// them.
///
/// What it does catch is the class of mistake that is invisible in review and
/// expensive in production — a grant to `anon` that should not be there, a
/// column that should not be reachable, a `security definer` function with no
/// pinned `search_path`, a writer that stopped taking its actor from the
/// session.
void main() {
  // Normalised on the way in: Git checks this file out with CRLF endings on
  // Windows, and several assertions below span two lines.
  final sql = File(
    '../supabase/migrations/0078_package_five_public_sharing.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with every SQL string literal blanked as well — the `comment on`
  /// bodies legitimately name things the migration does not touch.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// The body of one `create ... function public.<name>(`, up to its `$$;`.
  String functionBody(String name) {
    final start = statements.indexOf('function public.$name(');
    expect(start, isNot(-1), reason: '$name is not created by this migration');
    final end = statements.indexOf(r'$$;', start);
    expect(end, isNot(-1), reason: '$name has no body');
    return statements.substring(start, end);
  }

  group('the public surface is exactly four functions', () {
    /// The only relations migration 0078 may hand to `anon`.
    const publicContracts = [
      'public_player_profile(uuid)',
      'public_player_recent_form(uuid, int)',
      'public_player_recent_highlight(uuid)',
      'public_match_detail(uuid)',
    ];

    test('each one is granted to anon', () {
      for (final contract in publicContracts) {
        expect(
          statements,
          contains('grant execute on function public.$contract\n'
              '  to anon, authenticated, service_role;'),
          reason: '$contract is not granted to anon',
        );
      }
    });

    test('and nothing else in the file is', () {
      // Every `to anon` in the migration, counted. Four grants, and the four
      // above are which four — so a fifth would have to be added here
      // deliberately rather than slipping in.
      final grantsToAnon =
          RegExp(r'grant execute[^;]*to anon').allMatches(executable).length;
      expect(grantsToAnon, publicContracts.length);

      // No table, view or sequence privilege reaches anon at all: every grant
      // in this file is on a function.
      expect(
        RegExp(r'grant select[^;]*anon').hasMatch(executable),
        isFalse,
        reason: 'anon must gain no relation, only the four functions',
      );
      expect(
        RegExp(r'grant (insert|update|delete)').hasMatch(executable),
        isFalse,
        reason: 'no write privilege is granted to anybody here',
      );
    });

    test('the authenticated-only football internals are not opened up', () {
      // The named things the approved architecture forbids granting to anon.
      // Asserted by name because that is what a reviewer would look for.
      for (final protected in [
        'player_profile(uuid)',
        'v_football_completed_matches',
        'v_football_match_lineup',
        'v_football_match_participants',
        'v_football_community_player_stats',
        'community_period_xi_evidence',
        'community_period_xi_window',
      ]) {
        expect(
          RegExp('grant[^;]*$protected[^;]*anon').hasMatch(executable),
          isFalse,
          reason: '$protected must not become anon-readable',
        );
      }

      // `player_profile` is mentioned in prose and must not be executed
      // against, re-granted or replaced.
      expect(
          executable,
          isNot(contains('drop function if exists '
              'public.player_profile')));
    });

    test('the two internal reads stay behind a session', () {
      for (final internal in [
        'player_recent_form(uuid, int)',
        'player_recent_mvp(uuid)',
      ]) {
        // The statement is wrapped at different points for the two names, so
        // the whitespace between the clauses is what varies and nothing else.
        expect(
          statements.replaceAll(RegExp(r'\s+'), ' '),
          contains('revoke execute on function public.$internal '
              'from anon, public;'),
          reason: '$internal must be revoked from anon',
        );
        expect(
          RegExp('grant execute on function public.'
                  '${RegExp.escape(internal)}[^;]*to anon')
              .hasMatch(executable),
          isFalse,
        );
      }
    });
  });

  group('what the public contracts may return', () {
    /// Every column `public_player_profile` can ever answer with.
    const playerProfileColumns = [
      'user_id uuid',
      'full_name text',
      'primary_position text',
      'secondary_position text',
      'avatar_path text',
      'overall_rating numeric',
      'matches_played int',
      'wins int',
      'losses int',
      'draws int',
      'goals int',
      'mvp_count int',
    ];

    test('the public player profile is an explicit allowlist', () {
      final body = functionBody('public_player_profile');
      for (final column in playerProfileColumns) {
        expect(body, contains(column));
      }
      // No `select *` anywhere in the file: a row type from a table is exactly
      // how a column nobody reviewed becomes public.
      expect(executable, isNot(contains('select *')));
    });

    test('no private column is reachable through any public contract', () {
      for (final name in [
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
        'public_match_detail',
      ]) {
        final body = functionBody(name);
        for (final forbidden in [
          'date_of_birth',
          'phone',
          'email',
          'auth_user_id',
          'join_code',
          'owner_id',
          'created_by',
          'recorded_by',
          'is_system_admin',
          'suspended',
        ]) {
          expect(
            body,
            isNot(contains(forbidden)),
            reason: '$name must not be able to return $forbidden',
          );
        }
      }
    });

    test('the public form carries no fixture identity', () {
      final body = functionBody('public_player_recent_form');
      // It returns a sequence, an outcome, goals and MVP — and deliberately no
      // match id, community id or kick-off time, which is what keeps completed
      // match history behind a session (migration 0057).
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
      expect(returns, contains('sequence_no int'));
      expect(returns, contains('outcome text'));
      expect(returns, isNot(contains('match_id')));
      expect(returns, isNot(contains('community_id')));
      expect(returns, isNot(contains('start_at')));
    });

    test('the public match reads the view rather than copying its filter', () {
      final body = functionBody('public_match_detail');
      expect(body, contains('from v_public_upcoming_matches v'));
      // No second copy of the rule. A filter written out here could drift from
      // the view and start answering for matches discovery would not list.
      expect(body, isNot(contains("status <> 'completed'")));
      expect(body, isNot(contains('end_at > now()')));
      // And no roster, result or lineup is joined in.
      for (final table in [
        'match_registrations',
        'match_results',
        'match_team_assignments',
        'match_goals',
      ]) {
        expect(body, isNot(contains(table)));
      }
    });

    test('an inactive player has no public profile, and no error either', () {
      for (final name in [
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
      ]) {
        expect(
          functionBody(name),
          contains('is_active'),
          reason: '$name must answer for active players only',
        );
      }
    });
  });

  group('the security definer conventions are kept', () {
    test('every function in the file pins its search_path', () {
      final definers =
          RegExp(r'security definer').allMatches(statements).length;
      final pinned =
          RegExp(r'set search_path = public').allMatches(statements).length;
      expect(definers, greaterThan(0));
      expect(
        pinned,
        definers,
        reason: 'a security definer function with an unpinned search_path '
            'resolves its own names against a schema a caller controls',
      );
    });

    test('the reads are stable, so none of them can write', () {
      for (final name in [
        'player_recent_form',
        'player_recent_mvp',
        'public_player_profile',
        'public_player_recent_form',
        'public_player_recent_highlight',
        'public_match_detail',
      ]) {
        expect(functionBody(name), contains('stable'), reason: name);
      }
    });

    test('recent form is bounded, whatever it is asked for', () {
      final body = functionBody('player_recent_form');
      expect(
          body, contains('limit least(greatest(coalesce(p_limit, 5), 1), 10)'));
    });

    test('recent form derives its outcome from the existing truth', () {
      final body = functionBody('player_recent_form');
      // The same function `apply_match_statistics` feeds the career counters
      // from. A `case` over the two scores written out here would be a second
      // definition of what a win is.
      expect(body, contains('match_result_contribution(recent.match_id)'));
      expect(body, isNot(contains('team_a_score >')));
    });
  });

  group('analytics keeps its identity requirement', () {
    test('user_id is never made nullable', () {
      expect(executable, isNot(contains('alter column user_id')));
      expect(executable, isNot(contains('drop not null')));
    });

    test('the writer still takes its actor from the session', () {
      final body = functionBody('record_product_event');
      expect(body, contains('v_user_id := auth.uid();'));
      expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
      expect(body, contains('is_current_user_active()'));
      // There is still no user-id argument to point at somebody else.
      expect(body, isNot(contains('p_user_id')));
    });

    test('anon cannot write an event, and there is no second writer', () {
      expect(
        statements,
        contains('revoke execute on function\n'
            '  public.record_product_event(text, uuid, uuid, text, text, '
            'text, text)\n'
            '  from anon, public;'),
      );
      // No other function in this file inserts anything.
      final inserts = RegExp(r'insert into').allMatches(executable).length;
      expect(inserts, 1, reason: 'record_product_event is the only writer');
    });

    test('the share metadata is nullable and constrained', () {
      expect(
        statements,
        contains('add column if not exists share_type text'),
      );
      expect(statements, contains('add column if not exists source text'));
      // Nullable: no existing row is invalidated and no event is blocked for
      // want of a field.
      expect(executable, isNot(contains('share_type text not null')));
      expect(executable, isNot(contains('source text not null')));

      for (final type in ShareType.values) {
        expect(
          statements,
          contains("'${type.wireName}'"),
          reason: '${type.name} is missing from the share_type CHECK',
        );
      }
    });

    test('the event list is restated in full and carries every known name', () {
      final constraint = statements.substring(
        statements.indexOf('add constraint product_events_event_name_check'),
        statements
            .indexOf('comment on column public.product_events.share_type'),
      );
      for (final event in ProductEvent.values) {
        expect(constraint, contains("'${event.wireName}'"));
      }
      // And nothing the application does not know.
      final quoted = RegExp("'[a-z_]+'").allMatches(constraint).length;
      expect(quoted, ProductEvent.values.length);
    });
  });

  group('the migration is additive', () {
    test('it edits no earlier migration file', () {
      final directory = Directory('../supabase/migrations');
      final names = [
        for (final entry in directory.listSync()) entry.uri.pathSegments.last,
      ];
      expect(names, contains('0078_package_five_public_sharing.sql'));
    });

    test('nothing is dropped except the one signature being replaced', () {
      final drops = RegExp(r'drop (table|view|policy|column|trigger|index)')
          .allMatches(executable);
      expect(drops, isEmpty, reason: 'no destructive drop belongs here');

      // The function drop is the signature change `record_product_event`
      // needs, and the constraint drops are the two being re-added.
      expect(
        executable,
        contains('drop function if exists '
            'public.record_product_event(text, uuid, uuid, text, text);'),
      );
    });

    test('it backfills nothing and rewrites nothing', () {
      for (final dml in ['update public.', 'delete from', 'truncate']) {
        expect(executable, isNot(contains(dml)));
      }
    });
  });
}
