import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// What migration 0070 says — a static review of the file, not a runtime
/// result.
///
/// The migration has not been applied anywhere and cannot be executed from a
/// widget test, so these assertions read the text. That limit is worth stating,
/// as 0069's suite states it: this proves the file says the right things, and a
/// live precheck is what proves the database does them.
///
/// Cycle 1 builds the Team of Period **evidence** and nothing else, so most of
/// what is checked here is about what the migration refuses to do — no stored
/// award, no selected XI, no trigger, no widened visibility, and no eleven
/// players chosen anywhere.
///
/// Two groups are genuine arithmetic rather than text: the Period Form Score v1
/// components and the normalized metrics. Those are rules with examples, the
/// examples are the specification, and a test that only grepped for `0.10`
/// would not notice a cap applied per goal instead of per match.
void main() {
  const path = '../supabase/migrations/0070_team_of_period_evidence.sql';

  /// Line endings normalized, and not as a nicety.
  ///
  /// `core.autocrlf` is `true` in this repository and no `.gitattributes` rule
  /// covers `*.sql`, so the blob is stored with LF and **checked out with
  /// CRLF**. Every migration already committed is CRLF in the working tree;
  /// this one is LF only because it has not been committed yet. Most of the
  /// assertions below span lines, and `contains('a\n  b')` does not match
  /// `'a\r\n  b'` — so without this the suite would pass here and fail for the
  /// next person to clone the repository, which is exactly what has already
  /// happened to `community_logo_test.dart` against migration 0061.
  final sql = File(path).readAsStringSync().replaceAll('\r\n', '\n');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// The same, with SQL string literals blanked. A `comment on` body is a
  /// statement rather than a comment line, and these legitimately *name* the
  /// things the migration leaves alone.
  final executable = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// One function's own text, header through body.
  ///
  /// Called while the groups are declared, so it throws rather than using
  /// `expect` — a matcher outside a test is an `OutsideTestException`.
  String functionBody(String name) {
    final start = statements.indexOf('create or replace function public.$name');
    if (start < 0) throw StateError('0070 does not create $name');
    // The dollar-quote that closes a body, escaped: a bare `$` starts an
    // interpolation in Dart.
    final end = statements.indexOf('\n\$\$;', start);
    return statements.substring(start, end == -1 ? statements.length : end);
  }

  // The seven functions 0070 creates. Two are public read paths; the rest are
  // helpers that exist so a rule is written once and called twice.
  final evidence = functionBody('community_period_xi_evidence');
  final window = functionBody('community_period_xi_window');
  final matches = functionBody('community_period_xi_matches');
  final periodFn = functionBody('last_completed_statistics_period');
  final requiredFn = functionBody('period_xi_required_matches');
  final formScore = functionBody('period_form_score_v1');
  final goalForm = functionBody('period_goal_form_v1');

  /// The body of one named `with` branch of [body], up to the comma that closes
  /// it. Enough to assert that a rule is stated *in the place it belongs*
  /// rather than merely somewhere in a 700-line file.
  String cteIn(String body, String name) {
    // Anchored on the line that opens the branch, so `shape` cannot be found
    // inside `positional_shape` — a negative assertion that quietly read the
    // wrong branch would pass for the wrong reason.
    final opening =
        RegExp('^  (?:with )?$name as \\(', multiLine: true).firstMatch(body);
    if (opening == null) throw StateError('0070 has no `$name` CTE there');
    final start = opening.start;
    // A branch closes either with a comma or, for the last one, with the final
    // select. Stopping at whichever comes first keeps an assertion about one
    // branch from being satisfied by the next.
    final ends = [
      body.indexOf('\n  ),', start),
      body.indexOf('\n  )\n  select', start),
    ].where((index) => index > 0);
    return body.substring(
      start,
      ends.isEmpty ? body.length : ends.reduce(math.min),
    );
  }

  /// A branch of the candidate read path.
  String cte(String name) => cteIn(evidence, name);

  /// A branch of the period-window read path.
  String wcte(String name) => cteIn(window, name);

  group('the migration is 0070 and only 0070', () {
    test('the file exists under the number the brief fixed', () {
      expect(File(path).existsSync(), isTrue);
    });

    test('exactly one migration file carries this number', () {
      final numbered = Directory('../supabase/migrations')
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.startsWith('0070'))
          .toList();
      expect(numbered, hasLength(1));
    });

    test('0001 to 0069 are untouched by this cycle', () {
      // Append-only. The evidence this reads is defined by migrations that
      // already shipped, and re-stating any of them here would give the award
      // a second opinion about football that has already been played.
      for (final untouchable in [
        'statistics_period_zone()\nreturns',
        'statistics_period_key(',
        'match_result_contribution(',
        'match_community_contribution(',
        'apply_match_statistics(',
        'rebuild_community_statistics(',
        'community_statistics_recency(',
        'v_completed_matches',
        'replace_match_lineup(',
        'record_match_result(',
      ]) {
        expect(
          executable,
          isNot(contains('create or replace function public.$untouchable')),
          reason: '0070 adds a read model and redefines nothing',
        );
      }
      expect(executable, isNot(contains('create or replace view')));
    });

    test('both read paths declare and project the same arity', () {
      // A `returns table` that names more or fewer columns than the final
      // select projects is a runtime error on the first call and nothing a
      // static reader notices, so it is counted here rather than discovered by
      // the first person to open the screen.
      int declaredIn(String body) {
        final declaration = body.substring(
          body.indexOf('returns table ('),
          body.indexOf('\n)\nlanguage plpgsql'),
        );
        return declaration
            .split('\n')
            .skip(1)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .length;
      }

      int projectedIn(String body, String from) {
        final projection = body.substring(
          body.lastIndexOf('\n  select\n'),
          body.indexOf(from),
        );
        return projection
            .split('\n')
            .skip(2)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .length;
      }

      expect(declaredIn(evidence), 25);
      expect(projectedIn(evidence, '\n  from totals t'), declaredIn(evidence));
      expect(declaredIn(window), 10);
      expect(projectedIn(window, '\n  from period p'), declaredIn(window));
    });

    test('it creates exactly seven functions', () {
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        7,
      );
      // And the prose at the top says the same number, so a reader is not
      // told there are six.
      expect(sql, contains('Seven functions are added'));
      for (final name in [
        // Two public read paths.
        'public.community_period_xi_evidence(',
        'public.community_period_xi_window(',
        // Five helpers, each existing so a rule is written once.
        'public.community_period_xi_matches(',
        'public.last_completed_statistics_period(',
        'public.period_xi_required_matches(',
        'public.period_form_score_v1(',
        'public.period_goal_form_v1(',
      ]) {
        expect(statements, contains(name));
      }
    });
  });

  group('no award is stored, and nothing is written', () {
    test('there is no Team of Period table and no selected-XI persistence', () {
      for (final forbidden in [
        'team_of_week',
        'team_of_month',
        'team_of_period',
        'period_xi_selection',
        'selected_xi',
      ]) {
        expect(executable, isNot(contains(forbidden)),
            reason: 'the award is calculated, never stored');
      }
    });

    test('it creates no table, view, type, index or trigger', () {
      for (final forbidden in [
        'create table',
        'create index',
        'alter table',
        'create type',
        'create view',
        'materialized view',
        'create trigger',
        'create or replace trigger',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
    });

    test('it writes no row anywhere', () {
      for (final forbidden in [
        'insert into',
        'delete from',
        'truncate',
        'generate_series',
      ]) {
        expect(statements, isNot(contains(forbidden)));
      }
      expect(
        RegExp(r'^\s*update ', multiLine: true).allMatches(statements),
        isEmpty,
      );
    });

    test('it changes no policy and no RLS', () {
      // Community Statistics visibility is exactly what it was: the read model
      // is offered to the same members `community_statistics_select_members`
      // already serves, and no policy is created, dropped or replaced.
      expect(statements, isNot(contains('create policy')));
      expect(statements, isNot(contains('drop policy')));
      expect(statements, isNot(contains('row level security')));
      expect(statements, isNot(contains('grant select on')));
      expect(statements, isNot(contains('grant all on')));
    });
  });

  group('the period is the last completed one, in Asia/Muscat', () {
    test('the period is resolved in exactly one place', () {
      // Both read paths call the same function rather than each computing a
      // boundary, so the window and the candidate list cannot describe
      // different weeks.
      expect(
        evidence,
        contains('from public.last_completed_statistics_period(p_period_type)'),
      );
      expect(
        window,
        contains('from public.last_completed_statistics_period(p_period_type)'),
      );
      // And the arithmetic lives nowhere else.
      expect(evidence, isNot(contains('date_trunc(')));
      expect(window, isNot(contains('date_trunc(')));
      expect(
        RegExp("date_trunc\\('week'").allMatches(statements).length,
        2,
        reason: 'the running week is computed once, and stepped back from',
      );
    });

    test('the zone is the frozen one and is never restated', () {
      expect(periodFn, contains('public.statistics_period_zone()'));
      // Not a literal beside it. Two statements of the zone are two chances to
      // bucket a match into different weeks.
      expect(executable, isNot(contains('Asia/Muscat')));
    });

    test('weekly is the previous completed ISO week', () {
      expect(
        periodFn,
        contains(
            "v_start := (date_trunc('week', v_muscat_now) - interval '7 days')"),
      );
      // The end of the award week is the start of the running one, so the
      // interval is half-open and the current week is outside it.
      expect(
        periodFn,
        contains("v_end := date_trunc('week', v_muscat_now) at time zone"),
      );
    });

    test('monthly is the previous completed calendar month', () {
      expect(
        periodFn,
        contains(
            "v_start := (date_trunc('month', v_muscat_now) - interval '1 month')"),
      );
      expect(
        periodFn,
        contains("v_end := date_trunc('month', v_muscat_now) at time zone"),
      );
    });

    test('the running period is never the award period', () {
      // The key is derived from the *start of the completed period*, and it is
      // the only thing matches are filtered by. Nothing filters on `now()`, and
      // no untruncated clock reaches the key.
      expect(
        periodFn,
        contains('public.statistics_period_key(v_start, p_period_type)'),
      );
      expect(
        cteIn(matches, 'period'),
        contains('public.last_completed_statistics_period(p_period_type)'),
      );
      expect(
        matches,
        contains(
            'public.statistics_period_key(c.start_at, p_period_type) = pk.period_key'),
      );
      expect(
        executable,
        isNot(contains('public.statistics_period_key(now()')),
      );
    });

    test('the caller cannot name a period, only a kind of one', () {
      // Two parameters and no timestamp: the server decides which week.
      expect(
        statements,
        contains('create or replace function public.community_period_xi_evidence(\n'
            '  p_community_id uuid,\n'
            '  p_period_type text\n'
            ')'),
      );
      expect(statements, contains('public.community_period_xi_evidence(uuid, text)'));
    });

    test('there is no All Time period XI', () {
      expect(
        periodFn,
        contains("p_period_type not in ('weekly', 'monthly')"),
      );
      expect(periodFn, contains("raise exception 'INVALID_PERIOD_TYPE'"));
      // Refused once, in the shared resolution, so neither read path can
      // accept a period the other rejects.
      expect(
        RegExp('INVALID_PERIOD_TYPE').allMatches(statements).length,
        1,
      );
    });
  });

  group('a match qualifies on six conditions and no others', () {
    test('qualification is decided in exactly one place', () {
      // Both read paths call the same function, so the window cannot count
      // three matches while the participation rates were taken over four.
      expect(
        cte('qualifying'),
        contains(
            'public.community_period_xi_matches(p_community_id, p_period_type)'),
      );
      expect(
        wcte('qualifying'),
        contains(
            'public.community_period_xi_matches(p_community_id, p_period_type)'),
      );
      expect(matches, contains('from v_completed_matches c'));
    });

    test('it belongs to the requested community', () {
      expect(matches, contains('c.community_id = p_community_id'));
    });

    test('completion is read from v_completed_matches, never restated', () {
      expect(matches, contains('from v_completed_matches c'));
      // `0029`'s rule lives in the view. A second copy here would let the award
      // and the match list report different histories.
      expect(executable, isNot(contains("status = 'completed'")));
      expect(executable, isNot(contains('end_at <= now()')));
    });

    test('a recorded result is required', () {
      expect(
        matches,
        contains('join match_results r on r.match_id = c.match_id'),
      );
    });

    test('a stored lineup with a real user on it is required', () {
      // Conditions 5 and 6 as one predicate: a lineup row naming a user *is* a
      // stored lineup row, so the real-user test strictly implies the
      // stored-lineup test. Writing both would be two statements of one rule,
      // and the weaker one would go stale first.
      expect(
        matches,
        contains('exists (\n'
            '      select 1 from match_team_assignments a\n'
            '      where a.match_id = c.match_id and a.user_id is not null\n'
            '    )'),
      );
    });

    test('registration is never evidence that anybody played', () {
      for (final forbidden in [
        'match_registrations',
        'registration',
        'reserve',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)),
            reason: 'the stored played lineup is the only participation');
      }
    });
  });

  group('a Professional Guest is evidence, never a candidate', () {
    test('the candidate half is filtered to real users', () {
      expect(cte('appearances'), contains('where l.player_id is not null'));
    });

    test('every player figure derives from that filtered half', () {
      // Totals, form score and position all read `appearances`, so the one
      // predicate above is the whole of the exclusion — from statistics, from
      // PFS, from eligibility and from the ranking evidence alike.
      expect(cte('totals'), contains('from appearances a'));
      expect(cte('by_position'), contains('from appearances a'));
      expect(cte('totals'), contains('public.period_form_score_v1('));
    });

    test('the shape evidence reads the whole stored lineup', () {
      // Guests actually played, so they count toward how big a team was and
      // how the pitch was filled. The window's `lineup` carries every stored
      // row and is not filtered by `user_id`.
      expect(wcte('lineup'), contains('from match_team_assignments a'));
      expect(wcte('lineup'), isNot(contains('user_id')));
      expect(wcte('sides'), contains('from lineup l'));
      expect(wcte('aggregate_shape'), contains('from lineup l'));
    });

    test('a guests-only match is not a qualifying match at all', () {
      // The exclusion is one predicate in the one qualification function, so
      // it reaches every figure at once: the match cannot raise
      // `required_matches`, cannot dilute a participation rate, and cannot
      // contribute a team-size or positional-shape observation, because every
      // one of those is arithmetic over `qualifying`.
      expect(matches, contains('a.user_id is not null'));
      expect(wcte('lineup'), contains('join qualifying q'));
      expect(wcte('sides'), contains('from lineup l'));
      expect(cte('qualifying'), contains('community_period_xi_matches'));
      expect(cteIn(evidence, 'counted'), contains('from qualifying'));
      expect(cteIn(window, 'counted'), contains('from qualifying'));
    });

    test('a mixed real-and-guest match qualifies in full', () {
      // Nothing narrows qualification beyond "at least one real user", so a
      // match with one Go Play player and nine guests is a qualifying match —
      // and the guests beside them still reach the shape evidence, because the
      // window's lineup is unfiltered.
      expect(matches, isNot(contains('not exists')));
      expect(matches, isNot(contains('count(*) =')));
      expect(matches, isNot(contains('professional_guest')));
      expect(wcte('lineup'), isNot(contains('is not null')));
    });

    test('no synthetic identity is invented for a guest', () {
      for (final forbidden in [
        'professional_guest_id',
        'coalesce(a.user_id',
        'coalesce(l.player_id',
      ]) {
        expect(executable, isNot(contains(forbidden)));
      }
    });
  });

  group('Period Form Score v1 is stated once, in full, and frozen', () {
    test('it is its own function with its own literals', () {
      // Not read from the rating engine. A future rating policy must not
      // re-score an award period that has already been played.
      expect(formScore, contains('when p_won   = 1 then  0.10'));
      expect(formScore, contains('when p_lost  = 1 then -0.10'));
      expect(formScore, contains('when p_drawn = 1 then  0.00'));
      expect(formScore, contains('when p_mvp = 1 then 0.05'));
      // The goal cap is the one weight it does not restate, because the
      // tie-break needs the identical arithmetic and two copies could drift.
      expect(formScore, contains('public.period_goal_form_v1(p_goals)'));
      expect(goalForm, contains('least(0.10, 0.02 * greatest('));
    });

    test('the weights are unchanged from the approved v1', () {
      // Guarding against every rejected variant by name: no ±0.06, no
      // shrinkage, no weighting of any kind.
      expect(executable, isNot(contains('0.06')));
      for (final rejected in [
        'shrink',
        'bayes',
        'prior',
        'recency_weight',
        'position_weight',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(rejected)));
      }
    });

    test('it is immutable, pinned and not client-callable', () {
      expect(formScore, contains('immutable'));
      expect(formScore, contains('set search_path = public'));
      expect(
        statements,
        contains('revoke execute on function\n'
            '  public.period_form_score_v1(int, int, int, int, int)\n'
            '  from anon, authenticated, public;'),
      );
      expect(
        statements,
        isNot(contains(
            'grant execute on function\n  public.period_form_score_v1')),
      );
    });

    test('the version is in the name, so a v2 is a new function', () {
      expect(statements, contains('period_form_score_v1'));
      expect(statements, isNot(contains('period_form_score_v2')));
      expect(statements, isNot(contains('period_form_score(')));
    });

    test('rating_history is not consulted, and no delta is read', () {
      // `delta` is what the 0.00-10.00 clamp allowed through. PFS is what the
      // rules asked for, which is a different number for a player at either end
      // of the scale.
      expect(executable, isNot(contains('rating_history')));
      expect(executable, isNot(contains('delta')));
      expect(executable, isNot(contains('apply_rating_delta')));
      expect(executable, isNot(contains('clamp')));
    });

    test('the period score is the average of the per-match contributions', () {
      expect(
        cte('totals'),
        contains(
            'avg(public.period_form_score_v1(a.won, a.lost, a.drawn, a.goals, a.mvp))'),
      );
      // Nothing rounds it on the way out.
      expect(evidence, isNot(contains('round(')));
      expect(evidence, contains('period_form_score numeric'));
    });
  });

  group('Period Form Score v1 arithmetic', () {
    // The rule restated as arithmetic, so the examples are executable. It is
    // the same shape as the SQL above, which the previous group holds the file
    // to; if the two ever disagree, one of these groups fails.
    double pfs({
      bool won = false,
      bool lost = false,
      bool drawn = false,
      int goals = 0,
      bool mvp = false,
    }) {
      final result = won
          ? 0.10
          : lost
              ? -0.10
              : drawn
                  ? 0.00
                  : 0.00;
      return result + math.min(0.10, 0.02 * goals) + (mvp ? 0.05 : 0.00);
    }

    test('a win is worth +0.10', () {
      expect(pfs(won: true), closeTo(0.10, 1e-9));
    });

    test('a loss is worth -0.10', () {
      expect(pfs(lost: true), closeTo(-0.10, 1e-9));
    });

    test('a draw is worth nothing', () {
      expect(pfs(drawn: true), closeTo(0.0, 1e-9));
    });

    test('each goal is worth +0.02', () {
      expect(pfs(drawn: true, goals: 1), closeTo(0.02, 1e-9));
      expect(pfs(drawn: true, goals: 3), closeTo(0.06, 1e-9));
    });

    test('goals cap at +0.10 per player per match', () {
      // The cap is on the total, not on each goal: five reach it exactly and a
      // sixth adds nothing.
      expect(pfs(drawn: true, goals: 5), closeTo(0.10, 1e-9));
      expect(pfs(drawn: true, goals: 6), closeTo(0.10, 1e-9));
      expect(pfs(drawn: true, goals: 40), closeTo(0.10, 1e-9));
    });

    test('being best on the pitch is worth +0.05', () {
      expect(pfs(drawn: true, mvp: true), closeTo(0.05, 1e-9));
    });

    test('the components sum', () {
      // Won, scored twice, named MVP: 0.10 + 0.04 + 0.05.
      expect(pfs(won: true, goals: 2, mvp: true), closeTo(0.19, 1e-9));
      // Lost and scored five: the cap brings them back to where they started.
      expect(pfs(lost: true, goals: 5), closeTo(0.0, 1e-9));
    });

    test('a period score is the mean of the appearances, not their sum', () {
      final matches = [
        pfs(won: true, goals: 1),
        pfs(lost: true),
        pfs(drawn: true, mvp: true),
      ];
      final mean = matches.reduce((a, b) => a + b) / matches.length;
      // (0.12 + -0.10 + 0.05) / 3
      expect(mean, closeTo(0.07 / 3, 1e-9));
      // Playing more matches does not by itself raise the score.
      expect(
        [pfs(won: true), pfs(won: true)].reduce((a, b) => a + b) / 2,
        closeTo(pfs(won: true), 1e-9),
      );
    });
  });

  group('participation and eligibility', () {
    test('participation is counted from the played lineup', () {
      expect(cte('appearances'), contains('from lineup l'));
      expect(cte('totals'), contains('count(*)::int as matches_played'));
    });

    test('weekly asks for one played match, and never two', () {
      expect(
        requiredFn,
        contains("when p_period_type = 'weekly' then 1"),
      );
      // A community that played once that week still has a Team of the Week.
      expect(requiredFn, isNot(contains("'weekly' then 2")));
    });

    test('monthly asks for half the community month, rounded up', () {
      expect(requiredFn, contains('(p_qualifying_matches + 1) / 2'));
    });

    test('an empty period asks for nothing, in either kind of period', () {
      // Tested before the weekly branch, so it applies to both: no qualifying
      // match means no award population, and a window reporting "1 required"
      // beside "0 matches" would be stating a rule that applies to nobody.
      expect(
        requiredFn,
        contains('when coalesce(p_qualifying_matches, 0) <= 0 then 0'),
      );
      expect(
        requiredFn.indexOf('coalesce(p_qualifying_matches, 0) <= 0'),
        lessThan(requiredFn.indexOf("when p_period_type = 'weekly'")),
        reason: 'the empty case must be decided before the weekly branch',
      );
    });

    test('the bar is stated once and published by both read paths', () {
      // A candidate's `eligible` flag must not disagree with the bar the
      // screen shows beside it.
      expect(
        cte('requirement'),
        contains('public.period_xi_required_matches(p_period_type,'),
      );
      expect(
        window,
        contains('public.period_xi_required_matches(p_period_type,'),
      );
    });

    test('the threshold is integer arithmetic that cannot truncate first', () {
      // `/` between two integers truncates in PostgreSQL, so `ceil(n / 2)`
      // would have discarded the half before `ceil` saw it — three matches
      // asking for one, and an eligibility bar that is too low still produces
      // a perfectly plausible XI, so nothing downstream would notice.
      // `ceil` must not appear at all: a `::numeric` cast is one deletion away
      // from the same silent bug.
      expect(executable, isNot(contains('ceil(')));
      expect(executable, isNot(contains('round(')));
      expect(executable, isNot(contains('floor(')));
    });

    test('the threshold table the brief fixed, 0 to 7, both periods', () {
      // The whole SQL expression restated, branches and all. `~/` is integer
      // division, so this is the arithmetic the database performs and not a
      // floating-point stand-in that could round where the database truncates.
      int required(String periodType, int qualifying) {
        if (qualifying <= 0) return 0;
        if (periodType == 'weekly') return 1;
        return (qualifying + 1) ~/ 2;
      }

      const weekly = [0, 1, 1, 1, 1, 1, 1, 1];
      const monthly = [0, 1, 1, 2, 2, 3, 3, 4];
      for (var n = 0; n <= 7; n++) {
        expect(required('weekly', n), weekly[n], reason: 'weekly at $n');
        expect(required('monthly', n), monthly[n], reason: 'monthly at $n');
      }
    });

    test('the truncating answers are named, so they cannot pass quietly', () {
      // What `ceil(integer / integer)` would have produced at the two counts
      // where the two formulas disagree. Stated as its own failure so a
      // regression reads as "3 asked for 1" rather than as a table row.
      int required(int qualifying) => (qualifying + 1) ~/ 2;
      expect(required(3), isNot(1), reason: 'three matches must ask for two');
      expect(required(5), isNot(2), reason: 'five matches must ask for three');
      expect(required(7), isNot(3), reason: 'seven matches must ask for four');
      // And the truncating form is genuinely different, so the check above is
      // not asserting something that was never in danger.
      expect(3 ~/ 2, 1);
      expect(5 ~/ 2, 2);
    });

    test('a period with no football asks for nothing and returns nobody', () {
      int required(String periodType, int qualifying) {
        if (qualifying <= 0) return 0;
        if (periodType == 'weekly') return 1;
        return (qualifying + 1) ~/ 2;
      }

      // Both kinds, and the weekly one is the case that was wrong: an empty
      // week previously asked for a match nobody could have played.
      expect(required('weekly', 0), 0);
      expect(required('monthly', 0), 0);
      // No row can exist at that count anyway: every row comes from `totals`,
      // which needs an appearance in a qualifying match.
      expect(evidence, contains('from totals t'));
    });

    test('the rate is played over the community qualifying count', () {
      expect(
        evidence,
        contains('t.matches_played::numeric / q.qualifying_matches'),
      );
      expect(evidence, contains('t.matches_played >= q.required_matches'));
    });

    test('no attendance rule beyond the threshold is applied', () {
      for (final forbidden in [
        'streak',
        'consecutive',
        'recency_weight',
        'weight',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)));
      }
    });
  });

  group('the normalized metrics', () {
    test('goals per match', () {
      expect(evidence, contains('t.goals::numeric / t.matches_played'));
    });

    test('win rate', () {
      expect(evidence, contains('t.wins::numeric / t.matches_played'));
    });

    test('points per game uses football scoring', () {
      expect(
        evidence,
        contains('(t.wins * 3 + t.draws)::numeric / t.matches_played'),
      );
    });

    test('the PPG examples the brief fixed', () {
      double ppg(int wins, int draws, int played) =>
          (wins * 3 + draws) / played;
      expect(ppg(4, 0, 4), closeTo(3.00, 1e-9));
      expect(ppg(3, 1, 4), closeTo(2.50, 1e-9));
      expect(ppg(0, 0, 4), closeTo(0.00, 1e-9));
      // The domain the brief names.
      expect(ppg(4, 0, 4), lessThanOrEqualTo(3.0));
      expect(ppg(0, 0, 4), greaterThanOrEqualTo(0.0));
    });

    test('MVP count is counted, never rated', () {
      expect(cte('totals'), contains('sum(a.mvp)::int as mvp_count'));
    });

    test('no denominator can be zero', () {
      // Every row comes from `totals`, which is grouped over `appearances` —
      // so `matches_played` is at least one. An appearance is in a qualifying
      // match, so `qualifying_matches` is at least one too. There is no row for
      // which either division is undefined, and therefore no coalesce hiding a
      // zero.
      expect(evidence, contains('from totals t'));
      expect(evidence, contains('count(*)::int as matches_played'));
      expect(evidence, isNot(contains('nullif(')));
    });
  });

  group('the Period Position is where the player actually stood', () {
    test('it is derived from the stored assignment', () {
      expect(cte('by_position'), contains('a.assigned_position as played_position'));
      expect(cte('by_position'), contains('group by a.player_id, a.assigned_position'));
    });

    test('the current profile decides nothing about a closed period', () {
      // A player who edits their profile in October must not reshuffle the XI
      // of a week that closed in August, so these two fields are read nowhere
      // in the function — not as a source, and no longer as a tie-break.
      for (final forbidden in [
        'u.primary_position',
        'u.secondary_position',
        'users.primary_position',
        'users.secondary_position',
      ]) {
        expect(executable, isNot(contains(forbidden)));
      }
      // And the branch that decides position does not reach `users` at all.
      expect(cte('ranked_positions'), isNot(contains('users')));
      expect(cte('by_position'), isNot(contains('users')));
      expect(cte('appearances'), isNot(contains('users')));
    });

    test('the tie-break is the basis recorded on those same lineup rows', () {
      // `assignment_basis` was written when the match was played, so it answers
      // "was this their natural role" from inside the period rather than from
      // a profile field that has moved since.
      expect(cte('lineup'), contains('a.assignment_basis'));
      expect(cte('appearances'), contains('l.assignment_basis'));
      for (final basis in ['PRIMARY', 'SECONDARY', 'TRANSITION']) {
        expect(
          cte('by_position'),
          contains(
              "(count(*) filter (where a.assignment_basis = '$basis'))::int"),
        );
      }
    });

    test('the order is frequency, PRIMARY, SECONDARY, recency, then axis', () {
      final order = cte('ranked_positions');
      for (final key in [
        'b.appearance_count desc',
        'b.primary_basis_count desc',
        'b.secondary_basis_count desc',
        'b.most_recent_at desc',
      ]) {
        expect(order, contains(key));
      }
      final rungs = [
        'b.appearance_count desc',
        'b.primary_basis_count desc',
        'b.secondary_basis_count desc',
        'b.most_recent_at desc',
        "when 'GK' then 0",
      ];
      for (var i = 0; i < rungs.length - 1; i++) {
        expect(
          order.indexOf(rungs[i]),
          lessThan(order.indexOf(rungs[i + 1])),
          reason: '${rungs[i]} must outrank ${rungs[i + 1]}',
        );
      }
    });

    test('recency is when they last played there, not when a row moved', () {
      // `matches.start_at`, carried through the lineup — so recording an old
      // fixture today does not make it the most recent thing they did, and
      // editing a lineup row does not either.
      expect(cte('by_position'), contains('max(a.start_at) as most_recent_at'));
      expect(cte('lineup'), contains('q.start_at'));
      expect(cte('appearances'), contains('l.start_at'));
      expect(cte('by_position'), isNot(contains('updated_at')));
      expect(cte('lineup'), isNot(contains('updated_at')));
      expect(cte('ranked_positions'), isNot(contains('updated_at')));
      expect(evidence, isNot(contains('a.updated_at')));
    });

    test('TRANSITION is evidence and never outranks PRIMARY or SECONDARY', () {
      // Counted, returned, and deliberately absent from the ordering: a move to
      // fill a gap says something about the match, not about the player's role.
      expect(cte('by_position'), contains('transition_basis_count'));
      final order = cte('ranked_positions');
      expect(order, isNot(contains('transition_basis_count')));
    });

    test('the deterministic fallback is the project position axis', () {
      expect(
        cte('ranked_positions'),
        contains("case b.played_position\n"
            "            when 'GK' then 0\n"
            "            when 'DEF' then 1\n"
            "            when 'MID' then 2\n"
            "            when 'FWD' then 3\n"
            "          end asc"),
      );
    });

    test('the basis evidence makes the tie-break explainable', () {
      final counts = cte('position_counts');
      expect(counts, contains('position_basis_evidence'));
      for (final key in [
        "'appearances', b.appearance_count",
        "'primary', b.primary_basis_count",
        "'secondary', b.secondary_basis_count",
        "'transition', b.transition_basis_count",
        "'most_recent_at', b.most_recent_at",
      ]) {
        expect(counts, contains(key));
      }
      expect(evidence, contains('position_basis_evidence jsonb'));
      // Built from `by_position`, which is grouped over `appearances` — so it
      // holds only positions actually played, and no guest is in it.
      expect(counts, contains('from by_position b'));
      expect(cte('by_position'), contains('from appearances a'));
    });

    test('a Period Secondary exists only where a second was actually played',
        () {
      // `by_position` holds only positions with at least one appearance, so
      // rank 2 exists exactly when the player stood in two places. The join is
      // a LEFT one: no second position means null, not a profile fallback.
      expect(
        evidence,
        contains('left join ranked_positions ps\n'
            '    on ps.player_id = t.player_id and ps.position_rank = 2'),
      );
      expect(
        evidence,
        contains('join ranked_positions pp\n'
            '    on pp.player_id = t.player_id and pp.position_rank = 1'),
      );
    });

    test('the frequencies themselves are returned as auditable evidence', () {
      expect(
        cte('position_counts'),
        contains('jsonb_object_agg(b.played_position, b.appearance_count)'),
      );
      expect(evidence, contains('position_appearances jsonb'));
    });
  });

  group('match and positional shape evidence', () {
    test('each played side is one observation, whatever its size', () {
      // Grouped by side, so an eleven-a-side match contributes two
      // observations and not twenty-two. This is the whole reason the per-side
      // form exists: counting rows would let one big match outvote a month of
      // small-sided ones.
      expect(wcte('sides'), contains('group by l.match_id, l.team'));
      expect(wcte('sides'), contains('count(*)::int as team_size'));
      expect(window, contains('position_shape_observations jsonb'));
    });

    test('a side carries its size and its whole positional make-up', () {
      final sides = wcte('sides');
      for (final position in ['GK', 'DEF', 'MID', 'FWD']) {
        expect(
          sides,
          contains(
              "(count(*) filter (where l.assigned_position = '$position'))::int"),
        );
      }
      // A guest with no recorded position is counted as unassigned rather than
      // guessed at. A real player always has one (0051).
      expect(
        sides,
        contains(
            '(count(*) filter (where l.assigned_position is null))::int as unassigned'),
      );
    });

    test('the observations are emitted deterministically', () {
      final shape = wcte('shape');
      expect(shape, contains('jsonb_agg('));
      expect(shape, contains('order by s.start_at, s.match_id, s.team'));
      expect(
        shape,
        contains(
            's.team_size order by s.team_size, s.start_at, s.match_id, s.team'),
      );
      // Ordered by when the football happened, never by when a row was
      // written.
      expect(shape, isNot(contains('updated_at')));
      expect(shape, isNot(contains('created_at')));
    });

    test('an empty period still returns arrays rather than nulls', () {
      expect(wcte('shape'), contains("'{}'::int[]"));
      expect(wcte('shape'), contains("'[]'::jsonb"));
    });

    test('no match identifier is disclosed by the shape evidence', () {
      // The caller is entitled to the shape, not to a manifest of fixtures.
      final built = wcte('shape');
      expect(built, isNot(contains("'match_id'")));
      expect(built, contains("'team'"));
      expect(built, contains("'team_size'"));
    });

    test('the aggregate shape survives, but only as a diagnostic', () {
      final aggregate = wcte('aggregate_shape');
      for (final position in ['GK', 'DEF', 'MID', 'FWD']) {
        expect(aggregate, contains("'$position'"));
      }
      expect(aggregate, contains("'unassigned', count(*) filter"));
      expect(window, contains('position_shape jsonb'));
      // And the file says which of the two Cycle 2 must use.
      expect(sql, contains('Diagnostic only'));
      expect(
        sql,
        contains('must not be treated as final'),
      );
    });

    test('the shape evidence lives on the window, not on every candidate', () {
      // It is a fact about the community's football, and it has to survive a
      // period with no candidates at all.
      expect(evidence, isNot(contains('team_size_observations')));
      expect(evidence, isNot(contains('position_shape')));
      expect(window, contains('team_size_observations int[]'));
    });

    test('Cycle 2 is left to assemble the XI', () {
      // No squad size, no slot allocation, no shortage redistribution and no
      // eleven anywhere.
      for (final forbidden in [
        'percentile_cont',
        'percentile_disc',
        'median',
        'limit 11',
        'squad_size',
        'slot',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)));
      }
    });
  });

  group('the selection ranks on five things, and the rating is not one', () {
    test('its five inputs are all returned', () {
      // PFS desc -> participation rate desc -> MVP count desc -> capped
      // goal-form total desc -> user_id. Nothing else.
      for (final column in [
        'period_form_score numeric',
        'participation_rate numeric',
        'mvp_count int',
        'goal_form_contribution_total numeric',
        'user_id uuid',
      ]) {
        expect(evidence, contains(column));
      }
    });

    test('the contract is written down in the order it will be applied', () {
      final contract = sql.substring(
        sql.indexOf('The selection contract'),
        sql.indexOf('create or replace function public.community_period_xi_evidence'),
      );
      final order = [
        'period_form_score',
        'participation_rate',
        'mvp_count',
        'goal_form_contribution_total',
        'user_id',
      ];
      for (var i = 0; i < order.length - 1; i++) {
        expect(
          contract.indexOf(order[i]),
          lessThan(contract.indexOf(order[i + 1])),
          reason: '${order[i]} ranks above ${order[i + 1]}',
        );
      }
      expect(contract, isNot(contains('current_overall_rating desc')));
    });

    test('no selection is implemented here', () {
      // Cycle 1 exposes the inputs and chooses nobody.
      for (final forbidden in [
        'limit 11',
        'percentile_cont',
        'percentile_disc',
        'median',
        'squad_size',
        'slot',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)));
      }
    });

    test('the rating is returned under a name that cannot be mistaken', () {
      expect(evidence, contains('current_overall_rating numeric'));
      // Not the ambiguous name. `overall_rating` alone reads as a fact about
      // the period; it is a live global figure, and the `current_` prefix is
      // what stops a later cycle from ranking on it by accident.
      expect(
        RegExp(r'^  overall_rating numeric', multiLine: true)
            .hasMatch(evidence),
        isFalse,
      );
    });

    test('the rating is presentation evidence and says so', () {
      // The contract is stated where a reader of the column will find it —
      // against the file, because `evidence` has the comments stripped out.
      expect(sql, contains('**Presentation only.**'));
      expect(sql, contains('MUST NOT participate in Period XI selection'));
      // `users` is read once, for that one column, and for nothing else.
      final joins = RegExp('join users').allMatches(executable).length;
      expect(joins, 1);
      expect(evidence, contains('join users u on u.id = t.player_id'));
    });

    test('nothing sorts, filters or scores by the rating', () {
      for (final forbidden in [
        'order by u.overall_rating',
        'order by t.overall_rating',
        'u.overall_rating desc',
        'u.overall_rating >',
        'u.overall_rating *',
        'u.overall_rating +',
      ]) {
        expect(executable, isNot(contains(forbidden)),
            reason: 'a September match must not move August XI');
      }
      // The rating appears exactly once in executable SQL: the projection.
      expect(
        RegExp('overall_rating').allMatches(executable).length,
        2,
        reason: 'once as the returned column, once as its source',
      );
    });

    test('user_id is the deterministic final tie-break', () {
      expect(evidence, contains('order by t.player_id;'));
      expect(evidence, contains('user_id uuid'));
      // Deterministic means one order, not a stable-sort accident: there is
      // exactly one ORDER BY on the returned rows.
      expect(
        RegExp(r'^  order by ', multiLine: true).allMatches(evidence).length,
        1,
      );
    });

    test('the rows are ordered for stability, not for selection', () {
      expect(evidence, isNot(contains('order by t.period_form_score')));
      expect(evidence, isNot(contains('order by q.participation_rate')));
    });

    test('no explanatory metric is folded into a score', () {
      // Goals/Match, Win Rate, PPG and MVP count are evidence the reader sees,
      // not extra weights. Nothing multiplies or adds them together.
      expect(evidence, isNot(contains('goals_per_match *')));
      expect(evidence, isNot(contains('win_rate *')));
      expect(evidence, isNot(contains('points_per_game *')));
      expect(evidence, isNot(contains('mvp_count *')));
    });

    test('no presentation data rides along', () {
      // A face and a name are the caller's problem, and the future screen is
      // not this cycle's contract.
      for (final forbidden in ['full_name', 'avatar_path', 'phone']) {
        expect(executable, isNot(contains(forbidden)));
      }
    });
  });

  group('a closed period moves only when its own evidence is corrected', () {
    // The invariant the whole design serves. A completed Period XI *may* change
    // when authoritative data inside that period is corrected — a lineup, a
    // score, a goal, an MVP, an assigned position. It must *not* change because
    // of anything that happened after the period ended.

    test('the invariant is written down where the next cycle will read it', () {
      expect(sql, contains('Historical stability'));
      expect(sql, contains('must not'));
    });

    test('every input is evidence from inside the period', () {
      // The four sources, and nothing present-tense among them.
      for (final source in [
        'from v_completed_matches c',
        'join match_results r on r.match_id = c.match_id',
        'from match_team_assignments a',
        'left join match_goals g',
      ]) {
        expect(executable, contains(source));
      }
      // Corrections reach the answer because there is nothing stored between
      // the evidence and the reader.
      expect(statements, isNot(contains('create table')));
      expect(statements, isNot(contains('create trigger')));
      expect(statements, isNot(contains('insert into')));
    });

    test('a later match cannot change a closed award', () {
      // Two ways it could: by moving the rating that ranks, or by moving the
      // rating rules that score. Neither is reachable — the rating does not
      // rank, and PFS carries its own frozen literals.
      expect(executable, isNot(contains('order by u.overall_rating')));
      expect(executable, isNot(contains('rating_history')));
      expect(functionBody('period_form_score_v1'), contains('0.10'));
      expect(executable, isNot(contains('ratingRules')));
    });

    test('a profile edit cannot change a closed award', () {
      expect(executable, isNot(contains('u.primary_position')));
      expect(executable, isNot(contains('u.secondary_position')));
      // Position is decided from the lineup rows of that period alone.
      expect(cte('by_position'), contains('a.assigned_position'));
      expect(cte('by_position'), contains('a.assignment_basis'));
    });

    test('a future rating policy cannot re-score a played period', () {
      // The version is in the name, so v2 has to be chosen rather than
      // inherited, and this body is what v1 will always have meant.
      expect(statements, contains('period_form_score_v1'));
      expect(statements, isNot(contains('period_form_score_v2')));
      expect(
        functionBody('period_form_score_v1'),
        isNot(contains('rating_rules')),
      );
    });

    test('two reads of an unchanged period agree', () {
      // Determinism, stated three times where it can be lost: the row order,
      // the shape arrays, and the position ranking.
      expect(evidence, contains('order by t.player_id;'));
      expect(
        wcte('shape'),
        contains(
            's.team_size order by s.team_size, s.start_at, s.match_id, s.team'),
      );
      expect(cte('ranked_positions'), contains('row_number() over ('));
      expect(
          cte('ranked_positions'), contains("end asc\n      ) as position_rank"));
    });

    test('a late historical match inside the period may change the award', () {
      // This is intentional, not a leak. A legitimate fixture entered today
      // with a date inside the period is authoritative evidence *about* that
      // period, so it qualifies like any other and moves the timestamp.
      // Nothing excludes a match for having been recorded late, and nothing
      // freezes an award for having been viewed.
      expect(matches, isNot(contains('created_at')));
      expect(matches, isNot(contains('is_historical')));
      expect(sql, contains('entered late'));
      expect(statements, isNot(contains('viewed')));
    });

    test('evidence from another period cannot reach this one', () {
      // Every source in the timestamp is joined to `qualifying`, which is this
      // period's match set and nothing else.
      final changed = wcte('changed');
      expect(
        RegExp('join qualifying q').allMatches(changed).length,
        4,
        reason: 'each of the four sources is scoped to the period',
      );
    });
  });

  group('the period window describes a period nobody played', () {
    test('it is a separate read path, not a candidate row', () {
      expect(statements, contains('public.community_period_xi_window('));
      // No metadata row masquerading as a player: the candidate function's
      // `user_id` comes from `totals`, which is grouped over real appearances,
      // so there is nowhere for a null-user row to come from.
      expect(evidence, contains('t.player_id'));
      expect(evidence, isNot(contains('null as user_id')));
      expect(evidence, isNot(contains('null::uuid')));
      expect(evidence, isNot(contains('union all')));
    });

    test('it returns exactly one row, always', () {
      // `period` is one row from the resolution; every other branch is an
      // unGROUPed aggregate, which is one row even over no input; and they are
      // combined with cross joins, so the product is exactly one.
      expect(window, contains('from period p'));
      for (final joined in [
        'cross join counted c',
        'cross join shape sh',
        'cross join aggregate_shape ag',
        'cross join changed ch',
      ]) {
        expect(window, contains(joined));
      }
      // Each cross-joined branch is an ungrouped aggregate, which is one row
      // even over no input at all. `sides` is grouped, but it feeds `shape`
      // rather than the projection.
      for (final single in ['counted', 'shape', 'aggregate_shape', 'changed']) {
        expect(wcte(single), isNot(contains('group by')),
            reason: '$single must collapse to one row');
      }
      // And nothing filters or groups the row away afterwards.
      final projection = window.substring(window.lastIndexOf('\n  select\n'));
      expect(projection, isNot(contains('group by')));
      expect(projection, isNot(contains('where')));
      expect(projection, isNot(contains('join qualifying')));
    });

    test('the period is named even when the period is empty', () {
      for (final column in [
        'period_type text',
        'period_key text',
        'period_start timestamptz',
        'period_end timestamptz',
      ]) {
        expect(window, contains(column));
      }
      // Which is what lets the screen say "25-31 August" rather than "Weekly".
      expect(wcte('period'), contains('p.period_start, p.period_end'));
    });

    test('zero qualifying matches is reported as zero, not as absence', () {
      expect(wcte('counted'), contains('count(*)::int as qualifying_matches'));
      expect(window, contains('qualifying_match_count int'));
      expect(window, contains('required_matches int'));
      // `count(*)` over an empty set is 0, and the threshold function takes
      // that without dividing by anything.
      expect(requiredFn, contains('coalesce(p_qualifying_matches, 0)'));
    });

    test('the candidate list may independently be empty', () {
      // Nothing in the candidate function manufactures a row, and the window
      // does not depend on there being one.
      expect(evidence, contains('from totals t'));
      expect(window, isNot(contains('totals')));
      expect(window, isNot(contains('community_period_xi_evidence')));
    });
  });

  group('the evidence change timestamp', () {
    test('it reads the strongest timestamp each source actually has', () {
      final changed = wcte('changed');
      // Trigger-maintained `updated_at` where one exists (0003, 0022, 0018)...
      expect(changed, contains('max(m.updated_at) from matches m'));
      expect(changed, contains('max(r.updated_at) from match_results r'));
      expect(
        changed,
        contains('max(a.updated_at) from match_team_assignments a'),
      );
      // ...and `created_at` for match_goals, which has no `updated_at` column
      // and needs none: a result correction deletes and reinserts those rows,
      // so the insert time is the time the goals last changed.
      expect(changed, contains('max(g.created_at) from match_goals g'));
      expect(changed, isNot(contains('g.updated_at')));
    });

    test('all four sources are folded into one timestamp', () {
      expect(wcte('changed'), contains('greatest('));
      expect(window, contains('evidence_last_changed_at timestamptz'));
    });

    test('an empty period may report null', () {
      // `greatest` ignores nulls and is null only when every source is, which
      // is exactly what a period with no qualifying evidence has.
      expect(sql, contains('is null only when every source is'));
      expect(wcte('changed'), isNot(contains('coalesce(')));
    });

    test('it is a timestamp, not award persistence', () {
      for (final forbidden in [
        'hash',
        'digest',
        'md5',
        'sha256',
        'version_id',
        'snapshot',
      ]) {
        expect(executable.toLowerCase(), isNot(contains(forbidden)));
      }
      expect(statements, isNot(contains('create table')));
    });
  });

  group('the capped goal-form tie-break', () {
    test('it is exposed for every candidate', () {
      expect(evidence, contains('goal_form_contribution_total numeric'));
      expect(
        cte('totals'),
        contains('sum(public.period_goal_form_v1(a.goals))'),
      );
    });

    test('it is the same capped arithmetic the form score uses', () {
      // One definition, two callers — so the tie-break and the score it breaks
      // ties for cannot drift apart.
      expect(goalForm, contains('least(0.10, 0.02 * greatest('));
      expect(formScore, contains('public.period_goal_form_v1(p_goals)'));
      expect(
        RegExp(r'least\(0\.10, 0\.02').allMatches(executable).length,
        1,
        reason: 'the cap is written once',
      );
    });

    test('it is summed across matches while the form score is averaged', () {
      final totals = cte('totals');
      expect(totals, contains('avg(public.period_form_score_v1('));
      expect(totals, contains('sum(public.period_goal_form_v1('));
    });

    test('raw goals stay separate and uncapped', () {
      // Presentation evidence keeps the real number; only the tie-break caps.
      expect(cte('totals'), contains('sum(a.goals)::int as goals'));
      expect(evidence, contains('goals int'));
      expect(evidence, contains('goals_per_match numeric'));
      expect(evidence, contains('t.goals::numeric / t.matches_played'));
    });

    test('the capped values the brief fixed', () {
      // The SQL expression, restated.
      double goalForm(int goals) => math.min(0.10, 0.02 * goals);
      expect(goalForm(0), closeTo(0.00, 1e-9));
      expect(goalForm(1), closeTo(0.02, 1e-9));
      expect(goalForm(3), closeTo(0.06, 1e-9));
      expect(goalForm(5), closeTo(0.10, 1e-9));
      expect(goalForm(8), closeTo(0.10, 1e-9));
      expect(goalForm(40), closeTo(0.10, 1e-9));
    });

    test('caps are summed per match, not applied to the period total', () {
      double goalForm(int goals) => math.min(0.10, 0.02 * goals);
      // Five goals in each of two matches is 0.20, not 0.10.
      expect(goalForm(5) + goalForm(5), closeTo(0.20, 1e-9));
      // And it is not the raw total either, which would be 0.20 for ten goals
      // in one match.
      expect(goalForm(10), closeTo(0.10, 1e-9));
      expect(goalForm(10), isNot(closeTo(0.02 * 10, 1e-9)));
    });
  });

  group('authorization is gated, definer, pinned and granted narrowly', () {
    test('both read paths open with the identical gate, before any read', () {
      for (final body in [evidence, window]) {
        expect(body, contains("raise exception 'NOT_AUTHENTICATED'"));
        expect(
          body,
          contains(
              'if not public.is_community_member(p_community_id, auth.uid()) then\n'
              "    raise exception 'NOT_AUTHORIZED';"),
        );
        final begin = body.indexOf('begin');
        final gate = body.indexOf('auth.uid() is null');
        final firstRead = body.indexOf('return query');
        expect(begin, lessThan(gate));
        expect(gate, lessThan(firstRead));
      }
      // Nothing runs before the decision in the candidate path: it is the only
      // one that declares variables, and they carry no initializer.
      final declare = evidence.indexOf('declare');
      if (declare >= 0) {
        expect(
          evidence.substring(declare, evidence.indexOf('begin')),
          isNot(contains(':=')),
        );
      }
    });

    test('both are stable definers with a pinned search path', () {
      for (final body in [evidence, window]) {
        expect(body, contains('security definer'));
        expect(body, contains('stable'));
        expect(body, contains('set search_path = public'));
        expect(body, isNot(contains('security invoker')));
      }
    });

    test('execute is revoked from the world and granted to authenticated', () {
      for (final signature in [
        'public.community_period_xi_evidence(uuid, text)',
        'public.community_period_xi_window(uuid, text)',
      ]) {
        expect(
          statements,
          contains('revoke execute on function\n  $signature from anon, public;'),
        );
        expect(
          statements,
          contains('grant execute on function\n  $signature to authenticated;'),
        );
      }
    });

    test('the five helpers are callable by no client role at all', () {
      // There is no weaker second way in: the helpers run only inside the two
      // gated functions, which run as their owner.
      for (final signature in [
        'public.period_goal_form_v1(int)',
        'public.period_form_score_v1(int, int, int, int, int)',
        'public.period_xi_required_matches(text, int)',
        'public.last_completed_statistics_period(text)',
        'public.community_period_xi_matches(uuid, text)',
      ]) {
        expect(statements, contains('$signature\n  from anon, authenticated, public;'));
        expect(statements, isNot(contains('grant execute on function\n  $signature')));
      }
      // Two grants in the whole migration, and both are to `authenticated`.
      expect(
        RegExp('grant execute on function').allMatches(statements).length,
        2,
      );
      expect(statements, isNot(contains('to anon')));
      expect(statements, isNot(contains('to service_role')));
    });

    test('no other community can be reached through either path', () {
      // The community is a parameter that filters, and membership of *that*
      // community is what was checked. Nothing else narrows or widens it.
      expect(matches, contains('c.community_id = p_community_id'));
      for (final body in [evidence, window]) {
        expect(body, isNot(contains('is_system_admin')));
        expect(body, isNot(contains('service_role')));
      }
    });

    test('current membership is not an eligibility filter', () {
      // A player who earned an award and has since left keeps it.
      expect(executable, isNot(contains('community_members')));
      expect(executable, isNot(contains('v_community_members')));
    });
  });
}
