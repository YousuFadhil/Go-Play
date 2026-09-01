import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_details_screen.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';

/// Community Details, wearing the Club direction.
///
/// The screen it replaced was an app bar with the community's name in it, a
/// scrolling tab strip and a floating button. What is asserted here is that the
/// hero arrived and that nothing the screen could already do left with the app
/// bar — four destinations, the organizer's actions gated exactly as they were,
/// and a name that shortens rather than shoving anything off the edge.
void main() {
  const community = Community(
    id: 'c1',
    ownerId: 'u9',
    name: 'Al Amerat FC',
    description: 'Friday football in Al Amerat.',
    joinPolicy: JoinPolicy.open,
  );

  const members = [
    CommunityMember(
      userId: 'u1',
      fullName: 'Yousuf Al Amri',
      position: 'MID',
      role: CommunityRole.owner,
    ),
    CommunityMember(
      userId: 'u2',
      fullName: 'Ahmed Al Balushi',
      position: 'DEF',
      role: CommunityRole.player,
    ),
  ];

  final kickOff = DateTime.now().add(const Duration(days: 2));
  final played = DateTime.now().subtract(const Duration(days: 5));

  final matches = [
    Match(
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
    ),
    Match(
      id: 'm2',
      communityId: 'c1',
      createdBy: 'u9',
      location: 'Al Amerat Pitch',
      startAt: played,
      endAt: played.add(const Duration(hours: 2)),
      startingPlayers: 10,
      maxRegistration: 16,
      status: MatchStatus.completed,
      title: 'Last Sunday',
    ),
  ];

  Future<void> pumpCommunity(
    WidgetTester tester, {
    Community which = community,
    CommunityRole? role = CommunityRole.player,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: CommunityDetailsScreen(
        communityId: 'c1',
        communityRepository:
            CommunityRepository(_FakeCommunityAdapter(which)),
        memberRepository:
            MemberRepository(_FakeMemberAdapter(members: members, role: role)),
        matchService: MatchService(_FakeMatchAdapter(matches)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the hero', () {
    testWidgets('renders, flat and deep green', (tester) async {
      await pumpCommunity(tester);

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);

      // Flat is the whole point: the direction has one gradient in the product
      // and the hero is not it.
      final ground = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(ClubHero),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(ground.color, GoColors.bgHero);
    });

    testWidgets('carries the crest, the name and the description',
        (tester) async {
      await pumpCommunity(tester);

      expect(find.byType(CommunityCrest), findsOneWidget);
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Friday football in Al Amerat.'), findsOneWidget);
    });

    testWidgets('the crest is the initials of the first two words',
        (tester) async {
      expect(CommunityCrest.initialsOf('Al Amerat FC'), 'AA');
      expect(CommunityCrest.initialsOf('  spaced   out  '), 'SO');
      expect(CommunityCrest.initialsOf(''), '');
    });

    testWidgets('reports counts the screen already holds', (tester) async {
      await pumpCommunity(tester);

      // Two members, one upcoming match, one played — no second read was made
      // to learn any of it.
      expect(find.byType(ClubHeroCount), findsNWidgets(3));
      final counts = tester
          .widgetList<ClubHeroCount>(find.byType(ClubHeroCount))
          .map((c) => c.value)
          .toList();
      expect(counts, [2, 1, 1]);
    });

    testWidgets('the sheet is not a draggable one', (tester) async {
      await pumpCommunity(tester);

      expect(find.byType(DraggableScrollableSheet), findsNothing);
    });
  });

  group('role presentation', () {
    testWidgets('an owner is marked as one', (tester) async {
      await pumpCommunity(tester, role: CommunityRole.owner);
      expect(find.text('OWNER'), findsOneWidget);
    });

    testWidgets('an admin is marked as one', (tester) async {
      await pumpCommunity(tester, role: CommunityRole.admin);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('a player wears no marker', (tester) async {
      // A badge every ordinary member carries is a badge for having done
      // nothing, and the direction gives them none.
      await pumpCommunity(tester, role: CommunityRole.player);
      expect(find.text('PLAYER'), findsNothing);
    });

    testWidgets('a visitor with no role wears none either', (tester) async {
      await pumpCommunity(tester, role: null);
      expect(find.text('OWNER'), findsNothing);
      expect(find.text('ADMIN'), findsNothing);
      expect(find.text('PLAYER'), findsNothing);
    });
  });

  group('organizer gating is unchanged', () {
    testWidgets('an owner is offered create and invite', (tester) async {
      await pumpCommunity(tester, role: CommunityRole.owner);

      expect(find.byKey(const Key('heroCreateMatch')), findsOneWidget);
      expect(find.byKey(const Key('heroInvite')), findsOneWidget);
    });

    testWidgets('an admin is offered both as well', (tester) async {
      await pumpCommunity(tester, role: CommunityRole.admin);

      expect(find.byKey(const Key('heroCreateMatch')), findsOneWidget);
      expect(find.byKey(const Key('heroInvite')), findsOneWidget);
    });

    testWidgets('a player is offered neither', (tester) async {
      // Absent, not disabled. A disabled control still advertises the feature
      // and implies the reader is the problem.
      await pumpCommunity(tester, role: CommunityRole.player);

      expect(find.byKey(const Key('heroCreateMatch')), findsNothing);
      expect(find.byKey(const Key('heroInvite')), findsNothing);
      expect(
        find.text(
          'Only the owner and admins can create matches in this community.',
        ),
        findsWidgets,
        reason: 'the existing explanation still stands in its place',
      );
    });

    testWidgets('the actions sheet is still reachable for everybody',
        (tester) async {
      await pumpCommunity(tester, role: CommunityRole.player);

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // A player's sheet: no invitation, no joining policy, no deletion.
      expect(find.text('Manage members'), findsOneWidget);
      expect(find.text('Share invitation'), findsNothing);
    });
  });

  group('destinations survive the redesign', () {
    testWidgets('all four tabs are still there', (tester) async {
      await pumpCommunity(tester);

      expect(find.byType(Tab), findsNWidgets(4));
      for (final label in ['Matches', 'Members', 'Dashboard', 'Leaderboards']) {
        expect(find.widgetWithText(Tab, label), findsOneWidget);
      }
    });

    testWidgets('the matches tab still lists the community matches',
        (tester) async {
      await pumpCommunity(tester);

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Last Sunday'), findsOneWidget);
    });

    testWidgets('the members tab is still reachable and still lists members',
        (tester) async {
      await pumpCommunity(tester);

      await tester.tap(find.widgetWithText(Tab, 'Members'));
      await tester.pumpAndSettle();

      expect(find.text('Yousuf Al Amri'), findsOneWidget);
      expect(find.text('Ahmed Al Balushi'), findsOneWidget);
    });
  });

  group('long names and Arabic', () {
    const longEnglish = Community(
      id: 'c1',
      ownerId: 'u9',
      name: 'The Extremely Long Community Name Football Association Of Muscat',
      description: 'A description that also runs on well past the hero width.',
      joinPolicy: JoinPolicy.open,
    );

    const longArabic = Community(
      id: 'c1',
      ownerId: 'u9',
      name: 'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات بمحافظة مسقط',
      description: 'مجتمع كرة قدم يلتقي كل يوم جمعة في ملعب العامرات الرئيسي.',
      joinPolicy: JoinPolicy.open,
    );

    testWidgets('a long English name truncates rather than overflowing',
        (tester) async {
      await pumpCommunity(
        tester,
        which: longEnglish,
        role: CommunityRole.owner,
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      final name = tester.widget<Text>(find.text(longEnglish.name));
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      // The marker it would otherwise have pushed off the edge.
      expect(find.text('OWNER'), findsOneWidget);
    });

    testWidgets('a long Arabic name behaves the same, right to left',
        (tester) async {
      await pumpCommunity(
        tester,
        which: longArabic,
        role: CommunityRole.owner,
        locale: const Locale('ar'),
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(ClubHero))),
        TextDirection.rtl,
      );
      final name = tester.widget<Text>(find.text(longArabic.name));
      expect(name.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the hero holds together at 320 with every control on it',
        (tester) async {
      await pumpCommunity(
        tester,
        which: longEnglish,
        role: CommunityRole.owner,
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('heroCreateMatch')), findsOneWidget);
      expect(find.byKey(const Key('heroInvite')), findsOneWidget);
      expect(find.byType(ClubHeroCount), findsNWidgets(3));
    });

    testWidgets('Arabic renders the screen in Arabic', (tester) async {
      await pumpCommunity(tester, locale: const Locale('ar'));

      expect(tester.takeException(), isNull);
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(4));
    });
  });
}

// --- Fake ports -------------------------------------------------------------

class _FakeCommunityAdapter implements CommunityAdapter {
  _FakeCommunityAdapter(this.community);

  final Community community;

  @override
  Future<Community> fetchCommunity(String communityId) async => community;

  @override
  Future<List<Community>> fetchMyCommunities() => throw UnimplementedError();

  @override
  Future<List<Community>> fetchAllCommunities() => throw UnimplementedError();

  @override
  Future<String> joinCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<String> joinCommunityByCode(String code) => throw UnimplementedError();

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
  Future<String> fetchJoinCode(String communityId) async {
    // Owner and admin are the only roles this screen asks on behalf of, and
    // both are entitled to the code (migration `0056`).
    fetchJoinCodeCalls.add(communityId);
    return '4213';
  }

  final fetchJoinCodeCalls = <String>[];

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

class _FakeMemberAdapter implements MemberAdapter {
  _FakeMemberAdapter({required this.members, this.role});

  final List<CommunityMember> members;
  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      members;

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

class _FakeMatchAdapter implements MatchAdapter {
  _FakeMatchAdapter(this.matches);

  final List<Match> matches;

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) async =>
      matches;

  @override
  Future<Match> fetchMatch(String matchId) => throw UnimplementedError();

  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) =>
      throw UnimplementedError();

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
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
