import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_tabs.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/discover/public_community_tabs.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_community_screen.dart';
import 'package:go_play/features/football/football_repository.dart';

/// One community page for a reader who is not in the community.
///
/// **The approved decision this pins.** A signed-out guest and a signed-in
/// non-member see the same public football content in the same order: the
/// community hero, the football record, then Latest Results, Upcoming Matches
/// and Top Players, opening on Latest Results. What a session changes is what a
/// tap does, never what the page shows.
///
/// Every test here is run against **both** screens, from one fake, so a
/// difference between them is a failure of the test rather than something a
/// reader has to notice.
void main() {
  // --------------------------------------------------------------------------
  // Fixtures
  // --------------------------------------------------------------------------
  PublicResult result(String id, {String title = 'Friday football'}) =>
      PublicResult(
        matchId: id,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: title,
        startAt: DateTime(2026, 9, 11, 17),
        teamAScore: 3,
        teamBScore: 2,
      );

  PublicCommunityTopPlayer topPlayer(
    int n, {
    String? name,
    double rating = 6.0,
    int goals = 0,
    int mvp = 0,
  }) =>
      PublicCommunityTopPlayer(
        communityId: 'c1',
        userId: 'u$n',
        displayName: name ?? 'Player $n',
        overallRating: rating,
        matchesPlayed: 10,
        goals: goals,
        mvpCount: mvp,
      );

  /// Fifteen, best first as the database would send them. The contract's cap is
  /// eleven, so four of these must never be drawn.
  List<PublicCommunityTopPlayer> fifteen() => [
        for (var i = 1; i <= 15; i++)
          topPlayer(i, rating: 9.0 - i * 0.1, goals: 20 - i, mvp: 3),
      ];

  const record = PublicCommunityFootballRecord(
    communityId: 'c1',
    completedMatches: 14,
    players: 33,
    goals: 91,
    mvpCount: 4,
  );

  const en = Locale('en');
  const ar = Locale('ar');

  final labelsEn = ['Latest results', 'Upcoming matches', 'Top players'];
  final labelsAr = ['آخر النتائج', 'المباريات القادمة', 'أبرز اللاعبين'];

  Future<void> pumpPage(
    WidgetTester tester,
    _Audience audience,
    _Adapter adapter, {
    Locale locale = en,
    Size size = const Size(412, 2000),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final Widget home = switch (audience) {
      _Audience.guest => PublicCommunityScreen(
          communityId: 'c1',
          repository: DiscoverRepository(adapter),
          authService: AuthService(_GuestAuth()),
        ),
      _Audience.nonMember => FootballCommunityScreen(
          communityId: 'c1',
          discoverRepository: DiscoverRepository(adapter),
          footballRepository: FootballRepository(adapter.authenticatedFootball),
          communityRepository: CommunityRepository(_NoCommunities()),
        ),
    };

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  Finder tabs() => find.descendant(
      of: find.byType(DiscoverTabs), matching: find.byType(Tab));

  Future<void> openTab(WidgetTester tester, int index) async {
    final tab = tabs().at(index);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  TabController controllerOf(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!;

  List<String?> tabLabels(WidgetTester tester) => [
        for (final tab in tester.widgetList<Tab>(tabs()))
          (tab.child as Text).data,
      ];

  /// Every text a Top Players row draws, in reading order, row after row.
  List<String?> playerTexts(WidgetTester tester) => [
        for (final text in tester.widgetList<Text>(find.descendant(
          of: find.byType(TopPlayerRow),
          matching: find.byType(Text),
        )))
          text.data,
      ];

  List<String?> recordTexts(WidgetTester tester) => [
        for (final text in tester.widgetList<Text>(find.descendant(
          of: find.byKey(const Key('communityFootballRecord')),
          matching: find.byType(Text),
        )))
          text.data,
      ];

  // --------------------------------------------------------------------------
  // The hierarchy
  // --------------------------------------------------------------------------
  for (final audience in _Audience.values) {
    group('${audience.label}: one hierarchy', () {
      testWidgets('the hero, then the record, then the tabs, in that order',
          (tester) async {
        await pumpPage(tester, audience, _Adapter(record: record));

        final hero = tester.getRect(find.byType(ClubHero));
        final band = tester.getRect(
          find.byKey(const Key('communityFootballRecord')),
        );
        final bar = tester.getRect(find.byType(DiscoverTabs));
        final content = tester.getRect(find.byType(TabBarView));

        expect(hero.top, lessThan(band.top));
        expect(band.top, greaterThanOrEqualTo(hero.bottom - 1),
            reason: 'the record sits under the hero, on the sheet');
        expect(band.bottom, lessThanOrEqualTo(bar.top),
            reason: 'Football Record stays ABOVE the tabs');
        expect(bar.bottom, lessThanOrEqualTo(content.top));

        // All four figures, and only those four.
        expect(recordTexts(tester), [
          '14',
          'Completed matches',
          '33',
          'Players',
          '91',
          'Goals',
          '4',
          'MVPs',
        ]);
      });

      testWidgets('the record is on screen whichever tab is open',
          (tester) async {
        await pumpPage(tester, audience, _Adapter(record: record));

        for (final index in [1, 2, 0]) {
          await openTab(tester, index);
          expect(
              find.byKey(const Key('communityFootballRecord')), findsOneWidget,
              reason: 'tab $index');
          expect(find.text('91'), findsOneWidget);
        }
      });

      testWidgets('exactly three tabs, in the approved order', (tester) async {
        await pumpPage(tester, audience, _Adapter());

        expect(tabs(), findsNWidgets(3));
        expect(tabLabels(tester), labelsEn);
        expect(find.byType(TabBarView), findsOneWidget);
      });

      testWidgets('and in Arabic, whole', (tester) async {
        await pumpPage(tester, audience, _Adapter(), locale: ar);

        expect(tabLabels(tester), labelsAr);
      });

      testWidgets('it opens on Latest Results', (tester) async {
        await pumpPage(
          tester,
          audience,
          _Adapter(results: [result('m1')], players: fifteen()),
        );

        expect(controllerOf(tester).index, 0);
        expect(find.byType(PublicResultCard), findsOneWidget);
        expect(find.byType(PublicMatchCard), findsNothing);
        expect(find.byType(TopPlayerRow), findsNothing);
      });

      testWidgets('Upcoming Matches is the second tab', (tester) async {
        await pumpPage(tester, audience, _Adapter(results: [result('m1')]));
        await openTab(tester, 1);

        expect(controllerOf(tester).index, 1);
        expect(find.byType(PublicMatchCard), findsOneWidget);
        expect(find.byType(PublicResultCard), findsNothing);
      });

      testWidgets('no section headings are left over from the stacked page',
          (tester) async {
        await pumpPage(tester, audience, _Adapter(results: [result('m1')]));

        expect(find.byType(DiscoverSectionHeader), findsNothing);
      });

      testWidgets('nothing about the members or the join code is on it',
          (tester) async {
        await pumpPage(
          tester,
          audience,
          _Adapter(results: [result('m1')], players: fifteen()),
        );
        for (final index in [0, 1, 2]) {
          await openTab(tester, index);
          for (final forbidden in ['Roster', 'Join code', 'Manage']) {
            expect(find.textContaining(forbidden), findsNothing,
                reason: '$forbidden on tab $index');
          }
        }
      });
    });
  }

  // --------------------------------------------------------------------------
  // Narrow phones
  // --------------------------------------------------------------------------
  group('the tabs stay usable at 320px', () {
    for (final audience in _Audience.values) {
      for (final locale in [en, ar]) {
        testWidgets(
            '${audience.label}, ${locale.languageCode}: every label whole, '
            'nothing overflows', (tester) async {
          await pumpPage(
            tester,
            audience,
            _Adapter(results: [result('m1')], players: fifteen()),
            locale: locale,
            size: const Size(320, 2000),
          );

          final expected = locale == ar ? labelsAr : labelsEn;
          expect(tabLabels(tester), expected);
          for (final label in expected) {
            final text = find.descendant(
              of: find.byType(DiscoverTabs),
              matching: find.text(label),
            );
            expect(text, findsOneWidget, reason: label);
            // Never shortened and never ellipsized.
            final widget = tester.widget<Text>(text);
            expect(widget.overflow, isNot(TextOverflow.ellipsis));
            expect(widget.softWrap, isFalse);
          }
          expect(tester.takeException(), isNull);

          // And each tab can be opened and read at that width.
          for (final index in [1, 2, 0]) {
            await openTab(tester, index);
            expect(controllerOf(tester).index, index);
            expect(tester.takeException(), isNull, reason: 'tab $index');
          }
        });
      }
    }

    testWidgets('the bar is the Material one, reused', (tester) async {
      await pumpPage(tester, _Audience.guest, _Adapter());

      // Reused, not reimplemented: the selected state and the keyboard
      // traversal come from `TabBar`, exactly as they do on Discover.
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byKey(const Key('discoverTabs')), findsOneWidget);
    });
  });

  // --------------------------------------------------------------------------
  // The record band
  // --------------------------------------------------------------------------
  group('the football record band', () {
    Future<void> pumpBand(
      WidgetTester tester, {
      required double width,
      Locale locale = en,
      double textScale = 1.0,
      PublicCommunityFootballRecord value = record,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: GoColors.surfaceSheet,
          body: FootballRecordBand(record: value),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final labels = {
      en: ['Completed matches', 'Players', 'Goals', 'MVPs'],
      ar: ['المباريات المنتهية', 'اللاعبون', 'الأهداف', 'أفضل لاعب'],
    };

    // The test font is Ahem, whose glyphs are each a full em wide -- several
    // times wider than a real face -- so the widths below are the widths at
    // which *Ahem* fits, not a phone's. The rule is what is being pinned: a
    // measurement, not a breakpoint.

    testWidgets('four across when they read comfortably', (tester) async {
      await pumpBand(tester, width: 700);

      expect(find.byKey(const Key('recordOneRow')), findsOneWidget);
      expect(find.byKey(const Key('recordTwoByTwo')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two by two, not shrunk, when the labels no longer fit',
        (tester) async {
      // The same width, at a large text size: four columns would either break
      // a word or squeeze the labels, so the band reflows instead.
      await pumpBand(tester, width: 700, textScale: 2.0);

      expect(find.byKey(const Key('recordTwoByTwo')), findsOneWidget);
      expect(find.byKey(const Key('recordOneRow')), findsNothing);
      expect(tester.takeException(), isNull);

      // Nothing was shrunk to get there: the label is drawn at its own size.
      final label = tester.widget<Text>(find.text('Goals'));
      expect(label.style!.fontSize, 11);
      expect(label.maxLines, 2);
    });

    testWidgets('two by two on a narrow phone', (tester) async {
      await pumpBand(tester, width: 320);

      expect(find.byKey(const Key('recordTwoByTwo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and on a very narrow screen whatever the labels are',
        (tester) async {
      await pumpBand(tester, width: 250);

      expect(find.byKey(const Key('recordTwoByTwo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the arrangement is the same rule in Arabic', (tester) async {
      await pumpBand(tester, width: 700, locale: ar);
      expect(find.byKey(const Key('recordOneRow')), findsOneWidget);

      await pumpBand(tester, width: 700, textScale: 2.0, locale: ar);
      expect(find.byKey(const Key('recordTwoByTwo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [250.0, 280.0, 320.0, 360.0, 412.0, 600.0]) {
      for (final locale in [en, ar]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          testWidgets(
              'no overflow at ${width.toInt()}px, ${locale.languageCode}, '
              'text x$scale, and every label whole', (tester) async {
            await pumpBand(
              tester,
              width: width,
              locale: locale,
              textScale: scale,
              value: const PublicCommunityFootballRecord(
                communityId: 'c1',
                completedMatches: 12345,
                players: 678,
                goals: 91011,
                mvpCount: 1213,
              ),
            );

            expect(tester.takeException(), isNull);
            for (final label in labels[locale]!) {
              expect(find.text(label), findsOneWidget, reason: label);
              final text = tester.widget<Text>(find.text(label));
              expect(text.overflow, isNot(TextOverflow.ellipsis));
            }
            // One arrangement or the other, never neither.
            final arrangements = [
              find.byKey(const Key('recordOneRow')),
              find.byKey(const Key('recordTwoByTwo')),
            ].where((f) => f.evaluate().isNotEmpty);
            expect(arrangements.length, 1);
          });
        }
      }
    }

    testWidgets('the figure is the loud part and the label the quiet one',
        (tester) async {
      await pumpBand(tester, width: 412);

      final figure = tester.widget<Text>(find.text('91'));
      final label = tester.widget<Text>(find.text('Goals'));
      expect(figure.style!.fontSize!, greaterThan(label.style!.fontSize!));
      expect(figure.style!.fontWeight, FontWeight.w800);
    });

    testWidgets('one surface, not four cards', (tester) async {
      await pumpBand(tester, width: 412);

      expect(find.byType(Card), findsNothing);
      expect(find.byKey(const Key('communityFootballRecord')), findsOneWidget);
    });
  });

  // --------------------------------------------------------------------------
  // Top Players
  // --------------------------------------------------------------------------
  for (final audience in _Audience.values) {
    group('${audience.label}: Top Players', () {
      testWidgets('shows at most eleven, not five', (tester) async {
        await pumpPage(tester, audience, _Adapter(players: fifteen()));
        await openTab(tester, 2);

        expect(find.byType(TopPlayerRow), findsNWidgets(11));
        expect(find.text('Player 11'), findsOneWidget);
        expect(find.text('Player 12'), findsNothing);
        expect(find.text('Player 15'), findsNothing);
      });

      testWidgets('ranks one to eleven are drawn, explicitly', (tester) async {
        await pumpPage(tester, audience, _Adapter(players: fifteen()));
        await openTab(tester, 2);

        for (var rank = 1; rank <= 11; rank++) {
          final row = find.byKey(Key('topPlayerRow_u$rank'));
          expect(row, findsOneWidget, reason: 'rank $rank');
          expect(
            find.descendant(of: row, matching: find.text('$rank')),
            findsOneWidget,
            reason: 'the badge on rank $rank',
          );
        }
      });

      testWidgets('rows are in the order the database ranked them',
          (tester) async {
        // Handed over deliberately out of the order a client sort would give:
        // the lowest rating first. The page must not re-rank -- the ranking
        // (rating, goals, MVPs, name) is the database's, and a second copy of
        // it is a rule that can drift.
        final asRanked = [
          topPlayer(1, name: 'Low Rating First', rating: 5.0),
          topPlayer(2, name: 'High Rating Second', rating: 9.0, goals: 30),
          topPlayer(3, name: 'Mid Third', rating: 7.0),
        ];
        await pumpPage(tester, audience, _Adapter(players: asRanked));
        await openTab(tester, 2);

        final ys = [
          for (final name in [
            'Low Rating First',
            'High Rating Second',
            'Mid Third',
          ])
            tester.getTopLeft(find.text(name)).dy,
        ];
        expect(ys, [...ys]..sort());
      });

      testWidgets('each row keeps the existing player row content',
          (tester) async {
        await pumpPage(
          tester,
          audience,
          _Adapter(players: [
            topPlayer(1,
                name: 'Salim Al Busaidi', rating: 7.456, goals: 12, mvp: 3),
          ]),
        );
        await openTab(tester, 2);

        expect(find.text('Salim Al Busaidi'), findsOneWidget);
        // Matches played, goals and MVPs, then the rating to two decimals.
        expect(find.textContaining('Matches played 10'), findsOneWidget);
        expect(find.textContaining('Goals 12'), findsOneWidget);
        expect(find.textContaining('MVPs 3'), findsOneWidget);
        expect(find.text('7.46'), findsOneWidget);
      });

      testWidgets('the first three are lifted, the rest are plain',
          (tester) async {
        await pumpPage(tester, audience, _Adapter(players: fifteen()));
        await openTab(tester, 2);

        Color? surfaceOf(int rank) => tester
            .widget<Material>(find
                .descendant(
                  of: find.byKey(Key('topPlayerRow_u$rank')),
                  matching: find.byType(Material),
                )
                .first)
            .color;

        for (final rank in [1, 2, 3]) {
          expect(surfaceOf(rank), GoColors.surfaceCard, reason: 'rank $rank');
        }
        for (final rank in [4, 8, 11]) {
          expect(surfaceOf(rank), Colors.transparent, reason: 'rank $rank');
        }

        Color? badgeOf(int rank) => tester
            .widget<CircleAvatar>(find
                .descendant(
                  of: find.byKey(Key('topPlayerRow_u$rank')),
                  matching: find.byType(CircleAvatar),
                )
                .first)
            .backgroundColor;
        // Stepping down from the primary green, all from the existing tokens.
        expect(badgeOf(1), GoColors.primary);
        expect(badgeOf(2), GoColors.primaryMid);
        expect(badgeOf(3), GoColors.primaryContainer);
        expect(badgeOf(4), GoColors.surfaceContainerHighest);
      });

      testWidgets('there is no pagination and no "show more"', (tester) async {
        await pumpPage(tester, audience, _Adapter(players: fifteen()));
        await openTab(tester, 2);

        expect(find.textContaining('more'), findsNothing);
        expect(find.byKey(const Key('publicCommunityPreviousResultsToggle')),
            findsNothing);
        expect(find.byType(TextButton), findsNothing);
      });

      testWidgets('nobody ranked yet is an empty state, not a fault',
          (tester) async {
        await pumpPage(tester, audience, _Adapter(record: record));
        await openTab(tester, 2);

        expect(find.text('Nobody has a record here yet.'), findsOneWidget);
        expect(find.byType(TopPlayerRow), findsNothing);
        expect(find.textContaining('Could not load'), findsNothing);
      });

      testWidgets('a failed football read is its own state, with a retry',
          (tester) async {
        final adapter = _Adapter(players: fifteen())..failFootball = true;
        await pumpPage(tester, audience, adapter);

        // The community and its results are still standing...
        expect(find.byType(ClubHero), findsOneWidget);
        // ...the record says so where it would have been...
        expect(find.textContaining('Could not load recent football'),
            findsOneWidget);
        expect(find.byKey(const Key('recordRetry')), findsOneWidget);

        // ...and so does the tab.
        await openTab(tester, 2);
        expect(find.byType(TopPlayerRow), findsNothing);
        expect(find.textContaining('Could not load recent football'),
            findsNWidgets(2));

        adapter.failFootball = false;
        await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
        await tester.pumpAndSettle();

        expect(find.byType(TopPlayerRow), findsNWidgets(11));
        expect(controllerOf(tester).index, 2,
            reason: 'a retry does not send the reader back to the results');
      });

      testWidgets('a slow football read shows placeholders in place',
          (tester) async {
        final adapter = _Adapter(players: fifteen())
          ..footballGate = Completer<void>();
        tester.view.physicalSize = const Size(412, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          locale: en,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: switch (audience) {
            _Audience.guest => PublicCommunityScreen(
                communityId: 'c1',
                repository: DiscoverRepository(adapter),
                authService: AuthService(_GuestAuth()),
              ),
            _Audience.nonMember => FootballCommunityScreen(
                communityId: 'c1',
                discoverRepository: DiscoverRepository(adapter),
                footballRepository:
                    FootballRepository(adapter.authenticatedFootball),
                communityRepository: CommunityRepository(_NoCommunities()),
              ),
          },
        ));
        // The community has landed; the football has not.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(ClubHero), findsOneWidget);
        expect(
            find.byKey(const Key('communityFootballRecord')), findsOneWidget);
        expect(find.byType(DiscoverTabs), findsOneWidget);
        expect(find.byType(TopPlayerRow), findsNothing);

        adapter.footballGate!.complete();
        await tester.pumpAndSettle();
        await openTab(tester, 2);
        expect(find.byType(TopPlayerRow), findsNWidgets(11));
      });
    });
  }

  test('the Top Players cap is eleven', () {
    expect(DiscoverRepository.topPlayers, 11);
  });

  // --------------------------------------------------------------------------
  // Guest and signed-in non-member: one dataset
  // --------------------------------------------------------------------------
  group('a guest and a signed-in non-member see the same football', () {
    Future<
        ({
          List<String?> record,
          List<String?> players,
          List<String?> tabs,
          List<String> reads,
          int lineupReads,
        })> read(WidgetTester tester, _Audience audience) async {
      final adapter = _Adapter(
        record: record,
        players: fifteen(),
        results: [result('m1')],
      );
      await pumpPage(tester, audience, adapter);
      final recordShown = recordTexts(tester);
      await openTab(tester, 2);
      final playersShown = playerTexts(tester);
      final tabsShown = tabLabels(tester);
      return (
        record: recordShown,
        players: playersShown,
        tabs: tabsShown,
        reads: adapter.footballReads,
        lineupReads: adapter.lineupReads.length,
      );
    }

    testWidgets('the same record and the same eleven, in the same order',
        (tester) async {
      final guest = await read(tester, _Audience.guest);
      await tester.pumpWidget(const SizedBox());
      final member = await read(tester, _Audience.nonMember);

      expect(member.record, guest.record);
      expect(member.players, guest.players);
      expect(member.tabs, guest.tabs);
      expect(guest.players, isNotEmpty);
    });

    testWidgets('through the same two public contracts, and no other',
        (tester) async {
      final guest = await read(tester, _Audience.guest);
      await tester.pumpWidget(const SizedBox());
      final member = await read(tester, _Audience.nonMember);

      expect(guest.reads, ['record:c1', 'players:c1']);
      expect(member.reads, guest.reads);
    });

    testWidgets('the signed-in page reads none of the authenticated football',
        (tester) async {
      final adapter = _Adapter(record: record, players: fifteen());
      await pumpPage(tester, _Audience.nonMember, adapter);
      await openTab(tester, 1);
      await openTab(tester, 2);

      expect(adapter.authenticatedFootball.calls, isEmpty,
          reason: 'v_football_* are authenticated-only; the page reads the '
              'narrow public contracts instead');
    });

    testWidgets('upcoming rosters stay private for both', (tester) async {
      for (final audience in _Audience.values) {
        final adapter = _Adapter(record: record, players: fifteen());
        await pumpPage(tester, audience, adapter);
        await openTab(tester, 1);

        expect(find.byType(PublicMatchCard), findsOneWidget);
        expect(adapter.lineupReads, isEmpty,
            reason: '${audience.label}: no roster is asked for');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  // --------------------------------------------------------------------------
  // What a tap does -- the only thing that may differ
  // --------------------------------------------------------------------------
  group('joining is unchanged', () {
    testWidgets('a guest is asked for an account, from the hero',
        (tester) async {
      await pumpPage(tester, _Audience.guest, _Adapter());

      await tester.tap(find.byKey(const Key('publicCommunityJoin')));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to join this community.'),
          findsOneWidget);
    });

    testWidgets('and from an upcoming match, for that match', (tester) async {
      await pumpPage(tester, _Audience.guest, _Adapter());
      await openTab(tester, 1);

      await tester.tap(find.descendant(
        of: find.byType(PublicMatchCard),
        matching: find.byType(FilledButton),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to register for this match.'),
          findsOneWidget);
    });

    testWidgets('a signed-in non-member keeps the real join button',
        (tester) async {
      await pumpPage(tester, _Audience.nonMember, _Adapter());

      expect(find.byKey(const Key('footballCommunityJoin')), findsOneWidget);
      expect(find.byKey(const Key('publicCommunityJoin')), findsNothing);
    });
  });

  // --------------------------------------------------------------------------
  // Refresh
  // --------------------------------------------------------------------------
  for (final audience in _Audience.values) {
    group('${audience.label}: pull to refresh', () {
      testWidgets('keeps the selected tab and re-reads the football',
          (tester) async {
        final adapter = _Adapter(
          record: record,
          players: fifteen(),
          results: [result('m1')],
        );
        await pumpPage(tester, audience, adapter);
        await openTab(tester, 2);
        expect(adapter.footballReads, ['record:c1', 'players:c1']);
        expect(find.byType(TopPlayerRow), findsNWidgets(11));

        // The refresh each tab already offers, driven through its own
        // `RefreshIndicator`: the same `onRefresh` a pull down runs.
        final indicator = tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first);
        unawaited(indicator.show());
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }

        expect(adapter.footballReads.length, 4,
            reason: 'both contracts were read again');
        expect(controllerOf(tester).index, 2,
            reason: 'newer players were asked for, not the first tab');
        expect(find.byType(TopPlayerRow), findsNWidgets(11));
        expect(find.byType(ClubHero), findsOneWidget,
            reason: 'the page stayed up while it refreshed');
      });

      testWidgets('works on every tab', (tester) async {
        final adapter = _Adapter(record: record, results: [result('m1')]);
        await pumpPage(tester, audience, adapter);

        for (final index in [1, 0, 2]) {
          await openTab(tester, index);
          final before = adapter.footballReads.length;

          final indicator = tester.state<RefreshIndicatorState>(
              find.byType(RefreshIndicator).first);
          unawaited(indicator.show());
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 400));
          }

          expect(controllerOf(tester).index, index);
          expect(adapter.footballReads.length, before + 2,
              reason: 'tab $index');
        }
      });

      testWidgets('an empty tab can still be pulled', (tester) async {
        await pumpPage(tester, audience, _Adapter());
        await openTab(tester, 2);

        final indicator = tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first);
        final list = tester.widget<ListView>(find.descendant(
          of: find.byKey(const Key('communityTabPlayers')),
          matching: find.byType(ListView),
        ));
        expect(list.physics, isA<AlwaysScrollableScrollPhysics>());
        expect(indicator, isNotNull);
      });
    });
  }

  // --------------------------------------------------------------------------
  // Both pages, narrow, both languages, every tab
  // --------------------------------------------------------------------------
  group('nothing overflows on either page', () {
    const longEn = 'Muhammad Abdullah Al-Rashidi Al-Balushi Of Muscat';
    const longAr = 'محمد عبدالله بن سعيد الراشدي البلوشي المسقطي';

    for (final audience in _Audience.values) {
      for (final width in [320.0, 412.0]) {
        for (final locale in [en, ar]) {
          testWidgets(
              '${audience.label} at ${width.toInt()}px in ${locale.languageCode}',
              (tester) async {
            final adapter = _Adapter(
              record: record,
              results: [result('m1'), result('m2')],
              players: [
                for (var i = 1; i <= 11; i++)
                  topPlayer(
                    i,
                    name: locale == ar ? longAr : longEn,
                    rating: 9.0 - i * 0.1,
                    goals: 100 + i,
                    mvp: 10 + i,
                  ),
              ],
            );
            await pumpPage(
              tester,
              audience,
              adapter,
              locale: locale,
              size: Size(width, 1400),
            );

            for (final index in [0, 1, 2]) {
              await openTab(tester, index);
              expect(tester.takeException(), isNull, reason: 'tab $index');
            }
          });
        }
      }
    }
  });
}

enum _Audience {
  guest('a signed-out guest'),
  nonMember('a signed-in non-member');

  const _Audience(this.label);
  final String label;
}

/// The public reads, answered from memory.
class _Adapter implements DiscoverAdapter {
  _Adapter({
    this.results = const [],
    this.players = const [],
    this.record = const PublicCommunityFootballRecord(
      communityId: 'c1',
      completedMatches: 0,
      players: 0,
      goals: 0,
      mvpCount: 0,
    ),
  });

  List<PublicResult> results;
  List<PublicCommunityTopPlayer> players;
  PublicCommunityFootballRecord record;

  bool failFootball = false;

  /// Held until completed, so a test can look at the page mid-read.
  Completer<void>? footballGate;

  /// One entry per read of the football contracts.
  final List<String> footballReads = [];
  final List<String> lineupReads = [];

  /// Stands in for the authenticated football views. Every call is recorded and
  /// refused: a community page that reads them is a page that has stopped
  /// being the public one.
  final authenticatedFootball = _AuthenticatedFootball();

  PublicCommunity get _community => const PublicCommunity(
        id: 'c1',
        name: 'Al Amerat FC',
        memberCount: 12,
        upcomingMatchCount: 1,
      );

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async =>
      _community;

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => [_community];

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      [
        PublicMatch(
          id: 'up1',
          communityId: 'c1',
          communityName: 'Al Amerat FC',
          title: 'Friday night five-a-side',
          location: 'Al Amerat Pitch',
          startAt: DateTime(2026, 9, 25, 19),
          endAt: DateTime(2026, 9, 25, 21),
          startingPlayers: 10,
          openSlots: 6,
        ),
      ];

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async =>
      results.take(limit).toList();

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async => null;

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async {
    lineupReads.add(matchId);
    return const [];
  }

  @override
  Future<PublicCommunityFootballRecord> fetchCommunityFootballRecord(
    String communityId,
  ) async {
    footballReads.add('record:$communityId');
    await footballGate?.future;
    if (failFootball) throw StateError('offline');
    return record;
  }

  @override
  Future<List<PublicCommunityTopPlayer>> fetchCommunityTopPlayers(
    String communityId,
  ) async {
    footballReads.add('players:$communityId');
    await footballGate?.future;
    if (failFootball) throw StateError('offline');
    return players;
  }
}

class _AuthenticatedFootball implements FootballAdapter {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('an authenticated football read was made');
  }
}

class _NoCommunities implements CommunityAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no community read is expected here');
}

class _GuestAuth implements AuthAdapter {
  @override
  bool get isSignedIn => false;

  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
