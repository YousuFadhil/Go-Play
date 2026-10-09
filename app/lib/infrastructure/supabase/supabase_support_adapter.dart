import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/support/support_adapter.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Reads the platform's support destination under the existing app_settings
/// authenticated SELECT policy; writes pass through one System Admin RPC.
class SupabaseSupportAdapter implements SupportAdapter {
  SupabaseSupportAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<String?> fetchWhatsAppPhone() => guarded(() async {
        final row = await _client
            .from('app_settings')
            .select('support_whatsapp_phone')
            .eq('id', true)
            .single();
        return row['support_whatsapp_phone'] as String?;
      });

  @override
  Future<void> setWhatsAppPhone(String? phone) => guarded(() async {
        await _client.rpc(
          'admin_set_support_whatsapp_phone',
          params: {'p_phone': phone},
        );
      });
}
