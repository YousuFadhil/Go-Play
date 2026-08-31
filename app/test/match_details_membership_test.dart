import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/football_components.dart';
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
import 'package:go_play/features/profile/player_identity.dart';
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
    bool signedIn = true,
    Size size = const Size(900, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MatchDetailsScreen(
        // A fresh key per pump. Without it a second `pumpDetails` in the same
        // test lands on the same element, Flutter updates the existing State
        // instead of creating one, and the screen keeps the match and the role
        // it loaded the first time — so the assertion reads the previous
        // screen rather than the one just asked for.
        key: UniqueKey(),
        matchId: 'm1',
        matchService: MatchService(matches),
        memberRepository: MemberRepository(FakeMemberAdapter(role: role)),
        communityRepository:
            CommunityRepository(communities ?? FakeCommunityAdapter()),
        authService: AuthService(_StubAuthAdapter(signedIn: signedIn)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('Club Match Details presentation', () {
    testWidgets('uses the Club hero and sheet for a long English title at 320px',
        (tester) async {
      const title =
          'Friday Night Championship Match at Al Amerat Football Complex';
      final longTitleMatch = Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u9',
        location: 'Al Amerat Pitch',
        startAt: kickOff,
        endAt: kickOff.add(const Duration(hours: 2)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: MatchStatus.open,
        title: title,
      );
      await pumpDetails(
        tester,
        matches: FakeMatchAdapter(match: longTitleMatch, access: memberContext),
        size: const Size(320, 700),
      );

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(
        tester.widget<GoStatusChip>(find.byType(GoStatusChip)).tone,
        GoChipTone.open,
      );
      final titleWidget = tester.widget<Text>(find.text(title));
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a long Arabic title bounded at 320px RTL', (tester) async {
      const title =
          'مباراة بطولة مساء الجمعة في مجمع العامرات لكرة القدم للمحترفين';
      final arabicTitleMatch = Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u9',
        location: 'ملعب العامرات الرئيسي لكرة القدم',
        startAt: kickOff,
        endAt: kickOff.add(const Duration(hours: 2)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: MatchStatus.open,
        title: title,
      );
      await pumpDetails(
        tester,
        matches: FakeMatchAdapter(match: arabicTitleMatch, access: memberContext),
        locale: const Locale('ar'),
        size: const Size(320, 700),
      );

      final titleWidget = tester.widget<Text>(find.text(title));
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('maps full and completed matches through the Club status presentation',
        (tester) async {
      final fullMatch = Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u9',
        location: 'Al Amerat Pitch',
        startAt: kickOff,
        endAt: kickOff.add(const Duration(hours: 2)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: MatchStatus.full,
        title: 'Full match',
      );
      await pumpDetails(
        tester,
        matches: FakeMatchAdapter(match: fullMatch, access: memberContext),
      );
      expect(
        tester.widget<GoStatusChip>(find.byType(GoStatusChip)).tone,
        GoChipTone.full,
      );

      final completedMatch = Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u9',
        location: 'Al Amerat Pitch',
        startAt: DateTime.now().subtract(const Duration(hours: 3)),
        endAt: DateTime.now().subtract(const Duration(hours: 1)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: MatchStatus.open,
        title: 'Completed match',
      );
      await pumpDetails(
        tester,
        matches: FakeMatchAdapter(match: completedMatch, access: memberContext),
      );
      expect(
        tester.widget<GoStatusChip>(find.byType(GoStatusChip)).tone,
        GoChipTone.completed,
      );
    });

    testWidgets('keeps organizer controls gated by the existing community role',
        (tester) async {
      final matches = FakeMatchAdapter(match: match, access: memberContext);
      await pumpDetails(tester, matches: matches, role: CommunityRole.player);
      expect(find.text('Match management'), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Teams'))
            .onTap,
        isNotNull,
      );

      await pumpDetails(tester, matches: matches, role: CommunityRole.admin);
      expect(find.text('Match management'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Match management'),
            )
            .onTap,
        isNotNull,
      );
    });
  });

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

    testWidgets('a player on the roster is a face, a name and a way into '
        'their profile', (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: const [
          MatchRegistration(
            registrationId: 'reg-u1',
            userId: 'u1',
            fullName: 'Yousuf Al Amri',
            position: 'MID',
            status: RegistrationStatus.confirmed,
            registrationOrder: 1,
            avatarUrl: 'https://example.test/u1.jpg',
          ),
          MatchRegistration(
            registrationId: 'reg-g1',
            professionalGuestId: 'g1',
            fullName: 'Ahmed',
            status: RegistrationStatus.confirmed,
            registrationOrder: 2,
          ),
        ],
      );
      await pumpDetails(tester, matches: matches);

      final avatars =
          tester.widgetList<PlayerAvatar>(find.byType(PlayerAvatar)).toList();
      expect(avatars, hasLength(2));
      expect(avatars.first.avatarUrl, 'https://example.test/u1.jpg');
      expect(avatars.last.isProfessionalGuest, isTrue);
      expect(avatars.last.avatarUrl, isNull,
          reason: 'a guest has no account, so no picture is theirs');

      // Nothing else claims a roster row here, so the row is the control — and
      // the guest's is not a control at all, because there is nothing to open.
      final tiles = tester
          .widgetList<ListTile>(find.ancestor(
            of: find.byType(PlayerAvatar),
            matching: find.byType(ListTile),
          ))
          .toList();
      expect(tiles.first.onTap, isNotNull);
      expect(tiles.last.onTap, isNull);
    });
  });

  group('whose registration is whose', () {
    // The guard these cover is one line in Match Details:
    //
    //   r.userId != null && r.userId == currentUserId
    //
    // Both halves matter. A Professional Guest's seat carries no account, and
    // so does a signed-out reader — without the null check the two would match
    // each other and a visitor would be shown a guest's place as their own,
    // with a Withdraw button for it. Extracting the registration card must not
    // move this decision, so it is asserted through the screen.
    const guestSeat = MatchRegistration(
      registrationId: 'reg-g1',
      professionalGuestId: 'g1',
      fullName: 'Ahmed',
      status: RegistrationStatus.confirmed,
      registrationOrder: 1,
    );

    testWidgets('a signed-out reader is given no place of their own',
        (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: const [guestSeat],
      );
      await pumpDetails(tester, matches: matches, signedIn: false);

      expect(find.text('You are registered in this match.'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Join match'), findsOneWidget,
          reason: 'holding no registration is what they hold');
    });

    testWidgets('a signed-in player is given their own place', (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: const [
          guestSeat,
          MatchRegistration(
            registrationId: 'reg-u1',
            userId: 'u1',
            fullName: 'Yousuf Al Amri',
            position: 'MID',
            status: RegistrationStatus.confirmed,
            registrationOrder: 2,
          ),
        ],
      );
      await pumpDetails(tester, matches: matches);

      expect(find.text('You are registered in this match.'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Join match'), findsNothing);
    });

    testWidgets('a reserve place is reported as one', (tester) async {
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: const [
          MatchRegistration(
            registrationId: 'reg-u1',
            userId: 'u1',
            fullName: 'Yousuf Al Amri',
            position: 'MID',
            status: RegistrationStatus.reserve,
            registrationOrder: 11,
          ),
        ],
      );
      await pumpDetails(tester, matches: matches);

      expect(find.text('You are on the reserve list.'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets('the cap closes registration for a reader holding no place',
        (tester) async {
      // `registrations.length >= match.maxRegistration` — the match takes 16
      // and 16 are in it.
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: [
          for (var i = 0; i < 16; i++)
            MatchRegistration(
              registrationId: 'reg-$i',
              userId: 'other-$i',
              fullName: 'Player $i',
              position: 'MID',
              status: i < 10
                  ? RegistrationStatus.confirmed
                  : RegistrationStatus.reserve,
              registrationOrder: i + 1,
            ),
        ],
      );
      await pumpDetails(tester, matches: matches);

      expect(
        find.text('Registration is closed; the match reached its maximum.'),
        findsOneWidget,
      );
      expect(find.text('Join match'), findsNothing);
    });

    testWidgets('a full starting eleven still offers the reserve',
        (tester) async {
      // `confirmed.length >= match.startingPlayers`, but the cap is 16 and only
      // 10 are in — so joining is still offered, with the warning above it.
      final matches = FakeMatchAdapter(
        match: match,
        access: memberContext,
        registrations: [
          for (var i = 0; i < 10; i++)
            MatchRegistration(
              registrationId: 'reg-$i',
              userId: 'other-$i',
              fullName: 'Player $i',
              position: 'MID',
              status: RegistrationStatus.confirmed,
              registrationOrder: i + 1,
            ),
        ],
      );
      await pumpDetails(tester, matches: matches);

      expect(
        find.text('The match is full. Joining now adds you to the reserve '
            'list.'),
        findsOneWidget,
      );
      expect(find.text('Join match'), findsOneWidget);
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
    bool isHistorical = false,
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
  Future<void> setRosterOrder(String matchId, List<String> registrationIds) =>
      throw UnimplementedError();

  @override
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) =>
      throw UnimplementedError();

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
  _StubAuthAdapter({this.signedIn = true});

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
