import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/arrange_roster_screen.dart';
import 'package:go_play/features/matches/manage_roster_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/community_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';

/// Player identity: a face, a name, and a way into the Player Profile.
///
/// The approved rule is one sentence — a registered Community Player is drawn
/// with their avatar and opens their profile; a Professional Guest is drawn as
/// one and opens nothing — and this file is where it is held to.
///
/// **What is deliberately not tested here.** Whether a viewer may *read* a
/// profile is `player_profile` (migration `0043`) deciding against their own
/// session, and `ProfileScreen` wording the refusal. Nothing in this feature
/// asks that question or could answer it differently: a name being tappable is
/// an offer to ask the server, not a claim about what it will say. The rules
/// themselves are covered by `test/integration/profile_visibility_test.dart`.
void main() {
  Widget host(Widget child, {NavigatorObserver? observer}) => MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observer == null ? const [] : [observer],
        home: Scaffold(body: child),
      );

  CircleAvatar avatarOf(WidgetTester tester) =>
      tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);

  // --- 1. the face -------------------------------------------------------------

  group('1. a community player is drawn with their picture', () {
    testWidgets('the stored picture is used when there is one', (tester) async {
      await tester.pumpWidget(host(const PlayerAvatar(
        avatarUrl: 'https://example.test/u1/avatar.jpg',
        fullName: 'Yousuf Al Amri',
      )));

      final avatar = avatarOf(tester);
      expect(avatar.foregroundImage, isA<NetworkImage>());
      expect(
        (avatar.foregroundImage! as NetworkImage).url,
        'https://example.test/u1/avatar.jpg',
      );
    });

    testWidgets('a player with no picture falls back to their initials',
        (tester) async {
      await tester.pumpWidget(host(const PlayerAvatar(
        fullName: 'Yousuf Al Amri',
      )));

      expect(avatarOf(tester).foregroundImage, isNull,
          reason: 'there is no picture to fetch, so nothing is fetched');
      // The app's existing fallback, not a new visual language: initials are
      // what an account without a picture has always looked like.
      expect(find.text('YA'), findsOneWidget);
    });

    testWidgets('a player with no name at all falls back to the person icon',
        (tester) async {
      await tester.pumpWidget(host(const PlayerAvatar()));
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('2. a Professional Guest is drawn as one', () {
    testWidgets('the guest treatment, and never a picture', (tester) async {
      await tester.pumpWidget(host(const PlayerAvatar(
        isProfessionalGuest: true,
        // Supplied on purpose. A guest holds no account, so even a URL handed
        // to one must not become a face: it would be somebody else's.
        avatarUrl: 'https://example.test/u1/avatar.jpg',
        fullName: 'Ahmed',
      )));

      expect(avatarOf(tester).foregroundImage, isNull);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsOneWidget);
      expect(find.text('A'), findsNothing,
          reason: 'a guest is marked as a guest, not lettered like a profile');
    });

    testWidgets('the guest disc is not the player disc', (tester) async {
      await tester.pumpWidget(host(const Row(children: [
        PlayerAvatar(fullName: 'Yousuf', key: Key('player')),
        PlayerAvatar(isProfessionalGuest: true, key: Key('guest')),
      ])));

      final scheme = Theme.of(tester.element(find.byType(Row))).colorScheme;
      final guest = tester.widget<CircleAvatar>(find.descendant(
        of: find.byKey(const Key('guest')),
        matching: find.byType(CircleAvatar),
      ));
      expect(guest.backgroundColor, scheme.tertiaryContainer);
    });
  });

  // --- 3. the way in -------------------------------------------------------------

  group('3. an identity opens the Player Profile', () {
    testWidgets('and it is the existing one, told whose record to read',
        (tester) async {
      final observer = _RouteRecorder();
      await tester.pumpWidget(host(
        const PlayerIdentityTap(userId: 'user-7', child: Text('Yousuf')),
        observer: observer,
      ));
      observer.ignoreInitialRoute();

      // Not pumped afterwards on purpose: the assertion is about the route that
      // was pushed, and building it would construct the production
      // repositories `ProfileScreen` makes when nobody injects any.
      await tester.tap(find.text('Yousuf'));

      final route = observer.pushed.single;
      final screen = route.builder(tester.element(find.byType(Scaffold)));
      expect(screen, isA<ProfileScreen>());
      expect((screen as ProfileScreen).userId, 'user-7',
          reason: 'one Player Profile, told whose record to read — never a '
              'second implementation of it');
      observer.discard();
    });

    testWidgets('a Professional Guest has nothing to open', (tester) async {
      final observer = _RouteRecorder();
      await tester.pumpWidget(host(
        const PlayerIdentityTap(userId: null, child: Text('Ahmed')),
        observer: observer,
      ));
      observer.ignoreInitialRoute();

      await tester.tap(find.text('Ahmed'));
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty);
      expect(find.byType(InkWell), findsNothing,
          reason: 'no affordance, because there is nothing behind it');
    });

    testWidgets('a busy screen does not open one out from under a write',
        (tester) async {
      final observer = _RouteRecorder();
      await tester.pumpWidget(host(
        const PlayerIdentityTap(
          userId: 'user-7',
          enabled: false,
          child: Text('Yousuf'),
        ),
        observer: observer,
      ));
      observer.ignoreInitialRoute();

      await tester.tap(find.text('Yousuf'));
      await tester.pumpAndSettle();
      expect(observer.pushed, isEmpty);
    });
  });

  // --- 4. the data behind the face --------------------------------------------------

  group('4. the picture reaches the model', () {
    test('a roster row carries the player picture the adapter looked up', () {
      final registration = matchRegistrationFromRow(
        const {
          'registration_id': 'reg-1',
          'user_id': 'u1',
          'professional_guest_id': null,
          'participant_type': 'USER',
          'display_name': 'Yousuf',
          'primary_position': 'MID',
          'status': 'confirmed',
          'registration_order': 1,
          'admin_order': null,
          'roster_position': 1,
        },
        avatarUrl: 'https://example.test/u1/avatar.jpg',
      );

      expect(registration.avatarUrl, 'https://example.test/u1/avatar.jpg');
    });

    test('a guest row carries none, whatever is passed', () {
      final guest = matchRegistrationFromRow(
        const {
          'registration_id': 'reg-2',
          'user_id': null,
          'professional_guest_id': 'g1',
          'participant_type': 'PROFESSIONAL',
          'display_name': 'Ahmed',
          'primary_position': null,
          'status': 'reserve',
          'registration_order': 2,
          'admin_order': null,
          'roster_position': 2,
        },
        avatarUrl: 'https://example.test/u1/avatar.jpg',
      );

      expect(guest.avatarUrl, isNull,
          reason: 'a guest has no account, so no picture is theirs');
    });

    test('a member row resolves the stored path through the provided resolver',
        () {
      final member = communityMemberFromRow(
        const {
          'role': 'player',
          'user': {
            'id': 'u1',
            'full_name': 'Yousuf',
            'primary_position': 'MID',
            'avatar_path': 'u1/avatar.jpg',
          },
        },
        avatarUrl: (path) => path == null ? null : 'https://cdn.test/$path',
      );

      expect(member.avatarUrl, 'https://cdn.test/u1/avatar.jpg');
    });

    test('a member with no picture carries none', () {
      final member = communityMemberFromRow(
        const {
          'role': 'player',
          'user': {
            'id': 'u1',
            'full_name': 'Yousuf',
            'primary_position': 'MID',
            'avatar_path': null,
          },
        },
        avatarUrl: (path) => path == null ? null : 'https://cdn.test/$path',
      );

      expect(member.avatarUrl, isNull);
    });
  });

  // --- 5. management rows keep their controls -----------------------------------------

  group('5. the management screens keep what they had', () {
    MatchRegistration player(
      String id, {
      RegistrationStatus status = RegistrationStatus.confirmed,
      String? avatarUrl,
      int order = 1,
    }) =>
        MatchRegistration(
          registrationId: 'reg-$id',
          userId: id,
          fullName: 'Player $id',
          position: 'MID',
          status: status,
          registrationOrder: order,
          avatarUrl: avatarUrl,
        );

    MatchRegistration guest(String id, {int order = 9}) => MatchRegistration(
          registrationId: 'reg-$id',
          professionalGuestId: id,
          fullName: 'Ahmed',
          status: RegistrationStatus.confirmed,
          registrationOrder: order,
        );

    Future<_FakeMatchAdapter> pumpManage(
      WidgetTester tester,
      List<MatchRegistration> roster,
    ) async {
      final adapter = _FakeMatchAdapter(registrations: roster);
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ManageRosterScreen(
          matchId: 'm1',
          communityId: 'c1',
          filter: RegistrationStatus.confirmed,
          title: 'Manage players',
          canRemove: true,
          canManageGuests: true,
          service: MatchService(adapter),
          memberRepository: MemberRepository(_FakeMemberAdapter()),
        ),
      ));
      await tester.pumpAndSettle();
      return adapter;
    }

    testWidgets('Manage Roster: the face is the profile control and the '
        'remove button is still the remove button', (tester) async {
      await pumpManage(tester, [player('u1'), guest('g1')]);

      // The player's identity is a control...
      final identity = find.byKey(const Key('identity_u1'));
      expect(identity, findsOneWidget);
      expect(
        tester.widget<PlayerIdentityTap>(identity).userId,
        'u1',
      );
      // ...and the guest's is not.
      expect(
        tester.widget<PlayerIdentityTap>(find.byKey(const Key('identity_g1')))
            .userId,
        isNull,
      );
      // The row itself never became a navigation target, so the controls that
      // were there are still there.
      expect(find.byIcon(Icons.person_remove), findsNWidgets(2));
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget);
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget);
    });

    testWidgets('Manage Roster: a player picture is drawn where there is one',
        (tester) async {
      await pumpManage(tester, [
        player('u1', avatarUrl: 'https://example.test/u1.jpg'),
        guest('g1'),
      ]);

      final avatars = tester
          .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
          .toList();
      expect(avatars.first.avatarUrl, 'https://example.test/u1.jpg');
      expect(avatars.last.isProfessionalGuest, isTrue);
      expect(avatars.last.avatarUrl, isNull);
    });

    Future<_FakeMatchAdapter> pumpArrange(WidgetTester tester) async {
      final adapter = _FakeMatchAdapter(
        registrations: [
          player('u1', avatarUrl: 'https://example.test/u1.jpg', order: 1),
          player('u2', order: 2),
          player('u3', status: RegistrationStatus.reserve, order: 3),
          guest('g1', order: 4),
        ],
        match: _match,
      );
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ArrangeRosterScreen(matchId: 'm1', service: MatchService(adapter)),
      ));
      await tester.pumpAndSettle();
      return adapter;
    }

    testWidgets('Arrange Participants: reordering by the handle still writes '
        'the whole order', (tester) async {
      final adapter = await pumpArrange(tester);

      await tester.drag(
        find
            .descendant(
              of: find.byKey(const Key('startingList')),
              matching: find.byIcon(Icons.drag_handle),
            )
            .first,
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();

      expect(adapter.orders, hasLength(1),
          reason: 'the drag handle is still a drag handle');
      expect(adapter.orders.single.length, 4);
    });

    testWidgets('Arrange Participants: swapping still works, and the identity '
        'is a separate control', (tester) async {
      final adapter = await pumpArrange(tester);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u1')));
      await tester.pumpAndSettle();

      expect(adapter.swaps, [('reg-u3', 'reg-u1')]);
      // And the identity control exists alongside, for the player and not for
      // the guest.
      expect(
        tester.widget<PlayerIdentityTap>(find.byKey(const Key('identity_u1')))
            .userId,
        'u1',
      );
      expect(
        tester.widget<PlayerIdentityTap>(find.byKey(const Key('identity_g1')))
            .userId,
        isNull,
      );
    });

    testWidgets('Arrange Participants: tapping a face opens that player',
        (tester) async {
      final observer = _RouteRecorder();
      final adapter = _FakeMatchAdapter(
        registrations: [player('u1'), guest('g1')],
        match: _match,
      );
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [observer],
        home: ArrangeRosterScreen(matchId: 'm1', service: MatchService(adapter)),
      ));
      await tester.pumpAndSettle();
      observer.ignoreInitialRoute();

      await tester.tap(find.byKey(const Key('identity_u1')));

      final screen = observer.pushed.single
          .builder(tester.element(find.byType(ArrangeRosterScreen)));
      expect((screen as ProfileScreen).userId, 'u1');
      // The swap selection was not started by the same tap: the identity is a
      // control of its own and the row's gesture is untouched.
      expect(adapter.swaps, isEmpty);
      observer.discard();
    });
  });
}

final _match = Match(
  id: 'm1',
  communityId: 'c1',
  createdBy: 'u0',
  location: 'Pitch',
  startAt: DateTime.now().add(const Duration(days: 3)),
  endAt: DateTime.now().add(const Duration(days: 3, hours: 2)),
  startingPlayers: 2,
  maxRegistration: 8,
  status: MatchStatus.open,
  title: 'Wednesday match',
);

/// Records what was pushed without letting it build.
///
/// A pushed route is inspected rather than mounted: `ProfileScreen` builds the
/// production repositories when nobody injects any, and this suite has no data
/// provider. [discard] takes the pending route back off so the binding never
/// gets a frame in which to build it.
class _RouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  /// Forgets the route `MaterialApp` pushes for its own home, so `pushed` holds
  /// only what the widget under test asked for.
  void ignoreInitialRoute() => pushed.clear();

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}

class _FakeMatchAdapter implements MatchAdapter {
  _FakeMatchAdapter({required this.registrations, Match? match})
      : match = match ?? _match;

  final Match match;
  List<MatchRegistration> registrations;

  final List<List<String>> orders = [];
  final List<(String, String)> swaps = [];

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  Future<void> setRosterOrder(
      String matchId, List<String> registrationIds) async {
    orders.add(registrationIds);
  }

  @override
  Future<void> swapParticipants(String matchId, String a, String b) async {
    swaps.add((a, b));
  }

  @override
  Future<void> removePlayer(String matchId, String userId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeMemberAdapter implements MemberAdapter {
  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
