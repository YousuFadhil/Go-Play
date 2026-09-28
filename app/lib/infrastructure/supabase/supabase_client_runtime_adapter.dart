import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/runtime/client_runtime_adapter.dart';
import '../../features/runtime/client_runtime_models.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the client runtime port: `start_client_runtime_v1`
/// and `report_client_error_v1` (migration `0090`), both callable signed in or
/// not, both behind the telemetry circuit breaker.
///
/// Nothing about the reader travels. A run carries the build; an error carries
/// its run id, category, fingerprint and a short sanitized code.
class SupabaseClientRuntimeAdapter implements ClientRuntimeAdapter {
  SupabaseClientRuntimeAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<String> startRun(ClientRuntimeIdentity identity) => guarded(
        () async {
          final runId = await _client.rpc(
            'start_client_runtime_v1',
            params: {
              'p_platform': identity.platform,
              'p_app_version': identity.appVersion,
              'p_build_sha': identity.buildSha,
            },
          );
          return runId as String;
        },
        operation: 'rpc start_client_runtime_v1',
      );

  @override
  Future<void> reportError({
    required String runId,
    required ClientErrorCategory category,
    required String fingerprint,
    String? contextCode,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'report_client_error_v1',
            params: {
              'p_run_id': runId,
              'p_category': category.wireName,
              'p_fingerprint': fingerprint,
              'p_context_code': contextCode,
            },
          );
        },
        operation: 'rpc report_client_error_v1',
      );
}
