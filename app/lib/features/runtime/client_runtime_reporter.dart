import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import 'client_runtime_fingerprint.dart';
import 'client_runtime_models.dart';
import 'client_runtime_repository.dart';

/// Production client runtime evidence (Wave 4, OI-06): one run per app
/// process or page load, and the uncaught errors that happen inside it.
///
/// **Production only.** A build is reporting only when its deployment
/// environment is `production` ([ClientRuntimeIdentity.resolve]); in every
/// other build [start] does nothing at all — no request, and no error handler
/// is touched.
///
/// **Memory only.** The run id is a field of this object and dies with the
/// process. It is never written to the device, the browser or the account.
///
/// **Observing, never handling.** The handlers it installs report and then
/// hand the error to whatever handled it before, returning what that handler
/// returned. An error that would have crashed, logged or been presented still
/// does exactly that.
///
/// **Never blocking.** Nothing here is awaited by the product, and every
/// network failure is swallowed by [ClientRuntimeRepository].
class ClientRuntimeReporter {
  ClientRuntimeReporter({
    ClientRuntimeRepository? repository,
    ClientRuntimeIdentity? identity,
  })  : _repository = repository ?? ClientRuntimeRepository(),
        _identity = identity;

  /// The reporter `main` starts. Enabled only for a production build.
  static ClientRuntimeReporter instance = ClientRuntimeReporter(
    identity: ClientRuntimeIdentity.resolve(
      environment: AppConfig.deploymentEnvironment,
      appVersion: AppConfig.appVersion,
      buildSha: AppConfig.buildSha,
      platform: ClientRuntimeIdentity.currentPlatform(),
    ),
  );

  /// At most this many errors are reported per run. It bounds a failure that
  /// repeats every frame; it does not change the run-based error rate, which
  /// counts runs with at least one error.
  static const int maxReportsPerRun = 20;

  final ClientRuntimeRepository _repository;
  final ClientRuntimeIdentity? _identity;

  /// The run, once asked for. Resolves to null when none could be started.
  Future<String?>? _run;

  int _reportsLeft = maxReportsPerRun;

  /// Whether this build reports at all.
  bool get enabled => _identity != null;

  /// Starts this process's run and begins observing uncaught errors.
  ///
  /// Idempotent: the first call starts the one run, later calls do nothing.
  /// Returns immediately; the run is requested in the background.
  void start() {
    final identity = _identity;
    if (identity == null || _run != null) return;
    _run = _repository.startRun(identity);
    _observeUncaughtErrors();
  }

  void _observeUncaughtErrors() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.silent) {
        _observe(
          ClientErrorCategory.flutterFramework,
          details.exception,
          details.stack,
        );
      }
      previousFlutterHandler?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformHandler = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      _observe(ClientErrorCategory.platformUnhandled, error, stack);
      // Unhandled stays unhandled: without a previous handler the answer is
      // `false`, which is what a null handler meant.
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Summarises [error] locally and reports it in the background.
  ///
  /// Guarded so that nothing about reporting — not a fingerprint, not a
  /// request — can throw into the handler it runs inside.
  void _observe(ClientErrorCategory category, Object error, StackTrace? stack) {
    try {
      final run = _run;
      if (run == null || _reportsLeft <= 0) return;
      _reportsLeft--;
      final fingerprint = clientErrorFingerprint(error, stack);
      final contextCode = clientErrorContextCode(error);
      unawaited(_send(run, category, fingerprint, contextCode));
    } catch (_) {
      // Reporting never becomes a second failure.
    }
  }

  Future<void> _send(
    Future<String?> run,
    ClientErrorCategory category,
    String fingerprint,
    String contextCode,
  ) async {
    // An error before the run is known waits for it; without a run nothing is
    // reported, because an error with no run would be fabricated evidence.
    final runId = await run;
    if (runId == null) return;
    await _repository.reportError(
      runId: runId,
      category: category,
      fingerprint: fingerprint,
      contextCode: contextCode,
    );
  }
}
