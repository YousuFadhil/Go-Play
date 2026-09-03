import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// What the repository makes of a community's rows.
///
/// Every product decision about a leader lives here: that a zero is not a
/// leader, that ties go to whoever did it most recently, and that a bounded
/// period counts who played in it rather than who is on the roster.
///
/// **The screen half of this file is gone, and deliberately.** The Community
/// Dashboard was a tab and is not one any more — its totals and its boards are
/// the one Statistics tab, which is tested in
/// `test/community_statistics_tab_test.dart`. What the repository builds did
/// not change with it, so this stayed exactly as it was.
void main() {
  CommunityPlayerStatistics player(
    String id,
    String? name, {
    int played = 0,
    int wins = 0,
    int losses = 0,
    int draws = 0,
    int goals = 0,
    int mvp = 0,
    String? avatarUrl,
  }) =>
      CommunityPlayerStatistics(
        userId: id,
        fullName: name,
        avatarUrl: avatarUrl,
        matchesPlayed: played,
        wins: wins,
        losses: losses,
        draws: draws,
        goals: goals,
        mvpCount: mvp,
      );

  /// A community mid-season: three players, one clear leader per measure.
  final squad = [
    // Ali has set a picture; Sara has not, so both the picture and the fallback
    // are on the same dashboard.
    player('u1', 'Ali',
        played: 3,
        wins: 2,
        losses: 1,
        goals: 5,
        mvp: 1,
        avatarUrl: 'https://example.test/u1.jpg'),
    player('u2', 'Sara', played: 4, wins: 1, losses: 3, goals: 2, mvp: 2),
    player('u3', 'Omar', played: 1, draws: 1, goals: 0, mvp: 0),
  ];

  group('assembling the dashboard', () {
    test('the totals are the community, not one player', () async {
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.completedMatches, 6);
      expect(dashboard.totalPlayers, 3);
      expect(dashboard.totalGoals, 7);
    });

    test('the match count comes from the match domain, never from the counters',
        () async {
      // Summing matches_played would give 8 -- three players' appearances in
      // the same matches. The two figures are different questions, and the
      // dashboard must not answer one with the other.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.completedMatches, 6);
      expect(dashboard.completedMatches, isNot(8));
    });

    test('the match count is the officially completed one, and nothing else',
        () async {
      // The community has fifteen matches; six carry the completed status. The
      // dashboard is its settled history, so nothing else contributes: not a
      // match still open or full, and not one whose end time has passed while
      // it waits for its result. The port answers that single question, and
      // there is no other total for the repository to fall back on -- the count
      // is taken from the completed-matches read and never derived here.
      final adapter =
          FakeStatisticsAdapter(players: squad, completedMatches: 6);
      final dashboard =
          await StatisticsRepository(adapter).fetchDashboard('c1');

      expect(adapter.completedMatchReads, 1);
      expect(dashboard.completedMatches, 6);
    });

    test('each leader is the highest of its own measure', () async {
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.topScorer?.fullName, 'Ali');
      expect(dashboard.topScorer?.value, 5);
      expect(dashboard.mostActivePlayer?.fullName, 'Sara');
      expect(dashboard.mostActivePlayer?.value, 4);
      expect(dashboard.mostMvp?.fullName, 'Sara');
      expect(dashboard.mostMvp?.value, 2);
    });

    test('nobody leads a measure that has not happened', () async {
      // Every member holds a record from the moment they join, so a community
      // with no recorded result is a table full of zeros. Naming a "top
      // scorer" out of it would be picking a name at random.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(
          players: [player('u1', 'Ali'), player('u2', 'Sara')],
          completedMatches: 2,
        ),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.totalPlayers, 2);
      expect(dashboard.totalGoals, 0);
      expect(dashboard.topScorer, isNull);
      expect(dashboard.mostActivePlayer, isNull);
      expect(dashboard.mostMvp, isNull);
    });

    test('a tie names the same player every time', () async {
      final tied = [
        player('u2', 'Sara', goals: 3),
        player('u1', 'Ali', goals: 3),
      ];
      final first = await StatisticsRepository(
        FakeStatisticsAdapter(players: tied, completedMatches: 1),
      ).fetchDashboard('c1');
      final second = await StatisticsRepository(
        FakeStatisticsAdapter(
            players: tied.reversed.toList(), completedMatches: 1),
      ).fetchDashboard('c1');

      expect(first.topScorer?.fullName, 'Ali');
      expect(second.topScorer?.fullName, first.topScorer?.fullName,
          reason: 'the row order must not decide who leads');
    });

    test('a departed player still counts, and can still lead', () async {
      // A soft-deleted account keeps its statistics and loses its profile. The
      // goals happened, so they stay in the total and the name is simply
      // unavailable.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(
          players: [player('u1', null, played: 2, goals: 9)],
          completedMatches: 2,
        ),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.totalGoals, 9);
      expect(dashboard.totalPlayers, 1);
      expect(dashboard.topScorer?.value, 9);
      expect(dashboard.topScorer?.fullName, isNull);
    });
  });

  group('assembling the dashboard for a period', () {
    /// The same community, seen through one week: two of the three played, and
    /// the figures are smaller than the running total in every measure.
    final thisWeek = [
      player('u1', 'Ali', played: 1, wins: 1, goals: 2, mvp: 1),
      player('u2', 'Sara', played: 1, losses: 1, goals: 0, mvp: 0),
    ];

    FakeStatisticsAdapter seasonAndWeek() => FakeStatisticsAdapter(
          players: squad,
          completedMatches: 6,
          periodPlayers: {StatisticsPeriod.weekly: thisWeek},
          periodMatches: {StatisticsPeriod.weekly: 1},
        );

    test('the chosen period reaches both reads', () async {
      // The two reads answer different questions -- players and matches -- and
      // a dashboard whose halves described different stretches of time would be
      // wrong in a way no single figure on it could show.
      final adapter = seasonAndWeek();

      await StatisticsRepository(adapter)
          .fetchDashboard('c1', StatisticsPeriod.monthly);

      expect(adapter.periodsAsked, [StatisticsPeriod.monthly]);
      expect(adapter.completedMatchReads, 1);
    });

    test('All Time is what it always was', () async {
      // The default, and the figures the app has always shown first.
      final adapter = seasonAndWeek();
      final dashboard =
          await StatisticsRepository(adapter).fetchDashboard('c1');

      expect(adapter.periodsAsked, [StatisticsPeriod.allTime]);
      expect(dashboard.completedMatches, 6);
      expect(dashboard.totalPlayers, 3);
      expect(dashboard.totalGoals, 7);
      expect(dashboard.topScorer?.fullName, 'Ali');
      expect(dashboard.topScorer?.value, 5);
    });

    test('a week totals the week, and nothing outside it', () async {
      final dashboard = await StatisticsRepository(seasonAndWeek())
          .fetchDashboard('c1', StatisticsPeriod.weekly);

      expect(dashboard.completedMatches, 1);
      // Who played this week, not who is in the community: a periodic record
      // exists only where a player actually played.
      expect(dashboard.totalPlayers, 2);
      expect(dashboard.totalGoals, 2);
    });

    test('a leader of the week is the leader of the week', () async {
      // Sara leads Most active and Most MVP over the season. Neither survives
      // one week in which Ali played as much and was named best player.
      final dashboard = await StatisticsRepository(seasonAndWeek())
          .fetchDashboard('c1', StatisticsPeriod.weekly);

      expect(dashboard.topScorer?.fullName, 'Ali');
      expect(dashboard.topScorer?.value, 2);
      expect(dashboard.mostMvp?.fullName, 'Ali');
      expect(dashboard.mostMvp?.value, 1);
      // Both played once, and the tie breaks by name as it does anywhere else.
      expect(dashboard.mostActivePlayer?.value, 1);
    });

    test('a period nobody played in names nobody', () async {
      // The database deletes a periodic record with nothing in it, so a quiet
      // week is no rows at all -- and every rule that refuses to name a leader
      // at zero refuses here for the same reason.
      final dashboard = await StatisticsRepository(seasonAndWeek())
          .fetchDashboard('c1', StatisticsPeriod.monthly);

      expect(dashboard.completedMatches, 0);
      expect(dashboard.totalPlayers, 0);
      expect(dashboard.totalGoals, 0);
      expect(dashboard.topScorer, isNull);
      expect(dashboard.mostActivePlayer, isNull);
      expect(dashboard.mostMvp, isNull);
    });

    test('a period still refuses to name a leader at zero', () async {
      // Not the same case as the one above: the players are here and their
      // records are here, and every counter in them is zero.
      final dashboard = await StatisticsRepository(
        FakeStatisticsAdapter(
          players: squad,
          completedMatches: 6,
          periodPlayers: {
            StatisticsPeriod.weekly: [
              player('u1', 'Ali'),
              player('u2', 'Sara')
            ],
          },
          periodMatches: {StatisticsPeriod.weekly: 1},
        ),
      ).fetchDashboard('c1', StatisticsPeriod.weekly);

      expect(dashboard.totalPlayers, 2);
      expect(dashboard.topScorer, isNull);
      expect(dashboard.mostMvp, isNull);
    });
  });
}

/// The statistics port, answering from memory and counting what it was asked.
///
/// [players] and [completedMatches] are the All Time answers, which is what the
/// screen opens on. [periodPlayers] and [periodMatches] hold the bounded
/// periods, and default to empty — a period nobody stocked is a period nothing
/// happened in, which is exactly what the database returns for one.
class FakeStatisticsAdapter implements StatisticsAdapter {
  FakeStatisticsAdapter({
    required this.players,
    required this.completedMatches,
    this.periodPlayers = const {},
    this.periodMatches = const {},
    this.failure,
    this.gate,
  });

  final List<CommunityPlayerStatistics> players;
  final int completedMatches;
  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodPlayers;
  final Map<StatisticsPeriod, int> periodMatches;
  final Failure? failure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;

  /// Counted separately, so a test can assert that the match figure came from
  /// the completed-matches read and not from anywhere else.
  int completedMatchReads = 0;

  /// Every period this port was asked about, in order, so a test can assert
  /// that the screen's choice reached the data layer rather than being applied
  /// on top of rows read for another period.
  final List<StatisticsPeriod> periodsAsked = [];

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async {
    reads++;
    periodsAsked.add(period);
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return period == StatisticsPeriod.allTime
        ? players
        : periodPlayers[period] ?? const [];
  }

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async {
    completedMatchReads++;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return period == StatisticsPeriod.allTime
        ? completedMatches
        : periodMatches[period] ?? 0;
  }

  /// The dashboard ranks nobody, so it never reads the roster. Reaching this
  /// from it would be a defect, so it fails loudly rather than answering.
  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      throw UnimplementedError('the Community Dashboard reads no roster');

  /// When each player last achieved each measure. Empty means nobody has any
  /// recency, which is the state before a test says otherwise — every tie then
  /// falls through to the name, exactly as it did before Cycle B1.
  Map<String, PlayerAchievementRecency> recency = const {};

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async {
    recencyReads++;
    lastRecencyPeriod = period;
    return recency;
  }

  int recencyReads = 0;
  StatisticsPeriod? lastRecencyPeriod;

  /// The dashboard is a community's figures, never one player's own totals.
  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError(
          'the Community Dashboard reads no player totals');
}
