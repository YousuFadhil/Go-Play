import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/statistics/community_dashboard_tab.dart';
import 'package:go_play/features/statistics/community_statistics_card.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community Statistics share card, and the Dashboard action that makes
/// one.
///
/// Two things are asserted and they are deliberately separate: what the card
/// draws when handed a period's figures, and that the Dashboard hands it the
/// figures and the period the reader is actually looking at. The Share Card
/// Engine is not retested here; it has its own suite.
void main() {
  StatisticLeader leader(String id, String? name, int value, {String? avatar}) =>
      StatisticLeader(
        userId: id,
        fullName: name,
        value: value,
        avatarUrl: avatar,
      );

  CommunityStatisticsCardData data({
    StatisticsPeriod period = StatisticsPeriod.allTime,
    int matches = 6,
    int players = 3,
    int goals = 7,
    StatisticLeader? topScorer,
    StatisticLeader? mostActive,
    StatisticLeader? mostMvp,
    bool leaders = true,
  }) =>
      CommunityStatisticsCardData(
        communityName: 'Al Amerat FC',
        period: period,
        completedMatches: matches,
        totalPlayers: players,
        totalGoals: goals,
        topScorer: leaders
            ? topScorer ??
                leader('u1', 'Ali', 5, avatar: 'https://example.test/u1.jpg')
            : null,
        mostActivePlayer: leaders ? mostActive ?? leader('u2', 'Sara', 4) : null,
        mostMvp: leaders ? mostMvp ?? leader('u2', 'Sara', 2) : null,
      );

  Future<void> pumpCard(
    WidgetTester tester,
    CommunityStatisticsCardData card, {
    Locale locale = const Locale('en'),
    GlobalKey? boundaryKey,
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
          key: boundaryKey ?? GlobalKey(),
          child: ShareCardSurface(child: CommunityStatisticsCard(data: card)),
        ),
      ),
    ));
    await tester.pump();
  }

  // --- the three totals, exactly as the Dashboard has them --------------------

  group('the totals are passed through untouched', () {
    testWidgets('each figure appears as given, and none is derived',
        (tester) async {
      // Deliberately three values that cannot be confused for one another, and
      // none of which is the sum or difference of the others.
      await pumpCard(tester, data(matches: 6, players: 3, goals: 7));

      expect(find.text('6'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('MATCHES'), findsOneWidget);
      expect(find.text('PLAYERS'), findsOneWidget);
      expect(find.text('GOALS'), findsOneWidget);
    });

    testWidgets('it reads them off the Dashboard model the screen is showing',
        (tester) async {
      // The card and the screen cannot report different numbers, because there
      // is one model and the card copies it rather than recomputing anything.
      const dashboard = CommunityDashboard(
        completedMatches: 11,
        totalPlayers: 4,
        totalGoals: 19,
        topScorer: null,
        mostActivePlayer: null,
        mostMvp: null,
      );

      final card = CommunityStatisticsCardData.of(
        dashboard,
        communityName: 'Al Amerat FC',
        period: StatisticsPeriod.monthly,
      );

      expect(card.completedMatches, 11);
      expect(card.totalPlayers, 4);
      expect(card.totalGoals, 19);
      expect(card.period, StatisticsPeriod.monthly);
      expect(card.communityName, 'Al Amerat FC');
      expect(card.hasLeaders, isFalse);
    });

    testWidgets('a community name is on the card', (tester) async {
      await pumpCard(tester, data());

      expect(find.text('Al Amerat FC'), findsOneWidget);
      // The mark opens and closes the card.
      expect(find.text('GO PLAY'), findsNWidgets(2));
    });
  });

  // --- the period -------------------------------------------------------------

  group('the card names the period it was given', () {
    testWidgets('All Time', (tester) async {
      await pumpCard(tester, data(period: StatisticsPeriod.allTime));
      expect(find.text('All time'), findsOneWidget);
      expect(find.text('Weekly'), findsNothing);
      expect(find.text('Monthly'), findsNothing);
    });

    testWidgets('Weekly, with the week\'s figures', (tester) async {
      await pumpCard(
        tester,
        data(period: StatisticsPeriod.weekly, matches: 1, players: 2, goals: 2),
      );

      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2));
      // The season's figures are nowhere on a weekly card.
      expect(find.text('6'), findsNothing);
      expect(find.text('7'), findsNothing);
    });

    testWidgets('Monthly, with the month\'s figures', (tester) async {
      await pumpCard(
        tester,
        data(period: StatisticsPeriod.monthly, matches: 4, players: 5, goals: 9),
      );

      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('All time'), findsNothing);
    });
  });

  // --- leaders ----------------------------------------------------------------

  group('the players who led', () {
    testWidgets('each leader is named, with the figure in its own words',
        (tester) async {
      await pumpCard(
        tester,
        data(
          topScorer: leader('u1', 'Ali', 5),
          mostActive: leader('u2', 'Sara', 4),
          mostMvp: leader('u3', 'Omar', 2),
        ),
      );

      expect(find.text('TOP SCORER'), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('5 goals'), findsOneWidget);

      expect(find.text('MOST ACTIVE PLAYER'), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('4 matches'), findsOneWidget);

      expect(find.text('MOST VALUABLE PLAYER'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);
    });

    testWidgets('the faces come from the existing avatar', (tester) async {
      await pumpCard(
        tester,
        data(
          topScorer:
              leader('u1', 'Ali', 5, avatar: 'https://example.test/u1.jpg'),
          mostActive: leader('u2', 'Sara', 4),
          mostMvp: leader('u2', 'Sara', 2),
        ),
      );

      final avatars =
          tester.widgetList<PlayerAvatar>(find.byType(PlayerAvatar)).toList();
      expect(avatars, hasLength(3));
      // Ali has a picture; Sara has not, so both the photo and the fallback are
      // on the same card — and both through the app's own avatar rather than a
      // second implementation built for cards.
      expect(avatars.first.avatarUrl, 'https://example.test/u1.jpg');
      expect(avatars.first.fullName, 'Ali');
      expect(avatars[1].avatarUrl, isNull);
      expect(find.text('S'), findsWidgets, reason: 'the existing initials');
      // Circular, and at card scale rather than list scale.
      expect(avatars.first.radius, greaterThan(40));
    });

    testWidgets('a measure nobody leads is left off, not filled in',
        (tester) async {
      // The Dashboard carries null where a measure has not happened; a row
      // saying "Not yet" on a picture sent to other people is an absence
      // nobody can act on.
      // Built directly rather than through the helper: the helper fills in
      // defaults, and what this test needs is the absences themselves.
      await pumpCard(
        tester,
        CommunityStatisticsCardData(
          communityName: 'Al Amerat FC',
          period: StatisticsPeriod.allTime,
          completedMatches: 6,
          totalPlayers: 3,
          totalGoals: 7,
          topScorer: leader('u1', 'Ali', 5),
        ),
      );

      expect(find.text('TOP SCORER'), findsOneWidget);
      expect(find.text('MOST ACTIVE PLAYER'), findsNothing);
      expect(find.text('MOST VALUABLE PLAYER'), findsNothing);
      expect(find.text('Not yet'), findsNothing);
      expect(find.byType(PlayerAvatar), findsOneWidget);
    });

    testWidgets('a community with no leaders drops the whole section',
        (tester) async {
      await pumpCard(tester, data(leaders: false));

      expect(find.text('LEADERS'), findsNothing);
      expect(find.byType(PlayerAvatar), findsNothing);
      // The totals are still the card.
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a record that outlived its profile keeps the app\'s wording',
        (tester) async {
      // A soft-deleted account keeps its figures and loses its name. The goals
      // still happened, so the measure stays and the player is labelled.
      await pumpCard(
        tester,
        CommunityStatisticsCardData(
          communityName: 'Al Amerat FC',
          period: StatisticsPeriod.allTime,
          completedMatches: 6,
          totalPlayers: 3,
          totalGoals: 9,
          topScorer: leader('gone', null, 9),
        ),
      );

      expect(find.text('Former player'), findsOneWidget);
      expect(find.text('9 goals'), findsOneWidget);
    });

    testWidgets('no leaderboard is on the card', (tester) async {
      // A summary, not the Leaderboards tab: three leaders, never five boards
      // and never a ranking.
      await pumpCard(tester, data());

      expect(find.text('HIGHEST RATED'), findsNothing);
      expect(find.text('MOST WINS'), findsNothing);
      expect(find.text('Show more'), findsNothing);
    });
  });

  // --- geometry ---------------------------------------------------------------

  group('the card is the engine\'s card', () {
    testWidgets('it fills the 1080x1920 surface and nothing overflows',
        (tester) async {
      await pumpCard(tester, data());

      expect(tester.getSize(find.byType(ShareCardSurface)),
          ShareCardCanvas.designSize);
      expect(tester.takeException(), isNull,
          reason: 'a card that overflows its own surface is a broken picture');
    });

    testWidgets('captured through the engine it is a 9:16 PNG', (tester) async {
      final key = GlobalKey();
      await pumpCard(tester, data(), boundaryKey: key);

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));

      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
      expect(image.isShareCardShape, isTrue);
      expect(image.bytes, isNotEmpty);
    });

    testWidgets('nothing in it measures the device', (tester) async {
      await pumpCard(tester, data());
      final composed = tester.getSize(find.byType(CommunityStatisticsCard));

      tester.view.physicalSize = const Size(1200, 3000);
      await tester.pump();

      expect(tester.getSize(find.byType(CommunityStatisticsCard)), composed);
      expect(composed, ShareCardCanvas.designSize);
    });
  });

  // --- localization -----------------------------------------------------------

  group('English and Arabic', () {
    testWidgets('English draws the card left to right', (tester) async {
      await pumpCard(tester, data());

      expect(
        Directionality.of(tester.element(find.text('MATCHES'))),
        TextDirection.ltr,
      );
    });

    testWidgets('Arabic draws the same hierarchy right to left',
        (tester) async {
      await pumpCard(
        tester,
        CommunityStatisticsCardData(
          communityName: 'نادي العامرات',
          period: StatisticsPeriod.weekly,
          completedMatches: 6,
          totalPlayers: 3,
          totalGoals: 7,
          topScorer: leader('u1', 'علي', 5),
          mostActivePlayer: leader('u2', 'سارة', 4),
          mostMvp: leader('u2', 'سارة', 2),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('نادي العامرات'), findsOneWidget);
      expect(find.text('أسبوعي'), findsOneWidget);
      expect(find.text('المباريات'), findsOneWidget);
      expect(find.text('اللاعبون'), findsOneWidget);
      expect(find.text('الأهداف'), findsOneWidget);
      expect(find.text('علي'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('المباريات'))),
        TextDirection.rtl,
        reason: 'the direction is inherited, not mirrored element by element',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('each period is named in Arabic', (tester) async {
      for (final (period, arabic) in [
        (StatisticsPeriod.weekly, 'أسبوعي'),
        (StatisticsPeriod.monthly, 'شهري'),
        (StatisticsPeriod.allTime, 'الكل'),
      ]) {
        await pumpCard(tester, data(period: period),
            locale: const Locale('ar'));
        expect(find.text(arabic), findsOneWidget);
      }
    });

    testWidgets('the mark reads Go Play in both languages', (tester) async {
      await pumpCard(tester, data(), locale: const Locale('ar'));

      expect(find.text('GO PLAY'), findsNWidgets(2));
    });
  });

  // --- the template depends on nothing ----------------------------------------

  group('the template is presentation only', () {
    test('it imports no repository, adapter or data provider', () {
      // If this file could fetch, the card would become a second source for
      // figures the Dashboard already has, free to disagree with the screen.
      final imports =
          File('lib/features/statistics/community_statistics_card.dart')
              .readAsLinesSync()
              .where((line) => line.startsWith('import '))
              .toList();

      for (final line in imports) {
        for (final word in const [
          'repository',
          'adapter',
          'supabase',
          'infrastructure',
          'auth_service',
        ]) {
          expect(line.contains(word), isFalse,
              reason: 'the card imports "$word" — it must be handed resolved '
                  'figures, never fetch them');
        }
      }
    });
  });

  // --- the Dashboard's Share action -------------------------------------------

  group('sharing from the Community Dashboard', () {
    final squad = [
      _player('u1', 'Ali', played: 3, goals: 5, mvp: 1),
      _player('u2', 'Sara', played: 4, goals: 2, mvp: 2),
      _player('u3', 'Omar', played: 1),
    ];

    Future<CapturingRenderer> pumpDashboard(
      WidgetTester tester, {
      String? communityName = 'Al Amerat FC',
      Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodPlayers =
          const {},
      Map<StatisticsPeriod, int> periodMatches = const {},
      Completer<void>? gate,
    }) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final renderer = CapturingRenderer();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityDashboardTab(
            communityId: 'c1',
            communityName: communityName,
            repository: StatisticsRepository(_DashboardAdapter(
              players: squad,
              completedMatches: 6,
              periodPlayers: periodPlayers,
              periodMatches: periodMatches,
              gate: gate,
            )),
            renderer: renderer,
            shareService: FakeShareService(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return renderer;
    }

    /// Builds whatever template the Dashboard handed the engine.
    Future<void> pumpTemplate(
      WidgetTester tester,
      CapturingRenderer renderer,
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

    CommunityStatisticsCard shownCard(WidgetTester tester) =>
        tester.widget<CommunityStatisticsCard>(
            find.byType(CommunityStatisticsCard));

    testWidgets('the Dashboard offers a Share action beside the period',
        (tester) async {
      await pumpDashboard(tester);

      expect(find.byTooltip('Share community statistics'), findsOneWidget);
      // And the period selector is not duplicated by it.
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
    });

    testWidgets('Share hands the engine a Community Statistics card',
        (tester) async {
      final renderer = await pumpDashboard(tester);

      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();

      // The existing engine composed it and the existing preview opened.
      expect(renderer.renders, 1);
      expect(find.byType(ShareCardPreviewScreen), findsOneWidget);
    });

    testWidgets('the card carries the figures and leaders on screen',
        (tester) async {
      final renderer = await pumpDashboard(tester);
      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.period, StatisticsPeriod.allTime);
      expect(card.communityName, 'Al Amerat FC');
      expect(card.completedMatches, 6);
      expect(card.totalPlayers, 3);
      expect(card.totalGoals, 7);
      // The leaders the repository picked, with their own values.
      expect(card.topScorer?.fullName, 'Ali');
      expect(card.topScorer?.value, 5);
      expect(card.mostActivePlayer?.fullName, 'Sara');
      expect(card.mostActivePlayer?.value, 4);
      expect(card.mostMvp?.fullName, 'Sara');
      expect(card.mostMvp?.value, 2);
    });

    testWidgets('the card is the period the reader selected', (tester) async {
      // The whole point of the entry point: no second period selector.
      final renderer = await pumpDashboard(
        tester,
        periodPlayers: {
          StatisticsPeriod.weekly: [_player('u1', 'Ali', played: 1, goals: 2)],
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
      expect(card.topScorer?.value, 2);
    });

    testWidgets('a month shares the month', (tester) async {
      final renderer = await pumpDashboard(
        tester,
        periodPlayers: {
          StatisticsPeriod.monthly: [
            _player('u2', 'Sara', played: 3, goals: 4, mvp: 1),
          ],
        },
        periodMatches: {StatisticsPeriod.monthly: 3},
      );

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.period, StatisticsPeriod.monthly);
      expect(card.completedMatches, 3);
      expect(card.totalGoals, 4);
      expect(card.mostMvp?.fullName, 'Sara');
    });

    testWidgets('an empty period shares a card with no invented leaders',
        (tester) async {
      final renderer = await pumpDashboard(tester);

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share community statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = shownCard(tester).data;
      expect(card.completedMatches, 0);
      expect(card.totalPlayers, 0);
      expect(card.hasLeaders, isFalse);
      expect(find.byType(PlayerAvatar), findsNothing);
    });

    testWidgets('Share waits until there are figures to share', (tester) async {
      final gate = Completer<void>();
      final renderer = await pumpDashboard(
        tester,
        periodPlayers: {
          StatisticsPeriod.weekly: [_player('u1', 'Ali', played: 1, goals: 2)],
        },
        periodMatches: {StatisticsPeriod.weekly: 1},
        gate: gate,
      );
      IconButton shareButton() => tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.ios_share));

      expect(shareButton().onPressed, isNotNull);

      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect(shareButton().onPressed, isNull,
          reason: 'the week has not arrived yet');

      gate.complete();
      await tester.pumpAndSettle();
      expect(shareButton().onPressed, isNotNull);
      expect(renderer.renders, 0);
    });

    testWidgets('without a community name there is nothing to picture',
        (tester) async {
      // A community's figures with no community on them belong to nobody.
      await pumpDashboard(tester, communityName: null);

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.ios_share))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the Share action does not crowd a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityDashboardTab(
            communityId: 'c1',
            communityName: 'Al Amerat FC',
            repository: StatisticsRepository(
              _DashboardAdapter(players: squad, completedMatches: 6),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Share community statistics'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the period labels shrink; nothing overflows');
    });
  });
}

CommunityPlayerStatistics _player(
  String id,
  String? name, {
  int played = 0,
  int goals = 0,
  int mvp = 0,
}) =>
    CommunityPlayerStatistics(
      userId: id,
      fullName: name,
      matchesPlayed: played,
      wins: 0,
      losses: 0,
      draws: 0,
      goals: goals,
      mvpCount: mvp,
    );

/// The statistics port, answering the Dashboard's two reads from memory.
///
/// Behind a real [StatisticsRepository], so the card is built from the figures
/// the product's own reasoning produced — including which player leads a
/// measure and when nobody does.
class _DashboardAdapter implements StatisticsAdapter {
  _DashboardAdapter({
    required this.players,
    required this.completedMatches,
    this.periodPlayers = const {},
    this.periodMatches = const {},
    this.gate,
  });

  final List<CommunityPlayerStatistics> players;
  final int completedMatches;
  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodPlayers;
  final Map<StatisticsPeriod, int> periodMatches;

  /// Held open to keep a period read pending while a test looks at the screen
  /// mid-load. Without it a fake answers on the next microtask and the loading
  /// window never exists to be observed.
  final Completer<void>? gate;

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async {
    if (period.isBounded && gate != null) await gate!.future;
    return period == StatisticsPeriod.allTime
        ? players
        : periodPlayers[period] ?? const [];
  }

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) async {
    if (period.isBounded && gate != null) await gate!.future;
    return period == StatisticsPeriod.allTime
        ? completedMatches
        : periodMatches[period] ?? 0;
  }

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      throw UnimplementedError('the Community Dashboard reads no roster');

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the Community Dashboard reads no player totals');
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
class FakeShareService implements ShareService {
  final List<ShareCardImage> shared = [];

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    shared.add(image);
    return ShareOutcome.shared;
  }
}
