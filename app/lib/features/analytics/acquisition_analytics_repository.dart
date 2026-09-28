import '../../infrastructure/supabase/supabase_acquisition_analytics_adapter.dart';
import '../sharing/public_link.dart';
import 'acquisition_analytics_adapter.dart';

/// Acquisition measurement that can never stop what it measures.
///
/// The same rule as `AnalyticsRepository`, for the same reason: nobody asked
/// for this, so it catches **everything** — a `Failure`, a Supabase client
/// that was never initialised, a bug in this file — and returns normally.
/// Public reading, sign-in, registration and the navigation after them cannot
/// tell a recorded event from a lost one.
class AcquisitionAnalyticsRepository {
  AcquisitionAnalyticsRepository([AcquisitionAnalyticsAdapter? adapter])
      : _injected = adapter;

  /// Supplied only by tests.
  final AcquisitionAnalyticsAdapter? _injected;

  /// Built on first use and inside the guard, so a widget test that never
  /// initialises Supabase cannot be failed by it.
  AcquisitionAnalyticsAdapter? _adapter;

  AcquisitionAnalyticsAdapter get _port =>
      _injected ?? (_adapter ??= SupabaseAcquisitionAnalyticsAdapter());

  /// The acquisition id of a recorded anonymous open, or null when it was not
  /// recorded for any reason.
  Future<String?> recordAnonymousOpen(PublicLinkKind kind) async {
    try {
      return await _port.recordAnonymousOpen(kind);
    } catch (_) {
      return null;
    }
  }

  /// Reports nothing, whatever happens.
  Future<void> recordSignupCompleted(String acquisitionId) async {
    try {
      await _port.recordSignupCompleted(acquisitionId);
    } catch (_) {
      // Deliberately silent. A conversion that did not reach the database is a
      // gap in a metric, never a fault in a registration.
    }
  }
}
