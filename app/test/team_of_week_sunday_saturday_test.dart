import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The FINAL weekly Team of Period contract, reviewed as text.
///
/// **What changed and why this suite exists.** `0077` made Team of the Week the
/// *running* ISO week, Monday to Sunday. The Product Owner's final decision is
/// a football week that runs **Sunday to Saturday** and an award that is only
/// ever about the week that has **fully closed**. Migration `0084` carries
/// that, and the two ways it could go wrong are what is pinned here:
///
///   1. moving `period_start`/`period_end` while leaving the ISO
///      `statistics_period_key` equality filter on the match set, which would
///      split the award week on Monday and disagree with its own stated
///      period;
///   2. changing the award week and forgetting that the general weekly
///      counters must keep their ISO buckets.
///
/// The arithmetic itself is Postgres's and cannot be executed from a widget
/// test; it was proved against the live database inside a rolled-back
/// transaction and the figures are recorded in the cycle report. What a review
/// would look for is held here.
void main() {
  // Normalised on the way in: Git checks these files out with CRLF endings on
  // Windows and LF on CI, and several assertions below span two lines.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final sql = read(
      '../supabase/migrations/0084_team_of_week_closed_sunday_saturday.sql');
  final rollback = read('../supabase/rollback/'
      '0084_team_of_week_closed_sunday_saturday_rollback.sql');
  final iso = read('../supabase/migrations/0077_current_week_team_of_week.sql');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  String executable(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final statements = executable(sql);
  final rollbackStatements = executable(rollback);

  group('the week is Sunday to Saturday', () {
    test('it starts on Sunday, by subtracting the day of week', () {
      // `extract(dow)` is 0 on Sunday, so this lands on that week's Sunday for
      // every day including Sunday itself.
      expect(
        statements,
        contains("date_trunc('day', v_local)\n"
            "                - (extract(dow from v_local))::int * interval '1 day'"),
      );
    });

    test('and ends exactly seven days later, half-open', () {
      expect(statements,
          contains("(v_sunday + interval '7 days') at time zone v_zone"));
      // Never an inclusive end: the instant a period ends is the first instant
      // of the next one.
      expect(statements, contains('c.start_at >= p_period_start'));
      expect(statements, contains('c.start_at < p_period_end'));
    });

    test('the key is the Saturday that closes it, through the one key function',
        () {
      expect(
        statements,
        contains('public.statistics_period_key(\n'
            "      (v_sunday + interval '6 days') at time zone v_zone, 'weekly')"),
      );
      // No second week-numbering rule anywhere in the migration.
      expect(
        RegExp(r'IYYY-"W"IW').allMatches(statements).length,
        1,
        reason: 'only the key inversion may name the ISO format directly',
      );
    });

    test('and a key can be read back into its exact bounds', () {
      expect(
          statements,
          contains(
              'create or replace function public.team_of_period_week_of_key'));
      expect(
          statements,
          contains("to_timestamp(p_period_key, 'IYYY-\"W\"IW')::timestamp\n"
              "                - interval '1 day'"));
    });
  });

  group('only the closed week is ever the award', () {
    test('the last completed week is one week back from now', () {
      expect(
        statements,
        contains(
            "from public.team_of_period_week_at(now() - interval '7 days') w"),
      );
    });

    test('and the running week is no longer what weekly resolves to', () {
      // `0077`'s answer, which this migration supersedes.
      expect(iso, contains('public.current_statistics_week_at(now())'));
      expect(statements, isNot(contains('current_statistics_week_at(now())')));
      expect(
        statements,
        contains('from public.last_completed_team_of_period_week() w'),
      );
    });

    test('monthly still delegates to the existing completed-month answer', () {
      expect(statements,
          contains("public.last_completed_statistics_period('monthly')"));
    });
  });

  group('match membership uses bounds, never the ISO key', () {
    test('the bounded match function is what decides it', () {
      expect(
        statements,
        contains(
            'create or replace function public.community_period_xi_matches_between'),
      );
      final body = statements.substring(
        statements.indexOf(
            'create or replace function public.community_period_xi_matches_between'),
        statements.indexOf(
            'create or replace function public.community_period_xi_matches_in'),
      );
      expect(body, contains('c.start_at >= p_period_start'));
      expect(body, contains('c.start_at < p_period_end'));
      // **The defect this replaces.** An ISO key test here would put a Sunday
      // match in the previous week.
      expect(body, isNot(contains('statistics_period_key')));
    });

    test('and the key-equality filter is gone from the match path', () {
      final body = statements.substring(
        statements.indexOf(
            'create or replace function public.community_period_xi_matches_in'),
      );
      final upTo = body.substring(0, body.indexOf(r'$$;'));
      expect(
        upTo,
        isNot(contains(
            "public.statistics_period_key(c.start_at, p_period_type) = pk.period_key")),
      );
      expect(upTo, contains('community_period_xi_matches_between'));
    });

    test('the window and the evidence consume the same one function', () {
      // Neither `_in` body is restated by 0084, so both keep calling
      // `community_period_xi_matches_in` -- and it now resolves bounds once.
      expect(
        statements,
        isNot(contains(
            'create or replace function public.community_period_xi_window_in')),
      );
      expect(
        statements,
        isNot(contains(
            'create or replace function public.community_period_xi_evidence_in')),
      );
    });
  });

  group('the screen and the snapshot cannot describe different periods', () {
    test('both closed reads resolve through the award-period function', () {
      for (final fn in [
        'community_period_xi_closed_window',
        'community_period_xi_closed_evidence',
      ]) {
        final body = statements.substring(
          statements.indexOf('create or replace function public.$fn'),
        );
        final upTo = body.substring(0, body.indexOf(r'$$;'));
        expect(upTo, contains('public.team_of_period_statistics_period'),
            reason: fn);
        // The old answer, which is an ISO week for weekly.
        expect(upTo, isNot(contains('last_completed_statistics_period')),
            reason: fn);
      }
    });

    test(
        'and the member-facing wrappers are left alone, because they already '
        'call it', () {
      for (final fn in [
        'community_period_xi_window(',
        'community_period_xi_evidence(',
        'community_period_xi_matches(',
      ]) {
        expect(statements,
            isNot(contains('create or replace function public.$fn')),
            reason: fn);
      }
    });
  });

  group('the writer accepts only a canonical Sunday-to-Saturday week', () {
    test('it validates against the Team of Period week', () {
      expect(statements,
          contains('from public.team_of_period_week_at(p_period_start) w'));
      expect(statements,
          isNot(contains('current_statistics_week_at(p_period_start)')));
    });

    test('and the expected key comes from that week, not from the start date',
        () {
      // `statistics_period_key(period_start, 'weekly')` on a Sunday start names
      // the *previous* ISO week, so it could never have matched.
      expect(statements, contains('v_expected_key text;'));
      expect(statements,
          contains('into v_expected_start, v_expected_end, v_expected_key'));
      expect(statements,
          contains('or p_period_key is distinct from v_expected_key then'));
    });

    test('every error token and invariant survives', () {
      for (final token in [
        'INVALID_PERIOD_TYPE',
        'PERIOD_IDENTITY_MISMATCH',
        'PERIOD_NOT_CLOSED',
        'COMMUNITY_NOT_FOUND',
        'INVALID_SNAPSHOT_STATE',
        'INVALID_SNAPSHOT_AWARDS',
        'INVALID_SELECTOR_VERSION',
        'SNAPSHOT_ALREADY_FINAL',
      ]) {
        expect(statements, contains("raise exception '$token'"), reason: token);
      }
      expect(statements, contains('if p_period_end > now() then'));
    });

    test('and service-role security is not loosened', () {
      expect(
        statements,
        contains(
            'revoke execute on function public.record_team_of_period_snapshot('),
      );
      expect(statements, isNot(contains('to anon')));
      // The closed reads stay service_role only.
      expect(
          statements,
          contains(
              'grant execute on function public.community_period_xi_closed_window(uuid, text)\n'
              '  to service_role;'));
    });
  });

  group('recent achievements ask for the new weekly period', () {
    test('the weekly half is the closed Sunday-to-Saturday week', () {
      final body = statements.substring(
        statements.indexOf(
            'create or replace function public.player_recent_achievements'),
      );
      expect(
          body, contains('from public.last_completed_team_of_period_week() w'));
      // And the monthly half is untouched.
      expect(
          body, contains("public.last_completed_statistics_period('monthly')"));
      // The old two-row lateral over both period types is gone.
      expect(
        body,
        isNot(contains(
            "from (values ('weekly'), ('monthly')) as t(period_type)")),
      );
    });

    test('and the rest of the contract is unchanged', () {
      final body = statements.substring(
        statements.indexOf(
            'create or replace function public.player_recent_achievements'),
      );
      expect(body, contains("'MVP'::text"));
      expect(body, contains("'TEAM_OF_PERIOD'::text"));
      expect(body, contains('order by all_achievements.occurred_at desc'));
      expect(
          body, contains('limit least(greatest(coalesce(p_limit, 5), 1), 10)'));
      expect(body, contains('c.is_active'));
    });

    test('the public wrapper is not redefined, because it delegates', () {
      expect(
        statements,
        isNot(contains(
            'create or replace function public.public_player_recent_achievements')),
      );
    });
  });

  group('general weekly statistics are not touched', () {
    test('none of the counter functions is redefined', () {
      for (final fn in [
        'statistics_period_key',
        'statistics_period_zone',
        'last_completed_statistics_period',
        'current_statistics_week_at',
        'community_scoped_rating',
        'apply_rating_delta',
        'apply_match_rating_effects',
      ]) {
        expect(statements,
            isNot(contains('create or replace function public.$fn')),
            reason: fn);
      }
    });

    test('and no counter table is written, altered or dropped', () {
      expect(statements.toLowerCase(), isNot(contains('alter table')));
      expect(statements.toLowerCase(), isNot(contains('drop table')));
      expect(statements.toLowerCase(), isNot(contains('delete from')));
      for (final table in [
        'community_statistics',
        'player_statistics',
        'rating_history',
        'users',
        'match_results',
        'matches',
      ]) {
        expect(statements.toLowerCase(), isNot(contains('insert into $table')),
            reason: table);
        expect(statements.toLowerCase(), isNot(contains('update $table')),
            reason: table);
      }
      // The only writes anywhere in the migration are the snapshot writer's
      // own two inserts, which are 0079's and unchanged.
      expect(
        RegExp('insert into').allMatches(statements).length,
        2,
        reason: 'team_of_period_snapshots and team_of_period_awards',
      );
    });
  });

  group('the rollback restores what was there before', () {
    test('it puts the running ISO week back', () {
      expect(rollbackStatements,
          contains('from public.current_statistics_week_at(now()) w'));
    });

    test('it puts the ISO key filter back on the match set', () {
      expect(
        rollbackStatements,
        contains(
            'public.statistics_period_key(c.start_at, p_period_type) = pk.period_key'),
      );
    });

    test('it points the closed reads back at the completed ISO period', () {
      expect(
          rollbackStatements,
          contains(
              'from public.last_completed_statistics_period(p_period_type) p'));
    });

    test('it restores the writer and the achievement query', () {
      expect(rollbackStatements,
          contains('from public.current_statistics_week_at(p_period_start) w'));
      expect(
        rollbackStatements,
        contains("from (values ('weekly'), ('monthly')) as t(period_type)"),
      );
    });

    test('and drops every helper 0084 introduced, last', () {
      for (final fn in [
        'community_period_xi_matches_between',
        'team_of_period_period_bounds',
        'last_completed_team_of_period_week',
        'team_of_period_week_of_key',
        'team_of_period_week_at',
      ]) {
        expect(
            rollbackStatements, contains('drop function if exists public.$fn'),
            reason: fn);
      }
      // The drops come after everything that referred to them was replaced.
      expect(
        rollbackStatements.indexOf('drop function if exists'),
        greaterThan(
            rollbackStatements.indexOf('create or replace function public.'
                'player_recent_achievements')),
      );
    });

    test('and never touches a stored snapshot', () {
      expect(rollbackStatements,
          isNot(contains('delete from team_of_period_snapshots')));
      expect(rollbackStatements,
          isNot(contains('delete from team_of_period_awards')));
      expect(
          rollbackStatements, isNot(contains('update team_of_period_awards')));
      expect(rollbackStatements, isNot(contains('drop table')));
    });
  });

  group('the rollback refuses once a Sunday-to-Saturday week is awarded', () {
    test('it raises a stable token', () {
      expect(
        rollbackStatements,
        contains(
            "raise exception 'ROLLBACK_BLOCKED_TEAM_OF_PERIOD_SNAPSHOTS_EXIST'"),
      );
    });

    test('and the guard is the first executable operation in the file', () {
      // **Zero changes when blocked.** A guard that ran after the first
      // `create or replace` would leave the database half rolled back.
      final guard = rollbackStatements.indexOf(r'do $guard$');
      final firstWrite =
          rollbackStatements.indexOf('create or replace function');

      expect(guard, isNot(-1));
      expect(guard, lessThan(firstWrite));
      // Nothing executable precedes it.
      expect(rollbackStatements.substring(0, guard).trim(), isEmpty);
    });

    test('it blocks on bounds and key together, not on existence', () {
      // The collision this exists for: `0084` names Sunday 2026-09-06 to
      // Sunday 2026-09-13 `2026-W37`, and the ISO contract names Monday
      // 2026-09-07 to Monday 2026-09-14 the *same* key. An award stored under
      // the first would be matched by a query asking for the second, and a
      // profile would show a Team of the Week for a period it is not about.
      // So compatibility is the full triple, not the key alone.
      expect(rollbackStatements, contains("where s.period_type = 'weekly'"));
      expect(rollbackStatements,
          contains('from public.current_statistics_week_at(s.period_start) w'));
      expect(rollbackStatements,
          contains('where w.period_start = s.period_start'));
      expect(rollbackStatements, contains('and w.period_end   = s.period_end'));
      expect(rollbackStatements, contains('and w.period_key   = s.period_key'));
      expect(rollbackStatements, contains('not exists ('));
    });

    test('and an empty snapshot table is not blocked', () {
      // `count(*) > 0` over a `not exists` filter: with no rows at all the
      // count is zero and the file proceeds, which is the state it has only
      // ever been run in.
      expect(rollbackStatements, contains('if v_blocked > 0 then'));
      expect(
          rollbackStatements, contains('select count(*), min(s.period_key)'));
    });

    test('monthly snapshots are deliberately not consulted', () {
      // 0084 did not change monthly behaviour, so a stored month means the
      // same period before and after.
      final guardBody = rollbackStatements.substring(
        rollbackStatements.indexOf(r'do $guard$'),
        rollbackStatements.indexOf(r'$guard$;'),
      );
      expect(guardBody, isNot(contains("'monthly'")));
    });

    test('the misleading claim is gone from the file', () {
      // The earlier draft asserted a stored award "simply will not match",
      // which is exactly what the key collision disproves.
      // The sentence itself is gone; the phrase survives only inside the
      // paragraph that quotes it in order to correct it.
      expect(rollback, isNot(contains('asks for ISO weeks again')));
      expect(rollback, contains('**That was wrong**'));
    });
  });

  group('a period key must name the period it produces', () {
    test('the shape check is not the only check', () {
      final body = statements.substring(
        statements.indexOf(
            'create or replace function public.team_of_period_week_of_key'),
      );
      final upTo = body.substring(0, body.indexOf(r'$$;'));

      // Shape first...
      expect(upTo, contains(r"p_period_key !~ '^\d{4}-W\d{2}$'"));
      // ...then the round trip, because `to_timestamp` rolls an impossible
      // week forward silently rather than refusing it: 2026-W00 lands in
      // January and 2026-W99 in November 2027.
      expect(
        upTo,
        contains('if public.statistics_period_key(\n'
            "       (v_sunday + interval '6 days') at time zone v_zone, "
            "'weekly')\n"
            '     is distinct from p_period_key then'),
      );
      // Both failures use the one token.
      expect(
        RegExp("raise exception 'INVALID_PERIOD_KEY'").allMatches(upTo).length,
        2,
      );
    });

    test('and the external format is unchanged', () {
      // Still YYYY-W##, still derived through the one key function.
      expect(statements, contains(r"'^\d{4}-W\d{2}$'"));
      expect(statements, isNot(contains('YYYY-"W"WW')));
    });
  });

  group('nothing historical was edited', () {
    test('0077 still says what it always said', () {
      expect(iso, contains('public.current_statistics_week_at(now())'));
      expect(iso, contains("date_trunc('week', p_at at time zone v_zone)"));
    });

    test('and 0084 is append-only', () {
      expect(statements, isNot(contains('drop function if exists')));
    });
  });
}
