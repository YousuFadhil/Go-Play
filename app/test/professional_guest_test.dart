import 'dart:io';

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
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:btge/btge.dart';
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
        registrationId: 'reg-$userId',
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
        registrationId: 'reg-$guestId',
        professionalGuestId: guestId,
        fullName: name,
        status: status,
        registrationOrder: ++nextOrder,
      );

  /// A match in one of the two states this suite cares about. `isCompleted`
  /// and `isLocked` are derived from these times, so a fixture with a past end
  /// is a played match to every reader that asks.
  Match matchIn({required Duration startsIn, Duration length = const Duration(hours: 2)}) {
    final start = DateTime.now().add(startsIn);
    return Match(
      id: matchId,
      communityId: communityId,
      createdBy: 'u9',
      location: 'Al Amerat Pitch',
      startAt: start,
      endAt: start.add(length),
      startingPlayers: 4,
      maxRegistration: 6,
      status: MatchStatus.open,
      title: 'ITest match',
    );
  }

  Match playedMatch() => matchIn(startsIn: const Duration(days: -3));

  Future<void> pumpRoster(
    WidgetTester tester, {
    required FakeMatchAdapter matches,
    bool canRemove = true,
    bool canManageGuests = true,
    Match? match,
    List<TeamAssignment> lineup = const [],
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
          match: match,
          service: MatchService(matches),
          memberRepository: MemberRepository(FakeMemberAdapter()),
          teamRepository: TeamRepository(_LineupOnlyAdapter(lineup)),
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
        'registration_id': 'reg-guest-1',
        'user_id': null,
        'professional_guest_id': 'guest-1',
        'participant_type': 'PROFESSIONAL',
        'display_name': 'أحمد',
        'primary_position': null,
        'status': 'reserve',
        'registration_order': 7,
        'admin_order': null,
        'roster_position': 7,
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
      expect(registration.registrationId, 'reg-guest-1',
          reason: 'a guest holds a seat, and a seat is what an arrangement '
              'names');
    });

    test('a registered player is unaffected', () {
      final registration = matchRegistrationFromRow({
        'registration_id': 'reg-user-1',
        'user_id': 'user-1',
        'professional_guest_id': null,
        'participant_type': 'USER',
        'display_name': 'Sara',
        'primary_position': 'GK',
        'status': 'confirmed',
        'registration_order': 1,
        'admin_order': null,
        'roster_position': 1,
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
          'registration_id': 'reg-1',
          'user_id': null,
          'professional_guest_id': null,
          'participant_type': 'USER',
          'display_name': 'Nobody',
          'status': 'confirmed',
          'registration_order': 1,
          'admin_order': null,
          'roster_position': 1,
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

  group('a played match: the factual lineup decides who may be removed', () {
    /// A guest's lineup row -- the only thing that makes them a participant of a
    /// match that has been played.
    TeamAssignment played(String guestId, {TeamId team = TeamId.a}) =>
        TeamAssignment(
          professionalGuestId: guestId,
          team: team,
          assignedPosition: Position.mid,
          basis: null,
        );

    testWidgets('a guest the lineup does not name may still leave the roster',
        (tester) async {
      // The case production already holds: a guest who was registered for a
      // match they did not play. Nothing factual records them, so the ordinary
      // roster removal is exactly right.
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpRoster(
        tester,
        matches: matches,
        match: playedMatch(),
        lineup: const [],
      );

      expect(find.byKey(const Key('addGuestButton')), findsNothing,
          reason: 'a new guest after completion goes through Teams');
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget,
          reason: 'renaming is neither an add nor a remove');
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('removeGuest_g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove guest'));
      await tester.pumpAndSettle();

      expect(matches.removedGuests, [(matchId, 'g1')],
          reason: 'the ordinary roster removal, called once');
    });

    testWidgets('a guest the lineup names is not removable from here',
        (tester) async {
      // They played. Taking their seat away here would free the seat and leave
      // the lineup row standing; the Teams screen's
      // `remove_played_professional_guest` is what takes both, with the guard
      // that protects a recorded scorer or best player.
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpRoster(
        tester,
        matches: matches,
        match: playedMatch(),
        lineup: [played('g1')],
      );

      expect(find.byKey(const Key('addGuestButton')), findsNothing);
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget);
      expect(find.byKey(const Key('removeGuest_g1')), findsNothing);
      expect(matches.removedGuests, isEmpty);
    });

    testWidgets('the lineup is authoritative, not the registration status',
        (tester) async {
      // The rule, stated where it can be got wrong. A confirmed seat is not
      // evidence of playing, and a reserve seat is not evidence of not playing:
      // only `match_team_assignments` answers that question.
      final matches = FakeMatchAdapter(
        registrations: [
          player('u1'),
          guest('g1', 'Confirmed but absent'),
          guest('g2', 'Reserve but played',
              status: RegistrationStatus.reserve),
        ],
      );

      await pumpRoster(
        tester,
        matches: matches,
        match: playedMatch(),
        lineup: [played('g2')],
        filter: RegistrationStatus.confirmed,
      );
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget,
          reason: 'confirmed, but no lineup row: a roster row and nothing more');

      await pumpRoster(
        tester,
        matches: matches,
        match: playedMatch(),
        lineup: [played('g2')],
        filter: RegistrationStatus.reserve,
      );
      expect(find.byKey(const Key('removeGuest_g2')), findsNothing,
          reason: 'a reserve seat with a lineup row is a participant, because '
              'the assignment is what is authoritative');
    });

    testWidgets('before completion the lineup decides nothing', (tester) async {
      // Future and active are untouched: every guest keeps add, rename and
      // remove, whether or not a lineup exists yet.
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpRoster(
        tester,
        matches: matches,
        lineup: [played('g1')],
      );

      expect(find.byKey(const Key('addGuestButton')), findsOneWidget);
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget);
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget,
          reason: 'the roster removal is the right one until the match is over');
    });
  });

  group('a match that finishes while the roster is open', () {
    // The race this guards: the screen is built while the match is being played,
    // so the permissions handed down say the roster is administrable -- and then
    // `end_at` passes with the screen still open. None of the ordinary roster
    // functions has a completion guard of its own: `remove_player` would delete
    // a seat, promote a reserve and notify them both about a match that is over,
    // and `admin_add_player_to_match` turns the time lock off deliberately. So
    // the stale screen must not offer, or send, any of them.
    //
    // The fixture is the stale state exactly: permissions computed for a match
    // in progress, paired with the match object as it now reads.
    Future<void> pumpStale(
      WidgetTester tester, {
      required FakeMatchAdapter matches,
      List<TeamAssignment> lineup = const [],
    }) =>
        pumpRoster(
          tester,
          matches: matches,
          canRemove: true,
          canManageGuests: true,
          match: playedMatch(),
          lineup: lineup,
        );

    testWidgets('the ordinary roster controls are gone once it is over',
        (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpStale(tester, matches: matches);

      // Adding either kind of participant was right a moment ago and is not now.
      expect(find.byKey(const Key('addPlayerButton')), findsNothing);
      expect(find.byKey(const Key('addGuestButton')), findsNothing);
      // Removing a community player is the factual correction's business now.
      expect(find.byTooltip('Remove'), findsNothing);
      // Renaming a guest is neither an add nor a remove, so it stays.
      expect(find.byKey(const Key('renameGuest_g1')), findsOneWidget);
    });

    testWidgets('a guest the lineup names cannot be removed from the roster',
        (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpStale(
        tester,
        matches: matches,
        lineup: const [
          TeamAssignment(
            professionalGuestId: 'g1',
            team: TeamId.a,
            assignedPosition: Position.mid,
            basis: null,
          ),
        ],
      );

      expect(find.byKey(const Key('removeGuest_g1')), findsNothing);
      expect(matches.removedGuests, isEmpty);
    });

    testWidgets('a guest the lineup does not name still may be', (tester) async {
      // The historical reserve: registered, never played, nothing factual about
      // them. The ordinary removal is still the right one, even now.
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpStale(tester, matches: matches, lineup: const []);

      await tester.tap(find.byKey(const Key('removeGuest_g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove guest'));
      await tester.pumpAndSettle();

      expect(matches.removedGuests, [(matchId, 'g1')]);
    });

    testWidgets('while the match is still being played, nothing is withheld',
        (tester) async {
      // The other side of the same rule: kickoff is not what closes the roster.
      final matches = FakeMatchAdapter(
        registrations: [player('u1'), guest('g1', 'Ahmed')],
      );
      await pumpRoster(
        tester,
        matches: matches,
        canRemove: true,
        canManageGuests: true,
        match: matchIn(
          startsIn: const Duration(hours: -1),
          length: const Duration(hours: 3),
        ),
      );

      expect(find.byKey(const Key('addGuestButton')), findsOneWidget);
      expect(find.byKey(const Key('removeGuest_g1')), findsOneWidget);
      expect(find.byTooltip('Remove'), findsOneWidget,
          reason: 'the community player removal is still the right one');
    });

    test('every handler re-asks the clock before it writes', () {
      // The controls above are the first half. This is the second: each handler
      // checks again immediately before its RPC, because a dialog or a sheet can
      // be open across the moment the match ends. Read as source, since the
      // window between a tap and a write is not something a widget test can sit
      // inside deterministically.
      final source = File('lib/features/matches/manage_roster_screen.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

      String handler(String signature) {
        final start = source.indexOf(signature);
        expect(start, greaterThan(-1), reason: signature);
        return source.substring(start, source.indexOf('\n  }', start));
      }

      // Community players: both ways in, each refusing before the service call.
      for (final signature in const [
        'Future<void> _addPlayers() async {',
        'Future<void> _remove(MatchRegistration player) async {',
        'Future<void> _addGuest() async {',
      ]) {
        final body = handler(signature);
        expect(body, contains('_refuseIfPlayed(l10n)'), reason: signature);
        expect(body.indexOf('_refuseIfPlayed(l10n)'),
            lessThan(body.indexOf('_service.')),
            reason: '$signature refuses before it calls the port');
      }

      // The two that stay open across a dialog ask a second time afterwards.
      expect(
          RegExp('_refuseIfPlayed').allMatches(handler(
              'Future<void> _addPlayers() async {')),
          hasLength(2));
      expect(
          RegExp('_refuseIfPlayed').allMatches(handler(
              'Future<void> _addGuest() async {')),
          hasLength(2));

      // Guest removal asks the factual lineup instead, and reads it first if the
      // match finished after the screen opened.
      final removeGuest =
          handler('Future<void> _removeGuest(MatchRegistration guest) async {');
      expect(removeGuest, contains('_mayRemoveFromRoster(guest)'));
      expect(removeGuest, contains('_loadPlayedGuestIds()'));
      expect(removeGuest.indexOf('_mayRemoveFromRoster(guest)'),
          lessThan(removeGuest.indexOf('_service.')));

      // And the live question is the clock's, never the flag the screen opened
      // with.
      expect(source, contains('bool get _played => widget.match?.isCompleted'));
    });
  });

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
        registrationId: 'reg-$id',
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

/// Serves one stored lineup and refuses everything else: the roster screen reads
/// nothing else through this port.
class _LineupOnlyAdapter implements TeamAdapter {
  _LineupOnlyAdapter(this.lineup);

  final List<TeamAssignment> lineup;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the roster screen reads only the lineup');
}
