/// Supabase configuration.
///
/// Values are injected at build time:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where a shared link points.
  ///
  /// **The deployed site, not a domain the product does not own.** The public
  /// web app is the Cloudflare Pages project `go-play`, whose production
  /// deployment is published on every push to `main`
  /// (`.github/workflows/deploy-web.yml`) and served at the address below. A
  /// shared card carries a link a stranger can actually open, which is the
  /// whole point of carrying one, so the default is the address that resolves
  /// rather than a nicer one that does not.
  ///
  /// Overridable by `--dart-define=PUBLIC_WEB_BASE=...` through the same
  /// mechanism the Supabase values already use — so the day a real domain is
  /// registered, the deployment workflow supplies it and nothing in the
  /// application changes. No trailing slash: [publicWebBase] is joined to a
  /// path that starts with one.
  static const String publicWebBase = String.fromEnvironment(
    'PUBLIC_WEB_BASE',
    defaultValue: 'https://go-play-44y.pages.dev',
  );

  /// Fail-fast validation: both values present and the URL has a real host.
  static bool get isValid {
    if (supabaseAnonKey.isEmpty) return false;
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Safe representation of the key for debug logging.
  static String get maskedAnonKey {
    if (supabaseAnonKey.isEmpty) return '<EMPTY>';
    final prefix = supabaseAnonKey.length <= 12
        ? supabaseAnonKey
        : supabaseAnonKey.substring(0, 12);
    return '$prefix... (${supabaseAnonKey.length} chars)';
  }
}
