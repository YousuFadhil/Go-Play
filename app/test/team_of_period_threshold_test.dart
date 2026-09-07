import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/time_format.dart';

/// The three staging corrections that are rules rather than screens: the
/// participation bar, and the way a period's dates are written.
///
/// The bar is a migration, so it is reviewed as text and restated as
/// arithmetic. The dates are a formatter, so they are pumped and read.
void main() {
  const path = '../supabase/migrations/'
      '0072_team_of_period_participation_threshold.sql';
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked: the function comment
  /// legitimately *names* the rule in prose, and an assertion about the
  /// executable text must not be satisfied by that.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  group('the participation bar is one rule for both periods', () {
    test('the migration is 0072 and replaces only the threshold', () {
      expect(File(path).existsSync(), isTrue);
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        1,
      );
      expect(statements, contains('public.period_xi_required_matches('));

      // Eligibility only. Nothing about the ranking, the form score, the
      // evidence queries or the read-path signatures moves with it.
      for (final untouched in [
        'period_form_score_v1',
        'period_goal_form_v1',
        'community_period_xi_evidence',
        'community_period_xi_window',
        'community_period_xi_matches',
        'last_completed_statistics_period',
        'create table',
        'create trigger',
        'create policy',
        'row level security',
      ]) {
        expect(statements, isNot(contains(untouched)), reason: untouched);
      }
    });

    test('it keeps the signature, the pinning and the revocations', () {
      expect(
        statements,
        contains('create or replace function public.period_xi_required_matches(\n'
            '  p_period_type text,\n'
            '  p_qualifying_matches int\n'
            ')'),
      );
      expect(statements, contains('immutable'));
      expect(statements, contains('set search_path = public'));
      expect(
        statements,
        contains('revoke execute on function public.period_xi_required_matches'
            '(text, int)\n  from anon, authenticated, public;'),
      );
      expect(statements, isNot(contains('grant execute')));
    });

    test('an empty period still asks for nothing', () {
      expect(
        statements,
        contains('when coalesce(p_qualifying_matches, 0) <= 0 then 0'),
      );
    });

    test('the bar is integer arithmetic, never a float', () {
      // `0.4` is not representable in binary, so `ceil(0.4 * 5)` can return 3
      // on a value that is 2.0000000000000004 -- a threshold one too high,
      // which silently excludes a player who qualified.
      expect(statements, contains('(2 * p_qualifying_matches + 4) / 5'));
      expect(executable, isNot(contains('0.4')));
      expect(executable, isNot(contains('ceil(')));
      expect(executable, isNot(contains('::numeric')));
    });

    test('nothing branches on the kind of period any more', () {
      // The parameter survives because every caller passes it; the rule no
      // longer reads it.
      final body = statements.substring(
        statements.indexOf('as \$\$'),
        statements.indexOf('\n\$\$;'),
      );
      expect(body, isNot(contains("'weekly'")));
      expect(body, isNot(contains("'monthly'")));
    });

    test('the approved table, 0 through 30', () {
      // The SQL expression restated. `~/` is integer division, so this is the
      // arithmetic the database performs.
      int required(int n) => n <= 0 ? 0 : (2 * n + 4) ~/ 5;

      const expected = {
        0: 0,
        1: 1,
        2: 1,
        3: 2,
        4: 2,
        5: 2,
        6: 3,
        7: 3,
        10: 4,
        14: 6,
        30: 12,
      };
      expected.forEach((n, bar) {
        expect(required(n), bar, reason: '$n qualifying matches');
      });
    });

    test('it is ceil(40%) for every count, not just the listed ones', () {
      int required(int n) => n <= 0 ? 0 : (2 * n + 4) ~/ 5;
      for (var n = 1; n <= 200; n++) {
        expect(required(n), (2 * n / 5).ceil(), reason: '$n');
      }
    });

    test('weekly and monthly ask for the same thing', () {
      // The whole point: five matches ask for two however long the community
      // took to play them.
      int required(String periodType, int n) =>
          n <= 0 ? 0 : (2 * n + 4) ~/ 5;
      for (var n = 0; n <= 40; n++) {
        expect(required('weekly', n), required('monthly', n), reason: '$n');
      }
    });

    test('a one-of-five player is out and a two-of-five player is in', () {
      // The staging case that prompted the change.
      int required(int n) => n <= 0 ? 0 : (2 * n + 4) ~/ 5;
      expect(required(5), 2);
      expect(1 >= required(5), isFalse, reason: 'one of five is ineligible');
      expect(2 >= required(5), isTrue, reason: 'two of five is eligible');
    });
  });

  group('a period range is written so both languages can read it', () {
    /// The visible text, with the bidi controls removed. They are how the
    /// fragments are placed and not part of what anybody sees.
    String visible(String text) =>
        text.replaceAll(RegExp('[\u2066-\u2069]'), '');

    Future<String> range(WidgetTester tester, Locale locale) async {
      late String formatted;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          formatted = formatAwardWeek(
            context,
            DateTime.utc(2026, 8, 30, 20), // Muscat midnight, 31 August
            DateTime.utc(2026, 9, 6, 20), // exclusive: through 6 September
          );
          return const SizedBox.shrink();
        }),
      ));
      await tester.pump();
      return formatted;
    }

    testWidgets('English reads left to right', (tester) async {
      expect(visible(await range(tester, const Locale('en'))),
          'Aug 31 – Sep 6');
    });

    testWidgets('Arabic keeps the day with its month, in order',
        (tester) async {
      final text = visible(await range(tester, const Locale('ar')));

      // Day then month within each fragment, and the start before the end --
      // the reordering the LTR-wrapped form produced is what this pins.
      expect(text, '31 أغسطس – 6 سبتمبر');
    });

    testWidgets('each date is isolated, and the pair is not forced LTR',
        (tester) async {
      final raw = await range(tester, const Locale('ar'));

      // First Strong Isolate around each date; no LTR isolate around the whole
      // range, which is what pulled the Arabic fragments apart.
      expect(raw.split('\u2068'), hasLength(3), reason: 'one per date');
      expect(raw, isNot(contains('\u2066')));
      expect(raw, contains('–'), reason: 'an en dash, not a hyphen');
      expect(raw, isNot(contains(' - ')));
    });

    testWidgets('the end stays exclusive', (tester) async {
      // 7 September is the instant the week ends and the first day it does not
      // cover.
      expect(visible(await range(tester, const Locale('en'))),
          isNot(contains('Sep 7')));
    });

    test('the formatter derives no period of its own', () {
      final source = File('lib/core/time_format.dart').readAsStringSync();
      final award = source.substring(source.indexOf('String formatAwardWeek'));
      expect(award, isNot(contains('DateTime.now')));
    });
  });
}
