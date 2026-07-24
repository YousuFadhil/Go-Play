import 'package:supabase_flutter/supabase_flutter.dart';

/// Global application settings. Reserve capacity lives here rather than on the
/// match: maximum registration is always starting players + reserve players.
class AppSettings {
  AppSettings._();

  /// Used until the stored value has been loaded, and if it cannot be read.
  static const int fallbackReservePlayers = 6;

  static int _reservePlayers = fallbackReservePlayers;

  /// Reserve slots added on top of the starting players.
  static int get reservePlayers => _reservePlayers;

  /// Maximum registration for a match with [startingPlayers] starting slots.
  static int maxRegistrationFor(int startingPlayers) =>
      startingPlayers + _reservePlayers;

  /// Loads the value from the database; safe to call more than once.
  static Future<void> load([SupabaseClient? client]) async {
    try {
      final db = client ?? Supabase.instance.client;
      final row = await db
          .from('app_settings')
          .select('reserve_players')
          .limit(1)
          .maybeSingle();
      final value = row?['reserve_players'] as int?;
      if (value != null && value >= 0) _reservePlayers = value;
    } catch (_) {
      // Keep the fallback; capacity is enforced server-side anyway.
    }
  }
}
