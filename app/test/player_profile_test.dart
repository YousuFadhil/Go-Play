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
/// The rules themselves are the database's — `player_profile` (migrations `0043`
/// and `0056`) decides what a football profile carries, and
/// `test/integration/profile_visibility_test.dart` proves that against a real
/// project. What is asserted here is everything above it: that the application
/// asks through the one authorized path, that a refusal is worded rather than
/// reported as a broken read, that a profile carries no contact detail because
/// the model has nowhere to put one, and that the two settings the boundary
/// retired are no longer offered.
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

  /// A football profile, which is all another player's record is.
  ///
  /// There is no date of birth to pass: migration `0056` took it out of
  /// `player_profile` altogether, so [PlayerProfileView] has nowhere to carry
  /// one and no test can construct a profile that leaks an age.
  PlayerProfileView viewOf({
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

    testWidgets("never shows an age on another player's profile",
        (tester) async {
      // A date of birth is account data and does not leave the database for
      // anybody but its owner (migration `0056`), so there is no age to draw
      // here — not a hidden one, not a withheld one, none.
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

  group('the settings the boundary retired', () {
    // Settings used to carry two controls: "who may open my profile" and "show
    // my age". Migration `0056` ended both disclosures they governed — a
    // football profile is readable by every signed-in player, and no date of
    // birth leaves the database for anybody but its owner — so a control that
    // still offered the choice would be stating something untrue about the
    // database. It is gone, and this is what says so.
    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsScreen(),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no profile-visibility choice is offered', (tester) async {
      await pumpSettings(tester);

      expect(find.byType(RadioListTile<ProfileVisibility>), findsNothing);
      expect(find.text('Everyone'), findsNothing);
      expect(find.text('Community members only'), findsNothing);
    });

    testWidgets('no age-visibility switch is offered', (tester) async {
      await pumpSettings(tester);

      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('and the Privacy section itself is gone', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Privacy'), findsNothing,
          reason: 'an empty section heading is still a claim');
      // The rest of Settings is untouched, which is the other half of the rule:
      // only the affected controls were removed.
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('and Settings reads no account data at all', (tester) async {
      // The screen no longer needs a profile to render, so it no longer asks
      // for one. Passing an adapter that fails every read proves it: the screen
      // still builds.
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final profiles = FakeProfileAdapter(
        readFailure: const InfrastructureFailure(),
      );
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsScreen(profileRepository: ProfileRepository(profiles)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);
      expect(profiles.readCount, 0);
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

    test('reads the football profile the function returns', () {
      final view = playerProfileViewFromRow(const {
        'user_id': 'u2',
        'full_name': 'Noor Al Kindi',
        'primary_position': 'MID',
        'secondary_position': null,
        'overall_rating': 6.4,
        'matches_played': 3,
        'wins': 1,
        'losses': 1,
        'draws': 1,
        'goals': 2,
        'mvp_count': 0,
        'is_self': false,
      });

      expect(view.userId, 'u2');
      expect(view.fullName, 'Noor Al Kindi');
      expect(view.primaryPosition, PlayerPosition.mid);
      expect(view.secondaryPosition, isNull);
      expect(view.statistics.matchesPlayed, 3);
      expect(view.statistics.goals, 2);
      expect(view.isSelf, isFalse);
    });

    test('carries nothing private, even when the row does', () {
      // The row below is deliberately wider than anything `player_profile` can
      // send: `0056` fixed its column list and none of these four is on it. The
      // point is that the mapper has nowhere to put them — `PlayerProfileView`
      // has no phone, no email, no auth identifier and no date of birth — so a
      // server that started returning them could not push them into the model.
      final born = bornYearsAgo(21);
      final view = playerProfileViewFromRow({
        'user_id': 'u2',
        'full_name': 'Noor Al Kindi',
        'primary_position': 'MID',
        'secondary_position': 'FWD',
        'overall_rating': 6.4,
        'matches_played': 0,
        'wins': 0,
        'losses': 0,
        'draws': 0,
        'goals': 0,
        'mvp_count': 0,
        'is_self': true,
        'phone': '+96890123456',
        'email': 'noor@example.com',
        'id': 'auth-identifier',
        'date_of_birth': '${born.year.toString().padLeft(4, '0')}-'
            '${born.month.toString().padLeft(2, '0')}-'
            '${born.day.toString().padLeft(2, '0')}',
      });

      expect(view.userId, 'u2');
      expect(view.isSelf, isTrue);
      expect(view.secondaryPosition, PlayerPosition.fwd);
      // Everything the model does carry is football data and nothing else. The
      // absence of the four keys above is enforced by the type, which is why
      // this test compiles rather than asserts.
      expect(view.fullName, 'Noor Al Kindi');
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
  group('the way back out of a profile', () {
    /// The profile as the shell opens it: the root of its own stack, with
    /// nothing beneath it to return to.
    Future<void> pumpAsRoot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ProfileScreen(
          profileRepository:
              ProfileRepository(FakeProfileAdapter(player: viewOf())),
          resultRepository: ResultRepository(_FakeResultAdapter(stats())),
          communityRepository: CommunityRepository(_FakeCommunityAdapter()),
          authService: AuthService(_StubAuthAdapter()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// The profile as a name on a pitch opens it: pushed onto a stack that has
    /// somewhere to go back to.
    Future<void> pumpPushed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileScreen(
                      userId: 'u9',
                      profileRepository: ProfileRepository(
                          FakeProfileAdapter(player: viewOf())),
                      resultRepository:
                          ResultRepository(_FakeResultAdapter(stats())),
                      communityRepository:
                          CommunityRepository(_FakeCommunityAdapter()),
                      authService: AuthService(_StubAuthAdapter()),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a pushed profile offers Back', (tester) async {
      await pumpPushed(tester);

      expect(find.byType(BackButtonIcon), findsOneWidget);
    });

    testWidgets('tapping Back returns to where it was opened from',
        (tester) async {
      await pumpPushed(tester);
      expect(find.text('open'), findsNothing);

      await tester.tap(find.byType(BackButtonIcon));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget,
          reason: 'the arrow pops the route it was pushed onto');
    });

    testWidgets('a root profile shows no arrow at all', (tester) async {
      // An arrow that pops nothing is worse than no arrow: it looks like a way
      // out and is not one.
      await pumpAsRoot(tester);

      expect(find.byType(BackButtonIcon), findsNothing);
    });

    testWidgets('the profile keeps its own action either way', (tester) async {
      // Route awareness decides the back affordance and nothing else.
      await pumpAsRoot(tester);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
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
    this.readFailure,
  });

  final PlayerProfile profile;
  final PlayerProfileView? player;

  /// What the *other player's* read does.
  final Failure? failure;
  final Future<void>? gate;

  /// What the *owner's own* read does. Set by a test that needs to prove a
  /// screen never asks for it.
  final Failure? readFailure;

  /// How many times the owner's own profile was read.
  int readCount = 0;

  /// What the privacy write does. Settable, so a test can let the load succeed
  /// and then refuse the save.
  Failure? writeFailure;

  String? requestedUserId;
  ProfilePrivacy? savedPrivacy;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    readCount++;
    if (readFailure != null) throw readFailure!;
    return profile;
  }

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
  Future<String> fetchJoinCode(String communityId) async =>
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

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) =>
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
  Future<bool> isCurrentUserActive() async => true;

  @override
  Future<void> signOut() => throw UnimplementedError();
}
