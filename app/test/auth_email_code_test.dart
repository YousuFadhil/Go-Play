import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/acquisition_analytics.dart';
import 'package:go_play/features/analytics/acquisition_analytics_adapter.dart';
import 'package:go_play/features/analytics/acquisition_analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/auth/account_suspended_screen.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/complete_profile_screen.dart';
import 'package:go_play/features/auth/email_code_view.dart';
import 'package:go_play/features/auth/forgot_password_screen.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/password_recovery_state.dart';
import 'package:go_play/features/auth/reset_password_screen.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/home/home_shell.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/infrastructure/supabase/supabase_auth_adapter.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_modernization_fakes.dart';
import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

/// Email codes for password recovery and sign-up verification.
///
/// Four layers, each proving something the others cannot:
///
///  1. the **service**, over a scripted port: what is validated, and in what
///     order the durable recovery record and the provider are touched;
///  2. the **screens**, over a scripted port: what the person sees and can do;
///  3. the **gate**, over a scripted port: where a verified code takes them;
///  4. the **real Supabase SDK** over a replaced transport: that the request the
///     SDK actually makes is the right one, that what it answers is worded
///     right, and that its events reach the gate in the order the design needs.
///
/// A code is a secret for the few minutes it lives, so what is asserted here
/// includes what is *not* done with it: never written to storage, never logged.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The gate renders the real destination screens, which build their Supabase
    // adapters as they draw. A harness detail: nothing here reaches a network.
    await Supabase.initialize(
      url: 'http://localhost:1',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProductAnalytics.instance = ProductAnalytics(
        repository: AnalyticsRepository(FakeAnalyticsAdapter()));
  });

  tearDown(() => ProductAnalytics.instance = ProductAnalytics());

  const address = 'sara@example.com';
  const code = '482913';

  Future<bool> persisted() async => (await SharedPreferences.getInstance())
          .getBool(PasswordRecoveryState.storageKey) ??
      false;

  Widget app(AuthService service, {Locale locale = const Locale('en')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AuthGate(authService: service),
      );

  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The gate, signed out, with a fresh recovery record of its own.
  Future<void> pumpGate(WidgetTester tester, AuthService service) async {
    tallSurface(tester);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
  }

  /// Pushed onto the gate's own navigator, as the application reaches them.
  Future<void> push(WidgetTester tester, Widget screen) async {
    final navigator = Navigator.of(tester.element(find.byType(AuthGate)));
    unawaited(
        navigator.push(MaterialPageRoute<void>(builder: (_) => screen)));
    await tester.pumpAndSettle();
  }

  /// From the forgot-password form to the code screen.
  Future<void> requestRecovery(WidgetTester tester, AuthService service,
      {String email = address}) async {
    await push(tester, ForgotPasswordScreen(authService: service));
    await tester.enterText(find.byType(TextFormField), email);
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String digits) async {
    await tester.enterText(find.byType(TextField), digits);
    await tester.pump();
  }

  Future<void> tapVerify(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();
  }

  String typed(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  /// The login screen, pushed onto the gate's navigator as the application
  /// reaches it.
  Future<void> openLogin(WidgetTester tester, AuthService service) =>
      push(tester, LoginScreen(authService: service));

  Future<void> logIn(WidgetTester tester,
      {String email = address, String password = 'password1'}) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
  }

  const loginFailed = 'Login failed. Check your email and password.';

  // ===========================================================================
  // 1. The service
  // ===========================================================================

  group('the code, as a value', () {
    test('Arabic-Indic and Eastern Arabic-Indic digits become ASCII ones', () {
      expect(AuthService.normalizeEmailCode('٤٨٢٩١٣'), '482913');
      expect(AuthService.normalizeEmailCode('۴۸۲۹۱۳'), '482913');
      expect(AuthService.normalizeEmailCode('٤٨2٩1٣'), '482913',
          reason: 'a keyboard that mixes them');
    });

    test('spaces, dashes and letters are dropped rather than refused', () {
      expect(AuthService.normalizeEmailCode(' 482 913 '), '482913');
      expect(AuthService.normalizeEmailCode('482-913'), '482913');
      expect(AuthService.normalizeEmailCode('4a8b2c'), '482');
    });

    test('a code is exactly six digits once normalised', () {
      expect(AuthService.isValidEmailCode('482913'), isTrue);
      expect(AuthService.isValidEmailCode('482 913'), isTrue);
      expect(AuthService.isValidEmailCode('٤٨٢٩١٣'), isTrue);
      expect(AuthService.isValidEmailCode('48291'), isFalse);
      expect(AuthService.isValidEmailCode('4829133'), isFalse);
      expect(AuthService.isValidEmailCode(''), isFalse);
      expect(AuthService.isValidEmailCode('abcdef'), isFalse);
    });
  });

  group('verifying a recovery code', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    test('something that is not an address, or not six digits, is refused '
        'before the provider is asked or anything is recorded', () async {
      await expectLater(
          service.verifyRecoveryCode(email: 'nope', code: code),
          throwsA(isA<ValidationFailure>()));
      await expectLater(
          service.verifyRecoveryCode(email: address, code: '12345'),
          throwsA(isA<ValidationFailure>()));

      expect(adapter.journal, isEmpty);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    test('the durable record is on disk BEFORE the provider is asked, so '
        'there is never a recovery session without one', () async {
      final prefs = await SharedPreferences.getInstance();
      bool? recordedWhenAsked;
      bool? onDiskWhenAsked;
      adapter.onVerify = () {
        recordedWhenAsked = recovery.isInProgress;
        onDiskWhenAsked = prefs.getBool(PasswordRecoveryState.storageKey);
      };

      await service.verifyRecoveryCode(email: address, code: code);

      expect(recordedWhenAsked, isTrue);
      expect(onDiskWhenAsked, isTrue,
          reason: 'the write was awaited, not merely started');
      expect(adapter.isSignedIn, isTrue);
      expect(recovery.isInProgress, isTrue);
      expect(await persisted(), isTrue);
    });

    test('the provider gets the trimmed address and the digits only',
        () async {
      await service.verifyRecoveryCode(email: '  $address ', code: '٤٨٢ ٩١٣');

      expect(adapter.recoveryVerifications.single,
          (email: address, code: code));
    });

    test('a code the provider refuses takes the record back out, and nobody '
        'is signed in', () async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);

      await expectLater(
          service.verifyRecoveryCode(email: address, code: code),
          throwsA(isA<AuthenticationFailure>()
              .having((f) => f.reason, 'reason',
                  FailureReason.invalidEmailCode)));

      expect(adapter.isSignedIn, isFalse);
      expect(recovery.isInProgress, isFalse,
          reason: 'nothing is being protected: there is no session');
      expect(await persisted(), isFalse);
    });

    test('so does a request that never reached the provider', () async {
      adapter.verifyFailure = const NetworkFailure();

      await expectLater(
          service.verifyRecoveryCode(email: address, code: code),
          throwsA(isA<NetworkFailure>()));

      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    test('with somebody already signed in, their ordinary session is not '
        'described as a recovery before the code is checked', () async {
      adapter = ScriptedAuthAdapter(signedIn: true);
      service = AuthService(adapter, recovery);
      bool? recordedWhenAsked;
      adapter.onVerify = () => recordedWhenAsked = recovery.isInProgress;

      await service.verifyRecoveryCode(email: address, code: code);

      expect(recordedWhenAsked, isFalse);
      expect(recovery.isInProgress, isTrue,
          reason: 'set once the recovery session exists');
    });

    test('a refusal with somebody already signed in changes nothing',
        () async {
      adapter = ScriptedAuthAdapter(signedIn: true);
      service = AuthService(adapter, recovery);
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);

      await expectLater(
          service.verifyRecoveryCode(email: address, code: code),
          throwsA(isA<AuthenticationFailure>()));

      expect(recovery.isInProgress, isFalse);
      expect(adapter.isSignedIn, isTrue);
    });
  });

  group('verifying a sign-up code', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    test('signs the account in as an ordinary session and never touches the '
        'recovery record', () async {
      await service.verifySignupCode(email: '  $address ', code: '482 913');

      expect(adapter.signupVerifications.single, (email: address, code: code));
      expect(adapter.recoveryVerifications, isEmpty);
      expect(adapter.isSignedIn, isTrue);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    test('a refused code signs nobody in and records nothing', () async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);

      await expectLater(
          service.verifySignupCode(email: address, code: code),
          throwsA(isA<AuthenticationFailure>()));

      expect(adapter.isSignedIn, isFalse);
      expect(recovery.isInProgress, isFalse);
    });

    test('something that is not an address, or not six digits, is refused '
        'before the provider', () async {
      await expectLater(service.verifySignupCode(email: 'nope', code: code),
          throwsA(isA<ValidationFailure>()));
      await expectLater(service.verifySignupCode(email: address, code: '1'),
          throwsA(isA<ValidationFailure>()));
      expect(adapter.journal, isEmpty);
    });
  });

  // ===========================================================================
  // 2. The screens
  // ===========================================================================

  group('the code screen', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    Future<void> openView(
      WidgetTester tester, {
      EmailCodePurpose purpose = EmailCodePurpose.recovery,
      Duration resendDelay = const Duration(seconds: 60),
      Locale locale = const Locale('en'),
    }) async {
      tallSurface(tester);
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: SingleChildScrollView(
                        child: EmailCodeView(
                          purpose: purpose,
                          email: address,
                          authService: service,
                          resendDelay: resendDelay,
                        ),
                      ),
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

    /// Unmounts the view so its resend timer is cancelled and nothing is pending
    /// when the test ends.
    Future<void> close(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('asks for a recovery code in the words the product uses, '
        'without repeating the address', (tester) async {
      await openView(tester);

      expect(find.text('Enter the code we sent to your email.'),
          findsOneWidget);
      expect(find.textContaining(address), findsNothing,
          reason: 'what a recovery says must not depend on the address');
      await close(tester);
    });

    testWidgets('asks for a sign-up code in its own words, and shows the '
        'address so a typo can be seen', (tester) async {
      await openView(tester, purpose: EmailCodePurpose.signup);

      expect(find.text('Verify your email to complete registration.'),
          findsOneWidget);
      expect(find.textContaining(address), findsOneWidget);
      await close(tester);
    });

    testWidgets('the field is numeric and takes six digits, no more, no other '
        'characters', (tester) async {
      await openView(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.number);
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);

      await enterCode(tester, '12ab34567890');
      expect(typed(tester), '123456');

      await enterCode(tester, '١٢٣٤٥٦٧');
      expect(typed(tester), '123456', reason: 'Arabic digits, converted');

      await enterCode(tester, '123 456');
      expect(typed(tester), '123456', reason: 'as pasted from an email');
      await close(tester);
    });

    testWidgets('fewer than six digits is said, and nothing reaches the '
        'provider', (tester) async {
      await openView(tester);

      await enterCode(tester, '123');
      await tapVerify(tester);

      expect(find.text('Enter all 6 digits.'), findsOneWidget);
      expect(adapter.journal, isEmpty);
      await close(tester);
    });

    testWidgets('a code the provider refuses stays on this screen, says the '
        'code is wrong or expired, and keeps what was typed', (tester) async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);
      await openView(tester);

      await enterCode(tester, code);
      await tapVerify(tester);

      expect(
          find.text('That code is incorrect or has expired. Check it, or ask '
              'for a new one.'),
          findsOneWidget);
      expect(find.byType(EmailCodeView), findsOneWidget);
      expect(typed(tester), code);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Verify'))
              .onPressed,
          isNotNull,
          reason: 'and it can be tried again');
      expect(adapter.isSignedIn, isFalse);
      expect(recovery.isInProgress, isFalse);
      await close(tester);
    });

    testWidgets('typing again clears the error', (tester) async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);
      await openView(tester);
      await enterCode(tester, code);
      await tapVerify(tester);
      expect(find.textContaining('incorrect or has expired'), findsOneWidget);

      await enterCode(tester, '48291');

      expect(find.textContaining('incorrect or has expired'), findsNothing);
      await close(tester);
    });

    testWidgets('while it is being checked the button shows progress and '
        'cannot be pressed a second time', (tester) async {
      final slow = _SlowVerifyAdapter();
      service = AuthService(slow, recovery);
      await openView(tester);
      await enterCode(tester, code);

      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.descendant(
              of: find.byType(FilledButton),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(slow.asked, 1);

      slow.release.complete();
      await tester.pumpAndSettle();
      expect(slow.asked, 1, reason: 'one request, however long it took');
      await close(tester);
    });

    testWidgets('no connection is said so', (tester) async {
      adapter.verifyFailure = const NetworkFailure();
      await openView(tester);
      await enterCode(tester, code);
      await tapVerify(tester);

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the provider limiting attempts is worded as a wait',
        (tester) async {
      adapter.verifyFailure =
          const InfrastructureFailure(FailureReason.tooManyRequests);
      await openView(tester);
      await enterCode(tester, code);
      await tapVerify(tester);

      expect(find.text('Too many attempts. Please wait a few minutes and try '
          'again.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('resending a recovery code repeats the recovery request, '
        'after the minute the provider asks for', (tester) async {
      await openView(tester);
      Finder resend() => find.widgetWithText(OutlinedButton, 'Send a new code');

      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull,
          reason: 'the request that led here just sent one');
      await tester.pump(const Duration(seconds: 61));
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNotNull);

      await tester.tap(resend());
      await tester.pump();

      expect(adapter.resetRequests, hasLength(1));
      expect(adapter.resetRequests.single.email, address);
      expect(adapter.resetRequests.single.redirectTo,
          AuthService.recoveryRedirect,
          reason: 'the same request, so an old-style link still returns to '
              'the recovery callback');
      expect(adapter.resends, isEmpty, reason: 'not the sign-up resend');
      expect(find.text('A new code is on its way.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull,
          reason: 'and the wait starts again');
      await close(tester);
    });

    testWidgets('resending a sign-up code uses the sign-up resend, not the '
        'recovery request', (tester) async {
      await openView(tester, purpose: EmailCodePurpose.signup);
      await tester.pump(const Duration(seconds: 61));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Send a new code'));
      await tester.pump();

      expect(adapter.resends.single.email, address);
      expect(adapter.resetRequests, isEmpty);
      await close(tester);
    });

    testWidgets('the provider refusing a resend is worded as a wait and the '
        'button waits again', (tester) async {
      await openView(tester);
      await tester.pump(const Duration(seconds: 61));
      adapter.resetFailure =
          const InfrastructureFailure(FailureReason.tooManyRequests);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Send a new code'));
      await tester.pump();

      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Send a new code'))
              .onPressed,
          isNull);
      await close(tester);
    });

    testWidgets('"Back to log in" leaves safely, with nothing recorded',
        (tester) async {
      await openView(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Back to log in'));
      await tester.pumpAndSettle();

      expect(find.byType(EmailCodeView), findsNothing);
      expect(recovery.isInProgress, isFalse);
      expect(adapter.journal, isEmpty);
    });

    testWidgets('is in Arabic in Arabic, and the digits typed there work',
        (tester) async {
      await openView(tester, locale: const Locale('ar'));

      expect(find.text('أدخل الرمز الذي أرسلناه إلى بريدك الإلكتروني.'),
          findsOneWidget);
      expect(find.text('تحقق'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '٤٨٢٩١٣');
      await tester.tap(find.widgetWithText(FilledButton, 'تحقق'));
      await tester.pumpAndSettle();

      expect(adapter.recoveryVerifications.single.code, code);
      await close(tester);
    });
  });

  group('asking for a recovery email', () {
    testWidgets('leads to the code screen, not to the reset screen, and asks '
        'the provider once', (tester) async {
      final adapter = ScriptedAuthAdapter();
      final service = AuthService(adapter, PasswordRecoveryState());
      await pumpGate(tester, service);

      await requestRecovery(tester, service);

      expect(find.byType(EmailCodeView), findsOneWidget);
      expect(tester.widget<EmailCodeView>(find.byType(EmailCodeView)).purpose,
          EmailCodePurpose.recovery);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(adapter.resetRequests, hasLength(1));
      expect(adapter.recoveryVerifications, isEmpty,
          reason: 'nothing is verified until a code is entered');
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ===========================================================================
  // 3. The gate
  // ===========================================================================

  group('a recovery code, through the gate', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    Future<void> verifyCode(WidgetTester tester) async {
      await requestRecovery(tester, service);
      await enterCode(tester, code);
      await tapVerify(tester);
    }

    testWidgets('a right code reaches the reset screen -- and never Home, an '
        'account check or the code screen again', (tester) async {
      await pumpGate(tester, service);

      await verifyCode(tester);

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(EmailCodeView), findsNothing);
      expect(adapter.accountStateChecks, 0,
          reason: 'a recovery session is not entering the product');
      expect(recovery.isInProgress, isTrue);
      expect(await persisted(), isTrue);
    });

    testWidgets('the record is already durable when the session appears',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      bool? onDisk;
      adapter.onVerify =
          () => onDisk = prefs.getBool(PasswordRecoveryState.storageKey);
      await pumpGate(tester, service);

      await verifyCode(tester);

      expect(onDisk, isTrue);
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
    });

    testWidgets('and it is still the reset screen after the provider\'s own '
        'event is withheld, because the record is what the gate reads',
        (tester) async {
      // A restart in the middle of a reset: nothing is listening for events, and
      // the durable record is all there is.
      await recovery.begin();
      adapter = ScriptedAuthAdapter(signedIn: true);
      service = AuthService(adapter, recovery);

      await pumpGate(tester, service);

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('choosing the new password signs out, clears the record and '
        'returns to Login with the news', (tester) async {
      await pumpGate(tester, service);
      await verifyCode(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'a-new-password');
      await tester.enterText(fields.at(1), 'a-new-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
      await tester.pumpAndSettle();

      expect(adapter.journal,
          ['verifyRecoveryCode', 'changePassword', 'signOut'],
          reason: 'the password is changed before the session ends');
      expect(adapter.isSignedIn, isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Your password was changed. Log in with your new '
          'password.'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('cancelling ends the session and the record, and lands on '
        'what a visitor sees', (tester) async {
      await pumpGate(tester, service);
      await verifyCode(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(adapter.isSignedIn, isFalse);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('a refused code leaves the code screen up, and an ordinary '
        'sign-in that follows is an ordinary one', (tester) async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);
      await pumpGate(tester, service);
      await verifyCode(tester);

      expect(find.byType(EmailCodeView), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(recovery.isInProgress, isFalse);

      // The person gives up on the code and signs in with their password.
      adapter.emit(AuthEvent.signedIn, signedIn: true);
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('a recovery LINK opened while the code screen is up still '
        'reaches the reset screen (compatibility with the old email)',
        (tester) async {
      await pumpGate(tester, service);
      await requestRecovery(tester, service);
      expect(find.byType(EmailCodeView), findsOneWidget);

      // What the running application does with a link: record it, then the SDK
      // exchanges it and announces a recovery.
      await recovery.captureLink(
          'https://go-play-staging.pages.dev/login-callback/recovery'
          '#access_token=a&type=recovery');
      adapter.emit(AuthEvent.passwordRecovery, signedIn: true);
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(EmailCodeView), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
      expect(adapter.recoveryVerifications, isEmpty,
          reason: 'no code was involved');
    });
  });

  group('a sign-up code, through the gate', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    Future<void> verify(WidgetTester tester) async {
      await pumpGate(tester, service);
      await push(
          tester,
          Scaffold(
            body: EmailCodeView(
              purpose: EmailCodePurpose.signup,
              email: address,
              authService: service,
            ),
          ));
      await enterCode(tester, code);
      await tapVerify(tester);
    }

    testWidgets('an active account goes to Home, through the account check',
        (tester) async {
      await verify(tester);

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(adapter.accountStateChecks, 1);
      expect(recovery.isInProgress, isFalse,
          reason: 'an ordinary session, never a recovery');
      expect(await persisted(), isFalse);
    });

    testWidgets('an account with no player profile is asked for one, as it '
        'always was', (tester) async {
      adapter.accountState = AccountState.profileRequired;

      await verify(tester);

      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a suspended account still reaches the suspension screen',
        (tester) async {
      adapter.accountState = AccountState.suspended;

      await verify(tester);

      expect(find.byType(AccountSuspendedScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a refused code leaves the person where they are, signed out',
        (tester) async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);

      await verify(tester);

      expect(find.byType(EmailCodeView), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(adapter.isSignedIn, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ===========================================================================
  // 3b. Signing in with an address that is not verified yet
  // ===========================================================================

  group('what the provider\'s refusal is called', () {
    Failure map(Object error) => SupabaseFailureMapper.from(error);

    AuthApiException refusal(String code,
            {String status = '400', String message = 'refused'}) =>
        AuthApiException(message, statusCode: status, code: code);

    test('email_not_confirmed is the dedicated reason, and only that code is',
        () {
      final failure = map(refusal('email_not_confirmed',
          message: 'Email not confirmed'));

      expect(failure, isA<AuthenticationFailure>());
      expect(failure.reason, FailureReason.emailNotConfirmed);
    });

    test('nothing else is: every other refusal keeps the meaning it had', () {
      final cases = <String, (Failure, FailureReason?)>{
        // The password was wrong, or nobody has that address -- one answer.
        'invalid_credentials': (map(refusal('invalid_credentials')), null),
        'user_not_found': (map(refusal('user_not_found')), null),
        // An account the provider has banned.
        'user_banned': (map(refusal('user_banned', status: '403')), null),
        'validation_failed': (map(refusal('validation_failed')), null),
        'provider_disabled': (map(refusal('provider_disabled')), null),
        'flow_state_not_found': (map(refusal('flow_state_not_found')), null),
        // A refused email code is its own thing.
        'otp_expired': (
          map(refusal('otp_expired', status: '403')),
          FailureReason.invalidEmailCode
        ),
        // A limit is a wait.
        'over_request_rate_limit': (
          map(refusal('over_request_rate_limit', status: '429')),
          FailureReason.tooManyRequests
        ),
        'over_email_send_rate_limit': (
          map(refusal('over_email_send_rate_limit', status: '429')),
          FailureReason.tooManyRequests
        ),
        // A taken address is a conflict.
        'user_already_exists': (
          map(refusal('user_already_exists', status: '422')),
          FailureReason.emailAlreadyUsed
        ),
      };

      for (final entry in cases.entries) {
        final (failure, reason) = entry.value;
        expect(failure.reason, reason, reason: entry.key);
        expect(failure.reason, isNot(FailureReason.emailNotConfirmed),
            reason: entry.key);
      }
    });

    test('a request that never reached the provider is a network failure',
        () {
      final failure = map(AuthRetryableFetchException(message: 'x'));

      expect(failure, isA<NetworkFailure>());
      expect(failure.reason, isNot(FailureReason.emailNotConfirmed));
    });

    test('the words alone are not enough: a message that resembles it, with '
        'no code, is an ordinary refusal', () {
      // The sign-in screen acts on this reason by opening the verification flow,
      // so it is never reached from prose.
      for (final message in [
        'Email not confirmed',
        'email_not_confirmed',
        'Please confirm your email',
      ]) {
        final failure = map(AuthApiException(message, statusCode: '400'));

        expect(failure, isA<AuthenticationFailure>(), reason: message);
        expect(failure.reason, isNull, reason: message);
      }
    });
  });

  group('signing in with an address that is not verified yet', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    const unverified = AuthenticationFailure(FailureReason.emailNotConfirmed);

    setUp(() {
      adapter = ScriptedAuthAdapter()..signInFailure = unverified;
      recovery = PasswordRecoveryState();
      service = AuthService(adapter, recovery);
    });

    /// Login, then a sign-in the provider refuses for the unverified address.
    Future<void> reachCodeScreen(WidgetTester tester,
        {String email = address}) async {
      await pumpGate(tester, service);
      await openLogin(tester, service);
      await logIn(tester, email: email);
    }

    testWidgets('opens the sign-up code screen instead of "login failed", '
        'without asking for anything to be entered again', (tester) async {
      await reachCodeScreen(tester);

      final view = tester.widget<EmailCodeView>(find.byType(EmailCodeView));
      expect(view.purpose, EmailCodePurpose.signup);
      expect(find.text('Verify your email to complete registration.'),
          findsOneWidget);
      expect(find.text(loginFailed), findsNothing);
      expect(find.byType(TextFormField), findsNothing,
          reason: 'no form: nobody registers, or types a password, again');
      expect(find.byType(CompletePlayerProfileScreen), findsNothing);
      expect(adapter.isSignedIn, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is for the address typed on Login, trimmed', (tester) async {
      await reachCodeScreen(tester, email: '  $address ');

      expect(tester.widget<EmailCodeView>(find.byType(EmailCodeView)).email,
          address);
      expect(find.textContaining(address), findsOneWidget);

      await enterCode(tester, '482 913');
      await tapVerify(tester);

      expect(adapter.signupVerifications.single, (email: address, code: code));
      expect(adapter.recoveryVerifications, isEmpty);
    });

    testWidgets('does not keep or reuse the password', (tester) async {
      await reachCodeScreen(tester);
      await enterCode(tester, code);
      await tapVerify(tester);

      expect(adapter.signIns, hasLength(1),
          reason: 'sent once, to sign in; verifying a code never signs in '
              'again with it');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty,
          reason: 'no password, no code, and no recovery record');
    });

    testWidgets('going back asks for the password afresh, and keeps the '
        'address', (tester) async {
      await reachCodeScreen(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Back to log in'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      expect(tester.widget<TextFormField>(fields.at(0)).controller!.text,
          address);
      expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, '');
    });

    testWidgets('a right code hands the rest to the gate: Home, through the '
        'account check, as an ordinary session', (tester) async {
      await reachCodeScreen(tester);

      await enterCode(tester, code);
      await tapVerify(tester);

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(EmailCodeView), findsNothing);
      expect(adapter.accountStateChecks, 1);
      expect(recovery.isInProgress, isFalse);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    });

    testWidgets('and an account that has no player profile is asked for one, '
        'as always', (tester) async {
      adapter.accountState = AccountState.profileRequired;
      await reachCodeScreen(tester);

      await enterCode(tester, code);
      await tapVerify(tester);

      expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a wrong or expired code stays on the code screen', (tester) async {
      adapter.verifyFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);
      await reachCodeScreen(tester);

      await enterCode(tester, code);
      await tapVerify(tester);

      expect(find.textContaining('incorrect or has expired'), findsOneWidget);
      expect(find.byType(EmailCodeView), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(adapter.isSignedIn, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sending a new code is the sign-up resend, and is allowed at '
        'once because nothing has just been sent', (tester) async {
      await reachCodeScreen(tester);
      Finder resend() => find.widgetWithText(OutlinedButton, 'Send a new code');

      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNotNull);
      expect(find.textContaining('in a minute'), findsNothing);

      await tester.tap(resend());
      await tester.pump();

      expect(adapter.resends.single.email, address);
      expect(adapter.resends.single.redirectTo, AuthService.authCallbackRedirect);
      expect(adapter.resetRequests, isEmpty, reason: 'not a recovery request');
      expect(find.text('A new code is on its way.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull,
          reason: 'and then the provider\'s minute applies');
      expect(find.textContaining('in a minute'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the provider refusing a new code is worded as a wait',
        (tester) async {
      adapter.resendFailure =
          const InfrastructureFailure(FailureReason.tooManyRequests);
      await reachCodeScreen(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Send a new code'));
      await tester.pump();

      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(adapter.resends, isEmpty);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Send a new code'))
              .onPressed,
          isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Back is the ordinary login form, and the app bar\'s back '
        'means the same before it leaves the login screen', (tester) async {
      await reachCodeScreen(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Back to log in'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailCodeView), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));

      // And once more, this time leaving through the app bar.
      await logIn(tester);
      expect(find.byType(EmailCodeView), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EmailCodeView), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget,
          reason: 'still on the login screen, showing the form');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(DiscoverScreen), findsOneWidget);
    });

    testWidgets('a wrong password does not open it', (tester) async {
      adapter.signInFailure = const AuthenticationFailure();

      await pumpGate(tester, service);
      await openLogin(tester, service);
      await logIn(tester);

      expect(find.text(loginFailed), findsOneWidget);
      expect(find.byType(EmailCodeView), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(adapter.resends, isEmpty);
      expect(adapter.signupVerifications, isEmpty);
    });

    testWidgets('nor does a refusal that only shares its type with it, such '
        'as a refused email code', (tester) async {
      adapter.signInFailure =
          const AuthenticationFailure(FailureReason.invalidEmailCode);

      await pumpGate(tester, service);
      await openLogin(tester, service);
      await logIn(tester);

      expect(find.text(loginFailed), findsOneWidget);
      expect(find.byType(EmailCodeView), findsNothing);
    });

    testWidgets('nor does having no connection', (tester) async {
      adapter.signInFailure = const NetworkFailure();

      await pumpGate(tester, service);
      await openLogin(tester, service);
      await logIn(tester);

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);
      expect(find.byType(EmailCodeView), findsNothing);
    });

    testWidgets('a verified, ordinary login is unchanged: Home, and no code '
        'screen', (tester) async {
      adapter.signInFailure = null;

      await pumpGate(tester, service);
      await openLogin(tester, service);
      await logIn(tester, email: '  $address ');

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(EmailCodeView), findsNothing);
      expect(adapter.signIns.single.email, address);
      expect(adapter.signupVerifications, isEmpty);
    });

    group('and the registration conversion', () {
      const target = PublicLinkTarget(
          PublicLinkKind.player, '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d');
      final previous = AcquisitionAnalytics.instance;
      late _Acquisitions acquisitions;

      setUp(() {
        acquisitions = _Acquisitions();
        AcquisitionAnalytics.instance = AcquisitionAnalytics(
          repository: AcquisitionAnalyticsRepository(acquisitions),
          isSignedIn: () => false,
          pendingTarget: ValueNotifier(target),
        );
      });
      tearDown(() => AcquisitionAnalytics.instance = previous);

      testWidgets('is not counted when an earlier registration is finished '
          'from Login: a login is never a signup', (tester) async {
        AcquisitionAnalytics.instance.externalArrivalLoaded(target);
        await reachCodeScreen(tester);

        await enterCode(tester, code);
        await tapVerify(tester);

        expect(find.byType(HomeShell), findsOneWidget,
            reason: 'the gate has confirmed an active account');
        expect(acquisitions.completions, isEmpty);
      });
    });
  });

  // ===========================================================================
  // 4. The real SDK
  // ===========================================================================

  group('the real SDK', () {
    late _Provider provider;
    late SupabaseClient client;
    late PasswordRecoveryState recovery;
    late SupabaseAuthAdapter adapter;
    late AuthService service;

    setUp(() {
      provider = _Provider();
      client = provider.newClient();
      recovery = PasswordRecoveryState();
      adapter = SupabaseAuthAdapter.forRecoveryTest(
        client,
        implicitAuthClient: provider.newImplicitAuthClient,
        web: true,
      );
      service = AuthService(adapter, recovery);
    });

    tearDown(() async => client.dispose());

    /// The failure a call raised, or the fact that it raised none.
    Future<Object?> failureOf(Future<void> call) async {
      try {
        await call;
        return null;
      } catch (error) {
        return error;
      }
    }

    group('what is asked of the provider', () {
      test('a recovery code is verified with type "recovery", by address and '
          'digits, and the session lands in the app\'s own client', () async {
        final events = <AuthEvent>[];
        final subscription = adapter.authEvents.listen(events.add);

        await adapter.verifyRecoveryCode(email: address, code: code);
        await Future<void>.delayed(Duration.zero);

        expect(provider.requests, ['POST /auth/v1/verify']);
        final body = provider.bodies['POST /auth/v1/verify']!;
        expect(body['type'], 'recovery');
        expect(body['email'], address);
        expect(body['token'], code);
        expect(body.containsKey('token_hash'), isFalse);
        expect(client.auth.currentSession, isNotNull);
        expect(adapter.isSignedIn, isTrue);
        expect(events, contains(AuthEvent.passwordRecovery),
            reason: 'the SDK announces a recovery for this type');
        await subscription.cancel();
      });

      test('a sign-up code is verified with type "signup", and the SDK '
          'announces an ordinary sign-in', () async {
        final events = <AuthEvent>[];
        final subscription = adapter.authEvents.listen(events.add);

        await adapter.verifySignupCode(email: address, code: code);
        await Future<void>.delayed(Duration.zero);

        expect(provider.bodies['POST /auth/v1/verify']!['type'], 'signup');
        expect(events, contains(AuthEvent.signedIn));
        expect(events, isNot(contains(AuthEvent.passwordRecovery)));
        await subscription.cancel();
      });

      test('the web recovery request is still the one without a PKCE '
          'challenge, so an old-style link redeems in any browser', () async {
        await adapter.requestPasswordReset(address,
            redirectTo: AuthService.recoveryRedirect);

        expect(provider.requests, ['POST /auth/v1/recover']);
        final body = provider.bodies['POST /auth/v1/recover']!;
        expect(body['code_challenge'], isNull);
        expect(body['code_challenge_method'], isNull);
      });

      test('resending a sign-up code is the SDK\'s resend, type "signup"',
          () async {
        await service.resendConfirmation('  $address ');

        expect(provider.requests, ['POST /auth/v1/resend']);
        final body = provider.bodies['POST /auth/v1/resend']!;
        expect(body['type'], 'signup');
        expect(body['email'], address);
      });

      test('a registration the provider holds for confirmation comes back as '
          '"confirmation required", with nobody signed in', () async {
        provider.signUpReturnsSession = false;

        final outcome = await adapter.signUp(
          email: address,
          password: 'password1',
          fullName: 'Sara Al Balushi',
          position: PlayerPosition.mid,
          phone: '+96890123456',
          dateOfBirth: DateTime(1999, 1, 1),
          secondaryPosition: null,
          redirectTo: AuthService.authCallbackRedirect,
        );

        expect(outcome, SignUpOutcome.confirmationRequired);
        expect(adapter.isSignedIn, isFalse);
      });

      test('a registration that came with a session is unchanged: signed in',
          () async {
        provider.signUpReturnsSession = true;

        final outcome = await adapter.signUp(
          email: address,
          password: 'password1',
          fullName: 'Sara Al Balushi',
          position: PlayerPosition.mid,
          phone: '+96890123456',
          dateOfBirth: DateTime(1999, 1, 1),
          secondaryPosition: null,
          redirectTo: AuthService.authCallbackRedirect,
        );

        expect(outcome, SignUpOutcome.signedIn);
        expect(adapter.isSignedIn, isTrue);
        expect(provider.requests, ['POST /auth/v1/signup'],
            reason: 'and nothing was asked to be verified');
      });

      test('signing in with a password is unchanged and asks for no code',
          () async {
        await adapter.signIn(email: address, password: 'password1');

        expect(provider.requests, ['POST /auth/v1/token']);
        expect(provider.queries['POST /auth/v1/token']!['grant_type'],
            'password');
        expect(adapter.isSignedIn, isTrue);
      });
    });

    group('what the provider answers', () {
      for (final purpose in EmailCodePurpose.values) {
        Future<void> verify() => purpose == EmailCodePurpose.recovery
            ? adapter.verifyRecoveryCode(email: address, code: code)
            : adapter.verifySignupCode(email: address, code: code);

        test('an expired or wrong ${purpose.name} code is one failure with '
            'one reason, and nobody is signed in', () async {
          provider.verify = _Verify.expired;

          final failure = await failureOf(verify());

          expect(failure, isA<AuthenticationFailure>());
          expect((failure as AuthenticationFailure).reason,
              FailureReason.invalidEmailCode);
          expect(adapter.isSignedIn, isFalse);
        });

        test('and from the older error shape too (${purpose.name})',
            () async {
          provider
            ..legacyErrorShape = true
            ..verify = _Verify.expired;

          final failure = await failureOf(verify());

          expect((failure as AuthenticationFailure).reason,
              FailureReason.invalidEmailCode);
        });

        test('and it is recognised from the message when an older server '
            'sends no error code (${purpose.name})', () async {
          provider.verify = _Verify.expiredWithoutCode;

          final failure = await failureOf(verify());

          expect((failure as AuthenticationFailure).reason,
              FailureReason.invalidEmailCode);
        });

        test('the provider limiting attempts is a wait, not a wrong code '
            '(${purpose.name})', () async {
          provider.verify = _Verify.rateLimited;

          final failure = await failureOf(verify());

          expect(failure, isA<InfrastructureFailure>());
          expect((failure as InfrastructureFailure).reason,
              FailureReason.tooManyRequests);
        });

        test('an answer with no session is a refusal, never a success '
            '(${purpose.name})', () async {
          provider.verify = _Verify.noSession;

          final failure = await failureOf(verify());

          expect((failure as AuthenticationFailure).reason,
              FailureReason.invalidEmailCode);
          expect(adapter.isSignedIn, isFalse);
        });
      }
    });

    group('through the gate', () {
      Future<void> pumpRealGate(WidgetTester tester) => pumpGate(tester, service);

      testWidgets('a recovery: request, code, reset screen -- the durable '
          'record set, no account check, no Home', (tester) async {
        await pumpRealGate(tester);

        await requestRecovery(tester, service);
        await enterCode(tester, code);
        await tapVerify(tester);

        expect(provider.requests, [
          'POST /auth/v1/recover',
          'POST /auth/v1/verify',
        ]);
        expect(find.byType(ResetPasswordScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        expect(find.byType(ForgotPasswordScreen), findsNothing);
        expect(recovery.isInProgress, isTrue);
        expect(await persisted(), isTrue);
      });

      testWidgets('and choosing the password signs out over the real SDK, '
          'clears the record and returns to Login', (tester) async {
        await pumpRealGate(tester);
        await requestRecovery(tester, service);
        await enterCode(tester, code);
        await tapVerify(tester);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'a-new-password');
        await tester.enterText(fields.at(1), 'a-new-password');
        await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
        await tester.pumpAndSettle();

        expect(provider.requests.skip(2), [
          'PUT /auth/v1/user',
          'POST /auth/v1/logout',
        ]);
        expect(adapter.isSignedIn, isFalse);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.textContaining('password was changed'), findsOneWidget);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
      });

      testWidgets('an expired code stays on the code screen with a useful '
          'message, no session and no record', (tester) async {
        provider.verify = _Verify.expired;
        await pumpRealGate(tester);

        await requestRecovery(tester, service);
        await enterCode(tester, code);
        await tapVerify(tester);

        expect(find.textContaining('incorrect or has expired'), findsOneWidget);
        expect(find.byType(EmailCodeView), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(adapter.isSignedIn, isFalse);
        expect(recovery.isInProgress, isFalse);
        expect(await persisted(), isFalse);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('a sign-up code confirms the account and carries on '
          'through the account-state check to Home', (tester) async {
        await pumpRealGate(tester);
        await push(
            tester,
            Scaffold(
              body: EmailCodeView(
                purpose: EmailCodePurpose.signup,
                email: address,
                authService: service,
              ),
            ));

        await enterCode(tester, code);
        await tapVerify(tester);

        expect(provider.requests.first, 'POST /auth/v1/verify');
        expect(provider.requests, contains('POST /rest/v1/rpc/get_my_account_state'));
        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(ResetPasswordScreen), findsNothing);
        expect(recovery.isInProgress, isFalse);
      });

      testWidgets('and an account whose profile is missing is asked for it',
          (tester) async {
        provider.accountState = 'PROFILE_REQUIRED';
        await pumpRealGate(tester);
        await push(
            tester,
            Scaffold(
              body: EmailCodeView(
                purpose: EmailCodePurpose.signup,
                email: address,
                authService: service,
              ),
            ));

        await enterCode(tester, code);
        await tapVerify(tester);

        expect(find.byType(CompletePlayerProfileScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
      });
    });

    group('signing in', () {
      for (final legacy in [false, true]) {
        final shape =
            legacy ? 'the older error shape' : 'the current error shape';

        test('an unverified address is the dedicated failure -- the code is '
            'read from the structured field ($shape)', () async {
          provider
            ..legacyErrorShape = legacy
            ..signIn = _SignIn.notConfirmed;

          final failure = await failureOf(
              adapter.signIn(email: address, password: 'password1'));

          expect(failure, isA<AuthenticationFailure>());
          expect((failure as AuthenticationFailure).reason,
              FailureReason.emailNotConfirmed);
          expect(adapter.isSignedIn, isFalse);
        });

        test('a wrong password and an unknown address are the same ordinary '
            'failure, indistinguishable ($shape)', () async {
          provider
            ..legacyErrorShape = legacy
            ..signIn = _SignIn.invalidCredentials;

          final failure = await failureOf(
              adapter.signIn(email: address, password: 'not-the-password'));

          expect(failure, isA<AuthenticationFailure>());
          expect((failure as AuthenticationFailure).reason, isNull);
        });
      }

      test('the provider limiting sign-ins is a wait, not an unverified '
          'address', () async {
        provider.signIn = _SignIn.rateLimited;

        final failure = await failureOf(
            adapter.signIn(email: address, password: 'password1'));

        expect(failure, isA<InfrastructureFailure>());
        expect((failure as InfrastructureFailure).reason,
            FailureReason.tooManyRequests);
      });
    });

    group('a login that finds the address unverified, through the gate', () {
      Future<void> reach(WidgetTester tester,
          {_SignIn signIn = _SignIn.notConfirmed,
          bool legacy = false,
          String password = 'password1'}) async {
        provider
          ..signIn = signIn
          ..legacyErrorShape = legacy;
        await pumpGate(tester, service);
        await openLogin(tester, service);
        await logIn(tester, password: password);
      }

      for (final legacy in [false, true]) {
        testWidgets('resumes the verification for the typed address: one '
            'sign-in, then the code, then Home (${legacy ? 'older' : 'current'} '
            'error shape)', (tester) async {
          await reach(tester, legacy: legacy);

          expect(find.byType(EmailCodeView), findsOneWidget);
          expect(find.text(loginFailed), findsNothing);
          expect(provider.requests, ['POST /auth/v1/token'],
              reason: 'the password was checked first, by the provider, and '
                  'nothing else has been asked of it');

          await enterCode(tester, code);
          await tapVerify(tester);

          final verify = provider.bodies['POST /auth/v1/verify']!;
          expect(verify['type'], 'signup');
          expect(verify['email'], address);
          expect(verify['token'], code);
          expect(verify.containsKey('password'), isFalse);
          expect(provider.requests.where((r) => r == 'POST /auth/v1/token'),
              hasLength(1),
              reason: 'verifying never signs in with the password again');
          expect(provider.requests,
              contains('POST /rest/v1/rpc/get_my_account_state'));
          expect(find.byType(HomeShell), findsOneWidget);
          expect(recovery.isInProgress, isFalse);
        });
      }

      testWidgets('a wrong password does not reach it, and neither does an '
          'address nobody registered -- the provider answers both alike',
          (tester) async {
        await reach(tester,
            signIn: _SignIn.invalidCredentials, password: 'wrong');

        expect(find.text(loginFailed), findsOneWidget);
        expect(find.byType(EmailCodeView), findsNothing);
        expect(provider.requests, ['POST /auth/v1/token'],
            reason: 'no resend, no verification: nothing was offered');
      });

      testWidgets('an expired code on the resumed screen says so and stays',
          (tester) async {
        provider.verify = _Verify.expired;
        await reach(tester);

        await enterCode(tester, code);
        await tapVerify(tester);

        expect(find.textContaining('incorrect or has expired'), findsOneWidget);
        expect(find.byType(EmailCodeView), findsOneWidget);
        expect(adapter.isSignedIn, isFalse);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('a new code is the SDK\'s sign-up resend, and can be asked '
          'for at once', (tester) async {
        await reach(tester);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Send a new code'));
        await tester.pumpAndSettle();

        expect(provider.requests.last, 'POST /auth/v1/resend');
        final body = provider.bodies['POST /auth/v1/resend']!;
        expect(body['type'], 'signup');
        expect(body['email'], address);
        expect(body.containsKey('password'), isFalse);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('a confirmed account signs in exactly as before',
          (tester) async {
        await reach(tester, signIn: _SignIn.ok);

        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.byType(EmailCodeView), findsNothing);
        expect(provider.requests.where((r) => r.contains('/verify')), isEmpty);
      });

      testWidgets('the password and the code are never written to storage or '
          'the log', (tester) async {
        final logged = <String>[];
        final previous = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) =>
            logged.add(message ?? '');
        try {
          await reach(tester, password: 'hunter2-hunter2');
          await enterCode(tester, code);
          await tapVerify(tester);
          expect(find.byType(HomeShell), findsOneWidget);
        } finally {
          debugPrint = previous;
        }

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), isEmpty);
        final stored = provider.storage.values.values.join();
        for (final secret in ['hunter2-hunter2', code]) {
          expect(stored, isNot(contains(secret)), reason: 'SDK storage');
          expect(logged.join('\n'), isNot(contains(secret)), reason: 'log');
        }
        expect(logged.join('\n'), isNot(contains(address)));
      });
    });

    group('what is kept, and what is not', () {
      testWidgets('the code is never written to storage or to the log -- not '
          'when it is right and not when it is wrong', (tester) async {
        final logged = <String>[];
        final previous = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) =>
            logged.add(message ?? '');
        try {
          await pumpGate(tester, service);

          // Wrong first, then right.
          provider.verify = _Verify.expired;
          await requestRecovery(tester, service);
          await enterCode(tester, code);
          await tapVerify(tester);
          provider.verify = _Verify.session;
          await tapVerify(tester);
          expect(find.byType(ResetPasswordScreen), findsOneWidget);
        } finally {
          // Restored here, not in a tear-down: the test binding checks it is
          // back to normal before tear-downs run.
          debugPrint = previous;
        }

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {PasswordRecoveryState.storageKey},
            reason: 'the recovery flag, and nothing else');
        for (final key in prefs.getKeys()) {
          expect('${prefs.get(key)}', isNot(contains(code)));
        }
        expect(provider.storage.values.values.join(), isNot(contains(code)),
            reason: 'nor in the SDK\'s own storage');

        final everything = logged.join('\n');
        expect(everything, isNot(contains(code)));
        expect(everything, isNot(contains(address)));
        expect(everything, isNot(contains(provider.accessToken)));
        expect(provider.requests.join(), isNot(contains(code)),
            reason: 'nor in a path');
      });
    });
  });
}

/// A port whose verification waits to be released, to hold the request open.
class _SlowVerifyAdapter extends ScriptedAuthAdapter {
  final release = Completer<void>();
  int asked = 0;

  @override
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    asked++;
    await release.future;
    return super.verifyRecoveryCode(email: email, code: code);
  }
}

/// What the provider answers to `POST /auth/v1/verify`.
enum _Verify {
  session,

  /// 403 `otp_expired`: what Supabase says for a wrong code, an expired one, a
  /// used one and an address nobody registered alike.
  expired,

  /// The same, from a server that sends no `error_code`.
  expiredWithoutCode,

  rateLimited,

  /// A 200 that carries a user and no session.
  noSession,
}

class _MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

/// What the provider answers to a password sign-in.
enum _SignIn {
  ok,

  /// 400 `email_not_confirmed`: the password was right and the address has not
  /// been verified. The provider checks the password first.
  notConfirmed,

  /// 400 `invalid_credentials`: a wrong password and an unknown address, alike.
  invalidCredentials,

  rateLimited,
}

/// What the acquisition port was asked, counted from 1 like a database would.
class _Acquisitions implements AcquisitionAnalyticsAdapter {
  int opens = 0;
  final completions = <String>[];

  @override
  Future<String> recordAnonymousOpen(PublicLinkKind kind) async =>
      'acq-${++opens}';

  @override
  Future<void> recordSignupCompleted(String acquisitionId) async =>
      completions.add(acquisitionId);
}

/// The provider's Auth and REST endpoints, as far as these flows reach them.
/// Records requests by method and path, and bodies and queries by what they
/// carried -- the code is asserted on, so it is kept only in `bodies`.
class _Provider {
  _Provider() {
    accessToken = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': 'u-1', 'role': 'authenticated', 'exp': 4102444800})}'
        '.sig';
  }

  late final String accessToken;
  final storage = _MemoryStorage();

  _Verify verify = _Verify.session;
  _SignIn signIn = _SignIn.ok;
  bool signUpReturnsSession = false;

  /// The shape of an error body. Real Supabase answers a request that carries
  /// `x-supabase-api-version: 2024-01-01` -- which supabase_flutter always
  /// sends, and which this was checked against on the live project -- with
  /// `{"code": "<error_code>", "message": ...}` and echoes the header, and the SDK
  /// reads the code from `code`. The older shape is
  /// `{"code": <status>, "error_code": ..., "msg": ...}`. Both are answered by
  /// real servers, so the tests that matter run under each; this is the current
  /// one unless a test says otherwise.
  bool legacyErrorShape = false;
  String accountState = 'ACTIVE';

  final requests = <String>[];
  final bodies = <String, Map<String, Object?>>{};
  final queries = <String, Map<String, String>>{};

  static String _b64(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  Map<String, Object?> get _user => {
        'id': 'u-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'sara@example.com',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-01-01T00:00:00Z',
      };

  Map<String, Object?> get _session => {
        'access_token': accessToken,
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh',
        'user': _user,
      };

  http.Response _json(http.Request request, Object? body,
          [int status = 200, Map<String, String> headers = const {}]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json', ...headers},
        request: request,
      );

  http.Response _apiError(
      http.Request request, int status, String code, String message) {
    if (legacyErrorShape) {
      return _json(request,
          {'code': status, 'error_code': code, 'msg': message}, status);
    }
    return _json(request, {'code': code, 'message': message}, status,
        {'x-supabase-api-version': '2024-01-01'});
  }

  http.Client get _transport => MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        requests.add(key);
        queries[key] = request.url.queryParameters;
        if (request.body.isNotEmpty) {
          try {
            bodies[key] = jsonDecode(request.body) as Map<String, Object?>;
          } catch (_) {}
        }

        switch (key) {
          case 'POST /auth/v1/verify':
            return switch (verify) {
              _Verify.session => _json(request, _session),
              _Verify.expired => _apiError(request, 403, 'otp_expired',
                  'Token has expired or is invalid'),
              _Verify.expiredWithoutCode => _json(request, {
                  'code': 403,
                  'msg': 'Token has expired or is invalid',
                }, 403),
              _Verify.rateLimited => _apiError(request, 429,
                  'over_request_rate_limit', 'Request rate limit reached'),
              _Verify.noSession => _json(request, _user),
            };
          case 'POST /auth/v1/signup':
            return _json(
                request,
                signUpReturnsSession
                    ? _session
                    : {..._user, 'confirmation_sent_at': '2026-01-01T00:00:00Z'});
          case 'POST /auth/v1/token':
            return switch (signIn) {
              _SignIn.ok => _json(request, _session),
              _SignIn.notConfirmed => _apiError(
                  request, 400, 'email_not_confirmed', 'Email not confirmed'),
              _SignIn.invalidCredentials => _apiError(request, 400,
                  'invalid_credentials', 'Invalid login credentials'),
              _SignIn.rateLimited => _apiError(request, 429,
                  'over_request_rate_limit', 'Request rate limit reached'),
            };
          case 'POST /auth/v1/recover':
          case 'POST /auth/v1/resend':
            return _json(request, <String, Object?>{});
          case 'GET /auth/v1/user':
          case 'PUT /auth/v1/user':
            return _json(request, _user);
          case 'POST /auth/v1/logout':
            return http.Response.bytes(const [], 204, request: request);
          case 'POST /rest/v1/rpc/get_my_account_state':
            return _json(request, accountState);
        }
        return _json(request, <Object?>[]);
      });

  SupabaseClient newClient() => SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        httpClient: _transport,
        authOptions: AuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: false,
          pkceAsyncStorage: storage,
        ),
      );

  GoTrueClient newImplicitAuthClient() => GoTrueClient(
        url: 'http://localhost:54321/auth/v1',
        headers: const {'apikey': 'test-publishable-key'},
        httpClient: _transport,
        autoRefreshToken: false,
        flowType: AuthFlowType.implicit,
      );
}
