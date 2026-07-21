/// Supabase configuration.
///
/// Values are injected at build time:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

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
