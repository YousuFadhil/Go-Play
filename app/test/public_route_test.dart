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
  _FakeDiscoverAdapter({this.match, this.failure});

  final PublicMatch? match;
  final Failure? failure;

  @override
  Future<PublicMatch?> fetchMatch(String matchId) async {
    if (failure != null) throw failure!;
    return match;
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
