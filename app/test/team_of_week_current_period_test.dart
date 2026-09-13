import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What migration 0077 says — Team of the Week is the CURRENT week, and Team
/// of the Month is untouched.
///
/// A static review of the file, as `team_of_period_migration_test.dart` is of
/// 0070: this proves the file says the right things, and
/// `integration/team_of_week_current_period_test.dart` is what proves the
/// database does them. One group is arithmetic rather than text — which week an
/// instant belongs to — because those examples are the product contract.
void main() {
  const path = '../supabase/migrations/0077_current_week_team_of_week.sql';
  const path0070 = '../supabase/migrations/0070_team_of_period_evidence.sql';

  // Line endings normalized: the repository checks `*.sql` out with CRLF.
  String read(String file) =>
      File(file).readAsStringSync().replaceAll('\r\n', '\n');

  final sql = read(path);
  final sql0070 = read(path0070);

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing it.
  String withoutComments(String text) => text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  final statements = withoutComments(sql);

  /// The same, with SQL string literals blanked, so a `comment on` body cannot
  /// satisfy an assertion about executable text.
  final executable = statements
      .split('\n')
      .map((line) => line.replaceAll(RegExp("'[^']*'"), "''"))
      .join('\n');

  /// One function, from its `create or replace` to the dollar-quote that closes
  /// its body — comments inside the body included.
  String functionIn(String text, String name) {
    final start = text.indexOf('create or replace function public.$name(');
    if (start < 0) throw StateError('no function $name');
    final end = text.indexOf('\n\$\$;', start);
    return text.substring(start, end + '\n\$\$;'.length);
  }

  final week = functionIn(sql, 'current_statistics_week_at');
  final resolver = functionIn(sql, 'team_of_period_statistics_period');

  const readPaths = [
    'community_period_xi_matches',
    'community_period_xi_window',
    'community_period_xi_evidence',
  ];

  group('the migration', () {
    test('is 0077 and creates the two helpers and the three read paths', () {
      expect(File(path).existsSync(), isTrue);
      expect(
        RegExp('create or replace function').allMatches(statements).length,
        5,
      );
      for (final name in [
        'current_statistics_week_at',
        'team_of_period_statistics_period',
        ...readPaths,
      ]) {
        expect(statements, contains('create or replace function public.$name('));
      }
    });

    test('stores nothing: no table, trigger, snapshot or written award', () {
      for (final forbidden in [
        'create table',
        'alter table',
        'create trigger',
        'create materialized view',
        'create view',
        'insert into',
        'update ',
        'delete from',
        'drop ',
        'create policy',
      ]) {
        expect(executable, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('Team of the Week is the week now running, in Asia/Muscat', () {
    test('weekly resolves the week containing now()', () {
      expect(resolver, contains("if p_period_type = 'weekly' then"));
      expect(
        resolver,
        contains('from public.current_statistics_week_at(now()) w;'),
      );
    });

    test('the week is Monday 00:00 on the Muscat wall clock, for seven days',
        () {
      expect(week, contains('v_zone := public.statistics_period_zone();'));
      expect(
        week,
        contains("v_week := date_trunc('week', p_at at time zone v_zone);"),
      );
      expect(week, contains('v_start := v_week at time zone v_zone;'));
      expect(
        week,
        contains("(v_week + interval '7 days') at time zone v_zone;"),
      );
      // The key is the counters' own function over the start just computed,
      // so the award week and the statistics week cannot be different weeks.
      expect(
        week,
        contains("public.statistics_period_key(v_start, 'weekly')"),
      );
    });

    test('it never steps back to the week that has finished', () {
      expect(week, isNot(contains("- interval '7 days'")));
      expect(withoutComments(resolver),
          isNot(contains("last_completed_statistics_period('weekly')")));
    });

    test('an empty week has no fallback', () {
      // The period is resolved before, and independently of, any match: there
      // is nothing here that could look at the football and pick another week.
      for (final body in [withoutComments(week), withoutComments(resolver)]) {
        expect(body, isNot(contains('match')));
        expect(body, isNot(contains('coalesce')));
        expect(body, isNot(contains('if not found')));
      }
    });

    test('the zone is the frozen one and is never restated', () {
      expect(executable, isNot(contains('Asia/Muscat')));
      expect(executable, isNot(contains('+04')));
    });
  });

  group('Team of the Month is exactly as it was', () {
    test('monthly calls 0070\'s last completed period, unmodified', () {
      expect(
        resolver,
        contains("from public.last_completed_statistics_period('monthly') m;"),
      );
      // Not recreated here, so its body is still 0070's.
      expect(
        statements,
        isNot(contains(
            'create or replace function public.last_completed_statistics_period')),
      );
      final monthly = functionIn(sql0070, 'last_completed_statistics_period');
      expect(
        monthly,
        contains(
            "v_start := (date_trunc('month', v_muscat_now) - interval '1 month')"),
      );
      expect(
        monthly,
        contains("v_end := date_trunc('month', v_muscat_now) at time zone"),
      );
    });

    test('overall is still refused with the existing token', () {
      expect(
        resolver,
        contains(
            "if p_period_type is null or p_period_type not in ('weekly', 'monthly') then\n"
            "    raise exception 'INVALID_PERIOD_TYPE';"),
      );
    });
  });

  group('the read paths change their period and nothing else', () {
    const oldCall =
        '    from public.last_completed_statistics_period(p_period_type) p';
    const newCall =
        '    -- CHANGED (0077): the current week, or the last completed month.\n'
        '    from public.team_of_period_statistics_period(p_period_type) p';

    for (final name in readPaths) {
      test('$name is 0070\'s body with one line changed', () {
        final before = functionIn(sql0070, name);
        final after = functionIn(sql, name);

        expect(before.split(oldCall).length - 1, 1);
        expect(after, before.replaceFirst(oldCall, newCall));
        expect(after, isNot(contains('last_completed_statistics_period')));
      });
    }

    test('the selection evidence is still the same evidence', () {
      final evidence = functionIn(sql, 'community_period_xi_evidence');
      // The ranking inputs, the threshold and the position rules the selector
      // depends on. Implied by the byte comparison above; named so a reader
      // sees what "no regression" means.
      for (final kept in [
        'public.period_form_score_v1(a.won, a.lost, a.drawn, a.goals, a.mvp)',
        'sum(public.period_goal_form_v1(a.goals))',
        'public.period_xi_required_matches(p_period_type, c.qualifying_matches)',
        'where l.player_id is not null',
        'order by t.player_id;',
      ]) {
        expect(evidence, contains(kept));
      }
    });
  });

  group('who may call what is unchanged', () {
    test('the two public read paths are still gated the same way', () {
      for (final name in ['community_period_xi_window', 'community_period_xi_evidence']) {
        final body = functionIn(sql, name);
        expect(body, contains('security definer'));
        expect(body, contains('set search_path = public'));
        expect(
          body,
          contains("if auth.uid() is null then\n    raise exception 'NOT_AUTHENTICATED';"),
        );
        expect(
          body,
          contains('if not public.is_community_member(p_community_id, auth.uid()) then\n'
              "    raise exception 'NOT_AUTHORIZED';"),
        );
        expect(
          statements,
          contains('revoke execute on function\n'
              '  public.$name(uuid, text) from anon, public;'),
        );
        expect(
          statements,
          contains('grant execute on function\n'
              '  public.$name(uuid, text) to authenticated;'),
        );
      }
      expect(
        RegExp('grant execute on function').allMatches(statements).length,
        2,
      );
      expect(statements, isNot(contains('to anon')));
      expect(statements, isNot(contains('to service_role')));
      expect(statements, isNot(contains('to public')));
    });

    test('every helper is callable by no client role at all', () {
      for (final signature in [
        'public.current_statistics_week_at(timestamptz)',
        'public.team_of_period_statistics_period(text)',
        'public.community_period_xi_matches(uuid, text)',
      ]) {
        expect(
          statements,
          contains('revoke execute on function $signature\n'
              '  from anon, authenticated, public;'),
        );
      }
    });

    test('the new helpers do not run as their owner', () {
      for (final body in [week, resolver]) {
        expect(body, isNot(contains('security definer')));
        expect(body, contains('set search_path = public'));
        expect(body, contains('stable'));
      }
    });
  });

  group('which week an instant belongs to', () {
    // The contract restated as arithmetic. Muscat is UTC+4 all year, a week
    // starts at Monday 00:00 on that wall clock, and the interval is half-open.
    // `IYYY-"W"IW` is the ISO year and week of that Monday.
    ({DateTime start, DateTime end, String key}) weekOf(DateTime instant) {
      const offset = Duration(hours: 4);
      final wall = instant.toUtc().add(offset);
      final monday = DateTime.utc(wall.year, wall.month, wall.day)
          .subtract(Duration(days: wall.weekday - DateTime.monday));
      final thursday = monday.add(const Duration(days: 3));
      final dayOfYear =
          thursday.difference(DateTime.utc(thursday.year)).inDays + 1;
      final isoWeek = (dayOfYear - 1) ~/ 7 + 1;
      final start = monday.subtract(offset);
      return (
        start: start,
        end: start.add(const Duration(days: 7)),
        key: '${thursday.year}-W${isoWeek.toString().padLeft(2, '0')}',
      );
    }

    /// The last day a week covers, as the screen writes it: the day before the
    /// exclusive end, on the Muscat wall clock.
    DateTime lastDay(DateTime end) =>
        end.add(const Duration(hours: 4)).subtract(const Duration(days: 1));

    test('A. Sunday 13 September 2026 is 7 -> 13 September', () {
      // Noon in Muscat.
      final w = weekOf(DateTime.utc(2026, 9, 13, 8));
      expect(w.start, DateTime.utc(2026, 9, 6, 20));
      expect(w.end, DateTime.utc(2026, 9, 13, 20));
      expect(w.key, '2026-W37');
      expect(w.start.add(const Duration(hours: 4)), DateTime.utc(2026, 9, 7));
      expect(lastDay(w.end), DateTime.utc(2026, 9, 13));
    });

    test('A. and is still that week at 23:59:59 on the Sunday', () {
      expect(weekOf(DateTime.utc(2026, 9, 13, 19, 59, 59)).key, '2026-W37');
    });

    test('B. Monday 14 September 2026 is 14 -> 20 September', () {
      // 00:00 in Muscat, the instant the week rolls over.
      final w = weekOf(DateTime.utc(2026, 9, 13, 20));
      expect(w.start, DateTime.utc(2026, 9, 13, 20));
      expect(w.end, DateTime.utc(2026, 9, 20, 20));
      expect(w.key, '2026-W38');
      expect(w.start.add(const Duration(hours: 4)), DateTime.utc(2026, 9, 14));
      expect(lastDay(w.end), DateTime.utc(2026, 9, 20));
      expect(weekOf(DateTime.utc(2026, 9, 14, 8)).key, '2026-W38');
    });

    test('the week before it is not the award week any more', () {
      expect(weekOf(DateTime.utc(2026, 9, 13, 8)).key,
          isNot('2026-W36'));
    });

    test('ISO weeks cross the new year the way IYYY does', () {
      // 31 December 2026 is a Thursday, in week 53 of 2026, and 1 January 2027
      // belongs to that same week.
      expect(weekOf(DateTime.utc(2026, 12, 31, 8)).key, '2026-W53');
      expect(weekOf(DateTime.utc(2027, 1, 1, 8)).key, '2026-W53');
      expect(weekOf(DateTime.utc(2027, 1, 4, 8)).key, '2027-W01');
    });
  });
}
