import 'analytics_models.dart';

/// The analytics port into the data provider.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). **Nothing here decides whether a failure
/// matters** — an adapter reports what happened and the repository above it is
/// what turns an analytics failure into silence.
abstract interface class AnalyticsAdapter {
  /// Records [event] against the signed-in account.
  ///
  /// There is deliberately **no user id parameter**, here or in the RPC beneath
  /// it. The database takes the actor from `auth.uid()`, so an event can only
  /// ever be attributed to the session that recorded it — a client-supplied id
  /// would be a way to write activity against somebody else.
  ///
  /// [communityId] and [matchId] are passed only when the calling screen
  /// already holds them. Null is ordinary: no screen makes an extra request to
  /// populate an analytics field.
  Future<void> record(
    ProductEvent event, {
    String? communityId,
    String? matchId,
  });
}
