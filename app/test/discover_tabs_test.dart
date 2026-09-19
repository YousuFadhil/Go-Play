import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/discover_tabs.dart';
import 'package:go_play/features/discover/discover_widgets.dart';

/// Discover, as one shell with three tabs.
///
/// **The defect this closes.** Discover used to render Upcoming Matches,
/// Latest Results and Communities one under another down a single page, and it
/// reorganised itself around the reader: a guest got the public results
/// section, a member got a different one, and finding a community meant
/// scrolling past every fixture and every result. The approved direction is
/// one composition with three tabs — identical for both readers, with the
/// session changing what the cards can *do* and never the shape of the page.
void main() {
  PublicMatch match(String id, {String title = 'Friday five-a-side'}) =>
      PublicMatch(
        id: id,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: title,
        location: 'Al Amerat Pitch',
        startAt: DateTime(2026, 9, 25, 19),
        endAt: DateTime(2026, 9, 25, 21),
        startingPlayers: 10,
        openSlots: 6,
      );

  PublicResult result(String id, {String title = 'Played on Friday'}) =>
      PublicResult(
        matchId: id,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: title,
        location: 'Al Amerat Pitch',
        startAt: DateTime(2026, 9, 11, 17),
        teamAScore: 3,
        teamBScore: 2,
      );

  PublicCommunity community(String id, String name) => PublicCommunity(
        id: id,
        name: name,
        memberCount: 12,
        upcomingMatchCount: 2,
      );

  Future<_Discover> pump(
    WidgetTester tester, {
    bool signedIn = false,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = _Discover(
      matches: [match('m1'), match('m2')],
      results: [for (var i = 1; i <= 5; i++) result('r$i', title: 'Result $i')],
      communities: [community('c1', 'Al Amerat FC')],
    );

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: DiscoverScreen(
        repository: DiscoverRepository(adapter),
        authService: AuthService(_Auth(signedIn: signedIn)),
      ),
    ));
    await tester.pumpAndSettle();
    return adapter;
  }

  Finder tabAt(int index) => find
      .descendant(of: find.byType(DiscoverTabs), matching: find.byType(Tab))
      .at(index);

  Future<void> openTab(WidgetTester tester, int index) async {
    await tester.ensureVisible(tabAt(index));
    await tester.pumpAndSettle();
    await tester.tap(tabAt(index));
    await tester.pumpAndSettle();
  }

  group('three tabs, and Upcoming is where it opens', () {
    testWidgets('the control is there, with the approved three',
        (tester) async {
      await pump(tester);

      expect(find.byType(DiscoverTabs), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(DiscoverTabs), matching: find.byType(Tab)),
        findsNWidgets(3),
      );
      expect(find.text('Upcoming matches'), findsOneWidget);
      expect(find.text('Latest results'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
    });

    testWidgets('Upcoming is selected on a fresh open', (tester) async {
      await pump(tester);

      final controller = DefaultTabController.maybeOf(
        tester.element(find.byType(DiscoverTabs)),
      );
      // The screen owns its controller rather than inheriting one.
      expect(controller, isNull);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    });

    testWidgets('and only its content is on screen', (tester) async {
      await pump(tester);

      expect(find.byType(CompactPublicMatchCard), findsNWidgets(2));
      expect(find.byType(PublicResultCard), findsNothing);
      expect(find.byType(CompactPublicCommunityCard), findsNothing);
    });
  });

  group('each tab shows its own football', () {
    testWidgets('Latest Results when it is asked for', (tester) async {
      await pump(tester);
      await openTab(tester, 1);

      expect(find.byType(PublicResultCard), findsNWidgets(3));
      expect(find.byType(CompactPublicMatchCard), findsNothing);
      expect(find.byType(CompactPublicCommunityCard), findsNothing);
    });

    testWidgets('Communities when it is asked for', (tester) async {
      await pump(tester);
      await openTab(tester, 2);

      expect(find.byType(CompactPublicCommunityCard), findsOneWidget);
      expect(find.byType(CompactPublicMatchCard), findsNothing);
      expect(find.byType(PublicResultCard), findsNothing);
    });

    testWidgets('and the old stacked composition is gone', (tester) async {
      // All three used to be on one page at once. Whichever tab is open, the
      // other two are not rendered beside it.
      await pump(tester);
      for (final index in [0, 1, 2]) {
        await openTab(tester, index);
        final kinds = [
          find.byType(CompactPublicMatchCard).evaluate().isNotEmpty,
          find.byType(PublicResultCard).evaluate().isNotEmpty,
          find.byType(CompactPublicCommunityCard).evaluate().isNotEmpty,
        ].where((shown) => shown).length;
        expect(kinds, 1, reason: 'tab $index showed more than its own content');
      }
    });
  });

  group('switching a tab is presentation, not a read', () {
    testWidgets('no repository call is made by changing tab', (tester) async {
      final adapter = await pump(tester);
      final afterLoad = adapter.overviewCalls;
      expect(afterLoad, 1);

      await openTab(tester, 1);
      await openTab(tester, 2);
      await openTab(tester, 0);
      await openTab(tester, 1);

      expect(adapter.overviewCalls, afterLoad,
          reason: 'the data was already in memory');
    });

    testWidgets('and the loaded results survive the round trip',
        (tester) async {
      await pump(tester);
      await openTab(tester, 1);
      expect(find.text('Result 1'), findsOneWidget);

      await openTab(tester, 0);
      await openTab(tester, 1);
      expect(find.text('Result 1'), findsOneWidget);
    });
  });

  group('a pull-to-refresh keeps the reader where they were', () {
    testWidgets('the selected tab is not reset', (tester) async {
      final adapter = await pump(tester);
      await openTab(tester, 2);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);

      final indicator = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator).first,
      );
      unawaited(indicator.show());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(adapter.overviewCalls, greaterThan(1), reason: 'it did refresh');
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2,
          reason: 'a refresh asks for newer data, not for a different tab');
    });
  });

  group('one shell, whoever is reading', () {
    testWidgets(
        'a guest and a member get the same three tabs in the same '
        'place', (tester) async {
      await pump(tester);
      final guestTabs = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(tabAt(i)),
      ];
      final guestLabels = tester
          .widgetList<Tab>(find.byType(Tab))
          .map((t) => (t.child! as Text).data)
          .toList();

      await pump(tester, signedIn: true);
      final memberTabs = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(tabAt(i)),
      ];
      final memberLabels = tester
          .widgetList<Tab>(find.byType(Tab))
          .map((t) => (t.child! as Text).data)
          .toList();

      expect(memberLabels, guestLabels);
      expect(memberTabs, guestTabs);
    });

    testWidgets('and the hero and sheet are the same composition',
        (tester) async {
      for (final signedIn in [false, true]) {
        await pump(tester, signedIn: signedIn);
        expect(find.byType(ClubHero), findsOneWidget);
        expect(find.byType(ClubSheet), findsOneWidget);
        expect(find.byType(DiscoverTabs), findsOneWidget);
      }
    });
  });

  group('the labels fit, or the bar scrolls rather than cutting them', () {
    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets('at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(
            tester,
            locale: locale,
            size: Size(width, 1400),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(DiscoverTabs), findsOneWidget);

          // Never ellipsized: whichever way the bar lays out, every label is
          // drawn whole. `softWrap: false` plus a scrollable bar is what makes
          // that true at 320px in Arabic.
          for (final tab in tester.widgetList<Tab>(find.byType(Tab))) {
            final label = tab.child! as Text;
            expect(label.overflow, isNot(TextOverflow.ellipsis));
            expect(label.softWrap, isFalse);
            expect(label.data, isNotEmpty);
          }

          // And all three are reachable.
          for (final index in [0, 1, 2]) {
            await openTab(tester, index);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  });
}

void unawaited(Future<void> future) {}

class _Discover implements DiscoverAdapter {
  _Discover({
    this.matches = const [],
    this.results = const [],
    this.communities = const [],
  });

  final List<PublicMatch> matches;
  final List<PublicResult> results;
  final List<PublicCommunity> communities;

  /// One per composed overview: the repository reads three ports to build it,
  /// and the upcoming-matches read is the one that happens exactly once each
  /// time.
  int overviewCalls = 0;

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async =>
      results;

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async {
    overviewCalls++;
    return matches;
  }

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => communities;

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async =>
      communities.firstWhere((c) => c.id == communityId);

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async => null;

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth implements AuthAdapter {
  _Auth({required this.signedIn});

  final bool signedIn;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentUserId => signedIn ? 'u1' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
