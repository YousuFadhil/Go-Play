import 'package:shared_preferences/shared_preferences.dart';

/// Where a visitor's chosen Wilayat is kept: on this device, and nowhere else.
///
/// A guest has no account to hold a Default Location, so the choice is a local
/// preference -- the same place the language setting lives. It is never sent
/// anywhere and never migrated to an account: signing in means the account's own
/// Default Location applies.
///
/// Every failure reads as "no choice". Storage that is blocked or missing (a
/// private window, a test) must not stop Discover from opening.
class GuestLocationStore {
  GuestLocationStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static const String key = 'guest_near_wilayat_code';

  Future<int?> load() async {
    try {
      return (await _preferences()).getInt(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(int? code) async {
    try {
      final prefs = await _preferences();
      if (code == null) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, code);
      }
    } catch (_) {
      // Non-fatal: the choice still applies until the screen is left.
    }
  }
}
