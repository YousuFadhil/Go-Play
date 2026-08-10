import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app locale and persists the user's choice.
///
/// The default is **the device's own language**, not a language this app picked
/// for them: `null` means "follow the phone", and Flutter resolves it against
/// [supported] the same way every other app on the device does. A visitor who
/// has never opened Settings therefore reads Go Play in whatever they read
/// everything else in.
///
/// A stored choice outranks the device, and is the only thing that does. It is
/// made in one place — the Settings screen — so the language is a setting rather
/// than a control that follows the reader around the product.
class LocaleController {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const String _prefsKey = 'app_locale';

  /// What is written when the reader asks to follow the device again. Stored
  /// rather than cleared so that "I chose the device" and "I have never chosen"
  /// stay the same answer without the key having to be absent to mean it.
  static const String systemValue = 'system';

  static const List<String> supported = ['ar', 'en'];

  /// `null` while the app follows the device.
  final ValueNotifier<Locale?> locale = ValueNotifier(null);

  /// Loads the persisted choice. Called once before the app starts.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code != null && supported.contains(code)) {
        locale.value = Locale(code);
      }
    } catch (_) {
      // Fall back to the device language if storage is unavailable.
    }
  }

  /// Sets the language, or returns to the device's with `null`.
  Future<void> setLocale(String? code) async {
    if (code != null && !supported.contains(code)) return;
    locale.value = code == null ? null : Locale(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code ?? systemValue);
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }
}
