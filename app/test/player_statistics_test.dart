import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/statistics/player_statistics_screen.dart';

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
