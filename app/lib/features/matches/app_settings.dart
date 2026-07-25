import 'match_service.dart';

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

  /// Loads the value through the match repository; safe to call more than
  /// once. Capacity is enforced server-side, so a failure just keeps the
  /// fallback rather than blocking the screen.
  static Future<void> load([MatchService? service]) async {
    try {
      final value = await (service ?? MatchService()).fetchReservePlayers();
      if (value != null && value >= 0) _reservePlayers = value;
    } catch (_) {
      // Keep the fallback; capacity is enforced server-side anyway.
    }
  }
}
