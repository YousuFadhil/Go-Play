import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/statistics/community_leaderboards_tab.dart';
import 'package:go_play/features/statistics/community_statistics_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';

/// Reverse community statistics and the efficiency line on two positive boards.
///
/// One fixture, chosen so that every rule in the contract is decided by it:
///
///   member  rating  played  wins  draws  goals  mvp   history
///   u1      7.5     4       3     1      6      2     all recent
///   u2      5.0     1       1     0      3      0     rated 01 Aug, played 05 Aug
///   u3      5.0     —       —     —      —      —     none at all (no counters)
///   u4      6.0     1       0     1      0      0     rated 01 Jul, played 10 Aug,
///                                                     a win dated 15 Jul
///
/// u3 has no counter row, which is what a member who did nothing in a bounded
/// period looks like, and must measure as zero on the reverse boards.
void main() {
  CommunityMemberRating member(String id, double rating) =>
      CommunityMemberRating(userId: id, fullName: 'Player $id', rating: rating);

  CommunityPlayerStatistics counters(
    String id, {
    required int played,
    required int wins,
    required int draws,
    required int goals,
    int mvp = 0,
  }) =>
      CommunityPlayerStatistics(
        userId: id,
        fullName: 'Player $id',
        matchesPlayed: played,
        wins: wins,
        losses: played - wins - draws,
        draws: draws,
        goals: goals,
        mvpCount: mvp,
      );

  PlayerAchievementRecency history({
    DateTime? rating,
    DateTime? played,
    DateTime? win,
  }) =>
      PlayerAchievementRecency(
        lastGoalAt: null,
        lastMvpAt: null,
        lastPlayedAt: played,
        lastWinAt: win,
        lastRatingAt: rating,
      );

  _FakeAdapter fixture() => _FakeAdapter(
        members: [
          member('u1', 7.5),
          member('u2', 5.0),
          member('u3', 5.0),
          member('u4', 6.0),
        ],
        counters: [
          counters('u1', played: 4, wins: 3, draws: 1, goals: 6, mvp: 2),
          counters('u2', played: 1, wins: 1, draws: 0, goals: 3),
          counters('u4', played: 1, wins: 0, draws: 1, goals: 0),
        ],
        recency: {
          'u1': history(
            rating: DateTime.utc(2026, 8, 20),
            played: DateTime.utc(2026, 8, 20),
            win: DateTime.utc(2026, 8, 20),
          ),
          'u2': history(
            rating: DateTime.utc(2026, 8, 1),
            played: DateTime.utc(2026, 8, 5),
            win: DateTime.utc(2026, 8, 5),
          ),
          'u4': history(
            rating: DateTime.utc(2026, 7, 1),
            played: DateTime.utc(2026, 8, 10),
            win: DateTime.utc(2026, 7, 15),
          ),
        },
      );

  Future<CommunityStatistics> load([
    _FakeAdapter? adapter,
    StatisticsPeriod period = StatisticsPeriod.weekly,
  ]) =>
      StatisticsRepository(adapter ?? fixture())
          .fetchCommunityStatistics('c1', period);

  ReverseLeaderboard reverse(
    CommunityStatistics statistics,
    ReverseLeaderboardKind kind,
  ) =>
      statistics.reverseBoards.singleWhere((board) => board.kind == kind);

  List<String> ids(ReverseLeaderboard board) =>
      [for (final entry in board.entries) entry.userId];
  List<int> ranks(ReverseLeaderboard board) =>
      [for (final entry in board.entries) entry.rank];

  group('the reverse boards', () {
    test('there are three, in the approved order', () async {
      final statistics = await load();
      expect(
        [for (final board in statistics.reverseBoards) board.kind],
        ReverseLeaderboardKind.values,
      );
    });

    test('Lowest Rated ranks the current rating from the bottom', () async {
      final board = reverse(await load(), ReverseLeaderboardKind.lowestRated);

      // 5.0, 5.0, then 6.0. The two at 5.0 share rank 1 and the next distinct
      // value takes rank 3.
      expect([for (final e in board.entries) e.value], [5.0, 5.0, 6.0]);
      expect(ranks(board), [1, 1, 3]);
      // Display order within the tie: u3 has no rating history at all, so
      // comes before u2, whose last rating change is dated.
      expect(ids(board), ['u3', 'u2', 'u4']);
    });

    test('Least Active includes the member who never played', () async {
      final board = reverse(await load(), ReverseLeaderboardKind.leastActive);

      // u3 has no counter row for the period and measures as zero.
      expect(ids(board).first, 'u3');
      expect(board.entries.first.value, 0);
      expect(board.entries.first.rank, 1);
    });

    test('Least Active breaks a tie by the oldest last match', () async {
      final board = reverse(await load(), ReverseLeaderboardKind.leastActive);

      // u2 and u4 both played once. u2 last played on 5 Aug, u4 on 10 Aug, so
      // u2 is shown first — and both keep rank 2.
      expect(ids(board), ['u3', 'u2', 'u4']);
      expect(ranks(board), [1, 2, 2]);
    });

    test('Fewest Wins includes zero and puts never-won first', () async {
      final board = reverse(await load(), ReverseLeaderboardKind.fewestWins);

      // u3 and u4 both have zero wins and share rank 1. u3 has no win history
      // at all, so is shown before u4, whose history holds a dated win.
      expect(ids(board), ['u3', 'u4', 'u2']);
      expect([for (final e in board.entries) e.value], [0, 0, 1]);
      expect(ranks(board), [1, 1, 3]);
    });

    test('a tie with no history on either side falls to user id', () async {
      final adapter = _FakeAdapter(
        members: [member('zeta', 5), member('alpha', 5)],
        counters: const [],
        recency: const {},
      );
      final statistics = await load(adapter);

      for (final kind in ReverseLeaderboardKind.values) {
        final board = reverse(statistics, kind);
        expect(ids(board), ['alpha', 'zeta'], reason: kind.name);
        expect(ranks(board), [1, 1], reason: kind.name);
      }
    });

    test('tie order never changes a rank', () async {
      // The same values with the history flipped: u2 now has none and u3 has a
      // recent rating change, so the two tied at 5.0 swap places on screen.
      // Their ranks do not move — the tie-break orders the display and nothing
      // else.
      final adapter = fixture()
        ..recency = {'u3': history(rating: DateTime.utc(2026, 8, 30))};
      final board =
          reverse(await load(adapter), ReverseLeaderboardKind.lowestRated);

      expect(ids(board), ['u2', 'u3', 'u4']);
      expect(ranks(board), [1, 1, 3]);
    });

    test('monthly behaves the same way for missing counters', () async {
      final statistics = await load(fixture(), StatisticsPeriod.monthly);
      final active = reverse(statistics, ReverseLeaderboardKind.leastActive);
      final wins = reverse(statistics, ReverseLeaderboardKind.fewestWins);

      expect(active.entries.first.userId, 'u3');
      expect(active.entries.first.value, 0);
      expect(wins.entries.first.userId, 'u3');
      expect(wins.entries.first.value, 0);
    });

    test('a community with no members has no reverse boards', () async {
      final statistics = await load(
        _FakeAdapter(members: const [], counters: const [], recency: const {}),
      );
      expect(statistics.reverseBoards, isEmpty);
    });
  });

  group('the efficiency line on two positive boards', () {
    Leaderboard board(CommunityStatistics statistics, LeaderboardKind kind) =>
        statistics.boards.singleWhere((b) => b.kind == kind);

    test('Top Scorer still ranks by total goals', () async {
      final scorer = board(await load(), LeaderboardKind.topScorer);

      // u1: 6 goals in 4 (1.50 per match). u2: 3 goals in 1 (3.00 per match).
      // Goals per match would put u2 first; total goals puts u1 first.
      expect([for (final e in scorer.entries) e.userId], ['u1', 'u2']);
      expect([for (final e in scorer.entries) e.value], [6, 3]);
      expect([for (final e in scorer.entries) e.secondary], [1.5, 3.0]);
    });

    test('Most Wins still ranks by total wins', () async {
      final wins = board(await load(), LeaderboardKind.mostWins);

      // u1: 3 wins, 1 draw in 4 (2.50 PPG). u2: 1 win in 1 (3.00 PPG). PPG
      // would put u2 first; total wins puts u1 first.
      expect([for (final e in wins.entries) e.userId], ['u1', 'u2']);
      expect([for (final e in wins.entries) e.value], [3, 1]);
      expect([for (final e in wins.entries) e.secondary], [2.5, 3.0]);
    });

    test('the other positive boards carry no secondary value', () async {
      final statistics = await load();
      for (final kind in [
        LeaderboardKind.highestRated,
        LeaderboardKind.mostMvp,
        LeaderboardKind.mostActive,
      ]) {
        expect(
          board(statistics, kind).entries.every((e) => e.secondary == null),
          isTrue,
          reason: kind.name,
        );
      }
    });

    test('goals per match', () {
      expect(StatisticsRepository.goalsPerMatch(6, 4), 1.5);
      expect(StatisticsRepository.goalsPerMatch(3, 1), 3.0);
      expect(StatisticsRepository.goalsPerMatch(5, 0), 0);
    });

    test('points per game uses three for a win and one for a draw', () {
      expect(StatisticsRepository.pointsPerGame(3, 1, 4), 2.5);
      expect(StatisticsRepository.pointsPerGame(1, 0, 1), 3.0);
      expect(StatisticsRepository.pointsPerGame(0, 2, 2), 1.0);
      expect(StatisticsRepository.pointsPerGame(4, 0, 0), 0);
    });
  });

  group('the Community Statistics page', () {
    Future<void> pumpTab(WidgetTester tester) async {
      // Tall enough that nothing needs scrolling into view.
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityStatisticsTab(
            communityId: 'c1',
            communityName: 'Al Amerat FC',
            repository: StatisticsRepository(fixture()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the reverse section is collapsed by default', (tester) async {
      await pumpTab(tester);

      expect(find.text('Reverse Statistics'), findsOneWidget);
      expect(find.byType(ReverseLeaderboardCard), findsNothing);
      expect(find.text('Lowest Rated'), findsNothing);
    });

    testWidgets('opening it shows exactly the three reverse boards',
        (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Reverse Statistics'));
      await tester.pumpAndSettle();

      expect(find.byType(ReverseLeaderboardCard), findsNWidgets(3));
      expect(
        [
          for (final card in tester.widgetList<ReverseLeaderboardCard>(
            find.byType(ReverseLeaderboardCard),
          ))
            card.board.kind,
        ],
        ReverseLeaderboardKind.values,
      );
      expect(find.text('Lowest Rated'), findsOneWidget);
      expect(find.text('Least Active'), findsOneWidget);
      expect(find.text('Fewest Wins'), findsOneWidget);
    });

    testWidgets('the positive boards are the same five, in the same order',
        (tester) async {
      await pumpTab(tester);

      expect(
        [
          for (final card in tester.widgetList<LeaderboardCard>(
            find.byType(LeaderboardCard),
          ))
            card.board.kind,
        ],
        LeaderboardKind.values,
      );
    });

    testWidgets('the efficiency line sits under the two leaders',
        (tester) async {
      await pumpTab(tester);

      // Leaders only — the runners-up are behind "Show more".
      expect(find.text('1.50 per match'), findsOneWidget);
      expect(find.text('2.50 PPG'), findsOneWidget);
    });
  });

  group('the Community Statistics share card', () {
    test('it reads nothing this feature added', () {
      // The share card iterates `LeaderboardKind.values` and switches on it
      // exhaustively; reverse boards have their own enum precisely so that it
      // could stay as approved. Its existing suite runs unchanged alongside.
      final source = File(
        'lib/features/statistics/community_statistics_card.dart',
      ).readAsStringSync();

      for (final absent in [
        'reverseBoards',
        'ReverseLeaderboard',
        'secondary',
        'leaderboardGoalsPerMatch',
        'leaderboardPointsPerGame',
        'goalsPerMatch',
        'pointsPerGame',
      ]) {
        expect(source, isNot(contains(absent)), reason: absent);
      }
    });
  });
}

class _FakeAdapter implements StatisticsAdapter {
  _FakeAdapter({
    required this.members,
    required this.counters,
    required this.recency,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> counters;
  Map<String, PlayerAchievementRecency> recency;

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      counters;

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      5;

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async =>
      members;

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      recency;

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError();

  @override
  Future<TeamOfPeriodWindow> fetchTeamOfPeriodWindow(
    String communityId,
    TeamOfPeriodKind kind,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<TeamOfPeriodCandidate>> fetchTeamOfPeriodCandidates(
    String communityId,
    TeamOfPeriodKind kind,
  ) =>
      throw UnimplementedError();

  @override
  Future<Map<String, TeamOfPeriodPlayerIdentity>>
      fetchTeamOfPeriodPlayerIdentities(Iterable<String> userIds) =>
          throw UnimplementedError();
}
