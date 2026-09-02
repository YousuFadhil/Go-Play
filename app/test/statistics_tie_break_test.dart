import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// Unified tie-breaking by most recent achievement (Cycle B1).
///
/// When two players are level, the one who did it more recently is shown first.
/// What is asserted here is the rule itself, at the repository — because the
/// repository is the only place it lives. The Community Dashboard and the
/// Community Leaderboards both come through it, which is what makes them agree
/// rather than two implementations that happen to.
///
/// **The timestamp decides display order and never rank.** Equal values share a
/// rank whatever their recency, and the next distinct value still skips the
/// places they used up. Several tests below exist only to hold that line.
void main() {
  /// `matches.start_at` — when the football happened. Never a `created_at`.
  DateTime at(int year, int month, int day) => DateTime.utc(year, month, day);

  CommunityMemberRating member(String id, String name, double rating) =>
      CommunityMemberRating(userId: id, fullName: name, rating: rating);

  CommunityPlayerStatistics counters(
    String id, {
    String? name,
    int played = 0,
    int wins = 0,
    int goals = 0,
    int mvp = 0,
  }) =>
      CommunityPlayerStatistics(
        userId: id,
        fullName: name,
        matchesPlayed: played,
        wins: wins,
        losses: 0,
        draws: 0,
        goals: goals,
        mvpCount: mvp,
      );

  PlayerAchievementRecency when({
    DateTime? goal,
    DateTime? mvp,
    DateTime? played,
    DateTime? win,
    DateTime? rating,
  }) =>
      PlayerAchievementRecency(
        lastGoalAt: goal,
        lastMvpAt: mvp,
        lastPlayedAt: played,
        lastWinAt: win,
        lastRatingAt: rating,
      );

  Future<List<Leaderboard>> boards(
    List<CommunityMemberRating> members,
    List<CommunityPlayerStatistics> records,
    Map<String, PlayerAchievementRecency> recency, {
    StatisticsPeriod period = StatisticsPeriod.allTime,
  }) =>
      StatisticsRepository(
        _FakeStatisticsAdapter(
          members: members,
          records: records,
          recency: recency,
        ),
      ).fetchLeaderboards('c1', period);

  Future<CommunityDashboard> dashboard(
    List<CommunityPlayerStatistics> records,
    Map<String, PlayerAchievementRecency> recency, {
    StatisticsPeriod period = StatisticsPeriod.allTime,
  }) =>
      StatisticsRepository(
        _FakeStatisticsAdapter(
          members: const [],
          records: records,
          recency: recency,
        ),
      ).fetchDashboard('c1', period);

  Leaderboard boardOf(List<Leaderboard> all, LeaderboardKind kind) =>
      all.firstWhere((board) => board.kind == kind);

  List<String> orderOf(Leaderboard board) =>
      [for (final entry in board.entries) entry.userId];

  group('1-5. the newer achievement leads a tie', () {
    test('equal goals: the newer goal first', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', goals: 8), counters('u2', goals: 8)],
        {
          // Ali is alphabetically first and would have led before Cycle B1.
          'u1': when(goal: at(2026, 5, 1)),
          'u2': when(goal: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)), ['u2', 'u1']);
    });

    test('equal MVP count: the newer MVP first', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', mvp: 2), counters('u2', mvp: 2)],
        {
          'u1': when(mvp: at(2026, 5, 1)),
          'u2': when(mvp: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.mostMvp)), ['u2', 'u1']);
    });

    test('equal matches played: the newer played match first', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', played: 4), counters('u2', played: 4)],
        {
          'u1': when(played: at(2026, 5, 1)),
          'u2': when(played: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.mostActive)), ['u2', 'u1']);
    });

    test('equal wins: the newer winning match first', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', wins: 3), counters('u2', wins: 3)],
        {
          'u1': when(win: at(2026, 5, 1)),
          'u2': when(win: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.mostWins)), ['u2', 'u1']);
    });

    test('equal rating: the newer effective rating match first', () async {
      final all = await boards(
        [member('u1', 'Ali', 6.5), member('u2', 'Sara', 6.5)],
        const [],
        {
          'u1': when(rating: at(2026, 5, 1)),
          'u2': when(rating: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.highestRated)), ['u2', 'u1']);
    });

    test('each measure reads its own evidence, not another\'s', () async {
      // Sara scored more recently; Ali played more recently. Each board follows
      // the timestamp that belongs to it.
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [
          counters('u1', goals: 8, played: 4),
          counters('u2', goals: 8, played: 4),
        ],
        {
          'u1': when(goal: at(2026, 5, 1), played: at(2026, 7, 1)),
          'u2': when(goal: at(2026, 6, 1), played: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)), ['u2', 'u1']);
      expect(orderOf(boardOf(all, LeaderboardKind.mostActive)), ['u1', 'u2']);
    });
  });

  group('6-8. rank is the value, and only the value', () {
    test('equal value and equal timestamp falls back to name then id',
        () async {
      final sameMatch = at(2026, 6, 1);
      final all = await boards(
        [
          member('u2', 'Sara', 5.0),
          member('u1', 'Ali', 5.0),
          // Same name as Ali, so only the id can separate them.
          member('u0', 'Ali', 5.0),
        ],
        [
          counters('u2', goals: 8),
          counters('u1', goals: 8),
          counters('u0', goals: 8),
        ],
        {
          'u2': when(goal: sameMatch),
          'u1': when(goal: sameMatch),
          'u0': when(goal: sameMatch),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)),
          ['u0', 'u1', 'u2'],
          reason: 'Ali before Sara by name; u0 before u1 by id');
    });

    test('different recency does not make the ranks different', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', goals: 8), counters('u2', goals: 8)],
        {
          'u1': when(goal: at(2026, 5, 1)),
          'u2': when(goal: at(2026, 6, 1)),
        },
      );

      final board = boardOf(all, LeaderboardKind.topScorer);
      expect([for (final e in board.entries) e.rank], [1, 1],
          reason: 'equal values share a rank however recently they were made');
    });

    test('the rank after a tie still skips the places it used', () async {
      // The specification's own example: 8, 8, 6 ranks 1, 1, 3.
      final all = await boards(
        [
          member('u1', 'Yousef', 5.0),
          member('u2', 'Ahmed', 5.0),
          member('u3', 'Khalid', 5.0),
        ],
        [
          counters('u1', goals: 8),
          counters('u2', goals: 8),
          counters('u3', goals: 6),
        ],
        {
          'u1': when(goal: at(2026, 6, 1)),
          'u2': when(goal: at(2026, 5, 1)),
          'u3': when(goal: at(2026, 7, 1)),
        },
      );

      final board = boardOf(all, LeaderboardKind.topScorer);
      expect(orderOf(board), ['u1', 'u2', 'u3']);
      expect([for (final e in board.entries) e.rank], [1, 1, 3],
          reason: 'Khalid is third despite the newest goal of the three');
    });
  });

  group('9-10. a rating with no history sorts last', () {
    test('a real rating event beats a baseline 5.00 with none', () async {
      // Both hold 5.00. One has actually played and come back to it; the other
      // has never had an effective rating event at all.
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        const [],
        {
          'u1': when(),
          'u2': when(rating: at(2026, 6, 1)),
        },
      );

      expect(orderOf(boardOf(all, LeaderboardKind.highestRated)), ['u2', 'u1'],
          reason: 'never is not a very old date');
    });

    test('two untouched baselines fall back deterministically', () async {
      final all = await boards(
        [member('u2', 'Sara', 5.0), member('u1', 'Ali', 5.0)],
        const [],
        const {},
      );

      expect(orderOf(boardOf(all, LeaderboardKind.highestRated)), ['u1', 'u2'],
          reason: 'name, then id — and the same answer every read');
    });

    test('a player missing from the map is the same as one with nulls',
        () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', goals: 8), counters('u2', goals: 8)],
        {'u2': when(goal: at(2026, 6, 1))},
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)), ['u2', 'u1']);
    });
  });

  group('11-13. the period the recency describes', () {
    test('the recency read is asked for the same period as the counters',
        () async {
      // The guarantee that a weekly board is broken by weekly recency: the
      // repository passes the period straight through, and the read model
      // buckets by the database's own `statistics_period_key`.
      final adapter = _FakeStatisticsAdapter(
        members: [member('u1', 'Ali', 5.0)],
        records: [counters('u1', goals: 1)],
        recency: const {},
      );

      await StatisticsRepository(adapter)
          .fetchLeaderboards('c1', StatisticsPeriod.weekly);

      expect(adapter.recencyPeriods, [StatisticsPeriod.weekly]);
      expect(adapter.counterPeriods, [StatisticsPeriod.weekly],
          reason: 'one window, asked of both reads');
    });

    test('a newer achievement outside the week does not lead inside it',
        () async {
      // The read model returns only what happened in the requested period, so
      // an event outside it is simply absent — and absent sorts last.
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', goals: 3), counters('u2', goals: 3)],
        {
          // Ali's goal is in this week. Sara's newer goal was last month and is
          // therefore not part of this week's evidence.
          'u1': when(goal: at(2026, 6, 3)),
          'u2': when(),
        },
        period: StatisticsPeriod.weekly,
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)), ['u1', 'u2']);
    });

    test('the monthly board behaves the same way', () async {
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        [counters('u1', goals: 3), counters('u2', goals: 3)],
        {
          'u1': when(goal: at(2026, 6, 20)),
          'u2': when(),
        },
        period: StatisticsPeriod.monthly,
      );

      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)), ['u1', 'u2']);
    });

    test('Highest Rated ties the same way in every period', () async {
      // The rating is the Global Rating in every period, so its recency is
      // global too: the same order whichever window the screen is showing.
      final recency = {
        'u1': when(rating: at(2026, 5, 1)),
        'u2': when(rating: at(2026, 6, 1)),
      };
      final roster = [member('u1', 'Ali', 6.5), member('u2', 'Sara', 6.5)];

      for (final period in StatisticsPeriod.values) {
        final all = await boards(roster, const [], recency, period: period);
        expect(orderOf(boardOf(all, LeaderboardKind.highestRated)),
            ['u2', 'u1'],
            reason: 'unchanged in $period');
      }
    });
  });

  group('14. the dashboard and the board agree', () {
    test('one tied measure, one selected player', () async {
      // The consistency requirement, asserted as one fact rather than two
      // screens tested apart: the same repository rule answers both.
      final records = [
        counters('u1', name: 'Ali', goals: 8, played: 4, mvp: 2),
        counters('u2', name: 'Sara', goals: 8, played: 4, mvp: 2),
      ];
      final recency = {
        'u1': when(
            goal: at(2026, 5, 1), played: at(2026, 5, 1), mvp: at(2026, 5, 1)),
        'u2': when(
            goal: at(2026, 6, 1), played: at(2026, 6, 1), mvp: at(2026, 6, 1)),
      };

      final leaders = await dashboard(records, recency);
      final all = await boards(
        [member('u1', 'Ali', 5.0), member('u2', 'Sara', 5.0)],
        records,
        recency,
      );

      expect(leaders.topScorer!.userId, 'u2');
      expect(orderOf(boardOf(all, LeaderboardKind.topScorer)).first, 'u2');

      expect(leaders.mostActivePlayer!.userId, 'u2');
      expect(orderOf(boardOf(all, LeaderboardKind.mostActive)).first, 'u2');

      expect(leaders.mostMvp!.userId, 'u2');
      expect(orderOf(boardOf(all, LeaderboardKind.mostMvp)).first, 'u2');
    });

    test('a departed player still leads if their achievement stands', () async {
      // The dashboard preserves records of players who have left, and Cycle B1
      // does not change that population — only which of two equals is named.
      final leaders = await dashboard(
        [
          counters('gone', name: 'Departed', goals: 8),
          counters('u1', name: 'Ali', goals: 8),
        ],
        {
          'gone': when(goal: at(2026, 6, 1)),
          'u1': when(goal: at(2026, 5, 1)),
        },
      );

      expect(leaders.topScorer!.userId, 'gone');
    });

    test('a record with no name still ties deterministically', () async {
      // `CommunityPlayerStatistics.fullName` is nullable; the fallback must not
      // throw when two nameless records are level and neither has recency.
      final leaders = await dashboard(
        [counters('u2', goals: 4), counters('u1', goals: 4)],
        const {},
      );

      expect(leaders.topScorer!.userId, 'u1');
    });
  });

  group('15-16. the answer does not depend on how the rows arrived', () {
    test('input order does not change output', () async {
      final recency = {
        'u1': when(goal: at(2026, 5, 1)),
        'u2': when(goal: at(2026, 6, 1)),
        'u3': when(goal: at(2026, 7, 1)),
      };
      final roster = [
        member('u1', 'Ali', 5.0),
        member('u2', 'Sara', 5.0),
        member('u3', 'Omar', 5.0),
      ];
      final records = [
        counters('u1', goals: 8),
        counters('u2', goals: 8),
        counters('u3', goals: 8),
      ];

      final forwards = await boards(roster, records, recency);
      final backwards = await boards(
        roster.reversed.toList(),
        records.reversed.toList(),
        recency,
      );

      expect(orderOf(boardOf(forwards, LeaderboardKind.topScorer)),
          ['u3', 'u2', 'u1']);
      expect(orderOf(boardOf(backwards, LeaderboardKind.topScorer)),
          orderOf(boardOf(forwards, LeaderboardKind.topScorer)));
    });

    test('four tied for first, three shown, all still rank 1', () async {
      // The board is three deep. Recency decides which three of the four are
      // shown; it does not decide that any of them placed differently.
      final all = await boards(
        [
          member('u1', 'Ali', 5.0),
          member('u2', 'Sara', 5.0),
          member('u3', 'Omar', 5.0),
          member('u4', 'Zed', 5.0),
        ],
        [
          counters('u1', goals: 8),
          counters('u2', goals: 8),
          counters('u3', goals: 8),
          counters('u4', goals: 8),
        ],
        {
          'u1': when(goal: at(2026, 4, 1)),
          'u2': when(goal: at(2026, 7, 1)),
          'u3': when(goal: at(2026, 6, 1)),
          'u4': when(goal: at(2026, 5, 1)),
        },
      );

      final board = boardOf(all, LeaderboardKind.topScorer);
      expect(board.entries, hasLength(3));
      expect(orderOf(board), ['u2', 'u3', 'u4'],
          reason: 'the three most recent of the four');
      expect([for (final e in board.entries) e.rank], [1, 1, 1]);
    });

    test('the third place of a tie is decided by recency, not by luck',
        () async {
      // Two players level on the value that lands at position three. Which of
      // them appears is the newer achievement, every read.
      final all = await boards(
        [
          member('u1', 'Ali', 5.0),
          member('u2', 'Sara', 5.0),
          member('u3', 'Omar', 5.0),
        ],
        [
          counters('u1', goals: 9),
          counters('u2', goals: 4),
          counters('u3', goals: 4),
        ],
        {
          'u1': when(goal: at(2026, 4, 1)),
          'u2': when(goal: at(2026, 5, 1)),
          'u3': when(goal: at(2026, 6, 1)),
        },
      );

      final board = boardOf(all, LeaderboardKind.topScorer);
      expect(orderOf(board), ['u1', 'u3', 'u2']);
      expect([for (final e in board.entries) e.rank], [1, 2, 2]);
    });
  });
}

/// The statistics port, answering from memory and recording what it was asked.
class _FakeStatisticsAdapter implements StatisticsAdapter {
  _FakeStatisticsAdapter({
    required this.members,
    required this.records,
    required this.recency,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> records;
  final Map<String, PlayerAchievementRecency> recency;

  /// Which periods each read was asked for, so a test can show that the counter
  /// and its tie-break describe the same window.
  final List<StatisticsPeriod> counterPeriods = [];
  final List<StatisticsPeriod> recencyPeriods = [];

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async {
    counterPeriods.add(period);
    return records;
  }

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async {
    recencyPeriods.add(period);
    return recency;
  }

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async =>
      members;

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      records.length;

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('not part of the tie-break rule');
}
