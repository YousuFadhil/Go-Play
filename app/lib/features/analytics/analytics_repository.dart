import '../../infrastructure/supabase/supabase_analytics_adapter.dart';
import 'analytics_adapter.dart';
import 'analytics_models.dart';

/// Recording what happened, in a way that can never stop it happening.
///
/// **This is the layer where an analytics failure ends.** Everywhere else in
/// the application a repository lets a `Failure` through, because a caller that
/// asked for something needs to know it did not get it. Analytics is the one
/// operation nobody asked for: the reader pressed Register, not Record An
/// Event, and a measurement that fails must leave the thing being measured
/// completely untouched.
///
/// So [track] catches everything and returns normally. Not `on Failure` —
/// **everything**: a `Failure` from the adapter, a Supabase client that was
/// never initialised, a platform channel missing under test, a bug in this
/// file. The product flow above must not be able to tell the difference between
/// an event that was recorded and one that was not, and the only way to
/// guarantee that is to have no path out of here that throws.
class AnalyticsRepository {
  AnalyticsRepository([AnalyticsAdapter? adapter]) : _injected = adapter;

  /// Supplied only by tests, exactly as every other repository takes its port.
  final AnalyticsAdapter? _injected;

  /// The production adapter, built on first use and kept.
  ///
  /// **Built lazily, and inside the guard below.** Constructing it reaches for
  /// the shared Supabase client, which throws when the SDK has not been
  /// initialised — which is the normal state of a widget test that injects
  /// every other port. Resolving it eagerly in the constructor would make
  /// analytics the one thing in the application capable of failing a screen it
  /// only observes.
  AnalyticsAdapter? _adapter;

  /// Records [event], and reports nothing whatever it happens.
  ///
  /// Completes normally in every case. There is no return value, because there
  /// is no outcome a caller could act on: acting on it would be exactly the
  /// coupling this class exists to prevent.
  Future<void> track(
    ProductEvent event, {
    String? communityId,
    String? matchId,
  }) async {
    try {
      final adapter = _injected ?? (_adapter ??= SupabaseAnalyticsAdapter());
      await adapter.record(event, communityId: communityId, matchId: matchId);
    } catch (_) {
      // Deliberately silent, and deliberately catching everything. See above.
      // Nothing is shown to the reader, nothing is retried, and nothing is
      // queued: an event that did not reach the database is an event that did
      // not happen, which is a gap in a metric and never a fault in a match.
    }
  }
}
