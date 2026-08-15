import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/statistics/community_dashboard_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community Dashboard, against a fake port.
///
/// Two things are asserted here and they are deliberately separate: what the
/// repository makes of a set of rows — which is where every product decision
/// about leaders lives — and what the screen shows of the result.
void main() {
  CommunityPlayerStatistics player(
    String id,
    String? name, {
    int played = 0,
    int wins = 0,
    int losses = 0,
    int draws = 0,
    int goals = 0,
    int mvp = 0,
    String? avatarUrl,
  }) =>
      CommunityPlayerStatistics(
        userId: id,
        fullName: name,
        avatarUrl: avatarUrl,
        matchesPlayed: played,
        wins: wins,
        losses: losses,
        draws: draws,
        goals: goals,
        mvpCount: mvp,
      );

  /// A community mid-season: three players, one clear leader per measure.
  final squad = [
    // Ali has set a picture; Sara has not, so both the picture and the fallback
    // are on the same dashboard.
    player('u1', 'Ali',
        played: 3,
        wins: 2,
        losses: 1,
        goals: 5,
        mvp: 1,
        avatarUrl: 'https://example.test/u1.jpg'),
    player('u2', 'Sara', played: 4, wins: 1, losses: 3, goals: 2, mvp: 2),
    player('u3', 'Omar', played: 1, draws: 1, goals: 0, mvp: 0),
  ];

  group('assembling the dashboard', () {
    test('the totals are the community, not one player', () async {
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.completedMatches, 6);
      expect(dashboard.totalPlayers, 3);
      expect(dashboard.totalGoals, 7);
    });

    test('the match count comes from the match domain, never from the counters',
        () async {
      // Summing matches_played would give 8 -- three players' appearances in
      // the same matches. The two figures are different questions, and the
      // dashboard must not answer one with the other.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.completedMatches, 6);
      expect(dashboard.completedMatches, isNot(8));
    });

    test('the match count is the officially completed one, and nothing else',
        () async {
      // The community has fifteen matches; six carry the completed status. The
      // dashboard is its settled history, so nothing else contributes: not a
      // match still open or full, and not one whose end time has passed while
      // it waits for its result. The port answers that single question, and
      // there is no other total for the repository to fall back on -- the count
      // is taken from the completed-matches read and never derived here.
      final adapter = FakeStatisticsAdapter(players: squad, completedMatches: 6);
      final dashboard = await StatisticsRepository(adapter).fetchDashboard('c1');

      expect(adapter.completedMatchReads, 1);
      expect(dashboard.completedMatches, 6);
    });

    test('each leader is the highest of its own measure', () async {
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.topScorer?.fullName, 'Ali');
      expect(dashboard.topScorer?.value, 5);
      expect(dashboard.mostActivePlayer?.fullName, 'Sara');
      expect(dashboard.mostActivePlayer?.value, 4);
      expect(dashboard.mostMvp?.fullName, 'Sara');
      expect(dashboard.mostMvp?.value, 2);
    });

    test('nobody leads a measure that has not happened', () async {
      // Every member holds a record from the moment they join, so a community
      // with no recorded result is a table full of zeros. Naming a "top
      // scorer" out of it would be picking a name at random.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(
          players: [player('u1', 'Ali'), player('u2', 'Sara')],
          completedMatches: 2,
        ),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.totalPlayers, 2);
      expect(dashboard.totalGoals, 0);
      expect(dashboard.topScorer, isNull);
      expect(dashboard.mostActivePlayer, isNull);
      expect(dashboard.mostMvp, isNull);
    });

    test('a tie names the same player every time', () async {
      final tied = [
        player('u2', 'Sara', goals: 3),
        player('u1', 'Ali', goals: 3),
      ];
      final first = await StatisticsRepository(
        FakeStatisticsAdapter(players: tied, completedMatches: 1),
      ).fetchDashboard('c1');
      final second = await StatisticsRepository(
        FakeStatisticsAdapter(players: tied.reversed.toList(), completedMatches: 1),
      ).fetchDashboard('c1');

      expect(first.topScorer?.fullName, 'Ali');
      expect(second.topScorer?.fullName, first.topScorer?.fullName,
          reason: 'the row order must not decide who leads');
    });

    test('a departed player still counts, and can still lead', () async {
      // A soft-deleted account keeps its statistics and loses its profile. The
      // goals happened, so they stay in the total and the name is simply
      // unavailable.
      final repository = StatisticsRepository(
        FakeStatisticsAdapter(
          players: [player('u1', null, played: 2, goals: 9)],
          completedMatches: 2,
        ),
      );

      final dashboard = await repository.fetchDashboard('c1');

      expect(dashboard.totalGoals, 9);
      expect(dashboard.totalPlayers, 1);
      expect(dashboard.topScorer?.value, 9);
      expect(dashboard.topScorer?.fullName, isNull);
    });
  });

  group('the screen', () {
    Future<void> pumpDashboard(
      WidgetTester tester,
      FakeStatisticsAdapter adapter, {
      Locale locale = const Locale('en'),
      bool settle = true,
      NavigatorObserver? observer,
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observer == null ? const [] : [observer],
        home: Scaffold(
          body: CommunityDashboardTab(
            communityId: 'c1',
            repository: StatisticsRepository(adapter),
          ),
        ),
      ));
      if (settle) await tester.pumpAndSettle();
    }

    // --- player identity on a leader tile ---------------------------------------

    testWidgets('a leader tile carries a face', (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      // Ali leads Top scorer with a picture; Sara leads Most MVP without one
      // and falls back to the initials every other surface uses.
      final ali = tester.widget<PlayerAvatar>(find.descendant(
        of: find.byKey(const Key('leaderIdentity_u1')).first,
        matching: find.byType(PlayerAvatar),
      ));
      expect(ali.avatarUrl, 'https://example.test/u1.jpg');
      expect(ali.isProfessionalGuest, isFalse);

      final sara = tester.widget<PlayerAvatar>(find.descendant(
        of: find.byKey(const Key('leaderIdentity_u2')).first,
        matching: find.byType(PlayerAvatar),
      ));
      expect(sara.avatarUrl, isNull);
    });

    testWidgets('the leader identity opens that player', (tester) async {
      final observer = _DashboardRouteRecorder();
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
        observer: observer,
      );
      observer.pushed.clear();

      await tester.tap(find.byKey(const Key('leaderIdentity_u1')).first);

      final screen = observer.pushed.single
          .builder(tester.element(find.byType(CommunityDashboardTab)));
      expect((screen as ProfileScreen).userId, 'u1');
      observer.discard();
    });

    testWidgets('a record that outlived its profile opens nothing',
        (tester) async {
      final observer = _DashboardRouteRecorder();
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(
          players: [player('gone', null, played: 2, goals: 9)],
          completedMatches: 2,
        ),
        observer: observer,
      );
      observer.pushed.clear();

      // The label itself is covered by 'an unnamed leader is labelled rather
      // than blank'; what is new here is that it leads nowhere.
      await tester.tap(find.byKey(const Key('leaderIdentity_gone')).first);
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty,
          reason: 'the account is gone, so there is no record to open and no '
              'link certain to be refused');
    });

    testWidgets('a measure nobody leads still says so, with no player on it',
        (tester) async {
      // Ali has played and scored but has never been named best player, so two
      // measures have a leader and the third has none.
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(
          players: [player('u1', 'Ali', played: 2, goals: 3)],
          completedMatches: 2,
        ),
      );

      final mvpTile = find.widgetWithText(LeaderTile, 'Most valuable player');
      expect(find.descendant(of: mvpTile, matching: find.text('Not yet')),
          findsOneWidget);
      expect(find.descendant(of: mvpTile, matching: find.byType(PlayerAvatar)),
          findsNothing,
          reason: 'an absence is not a player');

      // And the measures that do have one still draw them.
      expect(
        find.descendant(
          of: find.widgetWithText(LeaderTile, 'Top scorer'),
          matching: find.byType(PlayerAvatar),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the figures are unchanged', (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      // The same numbers the tiles carried before they carried faces.
      expect(find.text('5 goals'), findsOneWidget);
      expect(find.text('4 matches'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);
    });

    testWidgets('shows the indicator until the figures arrive', (tester) async {
      final gate = Completer<void>();
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6, gate: gate.future),
        settle: false,
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the six figures are on the screen', (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      // The three community totals.
      expect(find.text('Completed matches'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Total players'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Total goals'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      // The three leaders, each with its value in its own words.
      expect(find.text('Top scorer'), findsOneWidget);
      expect(find.text('5 goals'), findsOneWidget);
      expect(find.text('Most active player'), findsOneWidget);
      expect(find.text('4 matches'), findsOneWidget);
      expect(find.text('Most valuable player'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);

      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Sara'), findsNWidgets(2));
    });

    testWidgets('a community with no results says so rather than inventing one',
        (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(
          players: [player('u1', 'Ali'), player('u2', 'Sara')],
          completedMatches: 2,
        ),
      );

      // One empty state where the three leader rows would be, rather than
      // three rows each saying "Not yet" in its own words.
      expect(find.text('Ali'), findsNothing,
          reason: 'nobody is named the leader of a measure at zero');
      expect(find.text('Top scorer'), findsNothing);
      expect(
        find.textContaining('No results have been recorded'),
        findsOneWidget,
      );
    });

    testWidgets('an unnamed leader is labelled rather than blank',
        (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(
          players: [player('u1', null, played: 2, goals: 9)],
          completedMatches: 2,
        ),
      );

      expect(find.text('Former player'), findsWidgets);
      expect(find.text('9 goals'), findsOneWidget);
    });

    testWidgets('the scope of the figures is stated on the screen',
        (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      // Every figure counts completed matches only, and the player figures
      // narrow that further to matches with a recorded result. The screen says
      // both, because the two can differ and nothing else explains why.
      expect(find.textContaining('completed matches only'), findsOneWidget);
      expect(
        find.textContaining('result has been recorded'),
        findsOneWidget,
      );
    });

    testWidgets('a load that fails offers a retry', (tester) async {
      final adapter = FakeStatisticsAdapter(
        players: squad,
        completedMatches: 6,
        failure: const NetworkFailure(),
      );
      await pumpDashboard(tester, adapter);

      expect(find.text('Failed to load data.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.reads, 2);
    });

    testWidgets('nothing on it is editable', (tester) async {
      // Every counter is a consequence of a recorded result. There is no
      // client write path, so there is nothing here to type into or submit.
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('Arabic renders the dashboard in Arabic', (tester) async {
      await pumpDashboard(
        tester,
        FakeStatisticsAdapter(players: squad, completedMatches: 6),
        locale: const Locale('ar'),
      );

      expect(find.text('إحصائيات المجتمع'), findsOneWidget);
      expect(find.text('المباريات المكتملة'), findsOneWidget);
      expect(find.text('الهدّاف'), findsOneWidget);
      expect(find.text('المتصدّرون'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('إحصائيات المجتمع'))),
        TextDirection.rtl,
      );
    });
  });
}

/// The statistics port, answering from memory and counting what it was asked.
class FakeStatisticsAdapter implements StatisticsAdapter {
  FakeStatisticsAdapter({
    required this.players,
    required this.completedMatches,
    this.failure,
    this.gate,
  });

  final List<CommunityPlayerStatistics> players;
  final int completedMatches;
  final Failure? failure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;

  /// Counted separately, so a test can assert that the match figure came from
  /// the completed-matches read and not from anywhere else.
  int completedMatchReads = 0;

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
  ) async {
    reads++;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return players;
  }

  @override
  Future<int> fetchCompletedMatches(String communityId) async {
    completedMatchReads++;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return completedMatches;
  }

  /// The dashboard ranks nobody, so it never reads the roster. Reaching this
  /// from it would be a defect, so it fails loudly rather than answering.
  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      throw UnimplementedError('the Community Dashboard reads no roster');
}

/// Records a pushed route without letting it build: `ProfileScreen` makes the
/// production repositories when nobody injects any, and this suite has no data
/// provider.
class _DashboardRouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}
