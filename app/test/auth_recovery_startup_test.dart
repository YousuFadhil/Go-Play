import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/password_recovery_state.dart';
import 'package:go_play/features/auth/reset_password_screen.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/home/home_shell.dart';
import 'package:go_play/infrastructure/supabase/supabase_auth_adapter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

/// The web cold start of a password recovery, run against the **real Supabase
/// SDK** over a replaced transport.
///
/// `auth_modernization_gate_test.dart` drives the gate with a fake identity port,
/// which is right for what the gate decides but cannot say whether the *sequence*
/// holds: the application records the launch address, the SDK then exchanges the
/// link's credentials and emits its event -- before anything is listening -- and
/// only then does the gate read what was recorded. These tests run that sequence.
///
/// **What "the SDK initialises" means here.** On the web `Supabase.initialize()`
/// reads the address the page was opened on and, when it carries an auth
/// parameter, awaits `auth.getSessionFromUrl` (supabase_flutter 2.16.0,
/// `SupabaseAuth._handleDeeplink`). That is private and needs a browser, so
/// [_sdkInitialises] performs the same two steps against the real client. A
/// persisted session is restored *first*, as the SDK does.
///
/// The Product Owner's failed Staging UAT is the sixth group: the recovery was
/// requested in one browser and the link opened in another, so the browser that
/// opened it held no PKCE verifier and the SDK made no request at all.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The gate renders the real destinations, which build their Supabase
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

  const staging = 'https://go-play-staging.pages.dev';
  const verifierKey = 'supabase.auth.token-code-verifier';

  String b64(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final accessToken = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${b64({'sub': 'u-1', 'role': 'authenticated', 'exp': 4102444800})}.sig';

  const user = {
    'id': 'u-1',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'player@example.invalid',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-01-01T00:00:00Z',
  };

  Map<String, Object?> sessionJson() => {
        'access_token': accessToken,
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh',
        'user': user,
      };

  // The two recovery callbacks a provider can return, and the ordinary one.
  final implicitRecovery = '$staging/login-callback/recovery'
      '#access_token=$accessToken&expires_in=3600&refresh_token=refresh'
      '&token_type=bearer&type=recovery';
  const codeRecovery = '$staging/login-callback/recovery?code=good';
  const googleCallback = '$staging/login-callback?code=good';

  Widget app(AuthService service) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AuthGate(authService: service),
      );

  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<bool> persisted() async => (await SharedPreferences.getInstance())
          .getBool(PasswordRecoveryState.storageKey) ??
      false;

  /// The provider, as far as these tests need it. Records what was asked, by
  /// method and path and by the *names* of body fields -- never their values.
  group('harness', () {
    test('records requests by method and path only', () async {
      final provider = _Provider(accessToken);
      final client = provider.newClient();
      await client.auth.getUser(accessToken);
      expect(provider.requests, ['GET /auth/v1/user']);
    });
  });

  group('web cold start from a recovery callback', () {
    testWidgets('an implicit callback (#access_token…&type=recovery) reaches '
        'the reset screen', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(launch.recovery.isInProgress, isTrue);
      expect(await persisted(), isTrue);
      expect(launch.provider.requests, ['GET /auth/v1/user'],
          reason: 'the fragment was exchanged for a session, and nothing '
              'else -- in particular no account check');
    });

    testWidgets('and it does so without the provider\'s event, which the SDK '
        'emitted before anything was listening', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
            silentEvents: true,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget,
          reason: 'the durable record made from the launch address is enough');
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a code callback (?code=…) does too, when this browser holds '
        'the verifier', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            codeRecovery,
            accessToken: accessToken,
            verifier: 'v/passwordRecovery',
            silentEvents: true,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(launch.provider.requests, ['POST /auth/v1/token']);
      expect(launch.recovery.isInProgress, isTrue);
    });

    testWidgets('the recovery is what the gate reads first, whatever the '
        'account is', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
            accountState: 'SUSPENDED',
            silentEvents: true,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(
          launch.provider.requests
              .where((r) => r.contains('get_my_account_state')),
          isEmpty);
    });
  });

  group('what is not a recovery', () {
    testWidgets('a Google callback, returning on the ordinary path, is an '
        'ordinary sign-in', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            googleCallback,
            accessToken: accessToken,
            verifier: 'v',
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(launch.recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('an ordinary persisted session is an ordinary session',
        (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            '$staging/',
            accessToken: accessToken,
            persistedSession: sessionJson(),
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(launch.recovery.isInProgress, isFalse);
    });

    testWidgets('a bare recovery path shows nobody the reset screen',
        (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            '$staging/login-callback/recovery',
            accessToken: accessToken,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(launch.recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('nor does it give an ordinary session a reset context',
        (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            '$staging/login-callback/recovery',
            accessToken: accessToken,
            persistedSession: sessionJson(),
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsNothing,
          reason: 'typing the address of the recovery page is not a recovery');
      expect(find.byType(HomeShell), findsOneWidget);
      expect(launch.recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    testWidgets('an expired recovery link (an error, no credentials) is not '
        'one either', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            '$staging/login-callback/recovery'
            '?error=access_denied&error_code=otp_expired',
            accessToken: accessToken,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(launch.recovery.isInProgress, isFalse);
    });
  });

  group('across a restart', () {
    testWidgets('a recovery that was under way is the reset screen again, '
        'with no link and no event', (tester) async {
      tallSurface(tester);
      final first = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
            silentEvents: true,
          )))!;
      await tester.pumpWidget(app(first.service));
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      final stored = first.client.auth.currentSession!.toJson();

      // The process dies. What is left is the provider's persisted session and
      // the application's own record; the address it is reopened on has nothing.
      await tester.pumpWidget(const SizedBox());
      final restarted = (await tester.runAsync(() => _coldStart(
            '$staging/',
            accessToken: accessToken,
            persistedSession: stored,
            silentEvents: true,
          )))!;

      await tester.pumpWidget(app(restarted.service));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(
          restarted.provider.requests
              .where((r) => r.contains('get_my_account_state')),
          isEmpty);
    });

    testWidgets('a session that restores as an ordinary one stays ordinary',
        (tester) async {
      tallSurface(tester);
      final first = (await tester.runAsync(() => _coldStart(
            googleCallback,
            accessToken: accessToken,
            verifier: 'v',
          )))!;
      await tester.pumpWidget(app(first.service));
      await tester.pumpAndSettle();
      final stored = first.client.auth.currentSession!.toJson();

      await tester.pumpWidget(const SizedBox());
      final restarted = (await tester.runAsync(() => _coldStart(
            '$staging/',
            accessToken: accessToken,
            persistedSession: stored,
          )))!;
      await tester.pumpWidget(app(restarted.service));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    });
  });

  group('finishing, through the real adapter', () {
    Future<void> enterPasswords(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), 'a-new-password');
      await tester.enterText(find.byType(TextFormField).at(1), 'a-new-password');
    }

    testWidgets('changes the password, signs out, clears the record and '
        'returns to the login', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
            silentEvents: true,
          )))!;
      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();
      launch.provider.requests.clear();

      await enterPasswords(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
      await tester.pumpAndSettle();

      expect(launch.provider.requests, ['PUT /auth/v1/user', 'POST /auth/v1/logout'],
          reason: 'the password first, then the session ends');
      expect(launch.provider.bodyFields['PUT /auth/v1/user'], contains('password'));
      expect(launch.client.auth.currentSession, isNull);
      expect(launch.recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Your password was changed. Log in with your new '
          'password.'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('cancelling signs out and clears the record', (tester) async {
      tallSurface(tester);
      final launch = (await tester.runAsync(() => _coldStart(
            implicitRecovery,
            accessToken: accessToken,
            silentEvents: true,
          )))!;
      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();
      launch.provider.requests.clear();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(launch.provider.requests, ['POST /auth/v1/logout']);
      expect(launch.client.auth.currentSession, isNull);
      expect(launch.recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
      expect(find.byType(DiscoverScreen), findsOneWidget);
    });
  });

  group('the failed Staging UAT: requested in one browser, opened in another',
      () {
    testWidgets('a recovery link opened where no verifier was stored makes no '
        'exchange, creates no session, and shows the public page',
        (tester) async {
      tallSurface(tester);
      // Requested in Safari; this is Chrome, whose storage has no verifier.
      final launch = (await tester.runAsync(() => _coldStart(
            codeRecovery,
            accessToken: accessToken,
          )))!;

      await tester.pumpWidget(app(launch.service));
      await tester.pumpAndSettle();

      expect(launch.provider.requests, isEmpty,
          reason: 'the SDK refuses before any request: the log fingerprint of '
              'the failure is the absence of a /token call');
      expect(launch.client.auth.currentSession, isNull);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(launch.recovery.isInProgress, isFalse,
          reason: 'a record with no session behind it is dropped');
      expect(await persisted(), isFalse);
    });

    test('so on the web the recovery email is requested without a PKCE '
        'challenge, and stores no verifier a different browser would lack',
        () async {
      final provider = _Provider(accessToken);
      final storage = _MemoryPkceStorage();
      final adapter = SupabaseAuthAdapter.forRecoveryTest(
        provider.newClient(storage),
        implicitAuthClient: provider.newImplicitAuthClient,
        web: true,
      );

      await adapter.requestPasswordReset(
        'player@example.invalid',
        redirectTo: AuthService.webRecoveryRedirect(Uri.parse(staging)),
      );

      expect(provider.requests, ['POST /auth/v1/recover']);
      final body = provider.bodies['POST /auth/v1/recover']!;
      expect(body['code_challenge'], isNull);
      expect(body['code_challenge_method'], isNull);
      expect(provider.queries['POST /auth/v1/recover']!['redirect_to'],
          '$staging/login-callback/recovery');
      expect(storage.values, isEmpty,
          reason: 'nothing that only this browser could redeem');
    });

    test('and that email\'s link, which returns the session in the fragment, '
        'redeems in a browser that never made the request', () async {
      final provider = _Provider(accessToken);
      final other = provider.newClient(_MemoryPkceStorage());

      await other.auth.getSessionFromUrl(Uri.parse(implicitRecovery));

      expect(other.auth.currentSession, isNotNull);
      expect(provider.requests, ['GET /auth/v1/user']);
    });

    test('on Android the request stays PKCE: the link opens the app that '
        'holds the verifier', () async {
      final provider = _Provider(accessToken);
      final storage = _MemoryPkceStorage();
      final adapter = SupabaseAuthAdapter.forRecoveryTest(
        provider.newClient(storage),
        implicitAuthClient: provider.newImplicitAuthClient,
        web: false,
      );

      await adapter.requestPasswordReset(
        'player@example.invalid',
        redirectTo: AuthService.nativeRecoveryRedirect,
      );

      final body = provider.bodies['POST /auth/v1/recover']!;
      expect(body['code_challenge'], isNotNull);
      expect(body['code_challenge_method'], 's256');
      expect(storage.values[verifierKey], endsWith('/passwordRecovery'));
    });

    test('the web request still maps the provider\'s refusals', () async {
      final provider = _Provider(accessToken)..recoverStatus = 429;
      final adapter = SupabaseAuthAdapter.forRecoveryTest(
        provider.newClient(_MemoryPkceStorage()),
        implicitAuthClient: provider.newImplicitAuthClient,
        web: true,
      );

      await expectLater(
        adapter.requestPasswordReset('player@example.invalid',
            redirectTo: '$staging/login-callback/recovery'),
        throwsA(isA<Object>().having(
            (e) => e.toString(), 'a rate-limit failure', contains('tooManyRequests'))),
      );
    });
  });
}

// ---------------------------------------------------------------------------

/// What the app and the SDK do at launch, in order. See the file comment.
Future<_Launch> _coldStart(
  String launchUrl, {
  required String accessToken,
  String? verifier,
  Map<String, Object?>? persistedSession,
  bool silentEvents = false,
  String accountState = 'ACTIVE',
}) async {
  final provider = _Provider(accessToken)..accountState = accountState;
  final storage = _MemoryPkceStorage();
  if (verifier != null) {
    storage.values['supabase.auth.token-code-verifier'] = verifier;
  }
  final client = provider.newClient(storage);

  // 1. The application: read what was recorded, and record this launch.
  final recovery = PasswordRecoveryState();
  await recovery.startUp(launchLocation: launchUrl);

  // 2. The SDK initialises: it restores a persisted session first...
  if (persistedSession != null) {
    await client.auth.setInitialSession(jsonEncode(persistedSession));
  }
  // ...and then exchanges the launch address if it carries an auth parameter.
  await _sdkInitialises(client, launchUrl);

  // 3. The application is up.
  final adapter = silentEvents
      ? _SilentEvents(client, provider)
      : SupabaseAuthAdapter.forRecoveryTest(
          client,
          implicitAuthClient: provider.newImplicitAuthClient,
          web: true,
        );
  return _Launch(provider, client, recovery, AuthService(adapter, recovery));
}

/// `SupabaseAuth._handleDeeplink`, as supabase_flutter 2.16.0 runs it during
/// `Supabase.initialize()` on the web: ignore an address that carries no auth
/// parameter, otherwise exchange it and swallow the failure (the SDK reports it
/// on a stream nobody depends on).
Future<void> _sdkInitialises(SupabaseClient client, String launchUrl) async {
  final uri = Uri.parse(launchUrl);
  final fragment = uri.fragment.isEmpty
      ? const <String, String>{}
      : Uri.splitQueryString(uri.fragment);
  bool has(String key) =>
      uri.queryParameters.containsKey(key) || fragment.containsKey(key);
  final carriesAuth = has('access_token') ||
      has('code') ||
      has('error') ||
      has('error_code') ||
      has('error_description');
  if (!carriesAuth) return;
  try {
    await client.auth.getSessionFromUrl(uri);
  } on AuthException {
    // Reported by the SDK on its own stream; nothing here depends on it.
  }
}

class _Launch {
  _Launch(this.provider, this.client, this.recovery, this.service);

  final _Provider provider;
  final SupabaseClient client;
  final PasswordRecoveryState recovery;
  final AuthService service;
}

/// The real adapter with the provider's event withheld: the SDK emits it while
/// it initialises, before anything listens, so the application must not need it.
class _SilentEvents extends SupabaseAuthAdapter {
  _SilentEvents(super.client, _Provider provider)
      : super.forRecoveryTest(
          implicitAuthClient: provider.newImplicitAuthClient,
          web: true,
        );

  @override
  Stream<AuthEvent> get authEvents => const Stream.empty();
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

/// The provider's Auth and REST endpoints, as far as these flows reach them.
class _Provider {
  _Provider(this._accessToken);

  final String _accessToken;
  String accountState = 'ACTIVE';
  int recoverStatus = 200;

  /// "METHOD /path", in order. No query values, no body values, no tokens.
  final requests = <String>[];
  final bodies = <String, Map<String, Object?>>{};
  final queries = <String, Map<String, String>>{};

  /// The *names* of the fields each request carried.
  Map<String, Set<String>> get bodyFields =>
      {for (final e in bodies.entries) e.key: e.value.keys.toSet()};

  Map<String, Object?> get _user => {
        'id': 'u-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'player@example.invalid',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-01-01T00:00:00Z',
      };

  http.Response _json(http.Request request, Object? body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  http.Client get _transport => MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        requests.add(key);
        queries[key] = request.url.queryParameters;
        Map<String, Object?> body = const {};
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body) as Map<String, Object?>;
          } catch (_) {}
          bodies[key] = body;
        }

        switch (key) {
          case 'POST /auth/v1/token':
            if (request.url.queryParameters['grant_type'] == 'pkce' &&
                body['auth_code'] == 'good') {
              return _json(request, {
                'access_token': _accessToken,
                'token_type': 'bearer',
                'expires_in': 3600,
                'refresh_token': 'refresh',
                'user': _user,
              });
            }
            return _json(request, {'code': 400, 'msg': 'invalid flow state'}, 400);
          case 'GET /auth/v1/user':
          case 'PUT /auth/v1/user':
            return _json(request, _user);
          case 'POST /auth/v1/logout':
            return http.Response.bytes(const [], 204, request: request);
          case 'POST /auth/v1/recover':
            return recoverStatus == 200
                ? _json(request, <String, Object?>{})
                : _json(request, {
                    'code': recoverStatus,
                    'error_code': 'over_email_send_rate_limit',
                    'msg': 'rate limited',
                  }, recoverStatus);
          case 'POST /rest/v1/rpc/get_my_account_state':
            return _json(request, accountState);
        }
        return _json(request, <Object?>[]);
      });

  SupabaseClient newClient([GotrueAsyncStorage? storage]) => SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        httpClient: _transport,
        authOptions: AuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: false,
          pkceAsyncStorage: storage ?? _MemoryPkceStorage(),
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
