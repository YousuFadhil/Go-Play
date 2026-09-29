import '../../infrastructure/supabase/supabase_client_runtime_adapter.dart';
import 'client_runtime_adapter.dart';
import 'client_runtime_models.dart';

/// Client runtime evidence that can never become a client failure itself.
///
/// The `AnalyticsRepository` rule: catch **everything** and return normally.
/// A run that could not be started is a missing denominator, and an error that
/// could not be reported is a missing numerator — never a crash, a blocked
/// screen or a second error.
class ClientRuntimeRepository {
  ClientRuntimeRepository([ClientRuntimeAdapter? adapter])
      : _injected = adapter;

  /// Supplied only by tests.
  final ClientRuntimeAdapter? _injected;

  /// Built on first use and inside the guard, so an uninitialised Supabase
  /// client is swallowed like any other failure.
  ClientRuntimeAdapter? _adapter;

  ClientRuntimeAdapter get _port =>
      _injected ?? (_adapter ??= SupabaseClientRuntimeAdapter());

  /// The server's run id, or null when no run was started for any reason —
  /// including the telemetry circuit breaker refusing it.
  Future<String?> startRun(ClientRuntimeIdentity identity) async {
    try {
      return await _port.startRun(identity);
    } catch (_) {
      return null;
    }
  }

  /// Reports nothing, whatever happens.
  Future<void> reportError({
    required String runId,
    required ClientErrorCategory category,
    required String fingerprint,
    String? contextCode,
  }) async {
    try {
      await _port.reportError(
        runId: runId,
        category: category,
        fingerprint: fingerprint,
        contextCode: contextCode,
      );
    } catch (_) {
      // Deliberately silent: see the class comment.
    }
  }
}
