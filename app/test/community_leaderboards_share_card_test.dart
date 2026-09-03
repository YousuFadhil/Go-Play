import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/statistics/community_leaderboards_card.dart';
import 'package:go_play/features/statistics/community_leaderboards_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community Leaderboards share card, and the tab's way of producing one.
///
/// **The card decides nothing about who is ahead.** Cycle B1 settled the order
/// — value, then how recently the measure was achieved, then name, then id —
/// and settled that competition rank comes from the value alone. What is
/// asserted here is that the card prints what it was handed: the same rows, in
/// the same order, with the same ranks.
void main() {
  LeaderboardEntry entry(int rank, String name, num value) =>
      LeaderboardEntry(userId: 'u-$name', fullName: name, rank: rank,
          value: value);

  Leaderboard board(LeaderboardKind kind, List<LeaderboardEntry> entries) =>
      Leaderboard(kind: kind, entries: entries);

  /// Five boards, each with three players, all values distinct so a figure on
  /// the card can only have come from one of them.
  List<Leaderboard> fiveBoards() => [
        board(LeaderboardKind.highestRated, [
          entry(1, 'Ali', 8.4),
          entry(2, 'Sara', 7.9),
          entry(3, 'Omar', 7.1),
        ]),
        board(LeaderboardKind.topScorer, [
          entry(1, 'Yousef', 21),
          entry(2, 'Khalid', 17),
          entry(3, 'Noor', 12),
        ]),
        board(LeaderboardKind.mostMvp, [entry(1, 'Sara', 9)]),
        board(LeaderboardKind.mostActive, [entry(1, 'Omar', 31)]),
        board(LeaderboardKind.mostWins, [entry(1, 'Ali', 23)]),
      ];

  CommunityLeaderboardsCardData data({
    List<Leaderboard>? boards,
    String communityName = 'Al Amerat Friday Football',
    StatisticsPeriod period = StatisticsPeriod.allTime,
  }) =>
      CommunityLeaderboardsCardData(
        communityName: communityName,
        period: period,
        boards: boards ?? fiveBoards(),
      );

  Future<void> pumpCard(
    WidgetTester tester,
    CommunityLeaderboardsCardData card, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: ShareCardSurface(child: CommunityLeaderboardsCard(data: card)),
        ),
      ),
    ));
    await tester.pump();
  }

  group('what the card carries', () {
    testWidgets('the community, the period and all five measures',
        (tester) async {
      await pumpCard(tester, data(period: StatisticsPeriod.weekly));

      expect(find.text('Al Amerat Friday Football'), findsOneWidget);
      expect(find.text('Period · Weekly'), findsOneWidget);

      for (final heading in [
        'HIGHEST RATED',
        'TOP SCORER',
        'MOST VALUABLE PLAYER',
        'MOST ACTIVE',
        'MOST WINS',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: '$heading missing');
      }
    });

    testWidgets('each supplied row keeps its rank, name and value',
        (tester) async {
      await pumpCard(tester, data());

      // Top Scorer, as supplied.
      expect(find.text('Yousef'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('Khalid'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('Noor'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);

      // A rating keeps its decimal; a count does not gain one.
      expect(find.text('8.4'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
    });

    testWidgets('up to three rows a category, and no more', (tester) async {
      await pumpCard(tester, data());

      // Three on Top Scorer, one each on the three single-entry boards.
      expect(find.text('Yousef'), findsOneWidget);
      expect(find.text('Khalid'), findsOneWidget);
      expect(find.text('Noor'), findsOneWidget);
      // Sara appears on Highest Rated and on Most MVP, and nowhere else.
      expect(find.text('Sara'), findsNWidgets(2));
    });

    testWidgets('no Dashboard totals appear on it', (tester) async {
      // The two cards answer different questions. This one must not quietly
      // become the other.
      await pumpCard(tester, data());

      for (final label in [
        'MATCHES',
        'PLAYERS',
        'GOALS',
        'Matches',
        'Players',
      ]) {
        expect(find.text(label), findsNothing,
            reason: '$label belongs to the Community Statistics card');
      }
    });

    testWidgets('one Go Play mark, at the foot', (tester) async {
      await pumpCard(tester, data());

      final mark = find.text('GO PLAY');
      expect(mark, findsOneWidget);
      expect(tester.getCenter(mark).dy,
          greaterThan(tester.getCenter(find.text('MOST WINS')).dy));
    });
  });

  group('the order is the repository\'s', () {
    testWidgets('rows appear in the order supplied, not alphabetically',
        (tester) async {
      // Deliberately anti-alphabetical: if the card sorted by name, Ahmed would
      // come first. B1 put Yousef first, and the card prints that.
      await pumpCard(
        tester,
        data(boards: [
          board(LeaderboardKind.topScorer, [
            entry(1, 'Yousef', 8),
            entry(1, 'Ahmed', 8),
            entry(3, 'Khalid', 6),
          ]),
        ]),
      );

      expect(tester.getCenter(find.text('Yousef')).dy,
          lessThan(tester.getCenter(find.text('Ahmed')).dy));
      expect(tester.getCenter(find.text('Ahmed')).dy,
          lessThan(tester.getCenter(find.text('Khalid')).dy));
    });

    testWidgets('a tie keeps the equal ranks it was given', (tester) async {
      // The specification's own example: 8, 8, 6 ranks 1, 1, 3. The card must
      // not renumber them 1, 2, 3.
      await pumpCard(
        tester,
        data(boards: [
          board(LeaderboardKind.topScorer, [
            entry(1, 'Yousef', 8),
            entry(1, 'Ahmed', 8),
            entry(3, 'Khalid', 6),
          ]),
        ]),
      );

      expect(find.text('1'), findsNWidgets(2), reason: 'two players rank 1');
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing,
          reason: 'the tie used up second place');
    });
  });

  group('a category with nobody on it', () {
    testWidgets('keeps its heading and shows a dash', (tester) async {
      // The repository builds no board for a measure nobody has achieved. The
      // card still has five sections: a reader comparing two cards should find
      // the same headings on both.
      await pumpCard(
        tester,
        data(boards: [
          board(LeaderboardKind.topScorer, [entry(1, 'Yousef', 8)]),
        ]),
      );

      for (final heading in [
        'HIGHEST RATED',
        'TOP SCORER',
        'MOST VALUABLE PLAYER',
        'MOST ACTIVE',
        'MOST WINS',
      ]) {
        expect(find.text(heading), findsOneWidget);
      }
      // Four empty categories, one dash each.
      expect(find.text('—'), findsNWidgets(4));
    });

    testWidgets('a card with no boards at all still has five sections',
        (tester) async {
      await pumpCard(tester, data(boards: const []));

      expect(find.text('—'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  });

  group('it holds together at the size it is captured', () {
    testWidgets('long Arabic names and a long community name do not overflow',
        (tester) async {
      await pumpCard(
        tester,
        data(
          communityName: 'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات',
          boards: [
            for (final kind in LeaderboardKind.values)
              board(kind, [
                entry(1, 'عبدالرحمن بن سليمان بن خميس الحارثي المعمري', 21),
                entry(2, 'محمد بن عبدالله بن سالم البلوشي الزدجالي', 17),
                entry(3, 'أحمد بن ناصر بن حمد الكندي', 12),
              ]),
          ],
        ),
        locale: const Locale('ar'),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('it fills the share canvas exactly', (tester) async {
      await pumpCard(tester, data());

      expect(tester.getSize(find.byType(CommunityLeaderboardsCard)),
          ShareCardCanvas.designSize);
    });
  });

  // --- the tab that produces it -------------------------------------------------

  group('sharing from the Leaderboards tab', () {
    Future<_FakeAdapter> pumpTab(
      WidgetTester tester, {
      required CapturingRenderer renderer,
      String? communityName = 'Al Amerat Friday Football',
      _FakeAdapter? adapter,
    }) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final port = adapter ?? _FakeAdapter();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityLeaderboardsTab(
            communityId: 'c1',
            communityName: communityName,
            repository: StatisticsRepository(port),
            renderer: renderer,
            shareService: FakeShareService(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return port;
    }

    Future<void> tapShare(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('shareLeaderboardsButton')));
      await tester.pumpAndSettle();
    }

    CommunityLeaderboardsCard cardOf(CapturingRenderer renderer) {
      final built = renderer.captured!(
        // The template takes a context only to read localizations; the engine
        // supplies a real one and this stands in for the assertion.
        _NullContext(),
      );
      return built as CommunityLeaderboardsCard;
    }

    testWidgets('the card is composed from the loaded boards, with no reload',
        (tester) async {
      final renderer = CapturingRenderer();
      final adapter = await pumpTab(tester, renderer: renderer);
      final readsBefore = adapter.boardReads;

      await tapShare(tester);

      expect(renderer.renders, 1);
      expect(adapter.boardReads, readsBefore,
          reason: 'sharing pictures what is on screen; it does not ask again');
    });

    testWidgets('the card carries the selected period', (tester) async {
      final renderer = CapturingRenderer();
      await pumpTab(tester, renderer: renderer);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tapShare(tester);

      expect(cardOf(renderer).data.period, StatisticsPeriod.weekly);
    });

    testWidgets('switching period again shares the newer one', (tester) async {
      final renderer = CapturingRenderer();
      await pumpTab(tester, renderer: renderer);

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tapShare(tester);

      expect(cardOf(renderer).data.period, StatisticsPeriod.monthly);
    });

    testWidgets('the card carries the repository output, entry for entry',
        (tester) async {
      // The same repository and the same adapter, asked directly: whatever
      // order it produced is the order the card must show, kind for kind and
      // row for row. Nothing between the two may reorder it.
      final renderer = CapturingRenderer();
      await pumpTab(tester, renderer: renderer, adapter: _FakeAdapter());

      await tapShare(tester);

      final expected =
          await StatisticsRepository(_FakeAdapter()).fetchLeaderboards('c1');
      final onCard = cardOf(renderer).data.boards;

      expect([for (final b in onCard) b.kind],
          [for (final b in expected) b.kind]);
      for (final board in expected) {
        final mine =
            onCard.firstWhere((other) => other.kind == board.kind).entries;
        expect([for (final e in mine) e.userId],
            [for (final e in board.entries) e.userId],
            reason: 'row order for ${board.kind}');
        expect([for (final e in mine) e.rank],
            [for (final e in board.entries) e.rank],
            reason: 'ranks for ${board.kind}');
      }
    });

    testWidgets('Share is withheld until there is a community to name it',
        (tester) async {
      final renderer = CapturingRenderer();
      await pumpTab(tester, renderer: renderer, communityName: null);

      final button = tester.widget<IconButton>(
        find.byKey(const Key('shareLeaderboardsButton')),
      );
      expect(button.onPressed, isNull);
    });
  });
}

/// A `BuildContext` the template never actually uses for layout — the card is
/// constructed, not built, in the assertions above.
class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The statistics port, answering boards from memory and counting its reads.
class _FakeAdapter implements StatisticsAdapter {
  int boardReads = 0;

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async {
    boardReads++;
    return const [
      CommunityMemberRating(userId: 'u1', fullName: 'Ali', rating: 8.4),
      CommunityMemberRating(userId: 'u2', fullName: 'Sara', rating: 7.9),
    ];
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      const [
        CommunityPlayerStatistics(
          userId: 'u1',
          fullName: 'Ali',
          matchesPlayed: 6,
          wins: 4,
          losses: 1,
          draws: 1,
          goals: 9,
          mvpCount: 2,
        ),
      ];

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
      6;

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError();
}

/// The Share Card Engine's renderer port, keeping the template it was given.
class CapturingRenderer implements ShareCardRenderer {
  ShareCardTemplate? captured;
  int renders = 0;

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    renders++;
    captured = template;
    return ShareCardImage(
      bytes: Uint8List.fromList(_pixel),
      pixelWidth: 1080,
      pixelHeight: 1920,
    );
  }
}

/// The share port, sharing nothing.
class FakeShareService implements ShareService {
  final List<ShareCardImage> shared = [];

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    shared.add(image);
    return ShareOutcome.shared;
  }
}

/// A valid one-pixel PNG, so the preview decodes something real.
const _pixel = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
