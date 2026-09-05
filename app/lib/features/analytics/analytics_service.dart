import 'dart:async';

import 'analytics_models.dart';
import 'analytics_repository.dart';

/// How a screen records an event: one line, no plumbing, no waiting.
///
/// **A singleton, for the same reason `PushService`, `PendingInvite`,
/// `CurrentMatchDetails` and `LocaleController` are.** Analytics is observed
/// from a dozen screens that have nothing else in common, and threading an
/// optional repository through every one of their constructors would be a
/// larger change to the product than the measurement is worth — the brief is
/// explicit that production code must not be restructured to make analytics
/// testable. Screens reach for [instance]; tests replace it.
///
/// **Nothing here is awaited by a product flow.** [track] returns void, not a
/// Future: there is nothing to wait for and no outcome to branch on, and a
/// signature that offered one would invite a caller to `await` a measurement
/// before letting a registration complete.
class ProductAnalytics {
  ProductAnalytics({AnalyticsRepository? repository})
      : _repository = repository ?? AnalyticsRepository();

  /// The one every screen uses.
  ///
  /// Assignable so a test can put its own in place and read what was recorded;
  /// nothing in the application assigns it. Lazily initialised, as all Dart
  /// statics are, so a test that never touches analytics never builds one.
  static ProductAnalytics instance = ProductAnalytics();

  final AnalyticsRepository _repository;

  /// Whether this signed-in session has already been recorded.
  ///
  /// The whole of the session rule lives in this one boolean: a session is
  /// recorded when an authenticated, active reader enters the application, and
  /// the next `session_started` cannot happen until [endSession] is called.
  bool _sessionRecorded = false;

  /// Records [event]. Never throws, never blocks, never reports.
  ///
  /// The repository already swallows everything; `unawaited` is what keeps the
  /// *caller* free of it, so a registration completes and a screen rebuilds
  /// without a round trip to the analytics RPC in between.
  void track(
    ProductEvent event, {
    String? communityId,
    String? matchId,
  }) {
    unawaited(
      _repository.track(event, communityId: communityId, matchId: matchId),
    );
  }

  /// The one `session_started` for this signed-in session.
  ///
  /// Idempotent by design, because the gate that calls it is not: it re-checks
  /// the account on every resume and on every rebuild of the widget tree, and a
  /// session that counted itself again on each of those would make DAU a
  /// measure of how often people switch apps.
  ///
  /// **App resume is deliberately not a new session.** The approved model has
  /// no timeout: a session starts when a reader enters the application and ends
  /// when they sign out.
  void startSession() {
    if (_sessionRecorded) return;
    _sessionRecorded = true;
    track(ProductEvent.sessionStarted);
  }

  /// Signing out ends the session, so signing back in starts a real new one.
  ///
  /// Only the guard is reset. There is no `session_ended` event: the approved
  /// list has ten names and this is not one of them, and a session's length is
  /// not something this cycle measures.
  void endSession() => _sessionRecorded = false;
}
