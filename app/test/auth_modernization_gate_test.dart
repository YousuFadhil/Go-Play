import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/auth/account_suspended_screen.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/complete_profile_screen.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/password_recovery_state.dart';
import 'package:go_play/features/auth/reset_password_screen.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/home/home_shell.dart';
import 'package:go_play/features/invitations/invite_landing_screen.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_modernization_fakes.dart';
import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

/// The auth gate under the authentication modernization: which of five things a
/// signed-in account is shown, how it comes back from Google, and how a
/// password-recovery session outranks all of it.
///
/// The gate is driven exactly as the application drives it — through
/// `AuthService` over a fake identity port — so what is asserted is the routing
/// decision and not a copy of it. Existing behaviour of the gate (suspension, the
/// fail-closed check, resume, sessions) stays in `account_suspension_gate_test`
/// and is not restated here.
void main() {
  // The gate renders the real destination screens, and those construct their
  // Supabase adapters as they build. Nothing here makes a request; the client
  // has to exist for them to be constructed at all. A harness detail only.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  late FakeAnalyticsAdapter analytics;

  setUp(() {
    PendingInvite.instance.clear();
    analytics = FakeAnalyticsAdapter();
    ProductAnalytics.instance =
        ProductAnalytics(repository: AnalyticsRepository(analytics));
  });

  tearDown(() {
    PendingInvite.instance.clear();
    ProductAnalytics.instance = ProductAnalytics();
  });

  Widget app(AuthService service, {Locale locale = const Locale('en')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AuthGate(authService: service),
      );

  /// A surface tall enough for the whole of the longer forms; the screens
  /// scroll, and the default test window would leave a button below the fold.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<ScriptedAuthAdapter> pump(
    WidgetTester tester,
    ScriptedAuthAdapter adapter, {
    PasswordRecoveryState? recovery,
  }) async {
    tallSurface(tester);
    // Its own recovery state each time, never the process-wide one: what one
    // test records must not be there for the next.
    await tester.pumpWidget(
        app(AuthService(adapter, recovery ?? PasswordRecoveryState())));
    await tester.pumpAndSettle();
    return adapter;
  }

  group('the three things a signed-in account can be', () {
    testWidgets('active still reaches Home', (tester) async {
      final adapter = await pump(tester, ScriptedAuthAdapter(signedIn: true));

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(CompletePlayerProfileScreen), findsNothing);
      expect(find.byType(AccountSuspendedScreen), findsNothing);
      expect(adapter.accountStateChecks, 1);
    });

    testWidgets('suspended still reaches the suspension screen',
        (tester) async {
      await pump(
          tester,
          ScriptedAuthAdapter(
              signedIn: true, accountState: AccountState.suspended));

      expect(find.byType(AccountSuspendedScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(CompletePlayerProfileScreen), findsNothing,
          reason: 'a suspension is not a missing profile');
    });

    testWidgets('a missing player profile reaches Complete Player Profile, '
        'not the suspension screen and not Home', (tester) async {
      await pump(
          tester,
          ScriptedAuthAdapter(
              signedIn: true, accountState: AccountState.profileRequired));

      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(find.byType(AccountSuspendedScreen), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Complete your player profile'), findsOneWidget);
    });

    testWidgets('an account with no profile is not counted as a session',
        (tester) async {
      await pump(
          tester,
          ScriptedAuthAdapter(
              signedIn: true, accountState: AccountState.profileRequired));

      expect(analytics.events, isEmpty,
          reason: 'they have not entered the product yet');
    });

    testWidgets('a pending invitation does not carry an account with no '
        'profile past the profile screen', (tester) async {
      PendingInvite.instance.offer('1234');
      await pump(
          tester,
          ScriptedAuthAdapter(
              signedIn: true, accountState: AccountState.profileRequired));

      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(find.byType(InviteLandingScreen), findsNothing);
    });

    testWidgets('an unanswerable state still fails closed', (tester) async {
      await pump(
          tester,
          ScriptedAuthAdapter(signedIn: true)
            ..accountStateError = const NetworkFailure());

      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(CompletePlayerProfileScreen), findsNothing);
      expect(find.text('We could not check your account right now.'),
          findsOneWidget);
    });

    testWidgets('signing out from the profile screen is the ordinary sign-out',
        (tester) async {
      final adapter = await pump(
          tester,
          ScriptedAuthAdapter(
              signedIn: true, accountState: AccountState.profileRequired));

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(adapter.signOuts, 1);
      expect(find.byType(DiscoverScreen), findsOneWidget);
    });
  });

  group('coming back from Google', () {
    testWidgets('an existing account with its profile goes straight in',
        (tester) async {
      final adapter = await pump(tester, ScriptedAuthAdapter());
      expect(find.byType(DiscoverScreen), findsOneWidget);

      // The redirect returned and the SDK exchanged it for a session.
      adapter.emit(AuthEvent.signedIn, signedIn: true);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(analytics.events, [ProductEvent.sessionStarted]);
    });

    testWidgets('a new Google account is asked for its profile',
        (tester) async {
      final adapter = await pump(
          tester,
          ScriptedAuthAdapter(
              accountState: AccountState.profileRequired,
              suggestedName: 'Goo Gle'));

      adapter.emit(AuthEvent.signedIn, signedIn: true);
      await tester.pumpAndSettle();

      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('the login form the person started from is not left on top',
        (tester) async {
      final adapter = await pump(tester, ScriptedAuthAdapter());
      final service = AuthService(adapter);
      unawaited(Navigator.of(tester.element(find.byType(DiscoverScreen))).push(
        MaterialPageRoute<void>(
            builder: (_) => LoginScreen(authService: service)),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      adapter.emit(AuthEvent.signedIn, signedIn: true);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing,
          reason: 'on Android nothing else knows the moment the browser '
              'returns, so the gate clears what was pushed while signed out');
      expect(find.byType(HomeShell), findsOneWidget);
    });
  });

  group('completing the profile', () {
    Future<ScriptedAuthAdapter> pumpProfile(
      WidgetTester tester, {
      String? suggestedName,
      Locale locale = const Locale('en'),
    }) async {
      final adapter = ScriptedAuthAdapter(
        signedIn: true,
        accountState: AccountState.profileRequired,
        suggestedName: suggestedName,
      );
      tallSurface(tester);
      await tester.pumpWidget(app(AuthService(adapter), locale: locale));
      await tester.pumpAndSettle();
      return adapter;
    }

    Future<void> fillPhone(WidgetTester tester) =>
        tester.enterText(find.byType(TextFormField).at(1), '91234567');

    Future<void> pickDateOfBirth(WidgetTester tester) async {
      await tester.tap(find.text('Select date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, Finder field, String label) async {
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    final primary = find.byType(DropdownButtonFormField<PlayerPosition>);
    final secondary = find.byType(DropdownButtonFormField<PlayerPosition?>);

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the profile and nothing else: no email, no password',
        (tester) async {
      await pumpProfile(tester);

      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Date of birth'), findsOneWidget);
      expect(find.text('Primary position'), findsOneWidget);
      expect(find.text('Secondary position (optional)'), findsOneWidget);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Password'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2),
          reason: 'the name and the phone; the rest are pickers');
      expect(find.textContaining('ating'), findsNothing,
          reason: 'the rating is system-managed and never asked for (OP-1)');
    });

    testWidgets('the name Google supplied is there, and is editable',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Goo Gle');

      final name = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      expect(name.controller!.text, 'Goo Gle');

      await tester.enterText(find.byType(TextFormField).at(0), 'Salim Balushi');
      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(adapter.completions.single.fullName, 'Salim Balushi');
    });

    testWidgets('with no name from Google the field starts empty',
        (tester) async {
      await pumpProfile(tester);

      final name = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      expect(name.controller!.text, isEmpty);
    });

    testWidgets('refuses an empty form before anything reaches the port',
        (tester) async {
      final adapter = await pumpProfile(tester);

      await submit(tester);

      expect(find.text('Full name is required'), findsOneWidget);
      expect(find.text('Phone number is required'), findsOneWidget);
      expect(find.text('Date of birth is required'), findsOneWidget);
      expect(find.text('Primary position is required'), findsOneWidget);
      expect(adapter.completions, isEmpty);
      expect(adapter.accountStateChecks, 1, reason: 'no re-check: nothing sent');
    });

    testWidgets('refuses a phone that is not 8 digits', (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Goo Gle');

      await tester.enterText(find.byType(TextFormField).at(1), '9123');
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(find.textContaining('8 digits'), findsWidgets);
      expect(adapter.completions, isEmpty);
    });

    testWidgets('the primary is never offered as the secondary',
        (tester) async {
      await pumpProfile(tester, suggestedName: 'Goo Gle');

      await choose(tester, primary, 'Goalkeeper');
      await tester.tap(secondary);
      await tester.pumpAndSettle();

      expect(find.text('Goalkeeper'), findsOneWidget,
          reason: 'only the primary field itself still shows it');
      expect(find.text('Defender'), findsWidgets);
    });

    testWidgets('sends the stored forms and then asks the database again',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: ' Sara Al Harthy ');
      expect(adapter.accountStateChecks, 1);

      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Defender');
      await choose(tester, secondary, 'Forward');
      await submit(tester);

      final call = adapter.completions.single;
      expect(call.fullName, 'Sara Al Harthy');
      expect(call.phone, '+96891234567');
      expect(call.position, PlayerPosition.def);
      expect(call.secondaryPosition, PlayerPosition.fwd);
      expect(call.dateOfBirth.hour, 0, reason: 'a date, not a timestamp');

      // The screen decided nothing: the gate asked again, was told "active",
      // and only then let the player in.
      expect(adapter.accountStateChecks, 2);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(CompletePlayerProfileScreen), findsNothing);
      expect(analytics.events, [ProductEvent.sessionStarted]);
    });

    testWidgets('a database that has not caught up does not let anybody in',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Sara');
      adapter.completionActivatesAccount = false;

      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(adapter.completions, hasLength(1));
      expect(adapter.accountStateChecks, 2);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget,
          reason: 'still "profile required" is what the database still says');
    });

    testWidgets('a profile that already exists is not a failure to report',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Sara');
      // Finished somewhere else in the meantime.
      adapter
        ..completionFailure =
            const ConflictFailure(FailureReason.profileAlreadyExists)
        ..accountState = AccountState.active;

      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(adapter.accountStateChecks, 2);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('no connection is said so, and the form is kept',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Sara');
      adapter.completionFailure = const NetworkFailure();

      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);
      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!.text, '91234567');
    });

    testWidgets('a refusal from the database says to check the details',
        (tester) async {
      final adapter = await pumpProfile(tester, suggestedName: 'Sara');
      adapter.completionFailure = const ValidationFailure();

      await fillPhone(tester);
      await pickDateOfBirth(tester);
      await choose(tester, primary, 'Midfielder');
      await submit(tester);

      expect(find.text('Please check your details and try again.'),
          findsOneWidget);
    });

    testWidgets('is in Arabic in Arabic', (tester) async {
      await pumpProfile(tester, locale: const Locale('ar'));

      expect(find.text('أكمل ملفك كلاعب'), findsOneWidget);
      expect(find.text('متابعة'), findsOneWidget);
    });
  });

  group('a password-recovery session outranks normal routing', () {
    // The tests here use the application's own durable recovery state over
    // (mock) local storage, and simulate a restart by throwing the running app
    // and its state away and building new ones from storage alone -- which is
    // all a killed process leaves behind. Nothing replays an event for them.
    late PasswordRecoveryState recovery;

    const recoveryLink = 'goplay://login-callback/recovery?code=abc123';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recovery = PasswordRecoveryState();
      await recovery.load();
    });

    tearDown(() {
      PendingPublicLink.instance.clear();
    });

    Future<bool> persisted() async =>
        (await SharedPreferences.getInstance())
            .getBool(PasswordRecoveryState.storageKey) ??
        false;

    /// The app is opened by a recovery link whose session already exists, and
    /// no event is emitted: the launch is all there is to go on.
    Future<ScriptedAuthAdapter> pumpRecovery(
      WidgetTester tester, {
      AccountState accountState = AccountState.active,
      Locale locale = const Locale('en'),
    }) async {
      await recovery.captureLink(recoveryLink);
      final adapter =
          ScriptedAuthAdapter(signedIn: true, accountState: accountState);
      tallSurface(tester);
      await tester.pumpWidget(app(AuthService(adapter, recovery), locale: locale));
      await tester.pumpAndSettle();
      return adapter;
    }

    /// The process is killed: the widget tree, the state object and the fake
    /// provider go with it. What comes back is built from storage alone.
    Future<PasswordRecoveryState> restart(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      final restarted = PasswordRecoveryState();
      await restarted.load();
      return restarted;
    }

    Future<void> enterPasswords(
      WidgetTester tester,
      String password, [
      String? confirmation,
    ]) async {
      await tester.enterText(find.byType(TextFormField).at(0), password);
      await tester.enterText(
          find.byType(TextFormField).at(1), confirmation ?? password);
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
      await tester.pumpAndSettle();
    }

    group('how a recovery is recognised', () {
      testWidgets('the provider\'s event on a running app shows the reset '
          'screen, and is remembered', (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: recovery);
        expect(find.byType(HomeShell), findsOneWidget);
        final checks = adapter.accountStateChecks;

        adapter.emit(AuthEvent.passwordRecovery, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(adapter.accountStateChecks, checks,
            reason: 'nothing about the account is asked of a recovery session');
        expect(recovery.isInProgress, isTrue);
        expect(await persisted(), isTrue,
            reason: 'the event is only a backup, but it is a durable one');
      });

      testWidgets('a cold start from the recovery link, with its session and '
          'no event at all, shows the reset screen', (tester) async {
        final adapter = await pumpRecovery(tester);

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(adapter.accountStateChecks, 0,
            reason: 'the durable record is read before any account question');
        expect(analytics.events, isEmpty,
            reason: 'a recovery session is not a product session');
      });

      testWidgets('a link handed to the app while it is running shows it too',
          (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: recovery);
        expect(find.byType(HomeShell), findsOneWidget);

        expect(await recovery.captureLink(recoveryLink), isTrue);
        await tester.pumpAndSettle();

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(adapter.accountStateChecks, 1);
      });

      testWidgets('it lands on top of a form that was pushed', (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(),
            recovery: recovery);
        unawaited(Navigator.of(tester.element(find.byType(DiscoverScreen))).push(
          MaterialPageRoute<void>(
              builder: (_) => LoginScreen(authService: AuthService(adapter))),
        ));
        await tester.pumpAndSettle();

        adapter.emit(AuthEvent.passwordRecovery, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(ResetPasswordScreen), findsOneWidget);
      });

      testWidgets('an ordinary persisted session does not become one',
          (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: recovery);

        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(adapter.accountStateChecks, 1);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
      });

      testWidgets('nor does a Google return or a confirmation link',
          (tester) async {
        for (final link in [
          'goplay://login-callback?code=abc123',
          'https://go-play-44y.pages.dev/login-callback?code=abc123',
          'goplay://login-callback#access_token=a&refresh_token=b&type=signup',
          '/login-callback?code=abc123',
        ]) {
          expect(await recovery.captureLink(link), isFalse, reason: link);
        }
        expect(recovery.isInProgress, isFalse);

        final adapter = await pump(tester, ScriptedAuthAdapter(),
            recovery: recovery);
        adapter.emit(AuthEvent.signedIn, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
      });
    });

    group('across a restart', () {
      testWidgets('killed on the reset screen, it is the reset screen again',
          (tester) async {
        final first = await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: recovery);
        first.emit(AuthEvent.passwordRecovery, signedIn: true);
        await tester.pumpAndSettle();
        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        // The first run began as an ordinary session, so it did record one.
        final sessionsBefore = analytics.events.length;

        final restarted = await restart(tester);
        // The provider restores its persisted session; no event follows it.
        final second = await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: restarted);

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(second.accountStateChecks, 0);
        expect(analytics.events.length, sessionsBefore,
            reason: 'the restarted recovery session recorded nothing');
      });

      testWidgets('and again after a second restart, until it is finished',
          (tester) async {
        await pumpRecovery(tester);
        var state = await restart(tester);
        await pump(tester, ScriptedAuthAdapter(signedIn: true), recovery: state);
        expect(find.byType(ResetPasswordScreen), findsOneWidget);

        state = await restart(tester);
        await pump(tester, ScriptedAuthAdapter(signedIn: true), recovery: state);

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
      });

      testWidgets('what was recorded is read before Home or any account state',
          (tester) async {
        for (final state in AccountState.values) {
          SharedPreferences.setMockInitialValues(
              {PasswordRecoveryState.storageKey: true});
          final stored = PasswordRecoveryState();
          await stored.load();
          final adapter = await pump(
              tester,
              ScriptedAuthAdapter(signedIn: true, accountState: state),
              recovery: stored);

          expect(find.byType(ResetPasswordScreen), findsOneWidget,
              reason: '$state');
          expect(find.byType(HomeShell), findsNothing);
          expect(find.byType(CompletePlayerProfileScreen), findsNothing);
          expect(find.byType(AccountSuspendedScreen), findsNothing);
          expect(adapter.accountStateChecks, 0, reason: '$state');
        }
      });

      testWidgets('a record with no session behind it is dropped, and does '
          'not loop', (tester) async {
        SharedPreferences.setMockInitialValues(
            {PasswordRecoveryState.storageKey: true});
        final stale = PasswordRecoveryState();
        await stale.load();
        expect(stale.isInProgress, isTrue);

        await pump(tester, ScriptedAuthAdapter(), recovery: stale);

        expect(find.byType(DiscoverScreen), findsOneWidget,
            reason: 'the ordinary signed-out flow');
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(stale.isInProgress, isFalse);
        expect(await persisted(), isFalse);

        // Nothing is left to come back: the next start, with an ordinary
        // session, is an ordinary start.
        final restarted = await restart(tester);
        expect(restarted.isInProgress, isFalse);
        await pump(tester, ScriptedAuthAdapter(signedIn: true),
            recovery: restarted);
        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
      });

      testWidgets('the reset screen stays up if its session ends, until the '
          'person leaves it', (tester) async {
        final adapter = await pumpRecovery(tester);

        adapter.emit(AuthEvent.signedOut, signedIn: false);
        await tester.pumpAndSettle();

        expect(find.byType(ResetPasswordScreen), findsOneWidget,
            reason: 'it is what finishing relies on: the session ends before '
                'the screen says it is done');
        expect(recovery.isInProgress, isTrue);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
        expect(find.byType(DiscoverScreen), findsOneWidget);
      });
    });

    group('a link whose session has not arrived yet', () {
      testWidgets('is armed while nobody is signed in, and no reset screen is '
          'shown for it', (tester) async {
        await pump(tester, ScriptedAuthAdapter(), recovery: recovery);

        await recovery.captureLink(recoveryLink);
        await tester.pumpAndSettle();

        expect(find.byType(DiscoverScreen), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
      });

      testWidgets('shows the reset screen when the recovery session lands',
          (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(),
            recovery: recovery);
        await recovery.captureLink(recoveryLink);

        adapter.emit(AuthEvent.passwordRecovery, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(adapter.accountStateChecks, 0);
      });

      testWidgets('is not mistaken for the ordinary sign-in that comes instead '
          'when the link had expired', (tester) async {
        final adapter = await pump(tester, ScriptedAuthAdapter(),
            recovery: recovery);
        await recovery.captureLink(recoveryLink);

        // The exchange never produced a recovery session; the person went back
        // and simply signed in.
        adapter.emit(AuthEvent.signedIn, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
      });
    });

    group('nothing outranks it', () {
      testWidgets('not a pending invitation', (tester) async {
        PendingInvite.instance.offer('1234');
        await pumpRecovery(tester);

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(InviteLandingScreen), findsNothing);
      });

      testWidgets('not a pending public destination', (tester) async {
        PendingPublicLink.instance
            .offer('/player/3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d');
        expect(PendingPublicLink.instance.target.value, isNotNull);

        await pumpRecovery(tester);

        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(PendingPublicLink.instance.target.value, isNotNull,
            reason: 'still pending: the recovery only stands in front of it');
      });

      testWidgets('not an account with no profile, nor a suspended one',
          (tester) async {
        for (final state in [
          AccountState.profileRequired,
          AccountState.suspended,
        ]) {
          await pumpRecovery(tester, accountState: state);

          expect(find.byType(ResetPasswordScreen), findsOneWidget,
              reason: '$state');
          expect(find.byType(CompletePlayerProfileScreen), findsNothing);
          expect(find.byType(AccountSuspendedScreen), findsNothing);
        }
      });

      testWidgets('and there is no way back to the product from it',
          (tester) async {
        await pumpRecovery(tester);

        expect(find.byType(BackButton), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ResetPasswordScreen), findsOneWidget);
      });
    });

    group('the reset screen', () {
      testWidgets('refuses a short password before the port', (tester) async {
        final adapter = await pumpRecovery(tester);

        await enterPasswords(tester, 'short');
        await save(tester);

        expect(find.text('Password must be at least 8 characters'),
            findsOneWidget);
        expect(adapter.passwordChanges, isEmpty);
      });

      testWidgets('refuses a confirmation that differs before the port',
          (tester) async {
        final adapter = await pumpRecovery(tester);

        await enterPasswords(tester, 'a-new-password', 'a-new-passwrod');
        await save(tester);

        expect(find.text('The two passwords do not match'), findsOneWidget);
        expect(adapter.passwordChanges, isEmpty);
        expect(adapter.signOuts, 0);
      });

      testWidgets('says so when the link has expired, and stays',
          (tester) async {
        final adapter = await pumpRecovery(tester);
        adapter.changePasswordFailure = const AuthenticationFailure();

        await enterPasswords(tester, 'a-new-password');
        await save(tester);

        expect(find.text('This reset link is no longer valid. Request a new '
            'one.'), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(adapter.signOuts, 0);
        expect(recovery.isInProgress, isTrue,
            reason: 'nothing has finished, so nothing is cleared');
        expect(await persisted(), isTrue);
      });

      testWidgets('is in Arabic in Arabic', (tester) async {
        await pumpRecovery(tester, locale: const Locale('ar'));

        expect(find.text('اختر كلمة مرور جديدة'), findsWidgets);
        expect(find.text('كلمة المرور الجديدة'), findsOneWidget);
        expect(find.text('حفظ كلمة المرور الجديدة'), findsOneWidget);
      });
    });

    group('finishing', () {
      testWidgets('changes the password, signs out, clears the record, and '
          'returns to the login flow with the news', (tester) async {
        final adapter = await pumpRecovery(tester);
        bool? recordedAtSignOut;
        adapter.onSignOut = () => recordedAtSignOut = recovery.isInProgress;

        await enterPasswords(tester, 'a-new-password');
        await save(tester);

        expect(adapter.journal, ['changePassword', 'signOut']);
        expect(adapter.passwordChanges, ['a-new-password']);
        expect(adapter.isSignedIn, isFalse);
        expect(recordedAtSignOut, isTrue,
            reason: 'the record outlives the session it describes, so an '
                'interruption in between is met by the reset screen again');
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);

        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(find.byType(HomeShell), findsNothing,
            reason: 'the recovery session was never a way in');
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.text('Your password was changed. Log in with your new '
            'password.'), findsOneWidget);
        expect(analytics.events, isEmpty);
      });

      testWidgets('and that login is a destination with Back, over Discover',
          (tester) async {
        final adapter = await pumpRecovery(tester);
        await enterPasswords(tester, 'a-new-password');
        await save(tester);
        expect(find.byType(LoginScreen), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byType(DiscoverScreen), findsOneWidget);
        expect(adapter.isSignedIn, isFalse);
      });

      testWidgets('nothing of it is left to come back after a restart',
          (tester) async {
        await pumpRecovery(tester);
        await enterPasswords(tester, 'a-new-password');
        await save(tester);

        final restarted = await restart(tester);
        expect(restarted.isInProgress, isFalse);
        await pump(tester, ScriptedAuthAdapter(), recovery: restarted);
        expect(find.byType(DiscoverScreen), findsOneWidget);
      });

      testWidgets('afterwards an ordinary sign-in is an ordinary sign-in',
          (tester) async {
        final adapter = await pumpRecovery(tester);
        await enterPasswords(tester, 'a-new-password');
        await save(tester);

        adapter.emit(AuthEvent.signedIn, signedIn: true);
        await tester.pumpAndSettle();

        expect(find.byType(ResetPasswordScreen), findsNothing,
            reason: 'the recovery is over; it does not stick to later sessions');
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(HomeShell), findsOneWidget);
      });
    });

    group('cancelling', () {
      testWidgets('signs out and clears the record', (tester) async {
        final adapter = await pumpRecovery(tester);
        bool? recordedAtSignOut;
        adapter.onSignOut = () => recordedAtSignOut = recovery.isInProgress;

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(adapter.signOuts, 1);
        expect(adapter.passwordChanges, isEmpty);
        expect(adapter.isSignedIn, isFalse);
        expect(recordedAtSignOut, isTrue);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
        expect(find.byType(DiscoverScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(HomeShell), findsNothing);
      });

      testWidgets('leaves nothing to come back after a restart', (tester) async {
        await pumpRecovery(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final restarted = await restart(tester);

        expect(restarted.isInProgress, isFalse);
      });

      testWidgets('that cannot end the session keeps the record and the screen',
          (tester) async {
        final adapter = await pumpRecovery(tester);
        adapter
          ..signOutFailure = const NetworkFailure()
          ..signOutLeavesSession = true;

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(adapter.isSignedIn, isTrue);
        expect(find.byType(ResetPasswordScreen), findsOneWidget,
            reason: 'leaving would hand a live recovery session to the product');
        expect(recovery.isInProgress, isTrue);
        expect(await persisted(), isTrue);
        expect(find.text('Could not reach the server. Check your internet '
            'connection.'), findsOneWidget);
      });
    });
  });
}
