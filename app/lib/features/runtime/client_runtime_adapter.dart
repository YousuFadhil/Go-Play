import 'client_runtime_models.dart';

/// Port for Wave 4 client runtime evidence: the two RPCs of migration `0090`.
///
/// Operational evidence, not product analytics — a separate port from
/// `AnalyticsAdapter`, writing a separate table, keyed by a run rather than by
/// a person.
abstract interface class ClientRuntimeAdapter {
  /// Starts one production run and returns the run id the server generated.
  Future<String> startRun(ClientRuntimeIdentity identity);

  /// Reports one uncaught error of [runId]. The server copies the build from
  /// the run; only the category, fingerprint and context code travel.
  Future<void> reportError({
    required String runId,
    required ClientErrorCategory category,
    required String fingerprint,
    String? contextCode,
  });
}
