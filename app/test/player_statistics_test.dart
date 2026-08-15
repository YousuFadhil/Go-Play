import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/statistics/player_statistics_screen.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_period_selector.dart';
import 'package:go_play/features/statistics/stat_card.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Player Statistics screen against a fake result port.
///
/// The screen adds no data layer: `ResultRepository.fetchStatistics` already
/// returned these seven figures and had no reader until now. So there is no
/// product reasoning between the port and the screen to test separately —
/// what is asserted is what the screen shows of a career, and what it refuses
/// to offer.
void main() {
  /// A player mid-season.
  const played = PlayerStatistics(
    userId: 'u1',
    matchesPlayed: 9,
    wins: 5,
    losses: 3,
    draws: 1,
    goals: 12,
    mvpCount: 2,
    currentRating: 7.42,
  );

  /// A player who has registered and played nothing: the counters a career
  /// starts with, and the rating every account is given.
  const fresh = PlayerStatistics.none('u1', 5.0);

  Future<void> pumpStatistics(
    WidgetTester tester,
    FakeResultAdapter adapter, {
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: PlayerStatisticsScreen(
        // Named explicitly so the screen never reaches for a session: whose
        // record to show is the caller's business, not this screen's.
        userId: 'u1',
        repository: ResultRepository(adapter),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  group('loading', () {
    testWidgets('shows the indicator until the figures arrive', (tester) async {
      final gate = Completer<void>();
      await pumpStatistics(
        tester,
        FakeResultAdapter(statistics: played, gate: gate.future),
        settle: false,
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a load that fails offers a retry', (tester) async {
      final adapter = FakeResultAdapter(
        statistics: played,
        failure: const NetworkFailure(),
      );
      await pumpStatistics(tester, adapter);

      expect(find.text('Failed to load data.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.reads, 2);
    });
  });

  group('what the screen shows', () {
    testWidgets('all seven figures are on it', (tester) async {
      await pumpStatistics(tester, FakeResultAdapter(statistics: played));

      expect(find.text('Current rating'), findsOneWidget);
      expect(find.text('7.4'), findsOneWidget);

      expect(find.text('Matches played'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Wins'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Draws'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Losses'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Best player awards'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('the rating is shown to one decimal place (OP-1)',
        (tester) async {
      // The stored scale is two decimals, because the engine moves a rating by
      // 0.05 for a goal. The presentation rule is one, and the screen must not
      // leak the second.
      await pumpStatistics(tester, FakeResultAdapter(statistics: played));

      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('7.42'), findsNothing);
    });

    testWidgets('a whole rating still shows its decimal', (tester) async {
      await pumpStatistics(tester, FakeResultAdapter(statistics: fresh));

      expect(find.text('5.0'), findsOneWidget,
          reason: '"5" would read as a different kind of number');
    });

    testWidgets('a player who has played nothing sees zeros and is told why',
        (tester) async {
      await pumpStatistics(tester, FakeResultAdapter(statistics: fresh));

      expect(find.text('0'), findsNWidgets(6),
          reason: 'six counters, all of them genuinely zero');
      expect(
        find.textContaining('have not played a recorded match'),
        findsOneWidget,
      );
    });

    testWidgets('a player who has played is not told they have not',
        (tester) async {
      await pumpStatistics(tester, FakeResultAdapter(statistics: played));

      expect(find.textContaining('have not played a recorded match'),
          findsNothing);
    });

    testWidgets('the scope of the figures is stated', (tester) async {
      // These are career figures across every community, and they count only
      // matches whose result was saved. Neither is evident from the numbers.
      await pumpStatistics(tester, FakeResultAdapter(statistics: played));

      expect(find.textContaining('every community'), findsOneWidget);
    });
  });

  group('what the screen does not offer', () {
    testWidgets('nothing on it is editable (OP-1)', (tester) async {
      // The rating is system-managed and every counter is a consequence of a
      // recorded result. There is no client write path for any of them, so
      // there is nothing here to type into or submit.
      await pumpStatistics(tester, FakeResultAdapter(statistics: played));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('it reads once and writes nothing', (tester) async {
      final adapter = FakeResultAdapter(statistics: played);
      await pumpStatistics(tester, adapter);

      expect(adapter.reads, 1);
      expect(adapter.writes, 0);
    });
  });

  group('localization', () {
    testWidgets('Arabic renders the screen in Arabic', (tester) async {
      await pumpStatistics(tester, FakeResultAdapter(statistics: played),
          locale: const Locale('ar'));

      expect(find.text('إحصائياتي'), findsOneWidget);
      expect(find.text('التقييم الحالي'), findsOneWidget);
      expect(find.text('المباريات المُلعوبة'), findsOneWidget);
      expect(find.text('الأهداف'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('التقييم الحالي'))),
        TextDirection.rtl,
      );
    });

    testWidgets('the rating reads the same in both locales', (tester) async {
      // A rating is a number, not a word. It must not be localized into digits
      // the rest of the app does not use.
      await pumpStatistics(tester, FakeResultAdapter(statistics: played),
          locale: const Locale('ar'));

      expect(find.text('7.4'), findsOneWidget);
    });
  });

  // --- periods -----------------------------------------------------------------

  CommunityPlayerStatistics record(
    String communityId, {
    int played = 0,
    int wins = 0,
    int losses = 0,
    int draws = 0,
    int goals = 0,
    int mvp = 0,
  }) =>
      CommunityPlayerStatistics(
        userId: 'u1',
        // The read takes no profile embed: these rows are summed into six
        // numbers and never name anybody.
        fullName: null,
        matchesPlayed: played,
        wins: wins,
        losses: losses,
        draws: draws,
        goals: goals,
        mvpCount: mvp,
      );

  /// One player, two communities, one week. The whole point of the read is that
  /// the two are added together rather than shown apart.
  final weekAcrossTwoCommunities = [
    record('c1', played: 2, wins: 1, losses: 1, goals: 3, mvp: 1),
    record('c2', played: 1, draws: 1, goals: 1),
  ];

  group('a player total for a period', () {
    test('the records of every community are added together', () async {
      final adapter = FakePlayerPeriodAdapter(
        records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
      );

      final totals = await StatisticsRepository(adapter)
          .fetchPlayerPeriodStatistics('u1', StatisticsPeriod.weekly);

      expect(adapter.asked, [StatisticsPeriod.weekly]);
      expect(totals.matchesPlayed, 3);
      expect(totals.wins, 1);
      expect(totals.losses, 1);
      expect(totals.draws, 1);
      expect(totals.goals, 4);
      expect(totals.mvpCount, 1);
    });

    test('a month is read as a month, not as a week', () async {
      final adapter = FakePlayerPeriodAdapter(
        records: {
          StatisticsPeriod.weekly: weekAcrossTwoCommunities,
          StatisticsPeriod.monthly: [
            record('c1', played: 8, wins: 5, losses: 2, draws: 1, goals: 11,
                mvp: 3),
          ],
        },
      );

      final totals = await StatisticsRepository(adapter)
          .fetchPlayerPeriodStatistics('u1', StatisticsPeriod.monthly);

      expect(adapter.asked, [StatisticsPeriod.monthly]);
      expect(totals.matchesPlayed, 8);
      expect(totals.goals, 11);
      expect(totals.mvpCount, 3);
    });

    test('a period the player did not play in is six zeros', () async {
      // The database deletes a periodic record with nothing in it, so "no rows"
      // and "all zeros" are the same statement -- and the screen must show the
      // second rather than an error or an absence.
      final totals = await StatisticsRepository(
        FakePlayerPeriodAdapter(records: const {}),
      ).fetchPlayerPeriodStatistics('u1', StatisticsPeriod.weekly);

      expect(totals.matchesPlayed, 0);
      expect(totals.wins, 0);
      expect(totals.losses, 0);
      expect(totals.draws, 0);
      expect(totals.goals, 0);
      expect(totals.mvpCount, 0);
    });

    test('All Time is not answered here', () async {
      // The career has a source already, in the Result domain. Summing the
      // player's `overall` records would build a second one free to disagree
      // with it, so the request is refused rather than quietly served.
      expect(
        () => StatisticsRepository(FakePlayerPeriodAdapter(records: const {}))
            .fetchPlayerPeriodStatistics('u1', StatisticsPeriod.allTime),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('choosing a period on the player screen', () {
    Future<void> pumpPeriods(
      WidgetTester tester,
      FakeResultAdapter results,
      FakePlayerPeriodAdapter periods, {
      Locale locale = const Locale('en'),
      Size size = const Size(900, 1600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PlayerStatisticsScreen(
          userId: 'u1',
          repository: ResultRepository(results),
          statistics: StatisticsRepository(periods),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('all three periods are offered, and it opens on All time',
        (tester) async {
      final periods = FakePlayerPeriodAdapter(records: const {});
      await pumpPeriods(
          tester, FakeResultAdapter(statistics: played), periods);

      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
      expect(
        tester
            .widget<StatisticsPeriodSelector>(
                find.byType(StatisticsPeriodSelector))
            .selected,
        StatisticsPeriod.allTime,
      );
      // All Time is the career read and nothing else: the period port is not
      // touched at all.
      expect(periods.asked, isEmpty);
    });

    testWidgets('All Time still shows the career, from the career source',
        (tester) async {
      await pumpPeriods(
        tester,
        FakeResultAdapter(statistics: played),
        FakePlayerPeriodAdapter(
          records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
        ),
      );

      expect(find.text('9'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.textContaining('every community'), findsOneWidget);
    });

    testWidgets('a week shows the week, summed across communities',
        (tester) async {
      final periods = FakePlayerPeriodAdapter(
        records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
      );
      await pumpPeriods(
          tester, FakeResultAdapter(statistics: played), periods);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      expect(periods.asked, [StatisticsPeriod.weekly]);
      // Three matches and four goals, not the career's nine and twelve.
      expect(find.widgetWithText(StatCard, 'Matches played'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('the rating does not change with the period, and says so',
        (tester) async {
      // `OP-1` gives the Global Rating no periodic form. The screen shows the
      // one rating there is and names it for what it is, rather than making a
      // week's rating up.
      await pumpPeriods(
        tester,
        FakeResultAdapter(statistics: played),
        FakePlayerPeriodAdapter(
          records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
        ),
      );

      expect(find.text('7.4'), findsOneWidget);
      expect(find.textContaining('not a figure for this period'), findsNothing);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      expect(find.text('7.4'), findsOneWidget);
      expect(
          find.textContaining('not a figure for this period'), findsOneWidget);
    });

    testWidgets('a period the player sat out reads as zero, not as a new career',
        (tester) async {
      await pumpPeriods(
        tester,
        // Nine matches behind them: this is not a player who has never played.
        FakeResultAdapter(statistics: played),
        FakePlayerPeriodAdapter(records: const {}),
      );

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsNWidgets(6));
      expect(
          find.textContaining('have not played a recorded match in this period'),
          findsOneWidget);
      expect(find.textContaining('starting rating'), findsNothing,
          reason: 'their rating is nine matches old, not a starting one');
    });

    testWidgets('and back to All Time restores the career', (tester) async {
      final periods = FakePlayerPeriodAdapter(records: const {});
      await pumpPeriods(
          tester, FakeResultAdapter(statistics: played), periods);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();

      expect(find.text('9'), findsOneWidget);
      expect(find.textContaining('every community'), findsOneWidget);
      expect(find.textContaining('not a figure for this period'), findsNothing);
    });

    testWidgets('nothing on it becomes editable in a period', (tester) async {
      await pumpPeriods(
        tester,
        FakeResultAdapter(statistics: played),
        FakePlayerPeriodAdapter(
          records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
        ),
      );

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('the selector survives a narrow screen in English and Arabic',
        (tester) async {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        await pumpPeriods(
          tester,
          FakeResultAdapter(statistics: played),
          FakePlayerPeriodAdapter(records: const {}),
          locale: locale,
          size: const Size(320, 640),
        );

        expect(find.byType(StatisticsPeriodSelector), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'a period label must shrink rather than overflow');
      }
    });

    testWidgets('Arabic names all three periods in Arabic', (tester) async {
      await pumpPeriods(
        tester,
        FakeResultAdapter(statistics: played),
        FakePlayerPeriodAdapter(
          records: {StatisticsPeriod.weekly: weekAcrossTwoCommunities},
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('أسبوعي'), findsOneWidget);
      expect(find.text('شهري'), findsOneWidget);
      expect(find.text('الكل'), findsOneWidget);

      await tester.tap(find.text('أسبوعي'));
      await tester.pumpAndSettle();

      expect(find.textContaining('بتوقيت عُمان'), findsOneWidget);
    });
  });
}

/// The statistics port, answering one player's period records from memory.
///
/// A period nobody stocked returns nothing, which is what the database returns
/// for a period the player did not play in — it deletes a periodic record with
/// nothing in it.
class FakePlayerPeriodAdapter implements StatisticsAdapter {
  FakePlayerPeriodAdapter({required this.records});

  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> records;

  /// Every period asked for, in order.
  final List<StatisticsPeriod> asked = [];

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) async {
    asked.add(period);
    return records[period] ?? const [];
  }

  /// The player's own screen reads no community's figures. Reaching any of
  /// these from it would be a defect, so they fail loudly rather than answer.
  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the player screen reads no community counters');

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the player screen reads no match totals');

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      throw UnimplementedError('the player screen reads no roster');
}

/// The result port, answering a career from memory and counting what it was
/// asked for.
class FakeResultAdapter implements ResultAdapter {
  FakeResultAdapter({required this.statistics, this.failure, this.gate});

  final PlayerStatistics statistics;
  final Failure? failure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;
  int writes = 0;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async {
    reads++;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return statistics;
  }

  /// This screen records nothing and reads no single match. Reaching any of
  /// these from it would be a defect, so they fail loudly rather than answer.
  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) async {
    writes++;
    throw UnimplementedError('the statistics screen records nothing');
  }

  @override
  Future<MatchResult?> fetchResult(String matchId) =>
      throw UnimplementedError('the statistics screen reads no match');

  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) =>
      throw UnimplementedError('the statistics screen reads no audit');
}
