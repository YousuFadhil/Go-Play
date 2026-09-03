import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/states.dart';
import 'package:go_play/features/statistics/community_leaderboards_tab.dart';
import 'package:go_play/features/statistics/community_statistics_tab.dart';
import 'package:go_play/features/statistics/stat_card.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_period_selector.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The one Statistics tab.
///
/// It replaces two: a Dashboard with three totals and three leader highlights,
/// and a Leaderboards tab with five boards — each with its own period selector,
/// its own load and its own Share action. What is asserted here is that they
/// became one thing rather than two things stacked: one selector that moves
/// everything, one read behind it, the three totals once, the five boards once,
/// and no second copy of the leaders in between.
void main() {
  const roster = [
    CommunityMemberRating(userId: 'u1', fullName: 'Ali', rating: 7.4),
    CommunityMemberRating(userId: 'u2', fullName: 'Sara', rating: 6.1),
    CommunityMemberRating(userId: 'u3', fullName: 'Omar', rating: 5.2),
  ];

  CommunityPlayerStatistics record(
    String id,
    String name, {
    int played = 0,
    int goals = 0,
    int mvp = 0,
    int wins = 0,
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

  final squad = [
    record('u1', 'Ali', played: 3, goals: 5, mvp: 1, wins: 2),
    record('u2', 'Sara', played: 4, goals: 2, mvp: 2, wins: 1),
    record('u3', 'Omar', played: 1),
  ];

  Future<_Adapter> pumpTab(
    WidgetTester tester, {
    List<CommunityPlayerStatistics>? records,
    List<CommunityMemberRating> members = roster,
    int completedMatches = 6,
    Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodRecords =
        const {},
    Map<StatisticsPeriod, int> periodMatches = const {},
    Failure? failure,
    Completer<void>? gate,
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = _Adapter(
      members: members,
      records: records ?? squad,
      completedMatches: completedMatches,
      periodRecords: periodRecords,
      periodMatches: periodMatches,
      failure: failure,
      gate: gate?.future,
    );

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: CommunityStatisticsTab(
          communityId: 'c1',
          communityName: 'Al Amerat FC',
          repository: StatisticsRepository(adapter),
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
    return adapter;
  }

  // --- one selector, and nothing beside it ----------------------------------

  group('one period, for the whole tab', () {
    testWidgets('there is exactly one selector', (tester) async {
      // Two tabs meant two selectors, and a reader could leave them describing
      // two different weeks. One tab means one.
      await pumpTab(tester);

      expect(find.byType(StatisticsPeriodSelector), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
    });

    testWidgets('it opens on All Time', (tester) async {
      final adapter = await pumpTab(tester);
      expect(adapter.counterReads, [StatisticsPeriod.allTime]);
    });

    testWidgets('choosing a week moves the totals and the boards together',
        (tester) async {
      await pumpTab(
        tester,
        periodRecords: {
          StatisticsPeriod.weekly: [
            record('u2', 'Sara', played: 1, goals: 3, wins: 1),
          ],
        },
        periodMatches: {StatisticsPeriod.weekly: 1},
      );

      // All Time first: six matches, three players, seven goals.
      expect(find.widgetWithText(StatCard, '6'), findsOneWidget);
      expect(find.widgetWithText(StatCard, '7'), findsOneWidget);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      // The totals moved…
      expect(find.widgetWithText(StatCard, '1'), findsWidgets);
      expect(find.widgetWithText(StatCard, '3'), findsOneWidget);
      // …and so did the boards, in the same gesture: Sara leads the week's
      // scoring, where Ali led all time.
      final scorers = find.widgetWithText(LeaderboardCard, 'Top scorer');
      expect(
        find.descendant(of: scorers, matching: find.text('Sara')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: scorers, matching: find.text('Ali')),
        findsNothing,
      );
    });

    testWidgets('a month is one read of each kind, not two', (tester) async {
      // The consolidation this tab exists for: the Dashboard and the boards
      // each used to fetch the counters and the recency for the same period.
      final adapter = await pumpTab(tester);
      adapter.counterReads.clear();
      adapter.recencyReads.clear();
      adapter.matchReads.clear();

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();

      expect(adapter.counterReads, [StatisticsPeriod.monthly]);
      expect(adapter.recencyReads, [StatisticsPeriod.monthly]);
      expect(adapter.matchReads, [StatisticsPeriod.monthly]);
    });

    testWidgets('choosing the period already selected reads nothing',
        (tester) async {
      final adapter = await pumpTab(tester);
      adapter.counterReads.clear();

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();

      expect(adapter.counterReads, isEmpty);
    });
  });

  // --- the three totals -----------------------------------------------------

  group('the community totals', () {
    testWidgets('completed matches, players and goals, once each',
        (tester) async {
      await pumpTab(tester);

      expect(find.byType(StatCard), findsNWidgets(3));
      expect(find.text('Completed matches'), findsOneWidget);
      expect(find.text('Total players'), findsOneWidget);
      expect(find.text('Total goals'), findsOneWidget);
    });

    testWidgets('and no fourth figure was invented', (tester) async {
      await pumpTab(tester);

      expect(find.text('Wins'), findsNothing);
      expect(find.text('Current rating'), findsNothing);
    });
  });

  // --- the five boards, and no duplicate highlights -------------------------

  group('the five boards', () {
    testWidgets('all five are drawn', (tester) async {
      await pumpTab(tester);

      expect(find.byType(LeaderboardCard), findsNWidgets(5));
      expect(find.text('Highest rated'), findsOneWidget);
      expect(find.text('Top scorer'), findsOneWidget);
      expect(find.text('Most valuable player'), findsOneWidget);
      expect(find.text('Most active'), findsOneWidget);
      expect(find.text('Most wins'), findsOneWidget);
    });

    testWidgets('the old Dashboard leader highlights are gone', (tester) async {
      // The Dashboard named the top scorer, the most active player and the most
      // valuable one in tiles above the boards — the same three players, with
      // the same figures, that the boards below already name.
      //
      // The tile labels and the board titles are the same words, so their
      // absence cannot be asserted by searching for the words. What says it is
      // the count: each measure is named **once** on this tab, and its leader
      // appears **once**. Two of each would be the duplication that is gone.
      await pumpTab(tester);

      expect(find.text('Top scorer'), findsOneWidget);
      expect(find.text('Most valuable player'), findsOneWidget);
      expect(find.text('Most active'), findsOneWidget);
      // The old tiles used a label of their own for the third measure. Nothing
      // on the tab says it any more.
      expect(find.text('Most active player'), findsNothing);
      expect(find.text('Leaders'), findsOneWidget);

      // Ali tops three of the five boards, so he is named three times — once on
      // each board, and not a fourth time in a highlight above them.
      expect(find.text('Ali'), findsNWidgets(3));
    });

    testWidgets('a runner-up is still one tap away', (tester) async {
      // What the share card leaves out, the screen keeps: second place is worth
      // reading, and the tab is where reading happens.
      await pumpTab(tester);

      final scorers = find.widgetWithText(LeaderboardCard, 'Top scorer');
      expect(
        find.descendant(of: scorers, matching: find.text('Sara')),
        findsNothing,
      );

      await tester
          .tap(find.descendant(of: scorers, matching: find.text('Show more')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: scorers, matching: find.text('Sara')),
        findsOneWidget,
      );
    });
  });

  // --- loading, failure, emptiness ------------------------------------------

  group('what it shows when there is nothing to show', () {
    testWidgets('a load in flight is a loading state, and the selector stays',
        (tester) async {
      final gate = Completer<void>();
      await pumpTab(tester, gate: gate, settle: false);
      await tester.pump();

      expect(find.byType(LoadingState), findsOneWidget);
      // The control a reader would use to get out of this state must not vanish
      // into the spinner.
      expect(find.byType(StatisticsPeriodSelector), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingState), findsNothing);
    });

    testWidgets('a failed read offers a retry rather than empty figures',
        (tester) async {
      await pumpTab(tester, failure: const NetworkFailure());

      expect(find.byType(ErrorState), findsOneWidget);
      // Nothing was fabricated to fill the gap.
      expect(find.byType(StatCard), findsNothing);
      expect(find.byType(LeaderboardCard), findsNothing);
    });

    testWidgets('a community with no results says so once, not five times',
        (tester) async {
      await pumpTab(tester,
          records: const [], members: const [], completedMatches: 0);

      expect(find.byType(LeaderboardCard), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      // The totals are still drawn: zero matches is an answer.
      expect(find.byType(StatCard), findsNWidgets(3));
    });

    testWidgets('a quiet week is not a community with no history',
        (tester) async {
      await pumpTab(tester,
          records: const [], members: const [], completedMatches: 0);
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No results have been recorded in this period, so there is nothing '
          'to rank yet.',
        ),
        findsOneWidget,
      );
    });
  });

  // --- Arabic ---------------------------------------------------------------

  group('Arabic', () {
    testWidgets('the tab reads right to left, with its own words',
        (tester) async {
      await pumpTab(tester, locale: const Locale('ar'));

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(
            tester.element(find.byType(StatisticsPeriodSelector))),
        TextDirection.rtl,
      );
      // Once, on its board — not again in a highlight above it.
      expect(find.text('الهدّاف'), findsOneWidget);
      expect(find.byType(LeaderboardCard), findsNWidgets(5));
    });
  });
}

/// The statistics port, answering from memory and counting what it was asked.
class _Adapter implements StatisticsAdapter {
  _Adapter({
    required this.members,
    required this.records,
    required this.completedMatches,
    this.periodRecords = const {},
    this.periodMatches = const {},
    this.failure,
    this.gate,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> records;
  final int completedMatches;
  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodRecords;
  final Map<StatisticsPeriod, int> periodMatches;
  final Failure? failure;

  /// Held open to keep a load pending while a test looks at it.
  final Future<void>? gate;

  /// Which period each read asked for, in order. The evidence that one
  /// selection produces one read of each kind rather than two.
  final List<StatisticsPeriod> counterReads = [];
  final List<StatisticsPeriod> matchReads = [];
  final List<StatisticsPeriod> recencyReads = [];
  int ratingReads = 0;

  Future<void> _wait() async {
    if (gate != null) await gate;
    if (failure != null) throw failure!;
  }

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async {
    ratingReads++;
    await _wait();
    return members;
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async {
    counterReads.add(period);
    await _wait();
    return period == StatisticsPeriod.allTime
        ? records
        : periodRecords[period] ?? const [];
  }

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async {
    matchReads.add(period);
    await _wait();
    return period == StatisticsPeriod.allTime
        ? completedMatches
        : periodMatches[period] ?? 0;
  }

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async {
    recencyReads.add(period);
    await _wait();
    return const {};
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the Statistics tab reads no player totals');
}
