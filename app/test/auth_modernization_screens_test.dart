import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/check_email_view.dart';
import 'package:go_play/features/auth/forgot_password_screen.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/register_screen.dart';

import 'auth_modernization_fakes.dart';

/// The sign-in, registration and password-recovery screens under the
/// authentication modernization: the email-confirmation state, the Google
/// action, "Forgot password?", and the neutral reset request.
///
/// Every screen is driven through the real `AuthService` over a fake identity
/// port, so the path from a tap to the port is the production one.
void main() {
  Widget host(Widget Function(BuildContext) screen,
      {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // A root the screen is pushed over, as it is in the application: the
      // registration and login forms are always destinations, never the root.
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester,
    Widget Function(BuildContext) screen, {
    Locale locale = const Locale('en'),
  }) async {
    // Tall enough for the whole of the longer forms; they scroll, and the
    // default test window would leave the buttons below the fold.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen, locale: locale));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('registration', () {
    Future<ScriptedAuthAdapter> openRegister(
      WidgetTester tester, {
      SignUpOutcome outcome = SignUpOutcome.signedIn,
      Locale locale = const Locale('en'),
    }) async {
      final adapter = ScriptedAuthAdapter()..signUpOutcome = outcome;
      await open(
        tester,
        (_) => RegisterScreen(authService: AuthService(adapter)),
        locale: locale,
      );
      return adapter;
    }

    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(
          find.byType(TextFormField).at(0), 'Sara Al Balushi');
      await tester.enterText(
          find.byType(TextFormField).at(1), '  sara@example.com ');
      await tester.enterText(find.byType(TextFormField).at(2), '90123456');
      await tester.enterText(find.byType(TextFormField).at(3), 'password1');
      await tester.tap(find.text('Select date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<PlayerPosition>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Midfielder').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
    }

    testWidgets('a sign-up that produced a session leaves the screen to the '
        'gate, as it always did', (tester) async {
      final adapter = await openRegister(tester);

      await fillAndSubmit(tester);

      expect(adapter.signUps, hasLength(1));
      expect(find.byType(RegisterScreen), findsNothing,
          reason: 'unwound to the root, where the gate takes over');
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('the platform callback is passed to the provider',
        (tester) async {
      final adapter = await openRegister(tester);

      await fillAndSubmit(tester);

      expect(adapter.signUps.single.redirectTo,
          AuthService.authCallbackRedirect);
    });

    testWidgets('a sign-up held for confirmation does not behave as though '
        'the person were signed in', (tester) async {
      final adapter = await openRegister(
          tester, outcome: SignUpOutcome.confirmationRequired);

      await fillAndSubmit(tester);

      expect(adapter.signUps, hasLength(1));
      expect(adapter.isSignedIn, isFalse);
      // Still on the registration route, now showing where the email went.
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('sara@example.com'), findsOneWidget,
          reason: 'the trimmed address, so the person can see if it is wrong');
      expect(find.byType(TextFormField), findsNothing,
          reason: 'the form is gone; asking again would suggest it had failed');
    });

    testWidgets('resending is held back for a minute, then allowed, then held '
        'back again', (tester) async {
      final adapter = await openRegister(
          tester, outcome: SignUpOutcome.confirmationRequired);
      await fillAndSubmit(tester);

      Finder resend() => find.widgetWithText(OutlinedButton, 'Resend email');
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull,
          reason: 'the sign-up itself just sent one');
      expect(find.textContaining('in a minute'), findsOneWidget);

      await tester.pump(const Duration(seconds: 59));
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNotNull);
      expect(find.textContaining('in a minute'), findsNothing);

      await tester.tap(resend());
      await tester.pump();

      expect(adapter.resends.single.email, 'sara@example.com');
      expect(adapter.resends.single.redirectTo,
          AuthService.authCallbackRedirect);
      expect(find.text('Confirmation email sent again.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(resend()).onPressed, isNull,
          reason: 'and the provider\'s limit starts again');

      // Let the timer run out so nothing is pending when the test ends.
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('the provider limiting it is worded as a wait, and the button '
        'waits again', (tester) async {
      final adapter = await openRegister(
          tester, outcome: SignUpOutcome.confirmationRequired);
      await fillAndSubmit(tester);
      await tester.pump(const Duration(seconds: 61));
      adapter.resendFailure =
          const InfrastructureFailure(FailureReason.tooManyRequests);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Resend email'));
      await tester.pump();

      expect(find.text('Too many attempts. Please wait a few minutes and try '
          'again.'), findsOneWidget);
      expect(adapter.resends, isEmpty);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Resend email'))
              .onPressed,
          isNull);

      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('no connection while resending is said so', (tester) async {
      final adapter = await openRegister(
          tester, outcome: SignUpOutcome.confirmationRequired);
      await fillAndSubmit(tester);
      await tester.pump(const Duration(seconds: 61));
      adapter.resendFailure = const NetworkFailure();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Resend email'));
      await tester.pump();

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('"Back to log in" returns to where the person came from',
        (tester) async {
      await openRegister(tester, outcome: SignUpOutcome.confirmationRequired);
      await fillAndSubmit(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Back to log in'));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('an address that is already registered still says so',
        (tester) async {
      final adapter = await openRegister(tester)
        ..signUpFailure =
            const ConflictFailure(FailureReason.emailAlreadyUsed);

      await fillAndSubmit(tester);

      expect(find.text('This email is already registered.'), findsOneWidget);
      expect(adapter.signUps, isEmpty);
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('the confirmation state is in Arabic in Arabic',
        (tester) async {
      await open(
        tester,
        (_) => Scaffold(
          body: CheckEmailView(
            email: 'sara@example.com',
            authService: AuthService(ScriptedAuthAdapter()),
          ),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('تحقق من بريدك الإلكتروني'), findsOneWidget);
      expect(find.textContaining('sara@example.com'), findsOneWidget);
      expect(find.text('إعادة إرسال الرسالة'), findsOneWidget);
      expect(find.text('العودة إلى تسجيل الدخول'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('Continue with Google', () {
    Future<ScriptedAuthAdapter> openLogin(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      final adapter = ScriptedAuthAdapter();
      await open(
        tester,
        (_) => LoginScreen(authService: AuthService(adapter)),
        locale: locale,
      );
      return adapter;
    }

    Future<ScriptedAuthAdapter> openRegister(WidgetTester tester) async {
      final adapter = ScriptedAuthAdapter();
      await open(
        tester,
        (_) => RegisterScreen(authService: AuthService(adapter)),
      );
      return adapter;
    }

    testWidgets('is offered on the login screen, for both people who arrive '
        'there', (tester) async {
      await openLogin(tester);

      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('is offered on the registration screen too', (tester) async {
      await openRegister(tester);

      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('asks the application\'s auth abstraction, and only that, '
        'with the shared callback', (tester) async {
      final adapter = await openLogin(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(adapter.googleRedirects, [AuthService.authCallbackRedirect]);
      expect(find.byType(LoginScreen), findsOneWidget,
          reason: 'nothing here decides the outcome; the redirect returns '
              'through the session, and the gate moves the app on');
    });

    testWidgets('works from the registration screen the same way',
        (tester) async {
      final adapter = await openRegister(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(adapter.googleRedirects, [AuthService.authCallbackRedirect]);
    });

    testWidgets('a browser that cannot be opened is said so', (tester) async {
      final adapter = await openLogin(tester);
      adapter.googleFailure = const AuthenticationFailure();

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('Could not start Google sign-in. Please try again.'),
          findsOneWidget);
      expect(adapter.googleRedirects, isEmpty);
    });

    testWidgets('no connection is said so', (tester) async {
      final adapter = await openLogin(tester);
      adapter.googleFailure = const NetworkFailure();

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);
    });

    testWidgets('is in Arabic in Arabic', (tester) async {
      await openLogin(tester, locale: const Locale('ar'));

      expect(find.text('المتابعة باستخدام Google'), findsOneWidget);
      expect(find.text('أو'), findsOneWidget);
    });
  });

  group('Forgot password?', () {
    testWidgets('is on the login screen and opens the request, carrying the '
        'email already typed', (tester) async {
      await open(tester,
          (_) => LoginScreen(authService: AuthService(ScriptedAuthAdapter())));

      await tester.enterText(
          find.byType(TextFormField).at(0), ' sara@example.com ');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      final email =
          tester.widget<TextFormField>(find.byType(TextFormField).first);
      expect(email.controller!.text, 'sara@example.com');
    });

    testWidgets('the login screen after a reset says it worked, and only '
        'then', (tester) async {
      await open(
          tester,
          (_) => LoginScreen(
                authService: AuthService(ScriptedAuthAdapter()),
                passwordResetSucceeded: true,
              ));
      expect(find.text('Your password was changed. Log in with your new '
          'password.'), findsOneWidget);
    });

    testWidgets('an ordinary login screen has no such banner', (tester) async {
      await open(tester,
          (_) => LoginScreen(authService: AuthService(ScriptedAuthAdapter())));

      expect(find.textContaining('password was changed'), findsNothing);
    });
  });

  group('the reset request', () {
    Future<ScriptedAuthAdapter> openForgot(
      WidgetTester tester, {
      String initialEmail = '',
      Locale locale = const Locale('en'),
    }) async {
      final adapter = ScriptedAuthAdapter();
      await open(
        tester,
        (_) => ForgotPasswordScreen(
          authService: AuthService(adapter),
          initialEmail: initialEmail,
        ),
        locale: locale,
      );
      return adapter;
    }

    Future<void> send(WidgetTester tester, String email) async {
      await tester.enterText(find.byType(TextFormField), email);
      await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
      await tester.pumpAndSettle();
    }

    const neutral = 'If that email belongs to an account, a reset link is on '
        'its way. Check your inbox and your spam folder.';

    testWidgets('an empty address is refused before the port', (tester) async {
      final adapter = await openForgot(tester);

      await send(tester, '   ');

      expect(find.text('Email is required'), findsOneWidget);
      expect(adapter.resetRequests, isEmpty);
    });

    testWidgets('something that is not an address is refused before the port',
        (tester) async {
      final adapter = await openForgot(tester);

      await send(tester, 'not-an-email');

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(adapter.resetRequests, isEmpty);
    });

    testWidgets('asks for the trimmed address with the platform callback',
        (tester) async {
      final adapter = await openForgot(tester);

      await send(tester, '  sara@example.com ');

      expect(adapter.resetRequests.single.email, 'sara@example.com');
      expect(adapter.resetRequests.single.redirectTo,
          AuthService.authCallbackRedirect);
    });

    testWidgets('answers in neutral words, and never echoes the address',
        (tester) async {
      await openForgot(tester);

      await send(tester, 'sara@example.com');

      expect(find.text(neutral), findsOneWidget);
      expect(find.textContaining('sara@example.com'), findsNothing);
      expect(find.byType(TextFormField), findsNothing,
          reason: 'the form is replaced, so it cannot be hammered');
    });

    testWidgets('the answer is the same for an address that is not '
        'registered', (tester) async {
      // The port raises nothing for either, so what the person sees for one
      // address is what they see for any other.
      await openForgot(tester);
      await send(tester, 'registered@example.com');
      final first = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      await tester.pumpWidget(const SizedBox());
      await openForgot(tester);
      await send(tester, 'nobody-has-this@example.com');
      final second = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      expect(second, first);
    });

    testWidgets('"Back to log in" goes back', (tester) async {
      await openForgot(tester);
      await send(tester, 'sara@example.com');

      await tester.tap(find.widgetWithText(FilledButton, 'Back to log in'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsNothing);
    });

    testWidgets('no connection is said so, and the form stays for another try',
        (tester) async {
      final adapter = await openForgot(tester);
      adapter.resetFailure = const NetworkFailure();

      await send(tester, 'sara@example.com');

      expect(find.text('Could not reach the server. Check your internet '
          'connection.'), findsOneWidget);
      expect(find.text(neutral), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('the provider limiting it is worded as a wait',
        (tester) async {
      final adapter = await openForgot(tester);
      adapter.resetFailure =
          const InfrastructureFailure(FailureReason.tooManyRequests);

      await send(tester, 'sara@example.com');

      expect(find.text('Too many attempts. Please wait a few minutes and try '
          'again.'), findsOneWidget);
      expect(find.text(neutral), findsNothing);
    });

    testWidgets('anything else is the generic message, not a reason',
        (tester) async {
      final adapter = await openForgot(tester);
      adapter.resetFailure = const UnknownFailure();

      await send(tester, 'sara@example.com');

      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget);
    });

    testWidgets('is in Arabic in Arabic', (tester) async {
      await openForgot(tester, locale: const Locale('ar'));

      expect(find.text('إعادة تعيين كلمة المرور'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'sara@example.com');
      await tester.tap(find.text('إرسال رابط إعادة التعيين'));
      await tester.pumpAndSettle();

      expect(
          find.text('إن كان هذا البريد يخص حساباً فقد أُرسل إليه رابط إعادة '
              'التعيين. تحقق من صندوق الوارد ومن البريد غير المرغوب فيه.'),
          findsOneWidget);
    });
  });
}
