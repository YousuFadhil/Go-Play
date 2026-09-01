import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/register_screen.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';

/// The public entry experience: what a visitor can see, and where they are
/// stopped.
///
/// The two halves are asserted separately on purpose, because Sprint 1 is a
/// claim about both. Browsing has to work with no session at all — every read
/// behind these screens goes through `DiscoverAdapter`, and nothing here is
/// given an `AuthService` that says anyone is signed in. Taking part has to
/// stop, at every one of the actions the sprint names, and stop in the same
/// place rather than in five.
void main() {
  PublicCommunity community(
    String id,
    String name, {
    String? description = 'Weekly six-a-side',
    int members = 12,
    int upcoming = 2,
  }) =>
      PublicCommunity(
        id: id,
        name: name,
        description: description,
        memberCount: members,
        upcomingMatchCount: upcoming,
      );

  /// A fixed future date, so the formatted day is the same on every run.
  final start = DateTime(2027, 3, 6, 20, 0);

  PublicMatch match(
    String id, {
    String? title = 'Friday night five-a-side',
    String communityName = 'Muscat United',
    String location = 'Al Amerat Pitch 2',
    int openSlots = 4,
  }) =>
      PublicMatch(
        id: id,
        communityId: 'c1',
        communityName: communityName,
        location: location,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 10,
        openSlots: openSlots,
        title: title,
      );

  Future<void> pumpDiscover(
    WidgetTester tester, {
    List<PublicCommunity>? communities,
    List<PublicMatch>? matches,
    Object? failure,
    bool signedIn = false,
    PlayerProfile? profile,
    Locale locale = const Locale('en'),
    Size size = const Size(800, 2400),
    // Cycle 3: a signed-in Discover also reads football history and the
    // reader's own memberships. Supplied here so the screen never reaches the
    // real provider, exactly as the discover repository already is.
    List<CompletedMatch>? results,
    Object? footballFailure,
    List<String> joinedCommunityIds = const [],
  }) async {
    // The greeting reads the profile the session holds. Left null nothing is
    // loaded, which is the case the headline has to fall back for.
    CurrentUser.instance.useRepository(
      profile == null ? null : ProfileRepository(_StaticProfileAdapter(profile)),
    );
    addTearDown(() => CurrentUser.instance.useRepository(null));

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _FakeDiscoverAdapter(
      communities: communities ?? [community('c1', 'Muscat United')],
      matches: matches ?? [match('m1')],
      failure: failure,
    );

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: locale,
      home: DiscoverScreen(
        repository: DiscoverRepository(adapter),
        authService: AuthService(_StubAuthAdapter(signedIn: signedIn)),
        footballRepository: FootballRepository(
          _FakeFootballAdapter(
            results: results ?? const [],
            failure: footballFailure,
          ),
        ),
        communityRepository:
            CommunityRepository(_JoinedCommunitiesAdapter(joinedCommunityIds)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the app opens on something to look at', () {
    testWidgets('uses the frozen Club place presentation', (tester) async {
      await pumpDiscover(tester);

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(find.byType(CommunityCrest), findsOneWidget);
    });

    testWidgets('the banner names the product and offers an account',
        (tester) async {
      await pumpDiscover(tester);

      expect(find.text('Go Play'), findsOneWidget);
      expect(find.text('Football, with your people.'), findsOneWidget);
      // Twice: once in the banner, once in the closing call to action.
      expect(find.text('Create account'), findsNWidgets(2));
      // Sprint 2 made the second way in a real button beside the first rather
      // than a sentence under it, which is what took a row out of the banner.
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsOneWidget);
    });

    testWidgets('a guest sees the upcoming matches', (tester) async {
      await pumpDiscover(tester);

      expect(find.text('Friday night five-a-side'), findsOneWidget);
      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('Al Amerat Pitch 2'), findsOneWidget);
      expect(find.text('4 places left'), findsOneWidget);

      // Sprint 2 replaced the "Sat, Mar 6, 2027" line with a date tile, so the
      // day reads from across a scrolling list. Same fact, stacked.
      expect(find.text('SAT'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Mar'), findsOneWidget);
    });

    testWidgets('a full match says so instead of offering places',
        (tester) async {
      await pumpDiscover(tester, matches: [match('m1', openSlots: 0)]);

      expect(find.text('Full'), findsOneWidget);
      expect(find.textContaining('places left'), findsNothing);
    });

    testWidgets('a match with no title falls back to its location',
        (tester) async {
      await pumpDiscover(tester, matches: [match('m1', title: null)]);

      expect(find.text('Al Amerat Pitch 2'), findsWidgets);
    });

    testWidgets('every community is listed, whatever its policy',
        (tester) async {
      // The sprint is explicit that this list is not filtered. A community the
      // visitor cannot join without a code is still one they can see exists.
      await pumpDiscover(tester, communities: [
        community('c1', 'Muscat United'),
        community('c2', 'Seeb Strikers'),
        community('c3', 'Sohar FC'),
      ]);

      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('Seeb Strikers'), findsOneWidget);
      expect(find.text('Sohar FC'), findsOneWidget);
    });

    testWidgets('a community card carries its mark, size and schedule',
        (tester) async {
      await pumpDiscover(tester, communities: [
        community('c1', 'Muscat United', members: 24, upcoming: 3),
      ]);

      // The initials are the logo: there is no logo column, and this sprint
      // adds none.
      expect(find.text('MU'), findsOneWidget);
      expect(find.text('Weekly six-a-side'), findsOneWidget);
      expect(find.text('24 members'), findsOneWidget);
      expect(find.text('3 upcoming matches'), findsOneWidget);
    });

    testWidgets('nothing to browse is said, not shown as an error',
        (tester) async {
      await pumpDiscover(tester, communities: [], matches: []);

      expect(find.text('Nothing is scheduled just yet. Check back soon.'),
          findsOneWidget);
      expect(find.text('No communities yet. Be the first to start one.'),
          findsOneWidget);
      expect(find.text('Failed to load data.'), findsNothing);
    });

    testWidgets('a failed load still lets a visitor sign up', (tester) async {
      await pumpDiscover(tester, failure: StateError('offline'));

      expect(find.text('Failed to load data.'), findsOneWidget);
      // The banner and the closing ask survive: the product is describable
      // without a working connection.
      expect(find.text('Create account'), findsNWidgets(2));
    });
  });

  group('a guest may look but not take part', () {
    testWidgets('registering for a match asks for an account', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();

      expect(find.text('Account needed'), findsOneWidget);
      expect(find.text('Create an account to register for this match.'),
          findsOneWidget);
    });

    testWidgets('joining a community asks for an account', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to join this community.'),
          findsOneWidget);
    });

    testWidgets('creating a community asks for an account', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Create community'));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to start your own community.'),
          findsOneWidget);
    });

    testWidgets('the sheet leads to registration', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();
      // Scoped to the sheet: "Create account" is also on the page underneath it.
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(FilledButton, 'Create account'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('the sheet leads to signing in', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(OutlinedButton, 'Log in'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('the banner opens the forms directly', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Log in'));
      await tester.pumpAndSettle();

      // Straight to the form: somebody who says they have an account is not
      // asked whether they need one.
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('a guest may open a community', () {
    testWidgets('opening it is the card\'s named primary action',
        (tester) async {
      // Not a tappable card somebody has to guess at: the sprint's flow is
      // browse, open, then decide, so the step in the middle is a button with
      // a name on it.
      await pumpDiscover(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'View community'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicCommunityScreen), findsOneWidget);
    });

    testWidgets('the card opens the public community page', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Weekly six-a-side'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicCommunityScreen), findsOneWidget);
      // What it shows is the community and what it has scheduled.
      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('12 members'), findsOneWidget);
      expect(find.text('Friday night five-a-side'), findsOneWidget);
    });

    testWidgets('joining from that page still asks for an account',
        (tester) async {
      await pumpDiscover(tester);
      await tester.tap(find.text('Weekly six-a-side'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to join this community.'),
          findsOneWidget);
    });
  });

  group('a member gets the same page, addressed to them', () {
    const profile = PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    );

    testWidgets('the banner greets them instead of pitching', (tester) async {
      await pumpDiscover(tester, signedIn: true, profile: profile);
      // The profile is read asynchronously by the identity menu.
      await tester.pumpAndSettle();

      expect(find.text('Welcome back, Salim'), findsOneWidget);
      expect(find.text('Football, with your people.'), findsNothing);
      // Nobody who is signed in is asked to sign up, in either place.
      expect(find.text('Create account'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsNothing);
    });

    testWidgets('a profile that has not arrived is not greeted by name',
        (tester) async {
      // The fallback matters: a greeting addressed to nobody is worse than the
      // headline it replaced.
      await pumpDiscover(tester, signedIn: true);

      expect(find.text('Football, with your people.'), findsOneWidget);
      expect(find.textContaining('Welcome back'), findsNothing);
    });

    testWidgets('both asks become the one a member can act on', (tester) async {
      await pumpDiscover(tester, signedIn: true);

      // Banner and closing call to action.
      expect(find.text('Create community'), findsNWidgets(2));
      expect(find.text('Start something of your own'), findsOneWidget);
    });

    testWidgets('the actions lead somewhere instead of asking for an account',
        (tester) async {
      await pumpDiscover(tester, signedIn: true);

      expect(find.text('View match'), findsOneWidget);
      expect(find.text('Join match'), findsNothing);

      // No sheet: the gate is open, so a tap goes to the real screen. That
      // navigation reaches the production repositories and is exercised on a
      // device, not here — what this asserts is that the gate does not fire.
      expect(find.text('Account needed'), findsNothing);
    });

    testWidgets('the identity menu is reachable from the home screen',
        (tester) async {
      // Discover has no AppHeader to carry it, and it is now the first thing a
      // signed-in player sees — without this there is no way to their profile
      // or out of the session from the screen the app opens on.
      await pumpDiscover(tester, signedIn: true, profile: profile);
      await tester.pumpAndSettle();

      expect(find.byType(CurrentUserMenu), findsOneWidget);
    });
  });

  group('a community mark is the letter you would name it by', () {
    String initialsOf(String name) => community('c1', name).initials;

    test('a Latin name gives up to two initials', () {
      expect(initialsOf('Muscat United'), 'MU');
      expect(initialsOf('Seeb'), 'S');
      expect(initialsOf('Sohar Football Club'), 'SF');
    });

    test('the Arabic definite article is skipped', () {
      // Every club named "الـ..." reduced to the same mark before this, which
      // made half the page look identical.
      expect(initialsOf('البحر'), 'ب');
      expect(initialsOf('الشمال'), 'ش');
      expect(initialsOf('السلام'), 'س');
      expect(initialsOf('النصر'), 'ن');
    });

    test('a name without the article is untouched', () {
      expect(initialsOf('نجوم'), 'ن');
      expect(initialsOf('صحار'), 'ص');
    });

    test('the article is skipped per word, not once', () {
      expect(initialsOf('البحر الأزرق'), 'بأ');
    });

    test('a name that is only the article keeps its own letters', () {
      // The stem would be empty, so the skip does not apply and nothing
      // indexes past the end.
      expect(initialsOf('ال'), 'ا');
    });

    test('an empty name has no mark rather than a crash', () {
      expect(initialsOf('   '), '');
    });
  });

  group('the sections are titled, not numbered', () {
    testWidgets('no count is shown beside a section heading', (tester) async {
      // A bare "1" beside a heading read as a debugging marker on the device.
      // The cards below are the count.
      await pumpDiscover(
        tester,
        communities: [community('c1', 'Muscat United')],
        matches: [match('m1')],
      );

      expect(find.text('Upcoming matches'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
      // '1' would be the old match-section pill; '2' never applied here. The
      // banner still reports the totals in words.
      expect(find.text('1'), findsNothing);
      expect(find.text('1 upcoming match'), findsOneWidget);
    });
  });

  group('the banner reports what is on the platform', () {
    testWidgets('the live counts match the lists below it', (tester) async {
      await pumpDiscover(
        tester,
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Seeb Strikers'),
        ],
        matches: [match('m1'), match('m2'), match('m3')],
      );

      expect(find.text('2 communities'), findsOneWidget);
      // Once in the banner; the community cards carry their own counts.
      expect(find.text('3 upcoming matches'), findsWidgets);
    });

    testWidgets('nothing is claimed before the read comes back',
        (tester) async {
      await pumpDiscover(tester, failure: StateError('offline'));

      expect(find.textContaining('communities'), findsNothing);
    });
  });

  group('long content stays inside Club cards', () {
    testWidgets('long English community, title, and location are safe at 320',
        (tester) async {
      const communityName =
          'The Extremely Long Community Name Football Association Of Muscat';
      const matchTitle =
          'The Very Long Friday Evening Football Match Title For Every Player';
      const location =
          'The Extremely Long Al Amerat Football Ground Location Description';
      await pumpDiscover(
        tester,
        communities: [community('c1', communityName)],
        matches: [match('m1', title: matchTitle, location: location)],
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text(communityName)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(matchTitle)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(location)).overflow,
          TextOverflow.ellipsis);
    });

    testWidgets('long Arabic content is safe at 320 RTL', (tester) async {
      const communityName =
          'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات بمحافظة مسقط';
      const matchTitle =
          'مباراة كرة القدم المسائية الطويلة جداً لجميع لاعبي المجتمع';
      const location = 'ملعب العامرات الرئيسي لكرة القدم في محافظة مسقط';
      await pumpDiscover(
        tester,
        communities: [community('c1', communityName)],
        matches: [match('m1', title: matchTitle, location: location)],
        locale: const Locale('ar'),
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(ClubHero))),
        TextDirection.rtl,
      );
      expect(tester.widget<Text>(find.text(communityName)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(matchTitle)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(location)).overflow,
          TextOverflow.ellipsis);
    });
  });
}

/// Answers from memory, with no session anywhere in sight.
class _FakeDiscoverAdapter implements DiscoverAdapter {
  _FakeDiscoverAdapter({
    required this.communities,
    required this.matches,
    this.failure,
  });

  final List<PublicCommunity> communities;
  final List<PublicMatch> matches;

  /// Thrown by every read when set, which is how a visitor on a bad connection
  /// is reproduced.
  final Object? failure;

  @override
  Future<List<PublicCommunity>> fetchCommunities() async {
    if (failure != null) throw failure!;
    return communities;
  }

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async {
    if (failure != null) throw failure!;
    return communities.firstWhere((c) => c.id == communityId);
  }

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async {
    if (failure != null) throw failure!;
    if (communityId == null) return matches;
    return [
      for (final m in matches)
        if (m.communityId == communityId) m,
    ];
  }
}

/// Says whether somebody is signed in, and nothing else — every method that
/// would change that is out of this test's scope and says so.
class _StubAuthAdapter implements AuthAdapter {
  _StubAuthAdapter({required this.signedIn});

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) async =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async => throw UnimplementedError();
}

/// The profile the greeting reads, answered from memory.
class _StaticProfileAdapter implements ProfileAdapter {
  _StaticProfileAdapter(this.profile);

  final PlayerProfile profile;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile;

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeMyAvatar() => throw UnimplementedError();

  // Requirement 2 added two members to the port. Neither is reached from this
  // test, so both refuse rather than answer.
  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}


/// A football port that answers from a list, or refuses.
///
/// Only Discover's two signed-in reads are exercised here; the rest throw so a
/// screen that started calling them would say so rather than pass quietly.
class _FakeFootballAdapter implements FootballAdapter {
  _FakeFootballAdapter({this.results = const [], this.failure});

  final List<CompletedMatch> results;
  final Object? failure;
  var completedCalls = 0;

  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) async {
    completedCalls++;
    if (failure != null) throw failure!;
    return results;
  }

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) =>
      throw UnimplementedError();
  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) =>
      throw UnimplementedError();
  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) =>
      throw UnimplementedError();
  @override
  Future<CommunityFootballStats> fetchCommunityStats(String communityId) =>
      throw UnimplementedError();
  @override
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
          String communityId) =>
      throw UnimplementedError();
}

/// A community port that reports which communities the reader has joined, and
/// refuses everything else — Discover reads exactly one thing from it.
class _JoinedCommunitiesAdapter implements CommunityAdapter {
  _JoinedCommunitiesAdapter(this.joinedIds);

  final List<String> joinedIds;
  var myCommunitiesCalls = 0;

  @override
  Future<List<Community>> fetchMyCommunities() async {
    myCommunitiesCalls++;
    return [
      for (final id in joinedIds)
        Community(
          id: id,
          ownerId: 'owner',
          name: 'Joined $id',
          joinPolicy: JoinPolicy.open,
        ),
    ];
  }

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
  Future<String> joinCommunity(String communityId) =>
      throw UnimplementedError();
  @override
  Future<String> joinCommunityByCode(String code) =>
      throw UnimplementedError();
  @override
  Future<void> setJoinPolicy(String communityId,
          {required JoinPolicy joinPolicy}) =>
      throw UnimplementedError();
  @override
  Future<String> fetchJoinCode(String communityId) =>
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
