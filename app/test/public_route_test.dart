import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/states.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/invitations/invite_landing_screen.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/infrastructure/supabase/mappers/discover_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'player_record_fakes.dart';

/// Public links, from the visitor's side.
///
/// Two questions, and they are different ones: **what a guest is shown** when a
/// link opens, and **what a guest is still refused**. A public route that
/// quietly widened access would pass the first and fail the second, so both
/// are asserted for each of the three kinds.
void main() {
  const player = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
  const community = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const match = '11111111-2222-4333-8444-555555555555';

  // The gate renders the real destination screens, and those construct their
  // Supabase adapters as they build. Nothing here makes a request; the client
  // only has to exist for them to be constructed. A harness detail, exactly as
  // in `account_suspension_gate_test.dart`.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  setUp(() {
    PendingPublicLink.instance.clear();
    PendingInvite.instance.code.value = null;
  });
  tearDown(() {
    PendingPublicLink.instance.clear();
    PendingInvite.instance.code.value = null;
  });

  Future<void> pumpGate(WidgetTester tester, {bool signedIn = false}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AuthGate(
        authService: AuthService(_FakeAuthAdapter(signedIn: signedIn)),
      ),
    ));
    await tester.pump();
  }

  group('a visitor opening a public link', () {
    testWidgets('lands on the player, not on Discover', (tester) async {
      PendingPublicLink.instance.offer('/player/$player');
      await pumpGate(tester);

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(DiscoverScreen), findsNothing);

      // And as a visitor, which is what decides that only the public contracts
      // are called. Stated by the gate rather than asked again by the screen.
      final screen = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
      expect(screen.asVisitor, isTrue);
      expect(screen.userId, player);
    });

    testWidgets('lands on the community', (tester) async {
      PendingPublicLink.instance.offer('/community/$community');
      await pumpGate(tester);

      // The existing public community surface, reused rather than duplicated.
      expect(find.byType(PublicCommunityScreen), findsOneWidget);
      expect(
        tester
            .widget<PublicCommunityScreen>(find.byType(PublicCommunityScreen))
            .communityId,
        community,
      );
    });

    testWidgets('lands on the match', (tester) async {
      PendingPublicLink.instance.offer('/match/$match');
      await pumpGate(tester);

      expect(find.byType(PublicMatchScreen), findsOneWidget);
      expect(
        tester
            .widget<PublicMatchScreen>(find.byType(PublicMatchScreen))
            .matchId,
        match,
      );
    });

    testWidgets('with no link, the app still opens on Discover',
        (tester) async {
      await pumpGate(tester);
      expect(find.byType(DiscoverScreen), findsOneWidget);
    });

    testWidgets('an invitation still outranks a public link', (tester) async {
      // Unchanged behaviour: somebody who tapped an invitation asked for that
      // and nothing else.
      PendingPublicLink.instance.offer('/player/$player');
      PendingInvite.instance.offer('4821');
      await pumpGate(tester);

      expect(find.byType(InviteLandingScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
    });

    testWidgets('a signed-in reader is not sent to the public landing',
        (tester) async {
      // Their link is pushed onto their own stack instead, so Back returns
      // them to where they were. The gate renders the signed-in tree.
      PendingPublicLink.instance.offer('/player/$player');
      await pumpGate(tester, signedIn: true);
      await tester.pump();

      expect(find.byType(PublicMatchScreen), findsNothing);
      expect(find.byType(PublicCommunityScreen), findsNothing);
    });
  });

  group('a public match link', () {
    Future<void> pumpMatch(
      WidgetTester tester, {
      required _FakeDiscoverAdapter discover,
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PublicMatchScreen(
          matchId: match,
          repository: DiscoverRepository(discover),
          authService: AuthService(_FakeAuthAdapter()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a publicly visible match', (tester) async {
      await pumpMatch(
        tester,
        discover: _FakeDiscoverAdapter(match: _publicMatch()),
      );

      expect(find.text('Friday football'), findsOneWidget);
      expect(find.text('Al Amerat Pitch'), findsOneWidget);
    });

    testWidgets('a match that is not publicly visible is not shown at all',
        (tester) async {
      // A completed match, a finished one, or one in a deactivated community:
      // the contract answers no rows for all of them, and so does this.
      await pumpMatch(tester, discover: _FakeDiscoverAdapter(match: null));

      expect(find.text('Friday football'), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('no longer available'), findsOneWidget);
    });

    testWidgets('a guessed id is answered the same way as a real one',
        (tester) async {
      // No retry is offered either: the read would fail again for the same
      // reason, and an id that does not resolve must not be distinguishable
      // from one the reader simply may not open.
      await pumpMatch(tester, discover: _FakeDiscoverAdapter(match: null));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('registering still requires an account', (tester) async {
      await pumpMatch(
        tester,
        discover: _FakeDiscoverAdapter(match: _publicMatch()),
      );

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();

      // The same sign-in sheet every other guest action opens. Nothing on a
      // public route registers anybody.
      expect(find.textContaining('account'), findsWidgets);
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('a failed read is a failure, not an empty page',
        (tester) async {
      await pumpMatch(
        tester,
        discover: _FakeDiscoverAdapter(failure: const NetworkFailure()),
      );

      // Different from "not visible" on purpose: this one *can* be retried.
      expect(find.byType(ErrorState), findsOneWidget);
    });
  });

  group('a completed public match, as data', () {
    // The page that draws a played match for a visitor is awaiting an approved
    // mockup, so what is asserted here is the read path it will be handed, not
    // a presentation.

    PublicCompletedMatch played({List<PublicLineupEntry> lineup = const []}) =>
        PublicCompletedMatch(
          id: match,
          communityId: community,
          communityName: 'Al Amerat FC',
          startAt: DateTime(2026, 9, 12, 18),
          endAt: DateTime(2026, 9, 12, 20),
          hasResult: true,
          teamAScore: 3,
          teamBScore: 2,
          mvpDisplayName: 'Noor Al Kindi',
          lineup: lineup,
        );

    test('a completed match comes back with its lineup attached', () async {
      final discover = _FakeDiscoverAdapter(
        completed: played(lineup: const [
          PublicLineupEntry(
            team: 'A',
            displayName: 'Noor Al Kindi',
            isProfessionalGuest: false,
            goals: 2,
            isMvp: true,
            playerId: player,
          ),
        ]),
      );

      final detail = await DiscoverRepository(discover).fetchMatchDetail(match);

      expect(detail, isA<PublicCompletedMatch>());
      final completed = detail! as PublicCompletedMatch;
      expect(completed.teamAScore, 3);
      expect(completed.lineup.single.playerId, player);
      expect(discover.lineupReads, [match]);
    });

    test('an upcoming match never asks for a roster', () async {
      final discover = _FakeDiscoverAdapter(match: _publicMatch());

      final detail = await DiscoverRepository(discover).fetchMatchDetail(match);

      expect(detail, isA<PublicUpcomingMatch>());
      expect(
        discover.lineupReads,
        isEmpty,
        reason: 'an upcoming roster is not public, so it is never requested',
      );
    });

    test('a match that is not public is null, and nothing else is read',
        () async {
      // Inactive or suspended community, or a guessed id: the contract returns
      // no rows for all of them, and the repository asks no follow-up question
      // that could tell them apart.
      final discover = _FakeDiscoverAdapter();

      expect(
        await DiscoverRepository(discover).fetchMatchDetail(match),
        isNull,
      );
      expect(discover.lineupReads, isEmpty);
    });

    test('the provisional page still reads only the upcoming shape', () async {
      // Until the public result page is approved, `fetchMatch` answers null for
      // a played match rather than letting the page improvise a presentation.
      final discover = _FakeDiscoverAdapter(completed: played());
      expect(await DiscoverRepository(discover).fetchMatch(match), isNull);
    });
  });

  group('reading the public match contract', () {
    String? avatar(String? path) => path == null ? null : 'https://img/$path';

    test('an upcoming row maps to the upcoming shape, with no result', () {
      final detail = publicMatchDetailFromRow({
        'match_id': match,
        'community_id': community,
        'community_name': 'Al Amerat FC',
        'community_logo_url': null,
        'title': 'Friday football',
        'location': 'Al Amerat Pitch',
        'start_at': '2026-09-20T15:00:00Z',
        'end_at': '2026-09-20T17:00:00Z',
        'public_state': 'UPCOMING',
        'starting_players': 10,
        'open_slots': 3,
        'has_result': null,
        'team_a_score': null,
        'team_b_score': null,
        'mvp_display_name': null,
        'mvp_avatar_path': null,
      }, avatarUrl: avatar);

      expect(detail, isA<PublicUpcomingMatch>());
      expect((detail! as PublicUpcomingMatch).match.openSlots, 3);
    });

    test('a completed row maps to the completed shape, with no places', () {
      final detail = publicMatchDetailFromRow({
        'match_id': match,
        'community_id': community,
        'community_name': 'Al Amerat FC',
        'community_logo_url': 'https://logo',
        'title': null,
        'location': 'Al Amerat Pitch',
        'start_at': '2026-09-12T15:00:00Z',
        'end_at': '2026-09-12T17:00:00Z',
        'public_state': 'COMPLETED',
        'starting_players': null,
        'open_slots': null,
        'has_result': true,
        'team_a_score': 3,
        'team_b_score': 2,
        'mvp_display_name': 'Noor Al Kindi',
        'mvp_avatar_path': 'u/1.jpg',
      }, avatarUrl: avatar);

      final completed = detail! as PublicCompletedMatch;
      expect(completed.teamAScore, 3);
      expect(completed.mvpAvatarUrl, 'https://img/u/1.jpg');
      expect(completed.communityLogoUrl, 'https://logo');
    });

    test('a played match with no recorded result has no score, not nil-nil',
        () {
      final detail = publicMatchDetailFromRow({
        'match_id': match,
        'community_id': community,
        'community_name': 'Al Amerat FC',
        'start_at': '2026-09-12T15:00:00Z',
        'end_at': '2026-09-12T17:00:00Z',
        'public_state': 'COMPLETED',
        'has_result': false,
      }, avatarUrl: avatar) as PublicCompletedMatch;

      expect(detail.hasResult, isFalse);
      expect(detail.teamAScore, isNull);
      expect(detail.mvpDisplayName, isNull);
    });

    test('a state this build does not know is not a match', () {
      expect(
        publicMatchDetailFromRow(
          {'match_id': match, 'public_state': 'ARCHIVED'},
          avatarUrl: avatar,
        ),
        isNull,
      );
    });

    test('a lineup row carries a player id only when the database gave one',
        () {
      final guest = publicLineupEntryFromRow({
        'team': 'B',
        'assigned_position': 'FWD',
        'participant_type': 'PROFESSIONAL',
        'display_name': 'Guest Striker',
        'avatar_path': null,
        'goals': 1,
        'is_mvp': false,
        'player_id': null,
      }, avatarUrl: avatar);
      expect(guest.isProfessionalGuest, isTrue);
      expect(guest.playerId, isNull);

      // A registered player whose profile is not available arrives the same
      // way: a name, and no id to follow.
      final unavailable = publicLineupEntryFromRow({
        'team': 'A',
        'participant_type': 'USER',
        'display_name': 'Former Player',
        'goals': 0,
        'is_mvp': false,
        'player_id': null,
      }, avatarUrl: avatar);
      expect(unavailable.isProfessionalGuest, isFalse);
      expect(unavailable.playerId, isNull);

      final available = publicLineupEntryFromRow({
        'team': 'A',
        'participant_type': 'USER',
        'display_name': 'Noor Al Kindi',
        'goals': 2,
        'is_mvp': true,
        'player_id': player,
      }, avatarUrl: avatar);
      expect(available.playerId, player);
    });
  });

  group('a visitor cannot reach a profile that is not public', () {
    testWidgets('no public record means no profile, and no detail either',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ProfileScreen(
          userId: player,
          asVisitor: true,
          // Answers null, which is what the database gives for a player who
          // does not exist and for one who is not active alike.
          playerRecordRepository:
              PlayerRecordRepository(FakePlayerRecordAdapter()),
          authService: AuthService(_FakeAuthAdapter()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      // Nothing about the player is on screen, including whether they exist.
      expect(find.text('Noor Al Kindi'), findsNothing);
      expect(find.byTooltip('Share profile'), findsNothing);
    });
  });
}

PublicMatch _publicMatch() => PublicMatch(
      id: '11111111-2222-4333-8444-555555555555',
      communityId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      communityName: 'Al Amerat FC',
      title: 'Friday football',
      location: 'Al Amerat Pitch',
      startAt: DateTime.now().add(const Duration(days: 2)),
      endAt: DateTime.now().add(const Duration(days: 2, hours: 2)),
      startingPlayers: 10,
      openSlots: 3,
    );

class _FakeDiscoverAdapter implements DiscoverAdapter {
  _FakeDiscoverAdapter({this.match, this.completed, this.failure});

  final PublicMatch? match;
  final PublicCompletedMatch? completed;
  final Failure? failure;

  /// Every lineup read, so a test can prove an upcoming match's roster is never
  /// asked for.
  final List<String> lineupReads = [];

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async {
    if (failure != null) throw failure!;
    if (completed != null) return completed;
    final upcoming = match;
    return upcoming == null ? null : PublicUpcomingMatch(match: upcoming);
  }

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async {
    lineupReads.add(matchId);
    return completed?.lineup ?? const [];
  }

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => const [];

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      const [];
}

class _FakeAuthAdapter implements AuthAdapter {
  _FakeAuthAdapter({bool signedIn = false}) : _signedIn = signedIn;

  final bool _signedIn;
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> get signedInChanges => _controller.stream;

  @override
  Future<bool> isCurrentUserActive() async => true;

  @override
  String? get currentUserId => _signedIn ? 'u1' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
