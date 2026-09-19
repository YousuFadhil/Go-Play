import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community/Period Rating: what the database computes, and what the boards
/// do with it.
///
/// **Two halves, and both are here.** The arithmetic lives in
/// `community_scoped_rating` (migration `0081`) and cannot be executed from a
/// widget test, so it is reviewed as text — the same way every migration in
/// this repository is reviewed, and the same way `0078`'s own values are held
/// to the Dart mirror. What *can* be executed is everything above the adapter:
/// which board ranks it, who is eligible for one, and that the Global Rating is
/// not what is being ranked any more.
void main() {
  // Normalised on the way in: Git checks these files out with CRLF endings on
  // Windows, and several assertions below span two lines.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final sql = read(
      '../supabase/migrations/0081_community_scoped_rating_and_public_results.sql');
  final rollback = read(
      '../supabase/rollback/0081_community_scoped_rating_and_public_results.rollback.sql');

  /// The file with comment lines removed, so an assertion about what the
  /// migration *does* is never satisfied by prose describing what it does not.
  final statements = sql
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  /// One `create ... function public.<name>(` up to its `$$;`.
  String functionBody(String name) {
    final start = statements.indexOf('function public.$name(');
    expect(start, isNot(-1), reason: '$name is not created by this migration');
    final end = statements.indexOf(r'$$;', start);
    return statements.substring(start, end);
  }

  group('what migration 0081 computes', () {
    late final String body = functionBody('community_scoped_rating');

    test('it starts every player at the approved baseline', () {
      expect(body, contains('v_rating := 5.000;'));
    });

    test('it applies exactly 0078 values, in the engine order', () {
      // participation -> outcome -> goals (capped) -> MVP.
      expect(body, contains('v_rating + 0.005'));
      expect(body, contains('then 0.100'));
      expect(body, contains('then -0.100'));
      expect(body, contains('else 0.010'));
      expect(body, contains('least(0.070, 0.010 * r.scored)'));
      expect(body, contains('v_rating + 0.020'));

      expect(body.indexOf('v_rating + 0.005'),
          lessThan(body.indexOf('then 0.100')));
      expect(body.indexOf('then 0.100'),
          lessThan(body.indexOf('least(0.070, 0.010 * r.scored)')));
      expect(body.indexOf('least(0.070, 0.010 * r.scored)'),
          lessThan(body.indexOf('v_rating + 0.020')));
    });

    test('and clamps after every one of them, as the engine does', () {
      expect(
        RegExp(r'least\(10\.000, greatest\(0\.000').allMatches(body).length,
        4,
        reason: 'participation, outcome, goals and MVP are each clamped',
      );
    });

    test('a scope is a community and a statistics period, together', () {
      expect(body, contains('m.community_id = p_community_id'));
      expect(
        body,
        contains('public.statistics_period_key(m.start_at, p_period_type)'),
      );
      // Both halves of the key, so a week is this week rather than every week.
      expect(body, contains('= p_period_key'));
      expect(body, contains("not in ('overall', 'weekly', 'monthly')"));
    });

    test('only matches that were played and have a result are evidence', () {
      expect(body, contains('join match_results res on res.match_id = m.id'));
      expect(body, contains("(m.status = 'completed' or m.end_at <= now())"));
    });

    test('the order is chronological, because the clamp makes it matter', () {
      expect(body, contains('order by m.start_at, m.id'));
    });

    test('a Professional Guest has no rating', () {
      expect(body, contains('a.user_id is not null'));
      // The outcome and the goals come from the same function the Global
      // engine is applied from, which already excludes a null user.
      expect(body, contains('public.match_result_contribution(m.id)'));
    });

    test('the Global Rating is neither read nor written', () {
      for (final forbidden in [
        'overall_rating',
        'rating_history',
        'apply_rating_delta',
        'update ',
        'insert into',
        'delete from',
      ]) {
        expect(functionBody('community_scoped_rating').toLowerCase(),
            isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('it is authenticated-only, like the roster it ranks', () {
      expect(
        statements,
        contains('revoke execute on function '
            'public.community_scoped_rating(uuid, text, text)\n'
            '  from anon, public;'),
      );
      expect(
        statements,
        contains('grant execute on function '
            'public.community_scoped_rating(uuid, text, text)\n'
            '  to authenticated;'),
      );
    });
  });

  group('what migration 0081 publishes', () {
    test('the results lists carry the approved public columns and no more', () {
      for (final name in [
        'public_recent_results',
        'public_community_recent_results',
      ]) {
        final body = functionBody(name);
        final returns = body.substring(
          body.indexOf('returns table ('),
          body.indexOf(')\nlanguage sql'),
        );
        for (final column in [
          'match_id',
          'community_name',
          'start_at',
          'team_a_score',
          'team_b_score',
          'mvp_display_name',
        ]) {
          expect(returns, contains(column), reason: '$name $column');
        }
        // Nothing about who may still join, who is registered, or who played.
        for (final forbidden in [
          'open_slots',
          'starting_players',
          'join_code',
          'user_id',
          'registration',
        ]) {
          expect(returns, isNot(contains(forbidden)),
              reason: '$name $forbidden');
        }
        // Active communities only, and only matches with a recorded result.
        expect(body, contains('c.is_active'), reason: name);
        expect(body, contains('f.has_result'), reason: name);
      }
    });

    test('achievements are the last closed periods, never an older one', () {
      final body = functionBody('player_recent_achievements');
      expect(body, contains('public.last_completed_statistics_period'));
      expect(body, contains('team_of_period_awards'));
      expect(body, contains('team_of_period_snapshots'));
      // The MVP half is one row, the awards half is every community.
      expect(body, contains("'MVP'::text"));
      expect(body, contains("'TEAM_OF_PERIOD'::text"));
      expect(body, contains('order by all_achievements.occurred_at desc'));
    });

    test('the public achievements carry no identifier', () {
      final body = functionBody('public_player_recent_achievements');
      final returns = body.substring(
        body.indexOf('returns table ('),
        body.indexOf(')\nlanguage sql'),
      );
      expect(returns, contains('community_name'));
      expect(returns, isNot(contains('community_id')));
      expect(returns, isNot(contains('match_id')));
      expect(
          body, contains('join users u on u.id = p_user_id and u.is_active'));
    });

    test('nothing in the migration writes anything', () {
      for (final forbidden in [
        'create table',
        'alter table',
        'insert into',
        'update ',
        'delete from',
        'truncate',
        'create policy',
        'drop policy',
      ]) {
        expect(statements.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });

    test('the rollback removes exactly what the migration added', () {
      for (final signature in [
        'public.community_scoped_rating(uuid, text, text)',
        'public.public_recent_results(int)',
        'public.public_community_recent_results(uuid, int)',
        'public.player_recent_achievements(uuid, int)',
        'public.public_player_recent_achievements(uuid, int)',
      ]) {
        expect(rollback, contains('drop function if exists $signature;'),
            reason: signature);
      }
      for (final forbidden in ['drop table', 'delete from', 'truncate']) {
        expect(rollback.toLowerCase(), isNot(contains(forbidden)),
            reason: forbidden);
      }
    });
  });

  group('the boards rank the Community/Period Rating', () {
    CommunityMemberRating member(String id, String name, double global) =>
        CommunityMemberRating(userId: id, fullName: name, rating: global);

    CommunityPlayerStatistics counters(String id, {int played = 1}) =>
        CommunityPlayerStatistics(
          userId: id,
          fullName: null,
          matchesPlayed: played,
          wins: 0,
          losses: 0,
          draws: played,
          goals: 0,
          mvpCount: 0,
        );

    test('Highest Rated ranks the scoped rating, not the Global one', () async {
      // Ali holds the higher Global Rating; Sara has the better period.
      final adapter = _Adapter(
        members: [member('u1', 'Ali', 9.0), member('u2', 'Sara', 5.0)],
        counters: [counters('u1'), counters('u2')],
        scoped: {'u1': (5.105, 1), 'u2': (5.205, 2)},
      );

      final boards =
          await StatisticsRepository(adapter).fetchLeaderboards('c1');
      final rated = boards.firstWhere(
        (board) => board.kind == LeaderboardKind.highestRated,
      );

      expect(rated.entries.first.fullName, 'Sara');
      expect(rated.entries.first.value, 5.205);
      expect(rated.entries.last.value, 5.105);
    });

    test('a member with no football in the period is not on it', () async {
      final adapter = _Adapter(
        members: [member('u1', 'Ali', 6.0), member('u2', 'Sara', 7.0)],
        counters: [counters('u1')],
        // Sara has not played in this period, so the database returns no row
        // for her at all.
        scoped: {'u1': (5.105, 1)},
      );

      final boards =
          await StatisticsRepository(adapter).fetchLeaderboards('c1');
      final rated = boards.firstWhere(
        (board) => board.kind == LeaderboardKind.highestRated,
      );

      expect(rated.entries.map((e) => e.fullName), ['Ali']);
    });

    test('nobody having played means no rating board at all', () async {
      final adapter = _Adapter(
        members: [member('u1', 'Ali', 6.0)],
        counters: const [],
        scoped: const {},
      );

      final boards =
          await StatisticsRepository(adapter).fetchLeaderboards('c1');

      expect(
        boards.where((board) => board.kind == LeaderboardKind.highestRated),
        isEmpty,
      );
    });

    test('the selected period is the one the rating is read for', () async {
      final adapter = _Adapter(
        members: [member('u1', 'Ali', 6.0)],
        counters: [counters('u1')],
        scoped: {'u1': (5.105, 1)},
      );
      final repository = StatisticsRepository(adapter);

      await repository.fetchLeaderboards('c1', StatisticsPeriod.weekly);
      await repository.fetchLeaderboards('c1', StatisticsPeriod.monthly);
      await repository.fetchCommunityStatistics('c1', StatisticsPeriod.weekly);

      expect(adapter.scopedPeriods, [
        StatisticsPeriod.weekly,
        StatisticsPeriod.monthly,
        StatisticsPeriod.weekly,
      ]);
    });

    test('Lowest Rated ranks the same rating over the same population',
        () async {
      final adapter = _Adapter(
        members: [
          member('u1', 'Ali', 9.0),
          member('u2', 'Sara', 5.0),
          member('u3', 'Noor', 8.0),
        ],
        counters: [counters('u1'), counters('u2')],
        // Noor has not played: absent from both rating boards rather than at
        // the bottom of one.
        scoped: {'u1': (5.105, 1), 'u2': (4.905, 1)},
      );

      final statistics = await StatisticsRepository(adapter)
          .fetchCommunityStatistics('c1', StatisticsPeriod.weekly);
      final lowest = statistics.reverseBoards.firstWhere(
        (board) => board.kind == ReverseLeaderboardKind.lowestRated,
      );

      expect(lowest.entries.first.fullName, 'Sara');
      expect(lowest.entries.map((e) => e.fullName), isNot(contains('Noor')));
    });
  });
}

/// A statistics port that answers from what a test handed it.
class _Adapter implements StatisticsAdapter {
  _Adapter({
    required this.members,
    required this.counters,
    required this.scoped,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> counters;
  final Map<String, (double, int)> scoped;

  final List<StatisticsPeriod> scopedPeriods = [];

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async =>
      members;

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      counters;

  @override
  Future<List<CommunityScopedRating>> fetchCommunityScopedRatings(
    String communityId,
    StatisticsPeriod period,
  ) async {
    scopedPeriods.add(period);
    return [
      for (final entry in scoped.entries)
        CommunityScopedRating(
          userId: entry.key,
          rating: entry.value.$1,
          matchesPlayed: entry.value.$2,
        ),
    ];
  }

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      const {};

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      counters.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
