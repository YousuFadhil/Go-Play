import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/states.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';

/// Opening a match you are not a member of.
///
/// `matches_select_community_members` (migration `0007`) filters the row out for
/// a non-member, so the read comes back as "no such match" — the same answer a
/// mistyped id gives. Match Details reported both as a failed load, which told a
/// reader nothing and offered them a retry that could never work.
///
/// What is asserted here is the difference: a membership refusal shows the
/// community and the way into it, a genuine transport failure still shows the
/// error state, and a member's match is unaffected. The policy is not weakened
/// anywhere — every test below has the match itself refused by the data layer
/// until the viewer has joined.
void main() {
  final kickOff = DateTime.now().add(const Duration(days: 2));

  final match = Match(
    id: 'm1',
    communityId: 'c1',
    createdBy: 'u9',
    location: 'Al Amerat Pitch',
    startAt: kickOff,
    endAt: kickOff.add(const Duration(hours: 2)),
    startingPlayers: 10,
    maxRegistration: 16,
    status: MatchStatus.open,
    title: 'Friday Night',
  );

  const memberContext = MatchAccessContext(
    matchExists: true,
    isMember: true,
    communityId: 'c1',
    communityName: 'Al Amerat FC',
    joinPolicy: JoinPolicy.open,
  );

  const outsiderContext = MatchAccessContext(
    matchExists: true,
    isMember: false,
    communityId: 'c1',
    communityName: 'Al Amerat FC',
    joinPolicy: JoinPolicy.open,
  );

  Future<void> pumpDetails(
    WidgetTester tester, {
    required FakeMatchAdapter matches,
    FakeCommunityAdapter? communities,
    CommunityRole? role = CommunityRole.player,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MatchDetailsScreen(
        matchId: 'm1',
        matchService: MatchService(matches),
        memberRepository: MemberRepository(FakeMemberAdapter(role: role)),
        communityRepository:
            CommunityRepository(communities ?? FakeCommunityAdapter()),
        authService: AuthService(_StubAuthAdapter()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('a non-member opens the match', () {
    testWidgets('is told to join the community rather than shown an error',
        (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: outsiderContext,
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.text('Join the community first'), findsOneWidget);
      expect(
        find.text('This match belongs to Al Amerat FC. Join the community to '
            'see the match and register for it.'),
        findsOneWidget,
      );
      expect(find.text('Join'), findsOneWidget);

      // The generic failure is gone, and with it the retry that led nowhere.
      expect(find.text('Failed to load data.'), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('is shown none of the match', (tester) async {
      // The policy is what withholds it and nothing here works around that.
      // The screen never received a match, so there is nothing to leak.
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: outsiderContext,
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.text('Friday Night'), findsNothing);
      expect(find.text('Al Amerat Pitch'), findsNothing);
      expect(find.text('Join match'), findsNothing);
      expect(matches.registrationReads, 0,
          reason: 'the roster is not asked for either');
    });

    testWidgets('a refusal the policy raised reaches the same state',
        (tester) async {
      // RLS can also refuse the statement outright (42501), which arrives as an
      // authorization failure rather than a missing row. Same situation, same
      // screen.
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const AuthorizationFailure(),
        access: outsiderContext,
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.text('Join the community first'), findsOneWidget);
    });

    testWidgets('a community with no name still says what to do',
        (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: const MatchAccessContext(
          matchExists: true,
          isMember: false,
          communityId: 'c1',
        ),
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(
        find.text('This match belongs to a community you have not joined. '
            'Join the community to see the match and register for it.'),
        findsOneWidget,
      );
    });

    testWidgets('Arabic says it in Arabic', (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: outsiderContext,
      );
      await pumpDetails(
        tester,
        matches: matches,
        role: null,
        locale: const Locale('ar'),
      );

      expect(find.text('انضم إلى المجتمع أولاً'), findsOneWidget);
    });
  });

  group('a member opens the match', () {
    testWidgets('sees the match, and nothing about joining a community',
        (tester) async {
      final matches = FakeMatchAdapter(match: match, access: memberContext);
      await pumpDetails(tester, matches: matches);

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Join the community first'), findsNothing);
      expect(matches.accessReads, 0,
          reason: 'a read that worked asks no follow-up question');
    });
  });

  group('joining, then opening the match', () {
    testWidgets('the match loads once the viewer is a member', (tester) async {
      // The fake behaves the way the database does: the match is unreadable
      // until the membership exists, and readable immediately afterwards.
      final communities = FakeCommunityAdapter();
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: outsiderContext,
      );
      communities.onJoin = () {
        matches.readFailure = null;
        matches.access = memberContext;
      };

      await pumpDetails(tester, matches: matches, communities: communities);
      expect(find.text('Join the community first'), findsOneWidget);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(communities.joinedCommunityId, 'c1',
          reason: 'the existing join flow is what runs');
      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Join the community first'), findsNothing);
    });

    testWidgets('a community that requires its code asks for it',
        (tester) async {
      final communities = FakeCommunityAdapter();
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: const MatchAccessContext(
          matchExists: true,
          isMember: false,
          communityId: 'c1',
          communityName: 'Al Amerat FC',
          joinPolicy: JoinPolicy.codeRequired,
        ),
      );

      await pumpDetails(tester, matches: matches, communities: communities);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      // The existing dialog, reached without a round trip that would be
      // refused: the policy travelled with the context.
      expect(find.text('Join code'), findsOneWidget);
      expect(communities.joinedCommunityId, isNull);
    });

    testWidgets('a refused join leaves the membership notice up',
        (tester) async {
      final communities = FakeCommunityAdapter(
        joinFailure: const InfrastructureFailure(),
      );
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: outsiderContext,
      );

      await pumpDetails(tester, matches: matches, communities: communities);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Join the community first'), findsOneWidget);
      expect(find.text('Friday Night'), findsNothing);
    });
  });

  group('a genuine loading failure', () {
    testWidgets('a dropped connection is still reported as one',
        (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NetworkFailure(),
        access: outsiderContext,
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Join the community first'), findsNothing);
      expect(matches.accessReads, 0,
          reason: 'a transport failure says nothing about membership, so the '
              'question is not asked');
    });

    testWidgets('a database fault is reported as one', (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const InfrastructureFailure(),
        access: outsiderContext,
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(matches.accessReads, 0);
    });

    testWidgets('a missing match is an error, not an invitation to join',
        (tester) async {
      // The id names nothing. There is no community to join, so the reader gets
      // the failure they always got.
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        access: const MatchAccessContext(matchExists: false, isMember: false),
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Join the community first'), findsNothing);
    });

    testWidgets('a follow-up question that itself fails changes nothing',
        (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        readFailure: const NotFoundFailure(),
        accessFailure: const NetworkFailure(),
      );
      await pumpDetails(tester, matches: matches, role: null);

      expect(find.byType(ErrorState), findsOneWidget,
          reason: 'the original failure stands');
    });
  });
}

// --- Fake ports -------------------------------------------------------------

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    required this.match,
    this.readFailure,
    this.access,
    this.accessFailure,
    this.registrations = const [],
  });

  final Match match;
  final List<MatchRegistration> registrations;

  /// What the match read does. Cleared by a successful join, which is how the
  /// policy behaves: the row becomes readable the moment the membership exists.
  Failure? readFailure;
  MatchAccessContext? access;
  final Failure? accessFailure;

  int accessReads = 0;
  int registrationReads = 0;

  @override
  Future<Match> fetchMatch(String matchId) async {
    if (readFailure != null) throw readFailure!;
    return match;
  }

  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) async {
    accessReads++;
    if (accessFailure != null) throw accessFailure!;
    return access ??
        const MatchAccessContext(matchExists: false, isMember: false);
  }

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async {
    registrationReads++;
    return registrations;
  }

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchUpcomingMatches() => throw UnimplementedError();

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMatch(String matchId) => throw UnimplementedError();

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      throw UnimplementedError();

  @override
  Future<void> withdrawFromMatch(String matchId) => throw UnimplementedError();

  @override
  Future<void> removePlayer(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<String> addProfessionalGuest(String matchId, String name) =>
      throw UnimplementedError();

  @override
  Future<void> removeProfessionalGuest(String matchId, String guestId) =>
      throw UnimplementedError();

  @override
  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) =>
      throw UnimplementedError();

  @override
  Future<int?> fetchReservePlayers() => throw UnimplementedError();
}

class FakeMemberAdapter implements MemberAdapter {
  FakeMemberAdapter({this.role});

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      const [];

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();

  @override
  Future<void> removeMember(String communityId, String userId) =>
      throw UnimplementedError();
}

/// A signed-in session, which is all this screen asks of identity: whose
/// registration is whose.
class _StubAuthAdapter implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => 'u1';

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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}

class FakeCommunityAdapter implements CommunityAdapter {
  FakeCommunityAdapter({this.joinFailure});

  final Failure? joinFailure;

  /// Run when a join succeeds, so a test can make the match readable the way a
  /// real membership does.
  void Function()? onJoin;

  String? joinedCommunityId;

  @override
  Future<String> joinCommunity(String communityId) async {
    if (joinFailure != null) throw joinFailure!;
    joinedCommunityId = communityId;
    onJoin?.call();
    return communityId;
  }

  @override
  Future<String> joinCommunityByCode(String code) => throw UnimplementedError();

  @override
  Future<List<Community>> fetchMyCommunities() => throw UnimplementedError();

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
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
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
}
