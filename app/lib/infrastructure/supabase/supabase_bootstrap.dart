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

  /// A second, short-lived Auth client that differs from [client]'s in exactly
  /// one way: it uses the **implicit** flow, so what it asks the provider to send
  /// carries no PKCE challenge.
  ///
  /// It exists for one request -- the password-recovery email on the web -- and
  /// is never given a session, storage or a listener. See
  /// `SupabaseAuthAdapter.requestPasswordReset` for why that request cannot use
  /// the app-wide PKCE flow. The caller disposes it.
  static GoTrueClient newImplicitAuthClient() => GoTrueClient(
        url: '${AppConfig.supabaseUrl}/auth/v1',
        headers: {
          ...client.headers,
          'apikey': AppConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        },
        autoRefreshToken: false,
        flowType: AuthFlowType.implicit,
      );
}
