import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/skeleton.dart';
import 'package:go_play/core/states.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_management_screen.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/settings/settings_screen.dart';
import 'package:go_play/features/statistics/player_statistics_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/profile_mapper.dart';

/// A player's profile, as another player sees it.
///
/// The rules themselves are the database's — `player_profile` (migration `0043`)
/// decides who may open a profile and withholds a hidden age at the source, and
/// `test/integration/profile_visibility_test.dart` proves that against a real
/// project. What is asserted here is everything above it: that the application
/// asks through the one authorized path, that a refusal is worded rather than
/// reported as a broken read, that a profile carries no contact detail because
/// the model has nowhere to put one, and that the two settings behind it are
/// where a player can reach them.
void main() {
  PlayerStatistics stats({
    int played = 12,
    int wins = 7,
    double rating = 6.4,
  }) =>
      PlayerStatistics(
        userId: 'u2',
        matchesPlayed: played,
        wins: wins,
        losses: 3,
        draws: 2,
        goals: 9,
        mvpCount: 1,
        currentRating: rating,
      );

  PlayerProfileView viewOf({
    DateTime? dateOfBirth,
    bool isSelf = false,
    String fullName = 'Noor Al Kindi',
  }) =>
      PlayerProfileView(
        userId: 'u2',
        fullName: fullName,
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: PlayerPosition.fwd,
        statistics: stats(),
        isSelf: isSelf,
        dateOfBirth: dateOfBirth,
      );

  /// The signed-in player's own record, which is the reading of this screen
  /// that carries the account's controls.
  PlayerProfile ownProfile() => const PlayerProfile(
        fullName: 'Salim Al Harthy',
        phone: '+96890123456',
        primaryPosition: PlayerPosition.def,
      );

  /// A date of birth that is exactly [years] old today, so the derived age is
  /// the same figure whenever the suite runs.
  DateTime bornYearsAgo(int years) {
    final now = DateTime.now();
    return DateTime(now.year - years, now.month, now.day);
  }

  Future<void> pumpPlayerProfile(
    WidgetTester tester, {
    required FakeProfileAdapter profiles,
    String? userId = 'u2',
    Locale locale = const Locale('en'),
    Size size = const Size(900, 2000),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ProfileScreen(
        userId: userId,
        profileRepository: ProfileRepository(profiles),
        resultRepository: ResultRepository(_FakeResultAdapter(stats())),
        communityRepository: CommunityRepository(_FakeCommunityAdapter()),
        authService: AuthService(_StubAuthAdapter()),
      ),
    ));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  group('opening another player', () {
    testWidgets('shows their record, read through the one authorized path',
        (tester) async {
      final profiles = FakeProfileAdapter(player: viewOf());
      await pumpPlayerProfile(
        tester,
        profiles: profiles,
        size: const Size(412, 900),
      );

      expect(profiles.requestedUserId, 'u2');
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(find.text('Player profile'), findsOneWidget);
      expect(find.text('Noor Al Kindi'), findsOneWidget);
      expect(find.text('Midfielder'), findsOneWidget);
      expect(find.text('6.4'), findsOneWidget);
      expect(find.text('12'), findsOneWidget, reason: 'matches played');
    });

    testWidgets('long English names remain safe at 320 pixels',
        (tester) async {
      final name =
          'Alexanderson Montgomery-Wellington the Third of Al Amerat';
      await pumpPlayerProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf(fullName: name)),
        size: const Size(320, 800),
      );

      expect(find.text(name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long Arabic names remain safe at 320 pixels in RTL',
        (tester) async {
      final name = 'عبدالرحمن بن محمد بن عبدالله السالمي الطويل جداً';
      await pumpPlayerProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf(fullName: name)),
        locale: const Locale('ar'),
        size: const Size(320, 800),
      );

      expect(find.text(name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the profile skeleton remains while data is loading',
        (tester) async {
      final gate = Completer<void>();
      await pumpPlayerProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf(), gate: gate.future),
        settle: false,
      );

      expect(find.byType(SkeletonFade), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ClubHero), findsOneWidget);
    });

    testWidgets('carries no phone number, email or identifier', (tester) async {
      final profiles = FakeProfileAdapter(player: viewOf());
      await pumpPlayerProfile(tester, profiles: profiles);

      // Nothing to assert about a field that does not exist, so what is checked
      // is that none of it reached the screen by another route.
      expect(find.textContaining('+968'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('u2'), findsNothing);
      expect(find.text('Phone number'), findsNothing);
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('offers none of the account\'s own controls', (tester) async {
      final profiles = FakeProfileAdapter(player: viewOf());
      await pumpPlayerProfile(tester, profiles: profiles);

      expect(find.text('Edit profile'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Log out'), findsNothing);
      // How many communities somebody else is in is not part of what they
      // publish, so the card is absent rather than empty.
      expect(find.text('Communities'), findsNothing);
    });

    testWidgets('shows the age when the player has left it visible',
        (tester) async {
      final profiles = FakeProfileAdapter(
        player: viewOf(dateOfBirth: bornYearsAgo(29)),
      );
      await pumpPlayerProfile(tester, profiles: profiles);

      expect(find.text('29 years old'), findsOneWidget);
    });

    testWidgets('shows no age when the player has hidden it', (tester) async {
      // A hidden age arrives as no date of birth at all — the value never left
      // the database — so there is nothing here to withhold.
      final profiles = FakeProfileAdapter(player: viewOf());
      await pumpPlayerProfile(tester, profiles: profiles);

      expect(find.textContaining('years old'), findsNothing);
      expect(find.text('Noor Al Kindi'), findsOneWidget,
          reason: 'the rest of the profile is unaffected');
    });
  });

  group('a profile the viewer may not open', () {
    testWidgets('is worded, not reported as a failed read', (tester) async {
      final profiles = FakeProfileAdapter(
        failure: const AuthorizationFailure(FailureReason.profileNotVisible),
      );
      await pumpPlayerProfile(tester, profiles: profiles);

      expect(find.text('Profile not available'), findsOneWidget);
      expect(
        find.text('This player shares their profile with their community '
            'members only.'),
        findsOneWidget,
      );
      // A retry would fail exactly the same way, so none is offered.
      expect(find.byType(ErrorState), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a genuine failure still offers the retry', (tester) async {
      final profiles = FakeProfileAdapter(failure: const NetworkFailure());
      await pumpPlayerProfile(tester, profiles: profiles);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Profile not available'), findsNothing);
    });

    testWidgets('Arabic says it in Arabic', (tester) async {
      final profiles = FakeProfileAdapter(
        failure: const AuthorizationFailure(FailureReason.profileNotVisible),
      );
      await pumpPlayerProfile(
        tester,
        profiles: profiles,
        locale: const Locale('ar'),
      );

      expect(find.text('الملف غير متاح'), findsOneWidget);
    });
  });

  group('the player looking at themselves', () {
    testWidgets('their own record keeps the controls and shows their age',
        (tester) async {
      // The owner always sees their own age, whatever they have set for
      // everybody else: this is their own row, read through their own session.
      final profiles = FakeProfileAdapter(
        profile: PlayerProfile(
          fullName: 'Salim Al Harthy',
          phone: '+96890123456',
          primaryPosition: PlayerPosition.def,
          dateOfBirth: bornYearsAgo(34),
          privacy: const ProfilePrivacy(
            visibility: ProfileVisibility.communityMembersOnly,
            ageVisible: false,
          ),
        ),
      );
      await pumpPlayerProfile(
        tester,
        profiles: profiles,
        userId: null,
        size: const Size(480, 900),
      );

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Salim Al Harthy'), findsOneWidget);
      expect(find.text('34 years old'), findsOneWidget);
      expect(find.byTooltip('Edit profile'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
    });
  });

  group('the way in to Player Statistics', () {
    testWidgets('the player\'s own profile offers it', (tester) async {
      await pumpPlayerProfile(
        tester,
        profiles: FakeProfileAdapter(profile: ownProfile()),
        userId: null,
      );

      expect(
        find.widgetWithText(ListTile, 'My statistics'),
        findsOneWidget,
        reason: 'the only way into the screen, and the only way to share a '
            'card of it',
      );
    });

    testWidgets('tapping it opens Player Statistics for the signed-in player',
        (tester) async {
      final observer = _RouteRecorder();
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [observer],
        home: ProfileScreen(
          profileRepository:
              ProfileRepository(FakeProfileAdapter(profile: ownProfile())),
          resultRepository: ResultRepository(_FakeResultAdapter(stats())),
          communityRepository: CommunityRepository(_FakeCommunityAdapter()),
          authService: AuthService(_StubAuthAdapter()),
        ),
      ));
      await tester.pumpAndSettle();
      observer.pushed.clear();

      await tester.tap(find.widgetWithText(ListTile, 'My statistics'));

      // The route is read rather than built: the screen makes the production
      // repositories when nobody injects any, and this suite has no data
      // provider behind them.
      final screen = observer.pushed.single
          .builder(tester.element(find.byType(ProfileScreen)));
      expect(screen, isA<PlayerStatisticsScreen>());
      // Null is the signed-in player, which is the identity this branch of the
      // profile already knows it is showing. A userId read here would be a
      // second answer to a question the session settles.
      expect((screen as PlayerStatisticsScreen).userId, isNull);
      observer.discard();
    });

    testWidgets('somebody else\'s profile does not', (tester) async {
      // The screen it opens is the signed-in player's record, so offering it
      // on another player's profile would lead somewhere that is not them.
      await pumpPlayerProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
      );

      expect(find.widgetWithText(ListTile, 'My statistics'), findsNothing);
    });
  });

  group('the way in, from a community roster', () {
    testWidgets('tapping a member opens their profile', (tester) async {
      final profiles = FakeProfileAdapter(player: viewOf());
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MemberManagementScreen(
          communityId: 'c1',
          communityName: 'Al Amerat FC',
          memberRepository: MemberRepository(_FakeMemberAdapter()),
          authService: AuthService(_StubAuthAdapter()),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Noor Al Kindi'));
      await tester.pumpAndSettle();

      // The existing profile screen, told whose record to read. What it then
      // shows is that screen's business and is asserted above; what is pinned
      // here is that the roster is the way in and that it names the right
      // player.
      final pushed = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
      expect(pushed.userId, 'u2');
      expect(profiles.requestedUserId, isNull,
          reason: 'the pushed screen builds its own port, as it does in '
              'production');
    });
  });

  group('the two settings behind it', () {
    Future<FakeProfileAdapter> pumpSettings(
      WidgetTester tester, {
      ProfilePrivacy privacy = const ProfilePrivacy.defaults(),
    }) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final profiles = FakeProfileAdapter(
        profile: PlayerProfile(
          fullName: 'Salim Al Harthy',
          phone: '+96890123456',
          primaryPosition: PlayerPosition.mid,
          privacy: privacy,
        ),
      );
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsScreen(profileRepository: ProfileRepository(profiles)),
      ));
      await tester.pumpAndSettle();
      return profiles;
    }

    testWidgets('a profile that has never been configured opens on Everyone',
        (tester) async {
      await pumpSettings(tester);

      final selected = tester
          .widgetList<RadioListTile<ProfileVisibility>>(
              find.byType(RadioListTile<ProfileVisibility>))
          .where((tile) => tile.value == ProfileVisibility.everyone);
      expect(selected, hasLength(1));
      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Community members only'), findsOneWidget);
    });

    testWidgets('the age is shown by default', (tester) async {
      await pumpSettings(tester);

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isTrue);
      expect(find.text('Show my age'), findsOneWidget);
    });

    testWidgets('choosing community members only is written', (tester) async {
      final profiles = await pumpSettings(tester);

      await tester.tap(find.text('Community members only'));
      await tester.pumpAndSettle();

      expect(profiles.savedPrivacy?.visibility,
          ProfileVisibility.communityMembersOnly);
      expect(profiles.savedPrivacy?.ageVisible, isTrue,
          reason: 'one setting at a time; the other is left as it was');
    });

    testWidgets('hiding the age is written', (tester) async {
      final profiles = await pumpSettings(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(profiles.savedPrivacy?.ageVisible, isFalse);
      expect(profiles.savedPrivacy?.visibility, ProfileVisibility.everyone);
    });

    testWidgets('a stored setting is the one shown back', (tester) async {
      await pumpSettings(
        tester,
        privacy: const ProfilePrivacy(
          visibility: ProfileVisibility.communityMembersOnly,
          ageVisible: false,
        ),
      );

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
    });

    testWidgets('a refused write puts the previous answer back',
        (tester) async {
      final profiles = await pumpSettings(tester);
      profiles.writeFailure = const InfrastructureFailure();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isTrue,
          reason: 'the screen must not show a setting the database refused');
      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
    });
  });

  group('the row, read', () {
    test('an unset visibility reads as everyone', () {
      expect(profileVisibilityFromDb(null), ProfileVisibility.everyone);
      expect(profileVisibilityFromDb('EVERYONE'), ProfileVisibility.everyone);
      expect(profileVisibilityFromDb('COMMUNITY_MEMBERS'),
          ProfileVisibility.communityMembersOnly);
    });

    test('the two columns a privacy write touches, and no others', () {
      final row = privacyUpdateToRow(const ProfilePrivacy(
        visibility: ProfileVisibility.communityMembersOnly,
        ageVisible: false,
      ));

      expect(row, {
        'profile_visibility': 'COMMUNITY_MEMBERS',
        'age_visible': false,
      });
    });

    test('a row with no date of birth derives no age', () {
      final view = playerProfileViewFromRow(const {
        'user_id': 'u2',
        'full_name': 'Noor Al Kindi',
        'primary_position': 'MID',
        'secondary_position': null,
        'date_of_birth': null,
        'overall_rating': 6.4,
        'matches_played': 3,
        'wins': 1,
        'losses': 1,
        'draws': 1,
        'goals': 2,
        'mvp_count': 0,
        'is_self': false,
      });

      expect(view.dateOfBirth, isNull);
      expect(view.age, isNull);
      expect(view.fullName, 'Noor Al Kindi');
      expect(view.statistics.matchesPlayed, 3);
    });

    test('an age is derived from the date, never read as a number', () {
      final born = bornYearsAgo(21);
      final view = playerProfileViewFromRow({
        'user_id': 'u2',
        'full_name': 'Noor Al Kindi',
        'primary_position': 'MID',
        'secondary_position': 'FWD',
        'date_of_birth': '${born.year.toString().padLeft(4, '0')}-'
            '${born.month.toString().padLeft(2, '0')}-'
            '${born.day.toString().padLeft(2, '0')}',
        'overall_rating': 6.4,
        'matches_played': 0,
        'wins': 0,
        'losses': 0,
        'draws': 0,
        'goals': 0,
        'mvp_count': 0,
        'is_self': true,
      });

      expect(view.age, 21);
      expect(view.isSelf, isTrue);
      // The day before the birthday is still the previous year.
      expect(view.ageOn(born.add(const Duration(days: 1))), 0);
    });
  });

  group('the repository adds no rule of its own', () {
    test('the read is a straight pass-through', () async {
      final adapter = FakeProfileAdapter(player: viewOf());
      final read = await ProfileRepository(adapter).fetchPlayerProfile('u2');

      expect(adapter.requestedUserId, 'u2');
      expect(read.fullName, 'Noor Al Kindi');
    });

    test('a refusal travels untouched', () async {
      final adapter = FakeProfileAdapter(
        failure: const AuthorizationFailure(FailureReason.profileNotVisible),
      );

      await expectLater(
        ProfileRepository(adapter).fetchPlayerProfile('u2'),
        throwsA(isA<AuthorizationFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.profileNotVisible,
        )),
      );
    });
  });
}

// --- Fake ports -------------------------------------------------------------

class FakeProfileAdapter implements ProfileAdapter {
  FakeProfileAdapter({
    this.profile = const PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    ),
    this.player,
    this.failure,
    this.gate,
  });

  final PlayerProfile profile;
  final PlayerProfileView? player;

  /// What the *other player's* read does.
  final Failure? failure;
  final Future<void>? gate;

  /// What the privacy write does. Settable, so a test can let the load succeed
  /// and then refuse the save.
  Failure? writeFailure;

  String? requestedUserId;
  ProfilePrivacy? savedPrivacy;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile;

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) async {
    requestedUserId = userId;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return player!;
  }

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) async {
    if (writeFailure != null) throw writeFailure!;
    savedPrivacy = privacy;
  }

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
}

/// Records a pushed route without letting it build.
///
/// `PlayerStatisticsScreen` makes the production repositories when nobody
/// injects any, and this suite has no data provider behind them — so the route
/// is read for what it would build rather than built.
class _RouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}

class _FakeResultAdapter implements ResultAdapter {
  _FakeResultAdapter(this.statistics);

  final PlayerStatistics statistics;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async => statistics;

  @override
  Future<MatchResult?> fetchResult(String matchId) =>
      throw UnimplementedError();

  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) =>
      throw UnimplementedError();

  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) =>
      throw UnimplementedError();
}

class _FakeCommunityAdapter implements CommunityAdapter {
  @override
  Future<List<Community>> fetchMyCommunities() async => const [
        Community(
          id: 'c1',
          ownerId: 'u9',
          name: 'Al Amerat FC',
          joinPolicy: JoinPolicy.open,
          joinCode: '123456',
        ),
      ];

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
  Future<String> joinCommunityByCode(String code) => throw UnimplementedError();

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

class _FakeMemberAdapter implements MemberAdapter {
  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async =>
      CommunityRole.player;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      const [
        CommunityMember(
          userId: 'u2',
          fullName: 'Noor Al Kindi',
          position: 'MID',
          role: CommunityRole.player,
        ),
      ];

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
