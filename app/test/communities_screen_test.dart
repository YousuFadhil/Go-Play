import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/states.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/communities/communities_screen.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';

void main() {
  const mine = Community(
    id: 'mine',
    ownerId: 'u1',
    name: 'Al Amerat Friday Football',
    description: 'Friday evening football.',
    joinPolicy: JoinPolicy.open,
  );
  const discover = Community(
    id: 'discover',
    ownerId: 'u2',
    name: 'Muscat Open Football Club',
    description: 'Open games every week.',
    joinPolicy: JoinPolicy.codeRequired,
  );

  Future<void> pumpCommunities(
    WidgetTester tester, {
    required CommunityRepository repository,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
    List<NavigatorObserver> observers = const [],
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observers,
        // A fresh key per pump: a second `pumpCommunities` in one test would
        // otherwise land on the same element and keep the future the screen
        // loaded the first time, so the new repository would never be read.
        home: CommunitiesScreen(
          key: UniqueKey(),
          communityRepository: repository,
        ),
      ),
    );
    // `LoadingState` is a `CircularProgressIndicator`, which never stops
    // animating, so a screen parked on it can be pumped but never settled.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  CommunityRepository repository({
    List<Community> my = const [mine],
    List<Community> all = const [mine, discover],
    Completer<List<Community>>? waitingForMyCommunities,
    Object? error,
  }) =>
      CommunityRepository(
        _FakeCommunityAdapter(
          my: my,
          all: all,
          waitingForMyCommunities: waitingForMyCommunities,
          error: error,
        ),
      );

  testWidgets('renders the Club hero, sheet, and community cards',
      (tester) async {
    await pumpCommunities(tester, repository: repository());

    expect(find.byType(ClubHero), findsOneWidget);
    expect(find.byType(ClubSheet), findsOneWidget);
    expect(find.byType(CommunityCrest), findsNWidgets(2));
    expect(find.text(mine.name), findsOneWidget);
    expect(find.text(discover.name), findsOneWidget);
  });

  testWidgets('carries exactly one way to the profile', (tester) async {
    // A shell screen: reached from the bottom bar, with no back button to leave
    // by. The Club redesign moved this screen off `AppHeader`, which appended
    // the identity for free, and nothing replaced it — so a player standing on
    // Communities had no way to their own profile, their settings or sign-out.
    //
    // Exactly one, not merely at least one: the invite action beside it must
    // not be joined by a second identity.
    CurrentUser.instance
        .useRepository(ProfileRepository(_StaticProfileAdapter()));
    addTearDown(() => CurrentUser.instance.useRepository(null));

    await pumpCommunities(tester, repository: repository());

    expect(find.byType(CurrentUserMenu), findsOneWidget);
  });

  testWidgets('community navigation remains available', (tester) async {
    final observer = _RouteRecorder();
    await pumpCommunities(
      tester,
      repository: repository(),
      observers: [observer],
    );

    await tester.tap(find.text(mine.name));
    await tester.pump();

    // The recorder sees the initial route too, so the tap is the second push.
    // The destination itself is not built here: given no injected repository
    // `CommunityDetailsScreen` reaches for the provider, and a tap has nothing
    // to hand it. What this test owns is that the tap navigates; what the
    // details screen renders is `community_details_hero_test`'s.
    expect(observer.pushed, hasLength(2));
  });

  testWidgets('create, join, and invitation entry points remain available',
      (tester) async {
    await pumpCommunities(tester, repository: repository());

    expect(find.byKey(const Key('communitiesCreate')), findsOneWidget);
    expect(find.byKey(const Key('communitiesJoin')), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('keeps loading, empty, and error states', (tester) async {
    final waiting = Completer<List<Community>>();
    await pumpCommunities(
      tester,
      // `all` is emptied too: the screen shows the empty state only when there
      // is nothing on either side, which is right — a member of nothing who
      // still has communities to discover is not looking at an empty product.
      repository: repository(waitingForMyCommunities: waiting, all: const []),
      settle: false,
    );
    expect(find.byType(LoadingState), findsOneWidget);

    waiting.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);

    await pumpCommunities(
      tester,
      repository: repository(error: StateError('offline')),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('long English names are safe at 320 pixels', (tester) async {
    const longName =
        'The Extremely Long Community Name Football Association Of Muscat';
    const longCommunity = Community(
      id: 'long',
      ownerId: 'u1',
      name: longName,
      description: 'An intentionally long community description.',
      joinPolicy: JoinPolicy.codeRequired,
    );
    await pumpCommunities(
      tester,
      repository: repository(my: const [longCommunity], all: const [longCommunity]),
      size: const Size(320, 900),
    );

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text(longName));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('long Arabic names are safe at 320 pixels RTL', (tester) async {
    const longName =
        'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات بمحافظة مسقط';
    const longCommunity = Community(
      id: 'arabic',
      ownerId: 'u1',
      name: longName,
      description: 'مجتمع كرة قدم يلتقي كل يوم جمعة في ملعب العامرات الرئيسي.',
      joinPolicy: JoinPolicy.open,
    );
    await pumpCommunities(
      tester,
      repository: repository(my: const [longCommunity], all: const [longCommunity]),
      locale: const Locale('ar'),
      size: const Size(320, 900),
    );

    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(ClubHero))),
      TextDirection.rtl,
    );
    expect(
      tester.widget<Text>(find.text(longName)).overflow,
      TextOverflow.ellipsis,
    );
  });
}

class _RouteRecorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

class _FakeCommunityAdapter implements CommunityAdapter {
  _FakeCommunityAdapter({
    required this.my,
    required this.all,
    this.waitingForMyCommunities,
    this.error,
  });

  final List<Community> my;
  final List<Community> all;
  final Completer<List<Community>>? waitingForMyCommunities;
  final Object? error;

  @override
  Future<List<Community>> fetchMyCommunities() async {
    if (error != null) throw error!;
    return waitingForMyCommunities?.future ?? my;
  }

  @override
  Future<List<Community>> fetchAllCommunities() async => all;

  @override
  Future<Community> fetchCommunity(String communityId) =>
      throw UnimplementedError();

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

/// A loaded session, so [CurrentUserMenu] has a player to name rather than a
/// read that cannot succeed.
class _StaticProfileAdapter implements ProfileAdapter {
  static const _profile = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.mid,
  );

  @override
  Future<PlayerProfile> fetchMyProfile() async => _profile;

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

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}
