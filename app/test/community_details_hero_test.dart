import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/features/communities/member_card.dart';
import 'package:go_play/features/matches/compact_match_card.dart';
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
    // A roster of the caller's own, for the tests that need more than two
    // people to see how the member grid lays them out.
    List<CommunityMember>? roster,
    // A port of the caller's own, for the tests that write through it.
    _FakeCommunityAdapter? adapter,
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
            CommunityRepository(adapter ?? _FakeCommunityAdapter(which)),
        memberRepository: MemberRepository(
          _FakeMemberAdapter(members: roster ?? members, role: role),
        ),
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
    testWidgets('three tabs: matches, members, statistics', (tester) async {
      // Four became three. The Dashboard and the Leaderboards were one subject
      // split across two destinations, each with its own period and its own
      // Share action; they are one Statistics tab now.
      await pumpCommunity(tester);

      expect(find.byType(Tab), findsNWidgets(3));
      for (final label in ['Matches', 'Members', 'Statistics']) {
        expect(find.widgetWithText(Tab, label), findsOneWidget);
      }
      expect(find.widgetWithText(Tab, 'Dashboard'), findsNothing);
      expect(find.widgetWithText(Tab, 'Leaderboards'), findsNothing);
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
      expect(find.byType(Tab), findsNWidgets(3));
    });
  });

  group("the community's picture", () {
    const withLogo = Community(
      id: 'c1',
      ownerId: 'u9',
      name: 'Al Amerat FC',
      description: 'Friday football in Al Amerat.',
      joinPolicy: JoinPolicy.open,
      logoUrl: 'https://example.test/community-logos/c1/logo-7.png',
    );

    /// Opens the actions sheet, which is where the two controls live.
    Future<void> openActions(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('the hero draws it where the initials were', (tester) async {
      await pumpCommunity(tester, which: withLogo);

      final crest = tester.widget<CommunityCrest>(find.byType(CommunityCrest));
      expect(crest.logoUrl, withLogo.logoUrl);
    });

    testWidgets('and the initials where there is none', (tester) async {
      await pumpCommunity(tester);

      final crest = tester.widget<CommunityCrest>(find.byType(CommunityCrest));
      expect(crest.logoUrl, isNull);
      expect(find.text('AA'), findsWidgets);
    });

    testWidgets('an owner may change it', (tester) async {
      await pumpCommunity(tester, role: CommunityRole.owner);
      await openActions(tester);

      expect(find.byKey(const Key('communityChangeLogo')), findsOneWidget);
    });

    testWidgets('an admin may change it too', (tester) async {
      // The reason `set_community_logo` exists: an admin gets this without
      // being handed generic community UPDATE.
      await pumpCommunity(tester, role: CommunityRole.admin);
      await openActions(tester);

      expect(find.byKey(const Key('communityChangeLogo')), findsOneWidget);
    });

    testWidgets('a player is offered neither control', (tester) async {
      // Absent, not disabled — and the server refuses them regardless: this
      // gating is convenience, and the function and the storage policies are
      // the security.
      await pumpCommunity(tester, which: withLogo, role: CommunityRole.player);
      await openActions(tester);

      expect(find.byKey(const Key('communityChangeLogo')), findsNothing);
      expect(find.byKey(const Key('communityRemoveLogo')), findsNothing);
    });

    testWidgets('remove is not offered when there is nothing to remove',
        (tester) async {
      // A row that clears something already empty is a row that does nothing.
      await pumpCommunity(tester, role: CommunityRole.owner);
      await openActions(tester);

      expect(find.byKey(const Key('communityChangeLogo')), findsOneWidget);
      expect(find.byKey(const Key('communityRemoveLogo')), findsNothing);
    });

    testWidgets('and is offered when there is', (tester) async {
      await pumpCommunity(tester, which: withLogo, role: CommunityRole.owner);
      await openActions(tester);

      expect(find.byKey(const Key('communityRemoveLogo')), findsOneWidget);
    });

    testWidgets('removing it returns the community to its initials',
        (tester) async {
      final adapter = _FakeCommunityAdapter(withLogo);
      await pumpCommunity(
        tester,
        which: withLogo,
        role: CommunityRole.owner,
        adapter: adapter,
      );
      await openActions(tester);

      await tester.tap(find.byKey(const Key('communityRemoveLogo')));
      await tester.pumpAndSettle();

      expect(adapter.logoWrites, [null]);
      // The screen reloaded, and the port now answers with no picture.
      final crest = tester.widget<CommunityCrest>(find.byType(CommunityCrest));
      expect(crest.logoUrl, isNull);
      expect(find.text('AA'), findsWidgets);
    });

    testWidgets('a refusal leaves the picture it had', (tester) async {
      final adapter = _FakeCommunityAdapter(
        withLogo,
        setLogoFailure: const AuthorizationFailure(),
      );
      await pumpCommunity(
        tester,
        which: withLogo,
        role: CommunityRole.owner,
        adapter: adapter,
      );
      await openActions(tester);

      await tester.tap(find.byKey(const Key('communityRemoveLogo')));
      await tester.pumpAndSettle();

      final crest = tester.widget<CommunityCrest>(find.byType(CommunityCrest));
      expect(crest.logoUrl, withLogo.logoUrl,
          reason: 'a failed removal is not a community with no picture');
    });
  });

  group('the tabs lay their content out in a grid', () {
    /// How many cards share the topmost row.
    int columnsOf(WidgetTester tester, Finder cards) {
      final count = tester.widgetList(cards).length;
      expect(count, greaterThan(0), reason: 'nothing was rendered');
      var top = double.infinity;
      for (var i = 0; i < count; i++) {
        final dy = tester.getTopLeft(cards.at(i)).dy;
        if (dy < top) top = dy;
      }
      var first = 0;
      for (var i = 0; i < count; i++) {
        if ((tester.getTopLeft(cards.at(i)).dy - top).abs() < 0.5) first++;
      }
      return first;
    }

    List<CommunityMember> squad(int n) => [
          for (var i = 0; i < n; i++)
            CommunityMember(
              userId: 'u$i',
              fullName: 'Player Number $i',
              position: 'MID',
              role: i == 0 ? CommunityRole.owner : CommunityRole.player,
            ),
        ];

    testWidgets('matches sit two across, both the coming and the played',
        (tester) async {
      await pumpCommunity(tester);

      // The fixture carries one of each, and the two lists stay separate: a
      // plan and a record are different things to a member, so the played match
      // must not come up beside the coming one on a shared row.
      expect(find.byType(CompactMatchCard), findsNWidgets(2));
      expect(columnsOf(tester, find.byType(CompactMatchCard)), 1,
          reason: 'one upcoming and one played, in two sections');

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Last Sunday'), findsOneWidget);
      // `findsWidgets` and not `findsOneWidget`: each of these words the hero's
      // count as well as the section below it, and that was true before the
      // grid arrived.
      expect(find.text('Upcoming matches'), findsWidgets);
      expect(find.text('Completed matches'), findsWidgets);
    });

    testWidgets('members sit three across on a phone', (tester) async {
      await pumpCommunity(tester, roster: squad(6));
      await tester.tap(find.widgetWithText(Tab, 'Members'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 3);
    });

    testWidgets('and give up a column on a narrow one', (tester) async {
      // 320 wide leaves 292 to the cards, which is not enough for three.
      await pumpCommunity(
        tester,
        roster: squad(6),
        size: const Size(320, 900),
      );
      await tester.tap(find.widgetWithText(Tab, 'Members'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 2);
    });

    testWidgets('a role marker survives the move off the list row',
        (tester) async {
      await pumpCommunity(tester, roster: squad(6));
      await tester.tap(find.widgetWithText(Tab, 'Members'));
      await tester.pumpAndSettle();

      // One owner among six, exactly as the roster says — and no marker
      // invented for the five who are players.
      expect(find.text('OWNER'), findsOneWidget);
      expect(find.text('PLAYER'), findsNothing);
    });

    testWidgets('a long Arabic roster stays inside its cards', (tester) async {
      await pumpCommunity(
        tester,
        locale: const Locale('ar'),
        roster: const [
          CommunityMember(
            userId: 'u1',
            fullName: 'عبدالرحمن بن سليمان الحارثي',
            position: 'MID',
            role: CommunityRole.owner,
          ),
          CommunityMember(
            userId: 'u2',
            fullName: 'محمد بن عبدالله البلوشي',
            position: 'DEF',
            role: CommunityRole.player,
          ),
          CommunityMember(
            userId: 'u3',
            fullName: 'يوسف العامري',
            position: 'FWD',
            role: CommunityRole.player,
          ),
        ],
      );
      await tester.tap(find.widgetWithText(Tab, 'الأعضاء'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 3);
    });
  });
}

// --- Fake ports -------------------------------------------------------------

class _FakeCommunityAdapter implements CommunityAdapter {
  _FakeCommunityAdapter(this._community, {this.setLogoFailure});

  Community _community;

  /// What the port refuses with, where a test is about a refusal.
  final Failure? setLogoFailure;

  /// Every value written to `logo_url`, in order. Null is a reset.
  final List<String?> logoWrites = [];

  Community get community => _community;

  @override
  Future<Community> fetchCommunity(String communityId) async => _community;

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

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) async =>
      'https://example.test/community-logos/$communityId/logo-new.$fileExtension';

  /// Writes the column, so that the screen's reload sees what it just set —
  /// which is what makes "the crest went back to initials" a real assertion
  /// rather than a restated expectation.
  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) async {
    if (setLogoFailure != null) throw setLogoFailure!;
    logoWrites.add(logoUrl);
    _community = _community.withLogo(logoUrl);
  }

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) async {}
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
