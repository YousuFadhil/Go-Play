/// Recognises the password-recovery callback, and nothing else.
///
/// A recovery email carries its own redirect, distinct from the ordinary auth
/// callback that sign-up confirmation and Google use:
///
///   * ordinary:  `goplay://login-callback`            `<origin>/login-callback`
///   * recovery:  `goplay://login-callback/recovery`   `<origin>/login-callback/recovery`
///
/// The distinction exists so the application can tell what a link was *for*
/// without depending on having watched the provider's own event. That event is
/// emitted while the SDK initialises, which can be before anything in the
/// application is listening, and a recovery session that is later restored from
/// storage is indistinguishable from any other session. The address the person
/// arrived on is the one thing that is still there.
///
/// **A link counts only if it carries credentials** — a `code`, an
/// `access_token` or a `token_hash`. A bare `/login-callback/recovery` is what a
/// browser shows after the SDK has consumed the parameters, and what anybody can
/// type; neither is a recovery in progress. An expired link comes back with an
/// `error` and no credentials, and there is nothing to recover from it.
///
/// The three places a link can be read — a web page's address, the route a
/// running app is handed, and the route a cold start is launched with — do not
/// agree on shape. Android's engine may hand a custom-scheme link over as the
/// whole URI or as its path alone, so `/recovery?code=…` is accepted as well as
/// `goplay://login-callback/recovery?code=…`. What none of them may be is the
/// ordinary callback, which has no `recovery` segment.
abstract final class RecoveryLink {
  static const String _callback = 'login-callback';
  static const String _recovery = 'recovery';

  /// Query or fragment keys that mean the link carries something to exchange.
  static const Set<String> _credentialKeys = {
    'code',
    'access_token',
    'token_hash',
  };

  static bool isRecoveryCallback(String? location) {
    if (location == null) return false;
    final uri = Uri.tryParse(location.trim());
    if (uri == null || !_carriesCredentials(uri)) return false;

    final segments = <String>[
      // On a custom scheme the first thing after `://` is the *host*, and it is
      // where `login-callback` lives: goplay://login-callback/recovery.
      if (uri.hasScheme &&
          uri.scheme != 'http' &&
          uri.scheme != 'https' &&
          uri.host.isNotEmpty)
        uri.host.toLowerCase(),
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment.toLowerCase(),
    ];
    if (segments.isNotEmpty && segments.first == _callback) {
      segments.removeAt(0);
    }
    return segments.length == 1 && segments.single == _recovery;
  }

  static bool _carriesCredentials(Uri uri) {
    if (uri.queryParameters.keys.any(_credentialKeys.contains)) return true;
    if (uri.fragment.isEmpty) return false;
    try {
      return Uri.splitQueryString(uri.fragment)
          .keys
          .any(_credentialKeys.contains);
    } on FormatException {
      return false;
    }
  }
}
