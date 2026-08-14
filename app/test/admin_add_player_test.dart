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

    testWidgets('is withheld once the match is locked or completed',
        (tester) async {
      // The same answer that already hides Remove. A roster that cannot be
      // shortened cannot be lengthened either, and offering the action would
      // only earn a refusal from the database.
      await pumpRoster(
        tester,
        canRemove: false,
        matches: FakeMatchAdapter(
          registrations: [registration('a', RegistrationStatus.confirmed)],
        ),
        members: FakeMemberAdapter(members: [member('b')]),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
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
    Future<void> pickAndConfirm(WidgetTester tester, String name) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add player'));
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

      await pickAndConfirm(tester, 'Member b');

      expect(matches.added, [(matchId, 'b')]);
      expect(find.text('Member b was added to the starting players.'),
          findsOneWidget);
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

      await pickAndConfirm(tester, 'Member b');

      expect(find.text('Member b was added to the reserve list.'),
          findsOneWidget);
    });

    testWidgets('does nothing when the confirmation is declined',
        (tester) async {
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
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();

      expect(matches.added, isEmpty);
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
      await tester.tap(find.widgetWithText(FilledButton, 'Add player'));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
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
      await tester.tap(find.widgetWithText(FilledButton, 'إضافة لاعب'));
      await tester.pumpAndSettle();

      expect(find.text('تمت إضافة Member b إلى قائمة الاحتياط.'),
          findsOneWidget);
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
    if (addFailure != null) throw addFailure!;
    added.add((matchId, userId));
    return addResult;
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
