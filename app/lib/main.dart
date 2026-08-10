import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/config_error_app.dart';
import 'core/locale_controller.dart';
import 'features/notifications/push_service.dart';
import 'infrastructure/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved language (Arabic by default) before the first frame.
  await LocaleController.instance.load();

  if (kDebugMode) {
    debugPrint('[GoPlay] SUPABASE_URL = '
        '${AppConfig.supabaseUrl.isEmpty ? "<EMPTY>" : AppConfig.supabaseUrl}');
    debugPrint('[GoPlay] SUPABASE_ANON_KEY = ${AppConfig.maskedAnonKey}');
    debugPrint('[GoPlay] config valid = ${AppConfig.isValid}');
  }

  // Fail fast: never boot the real app against a missing/invalid config.
  if (!AppConfig.isValid) {
    runApp(const ConfigErrorApp());
    return;
  }

  await SupabaseBootstrap.initialize();

  // Follows the session from here on: registers this device when somebody signs
  // in, forgets it when they sign out. Returns as soon as it is listening —
  // Firebase itself is reached on the first signed-in event, and an unconfigured
  // or refused Firebase costs the app nothing but push.
  await PushService.instance.start();

  runApp(const GoPlayApp());
}
