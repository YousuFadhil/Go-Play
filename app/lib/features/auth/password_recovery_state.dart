import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recovery_link.dart';

/// Whether a password recovery is in progress on this device, kept across
/// restarts.
///
/// A recovery link produces a session that exists to choose a new password and
/// nothing else. The provider stores that session like any other, so once the
/// app has been closed it comes back as an ordinary signed-in session with
/// nothing to say how it began. **The application must never let an unfinished
/// recovery become an ordinary product session**, and the only way to keep that
/// promise across a restart is to remember it ourselves.
///
/// This is that memory: one flag, in local storage, provider-independent.
///
///   * It is **set** by the launch or resume that came from the recovery
///     callback ([captureLink]), and by the provider's recovery event as a
///     backup ([begin]) — neither alone is reliable. The event can be emitted
///     before the application is listening; the link can be one the platform
///     hands over in a shape nobody anticipated.
///   * It is **cleared** by finishing or cancelling the recovery, by the gate
///     finding it with no session behind it, and by an ordinary sign-in taking
///     over from a link that never produced a session.
///   * It is **read** by the auth gate before anything else about a signed-in
///     account, so a session it marks never reaches Home, an invitation,
///     profile onboarding or the suspension screen.
///
/// The value is in memory as soon as it is set and written to storage after;
/// callers that need it on disk before continuing await the returned future.
/// When storage cannot be read or written the flag still works for this run,
/// which is the most that can be said for it.
class PasswordRecoveryState {
  PasswordRecoveryState({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  /// The one the application uses. Tests construct their own.
  static final PasswordRecoveryState instance = PasswordRecoveryState();

  /// Where the flag lives in local storage.
  static const String storageKey = 'auth.password_recovery_in_progress';

  final Future<SharedPreferences> Function() _preferences;
  final ValueNotifier<bool> _inProgress = ValueNotifier<bool>(false);

  /// Whether a recovery is in progress. Listenable so the gate reacts when a
  /// link or the provider's event starts one while it is on screen.
  ValueListenable<bool> get inProgress => _inProgress;

  bool get isInProgress => _inProgress.value;

  /// Reads the flag from storage. Called once at start-up, before anything that
  /// consults it, so a recovery interrupted by a restart is known before the
  /// first frame.
  Future<void> load() async {
    try {
      final prefs = await _preferences();
      _inProgress.value = prefs.getBool(storageKey) ?? false;
    } catch (_) {
      // Storage unavailable: nothing durable to read. The flag still works for
      // this run.
    }
  }

  /// Records that a recovery is in progress.
  Future<void> begin() async {
    _inProgress.value = true;
    await _persist(true);
  }

  /// Records that it is over, or that there was never one to have.
  Future<void> clear() async {
    _inProgress.value = false;
    await _persist(false);
  }

  /// What the application does at launch, **before the provider starts**: read
  /// the persisted record, then record the recovery if [launchLocation] -- the
  /// address the app was opened on -- is the recovery callback. Says whether it
  /// was.
  ///
  /// The order is the point, and it is why this is one call. On the web the SDK
  /// exchanges the link's credentials and strips them from the address while it
  /// initialises; by the time anything else runs the link is gone. What is
  /// recorded here is what the auth gate reads first.
  Future<bool> startUp({String? launchLocation}) async {
    await load();
    return captureLink(launchLocation);
  }

  /// Starts a recovery if [location] is the recovery callback, and says whether
  /// it was.
  ///
  /// [location] is whatever the launch or the running app was handed: a page
  /// address on the web, a route on a phone. See [RecoveryLink] for what counts.
  /// Anything else — the ordinary callback that Google and sign-up confirmation
  /// return to, an invitation, a public link, nothing — changes nothing.
  Future<bool> captureLink(String? location) async {
    if (!RecoveryLink.isRecoveryCallback(location)) return false;
    await begin();
    return true;
  }

  Future<void> _persist(bool value) async {
    try {
      final prefs = await _preferences();
      if (value) {
        await prefs.setBool(storageKey, true);
      } else {
        await prefs.remove(storageKey);
      }
    } catch (_) {
      // See the class comment: the in-memory value stands.
    }
  }
}
