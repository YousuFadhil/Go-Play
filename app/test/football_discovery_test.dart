import 'dart:typed_data';

import 'dart:async';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_details_screen.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_community_screen.dart';
import 'package:go_play/features/football/football_match_screen.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/match_result_card.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/teams/match_stage.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';

/// Cycle 3: the football discovery experience.
///
/// What the *database* gives whom is proved in
/// `test/integration/public_football_data_test.dart` and was verified live when
/// `0057` was applied. What is asserted here is everything above it: that a
/// guest never reaches the authenticated football reads at all, that a
/// signed-in reader is routed by membership rather than by hope, that a
/// completed match reads correctly including the states that are easy to fake
/// (no result, no MVP, no lineup), and that viewing football confers no
/// management capability.
void main() {
  // --------------------------------------------------------------------------
  // Fixtures
  // --------------------------------------------------------------------------
  PublicCommunity community(String id, String name) => PublicCommunity(
        id: id,
        name: name,
        memberCount: 12,
        upcomingMatchCount: 1,
      );

  PublicMatch upcoming(String id, {String communityId = 'c1'}) => PublicMatch(
        id: id,
        communityId: communityId,
        communityName: 'Muscat United',
        location: 'Al Amerat',
        startAt: DateTime.now().add(const Duration(days: 2)),
        endAt: DateTime.now().add(const Duration(days: 2, hours: 2)),
        startingPlayers: 10,
        openSlots: 4,
        title: 'Friday night',
      );

  FootballParticipant player(
    String id,
    String name, {
    String? position = 'MID',
  }) =>
      FootballParticipant(
        type: ParticipantType.user,
        displayName: name,
        userId: id,
        primaryPosition: position,
        overallRating: 6.4,
      );

  const guest = FootballParticipant(
    type: ParticipantType.professionalGuest,
    displayName: 'Guest Striker',
    guestId: 'g1',
  );

  CompletedMatch completed(
    String id, {
    String communityId = 'c1',
    String communityName = 'Muscat United',
    DateTime? start,
    bool hasResult = true,
    int? a = 3,
    int? b = 2,
    FootballParticipant? mvp,
    String? title = 'Friday night',
  }) =>
      CompletedMatch(
        matchId: id,
        communityId: communityId,
        communityName: communityName,
        location: 'Al Amerat',
        startAt: start ?? DateTime(2026, 8, 20, 18),
        endAt: (start ?? DateTime(2026, 8, 20, 18))
            .add(const Duration(hours: 2)),
        isHistorical: false,
        hasResult: hasResult,
        title: title,
        teamAScore: hasResult ? a : null,
        teamBScore: hasResult ? b : null,
        mvp: mvp,
      );

  Widget wrap(
    Widget home, {
    Locale locale = const Locale('en'),
    List<NavigatorObserver> observers = const [],
  }) =>
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observers,
        home: home,
      );

  Future<({_FakeFootballAdapter football, _JoinedAdapter communities})>
      pumpDiscover(
    WidgetTester tester, {
    required bool signedIn,
    List<CompletedMatch> results = const [],
    List<PublicMatch> matches = const [],
    List<PublicCommunity> communities = const [],
    List<String> joined = const [],
    Object? footballFailure,
    Object? membershipFailure,
    Object? publicFailure,
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final football = _FakeFootballAdapter(
      results: results,
      failure: footballFailure,
    );
    final communitiesPort =
        _JoinedAdapter(joined, failure: membershipFailure);

    await tester.pumpWidget(wrap(DiscoverScreen(
      repository: DiscoverRepository(_FakeDiscoverAdapter(
        communities: communities,
        matches: matches,
        failure: publicFailure,
      )),
      authService: AuthService(_StubAuth(signedIn: signedIn)),
      footballRepository: FootballRepository(football),
      communityRepository: CommunityRepository(communitiesPort),
    ), observers: observers));
    await tester.pumpAndSettle();
    return (football: football, communities: communitiesPort);
  }

  // --------------------------------------------------------------------------
  group('a guest never reaches authenticated football', () {
    testWidgets('Discover does not call the football repository',
        (tester) async {
      final ports = await pumpDiscover(
        tester,
        signedIn: false,
        matches: [upcoming('m1')],
        communities: [community('c1', 'Muscat United')],
        results: [completed('p1')],
      );

      expect(ports.football.completedCalls, 0,
          reason: 'Cycle 2 granted football history to authenticated only; a '
              'guest must not ask for it at all');
      expect(ports.communities.myCommunitiesCalls, 0,
          reason: 'a guest has no membership to have, so nothing asks');
    });

    testWidgets('and still gets Upcoming and Communities', (tester) async {
      await pumpDiscover(
        tester,
        signedIn: false,
        matches: [upcoming('m1')],
        communities: [community('c1', 'Muscat United')],
      );

      expect(find.text('Upcoming matches'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
      expect(find.text('Latest results'), findsNothing,
          reason: 'the football section belongs to signed-in readers');
    });
  });

  group('the signed-in feed', () {
    testWidgets('shows Latest results between Upcoming and Communities',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        matches: [upcoming('m1')],
        communities: [community('c1', 'Muscat United')],
        results: [completed('p1')],
      );

      expect(find.text('Latest results'), findsOneWidget);

      final upcomingY = tester.getTopLeft(find.text('Upcoming matches')).dy;
      final resultsY = tester.getTopLeft(find.text('Latest results')).dy;
      final communitiesY = tester.getTopLeft(find.text('Communities')).dy;
      expect(upcomingY, lessThan(resultsY));
      expect(resultsY, lessThan(communitiesY));
    });

    testWidgets('newest first', (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        results: [
          completed('new', title: 'Newer', start: DateTime(2026, 8, 20)),
          completed('old', title: 'Older', start: DateTime(2026, 8, 10)),
        ],
      );

      // Only the newest is shown until the reader asks for the rest (Cycle
      // B2); the order under that disclosure is what this test owns.
      await tester.tap(find.byKey(const Key('discoverPreviousResultsToggle')));
      await tester.pumpAndSettle();

      // The repository preserves the order the read model returns, which is
      // most recent first; the screen must not re-sort it.
      expect(tester.getTopLeft(find.text('Newer')).dy,
          lessThan(tester.getTopLeft(find.text('Older')).dy));
    });

    testWidgets('a recorded match shows its score', (tester) async {
      await pumpDiscover(tester,
          signedIn: true, results: [completed('p1', a: 3, b: 2)]);

      expect(find.text('3 - 2'), findsOneWidget);
      expect(find.text('Result pending'), findsNothing);
    });

    testWidgets('an unrecorded match says so instead of showing 0-0',
        (tester) async {
      await pumpDiscover(tester,
          signedIn: true, results: [completed('p1', hasResult: false)]);

      expect(find.text('Result pending'), findsOneWidget);
      expect(find.text('0 - 0'), findsNothing,
          reason: '0-0 is a result somebody recorded; this is not');
    });

    testWidgets('an MVP is shown when one was named', (tester) async {
      await pumpDiscover(tester,
          signedIn: true,
          results: [completed('p1', mvp: player('u1', 'Salim Al Harthy'))]);

      expect(find.text('Salim Al Harthy'), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
    });

    // A separate test rather than a second pump: re-pumping the same widget
    // type reuses the Element, so the screen's State -- and the futures it
    // already holds -- would survive and the second case would assert nothing.
    testWidgets('and nothing is claimed when none was', (tester) async {
      await pumpDiscover(tester, signedIn: true, results: [completed('p2')]);

      expect(find.text('MVP'), findsNothing);
    });

    testWidgets('no completed matches is an empty state, not an error',
        (tester) async {
      await pumpDiscover(tester, signedIn: true, results: const []);

      expect(find.text('Latest results'), findsOneWidget);
      expect(find.textContaining('No results yet'), findsOneWidget);
    });

    // The sectional-failure rule: public content must survive a football
    // failure, because the two are different reads with different privileges.
    testWidgets('a football failure does not remove public Discover content',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        matches: [upcoming('m1')],
        communities: [community('c1', 'Muscat United')],
        footballFailure: StateError('football offline'),
      );

      expect(find.text('Upcoming matches'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
      expect(find.text('Muscat United'), findsWidgets);
      expect(find.textContaining('Could not load recent football'),
          findsOneWidget);
    });
  });

  // Navigation is asserted on the route that was pushed, not by building the
  // destination. Building `CommunityDetailsScreen`, `MatchDetailsScreen` or
  // `ProfileScreen` here would construct their real repositories and reach a
  // Supabase client that no widget test initialises. `MaterialPageRoute.builder`
  // returns the widget without mounting it, so the type is checkable and no
  // `State` -- and therefore no repository -- is ever created.
  group('membership decides where a card goes', () {
    Future<Widget?> tapAndCapture(
      WidgetTester tester,
      Finder target, {
      required bool signedIn,
      List<PublicCommunity> communities = const [],
      List<PublicMatch> matches = const [],
      List<String> joined = const [],
    }) async {
      final routes = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: signedIn,
        communities: communities,
        matches: matches,
        joined: joined,
        observers: [routes],
      );

      await tester.tap(target);
      await tester.idle();
      return routes.lastPushedWidget(tester);
    }

    // `CommunityDetailsScreen` and `MatchDetailsScreen` build their own
    // production repositories the moment they mount, so a widget test cannot
    // navigate to them. Their routing is asserted where it is decided.
    test('a member is routed to the member community screen', () {
      expect(
        communityDestinationFor(signedIn: true, isMember: true),
        CommunityDestination.memberDetails,
      );
    });

    test('a signed-in non-member is not', () {
      expect(
        communityDestinationFor(signedIn: true, isMember: false),
        CommunityDestination.football,
      );
    });

    test('a guest is routed to the public community screen', () {
      expect(
        communityDestinationFor(signedIn: false, isMember: false),
        CommunityDestination.guestPublic,
      );
      expect(
        communityDestinationFor(signedIn: false, isMember: true),
        CommunityDestination.guestPublic,
        reason: 'a guest has no membership to have',
      );
    });

    test('a member keeps the existing match-details flow', () {
      expect(
        upcomingMatchDestinationFor(signedIn: true, isMember: true),
        UpcomingMatchDestination.memberMatchDetails,
      );
    });

    test('a non-member is never sent into member-only match details', () {
      expect(
        upcomingMatchDestinationFor(signedIn: true, isMember: false),
        UpcomingMatchDestination.football,
      );
    });

    test('a guest still meets the sign-in gate', () {
      expect(
        upcomingMatchDestinationFor(signedIn: false, isMember: false),
        UpcomingMatchDestination.signInGate,
      );
    });

    // These two destinations receive Discover's injected repositories, so they
    // can be navigated to for real and the whole path is exercised.
    testWidgets('a guest actually lands on the public community screen',
        (tester) async {
      final pushed = await tapAndCapture(
        tester,
        find.text('View community'),
        signedIn: false,
        communities: [community('c1', 'Muscat United')],
      );

      expect(pushed, isA<PublicCommunityScreen>());
    });

    testWidgets('a signed-in non-member actually lands on the football '
        'community screen', (tester) async {
      final pushed = await tapAndCapture(
        tester,
        find.text('View community'),
        signedIn: true,
        communities: [community('c1', 'Muscat United')],
        joined: const [],
      );

      expect(pushed, isA<FootballCommunityScreen>(),
          reason: 'a non-member must not be sent into member-only reads that '
              'would come back empty');
      expect(pushed, isNot(isA<CommunityDetailsScreen>()));
    });

    testWidgets('a completed result opens the read-only football match screen',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        results: [completed('p1')],
        observers: [routes],
      );

      await tester.tap(find.text('Friday night'));
      await tester.idle();

      expect(routes.lastPushedWidget(tester), isA<FootballMatchScreen>());
    });
  });


  // ==========================================================================
  // The defect this correction exists for: membership and football history are
  // two different facts, loaded independently. A failed football read used to
  // resolve to a feed with no memberships in it, and a member was then routed
  // as a stranger to their own community.
  // ==========================================================================
  group('membership survives a football failure', () {
    testWidgets('a member is still a member when Latest Results fails',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        communities: [community('c1', 'Muscat United')],
        joined: const ['c1'],
        footballFailure: StateError('football offline'),
        observers: [routes],
      );

      // The section reports its own failure...
      expect(find.textContaining('Could not load recent football'),
          findsOneWidget);

      // ...and the member is still routed to their own community.
      await tester.tap(find.text('View community'));
      await tester.idle();
      expect(routes.lastPushedWidget(tester), isA<CommunityDetailsScreen>(),
          reason: 'a football failure must not demote a member');
    });

    testWidgets('their upcoming match still opens member match details',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        matches: [upcoming('m1', communityId: 'c1')],
        joined: const ['c1'],
        footballFailure: StateError('football offline'),
        observers: [routes],
      );

      await tester.tap(find.text('View match'));
      await tester.idle();
      expect(routes.lastPushedWidget(tester), isA<MatchDetailsScreen>(),
          reason: 'the football read failing says nothing about membership');
    });

    testWidgets('a membership failure is the only thing that falls back',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        communities: [community('c1', 'Muscat United')],
        joined: const ['c1'],
        membershipFailure: StateError('membership offline'),
        results: [completed('p1')],
        observers: [routes],
      );

      // Discover survives it...
      expect(find.text('Communities'), findsWidgets);
      expect(find.text('Latest results'), findsOneWidget);

      // ...and falls back conservatively, sending nobody into a screen that
      // would refuse them.
      await tester.tap(find.text('View community'));
      await tester.idle();
      expect(routes.lastPushedWidget(tester), isA<FootballCommunityScreen>());
    });

    testWidgets('the two reads are issued separately', (tester) async {
      final ports = await pumpDiscover(
        tester,
        signedIn: true,
        joined: const ['c1'],
        footballFailure: StateError('football offline'),
      );

      expect(ports.communities.myCommunitiesCalls, 1,
          reason: 'membership is read once per screen load, and its own read');
      expect(ports.football.completedCalls, 1);
    });
  });

  // --------------------------------------------------------------------------
  group('the read-only football match screen', () {
    late _RouteRecorder routes;

    Future<_FakeFootballAdapter> pumpMatch(
      WidgetTester tester, {
      required CompletedMatch match,
      List<LineupSlot> lineup = const [],
      List<MatchRosterEntry> roster = const [],
      ShareCardRenderer? renderer,
      ShareService? shareService,
    }) async {
      routes = _RouteRecorder();
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final adapter = _FakeFootballAdapter(
        results: [match],
        detail: match,
        lineup: lineup,
        roster: roster,
      );
      await tester.pumpWidget(wrap(FootballMatchScreen(
        matchId: match.matchId,
        repository: FootballRepository(adapter),
        renderer: renderer,
        shareService: shareService,
      ), observers: [routes]));
      await tester.pumpAndSettle();
      return adapter;
    }

    LineupSlot slot(
      FootballParticipant p, {
      FootballTeam team = FootballTeam.a,
      int goals = 0,
      bool isMvp = false,
      String? position = 'MID',
    }) =>
        LineupSlot(
          matchId: 'p1',
          participant: p,
          team: team,
          assignedPosition: position,
          goals: goals,
          isMvp: isMvp,
          isOutOfPosition: false,
        );

    testWidgets('shows the score', (tester) async {
      await pumpMatch(tester, match: completed('p1', a: 4, b: 1));
      expect(find.textContaining('4'), findsWidgets);
      expect(find.textContaining('1'), findsWidgets);
    });

    testWidgets('says the result is pending when it is', (tester) async {
      await pumpMatch(tester, match: completed('p1', hasResult: false));
      expect(find.text('Result pending'), findsWidgets);
    });

    testWidgets('shows the MVP when one was named', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', mvp: player('u1', 'Salim Al Harthy')),
      );
      expect(find.text('MVP'), findsWidgets);
      expect(find.text('Salim Al Harthy'), findsWidgets);
    });

    testWidgets('reconstructs both sides of the saved lineup', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: [
          slot(player('u1', 'Player A')),
          slot(player('u2', 'Player B'), team: FootballTeam.b),
        ],
      );

      expect(find.byType(MatchStageSection), findsNWidgets(2),
          reason: 'one section per side');
      expect(find.text('Player A'), findsOneWidget);
      expect(find.text('Player B'), findsOneWidget);
    });

    testWidgets('shows goals from the slot, and nothing for a scorer of none',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: [
          slot(player('u1', 'Scorer'), goals: 2),
          slot(player('u2', 'Nobody'), goals: 0, team: FootballTeam.b),
        ],
      );

      // The mark is the pitch's, on the player, exactly as the Teams screen
      // draws it — not a line of prose beside a name.
      expect(find.byKey(PitchView.goalKey('u1')), findsOneWidget);
      expect(find.byKey(PitchView.goalKey('u2')), findsNothing,
          reason: 'zero goals is drawn as nothing, not asserted as a fact');
    });

    testWidgets('falls back to the roster when no lineup was saved',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: const [],
        roster: [
          MatchRosterEntry(
            matchId: 'p1',
            participant: player('u1', 'Registered Player'),
            status: ParticipationStatus.confirmed,
            rosterPosition: 1,
          ),
        ],
      );

      expect(find.text('Who played'), findsOneWidget);
      expect(find.text('Registered Player'), findsOneWidget);
      expect(find.byType(MatchStageSection), findsNothing,
          reason: 'an empty pitch would report a saved lineup that is not there');
      expect(find.byType(MatchStageBoard), findsNothing);
      expect(find.byType(PitchView), findsNothing);
      expect(find.textContaining('No lineup was saved'), findsOneWidget,
          reason: 'the reader is told why, rather than shown two empty sides');
    });

    testWidgets('a professional guest is drawn and opens nothing',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: [slot(guest, position: null)],
      );

      expect(find.text('Guest Striker'), findsOneWidget);

      await tester.tap(find.text('Guest Striker'));
      await tester.idle();

      expect(routes.pushes, isEmpty,
          reason: 'a guest has no account and therefore no profile');
    });

    testWidgets('a registered player opens their football profile',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: [slot(player('u1', 'Salim Al Harthy'))],
      );

      await tester.tap(find.text('Salim Al Harthy'));
      await tester.idle();

      expect(routes.lastPushedWidget(tester), isA<ProfileScreen>());
    });

    // Viewing football must not be a way to acquire a capability that
    // membership grants. The screen holds no write path at all.
    testWidgets('offers no management action whatsoever', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1'),
        lineup: [slot(player('u1', 'Player A'))],
      );

      for (final label in const [
        'Register',
        'Join match',
        'Generate teams',
        'Save',
        'Record result',
        'Edit',
        'Delete',
        'Manage',
        'Withdraw',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    // ------------------------------------------------------------------------
    // The unification. A completed match opened from Latest Results is the same
    // drawing the Teams screen makes once a result exists — not a second
    // football-results page that happens to share a header.
    // ------------------------------------------------------------------------

    /// Seven on one side, in the shape the approved pitch draws exactly.
    List<LineupSlot> approvedSeven() => [
          slot(player('gk', 'Keeper', position: 'GK'), position: 'GK'),
          slot(player('d1', 'Back One', position: 'DEF'), position: 'DEF'),
          slot(player('d2', 'Back Two', position: 'DEF'), position: 'DEF'),
          slot(player('m1', 'Middle One'), position: 'MID'),
          slot(player('m2', 'Middle Two'), position: 'MID'),
          slot(player('m3', 'Middle Three'), position: 'MID'),
          slot(player('f1', 'Front One', position: 'FWD'), position: 'FWD'),
        ];

    testWidgets('draws the match on the pitch, not as two lists of names',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [
          slot(player('u1', 'Player A')),
          slot(player('u2', 'Player B'), team: FootballTeam.b),
        ],
      );

      // The shared presentation, and both of its sides.
      expect(find.byType(MatchStageBoard), findsOneWidget,
          reason: 'the drawing is the one the Teams screen makes');
      expect(find.byKey(const ValueKey('team-a-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-b-section')), findsOneWidget);

      // Placement goes through PitchView, which is what makes a player stand
      // where they played rather than sit in a row.
      expect(find.byType(PitchView), findsNWidgets(2));
      expect(find.byKey(const ValueKey('team-a-pitch')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-b-pitch')), findsOneWidget);
      expect(find.byKey(PitchView.avatarKey('u1')), findsOneWidget);
      expect(find.byKey(PitchView.avatarKey('u2')), findsOneWidget);
    });

    testWidgets('stands every player where they were assigned', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 2, b: 0),
        lineup: approvedSeven(),
      );

      for (final id in const ['gk', 'd1', 'd2', 'm1', 'm2', 'm3', 'f1']) {
        expect(find.byKey(PitchView.avatarKey(id)), findsOneWidget, reason: id);
      }

      // The assigned position is what decides where a card goes: the keeper,
      // the defence and the attack are three distinct lines, not one list in
      // the order the rows arrived.
      final keeper = tester.getCenter(find.byKey(PitchView.avatarKey('gk'))).dy;
      final back = tester.getCenter(find.byKey(PitchView.avatarKey('d1'))).dy;
      final front = tester.getCenter(find.byKey(PitchView.avatarKey('f1'))).dy;
      expect(keeper, isNot(closeTo(back, 1)));
      expect(back, isNot(closeTo(front, 1)));
      expect(keeper, isNot(closeTo(front, 1)));
    });

    testWidgets('carries the goals, the MVP and the winning side',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [
          slot(player('u1', 'Scorer'), goals: 2),
          slot(player('u2', 'Best'), isMvp: true),
          slot(player('u3', 'Loser'), team: FootballTeam.b),
        ],
      );

      // On the players, exactly as the Teams screen marks them.
      expect(find.byKey(PitchView.goalKey('u1')), findsOneWidget);
      expect(find.byKey(PitchView.mvpKey('u2')), findsOneWidget);
      expect(find.byKey(PitchView.mvpKey('u1')), findsNothing);

      // And the result decoration: the score strip, and the trophy on the side
      // that won it.
      expect(find.byKey(const ValueKey('result-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('winner-trophy')), findsOneWidget,
          reason: 'one side won, so exactly one side is marked');
    });

    testWidgets('a drawn match marks neither side', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 2, b: 2),
        lineup: [slot(player('u1', 'Player A'))],
      );

      expect(find.byKey(const ValueKey('result-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('winner-trophy')), findsNothing);
    });

    // The whole point of sharing the drawing rather than the screen: none of
    // the Teams screen's capabilities came with it. This holds for every
    // reader, an owner of this community included, because the route offers
    // the same nothing to all of them.
    testWidgets('reaches no Teams management action from this route',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: approvedSeven(),
      );

      for (final label in const [
        'Generate teams',
        'Regenerate teams',
        'Add a player who played',
        'Add professional guest',
        'Add a professional guest',
        'Move to the other team',
        'Swap with a player',
        'Change position',
        'Assigned position',
        'Remove',
        'Record result',
        'Save',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('tapping a player opens their profile and no override sheet',
        (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: approvedSeven(),
      );

      await tester.tap(find.byKey(PitchView.avatarKey('m1')));
      await tester.pumpAndSettle();

      expect(routes.lastPushedWidget(tester), isA<ProfileScreen>());
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'the manual-override sheet belongs to the Teams screen');
      expect(find.text('Move to the other team'), findsNothing);
    });

    testWidgets('a guest on the pitch still opens nothing', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [slot(guest, position: null), slot(player('u1', 'Player A'))],
      );

      await tester.tap(find.byKey(PitchView.avatarKey('g1')));
      await tester.pumpAndSettle();

      expect(routes.pushes, isEmpty,
          reason: 'a guest has no account and therefore no profile');
    });

    // ------------------------------------------------------------------------
    // Share, approved for anybody who can open the match.
    // ------------------------------------------------------------------------

    testWidgets('offers Share on a completed match', (tester) async {
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [slot(player('u1', 'Player A'))],
      );

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('shareCompletedMatchButton')),
      );
      expect(button.onPressed, isNotNull,
          reason: 'this route is open to any signed-in reader, member or not');
    });

    testWidgets('sends the existing match result card', (tester) async {
      final renderer = _Renderer();
      await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [
          slot(player('u1', 'Scorer'), goals: 2),
          slot(player('u2', 'Best'), isMvp: true),
          slot(player('u3', 'Loser'), team: FootballTeam.b),
        ],
        renderer: renderer,
        shareService: _Share(),
      );

      await tester.tap(find.byKey(const ValueKey('shareCompletedMatchButton')));
      await tester.pumpAndSettle();

      // The product's one match picture, not a public variant of it.
      expect(renderer.templates, hasLength(1));
      expect(renderer.lastBuilt, isA<MatchResultCard>());

      final data = (renderer.lastBuilt! as MatchResultCard).data;
      expect(data.hasResult, isTrue);
      expect(data.winner, TeamId.a);
      expect(data.goalsOf('u1'), 2);
      expect(data.isMvp('u2'), isTrue);
      expect(data.of(TeamId.a), hasLength(2));
      expect(data.of(TeamId.b), hasLength(1));
      expect(data.names['u1'], 'Scorer');
      expect(data.communityName, 'Muscat United');
      expect(data.playedAt, isNotNull);
    });

    testWidgets('sharing what is on screen reads nothing', (tester) async {
      final adapter = await pumpMatch(
        tester,
        match: completed('p1', a: 3, b: 1),
        lineup: [slot(player('u1', 'Player A'))],
        renderer: _Renderer(),
        shareService: _Share(),
      );

      final before = adapter.matchDetailReads;
      await tester.tap(find.byKey(const ValueKey('shareCompletedMatchButton')));
      await tester.pumpAndSettle();

      expect(adapter.matchDetailReads, before,
          reason: 'every value was resolved when the match loaded');
    });

    testWidgets('a match with no lineup has nothing to send', (tester) async {
      await pumpMatch(tester, match: completed('p1'), lineup: const []);

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('shareCompletedMatchButton')),
      );
      expect(button.onPressed, isNull);
    });
  });

  // --------------------------------------------------------------------------
  group('the football community screen', () {
    Future<void> pumpCommunity(
      WidgetTester tester, {
      List<CompletedMatch> results = const [],
      List<CommunityPlayerStats> players = const [],
      CommunityFootballStats? stats,
      Object? footballFailure,
      JoinCommunityOutcome joinOutcome = const NeedsJoinCode(),
      List<NavigatorObserver> observers = const [],
    }) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(FootballCommunityScreen(
        communityId: 'c1',
        discoverRepository: DiscoverRepository(_FakeDiscoverAdapter(
          communities: [community('c1', 'Muscat United')],
          matches: [upcoming('m1')],
        )),
        footballRepository: FootballRepository(_FakeFootballAdapter(
          results: results,
          players: players,
          stats: stats,
          failure: footballFailure,
        )),
        communityRepository:
            CommunityRepository(_JoinedAdapter(const [], join: joinOutcome)),
      ), observers: observers));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the community football record', (tester) async {
      await pumpCommunity(
        tester,
        stats: const CommunityFootballStats(
          communityId: 'c1',
          communityName: 'Muscat United',
          completedMatches: 14,
          players: 33,
          goals: 91,
          mvpCount: 4,
        ),
      );

      expect(find.text('Football record'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('33'), findsOneWidget);
      expect(find.text('91'), findsOneWidget);
    });

    testWidgets('shows recent results with the same card as Discover',
        (tester) async {
      await pumpCommunity(tester, results: [completed('p1', a: 3, b: 2)]);

      expect(find.text('Recent results'), findsOneWidget);
      expect(find.text('3 - 2'), findsOneWidget);
    });

    testWidgets('never reveals a join code', (tester) async {
      await pumpCommunity(tester);
      expect(find.textContaining('Join code'), findsNothing);
      expect(find.byKey(const Key('footballCommunityJoin')), findsOneWidget,
          reason: 'joining still goes through the existing flow');
    });

    // The upcoming-match action used to push `MatchDetailsScreen`, which is
    // membership-gated and would have refused this very reader. The useful
    // offer is the one thing that changes the answer.
    testWidgets('an upcoming match offers the way in, not a refused screen',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpCommunity(tester, observers: [routes]);

      // Two of them: the hero's, and the upcoming-match card's. The card's
      // action used to read "View match" and push a screen that would refuse
      // this reader.
      expect(find.text('Join'), findsNWidgets(2));
      expect(find.text('View match'), findsNothing);

      await tester.tap(find.text('Join').last);
      await tester.idle();

      expect(routes.lastPushedWidget(tester), isNot(isA<MatchDetailsScreen>()),
          reason: 'a read-only screen must not lead into a membership wall');
    });

    testWidgets('a successful join replaces this screen with the member one',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpCommunity(
        tester,
        joinOutcome: const JoinedCommunity('c1'),
        observers: [routes],
      );

      await tester.tap(find.byKey(const Key('footballCommunityJoin')));
      await tester.pumpAndSettle();

      expect(routes.replacedWith(tester), isA<CommunityDetailsScreen>(),
          reason: 'the reader is a member now; this screen describes a state '
              'that has ended, and Back must not return to it');
    });

    testWidgets('a refused join leaves the read-only screen in place',
        (tester) async {
      final routes = _RouteRecorder();
      await pumpCommunity(
        tester,
        joinOutcome: const NeedsJoinCode(),
        observers: [routes],
      );

      await tester.tap(find.byKey(const Key('footballCommunityJoin')));
      await tester.pumpAndSettle();

      expect(routes.replacements, isEmpty);
      expect(find.byType(FootballCommunityScreen), findsOneWidget);
    });

    testWidgets('a football failure leaves the public half standing',
        (tester) async {
      await pumpCommunity(tester, footballFailure: StateError('offline'));

      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('Upcoming matches'), findsWidgets);
      expect(find.textContaining('Could not load recent football'),
          findsOneWidget);
    });
  });

  // --------------------------------------------------------------------------
  group('the Top Players rule', () {
    CommunityPlayerStats p(
      String name, {
      double rating = 6.0,
      int goals = 0,
      int mvp = 0,
    }) =>
        CommunityPlayerStats(
          communityId: 'c1',
          userId: 'u-$name',
          displayName: name,
          overallRating: rating,
          matchesPlayed: 10,
          wins: 5,
          draws: 2,
          losses: 3,
          goals: goals,
          mvpCount: mvp,
        );

    test('rating descending leads', () {
      final ranked = rankTopPlayers([p('low', rating: 5.0), p('high', rating: 7.0)]);
      expect(ranked.map((e) => e.displayName), ['high', 'low']);
    });

    test('goals break a rating tie', () {
      final ranked = rankTopPlayers([
        p('few', rating: 6.0, goals: 1),
        p('many', rating: 6.0, goals: 9),
      ]);
      expect(ranked.map((e) => e.displayName), ['many', 'few']);
    });

    test('MVPs break a rating and goals tie', () {
      final ranked = rankTopPlayers([
        p('none', rating: 6.0, goals: 3, mvp: 0),
        p('some', rating: 6.0, goals: 3, mvp: 2),
      ]);
      expect(ranked.map((e) => e.displayName), ['some', 'none']);
    });

    test('the name is the deterministic last resort', () {
      final ranked = rankTopPlayers([
        p('Zaid', rating: 6.0, goals: 3, mvp: 1),
        p('Ahmed', rating: 6.0, goals: 3, mvp: 1),
      ]);
      expect(ranked.map((e) => e.displayName), ['Ahmed', 'Zaid'],
          reason: 'a ranking that is not stable is not a ranking');
    });

    test('takes five', () {
      final ranked = rankTopPlayers([
        for (var i = 0; i < 9; i++) p('p$i', rating: 9.0 - i),
      ]);
      expect(ranked, hasLength(5));
      expect(ranked.first.displayName, 'p0');
    });
  });
  // --- how many results are shown before the reader asks for more -----------

  group('previous results are behind a disclosure', () {
    Finder toggle() => find.byKey(const Key('discoverPreviousResultsToggle'));

    /// The refresh the screen already offers, driven through its own
    /// `RefreshIndicator` — the same `onRefresh` a pull down runs.
    ///
    /// Pumped in bounded steps rather than settled: the indicator's own
    /// animation and the feed's `AnimatedSwitcher` keep a frame scheduled, so
    /// `pumpAndSettle` never returns here.
    Future<void> pullToRefresh(WidgetTester tester) async {
      final indicator = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator).first,
      );
      unawaited(indicator.show());
      // Enough frames for the read to resolve, the switcher's 180ms crossfade
      // to finish and the indicator to retract.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    List<CompletedMatch> feed(int count) => [
          for (var i = 1; i <= count; i++)
            completed('p$i',
                title: 'Result $i',
                start: DateTime(2026, 8, 30 - i)),
        ];

    testWidgets('nothing played yet keeps the empty state and offers no control',
        (tester) async {
      await pumpDiscover(tester, signedIn: true, results: const []);

      expect(find.text('No results yet. Once a match is played it shows up '
          'here.'), findsOneWidget);
      expect(toggle(), findsNothing);
    });

    testWidgets('a single result shows alone, with no control', (tester) async {
      // A disclosure that reveals nothing is noise.
      await pumpDiscover(tester, signedIn: true, results: feed(1));

      expect(find.text('Result 1'), findsOneWidget);
      expect(toggle(), findsNothing);
    });

    testWidgets('two results show the newest and offer the other',
        (tester) async {
      await pumpDiscover(tester, signedIn: true, results: feed(2));

      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 2'), findsNothing);
      expect(find.text('Show previous results (1)'), findsOneWidget);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.text('Result 2'), findsOneWidget);
      expect(find.text('Hide previous results'), findsOneWidget);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.text('Result 2'), findsNothing);
      expect(find.text('Show previous results (1)'), findsOneWidget);
    });

    testWidgets('five results count the four behind the newest',
        (tester) async {
      await pumpDiscover(tester, signedIn: true, results: feed(5));

      expect(find.text('Result 1'), findsOneWidget);
      for (final hidden in ['Result 2', 'Result 3', 'Result 4', 'Result 5']) {
        expect(find.text(hidden), findsNothing);
      }
      expect(find.text('Show previous results (4)'), findsOneWidget);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      for (final shown in [
        'Result 1',
        'Result 2',
        'Result 3',
        'Result 4',
        'Result 5',
      ]) {
        expect(find.text(shown), findsOneWidget);
      }

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 5'), findsNothing);
    });

    testWidgets('expanding asks the repository for nothing', (tester) async {
      // The whole list is already in memory, fetched by the read that built
      // this section. Opening it is presentation, not a request.
      final ports =
          await pumpDiscover(tester, signedIn: true, results: feed(5));
      final callsAfterLoad = ports.football.completedCalls;
      expect(callsAfterLoad, 1);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(ports.football.completedCalls, callsAfterLoad,
          reason: 'no reload, no refetch, no repository call at all');
    });

    testWidgets('a refreshed feed leaves the list collapsed and honest',
        (tester) async {
      // The refresh keeps five results and keeps the newest one, and replaces
      // one of the *hidden* ones — the case a length-and-newest comparison
      // cannot see.
      //
      // Note what this does and does not prove. On this screen the expansion is
      // reset twice over: `_ResultsList.didUpdateWidget` compares the ordered
      // ids, and the screen's own `AnimatedSwitcher` keys on load state, so a
      // refresh passes through `loading` and disposes the subtree before that
      // comparison is ever consulted. What is pinned here is the behaviour the
      // reader gets. See the note on `_feedChanged` for the comparison itself.
      final ports = await pumpDiscover(
        tester,
        signedIn: true,
        results: feed(5),
      );

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.text('Result 2'), findsOneWidget);
      expect(find.text('Hide previous results'), findsOneWidget);

      // Same length, same newest match, one hidden result replaced.
      ports.football.results = [
        completed('p1', title: 'Result 1', start: DateTime(2026, 8, 29)),
        completed('p8', title: 'Result 8', start: DateTime(2026, 8, 24)),
        completed('p3', title: 'Result 3', start: DateTime(2026, 8, 27)),
        completed('p4', title: 'Result 4', start: DateTime(2026, 8, 26)),
        completed('p5', title: 'Result 5', start: DateTime(2026, 8, 25)),
      ];

      await pullToRefresh(tester);

      // Collapsed again, and honest about what is behind the control.
      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 8'), findsNothing);
      expect(find.text('Result 2'), findsNothing);
      expect(find.text('Show previous results (4)'), findsOneWidget);
      expect(find.text('Hide previous results'), findsNothing);
    });

    testWidgets('a refresh is one read, and toggling is still none',
        (tester) async {
      final ports =
          await pumpDiscover(tester, signedIn: true, results: feed(5));
      expect(ports.football.completedCalls, 1);
      expect(ports.football.lastLimit, 5);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(ports.football.completedCalls, 1,
          reason: 'opening the list asks for nothing');

      await pullToRefresh(tester);

      expect(ports.football.completedCalls, 2,
          reason: 'the refresh is the only new read');
      expect(ports.football.lastLimit, 5, reason: 'and still capped at five');

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(ports.football.completedCalls, 2);
    });

    testWidgets('the read is still capped at five', (tester) async {
      final ports =
          await pumpDiscover(tester, signedIn: true, results: feed(5));

      expect(ports.football.lastLimit, 5,
          reason: 'Cycle B2 changed presentation, not the read');
    });

    testWidgets('the newest result still opens from its card', (tester) async {
      final observer = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        results: feed(3),
        joined: const ['c1'],
        observers: [observer],
      );
      observer.pushes.clear();

      await tester.tap(find.text('Result 1'));
      await tester.pumpAndSettle();

      expect(observer.pushes, isNotEmpty,
          reason: 'the card still navigates');
    });

    testWidgets('a revealed result opens from its card too', (tester) async {
      final observer = _RouteRecorder();
      await pumpDiscover(
        tester,
        signedIn: true,
        results: feed(3),
        joined: const ['c1'],
        observers: [observer],
      );

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      observer.pushes.clear();

      await tester.tap(find.text('Result 3'));
      await tester.pumpAndSettle();

      expect(observer.pushes, isNotEmpty);
    });

    testWidgets('a failed read is unchanged and offers no control',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        footballFailure: StateError('offline'),
      );

      expect(find.text('Could not load recent football.'), findsOneWidget);
      expect(toggle(), findsNothing);
    });
  });

}

// ---------------------------------------------------------------------------
// Fake ports
// ---------------------------------------------------------------------------

class _FakeFootballAdapter implements FootballAdapter {
  _FakeFootballAdapter({
    this.results = const [],
    this.players = const [],
    this.lineup = const [],
    this.roster = const [],
    this.stats,
    this.detail,
    this.failure,
  });

  /// Not final: a refresh can legitimately answer a different feed, and the
  /// collapse rule is about exactly that.
  List<CompletedMatch> results;
  final List<CommunityPlayerStats> players;
  final List<LineupSlot> lineup;
  final List<MatchRosterEntry> roster;
  final CommunityFootballStats? stats;
  final CompletedMatch? detail;
  final Object? failure;

  var completedCalls = 0;

  /// Reads that opening one completed match costs. Counted so a test can show
  /// that sharing what is already on screen costs none.
  var matchDetailReads = 0;

  /// The cap the screen asked for, so a test can show the read is unchanged.
  int? lastLimit;

  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) async {
    completedCalls++;
    lastLimit = limit;
    if (failure != null) throw failure!;
    return results;
  }

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) async {
    matchDetailReads++;
    if (failure != null) throw failure!;
    return detail ?? results.first;
  }

  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) async {
    matchDetailReads++;
    if (failure != null) throw failure!;
    return roster;
  }

  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) async {
    matchDetailReads++;
    if (failure != null) throw failure!;
    return lineup;
  }

  @override
  Future<CommunityFootballStats> fetchCommunityStats(String communityId) async {
    if (failure != null) throw failure!;
    return stats ??
        const CommunityFootballStats(
          communityId: 'c1',
          communityName: 'Muscat United',
          completedMatches: 0,
          players: 0,
          goals: 0,
          mvpCount: 0,
        );
  }

  @override
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
    String communityId,
  ) async {
    if (failure != null) throw failure!;
    return players;
  }
}

class _JoinedAdapter implements CommunityAdapter {
  _JoinedAdapter(this.joinedIds, {this.failure, this.join});

  final List<String> joinedIds;
  final Object? failure;

  /// What `joinCommunity` resolves to. `JoinedCommunity` is the success path the
  /// replacement navigation hangs off; anything else leaves the reader put.
  final JoinCommunityOutcome? join;

  var myCommunitiesCalls = 0;

  @override
  Future<List<Community>> fetchMyCommunities() async {
    myCommunitiesCalls++;
    if (failure != null) throw failure!;
    return [
      for (final id in joinedIds)
        Community(
          id: id,
          ownerId: 'owner',
          name: 'Joined $id',
          joinPolicy: JoinPolicy.open,
        ),
    ];
  }

  @override
  Future<String> joinCommunity(String communityId) async {
    if (join is JoinedCommunity) return communityId;
    // The repository turns this into `NeedsJoinCode`, which is the refusal the
    // shared flow words for itself.
    throw const ValidationFailure(FailureReason.joinCodeRequired);
  }

  @override
  Future<List<Community>> fetchAllCommunities() => throw UnimplementedError();
  @override
  Future<Community> fetchCommunity(String communityId) =>
      throw UnimplementedError();
  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) =>
      throw UnimplementedError();
  @override
  Future<String> joinCommunityByCode(String code) => throw UnimplementedError();
  @override
  Future<void> setJoinPolicy(String communityId,
          {required JoinPolicy joinPolicy}) =>
      throw UnimplementedError();
  @override
  Future<String> fetchJoinCode(String communityId) =>
      throw UnimplementedError();
  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      throw UnimplementedError();
  @override
  Future<String> regenerateJoinCode(String communityId) =>
      throw UnimplementedError();
  @override
  Future<void> deleteCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) =>
      throw UnimplementedError();
}

class _FakeDiscoverAdapter implements DiscoverAdapter {
  _FakeDiscoverAdapter({
    this.communities = const [],
    this.matches = const [],
    this.failure,
  });

  final List<PublicCommunity> communities;
  final List<PublicMatch> matches;
  final Object? failure;

  @override
  Future<List<PublicCommunity>> fetchCommunities() async {
    if (failure != null) throw failure!;
    return communities;
  }

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async {
    if (failure != null) throw failure!;
    return communities.firstWhere((c) => c.id == communityId,
        orElse: () => communities.first);
  }

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async {
    if (failure != null) throw failure!;
    return matches;
  }
}

class _StubAuth implements AuthAdapter {
  _StubAuth({required this.signedIn});

  final bool signedIn;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentUserId => signedIn ? 'u1' : null;

  @override
  String? get currentUserEmail => null;

  @override
  Stream<bool> get signedInChanges => const Stream<bool>.empty();

  @override
  Future<String?> fetchCurrentUserFullName() async => null;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) async =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async => throw UnimplementedError();
}

/// Records pushed routes so navigation can be asserted without building the
/// destination.
///
/// `MaterialPageRoute.builder` returns the widget instance; it does not mount
/// it, so no `State` is created and no repository is constructed. That is the
/// whole point here -- the destinations of this cycle's navigation all build
/// their own production repositories, which reach a Supabase client that a
/// widget test has not initialised.
class _RouteRecorder extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];
  final replacements = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The initial route is not a navigation any test made.
    if (route.settings.name != '/') pushes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) replacements.add(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  /// The widget a `pushReplacement` put in place, without mounting it.
  Widget? replacedWith(WidgetTester tester) {
    if (replacements.isEmpty) return null;
    final route = replacements.last;
    if (route is! MaterialPageRoute) return null;
    return route.builder(tester.element(find.byType(Navigator).first));
  }

  Widget? lastPushedWidget(WidgetTester tester) {
    if (pushes.isEmpty) return null;
    final route = pushes.last;
    if (route is! MaterialPageRoute) return null;
    return route.builder(tester.element(find.byType(Navigator).first));
  }
}

/// Captures which template the screen handed the engine, which is the whole of
/// what "the same card, from either screen" means.
class _Renderer implements ShareCardRenderer {
  final List<ShareCardTemplate> templates = [];
  Widget? lastBuilt;

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    templates.add(template);
    lastBuilt = template(_StubContext());
    return ShareCardImage(bytes: _png, pixelWidth: 1080, pixelHeight: 1920);
  }
}

/// The template is a function of a context it does not read until it builds, so
/// calling it with a stub is enough to learn which widget it makes.
class _StubContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Share implements ShareService {
  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async =>
      ShareOutcome.shared;
}

/// A one-pixel PNG. The preview screen decodes whatever it is handed, so the
/// bytes have to be a real picture even though nothing here looks at it.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
]);
