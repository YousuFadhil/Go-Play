import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/manage_roster_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';

/// Owner/admin adding a member to a match, from the screen's side.
///
/// What is asserted here is the half the app owns: which members are *offered*,
/// what the reader is told about the result, and that a refusal is shown rather
/// than swallowed. **The rules themselves are not tested here and cannot be** —
/// capacity, reserve, overlap, ordering and the duplicate rule live in one
/// SQL transaction that this layer only calls. Those are exercised against the
/// database directly; see the Feature 2 report.
///
/// The one rule this layer does implement is the eligibility filter, and it is
/// deliberately the narrow one: a member already registered is not offered.
/// Everything else is left to the server precisely so there is no second copy
/// of it here to drift.
void main() {
  const matchId = 'match-1';
  const communityId = 'community-1';

  var nextOrder = 0;
  MatchRegistration registration(String userId, RegistrationStatus status) =>
      MatchRegistration(
        registrationId: 'reg-$userId',
        userId: userId,
        fullName: 'Player $userId',
        position: 'MID',
        status: status,
        registrationOrder: ++nextOrder,
      );

  CommunityMember member(String userId, {String name = ''}) => CommunityMember(
        userId: userId,
        fullName: name.isEmpty ? 'Member $userId' : name,
        position: 'MID',
        role: CommunityRole.player,
      );

  Future<void> pumpRoster(
    WidgetTester tester, {
    required FakeMatchAdapter matches,
    required FakeMemberAdapter members,
    bool canRemove = true,
    bool canAddCommunityPlayer = true,
    bool canManageGuests = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ManageRosterScreen(
          matchId: matchId,
          communityId: communityId,
          filter: RegistrationStatus.confirmed,
          title: 'Players',
          canRemove: canRemove,
          canAddCommunityPlayer: canAddCommunityPlayer,
          canManageGuests: canManageGuests,
          service: MatchService(matches),
          memberRepository: MemberRepository(members),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the Add player action', () {
    testWidgets('is offered while the roster can still be changed',
        (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.widgetWithText(FloatingActionButton, 'Add player'),
          findsOneWidget);
    });

    // CHANGED: this used to assert the opposite, on the reasoning that a roster
    // which cannot be shortened cannot be lengthened either. That was never the
    // database's rule — `admin_add_player_to_match` passes
    // `p_enforce_time_lock => false` — and it is what left a completed match
    // offering to add a Professional Guest but not a community player.
    testWidgets('survives the lock that closes removal', (tester) async {
      await pumpRoster(
        tester,
        // The state a locked or completed match arrives in.
        canRemove: false,
        canAddCommunityPlayer: true,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.widgetWithText(FloatingActionButton, 'Add player'),
          findsOneWidget,
          reason: 'an owner or admin adds a community member in every ordinary '
              'match state, which is what the database allows');
    });

    testWidgets('is withheld from a reader who may not add', (tester) async {
      await pumpRoster(
        tester,
        canRemove: false,
        canAddCommunityPlayer: false,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    // The two capabilities are independent in both directions, which is the
    // point of splitting them: widening addition must not widen removal.
    testWidgets('being offered does not bring Remove with it', (tester) async {
      await pumpRoster(
        tester,
        canRemove: false,
        canAddCommunityPlayer: true,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.widgetWithText(FloatingActionButton, 'Add player'),
          findsOneWidget);
      expect(find.byTooltip('Remove player'), findsNothing,
          reason: 'removal answers to its own rule and is closed on a match '
              'that has been played');
    });

    testWidgets('stands beside Add guest on a completed match', (tester) async {
      await pumpRoster(
        tester,
        // Exactly how a completed match reaches this screen: removal closed,
        // both additions open.
        canRemove: false,
        canAddCommunityPlayer: true,
        canManageGuests: true,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.byKey(const Key('addPlayerButton')), findsOneWidget);
      expect(find.byKey(const Key('addGuestButton')), findsOneWidget,
          reason: 'the guest action was always available here; the community '
              'player action is what was missing beside it');
    });
  });

  group('who is offered', () {
    testWidgets('a confirmed player is not offered again', (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('a'), member('b')]),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Member b'), findsOneWidget);
      expect(find.text('Member a'), findsNothing);
    });

    testWidgets('a reserve player is not offered again either', (tester) async {
      // The screen is showing the *confirmed* list, so a reserve player is not
      // on it — and would be invisible to a filter that only looked at what is
      // rendered. Reserve is registration, and registration is what excludes.
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(
          registrations: [
            registration('a', RegistrationStatus.confirmed),
            registration('r', RegistrationStatus.reserve),
          ],
        ),
        members: FakeMemberAdapter(
          members: [member('a'), member('r'), member('b')],
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Member b'), findsOneWidget);
      expect(find.text('Member r'), findsNothing);
      expect(find.text('Member a'), findsNothing);
    });

    testWidgets('says so when everyone is already in the match',
        (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('a')]),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Every community member is already in this match.'),
          findsOneWidget);
    });
  });

  group('adding', () {
    /// Opens the picker once, selects everybody named, and starts the batch.
    ///
    /// One trip through the sheet however many players are chosen, which is the
    /// whole point of the change: there is no per-player confirmation to answer
    /// and no reopening between them.
    Future<void> pickAndAdd(WidgetTester tester, List<String> names) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      for (final name in names) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('addSelectedPlayersButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('reports a confirmed place and refreshes the roster',
        (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [registration('a', RegistrationStatus.confirmed)],
        addResult: RegistrationStatus.confirmed,
      );
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b')]),
      );

      await pickAndAdd(tester, ['Member b']);

      expect(matches.added, [(matchId, 'b')]);
      expect(find.text('1 player was added.'), findsOneWidget);
      // Re-read rather than patched in memory: the server decided the roster,
      // so the server is asked what it now looks like.
      expect(matches.registrationFetches, greaterThan(1));
    });

    testWidgets('reports a reserve place when the starting places are full',
        (tester) async {
      // The screen does not work this out from the counts it has — it says
      // what the database returned, which is the only answer that survives a
      // roster moving between opening the picker and confirming.
      final matches = FakeMatchAdapter(
        registrations: [registration('a', RegistrationStatus.confirmed)],
        addResult: RegistrationStatus.reserve,
      );
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b')]),
      );

      await pickAndAdd(tester, ['Member b']);

      // The status still comes from the server; where they landed is shown by
      // the reloaded roster rather than restated in the summary.
      expect(matches.added, [(matchId, 'b')]);
      expect(find.text('1 player was added.'), findsOneWidget);
    });

    testWidgets('adds nobody when the sheet is dismissed', (tester) async {
      // The count on the action is the confirmation now, so what replaces
      // declining a dialog is simply not pressing it.
      final matches = FakeMatchAdapter(
        registrations: [registration('a', RegistrationStatus.confirmed)],
      );
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b')]),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member b'));
      await tester.pumpAndSettle();
      // Dismissed by tapping the barrier above the sheet.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(matches.added, isEmpty);
    });

    testWidgets('the action stays inert until somebody is chosen',
        (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('addSelectedPlayersButton')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('adding several at once', () {
    Future<void> pickAndAddMany(
        WidgetTester tester, List<String> names) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      for (final name in names) {
        // The sheet scrolls once there are more members than fit, so a row is
        // brought into view before it is tapped.
        await tester.ensureVisible(find.text(name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('addSelectedPlayersButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('the action counts what is chosen', (tester) async {
      await pumpRoster(
        tester,
        matches: FakeMatchAdapter(registrations: const []),
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 player'), findsNothing);

      await tester.tap(find.text('Member b'));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 player'), findsOneWidget);

      await tester.tap(find.text('Member c'));
      await tester.pumpAndSettle();
      expect(find.text('Add 2 players'), findsOneWidget);

      // Chosen twice is unchosen: the row is a toggle.
      await tester.tap(find.text('Member c'));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 player'), findsOneWidget);
    });

    testWidgets('every one of them goes through the canonical add',
        (tester) async {
      // One call per player, each the same `addPlayerToMatch` the single add
      // always used — so membership, duplicates, capacity, overlap and the
      // confirmed/reserve decision are still the database's, per player.
      final matches = FakeMatchAdapter(registrations: const []);
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

      expect(matches.added, [(matchId, 'b'), (matchId, 'c'), (matchId, 'd')]);
      expect(find.text('3 players were added.'), findsOneWidget);
    });

    testWidgets('where each landed stays the answer the server gave',
        (tester) async {
      // Two seats left and three added: the screen does not work out who
      // starts. It sends three and shows what came back.
      final matches = FakeMatchAdapter(registrations: const [])
        ..addResults['b'] = RegistrationStatus.confirmed
        ..addResults['c'] = RegistrationStatus.confirmed
        ..addResults['d'] = RegistrationStatus.reserve;
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

      expect(matches.added, hasLength(3));
      expect(find.text('3 players were added.'), findsOneWidget);
    });

    testWidgets('one refusal does not undo the others', (tester) async {
      // The case the batch exists for: some added, one with a clashing match.
      // Those stand — there is no batch in the database to roll back.
      final matches = FakeMatchAdapter(registrations: const [])
        ..addFailures['c'] =
            const ConflictFailure(FailureReason.overlappingMatch);
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

      expect(matches.added, [(matchId, 'b'), (matchId, 'd')],
          reason: 'the two that were accepted stay accepted');
      expect(find.textContaining('2 added, 1 could not be.'), findsOneWidget);
      expect(
        find.textContaining(
            'That player is registered in another match at the same time.'),
        findsOneWidget,
        reason: 'the refusal the database gave is kept, not flattened',
      );
    });

    testWidgets('all refused says so once, not once per player',
        (tester) async {
      final matches = FakeMatchAdapter(
        registrations: const [],
        addFailure: const ConflictFailure(FailureReason.alreadyRegistered),
      );
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b'), member('c')]),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c']);

      expect(matches.added, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'one report for the batch, not one per failure');
      expect(
        find.textContaining('None of the 2 players could be added.'),
        findsOneWidget,
      );
    });

    testWidgets('two failures for the same reason say it once', (tester) async {
      final matches = FakeMatchAdapter(registrations: const [])
        ..addFailures['b'] =
            const ConflictFailure(FailureReason.overlappingMatch)
        ..addFailures['c'] =
            const ConflictFailure(FailureReason.overlappingMatch);
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      final text = (snack.content as Text).data!;
      expect(
        'That player is registered in another match at the same time.'
            .allMatches(text),
        hasLength(1),
        reason: 'the same refusal twice is still one thing to say',
      );
    });

    // How many players were refused, and how many different things there are to
    // say about it, are two quantities. Counting the sentences instead of the
    // players under-reported every batch where refusals shared a reason.
    group('the failure count is players, not reasons', () {
      testWidgets('three refused for one reason is three, said once',
          (tester) async {
        final matches = FakeMatchAdapter(registrations: const [])
          ..addFailures['c'] =
              const ConflictFailure(FailureReason.overlappingMatch)
          ..addFailures['d'] =
              const ConflictFailure(FailureReason.overlappingMatch)
          ..addFailures['e'] =
              const ConflictFailure(FailureReason.overlappingMatch);
        await pumpRoster(
          tester,
          matches: matches,
          members: FakeMemberAdapter(members: [
            member('b'),
            member('c'),
            member('d'),
            member('e'),
            member('f'),
          ]),
        );

        await pickAndAddMany(tester, [
          'Member b',
          'Member c',
          'Member d',
          'Member e',
          'Member f',
        ]);

        expect(matches.added, [(matchId, 'b'), (matchId, 'f')]);

        final text = ((tester.widget<SnackBar>(find.byType(SnackBar)).content)
                as Text)
            .data!;
        expect(text, contains('2 added, 3 could not be.'),
            reason: 'three players failed, however few reasons they share');
        expect(
          'That player is registered in another match at the same time.'
              .allMatches(text),
          hasLength(1),
          reason: 'and the reason they share is still said once',
        );
      });

      testWidgets('failures with different reasons are all counted',
          (tester) async {
        final matches = FakeMatchAdapter(registrations: const [])
          ..addFailures['c'] =
              const ConflictFailure(FailureReason.overlappingMatch)
          ..addFailures['d'] =
              const ConflictFailure(FailureReason.alreadyRegistered);
        await pumpRoster(
          tester,
          matches: matches,
          members: FakeMemberAdapter(
            members: [member('b'), member('c'), member('d')],
          ),
        );

        await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

        final text = ((tester.widget<SnackBar>(find.byType(SnackBar)).content)
                as Text)
            .data!;
        expect(text, contains('1 added, 2 could not be.'));
        expect(
          text,
          contains(
              'That player is registered in another match at the same time.'),
        );
        expect(text, contains('That player is already in this match.'),
            reason: 'each distinct reason is rendered, once each');
      });

      testWidgets('all refused for one reason counts every player',
          (tester) async {
        // The count in "None of the N players could be added." is the players
        // that failed, not the sentences describing it.
        final matches = FakeMatchAdapter(
          registrations: const [],
          addFailure: const ConflictFailure(FailureReason.overlappingMatch),
        );
        await pumpRoster(
          tester,
          matches: matches,
          members: FakeMemberAdapter(
            members: [member('b'), member('c'), member('d')],
          ),
        );

        await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

        expect(matches.added, isEmpty);
        final text = ((tester.widget<SnackBar>(find.byType(SnackBar)).content)
                as Text)
            .data!;
        expect(text, contains('None of the 3 players could be added.'));
        expect(
          'That player is registered in another match at the same time.'
              .allMatches(text),
          hasLength(1),
        );
      });

      testWidgets('a clean batch still reports no failures at all',
          (tester) async {
        await pumpRoster(
          tester,
          matches: FakeMatchAdapter(registrations: const []),
          members: FakeMemberAdapter(
            members: [member('b'), member('c')],
          ),
        );

        await pickAndAddMany(tester, ['Member b', 'Member c']);

        expect(find.text('2 players were added.'), findsOneWidget);
        expect(find.textContaining('could not be'), findsNothing);
      });
    });

    testWidgets('the roster is re-read once, after the batch', (tester) async {
      final matches = FakeMatchAdapter(registrations: const []);
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(
          members: [member('b'), member('c'), member('d')],
        ),
      );
      final before = matches.registrationFetches;

      await pickAndAddMany(tester, ['Member b', 'Member c', 'Member d']);

      expect(matches.registrationFetches, before + 1,
          reason: 'one refresh for the batch, not one per player');
    });

    testWidgets('a stale pick is still refused by the server', (tester) async {
      // Eligible when the sheet opened, registered by the time the batch ran.
      // The client filter is a convenience; this is the authority.
      final matches = FakeMatchAdapter(registrations: const [])
        ..addFailures['b'] =
            const ConflictFailure(FailureReason.alreadyRegistered);
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b'), member('c')]),
      );

      await pickAndAddMany(tester, ['Member b', 'Member c']);

      expect(matches.added, [(matchId, 'c')]);
      expect(find.textContaining('That player is already in this match.'),
          findsOneWidget);
    });
  });

  group('when the database refuses', () {
    Future<void> expectRefusal(
      WidgetTester tester,
      Failure failure,
      String message,
    ) async {
      final matches = FakeMatchAdapter(
        registrations: [registration('a', RegistrationStatus.confirmed)],
        addFailure: failure,
      );
      await pumpRoster(
        tester,
        matches: matches,
        members: FakeMemberAdapter(members: [member('b')]),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member b'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addSelectedPlayersButton')));
      await tester.pumpAndSettle();

      // The refusal the database gave, kept word for word inside the summary
      // the batch reports.
      expect(find.textContaining(message), findsOneWidget);
    }

    testWidgets('a player added in the meantime is reported as already in',
        (tester) async {
      // The race the picker cannot prevent: eligible when the sheet opened,
      // registered by the time it was confirmed. The server is authoritative
      // and its refusal is what the reader is told.
      await expectRefusal(
        tester,
        const ConflictFailure(FailureReason.alreadyRegistered),
        'That player is already in this match.',
      );
    });

    testWidgets('a clash is reported about the player, not the reader',
        (tester) async {
      // "You are registered in another match" would be the wrong sentence:
      // the reader is an admin adding somebody else.
      await expectRefusal(
        tester,
        const ConflictFailure(FailureReason.overlappingMatch),
        'That player is registered in another match at the same time.',
      );
    });

    testWidgets('a non-member is reported as one', (tester) async {
      await expectRefusal(
        tester,
        const ConflictFailure(FailureReason.notCommunityMember),
        'That player is not a member of this community.',
      );
    });

    testWidgets('a full match is reported with the existing wording',
        (tester) async {
      await expectRefusal(
        tester,
        const ConflictFailure(FailureReason.registrationClosed),
        'Registration is closed; the match reached its maximum.',
      );
    });

    testWidgets('a locked match is reported with the existing wording',
        (tester) async {
      await expectRefusal(
        tester,
        const ConflictFailure(FailureReason.matchLocked),
        'The match has started and is locked until it finishes.',
      );
    });

    testWidgets('a refused permission is reported as one', (tester) async {
      await expectRefusal(
        tester,
        const AuthorizationFailure(),
        'You do not have permission to do this.',
      );
    });

    testWidgets('anything else falls back rather than showing nothing',
        (tester) async {
      await expectRefusal(
        tester,
        const NetworkFailure(),
        'That player could not be added. Try again.',
      );
    });
  });

  group('Arabic', () {
    testWidgets('the action and the result are localized', (tester) async {
      final matches = FakeMatchAdapter(
        registrations: [registration('a', RegistrationStatus.confirmed)],
        addResult: RegistrationStatus.reserve,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ManageRosterScreen(
            matchId: matchId,
            communityId: communityId,
            filter: RegistrationStatus.confirmed,
            title: 'اللاعبون',
            canRemove: true,
            canAddCommunityPlayer: true,
            service: MatchService(matches),
            memberRepository:
                MemberRepository(FakeMemberAdapter(members: [member('b')])),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FloatingActionButton, 'إضافة لاعب'),
          findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member b'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addSelectedPlayersButton')));
      await tester.pumpAndSettle();

      // The counted action and the batch summary are both Arabic.
      expect(matches.added, [(matchId, 'b')]);
      expect(find.text('تمت إضافة لاعب واحد.'), findsOneWidget);
    });
  });
}

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    this.registrations = const [],
    this.addResult = RegistrationStatus.confirmed,
    this.addFailure,
  });

  final List<MatchRegistration> registrations;
  final RegistrationStatus addResult;
  final Failure? addFailure;

  /// Refusals for particular players, so a batch can be partly refused the way
  /// the database refuses one: per registration, not per batch.
  final Map<String, Failure> addFailures = {};

  /// Where particular players land, when the server's answer differs per
  /// player.
  final Map<String, RegistrationStatus> addResults = {};

  final List<(String, String)> added = [];
  int registrationFetches = 0;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async {
    registrationFetches++;
    return registrations;
  }

  @override
  Future<RegistrationStatus> addPlayerToMatch(
      String matchId, String userId) async {
    final perPlayer = addFailures[userId];
    if (perPlayer != null) throw perPlayer;
    if (addFailure != null) throw addFailure!;
    added.add((matchId, userId));
    return addResults[userId] ?? addResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeMemberAdapter implements MemberAdapter {
  FakeMemberAdapter({this.members = const []});

  final List<CommunityMember> members;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      members;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
