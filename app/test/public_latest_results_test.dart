import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/results/score_pair.dart';

/// Latest Results for a reader with no account.
///
/// **The defect this fixes:** a guest was shown what is coming up and nothing
/// that had been played, although every completed public match was already
/// openable by id. The listing is the missing half, and it is the narrow public
/// contract migration `0081` grants `anon` — so nothing here asks a visitor to
/// sign in to see a result that is public.
void main() {
  PublicResult result(
    String id, {
    String community = 'Al Amerat FC',
    String communityId = 'c1',
    int a = 3,
    int b = 2,
    String? mvp,
  }) =>
      PublicResult(
        matchId: id,
        communityId: communityId,
        communityName: community,
        title: 'Friday football',
        location: 'Al Amerat Pitch',
        startAt: DateTime(2026, 9, 11, 17),
        teamAScore: a,
        teamBScore: b,
        mvpDisplayName: mvp,
      );

  PublicCommunity community(String id, String name) => PublicCommunity(
        id: id,
        name: name,
        memberCount: 8,
        upcomingMatchCount: 0,
      );

  Future<_Routes> pumpDiscover(
    WidgetTester tester,
    _Discover adapter, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: [routes],
      home: DiscoverScreen(
        repository: DiscoverRepository(adapter),
        authService: AuthService(_GuestAuth()),
      ),
    ));
    await tester.pumpAndSettle();
    return routes;
  }

  group('a guest gets the results on Discover', () {
    testWidgets('the section is there, between upcoming and communities',
        (tester) async {
      await pumpDiscover(
        tester,
        _Discover(
          results: [result('m1')],
          communities: [community('c1', 'Al Amerat FC')],
        ),
      );

      final matches = tester.getTopLeft(find.text('Upcoming matches')).dy;
      final results = tester.getTopLeft(find.text('Latest results')).dy;
      final communities = tester.getTopLeft(find.text('Communities')).dy;

      expect(matches, lessThan(results));
      expect(results, lessThan(communities));
      expect(find.byType(PublicResultCard), findsOneWidget);
    });

    testWidgets('nothing played yet is said, not hidden', (tester) async {
      await pumpDiscover(
        tester,
        _Discover(communities: [community('c1', 'Al Amerat FC')]),
      );

      expect(find.text('Latest results'), findsOneWidget);
      expect(find.byType(PublicResultCard), findsNothing);
    });

    testWidgets('the newest is shown and the rest are one tap away',
        (tester) async {
      await pumpDiscover(
        tester,
        _Discover(results: [
          for (var i = 1; i <= 5; i++) result('m$i'),
        ]),
      );

      expect(find.byType(PublicResultCard), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('discoverPublicPreviousResultsToggle')));
      await tester.pumpAndSettle();
      expect(find.byType(PublicResultCard), findsNWidgets(5));
    });

    testWidgets('tapping one opens the public completed match, with no prompt',
        (tester) async {
      final routes = await pumpDiscover(
        tester,
        _Discover(results: [result('m1')]),
      );
      routes.pushed.clear();

      await tester.tap(find.byType(PublicResultCard));
      await tester.pumpAndSettle();

      expect(find.byType(PublicMatchScreen), findsOneWidget);
      // One push, and it is that page: no sign-in sheet stands between a
      // visitor and a result that is already public.
      expect(routes.pushed, hasLength(1));
    });

    testWidgets('a guest still never asks for authenticated football',
        (tester) async {
      final adapter = _Discover(results: [result('m1')]);
      await pumpDiscover(tester, adapter);

      // The public contract, and only it.
      expect(adapter.recentResultsRequests, [null]);
    });
  });

  group('a public community page shows its own results', () {
    testWidgets('scoped to that community, under its upcoming matches',
        (tester) async {
      final adapter = _Discover(
        results: [
          result('m1', communityId: 'c1'),
          result('m2', communityId: 'c2', community: 'Al Seeb'),
        ],
        communities: [community('c1', 'Al Amerat FC')],
      );

      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final routes = _Routes();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [routes],
        home: PublicCommunityScreen(
          communityId: 'c1',
          repository: DiscoverRepository(adapter),
          authService: AuthService(_GuestAuth()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(adapter.recentResultsRequests, ['c1']);
      expect(find.text('Latest results'), findsOneWidget);
      expect(find.byType(PublicResultCard), findsOneWidget);

      routes.pushed.clear();
      await tester.tap(find.byType(PublicResultCard));
      await tester.pumpAndSettle();

      expect(find.byType(PublicMatchScreen), findsOneWidget);
      expect(routes.pushed, hasLength(1));
    });

    testWidgets('a community with nothing scheduled is not an empty page',
        (tester) async {
      final adapter = _Discover(
        results: [result('m1', communityId: 'c1')],
        communities: [community('c1', 'Al Amerat FC')],
      );

      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PublicCommunityScreen(
          communityId: 'c1',
          repository: DiscoverRepository(adapter),
          authService: AuthService(_GuestAuth()),
        ),
      ));
      await tester.pumpAndSettle();

      // No upcoming match, and the page still has football on it.
      expect(find.byType(PublicMatchCard), findsNothing);
      expect(find.byType(PublicResultCard), findsOneWidget);
    });
  });

  group('the score is bound to its team', () {
    Future<void> pumpScore(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(
          body: Center(child: ScorePair(teamAScore: 2, teamBScore: 3)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('each number carries its team, and no ambiguous string',
        (tester) async {
      await pumpScore(tester, const Locale('en'));

      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // The thing the approved contract rules out.
      expect(find.text('2 - 3'), findsNothing);
    });

    testWidgets(
        'Arabic mirrors the pair without separating a team from its '
        'score', (tester) async {
      await pumpScore(tester, const Locale('ar'));

      final teamA = tester.getCenter(find.text('الفريق أ'));
      final teamB = tester.getCenter(find.text('الفريق ب'));
      final two = tester.getCenter(find.text('2'));
      final three = tester.getCenter(find.text('3'));

      // Team A leads, which in Arabic is the right; each score sits over its
      // own team's name rather than in a fixed left-to-right pair.
      expect(teamA.dx, greaterThan(teamB.dx));
      expect((two.dx - teamA.dx).abs(), lessThan(4));
      expect((three.dx - teamB.dx).abs(), lessThan(4));
    });
  });
}

/// Remembers the routes a screen pushed, so a destination can be read without
/// mounting it — `PublicMatchScreen` builds the production repository when it
/// is not given one, and that needs a Supabase this suite has no business
/// starting.
class _Routes extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

/// A discover port that answers from what a test handed it.
class _Discover implements DiscoverAdapter {
  _Discover({this.results = const [], this.communities = const []});

  final List<PublicResult> results;
  final List<PublicCommunity> communities;

  /// One entry per read, carrying the community it was scoped to.
  final List<String?> recentResultsRequests = [];

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async {
    recentResultsRequests.add(communityId);
    return [
      for (final result in results)
        if (communityId == null || result.communityId == communityId) result,
    ].take(limit).toList();
  }

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      const [];

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

class _GuestAuth implements AuthAdapter {
  @override
  bool get isSignedIn => false;

  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
