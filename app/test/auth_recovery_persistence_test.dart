import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/auth/password_recovery_state.dart';
import 'package:go_play/features/auth/recovery_link.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/notifications/notification_route.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pieces a password recovery is remembered with: how a link is recognised,
/// the durable state itself, and the platform assumption the recovery redirect
/// rests on.
///
/// What the auth gate does with them is in `auth_modernization_gate_test.dart`.
void main() {
  group('RecoveryLink', () {
    bool recognised(String? link) => RecoveryLink.isRecoveryCallback(link);

    test('recognises the native recovery callback', () {
      expect(recognised('goplay://login-callback/recovery?code=abc123'), isTrue);
    });

    test('recognises the web recovery callback, on any origin', () {
      for (final origin in [
        'https://go-play-44y.pages.dev',
        'https://go-play-staging.pages.dev',
        'http://localhost:8080',
      ]) {
        expect(recognised('$origin/login-callback/recovery?code=abc123'), isTrue,
            reason: origin);
      }
    });

    test('recognises the shapes a running app or a cold start may be handed',
        () {
      // Android's engine may deliver a custom-scheme link whole or as its path.
      expect(recognised('/login-callback/recovery?code=abc123'), isTrue);
      expect(recognised('/recovery?code=abc123'), isTrue);
      expect(recognised('recovery?code=abc123'), isTrue);
    });

    test('accepts each kind of credential the provider can return', () {
      expect(recognised('goplay://login-callback/recovery?code=abc'), isTrue);
      expect(recognised('goplay://login-callback/recovery?token_hash=abc&type=recovery'),
          isTrue);
      expect(
          recognised(
              'https://x.example/login-callback/recovery#access_token=a&refresh_token=b&type=recovery'),
          isTrue,
          reason: 'the implicit flow puts them in the fragment');
    });

    test('ignores case and surrounding whitespace', () {
      expect(recognised('  GOPLAY://Login-Callback/Recovery?code=abc  '), isTrue);
    });

    test('does not recognise the ordinary callback that Google and sign-up '
        'confirmation return to', () {
      for (final link in [
        'goplay://login-callback?code=abc123',
        'goplay://login-callback/?code=abc123',
        'https://go-play-44y.pages.dev/login-callback?code=abc123',
        'https://go-play-44y.pages.dev/login-callback#access_token=a&type=signup',
        '/login-callback?code=abc123',
        'goplay://login-callback#access_token=a&refresh_token=b',
      ]) {
        expect(recognised(link), isFalse, reason: link);
      }
    });

    test('does not recognise a recovery callback that carries nothing to '
        'exchange', () {
      // What a browser shows once the SDK has consumed the parameters, what
      // anybody can type, and what an expired link comes back as.
      for (final link in [
        'goplay://login-callback/recovery',
        'https://go-play-44y.pages.dev/login-callback/recovery',
        'https://go-play-44y.pages.dev/login-callback/recovery?utm=1',
        'goplay://login-callback/recovery?error=access_denied&error_code=otp_expired',
        'https://x.example/login-callback/recovery#error=access_denied',
      ]) {
        expect(recognised(link), isFalse, reason: link);
      }
    });

    test('does not recognise anything else the app is handed', () {
      for (final link in [
        null,
        '',
        '   ',
        '/',
        'goplay://join/1234',
        'https://goplay.app/join/1234',
        '/player/3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d',
        '/community/abc?code=1',
        '/match/abc',
        '/notifications',
        'goplay://login-callback/recovery/extra?code=abc',
        'goplay://login-callback/not-recovery?code=abc',
        'goplay://other-host/recovery?code=abc',
        'https://x.example/recovery-notes?code=abc',
        '::not a uri::',
      ]) {
        expect(recognised(link), isFalse, reason: '$link');
      }
    });
  });

  group('the other links the app is handed are unaffected', () {
    // A recovery link reaches the same route handling as invitations, public
    // links and notification taps. None of them may take it, and it may take
    // none of theirs.
    const recoveryLinks = [
      'goplay://login-callback/recovery?code=1234',
      '/login-callback/recovery?code=1234',
      '/recovery?code=1234',
      'https://go-play-44y.pages.dev/login-callback/recovery?code=1234',
    ];

    test('an invitation, a public link and a notification ignore a recovery '
        'link', () {
      for (final link in recoveryLinks) {
        expect(InviteLink.parse(link), isNull, reason: link);
        expect(PublicLink.parse(link), isNull, reason: link);
        expect(NotificationLink.parse(link), isNull, reason: link);
      }
    });

    test('a recovery link ignores every one of theirs', () {
      for (final link in [
        'goplay://join/1234',
        'https://goplay.app/join/1234',
        '/player/3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d',
        '/community/3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d',
        '/match/3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d',
        NotificationLink.consumedRoute,
      ]) {
        expect(RecoveryLink.isRecoveryCallback(link), isFalse, reason: link);
      }
    });
  });

  group('PasswordRecoveryState', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<bool> stored() async => (await SharedPreferences.getInstance())
            .getBool(PasswordRecoveryState.storageKey) ??
        false;

    Future<PasswordRecoveryState> freshlyLoaded() async {
      final state = PasswordRecoveryState();
      await state.load();
      return state;
    }

    test('starts with nothing in progress', () async {
      final state = await freshlyLoaded();

      expect(state.isInProgress, isFalse);
      expect(state.inProgress.value, isFalse);
    });

    test('begin sets it at once, and in storage', () async {
      final state = await freshlyLoaded();

      final done = state.begin();
      expect(state.isInProgress, isTrue,
          reason: 'in memory before the write lands, so the gate is never '
              'behind it');
      await done;

      expect(await stored(), isTrue);
    });

    test('clear unsets it, and removes it from storage', () async {
      final state = await freshlyLoaded();
      await state.begin();

      await state.clear();

      expect(state.isInProgress, isFalse);
      expect(await stored(), isFalse);
      expect((await SharedPreferences.getInstance())
          .containsKey(PasswordRecoveryState.storageKey), isFalse,
          reason: 'removed, not left as false');
    });

    test('survives the process: a new instance reads it back', () async {
      final first = await freshlyLoaded();
      await first.begin();

      final restarted = await freshlyLoaded();

      expect(restarted.isInProgress, isTrue);
    });

    test('a finished recovery does not come back', () async {
      final first = await freshlyLoaded();
      await first.begin();
      await first.clear();

      final restarted = await freshlyLoaded();

      expect(restarted.isInProgress, isFalse);
    });

    test('tells its listeners when it changes', () async {
      final state = await freshlyLoaded();
      final seen = <bool>[];
      state.inProgress.addListener(() => seen.add(state.isInProgress));

      await state.begin();
      await state.clear();

      expect(seen, [true, false]);
    });

    test('captureLink records the recovery callback and says so', () async {
      final state = await freshlyLoaded();

      final recorded = await state
          .captureLink('goplay://login-callback/recovery?code=abc123');

      expect(recorded, isTrue);
      expect(state.isInProgress, isTrue);
      expect(await stored(), isTrue);
    });

    test('captureLink records nothing for anything else', () async {
      final state = await freshlyLoaded();

      for (final link in [
        null,
        'goplay://login-callback?code=abc123',
        'https://go-play-44y.pages.dev/login-callback?code=abc123',
        'https://go-play-44y.pages.dev/login-callback/recovery',
        'goplay://join/1234',
      ]) {
        expect(await state.captureLink(link), isFalse, reason: '$link');
      }
      expect(state.isInProgress, isFalse);
      expect(await stored(), isFalse);
    });

    test('an unreadable store falls back to "not in progress" and still works '
        'for this run', () async {
      final state = PasswordRecoveryState(
          preferences: () => Future<SharedPreferences>.error(StateError('no')));

      await state.load();
      expect(state.isInProgress, isFalse);

      await state.begin();
      expect(state.isInProgress, isTrue,
          reason: 'memory only, which is the most that can be said for it');
      await state.clear();
      expect(state.isInProgress, isFalse);
    });
  });

  group('the Android manifest', () {
    // The recovery redirect adds a path segment to the ordinary callback. That
    // works with no manifest change only if the intent filter names the host and
    // restricts no path -- checked here, because it cannot be run from Dart.
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    String callbackFilter() {
      final filters = RegExp(r'<intent-filter[^>]*>.*?</intent-filter>',
              dotAll: true)
          .allMatches(manifest)
          .map((m) => m.group(0)!)
          .where((f) => f.contains('android:host="login-callback"'));
      expect(filters, hasLength(1), reason: 'exactly one login-callback filter');
      return filters.single;
    }

    test('accepts goplay://login-callback with any path, /recovery included',
        () {
      final filter = callbackFilter();

      expect(filter, contains('android:scheme="goplay"'));
      for (final restriction in [
        'android:path=',
        'android:pathPrefix=',
        'android:pathPattern=',
        'android:pathAdvancedPattern=',
        'android:pathSuffix=',
      ]) {
        expect(filter, isNot(contains(restriction)),
            reason: '$restriction would refuse /recovery');
      }
    });

    test('is a browsable, default VIEW filter, as a link needs', () {
      final filter = callbackFilter();

      expect(filter, contains('android.intent.action.VIEW'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
      expect(filter, contains('android.intent.category.DEFAULT'));
    });

    test('has Flutter deep linking on, which is how the route reaches the app',
        () {
      expect(manifest, contains('flutter_deeplinking_enabled'));
      expect(
          RegExp(r'flutter_deeplinking_enabled"\s+android:value="true"')
              .hasMatch(manifest),
          isTrue);
    });
  });
}
