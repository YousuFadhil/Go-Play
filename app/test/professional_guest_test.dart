import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/manage_roster_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_card.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';

/// Professional Guests, from the client's side.
///
/// What is asserted here is the half the app owns: that a guest read from the
/// provider becomes a guest in the domain, that they are named and drawn as one,
/// that only an owner or admin is offered the controls, and that every mutation
/// goes to the port and is followed by a fresh read of the roster.
///
/// **The rules themselves are not tested here and cannot be.** Capacity, the
/// community-first ordering, FIFO promotion, LIFO displacement and the
/// preservation of a played guest's record all live in one SQL transaction that
/// this layer only calls. Those are exercised against the database directly —
/// `test/integration/professional_guest_test.dart`. What this file proves is
/// that the client does not second-guess any of them: the starting/reserve
/// split shown is always the one the server just returned.
void main() {
  const matchId = 'match-1';
  const communityId = 'community-1';

  var nextOrder = 0;

  MatchRegistration player(
    String userId, {
    RegistrationStatus status = RegistrationStatus.confirmed,
    String? name,
  }) =>
      MatchRegistration(
        userId: userId,
        fullName: name ?? 'Player $userId',
        position: 'MID',
        status: status,
        registrationOrder: ++nextOrder,
      );

  MatchRegistration guest(
    String guestId,
    String name, {
    RegistrationStatus status = RegistrationStatus.confirmed,
  }) =>
      MatchRegistration(
        professionalGuestId: guestId,
        fullName: name,
        status: status,
        registrationOrder: ++nextOrder,
      );

  Future<void> pumpRoster(
    WidgetTester tester, {
    required FakeMatchAdapter matches,
    bool canRemove = true,
    bool canManageGuests = true,
    RegistrationStatus filter = RegistrationStatus.confirmed,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ManageRosterScreen(
          matchId: matchId,
          communityId: communityId,
          filter: filter,
          title: 'Players',
          canRemove: canRemove,
          canManageGuests: canManageGuests,
          service: MatchService(matches),
          memberRepository: MemberRepository(FakeMemberAdapter()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<AppLocalizations> localizationsFor(Locale locale) =>
      AppLocalizations.delegate.load(locale);

  // --- 1. mapping --------------------------------------------------------------

  group('1. a guest is mapped from the provider row', () {
    test('a guest row becomes a guest registration', () {
      final registration = matchRegistrationFromRow({
        'status': 'reserve',
        'registration_order': 7,
        'user': null,
        'guest': {'id': 'guest-1', 'display_name': 'أحمد'},
      });

      expect(registration.isProfessionalGuest, isTrue);
      expect(registration.professionalGuestId, 'guest-1');
      expect(registration.userId, isNull);
      expect(registration.fullName, 'أحمد');
      expect(registration.position, isNull,
          reason: 'a guest has no profile to read a position from');
      expect(registration.status, RegistrationStatus.reserve);
      expect(registration.registrationOrder, 7);
      expect(registration.participantId, 'guest-1');
    });

    test('a registered player is unaffected', () {
      final registration = matchRegistrationFromRow({
        'status': 'confirmed',
        'registration_order': 1,
        'user': {
          'id': 'user-1',
          'full_name': 'Sara',
          'primary_position': 'GK',
        },
        'guest': null,
      });

      expect(registration.isProfessionalGuest, isFalse);
      expect(registration.userId, 'user-1');
      expect(registration.professionalGuestId, isNull);
      expect(registration.fullName, 'Sara');
      expect(registration.position, 'GK');
      expect(registration.participantId, 'user-1');
    });

    test('a row naming neither participant is an infrastructure fault', () {
      expect(
        () => matchRegistrationFromRow({
          'status': 'confirmed',
          'registration_order': 1,
          'user': null,
          'guest': null,
        }),
        throwsA(isA<InfrastructureFailure>()),
      );
    });
  });

  // --- 2. the approved wording ---------------------------------------------------

  group('2. a guest is named as one', () {
    test('Arabic renders محترف (الاسم)', () async {
      final l10n = await localizationsFor(const Locale('ar'));
      expect(participantLabel(l10n, guest('g1', 'أحمد')), 'محترف (أحمد)');
    });

    test('English renders the same sentence in English', () async {
      final l10n = await localizationsFor(const Locale('en'));
      expect(participantLabel(l10n, guest('g1', 'Ahmed')), 'Professional (Ahmed)');
    });

    test('a registered player is their own name, unadorned', () async {
      final l10n = await localizationsFor(const Locale('ar'));
      expect(participantLabel(l10n, player('u1', name: 'سارة')), 'سارة');
    });

    test('the subtitle says what a guest is, and a position for anyone else',
        () async {
      final l10n = await localizationsFor(const Locale('en'));
      expect(
        participantSubtitle(l10n, guest('g1', 'Ahmed'), (p) => 'POS:$p'),
        'Professional guest',
      );
      expect(
        participantSubtitle(l10n, player('u1'), (p) => 'POS:$p'),
        'POS:MID',
      );
    });
  });

  // --- 3, 12. the roster as drawn --------------------------------------------------

  group('3. a guest is drawn differently from a player', () {
    testWidgets('the guest row is named, labelled and given its own tile',
        (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        player('u1', name: 'Sara'),
        guest('g1', 'Ahmed'),
      ]);
      await pumpRoster(tester, matches: matches);

      expect(find.text('Professional (Ahmed)'), findsOneWidget);
      expect(find.text('Professional guest'), findsOneWidget);
      expect(find.byKey(const Key('guestTile_g1')), findsOneWidget);
    });

    testWidgets('12. a normal player row is unchanged', (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        player('u1', name: 'Sara'),
        guest('g1', 'Ahmed'),
      ]);
      await pumpRoster(tester, matches: matches);

      // The player keeps their own name and their profile position, and gains
      // neither the guest wording nor the guest tile.
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('Midfielder'), findsOneWidget);
      expect(find.byKey(const Key('guestTile_u1')), findsNothing);
      expect(find.byKey(const Key('removeGuest_u1')), findsNothing);
    });
  });

  // --- 4, 5, 6. who is offered the controls -----------------------------------------

  group('who may manage guests', () {
    testWidgets('4/5. an owner or admin is offered Add professional guest',
        (tester) async {
      // The screen is reached only through the admin-gated management hub, which
      // passes `canManageGuests: true` for both roles — this is that contract.
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(registrations: [player('u1')]),
      );

      expect(find.byKey(const Key('addGuestButton')), findsOneWidget);
      expect(find.text('Add professional guest'), findsOneWidget);
    });

    testWidgets('6. without the role there are no guest controls at all',
        (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(registrations: [
          player('u1'),
          guest('g1', 'Ahmed'),
        ]),
        canManageGuests: false,
        canRemove: false,
      );

      expect(find.byKey(const Key('addGuestButton')), findsNothing);
      expect(find.byKey(const Key('renameGuest_g1')), findsNothing);
      expect(find.byKey(const Key('removeGuest_g1')), findsNothing);
      // The guest is still *shown* — reading a roster is not managing it.
      expect(find.text('Professional (Ahmed)'), findsOneWidget);
    });

    testWidgets(
        'the guest control survives a locked match, where the player one does '
        'not', (tester) async {
      // `canRemove: false` is the match lock. The approved rule is that it
      // closes the community roster and never the guest one.
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(registrations: [
          player('u1'),
          guest('g1', 'Ahmed'),
        ]),
        canRemove: false,
      );

      expect(find.byKey(const Key('addPlayerButton')), findsNothing);
      expect(find.byKey(const Key('addGuestButton')), findsOneWidget);
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget);
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget);
    });
  });

  // --- 7, 8, 9, 10, 11. the mutations -----------------------------------------------

  group('managing a guest', () {
    testWidgets('7/10/11. adding sends the name and re-reads the roster',
        (tester) async {
      // The server will seat this guest in the reserve. The screen has four
      // starting slots and one player in them, so any local guess would say
      // "starting" — reporting "reserve" is only possible by reading the
      // answer back.
      final matches = FakeMatchAdapter(
        registrations: [player('u1')],
        guestSeat: RegistrationStatus.reserve,
      );
      await pumpRoster(tester, matches: matches);
      final fetchesBefore = matches.registrationFetches;

      await tester.tap(find.byKey(const Key('addGuestButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guestNameField')), 'Ahmed');
      await tester.tap(find.byKey(const Key('guestNameSubmit')));
      await tester.pumpAndSettle();

      expect(matches.addedGuests, [(matchId, 'Ahmed')]);
      expect(matches.registrationFetches, greaterThan(fetchesBefore),
          reason: 'the roster is re-read after the mutation');
      expect(find.text('Ahmed was added to the reserve list.'), findsOneWidget,
          reason: 'the seat reported is the one the server returned');
    });

    testWidgets('the name is trimmed and a short one is refused before sending',
        (tester) async {
      final matches = FakeMatchAdapter(registrations: [player('u1')]);
      await pumpRoster(tester, matches: matches);

      await tester.tap(find.byKey(const Key('addGuestButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guestNameField')), ' A ');
      await tester.tap(find.byKey(const Key('guestNameSubmit')));
      await tester.pumpAndSettle();

      expect(matches.addedGuests, isEmpty);
      expect(find.text('Enter a name between 2 and 60 characters.'),
          findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('guestNameField')), '  Ahmed  ');
      await tester.tap(find.byKey(const Key('guestNameSubmit')));
      await tester.pumpAndSettle();

      expect(matches.addedGuests, [(matchId, 'Ahmed')]);
    });

    testWidgets('8/10. renaming sends the guest id and re-reads the roster',
        (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        player('u1'),
        guest('g1', 'Ahmed'),
      ]);
      await pumpRoster(tester, matches: matches);
      final fetchesBefore = matches.registrationFetches;

      await tester.tap(find.byKey(const Key('renameGuest_g1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guestNameField')), 'Ahmad');
      await tester.tap(find.byKey(const Key('guestNameSubmit')));
      await tester.pumpAndSettle();

      expect(matches.renamedGuests, [(matchId, 'g1', 'Ahmad')]);
      expect(matches.registrationFetches, greaterThan(fetchesBefore));
    });

    testWidgets('9/10. removing asks first, then sends the guest id and re-reads',
        (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        player('u1'),
        guest('g1', 'Ahmed'),
      ]);
      await pumpRoster(tester, matches: matches);
      final fetchesBefore = matches.registrationFetches;

      await tester.tap(find.byKey(const Key('removeGuest_g1')));
      await tester.pumpAndSettle();
      expect(find.text('Remove this professional guest?'), findsOneWidget);

      await tester.tap(find.text('Remove guest'));
      await tester.pumpAndSettle();

      expect(matches.removedGuests, [(matchId, 'g1')]);
      expect(matches.registrationFetches, greaterThan(fetchesBefore));
    });

    testWidgets('answering no to the removal sends nothing', (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        player('u1'),
        guest('g1', 'Ahmed'),
      ]);
      await pumpRoster(tester, matches: matches);

      await tester.tap(find.byKey(const Key('removeGuest_g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(matches.removedGuests, isEmpty);
    });

    testWidgets('a refusal is shown in the reader\'s words and still re-reads',
        (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [player('u1')],
        guestFailure: const ValidationFailure(FailureReason.invalidGuestName),
      );
      await pumpRoster(tester, matches: matches);
      final fetchesBefore = matches.registrationFetches;

      await tester.tap(find.byKey(const Key('addGuestButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guestNameField')), 'Ahmed');
      await tester.tap(find.byKey(const Key('guestNameSubmit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name between 2 and 60 characters.'),
          findsOneWidget);
      expect(matches.registrationFetches, greaterThan(fetchesBefore),
          reason: 'a refusal usually means the roster moved underneath');
    });

    testWidgets('a refused permission says so', (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
        guestFailure: const AuthorizationFailure(),
      );
      await pumpRoster(tester, matches: matches);

      await tester.tap(find.byKey(const Key('removeGuest_g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove guest'));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'),
          findsOneWidget);
    });
  });

  // --- 11. the ordering is the server's ----------------------------------------------

  group('11. the roster shown is the roster returned', () {
    testWidgets('reserve guests appear under the reserve filter, in order',
        (tester) async {
      // Deliberately handed back in the order the server chose, with a guest
      // between two players. Nothing in the client re-sorts it.
      final matches = FakeMatchAdapter(registrations: [
        player('u1', status: RegistrationStatus.reserve, name: 'First'),
        guest('g1', 'Ahmed', status: RegistrationStatus.reserve),
        player('u2', status: RegistrationStatus.reserve, name: 'Last'),
      ]);
      await pumpRoster(
        tester,
        matches: matches,
        filter: RegistrationStatus.reserve,
      );

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(
        [for (final tile in tiles) (tile.title! as Text).data],
        ['First', 'Professional (Ahmed)', 'Last'],
      );
    });

    testWidgets('a confirmed guest is not shown under the reserve filter',
        (tester) async {
      final matches = FakeMatchAdapter(registrations: [
        guest('g1', 'Ahmed'),
        guest('g2', 'Omar', status: RegistrationStatus.reserve),
      ]);
      await pumpRoster(
        tester,
        matches: matches,
        filter: RegistrationStatus.reserve,
      );

      expect(find.text('Professional (Omar)'), findsOneWidget);
      expect(find.text('Professional (Ahmed)'), findsNothing);
    });
  });
}

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    required this.registrations,
    this.guestFailure,
    this.guestSeat = RegistrationStatus.confirmed,
  });

  List<MatchRegistration> registrations;
  final Failure? guestFailure;

  /// The seat the server gives the next guest. The screen must report this and
  /// never a guess of its own, which is the whole point of setting it here.
  final RegistrationStatus guestSeat;

  final List<(String, String)> addedGuests = [];
  final List<(String, String)> removedGuests = [];
  final List<(String, String, String)> renamedGuests = [];
  int registrationFetches = 0;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async {
    registrationFetches++;
    return registrations;
  }

  @override
  Future<String> addProfessionalGuest(String matchId, String name) async {
    if (guestFailure != null) throw guestFailure!;
    addedGuests.add((matchId, name));
    final id = 'guest-${addedGuests.length}';
    // The roster the next read returns is the one this write produced, as it
    // would be against the real database.
    registrations = [
      ...registrations,
      MatchRegistration(
        professionalGuestId: id,
        fullName: name,
        status: guestSeat,
        registrationOrder: registrations.length + 1,
      ),
    ];
    return id;
  }

  @override
  Future<void> removeProfessionalGuest(String matchId, String guestId) async {
    if (guestFailure != null) throw guestFailure!;
    removedGuests.add((matchId, guestId));
  }

  @override
  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) async {
    if (guestFailure != null) throw guestFailure!;
    renamedGuests.add((matchId, guestId, name));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeMemberAdapter implements MemberAdapter {
  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
