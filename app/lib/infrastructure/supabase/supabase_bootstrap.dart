import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

/// Starts the Supabase SDK and hands out the one client the adapters share.
///
/// This is where the application's only data provider is named. `main.dart`
/// asks for initialisation without importing the SDK, which is what keeps
/// "Supabase" a fact of the infrastructure layer alone (OP-3).
class SupabaseBootstrap {
  SupabaseBootstrap._();

  static Future<void> initialize() => Supabase.initialize(
        url: AppConfig.supabaseUrl,
        // Accepts either the new publishable key or the legacy anon key.
        publishableKey: AppConfig.supabaseAnonKey,
      );

  /// The client every Supabase adapter talks through.
  static SupabaseClient get client => Supabase.instance.client;
}
