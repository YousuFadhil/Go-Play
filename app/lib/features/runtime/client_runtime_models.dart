import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, kIsWeb;

/// Which kind of uncaught failure an error report is (Wave 4, OI-06).
///
/// Two, and only uncaught ones. A `Failure` a screen or service handles — a
/// refusal, a validation error, an ordinary network failure — is not a client
/// error and never reaches this.
enum ClientErrorCategory {
  /// Caught by `FlutterError.onError`: a failure inside the framework.
  flutterFramework('flutter_framework'),

  /// Caught by `PlatformDispatcher.onError`: any other uncaught error.
  platformUnhandled('platform_unhandled');

  const ClientErrorCategory(this.wireName);

  /// The value `report_client_error_v1` accepts.
  final String wireName;
}

/// The build a production run is started under: nothing about the person.
@immutable
class ClientRuntimeIdentity {
  const ClientRuntimeIdentity({
    required this.platform,
    required this.appVersion,
    required this.buildSha,
  });

  /// `web`, `android` or `ios`.
  final String platform;

  /// From `pubspec.yaml`, injected by the deployment workflow.
  final String appVersion;

  /// The exact commit built, 40 lowercase hex digits.
  final String buildSha;

  static final _version = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$');
  static final _sha = RegExp(r'^[0-9a-f]{40}$');

  /// The identity to report under, or null when reporting must stay off.
  ///
  /// Only a **production** deployment reports. Staging, debug, local and
  /// unconfigured builds all resolve to null, and so does a production build
  /// whose version, commit or platform the server would not accept — reporting
  /// is left off rather than sent malformed.
  static ClientRuntimeIdentity? resolve({
    required String environment,
    required String appVersion,
    required String buildSha,
    required String? platform,
  }) {
    if (environment != 'production') return null;
    if (platform == null) return null;
    if (!_version.hasMatch(appVersion) || !_sha.hasMatch(buildSha)) {
      return null;
    }
    return ClientRuntimeIdentity(
      platform: platform,
      appVersion: appVersion,
      buildSha: buildSha,
    );
  }

  /// The platform this code is running on, in the three words the server
  /// accepts, or null for any other.
  static String? currentPlatform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ClientRuntimeIdentity &&
      other.platform == platform &&
      other.appVersion == appVersion &&
      other.buildSha == buildSha;

  @override
  int get hashCode => Object.hash(platform, appVersion, buildSha);
}
