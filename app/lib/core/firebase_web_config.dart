import 'package:firebase_core/firebase_core.dart';

/// Firebase Web configuration, injected at build time.
///
/// Android and iOS name their Firebase project through a file the build reads
/// (`google-services.json`, `GoogleService-Info.plist`), and both of those are
/// gitignored. The web build has no equivalent file, so it takes the same values
/// the same way the Supabase configuration is taken — `--dart-define` — and for
/// the same reason: **no Firebase identifier belongs in this repository.**
///
/// ```
/// flutter build web --release \
///   --dart-define=FIREBASE_WEB_API_KEY=... \
///   --dart-define=FIREBASE_WEB_APP_ID=1:...:web:... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... \
///   --dart-define=FIREBASE_WEB_VAPID_KEY=...
/// ```
///
/// None of these is a secret in the cryptographic sense — every one of them
/// ships inside the JavaScript bundle of any Firebase web app, and the VAPID
/// key here is the *public* half of the Web Push key pair. They are kept out of
/// source because they name an environment, not because they protect one. The
/// values that do protect something — the service account and the private VAPID
/// half — never leave the Firebase Console and the Edge Function's secrets.
///
/// Absent values are not an error. `isConfigured` is false, `PushService` skips
/// Firebase entirely, and the app runs exactly as it did before web push
/// existed: notices are still written, and still read in the Notification
/// Center.
class FirebaseWebConfig {
  FirebaseWebConfig._();

  static const String apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');

  /// The **web** app id (`1:<sender>:web:<hash>`). Not the Android one — a
  /// platform gets its own app inside the same Firebase project.
  static const String appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');

  /// Shared with Android: the project number.
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// The public key of the Web Push certificate pair. Web tokens are Web Push
  /// subscriptions underneath, and a subscription is made against this key.
  static const String vapidKey =
      String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  /// Optional, and derived when it is not given: Firebase's own default for a
  /// project is `<project-id>.firebaseapp.com`, so asking for it separately
  /// would be asking for something already known. Overridable because a project
  /// on a custom auth domain has to be able to say so.
  static const String _authDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  static String get authDomain =>
      _authDomain.isNotEmpty ? _authDomain : '$projectId.firebaseapp.com';

  /// Not required by messaging, and not requested. Declared so a build that
  /// passes it is not silently dropping it.
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// Every value messaging cannot work without. The VAPID key is one of them:
  /// omitting it makes the SDK fall back to a key that is not this project's,
  /// which fails later and less legibly than not starting at all.
  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      vapidKey.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}
