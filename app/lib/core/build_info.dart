import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// What build of Go Play is running, and on what.
///
/// **One authoritative answer, in one place.** Both values are reported with
/// every analytics event, and a version string repeated at ten call sites is a
/// version string that is wrong at three of them after the next release. Nothing
/// else in the application asks these questions, so nothing else needs to know
/// the answers.
///
/// No dependency is added for this. `package_info_plus` would read the real
/// bundle version at runtime, which is genuinely better — and it is a new
/// package, a new platform channel and a change to how the app is built, none
/// of which this cycle is permitted to make. A constant that has to be edited
/// beside `pubspec.yaml` is the honest MVP trade, and the test below it is what
/// stops the two drifting apart in silence.
class BuildInfo {
  const BuildInfo._();

  /// The running build.
  ///
  /// **Must match `version:` in `app/pubspec.yaml` exactly.** A static test
  /// asserts that it does, so a release that bumps one and forgets the other
  /// fails the suite rather than mislabelling every event it records.
  static const String appVersion = '0.4.1-public-beta+2';

  /// The platform, in the two words the database accepts, or null.
  ///
  /// Null is a real answer and not a gap: the column is nullable and the
  /// `record_product_event` CHECK admits null precisely so that a platform this
  /// cycle does not report is recorded as unknown rather than as a guess. iOS
  /// is deliberately absent — adding it is a product decision about a platform
  /// Go Play does not ship to yet, not a line of code.
  ///
  /// [kIsWeb] is tested first because it has to be: on the web
  /// [defaultTargetPlatform] reports the *host* — Android for a phone browser —
  /// so asking it first would file every mobile web session under `android`.
  static String? get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.android ? 'android' : null;
  }
}
