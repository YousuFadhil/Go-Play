import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/statistics/player_statistics_card.dart';
import 'package:go_play/features/statistics/player_statistics_screen.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Player Statistics share card: the first real template on the engine.
///
/// Two things are asserted and they are deliberately separate — what the card
/// draws when it is handed a period's figures, and that the screen hands it the
/// period the reader is actually looking at. The engine itself is not retested
/// here; it has its own suite.
void main() {
  const career = PlayerStatisticsCardData(
    fullName: 'Salim Al Harthy',
    rating: 7.42,
    period: StatisticsPeriod.allTime,
    matchesPlayed: 9,
    wins: 5,
    draws: 3,
    losses: 4,
    goals: 12,
    mvpCount: 2,
  );

  /// Pumps a card at the engine's own size, so what is measured is the card as
  /// it will actually be composed rather than a card squeezed into a phone.
  Future<void> pumpCard(
    WidgetTester tester,
    PlayerStatisticsCardData data, {
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
          child: ShareCardSurface(
            child: PlayerStatisticsCard(data: data),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  // --- what the card draws ----------------------------------------------------

  group('the period the share card names', () {
    // The selector on screen and the card that leaves the phone do not want the
    // same words for All Time. «الكل» is right between three chips and wrong on
    // its own: «الفترة · الكل» reads as "the period · everything".
    PlayerStatisticsCardData at(StatisticsPeriod period) =>
        PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          rating: 7.42,
          period: period,
          matchesPlayed: 17,
          wins: 9,
          draws: 5,
          losses: 3,
          goals: 21,
          mvpCount: 4,
        );

    testWidgets('English names all three exactly', (tester) async {
      for (final (period, expected) in [
        (StatisticsPeriod.allTime, 'Period · All time'),
        (StatisticsPeriod.weekly, 'Period · Weekly'),
        (StatisticsPeriod.monthly, 'Period · Monthly'),
      ]) {
        await pumpCard(tester, at(period));
        expect(find.text(expected), findsOneWidget, reason: '$period');
      }
    });

    testWidgets('Arabic names all three exactly', (tester) async {
      for (final (period, expected) in [
        (StatisticsPeriod.allTime, 'الفترة · كل الفترات'),
        (StatisticsPeriod.weekly, 'الفترة · أسبوعي'),
        (StatisticsPeriod.monthly, 'الفترة · شهري'),
      ]) {
        await pumpCard(tester, at(period), locale: const Locale('ar'));
        expect(find.text(expected), findsOneWidget, reason: '$period');
      }
    });

    testWidgets('the card never uses the selector short All Time word',
        (tester) async {
      await pumpCard(tester, at(StatisticsPeriod.allTime),
          locale: const Locale('ar'));

      expect(find.text('الفترة · الكل'), findsNothing);
      expect(find.text('الكل'), findsNothing);
    });
  });

  group('the six counters the screen shows', () {
    /// Distinct values, so a figure found on the card can only have come from
    /// the counter it belongs to.
    const six = PlayerStatisticsCardData(
      fullName: 'Salim Al Harthy',
      rating: 7.42,
      period: StatisticsPeriod.allTime,
      matchesPlayed: 17,
      wins: 9,
      draws: 5,
      losses: 3,
      goals: 21,
      mvpCount: 4,
    );

    testWidgets('all six are on the card, with the rating above them',
        (tester) async {
      // The card carried four and left draws and losses out, which made a
      // record of played football that could not be reconciled: wins and
      // matches with the two results in between missing.
      await pumpCard(tester, six);

      // The card prints the rating to one decimal.
      expect(find.text('7.4'), findsOneWidget);
      for (final (label, value) in [
        ('MATCHES', '17'),
        ('WINS', '9'),
        ('DRAWS', '5'),
        ('LOSSES', '3'),
        ('GOALS', '21'),
        ('MVP', '4'),
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
        expect(find.text(value), findsOneWidget,
            reason: 'the value for $label is missing');
      }
    });

    testWidgets('they are laid out two across and three down', (tester) async {
      await pumpCard(tester, six);

      Offset at(String label) => tester.getCenter(find.text(label));

      // Two columns: the left of each pair sits left of the right one, and the
      // three pairs share their two x positions.
      expect(at('MATCHES').dx, lessThan(at('WINS').dx));
      expect(at('DRAWS').dx, closeTo(at('MATCHES').dx, 1));
      expect(at('LOSSES').dx, closeTo(at('WINS').dx, 1));
      expect(at('GOALS').dx, closeTo(at('MATCHES').dx, 1));
      expect(at('MVP').dx, closeTo(at('WINS').dx, 1));

      // Three rows, in the order the screen reads them.
      expect(at('MATCHES').dy, lessThan(at('DRAWS').dy));
      expect(at('DRAWS').dy, lessThan(at('GOALS').dy));
      expect(at('WINS').dy, closeTo(at('MATCHES').dy, 1));
      expect(at('LOSSES').dy, closeTo(at('DRAWS').dy, 1));
      expect(at('MVP').dy, closeTo(at('GOALS').dy, 1));
    });

    testWidgets('exactly one Go Play mark, and it is at the foot',
        (tester) async {
      await pumpCard(tester, six);

      final marks = find.text('GO PLAY');
      expect(marks, findsOneWidget);
      // Below the figures: the card is signed, not headed.
      expect(tester.getCenter(marks).dy,
          greaterThan(tester.getCenter(find.text('GOALS')).dy));
    });

    testWidgets('and no decorative rule where the mark used to be',
        (tester) async {
      // The wordmark went first and the accent bar under it stayed behind, which
      // left a green line opening a card with nothing to open. The player is
      // what the card opens on now.
      await pumpCard(tester, six);

      final accentBars = find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.color == const Color(0xFF3DDC84),
      );
      expect(accentBars, findsNothing);

      // The accent itself is untouched where it means something: it is still
      // what the rating is drawn in.
      expect(find.text('7.4'), findsOneWidget);
    });

    testWidgets('a long name does not push the six off the card',
        (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'عبدالرحمن بن سليمان بن خميس الحارثي المعمري',
          rating: 7.42,
          period: StatisticsPeriod.weekly,
          matchesPlayed: 17,
          wins: 9,
          draws: 5,
          losses: 3,
          goals: 21,
          mvpCount: 4,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('LOSSES'), findsOneWidget);
      expect(find.text('GO PLAY'), findsOneWidget);
    });
  });

  group('the card shows the period it was given', () {
    testWidgets('All Time shows the career figures and names the period',
        (tester) async {
      await pumpCard(tester, career);

      expect(find.text('Period · All time'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // The four measures, and only those four.
      expect(find.text('MATCHES'), findsOneWidget);
      expect(find.text('WINS'), findsOneWidget);
      expect(find.text('GOALS'), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
    });

    testWidgets('Weekly shows the week\'s figures, not the career\'s',
        (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          rating: 7.42,
          period: StatisticsPeriod.weekly,
          matchesPlayed: 3,
          wins: 1,
          draws: 5,
          losses: 7,
          goals: 4,
          mvpCount: 2,
        ),
      );

      expect(find.text('Period · Weekly'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // The career's figures are nowhere on a weekly card.
      expect(find.text('9'), findsNothing);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('Monthly shows the month\'s figures', (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          rating: 7.42,
          period: StatisticsPeriod.monthly,
          matchesPlayed: 8,
          wins: 6,
          draws: 5,
          losses: 7,
          goals: 11,
          mvpCount: 3,
        ),
      );

      expect(find.text('Period · Monthly'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Period · Weekly'), findsNothing);
      expect(find.text('Period · All time'), findsNothing);
    });

    testWidgets('a period the player sat out is six zeros, not an empty card',
        (tester) async {
      // Sat out means sat out: a week with three draws and four losses in it is
      // not a week nobody played. My own fixture said so until this was fixed.
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          rating: 7.42,
          period: StatisticsPeriod.weekly,
          matchesPlayed: 0,
          wins: 0,
          draws: 0,
          losses: 0,
          goals: 0,
          mvpCount: 0,
        ),
      );

      expect(find.text('0'), findsNWidgets(6));
      // And the rating is still nine matches old, because it is not a week's.
      expect(find.text('7.4'), findsOneWidget);
    });
  });

  group('the rating is the Global Rating in every period', () {
    testWidgets('the same number, and the same words, on all three cards',
        (tester) async {
      // `OP-1` gives the rating no periodic form and this cycle invents none.
      for (final period in StatisticsPeriod.values) {
        await pumpCard(
          tester,
          PlayerStatisticsCardData(
            fullName: 'Salim Al Harthy',
            rating: 7.42,
            period: period,
            matchesPlayed: 1,
            wins: 1,
            draws: 3,
            losses: 4,
            goals: 1,
            mvpCount: 1,
          ),
        );

        expect(find.text('7.4'), findsOneWidget,
            reason: 'the rating does not change with the period');
        // The screen's own wording for the figure, so the card and the screen
        // say the same thing about what it is.
        expect(find.text('CURRENT RATING'), findsOneWidget);
      }
    });

    testWidgets('it keeps one decimal place (OP-1)', (tester) async {
      await pumpCard(tester, career);

      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('7.42'), findsNothing);
    });

    testWidgets('a whole rating still shows its decimal', (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          rating: 5.0,
          period: StatisticsPeriod.allTime,
          matchesPlayed: 0,
          wins: 0,
          draws: 3,
          losses: 4,
          goals: 0,
          mvpCount: 0,
        ),
      );

      expect(find.text('5.0'), findsOneWidget);
    });
  });

  // --- identity ---------------------------------------------------------------

  group('the player on the card', () {
    testWidgets('the name is drawn, and the Go Play mark once with it',
        (tester) async {
      await pumpCard(tester, career);

      expect(find.text('Salim Al Harthy'), findsOneWidget);
      // CHANGED (B2): once, at the foot. The card used to carry the mark twice
      // — large at the top and muted at the bottom — which read as the product
      // signing its own picture twice.
      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('the photo is passed to the existing avatar', (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Salim Al Harthy',
          avatarUrl: 'https://example.test/salim.jpg',
          rating: 7.42,
          period: StatisticsPeriod.allTime,
          matchesPlayed: 9,
          wins: 5,
          draws: 3,
          losses: 4,
          goals: 12,
          mvpCount: 2,
        ),
      );

      // The app's own avatar, not a second implementation built for cards.
      final avatar = tester.widget<PlayerAvatar>(find.byType(PlayerAvatar));
      expect(avatar.avatarUrl, 'https://example.test/salim.jpg');
      expect(avatar.fullName, 'Salim Al Harthy');
      expect(avatar.isProfessionalGuest, isFalse);
      // Circular, and at card scale rather than list scale.
      expect(avatar.radius, greaterThan(100));
    });

    testWidgets('a player with no photo falls back the way the app does',
        (tester) async {
      await pumpCard(tester, career);

      final avatar = tester.widget<PlayerAvatar>(find.byType(PlayerAvatar));
      expect(avatar.avatarUrl, isNull);
      expect(avatar.fullName, 'Salim Al Harthy');
      // The existing fallback draws the initials — first and last word, which
      // is `initialsOf`'s rule and not one this card restates.
      expect(find.text('SH'), findsOneWidget);
    });

    testWidgets('a long name is scaled rather than cut off', (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'Abdulrahman Mohammed Al Balushi Al Hinai',
          rating: 7.42,
          period: StatisticsPeriod.allTime,
          matchesPlayed: 9,
          wins: 5,
          draws: 3,
          losses: 4,
          goals: 12,
          mvpCount: 2,
        ),
      );

      expect(find.text('Abdulrahman Mohammed Al Balushi Al Hinai'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // --- geometry ---------------------------------------------------------------

  group('the card is the engine\'s card', () {
    testWidgets('it fills the 1080x1920 surface and nothing overflows',
        (tester) async {
      await pumpCard(tester, career);

      expect(tester.getSize(find.byType(ShareCardSurface)),
          ShareCardCanvas.designSize);
      expect(tester.takeException(), isNull,
          reason: 'a card that overflows its own surface is a broken picture');
    });

    testWidgets('captured through the engine it is a 9:16 PNG', (tester) async {
      final key = GlobalKey();
      await pumpCard(tester, career, boundaryKey: key);

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));

      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
      expect(image.isShareCardShape, isTrue);
      expect(image.bytes, isNotEmpty);
    });

    testWidgets('nothing in it measures the device', (tester) async {
      // The card is laid out in design units. A second, very different screen
      // must produce exactly the same geometry.
      await pumpCard(tester, career);
      final wide = tester.getSize(find.byType(PlayerStatisticsCard));

      tester.view.physicalSize = const Size(1200, 3000);
      await tester.pump();

      expect(tester.getSize(find.byType(PlayerStatisticsCard)), wide);
      expect(wide, ShareCardCanvas.designSize);
    });
  });

  // --- localization -----------------------------------------------------------

  group('English and Arabic', () {
    testWidgets('English draws the card left to right', (tester) async {
      await pumpCard(tester, career);

      expect(
        Directionality.of(tester.element(find.text('MATCHES'))),
        TextDirection.ltr,
      );
    });

    testWidgets('Arabic draws the same hierarchy right to left',
        (tester) async {
      await pumpCard(
        tester,
        const PlayerStatisticsCardData(
          fullName: 'سالم الحارثي',
          rating: 7.42,
          period: StatisticsPeriod.weekly,
          matchesPlayed: 3,
          wins: 1,
          draws: 3,
          losses: 4,
          goals: 4,
          mvpCount: 1,
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('سالم الحارثي'), findsOneWidget);
      expect(find.text('الفترة · أسبوعي'), findsOneWidget);
      expect(find.text('المباريات'), findsOneWidget);
      expect(find.text('الانتصارات'), findsOneWidget);
      expect(find.text('الأهداف'), findsOneWidget);
      expect(find.text('أفضل لاعب'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('المباريات'))),
        TextDirection.rtl,
        reason: 'the direction is inherited, not mirrored element by element',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('each period is named in Arabic', (tester) async {
      for (final (period, arabic) in [
        (StatisticsPeriod.weekly, 'الفترة · أسبوعي'),
        (StatisticsPeriod.monthly, 'الفترة · شهري'),
        // CHANGED: the share card says «كل الفترات»; «الكل» stays the
        // selector's word on screen.
        (StatisticsPeriod.allTime, 'الفترة · كل الفترات'),
      ]) {
        await pumpCard(
          tester,
          PlayerStatisticsCardData(
            fullName: 'سالم الحارثي',
            rating: 7.42,
            period: period,
            matchesPlayed: 1,
            wins: 1,
            draws: 3,
            losses: 4,
            goals: 1,
            mvpCount: 1,
          ),
          locale: const Locale('ar'),
        );
        expect(find.text(arabic), findsOneWidget);
      }
    });

    testWidgets('the mark reads Go Play in both languages', (tester) async {
      // It is a name, not a sentence, and the product is called Go Play in
      // Arabic too.
      await pumpCard(tester, career, locale: const Locale('ar'));

      // One mark, at the foot (B2).
      expect(find.text('GO PLAY'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('GO PLAY').first)),
        TextDirection.rtl,
        reason: 'the card is RTL; only the mark itself is set LTR',
      );
    });
  });

  // --- the template depends on nothing ----------------------------------------

  group('the template is presentation only', () {
    test('it imports no repository, adapter or data provider', () {
      // The engine is domain-neutral; a template is domain-*specific* and must
      // still be inert. If this file ever reached for a repository, the card
      // would become a second source for figures the screen already has, free
      // to disagree with what the reader is looking at.
      final imports =
          File('lib/features/statistics/player_statistics_card.dart')
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
          'current_user',
        ]) {
          expect(line.contains(word), isFalse,
              reason: 'the card imports "$word" — it must be handed resolved '
                  'figures, never fetch them');
        }
      }
    });

    test('its data carries figures and an identity, and no way to load any',
        () {
      // Six figures the screen already shows, plus who they belong to.
      expect(career.matchesPlayed, 9);
      expect(career.wins, 5);
      expect(career.goals, 12);
      expect(career.mvpCount, 2);
      expect(career.rating, 7.42);
      expect(career.period, StatisticsPeriod.allTime);
      expect(career.fullName, 'Salim Al Harthy');
    });
  });

  // --- the screen's Share action ----------------------------------------------

  group('sharing from the Player Statistics screen', () {
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

    const profile = PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
      avatarUrl: 'https://example.test/salim.jpg',
    );

    Future<CapturingRenderer> pumpScreen(
      WidgetTester tester, {
      PlayerProfile? loaded = profile,
      Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periods = const {},
      Completer<void>? gate,
    }) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      CurrentUser.instance.useRepository(
        ProfileRepository(_StaticProfileAdapter(loaded)),
      );
      addTearDown(() => CurrentUser.instance.useRepository(null));
      if (loaded != null) await CurrentUser.instance.ensureLoaded();

      final renderer = CapturingRenderer();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PlayerStatisticsScreen(
          userId: 'u1',
          repository: ResultRepository(_StaticResultAdapter(played)),
          statistics: StatisticsRepository(_PeriodAdapter(periods, gate: gate)),
          renderer: renderer,
          shareService: FakeShareService(),
        ),
      ));
      await tester.pumpAndSettle();
      return renderer;
    }

    /// Builds whatever template the screen handed the engine, so a test can
    /// read the card the reader would have seen.
    Future<void> pumpTemplate(
      WidgetTester tester,
      CapturingRenderer renderer,
    ) async {
      // Torn down first. Pumping another `MaterialApp` would *update* the one
      // already mounted, which keeps its Navigator and therefore the preview
      // route sitting on top -- and everything under an opaque route is
      // offstage, where `find.byType` does not look.
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

    testWidgets('the screen offers a Share action', (tester) async {
      await pumpScreen(tester);

      expect(find.byTooltip('Share my statistics'), findsOneWidget);
      // And the period selector is not duplicated by it.
      expect(find.text('Weekly'), findsOneWidget);
    });

    testWidgets('Share hands the engine a Player Statistics card',
        (tester) async {
      final renderer = await pumpScreen(tester);

      await tester.tap(find.byTooltip('Share my statistics'));
      await tester.pumpAndSettle();

      // The existing engine did the composing and the existing preview opened.
      expect(renderer.renders, 1);
      expect(renderer.captured, isNotNull);
      expect(find.byType(ShareCardPreviewScreen), findsOneWidget);
    });

    testWidgets('the card carries the figures and the player on screen',
        (tester) async {
      final renderer = await pumpScreen(tester);
      await tester.tap(find.byTooltip('Share my statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = tester
          .widget<PlayerStatisticsCard>(find.byType(PlayerStatisticsCard));
      expect(card.data.period, StatisticsPeriod.allTime);
      expect(card.data.matchesPlayed, 9);
      expect(card.data.wins, 5);
      expect(card.data.goals, 12);
      expect(card.data.mvpCount, 2);
      expect(card.data.rating, 7.42);
      // The identity comes from the session's held profile, not from a second
      // read of its own.
      expect(card.data.fullName, 'Salim Al Harthy');
      expect(card.data.avatarUrl, 'https://example.test/salim.jpg');
    });

    testWidgets('the card is the period the reader selected', (tester) async {
      // The whole point of the entry point: no second period selector.
      final renderer = await pumpScreen(tester, periods: {
        StatisticsPeriod.weekly: [
          _record(played: 3, wins: 1, goals: 4, mvp: 1),
        ],
      });

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share my statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = tester
          .widget<PlayerStatisticsCard>(find.byType(PlayerStatisticsCard));
      expect(card.data.period, StatisticsPeriod.weekly);
      expect(card.data.matchesPlayed, 3);
      expect(card.data.wins, 1);
      expect(card.data.goals, 4);
      expect(card.data.mvpCount, 1);
      // The rating is still the career's, because it has no weekly form.
      expect(card.data.rating, 7.42);
    });

    testWidgets('a month shares the month', (tester) async {
      final renderer = await pumpScreen(tester, periods: {
        StatisticsPeriod.monthly: [
          _record(played: 8, wins: 6, goals: 11, mvp: 3),
        ],
      });

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share my statistics'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final card = tester
          .widget<PlayerStatisticsCard>(find.byType(PlayerStatisticsCard));
      expect(card.data.period, StatisticsPeriod.monthly);
      expect(card.data.matchesPlayed, 8);
      expect(card.data.goals, 11);
    });

    testWidgets('Share is offered only once there are figures to share',
        (tester) async {
      // Nothing is on screen while a period loads, so there is no card to make.
      final gate = Completer<void>();
      final renderer = await pumpScreen(tester, gate: gate, periods: {
        StatisticsPeriod.weekly: [_record(played: 3)],
      });
      // By icon, not by tooltip: `find.byTooltip` matches the tooltip widget
      // itself, which is not the button whose enabled state is the question.
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

    testWidgets('a player whose profile is not loaded cannot be pictured',
        (tester) async {
      // The card needs a name and a face. Without them it would be a card of
      // figures belonging to nobody.
      await pumpScreen(tester, loaded: null);

      expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.ios_share))
            .onPressed,
        isNull,
      );
    });
  });
}

CommunityPlayerStatistics _record({
  int played = 0,
  int wins = 0,
  int goals = 0,
  int mvp = 0,
}) =>
    CommunityPlayerStatistics(
      userId: 'u1',
      fullName: null,
      matchesPlayed: played,
      wins: wins,
      losses: 0,
      draws: 0,
      goals: goals,
      mvpCount: mvp,
    );

/// The Share Card Engine's renderer port, keeping the template it was given.
///
/// Standing in for the real renderer means these tests assert what the screen
/// *hands the engine* rather than re-testing the engine, which has its own
/// suite — and it keeps a 1080x1920 capture out of a screen test.
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

/// The career source, answering one player from memory.
class _StaticResultAdapter implements ResultAdapter {
  _StaticResultAdapter(this.statistics);

  final PlayerStatistics statistics;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async => statistics;

  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) =>
      throw UnimplementedError('the statistics screen records nothing');

  @override
  Future<MatchResult?> fetchResult(String matchId) =>
      throw UnimplementedError('the statistics screen reads no match');

  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) =>
      throw UnimplementedError('the statistics screen reads no audit');
}

/// One player's period records, answered from memory.
///
/// Behind a real [StatisticsRepository], so the screen exercises the
/// repository's own summing across communities rather than a stub of it — the
/// figures on the card are the ones the product's reasoning produced.
class _PeriodAdapter implements StatisticsAdapter {
  _PeriodAdapter(this.periods, {this.gate});

  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periods;

  /// Held open to keep a period read pending while a test looks at the screen
  /// mid-load. Without it a fake answers on the next microtask and the loading
  /// window never exists to be observed.
  final Completer<void>? gate;

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) async {
    if (gate != null) await gate!.future;
    return periods[period] ?? const [];
  }

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

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async =>
      const {};
}

/// The session profile source.
class _StaticProfileAdapter implements ProfileAdapter {
  _StaticProfileAdapter(this.profile);

  final PlayerProfile? profile;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    final loaded = profile;
    if (loaded == null) throw const NetworkFailure();
    return loaded;
  }

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeMyAvatar() => throw UnimplementedError();
}
