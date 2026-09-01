import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_details_screen.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/invitations/community_invitation_screen.dart';
import 'package:go_play/features/invitations/invite_landing_screen.dart';
import 'package:go_play/features/invitations/invite_link.dart';

void main() {
  const code = '4819';

  Future<void> pumpInvite(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observers,
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  CommunityInvitePreview preview({
    bool isValid = true,
    bool isMember = false,
    String name = 'Al Amerat FC',
  }) =>
      CommunityInvitePreview(
        isValid: isValid,
        communityId: isValid ? 'c1' : null,
        communityName: isValid ? name : null,
        isMember: isMember,
      );

  CommunityInvitationScreen share({String name = 'Al Amerat FC'}) =>
      CommunityInvitationScreen(
        communityId: 'c1',
        communityName: name,
        joinCode: code,
      );

  group('Club invitation share', () {
    testWidgets('renders the Club hero, code, link, and actions',
        (tester) async {
      await pumpInvite(tester, share());

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(find.text(InviteLink.format(code)), findsOneWidget);
      expect(find.text('Share invitation'), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Regenerate code'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Share invitation'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('code and link remain LTR in Arabic at 320 pixels',
        (tester) async {
      final name = 'نادي العامرات الرياضي لكرة القدم الطويل جداً';
      await pumpInvite(
        tester,
        share(name: name),
        locale: const Locale('ar'),
        size: const Size(320, 800),
      );

      expect(find.text(name), findsOneWidget);
      // The code is set left-to-right by a `Directionality` above the
      // `SelectableText`, not by a property on it — the same way the link
      // below is — so the ambient direction is what the screen guarantees.
      final codeFinder = find.text(code);
      expect(codeFinder, findsOneWidget);
      expect(Directionality.of(tester.element(codeFinder)), TextDirection.ltr);
      final link = find.text(InviteLink.format(code));
      expect(link, findsOneWidget);
      expect(Directionality.of(tester.element(link)), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long English community name is safe at 320 pixels',
        (tester) async {
      final name =
          'Al Amerat Football Community for Players Across Muscat and Beyond';
      await pumpInvite(
        tester,
        share(name: name),
        size: const Size(320, 800),
      );

      expect(find.text(name), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('invitation landing', () {
    testWidgets('signed-out visitors keep the sign-in flow', (tester) async {
      addTearDown(PendingInvite.instance.clear);
      final observer = _RouteRecorder();
      await pumpInvite(
        tester,
        InviteLandingScreen(
          code: code,
          communityRepository: CommunityRepository(
            _FakeCommunityAdapter(preview: preview()),
          ),
          authService: AuthService(_FakeAuthAdapter()),
        ),
        observers: [observer],
      );

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      observer.pushed.clear();
      await tester.tap(find.text('Join Community'));
      await tester.pump();

      final route = observer.pushed.single;
      final screen = route.builder(tester.element(find.byType(ClubHero)));
      expect(screen, isA<LoginScreen>());
      observer.discard();
    });

    testWidgets('a signed-in visitor joins and opens the community',
        (tester) async {
      addTearDown(PendingInvite.instance.clear);
      final adapter = _FakeCommunityAdapter(preview: preview());
      final observer = _RouteRecorder();
      await pumpInvite(
        tester,
        InviteLandingScreen(
          code: code,
          communityRepository: CommunityRepository(adapter),
          authService: AuthService(_FakeAuthAdapter(userId: 'u1')),
        ),
        observers: [observer],
      );

      observer.pushed.clear();
      await tester.tap(find.text('Join Community'));
      await tester.pump();

      expect(adapter.joinedCodes, [code]);
      final route = observer.pushed.single;
      final screen = route.builder(tester.element(find.byType(ClubHero)));
      expect(screen, isA<CommunityDetailsScreen>());
      observer.discard();
    });

    testWidgets('an invalid or expired invitation remains unavailable',
        (tester) async {
      await pumpInvite(
        tester,
        InviteLandingScreen(
          code: code,
          communityRepository: CommunityRepository(
            _FakeCommunityAdapter(preview: preview(isValid: false)),
          ),
          authService: AuthService(_FakeAuthAdapter()),
        ),
        size: const Size(480, 900),
      );

      expect(find.byType(ClubHero), findsNothing);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a preview error still offers retry', (tester) async {
      await pumpInvite(
        tester,
        InviteLandingScreen(
          code: code,
          communityRepository: CommunityRepository(
            _FakeCommunityAdapter(
              preview: preview(),
              previewFailure: const NetworkFailure(),
            ),
          ),
          authService: AuthService(_FakeAuthAdapter()),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

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

class _FakeCommunityAdapter implements CommunityAdapter {
  _FakeCommunityAdapter({required this.preview, this.previewFailure});

  final CommunityInvitePreview preview;
  final Failure? previewFailure;
  final List<String> joinedCodes = [];

  @override
  Future<String> fetchJoinCode(String communityId) async =>
      throw UnimplementedError();

  @override
  Future<CommunityInvitePreview> previewInvite(String code) async {
    if (previewFailure != null) throw previewFailure!;
    return preview;
  }

  @override
  Future<String> joinCommunityByCode(String code) async {
    joinedCodes.add(code);
    return 'c1';
  }

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
  Future<String> joinCommunity(String communityId) => throw UnimplementedError();

  @override
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> regenerateJoinCode(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunity(String communityId) => throw UnimplementedError();
}

class _FakeAuthAdapter implements AuthAdapter {
  _FakeAuthAdapter({this.userId});

  final String? userId;

  @override
  String? get currentUserId => userId;

  @override
  String? get currentUserEmail => null;

  @override
  bool get isSignedIn => userId != null;

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
