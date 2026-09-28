import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/config_error_app.dart';
import 'core/locale_controller.dart';
import 'features/auth/password_recovery_state.dart';
import 'features/notifications/push_service.dart';
import 'features/runtime/client_runtime_reporter.dart';
import 'infrastructure/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the saved language before the first frame. Without one the app
  // follows the device, so this is a no-op for a reader who has never chosen.
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

  // Whether a password recovery is in progress is read from storage, and the
  // address the app was launched with is checked for the recovery callback --
  // both **before the SDK starts**. On the web the SDK exchanges a link's
  // credentials and strips them from the address while it initialises, and its
  // auth events are emitted then too, possibly before anything is listening; by
  // the time the app is up neither the link nor the event can be recovered. What
  // is recorded here is what the auth gate consults first, so a recovery session
  // is never mistaken for an ordinary one -- on this launch or after a restart.
  await PasswordRecoveryState.instance.load();
  await PasswordRecoveryState.instance.captureLink(
    kIsWeb ? Uri.base.toString() : PlatformDispatcher.instance.defaultRouteName,
  );

  await SupabaseBootstrap.initialize();

  // Production-only operational evidence (Wave 4): one run for this process
  // and its uncaught errors. Never awaited, never blocking, and a no-op in
  // staging, debug and local builds.
  ClientRuntimeReporter.instance.start();

  // Follows the session from here on: registers this device when somebody signs
  // in, forgets it when they sign out. Returns as soon as it is listening —
  // Firebase itself is reached on the first signed-in event, and an unconfigured
  // or refused Firebase costs the app nothing but push.
  await PushService.instance.start();

  runApp(const GoPlayApp());
}
