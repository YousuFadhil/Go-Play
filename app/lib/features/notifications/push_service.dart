import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import 'notification_service.dart';

/// Firebase on the device: permission, the token, and telling the backend which
/// devices a player can be reached on.
///
/// **Push is a delivery mechanism and nothing else.** Nothing here decides what
/// is worth notifying about, nothing here writes a notice, and nothing here can
/// prevent one being written — that is all the database's, and the Notification
/// Center stays the source of truth whether or not any of this works.
///
/// Which is the reason for how defensively it is written. Firebase may be
/// unconfigured (no `google-services.json`), the player may refuse permission,
/// the token request may fail on a device without Play Services, and none of
/// those may cost the app anything: the notice is still in the app, and a
/// player who never receives a push is a player who reads their notifications
/// when they open it. **Every failure below is swallowed on purpose.**
///
/// Registration follows the session rather than the app. A token is worth
/// storing only against an account, and a device that signs out must stop
/// receiving the notices of whoever was signed in.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  // Lazy, and it matters: both reach the Supabase client through their default
  // adapters, and this singleton is touched from `logOut` — which a widget test
  // can run with no provider initialised at all.
  late final NotificationService _notifications = NotificationService();
  late final AuthService _auth = AuthService();

  StreamSubscription<bool>? _session;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;

  bool _firebaseReady = false;
  String? _registeredToken;

  /// Ticks whenever a push arrives while the app is in the foreground.
  ///
  /// The app has no realtime subscription on `notifications`, so this is the
  /// one signal it gets that the unread count has moved while a screen is
  /// already open. Screens listen and re-read; **nothing renders the push
  /// itself**, because the Notification Center already holds the notice and
  /// showing it twice would make push look like the record.
  final ValueNotifier<int> foregroundPushes = ValueNotifier<int>(0);

  /// Starts following the session. Safe to call more than once.
  Future<void> start() async {
    if (!_supported) return;
    _session ??= _auth.signedInChanges.listen((signedIn) {
      if (signedIn) {
        unawaited(_attach());
      } else {
        _detachLocal();
      }
    });
  }

  /// Deregisters this device, to be called **before** signing out.
  ///
  /// Order matters: the delete is the player's own row under their own session,
  /// so after `signOut` there is no session left to authorise it. Best-effort
  /// even so — a token that survives here is taken over by the next account to
  /// register it, which is what `register_push_token` exists to do.
  Future<void> signOut() async {
    final token = _registeredToken;
    _detachLocal();
    if (token == null) return;
    try {
      await _notifications.removeDevice(token);
    } catch (_) {
      // See the class comment: never worth failing a sign-out over.
    }
  }

  /// Android and iOS only. Everything else has no Firebase configuration in
  /// this project and would fail at `initializeApp`.
  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<void> _attach() async {
    if (!await _ensureFirebase()) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ and every iOS version ask. A refusal is an answer, not a
      // failure: the player keeps the Notification Center and loses nothing
      // else.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      _foreground ??= FirebaseMessaging.onMessage
          .listen((_) => foregroundPushes.value++);

      final token = await messaging.getToken();
      if (token != null) await _register(token);

      // Firebase rotates tokens on its own schedule — a restore, a reinstall,
      // a long silence. A stale token is a device that stops receiving without
      // anybody noticing, so the refresh is followed rather than polled.
      _tokenRefresh ??= messaging.onTokenRefresh.listen(_register);
    } catch (error) {
      debugPrint('[GoPlay] push unavailable: $error');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _notifications.registerDevice(token: token, platform: _platform);
      _registeredToken = token;
    } catch (error) {
      debugPrint('[GoPlay] push token not registered: $error');
    }
  }

  /// Stops following this device's token. Does not touch the backend — the two
  /// callers differ on whether there is still a session to do that with.
  void _detachLocal() {
    _tokenRefresh?.cancel();
    _tokenRefresh = null;
    _registeredToken = null;
  }

  Future<bool> _ensureFirebase() async {
    if (_firebaseReady) return true;
    try {
      // No `firebase_options.dart`: the platform configuration files
      // (`google-services.json`, `GoogleService-Info.plist`) are what name the
      // project, so there is nothing to generate and nothing to keep in step
      // with them.
      await Firebase.initializeApp();
      _firebaseReady = true;
      return true;
    } catch (error) {
      debugPrint('[GoPlay] Firebase not configured; push disabled: $error');
      return false;
    }
  }
}

// There is deliberately no background message handler. Every push this system
// sends carries a `notification` block, so the operating system draws it
// without the app running, and the notice it reports is already committed to
// the Notification Center. A background isolate would have nothing to do that
// opening the app does not do better.
