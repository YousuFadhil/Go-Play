import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app locale and persists the user's choice. Arabic is the default
/// on first launch; the saved value is reused on later launches.
class LocaleController {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String _prefsKey = 'app_locale';
  static const List<String> supported = ['ar', 'en'];

  final ValueNotifier<Locale> locale = ValueNotifier(const Locale('ar'));

  /// Loads the persisted locale. Called once before the app starts.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code != null && supported.contains(code)) {
        locale.value = Locale(code);
      }
    } catch (_) {
      // Fall back to the Arabic default if storage is unavailable.
    }
  }

  Future<void> setLocale(String code) async {
    if (!supported.contains(code)) return;
    locale.value = Locale(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }
}
