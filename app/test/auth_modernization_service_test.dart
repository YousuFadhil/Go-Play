import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/password_recovery_state.dart';
import 'package:go_play/infrastructure/supabase/supabase_auth_adapter.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_modernization_fakes.dart';

/// The application side of the authentication modernization: what `AuthService`
/// decides, what the Supabase adapter sends and how it reads what comes back,
/// and how the provider's refusals become the application's own failures.
///
/// The adapter is driven through a real `SupabaseClient` whose HTTP transport is
/// replaced, so what is asserted is the request the SDK would actually make and
/// the response it would actually parse — nothing here reaches a network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService: sign-up', () {
    late ScriptedAuthAdapter adapter;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter();
      service = AuthService(adapter);
    });

    Future<SignUpOutcome> register({DateTime? dateOfBirth}) => service.register(
          email: ' sara@example.com ',
          localPhone: '9012 3456',
          password: 'password1',
          fullName: ' Sara Al Balushi ',
          position: PlayerPosition.mid,
          dateOfBirth: dateOfBirth ?? DateTime(1995, 6, 15, 13, 30),
          secondaryPosition: PlayerPosition.def,
        );

    test('a project that signs the account in straight away says so', () async {
      adapter.signUpOutcome = SignUpOutcome.signedIn;

      expect(await register(), SignUpOutcome.signedIn);
    });

    test('a project that holds the account for confirmation says so, too',
        () async {
      adapter.signUpOutcome = SignUpOutcome.confirmationRequired;

      expect(await register(), SignUpOutcome.confirmationRequired);
      expect(adapter.isSignedIn, isFalse,
          reason: 'no session was created, and nothing pretends otherwise');
    });

    test('the platform callback is what the provider is told to send people to',
        () async {
      await register();

      final call = adapter.signUps.single;
      expect(call.redirectTo, AuthService.authCallbackRedirect);
      // The tests run on a VM, not in a browser, so this is the native form.
      expect(call.redirectTo, 'goplay://login-callback');
    });

    test('the web form is the running origin, whatever path the reader was on',
        () {
      expect(
        AuthService.webEmailChangeRedirect(
            Uri.parse('https://go-play-staging.pages.dev/community/abc?x=1')),
        'https://go-play-staging.pages.dev/login-callback',
      );
      expect(
        AuthService.webEmailChangeRedirect(Uri.parse('http://localhost:8080/')),
        'http://localhost:8080/login-callback',
      );
    });

    test('one callback serves the email change, sign-up confirmation and '
        'Google', () {
      expect(AuthService.authCallbackRedirect, AuthService.emailChangeRedirect);
    });

    test('password recovery has its own, so it is recognisable on arrival', () {
      expect(AuthService.nativeRecoveryRedirect,
          'goplay://login-callback/recovery');
      expect(AuthService.recoveryRedirect, AuthService.nativeRecoveryRedirect,
          reason: 'a VM, not a browser');
      expect(
        AuthService.webRecoveryRedirect(
            Uri.parse('https://go-play-staging.pages.dev/community/abc?x=1')),
        'https://go-play-staging.pages.dev/login-callback/recovery',
      );
      expect(AuthService.recoveryRedirect,
          isNot(AuthService.authCallbackRedirect));
      expect(AuthService.recoveryRedirect,
          startsWith('${AuthService.authCallbackRedirect}/'),
          reason: 'the ordinary callback with one segment added, so the same '
              'manifest filter and origin serve it');
    });

    test('the profile reaches the port exactly as registration always sent it',
        () async {
      await register();

      final call = adapter.signUps.single;
      expect(call.email, 'sara@example.com');
      expect(call.fullName, 'Sara Al Balushi');
      expect(call.phone, '+96890123456');
      expect(call.position, PlayerPosition.mid);
      expect(call.secondaryPosition, PlayerPosition.def);
      expect(call.dateOfBirth, DateTime(1995, 6, 15),
          reason: 'a date, not a timestamp');
    });

    test('a date of birth that has not happened never reaches the provider',
        () async {
      await expectLater(
        register(dateOfBirth: DateTime.now().add(const Duration(days: 2))),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.signUps, isEmpty);
    });

    test('resending the confirmation names the address and the same callback',
        () async {
      await service.resendConfirmation('  sara@example.com ');

      expect(adapter.resends.single.email, 'sara@example.com');
      expect(adapter.resends.single.redirectTo, AuthService.authCallbackRedirect);
    });

    test('resending to something that is not an address asks nothing',
        () async {
      await expectLater(service.resendConfirmation('nope'),
          throwsA(isA<ValidationFailure>()));
      expect(adapter.resends, isEmpty);
    });
  });

  group('AuthService: Google', () {
    test('asks the port, with the same callback everything else uses',
        () async {
      final adapter = ScriptedAuthAdapter();

      await AuthService(adapter).signInWithGoogle();

      expect(adapter.googleRedirects, [AuthService.authCallbackRedirect]);
    });

    test('a refusal from the port is the caller\'s to see', () async {
      final adapter = ScriptedAuthAdapter()
        ..googleFailure = const AuthenticationFailure();

      await expectLater(AuthService(adapter).signInWithGoogle(),
          throwsA(isA<AuthenticationFailure>()));
    });
  });

  group('AuthService: password recovery', () {
    late ScriptedAuthAdapter adapter;
    late PasswordRecoveryState recovery;
    late AuthService service;

    Future<bool> persisted() async => (await SharedPreferences.getInstance())
            .getBool(PasswordRecoveryState.storageKey) ??
        false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      adapter = ScriptedAuthAdapter(signedIn: true);
      recovery = PasswordRecoveryState();
      await recovery.load();
      await recovery.begin();
      service = AuthService(adapter, recovery);
    });

    test('a request names the trimmed address and the recovery callback',
        () async {
      await service.requestPasswordReset('  sara@example.com ');

      expect(adapter.resetRequests.single.email, 'sara@example.com');
      expect(adapter.resetRequests.single.redirectTo,
          AuthService.recoveryRedirect,
          reason: 'not the ordinary callback: the address the link comes back '
              'to is how a recovery is recognised');
    });

    test('something that is not an address never reaches the provider',
        () async {
      for (final bad in ['', '   ', 'sara', 'sara@', '@example.com']) {
        await expectLater(service.requestPasswordReset(bad),
            throwsA(isA<ValidationFailure>()),
            reason: '"$bad"');
      }
      expect(adapter.resetRequests, isEmpty);
    });

    test('the answer does not depend on the address', () async {
      // The port raises nothing for an unregistered address and the service adds
      // nothing: both complete the same way with nothing to tell them apart.
      await service.requestPasswordReset('registered@example.com');
      await service.requestPasswordReset('nobody@example.com');

      expect(adapter.resetRequests, hasLength(2));
    });

    test('finishing changes the password and only then ends the session',
        () async {
      await service.completePasswordRecovery('a-new-password');

      expect(adapter.passwordChanges, ['a-new-password']);
      expect(adapter.journal, ['changePassword', 'signOut']);
      expect(adapter.isSignedIn, isFalse,
          reason: 'a recovery session must not survive as a product session');
    });

    test('and only then clears the durable record, and from storage too',
        () async {
      bool? atSignOut;
      adapter.onSignOut = () => atSignOut = recovery.isInProgress;

      await service.completePasswordRecovery('a-new-password');

      expect(atSignOut, isTrue,
          reason: 'still set when the session ends: interrupted here, the next '
              'start is met by the reset screen, not by an ordinary session');
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    test('cancelling ends the session and then clears the record', () async {
      bool? atSignOut;
      adapter.onSignOut = () => atSignOut = recovery.isInProgress;

      await service.cancelPasswordRecovery();

      expect(adapter.passwordChanges, isEmpty);
      expect(adapter.signOuts, 1);
      expect(adapter.isSignedIn, isFalse);
      expect(atSignOut, isTrue);
      expect(recovery.isInProgress, isFalse);
      expect(await persisted(), isFalse);
    });

    test('a cancel that cannot end the session keeps the record', () async {
      adapter
        ..signOutFailure = const NetworkFailure()
        ..signOutLeavesSession = true;

      await expectLater(service.cancelPasswordRecovery(),
          throwsA(isA<NetworkFailure>()));

      expect(adapter.isSignedIn, isTrue);
      expect(recovery.isInProgress, isTrue,
          reason: 'clearing it over a live recovery session is the one thing '
              'the record exists to prevent');
      expect(await persisted(), isTrue);
    });

    test('a cancel whose call failed but whose session is gone still clears it',
        () async {
      adapter.signOutFailure = const NetworkFailure();

      await service.cancelPasswordRecovery();

      expect(adapter.isSignedIn, isFalse);
      expect(recovery.isInProgress, isFalse);
    });

    test('a refusal from the provider keeps the record', () async {
      adapter.changePasswordFailure = const AuthenticationFailure();

      await expectLater(service.completePasswordRecovery('a-new-password'),
          throwsA(isA<AuthenticationFailure>()));

      expect(recovery.isInProgress, isTrue);
      expect(await persisted(), isTrue);
    });

    test('a password below the minimum keeps the record', () async {
      await expectLater(service.completePasswordRecovery('short'),
          throwsA(isA<ValidationFailure>()));

      expect(recovery.isInProgress, isTrue);
    });

    test('the provider\'s event is remembered as a backup', () async {
      await recovery.clear();
      expect(service.recoveryInProgress.value, isFalse);

      await service.beginPasswordRecovery();

      expect(service.recoveryInProgress.value, isTrue);
      expect(await persisted(), isTrue);
    });

    test('a record with nothing behind it can be discarded', () async {
      await service.discardPasswordRecovery();

      expect(service.recoveryInProgress.value, isFalse);
      expect(await persisted(), isFalse);
    });

    test('a password below the minimum changes nothing and keeps the session',
        () async {
      await expectLater(service.completePasswordRecovery('short'),
          throwsA(isA<ValidationFailure>()));

      expect(adapter.passwordChanges, isEmpty);
      expect(adapter.signOuts, 0);
      expect(adapter.isSignedIn, isTrue);
    });

    test('the same minimum as everywhere else is what counts', () async {
      await service
          .completePasswordRecovery('x' * AuthService.minimumPasswordLength);

      expect(adapter.passwordChanges, hasLength(1));
    });

    test('a refusal from the provider leaves the session for another try',
        () async {
      adapter.changePasswordFailure = const AuthenticationFailure();

      await expectLater(service.completePasswordRecovery('a-new-password'),
          throwsA(isA<AuthenticationFailure>()));

      expect(adapter.signOuts, 0, reason: 'nothing changed, so nothing ends');
      expect(adapter.isSignedIn, isTrue);
    });

    test('the password changed, so a failed sign-out call is not reported '
        'as though it had not', () async {
      // The provider clears its own session before it tells the server.
      adapter.signOutFailure = const NetworkFailure();

      await service.completePasswordRecovery('a-new-password');

      expect(adapter.isSignedIn, isFalse);
      expect(recovery.isInProgress, isFalse);
    });

    test('but a session that is somehow still there is a real failure, and '
        'the record stays', () async {
      adapter
        ..signOutFailure = const NetworkFailure()
        ..signOutLeavesSession = true;

      await expectLater(service.completePasswordRecovery('a-new-password'),
          throwsA(isA<NetworkFailure>()));

      expect(adapter.isSignedIn, isTrue);
      expect(recovery.isInProgress, isTrue);
    });
  });

  group('AuthService: completing a player profile', () {
    late ScriptedAuthAdapter adapter;
    late AuthService service;

    setUp(() {
      adapter = ScriptedAuthAdapter(signedIn: true);
      service = AuthService(adapter);
    });

    Future<void> complete({
      String fullName = '  Sara Al Harthy ',
      String localPhone = '9123 4567',
      DateTime? dateOfBirth,
      PlayerPosition position = PlayerPosition.def,
      PlayerPosition? secondary,
    }) =>
        service.completePlayerProfile(
          fullName: fullName,
          localPhone: localPhone,
          dateOfBirth: dateOfBirth ?? DateTime(2000, 1, 31, 9),
          position: position,
          secondaryPosition: secondary,
        );

    test('sends the stored forms: trimmed name, +968 phone, a plain date',
        () async {
      await complete(secondary: PlayerPosition.fwd);

      final call = adapter.completions.single;
      expect(call.fullName, 'Sara Al Harthy');
      expect(call.phone, '+96891234567');
      expect(call.dateOfBirth, DateTime(2000, 1, 31));
      expect(call.position, PlayerPosition.def);
      expect(call.secondaryPosition, PlayerPosition.fwd);
    });

    test('a secondary position is optional', () async {
      await complete();

      expect(adapter.completions.single.secondaryPosition, isNull);
    });

    test('each rule refuses before anything reaches the port', () async {
      final refusals = <String, Future<void> Function()>{
        'a blank name': () => complete(fullName: '   '),
        'a one-character name': () => complete(fullName: 'A'),
        'a short phone': () => complete(localPhone: '9123456'),
        'a long phone': () => complete(localPhone: '912345678'),
        'no digits': () => complete(localPhone: 'abcdefgh'),
        'a birthday that has not happened': () => complete(
            dateOfBirth: DateTime.now().add(const Duration(days: 2))),
        'a secondary that repeats the primary': () => complete(
            position: PlayerPosition.gk, secondary: PlayerPosition.gk),
      };

      for (final entry in refusals.entries) {
        await expectLater(entry.value(), throwsA(isA<ValidationFailure>()),
            reason: entry.key);
      }
      expect(adapter.completions, isEmpty);
    });

    test('the account state comes from the port, untouched', () async {
      for (final state in AccountState.values) {
        adapter.accountState = state;
        expect(await service.fetchAccountState(), state);
      }
    });

    test('the name the provider supplied is offered, not imposed', () {
      adapter.suggestedName = 'Goo Gle';

      expect(service.suggestedFullName, 'Goo Gle');
    });
  });

  group('failures', () {
    Failure map(Object error) => SupabaseFailureMapper.from(error);

    test('the provider limiting emails is a wait, not a wrong answer', () {
      final byStatus = map(const AuthException(
          'Email rate limit exceeded',
          statusCode: '429'));
      final byCode = map(const AuthException('slow down',
          code: 'over_email_send_rate_limit'));
      final byRequestCode =
          map(const AuthException('slow down', code: 'over_request_rate_limit'));

      for (final failure in [byStatus, byCode, byRequestCode]) {
        expect(failure, isA<InfrastructureFailure>());
        expect(failure.reason, FailureReason.tooManyRequests);
      }
    });

    test('what it used to mean is unchanged', () {
      expect(map(const AuthException('Invalid login credentials',
              statusCode: '400')),
          isA<AuthenticationFailure>());
      final taken = map(const AuthException('User already registered',
          statusCode: '422'));
      expect(taken, isA<ConflictFailure>());
      expect(taken.reason, FailureReason.emailAlreadyUsed);
    });

    test('a second profile is a state the operation ran into', () {
      final failure = map(const PostgrestException(
          message: 'PROFILE_ALREADY_EXISTS', code: 'P0001'));

      expect(failure, isA<ConflictFailure>());
      expect(failure.reason, FailureReason.profileAlreadyExists);
    });

    test('the database refusing an input is a validation failure', () {
      for (final token in [
        'INVALID_FULL_NAME',
        'INVALID_PHONE',
        'INVALID_DATE_OF_BIRTH',
        'INVALID_POSITION',
      ]) {
        expect(map(PostgrestException(message: token, code: 'P0001')),
            isA<ValidationFailure>(),
            reason: token);
      }
    });

    test('no session at the database is an authentication failure', () {
      expect(
        map(const PostgrestException(
            message: 'NOT_AUTHENTICATED', code: 'P0001')),
        isA<AuthenticationFailure>(),
      );
    });
  });

  group('SupabaseAuthAdapter', () {
    late List<http.Request> requests;
    late Map<String, Future<http.Response> Function(http.Request)> routes;
    late SupabaseClient client;
    late SupabaseAuthAdapter adapter;

    http.Response json(Object? body, [int status = 200]) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );

    String jwt() {
      String part(Map<String, Object?> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${part({'sub': 'u1', 'role': 'authenticated', 'exp': 4102444800})}.sig';
    }

    Map<String, Object?> session({Map<String, Object?> metadata = const {}}) =>
        {
          'access_token': jwt(),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh',
          'user': {
            'id': 'u1',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'p@example.com',
            'app_metadata': <String, Object?>{},
            'user_metadata': metadata,
            'created_at': '2026-01-01T00:00:00Z',
          },
        };

    Map<String, Object?> body(http.Request r) =>
        jsonDecode(r.body) as Map<String, Object?>;

    setUp(() {
      requests = [];
      routes = {};
      client = SupabaseClient(
        'http://localhost:54321',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final handler = routes[request.url.path];
          if (handler == null) {
            return json({'message': 'no route ${request.url.path}'}, 500);
          }
          final response = await handler(request);
          // The SDK reads `response.request`, which a real transport always
          // sets and a hand-built response does not.
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      );
      adapter = SupabaseAuthAdapter(client);
    });

    tearDown(() async => client.dispose());

    /// Signs the client in through its own sign-in endpoint, so the adapter is
    /// asked its questions from a real session.
    Future<void> signIn({Map<String, Object?> metadata = const {}}) async {
      routes['/auth/v1/token'] = (_) async => json(session(metadata: metadata));
      await adapter.signIn(email: 'p@example.com', password: 'password1');
    }

    group('sign-up', () {
      Future<SignUpOutcome> signUp({PlayerPosition? secondary}) =>
          adapter.signUp(
            email: 'sara@example.com',
            password: 'password1',
            fullName: 'Sara Al Balushi',
            position: PlayerPosition.mid,
            phone: '+96890123456',
            dateOfBirth: DateTime(1995, 6, 15),
            secondaryPosition: secondary,
            redirectTo: 'goplay://login-callback',
          );

      test('a response with a session is a signed-in account', () async {
        routes['/auth/v1/signup'] = (_) async => json(session());

        expect(await signUp(), SignUpOutcome.signedIn);
        expect(adapter.isSignedIn, isTrue);
      });

      test('a response without one is an account waiting for confirmation',
          () async {
        routes['/auth/v1/signup'] = (_) async => json({
              'id': 'u1',
              'aud': 'authenticated',
              'email': 'sara@example.com',
              'app_metadata': <String, Object?>{},
              'user_metadata': <String, Object?>{},
              'created_at': '2026-01-01T00:00:00Z',
            });

        expect(await signUp(), SignUpOutcome.confirmationRequired);
        expect(adapter.isSignedIn, isFalse,
            reason: 'no session, so nothing above may behave as signed in');
      });

      test('the redirect goes to the provider as the redirect_to it honours',
          () async {
        routes['/auth/v1/signup'] = (_) async => json(session());

        await signUp();

        expect(requests.single.url.queryParameters['redirect_to'],
            'goplay://login-callback');
      });

      test('the profile travels as metadata, and never a rating', () async {
        routes['/auth/v1/signup'] = (_) async => json(session());

        await signUp(secondary: PlayerPosition.def);

        final data = body(requests.single)['data']! as Map<String, Object?>;
        expect(data, {
          'full_name': 'Sara Al Balushi',
          'primary_position': 'MID',
          'phone': '+96890123456',
          'date_of_birth': '1995-06-15',
          'secondary_position': 'DEF',
        });
        expect(data.keys, isNot(contains('overall_rating')));
      });

      test('no secondary position is a missing key, not a null', () async {
        routes['/auth/v1/signup'] = (_) async => json(session());

        await signUp();

        final data = body(requests.single)['data']! as Map<String, Object?>;
        expect(data.containsKey('secondary_position'), isFalse);
      });

      test('an address that is already registered is still a conflict',
          () async {
        routes['/auth/v1/signup'] = (_) async => json({
              'code': 422,
              'error_code': 'user_already_exists',
              'msg': 'User already registered',
            }, 422);

        await expectLater(signUp(), throwsA(isA<ConflictFailure>()));
      });
    });

    group('resending the confirmation', () {
      test('asks for a signup email to the address, with the callback',
          () async {
        routes['/auth/v1/resend'] = (_) async => json(<String, Object?>{});

        await adapter.resendSignupConfirmation(
          email: 'sara@example.com',
          redirectTo: 'goplay://login-callback',
        );

        final request = requests.single;
        expect(body(request)['type'], 'signup');
        expect(body(request)['email'], 'sara@example.com');
        expect(request.url.queryParameters['redirect_to'],
            'goplay://login-callback');
      });

      test('the provider limiting it is the wait, not a generic failure',
          () async {
        routes['/auth/v1/resend'] = (_) async => json({
              'code': 429,
              'error_code': 'over_email_send_rate_limit',
              'msg': 'For security purposes, you can only request this after 60 seconds.',
            }, 429);

        await expectLater(
          adapter.resendSignupConfirmation(
            email: 'sara@example.com',
            redirectTo: 'goplay://login-callback',
          ),
          throwsA(isA<InfrastructureFailure>()
              .having((f) => f.reason, 'reason', FailureReason.tooManyRequests)),
        );
      });
    });

    group('password recovery', () {
      test('asks the provider to email a link, with the callback', () async {
        routes['/auth/v1/recover'] = (_) async => json(<String, Object?>{});

        await adapter.requestPasswordReset(
          'sara@example.com',
          redirectTo: 'goplay://login-callback',
        );

        final request = requests.single;
        expect(body(request)['email'], 'sara@example.com');
        expect(request.url.queryParameters['redirect_to'],
            'goplay://login-callback');
      });

      test('the provider answering the same for anybody is not altered',
          () async {
        routes['/auth/v1/recover'] = (_) async => json(<String, Object?>{});

        // Two addresses, one answer: nothing here can tell them apart.
        await adapter.requestPasswordReset('a@example.com',
            redirectTo: 'goplay://login-callback');
        await adapter.requestPasswordReset('b@example.com',
            redirectTo: 'goplay://login-callback');

        expect(requests, hasLength(2));
      });

      test('the recovery event arrives as an application event, and outranks '
          'a plain sign-in', () async {
        final seen = <AuthEvent>[];
        final subscription = adapter.authEvents.listen(seen.add);
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        seen.clear();

        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.signedIn);
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.passwordRecovery);
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.tokenRefreshed);
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.signedOut);
        await pumpEventQueue();

        expect(seen, [
          AuthEvent.signedIn,
          AuthEvent.passwordRecovery,
          AuthEvent.sessionUpdated,
          AuthEvent.signedOut,
        ]);
      });

      test('provider errors on the stream never reach a listener', () async {
        final errors = <Object>[];
        final seen = <AuthEvent>[];
        final subscription =
            adapter.authEvents.listen(seen.add, onError: errors.add);
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        seen.clear();

        // ignore: invalid_use_of_internal_member
        client.auth.notifyException(Exception('refresh failed'));
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.signedIn);
        await pumpEventQueue();

        expect(errors, isEmpty);
        expect(seen, [AuthEvent.signedIn], reason: 'and the stream carries on');
      });

      test('a session made by a recovery link is still "signed in" to the '
          'boolean stream, which is exactly why the event matters', () async {
        routes['/auth/v1/token'] = (_) async => json(session());
        final signedIn = <bool>[];
        final subscription = adapter.signedInChanges.listen(signedIn.add);
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        signedIn.clear();

        await adapter.signIn(email: 'p@example.com', password: 'password1');
        // ignore: invalid_use_of_internal_member
        client.auth.notifyAllSubscribers(AuthChangeEvent.passwordRecovery);
        await pumpEventQueue();

        expect(signedIn, everyElement(isTrue));
        expect(signedIn, isNotEmpty);
      });
    });

    group('Google', () {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      late List<String> launched;

      setUp(() {
        launched = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments;
          if (arguments is Map && arguments['url'] is String) {
            launched.add(arguments['url'] as String);
          }
          return true;
        });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      test('hands the browser the provider\'s Google authorize address, '
          'with the callback', () async {
        await adapter.signInWithGoogle(redirectTo: 'goplay://login-callback');

        final uri = Uri.parse(launched.single);
        expect(uri.path, '/auth/v1/authorize');
        expect(uri.queryParameters['provider'], 'google');
        expect(uri.queryParameters['redirect_to'], 'goplay://login-callback');
      });

      test('names no Google SDK: it is the provider\'s own redirect flow, so '
          'no request of its own is made', () async {
        await adapter.signInWithGoogle(redirectTo: 'goplay://login-callback');

        expect(requests, isEmpty);
      });
    });

    group('the account state', () {
      Future<void> answers(Object? value) async {
        routes['/rest/v1/rpc/get_my_account_state'] =
            (_) async => json(value);
      }

      test('reads the three answers', () async {
        await signIn();

        await answers('ACTIVE');
        expect(await adapter.fetchAccountState(), AccountState.active);
        await answers('SUSPENDED');
        expect(await adapter.fetchAccountState(), AccountState.suspended);
        await answers('PROFILE_REQUIRED');
        expect(await adapter.fetchAccountState(), AccountState.profileRequired);
      });

      test('an answer it does not recognise is a failure, never "active"',
          () async {
        await signIn();

        for (final unknown in ['active', 'OK', '', null, true, 1]) {
          await answers(unknown);
          await expectLater(adapter.fetchAccountState(),
              throwsA(isA<Failure>()),
              reason: '$unknown');
        }
      });

      test('the database refusing to answer is a failure the gate fails '
          'closed on', () async {
        await signIn();
        routes['/rest/v1/rpc/get_my_account_state'] = (_) async => json(
            {'code': 'P0001', 'message': 'NOT_AUTHENTICATED'}, 400);

        await expectLater(
            adapter.fetchAccountState(), throwsA(isA<AuthenticationFailure>()));
      });

      test('with no session there is nobody to ask about, and nothing is sent',
          () async {
        await expectLater(
            adapter.fetchAccountState(), throwsA(isA<AuthenticationFailure>()));

        expect(requests, isEmpty);
      });
    });

    group('completing the profile', () {
      test('calls the one RPC with the profile and nothing else', () async {
        await signIn();
        routes['/rest/v1/rpc/complete_my_player_profile'] =
            (_) async => http.Response('', 204);

        await adapter.completePlayerProfile(
          fullName: 'Sara Al Harthy',
          phone: '+96891234567',
          dateOfBirth: DateTime(2000, 1, 31),
          position: PlayerPosition.def,
          secondaryPosition: PlayerPosition.fwd,
        );

        final rpc = requests.last;
        expect(rpc.url.path, '/rest/v1/rpc/complete_my_player_profile');
        expect(body(rpc), {
          'p_full_name': 'Sara Al Harthy',
          'p_phone': '+96891234567',
          'p_date_of_birth': '2000-01-31',
          'p_primary_position': 'DEF',
          'p_secondary_position': 'FWD',
        });
      });

      test('nothing that names a user, a rating, a role or a state is ever '
          'sent', () async {
        await signIn();
        routes['/rest/v1/rpc/complete_my_player_profile'] =
            (_) async => http.Response('', 204);

        await adapter.completePlayerProfile(
          fullName: 'Sara',
          phone: '+96891234567',
          dateOfBirth: DateTime(2000, 1, 31),
          position: PlayerPosition.mid,
          secondaryPosition: null,
        );

        final keys = body(requests.last).keys;
        expect(keys, isNot(contains('p_secondary_position')),
            reason: 'left out, so the function\'s own default says "none"');
        for (final key in keys) {
          expect(key, matches(RegExp(r'^p_(full_name|phone|date_of_birth|'
              r'primary_position)$')));
        }
      });

      test('a profile that already exists is a conflict', () async {
        await signIn();
        routes['/rest/v1/rpc/complete_my_player_profile'] = (_) async =>
            json({'code': 'P0001', 'message': 'PROFILE_ALREADY_EXISTS'}, 400);

        await expectLater(
          adapter.completePlayerProfile(
            fullName: 'Sara',
            phone: '+96891234567',
            dateOfBirth: DateTime(2000, 1, 31),
            position: PlayerPosition.mid,
            secondaryPosition: null,
          ),
          throwsA(isA<ConflictFailure>()
              .having((f) => f.reason, 'reason',
                  FailureReason.profileAlreadyExists)),
        );
      });
    });

    group('the name the provider supplied', () {
      test('is full_name when there is one', () async {
        await signIn(metadata: {'full_name': ' Goo Gle ', 'name': 'Other'});

        expect(adapter.suggestedFullName, 'Goo Gle');
      });

      test('falls back to name', () async {
        await signIn(metadata: {'name': 'Goo Gle'});

        expect(adapter.suggestedFullName, 'Goo Gle');
      });

      test('is nothing when it is blank or absent', () async {
        await signIn(metadata: {'full_name': '   '});
        expect(adapter.suggestedFullName, isNull);
      });

      test('is nothing without a session', () {
        expect(adapter.suggestedFullName, isNull);
      });
    });
  });
}
