import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/statistics/community_statistics_card.dart';
import 'package:go_play/features/statistics/community_statistics_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The one Community Statistics card.
///
/// There used to be two: the Dashboard's, carrying three totals and three
/// leaders, and the Leaderboards', carrying five boards three deep. Each tab
/// had its own period, so one community could be sent two pictures of itself
/// describing two different weeks. What is asserted here is the card that
/// replaced them — the three totals and the one player at the top of each of
/// the five measures, in the period the reader had selected and no other.
void main() {
  CommunityStatisticsLeader leader(
    LeaderboardKind kind,
    String name,
    num value, {
    String? avatar,
  }) =>
      CommunityStatisticsLeader(
        kind: kind,
        fullName: name,
        value: value,
        avatarUrl: avatar,
      );

  /// A card with all five measures led, which is the shape the contract names.
  CommunityStatisticsCardData data({
    StatisticsPeriod period = StatisticsPeriod.allTime,
    String communityName = 'Al Amerat FC',
    int matches = 6,
    int players = 3,
    int goals = 7,
    List<CommunityStatisticsLeader>? leaders,
  }) =>
      CommunityStatisticsCardData(
        communityName: communityName,
        period: period,
        completedMatches: matches,
        totalPlayers: players,
        totalGoals: goals,
        leaders: leaders ??
            [
              leader(LeaderboardKind.highestRated, 'Ali', 7.4,
                  avatar: 'https://example.test/u1.jpg'),
              leader(LeaderboardKind.topScorer, 'Ali', 5),
              leader(LeaderboardKind.mostMvp, 'Sara', 2),
              leader(LeaderboardKind.mostActive, 'Sara', 4),
              leader(LeaderboardKind.mostWins, 'Omar', 3),
            ],
      );

  Future<void> pumpCard(
    WidgetTester tester,
    CommunityStatisticsCardData card, {
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
          child: ShareCardSurface(child: CommunityStatisticsCard(data: card)),
        ),
      ),
    ));
    await tester.pump();
  }

  // --- the three totals ------------------------------------------------------

  group('the totals are passed through untouched', () {
    testWidgets('each figure appears as given, and none is derived',
        (tester) async {
      // Three values that cannot be confused for one another, and none of which
      // is the sum or difference of the others.
      await pumpCard(tester, data(matches: 6, players: 3, goals: 7));

      expect(find.text('6'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('MATCHES'), findsOneWidget);
      expect(find.text('PLAYERS'), findsOneWidget);
      expect(find.text('GOALS'), findsOneWidget);
    });

    testWidgets('they are read off the snapshot the tab is showing',
        (tester) async {
      // The card and the screen cannot report different numbers, because there
      // is one snapshot and the card copies it rather than recomputing.
      const statistics = CommunityStatistics(
        dashboard: CommunityDashboard(
          completedMatches: 11,
          totalPlayers: 4,
          totalGoals: 19,
          topScorer: null,
          mostActivePlayer: null,
          mostMvp: null,
        ),
        boards: [],
      );

      final card = CommunityStatisticsCardData.of(
        statistics,
        communityName: 'Al Amerat FC',
        period: StatisticsPeriod.monthly,
      );

      expect(card.completedMatches, 11);
      expect(card.totalPlayers, 4);
      expect(card.totalGoals, 19);
      expect(card.period, StatisticsPeriod.monthly);
      expect(card.hasLeaders, isFalse);
    });
  });

  // --- five leaders, first place only ---------------------------------------

  group('all five measures, and only their leaders', () {
    testWidgets('every measure the tab ranks is named on the card',
        (tester) async {
      await pumpCard(tester, data());

      expect(find.text('HIGHEST RATED'), findsOneWidget);
      expect(find.text('TOP SCORER'), findsOneWidget);
      expect(find.text('MOST VALUABLE PLAYER'), findsOneWidget);
      expect(find.text('MOST ACTIVE'), findsOneWidget);
      expect(find.text('MOST WINS'), findsOneWidget);
    });

    testWidgets('each figure is stated in its own words', (tester) async {
      await pumpCard(tester, data());

      // A rating is written as a rating — one decimal, no unit, because it is
      // not a count of anything.
      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('5 goals'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);
      expect(find.text('4 matches'), findsOneWidget);
      expect(find.text('3 wins'), findsOneWidget);
    });

    testWidgets('only the first place, never a runner-up', (tester) async {
      // The board behind Top Scorer is three deep on screen. The card takes the
      // top of it and nothing else — this is what makes it a picture rather
      // than a table.
      const statistics = CommunityStatistics(
        dashboard: CommunityDashboard(
          completedMatches: 6,
          totalPlayers: 3,
          totalGoals: 12,
          topScorer: null,
          mostActivePlayer: null,
          mostMvp: null,
        ),
        boards: [
          Leaderboard(
            kind: LeaderboardKind.topScorer,
            entries: [
              LeaderboardEntry(
                  userId: 'u1', fullName: 'Ali', rank: 1, value: 7),
              LeaderboardEntry(
                  userId: 'u2', fullName: 'Sara', rank: 2, value: 4),
              LeaderboardEntry(
                  userId: 'u3', fullName: 'Omar', rank: 3, value: 1),
            ],
          ),
        ],
      );

      final card = CommunityStatisticsCardData.of(
        statistics,
        communityName: 'Al Amerat FC',
        period: StatisticsPeriod.allTime,
      );

      expect(card.leaders, hasLength(1));
      expect(card.leaders.single.fullName, 'Ali');
      expect(card.leaders.single.value, 7);

      await pumpCard(tester, card);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Sara'), findsNothing);
      expect(find.text('Omar'), findsNothing);
    });

    testWidgets('a measure nobody leads is left off rather than filled in',
        (tester) async {
      await pumpCard(
        tester,
        data(leaders: [leader(LeaderboardKind.topScorer, 'Ali', 5)]),
      );

      expect(find.text('TOP SCORER'), findsOneWidget);
      expect(find.text('MOST WINS'), findsNothing);
      expect(find.text('HIGHEST RATED'), findsNothing);
    });

    testWidgets('a record that outlived its profile still counts',
        (tester) async {
      await pumpCard(
        tester,
        data(leaders: const [
          CommunityStatisticsLeader(
            kind: LeaderboardKind.topScorer,
            fullName: null,
            value: 9,
          ),
        ]),
      );

      expect(find.text('Former player'), findsOneWidget);
      expect(find.text('9 goals'), findsOneWidget);
    });

    testWidgets('a leader carries their face', (tester) async {
      await pumpCard(tester, data());
      expect(find.byType(PlayerAvatar), findsNWidgets(5));
    });
  });

  // --- the period the reader chose ------------------------------------------

  group('the card names the period it is a picture of', () {
    testWidgets('a week says so', (tester) async {
      await pumpCard(tester, data(period: StatisticsPeriod.weekly));
      expect(find.text('Weekly'), findsOneWidget);
    });

    testWidgets('all time says so', (tester) async {
      await pumpCard(tester, data(period: StatisticsPeriod.allTime));
      expect(find.text('All time'), findsOneWidget);
    });
  });

  // --- the approved branding contract ---------------------------------------

  group('the branding is a signature, not a masthead', () {
    testWidgets('the wordmark appears once, and not above the community',
        (tester) async {
      // The card used to open on a large GO PLAY mark over an accent bar, which
      // said whose software this is before it said whose football it is.
      await pumpCard(tester, data());

      expect(find.text('GO PLAY'), findsOneWidget);

      final mark = tester.getCenter(find.text('GO PLAY'));
      final name = tester.getCenter(find.text('Al Amerat FC'));
      expect(mark.dy, greaterThan(name.dy),
          reason: 'the signature closes the card rather than opening it');
    });

    testWidgets('the decorative accent bar is gone', (tester) async {
      // A 132×6 block of accent green sat under the wordmark. It was the
      // masthead's underline, and it went with the masthead — there is no
      // accent-filled bar left anywhere on the card.
      await pumpCard(tester, data());

      final accentBars = find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.color == const Color(0xFF3DDC84),
      );
      expect(accentBars, findsNothing);
    });

    testWidgets('but the green that structures content stays', (tester) async {
      // Not a monochrome redesign. The accent still names the leaders section,
      // and the rules bracketing the totals are still drawn — what was removed
      // is the branding above the community, not the card's own structure.
      await pumpCard(tester, data());

      final heading = tester.widget<Text>(find.text('LEADERS'));
      expect(heading.style?.color, const Color(0xFF3DDC84));

      final rules = find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxHeight == 2,
      );
      expect(rules, findsWidgets,
          reason: 'the totals keep the rules that bracket them');
    });
  });

  // --- long names and Arabic -------------------------------------------------

  group('long names and Arabic', () {
    testWidgets('a long community name and long players do not overflow',
        (tester) async {
      await pumpCard(
        tester,
        data(
          communityName:
              'The Extremely Long Community Name Football Association Of Muscat',
          leaders: [
            leader(LeaderboardKind.highestRated,
                'Abdulrahman Bin Sulaiman Al Harthy', 7.4),
            leader(LeaderboardKind.topScorer,
                'Mohammed Bin Abdullah Al Balushi', 12),
            leader(LeaderboardKind.mostMvp, 'Yousuf Al Amri', 3),
            leader(LeaderboardKind.mostActive, 'Salim Al Harthy', 9),
            leader(LeaderboardKind.mostWins, 'Ahmed Al Balushi', 6),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the Arabic card is the same card, read the other way',
        (tester) async {
      await pumpCard(
        tester,
        data(
          communityName: 'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات',
          period: StatisticsPeriod.weekly,
          leaders: [
            leader(LeaderboardKind.highestRated, 'عبدالرحمن بن سليمان الحارثي',
                7.4),
            leader(LeaderboardKind.topScorer, 'محمد بن عبدالله البلوشي', 12),
            leader(LeaderboardKind.mostMvp, 'يوسف العامري', 3),
            leader(LeaderboardKind.mostActive, 'سالم الحارثي', 9),
            leader(LeaderboardKind.mostWins, 'أحمد البلوشي', 6),
          ],
        ),
        locale: const Locale('ar'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('نادي المجتمع الرياضي لكرة القدم في ولاية العامرات'),
          findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(CommunityStatisticsCard))),
        TextDirection.rtl,
      );
    });
  });

  // --- the one action, and what it hands the engine --------------------------

  group('the tab shares what it is showing', () {
    const roster = [
      CommunityMemberRating(userId: 'u1', fullName: 'Ali', rating: 7.4),
      CommunityMemberRating(userId: 'u2', fullName: 'Sara', rating: 6.1),
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

    Future<_CapturingRenderer> pumpTab(
      WidgetTester tester, {
      String? communityName = 'Al Amerat FC',
      Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodRecords =
          const {},
      Map<StatisticsPeriod, int> periodMatches = const {},
    }) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final renderer = _CapturingRenderer();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityStatisticsTab(
            communityId: 'c1',
            communityName: communityName,
            repository: StatisticsRepository(_Adapter(
              members: roster,
              records: [
                record('u1', 'Ali', played: 3, goals: 5, mvp: 1, wins: 2),
                record('u2', 'Sara', played: 4, goals: 2, mvp: 2, wins: 1),
              ],
              completedMatches: 6,
              periodRecords: periodRecords,
              periodMatches: periodMatches,
            )),
            renderer: renderer,
            shareService: _FakeShareService(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return renderer;
    }

    Future<void> pumpTemplate(
      WidgetTester tester,
      _CapturingRenderer renderer,
    ) async {
      // Torn down first: pumping another `MaterialApp` would update the one
      // already mounted, keeping its Navigator and the preview route on top —
      // and everything under an opaque route is offstage, where `find.byType`
      // does not look.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Align(
          alignment: Alignment.topLeft,
          child: ShareCardSurface(child: Builder(builder: renderer.captured!)),
        ),
      ));
      await tester.pump();
    }

    CommunityStatisticsCard shownCard(WidgetTester tester) => tester
        .widget<CommunityStatisticsCard>(find.byType(CommunityStatisticsCard));

    testWidgets('there is exactly one Community Statistics share action',
        (tester) async {
      // Two tabs meant two buttons and two cards. One tab means one of each.
      await pumpTab(tester);

      expect(find.byTooltip('Share community statistics'), findsOneWidget);
      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      expect(find.byTooltip('Share leaderboards'), findsNothing);
    });

    testWidgets('it shares the totals and the five leaders on screen',
        (tester) async {
      final renderer = await pumpTab(tester);

      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();
      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.communityName, 'Al Amerat FC');
      expect(card.period, StatisticsPeriod.allTime);
      expect(card.completedMatches, 6);
      expect(card.totalPlayers, 2);
      expect(card.totalGoals, 7);

      // One row per measure, in the order the tab lists them, each a first
      // place.
      expect(card.leaders.map((l) => l.kind).toList(), LeaderboardKind.values);
      expect(card.leaders.map((l) => l.fullName).toList(),
          ['Ali', 'Ali', 'Sara', 'Sara', 'Ali']);
    });

    testWidgets('a week shares the week, without asking again', (tester) async {
      // The whole point of the one selector: the share flow never offers a
      // second period.
      final renderer = await pumpTab(
        tester,
        periodRecords: {
          StatisticsPeriod.weekly: [
            record('u1', 'Ali', played: 1, goals: 2, wins: 1),
          ],
        },
        periodMatches: {StatisticsPeriod.weekly: 1},
      );

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();
      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.period, StatisticsPeriod.weekly);
      expect(card.completedMatches, 1);
      expect(card.totalPlayers, 1);
      expect(card.totalGoals, 2);
    });

    testWidgets('an empty period invents no leaders', (tester) async {
      final renderer = await pumpTab(tester);

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();
      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.period, StatisticsPeriod.monthly);
      expect(card.completedMatches, 0);
      expect(card.totalGoals, 0);
      // Highest Rated survives an empty month: the rating is the Global Rating
      // and has no periodic form, so the roster still ranks. The four counted
      // measures do not.
      expect(card.leaders.map((l) => l.kind).toList(),
          [LeaderboardKind.highestRated]);
    });

    testWidgets('nothing can be shared without a community to put on it',
        (tester) async {
      await pumpTab(tester, communityName: null);

      final button = tester.widget<IconButton>(
        find.byKey(const Key('shareCommunityStatisticsButton')),
      );
      expect(button.onPressed, isNull,
          reason: 'disabled rather than hidden — an action that comes and goes '
              'reads as a bug');
    });
  });
}

/// The statistics port, answering from memory.
class _Adapter implements StatisticsAdapter {
  _Adapter({
    required this.members,
    required this.records,
    required this.completedMatches,
    this.periodRecords = const {},
    this.periodMatches = const {},
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> records;
  final int completedMatches;
  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodRecords;
  final Map<StatisticsPeriod, int> periodMatches;

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
      period == StatisticsPeriod.allTime
          ? records
          : periodRecords[period] ?? const [];

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      period == StatisticsPeriod.allTime
          ? completedMatches
          : periodMatches[period] ?? 0;

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      const {};

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the Statistics tab reads no player totals');
}

/// Keeps whatever template the tab handed the engine.
class _CapturingRenderer implements ShareCardRenderer {
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

/// The share port, sharing nothing.
class _FakeShareService implements ShareService {
  final List<ShareCardImage> shared = [];

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    shared.add(image);
    return ShareOutcome.shared;
  }
}
