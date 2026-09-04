import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/account_suspended_screen.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/home/home_shell.dart';
import 'package:go_play/features/invitations/invite_landing_screen.dart';
import 'package:go_play/features/invitations/invite_link.dart';

/// An identity that answers exactly what a test needs about the account.
class _FakeAuthAdapter implements AuthAdapter {
  _FakeAuthAdapter({
    bool signedIn = false,
    this.active = true,
    this.throwsOnStatus = false,
  }) : _signedIn = signedIn;

  bool _signedIn;
  bool active;
  bool throwsOnStatus;

  int statusChecks = 0;
  int signOuts = 0;

  final _controller = StreamController<bool>.broadcast();

  void emitSignedIn(bool value) {
    _signedIn = value;
    _controller.add(value);
  }

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> get signedInChanges => _controller.stream;

  @override
  Future<bool> isCurrentUserActive() async {
    statusChecks++;
    if (throwsOnStatus) throw const NetworkFailure();
    return active;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    emitSignedIn(false);
  }

  @override
  String? get currentUserId => _signedIn ? 'u1' : null;

  @override
  String? get currentUserEmail => _signedIn ? 'u1@example.com' : null;

  @override
  Future<String?> fetchCurrentUserFullName() async => 'Ali';

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
}

Widget _app(AuthService service) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AuthGate(authService: service),
    );

void main() {
  // The gate renders the real destination screens, and those construct their
  // Supabase adapters as they build. Nothing in these tests makes a request --
  // the identity is faked and the destinations are only checked for existence
  // -- but the client has to exist for them to be constructed at all. This is
  // a test harness detail; no production code is involved.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  setUp(() => PendingInvite.instance.clear());
  tearDown(() => PendingInvite.instance.clear());

  testWidgets('signed out lands on Discover, and asks nothing about an account',
      (tester) async {
    final adapter = _FakeAuthAdapter();
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(adapter.statusChecks, 0);
  });

  testWidgets('signed out with a pending invitation still opens the landing',
      (tester) async {
    PendingInvite.instance.offer('1234');
    final adapter = _FakeAuthAdapter();
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pump();

    expect(find.byType(InviteLandingScreen), findsOneWidget);
  });

  testWidgets('signed in and active reaches HomeShell', (tester) async {
    final adapter = _FakeAuthAdapter(signedIn: true, active: true);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(adapter.statusChecks, 1);
  });

  testWidgets('signed in and active with a pending invitation opens it',
      (tester) async {
    PendingInvite.instance.offer('1234');
    final adapter = _FakeAuthAdapter(signedIn: true, active: true);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    expect(find.byType(InviteLandingScreen), findsOneWidget);
  });

  testWidgets('signed in and suspended shows Account Suspended, not Home',
      (tester) async {
    final adapter = _FakeAuthAdapter(signedIn: true, active: false);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    expect(find.byType(AccountSuspendedScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('a pending invitation does not bypass the suspension gate',
      (tester) async {
    PendingInvite.instance.offer('1234');
    final adapter = _FakeAuthAdapter(signedIn: true, active: false);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    expect(find.byType(AccountSuspendedScreen), findsOneWidget);
    expect(find.byType(InviteLandingScreen), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('a failed status check fails closed, and retry can recover',
      (tester) async {
    final adapter =
        _FakeAuthAdapter(signedIn: true, active: true, throwsOnStatus: true);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    // Never falls through to the product on an unanswered question.
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byType(AccountSuspendedScreen), findsNothing);
    expect(find.text('We could not check your account right now.'),
        findsOneWidget);

    adapter.throwsOnStatus = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('signing out of Account Suspended uses the ordinary logout path',
      (tester) async {
    final adapter = _FakeAuthAdapter(signedIn: true, active: false);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(adapter.signOuts, 1);
    // The gate follows the session on its own.
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  testWidgets('the account is re-checked when the app resumes', (tester) async {
    final adapter = _FakeAuthAdapter(signedIn: true, active: true);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(adapter.statusChecks, 1);

    // Suspended while the app was away.
    adapter.active = false;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(adapter.statusChecks, greaterThan(1));
    expect(find.byType(AccountSuspendedScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('signing in re-asks rather than trusting the previous answer',
      (tester) async {
    final adapter = _FakeAuthAdapter(signedIn: false, active: false);
    await tester.pumpWidget(_app(AuthService(adapter)));
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverScreen), findsOneWidget);

    adapter.emitSignedIn(true);
    await tester.pumpAndSettle();

    expect(adapter.statusChecks, 1);
    expect(find.byType(AccountSuspendedScreen), findsOneWidget);
  });
}
