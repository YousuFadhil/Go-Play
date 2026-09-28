import '../sharing/public_link.dart';

/// The analytics port for Wave 3's public-link acquisition measurement.
///
/// Not a second analytics system: both operations write `product_events`,
/// through two narrow RPCs of migration `0089`. It is a separate port from
/// `AnalyticsAdapter` because its two calls are shaped differently from the
/// generic writer — one is made with no session at all, and neither takes an
/// event name.
abstract interface class AcquisitionAnalyticsAdapter {
  /// Records an anonymous `public_link_opened` of [kind] and returns the
  /// acquisition id the database generated for it.
  ///
  /// Only the kind travels: never the target's id, and nothing about the
  /// reader.
  Future<String> recordAnonymousOpen(PublicLinkKind kind);

  /// Records `public_link_signup_completed` for the signed-in account against
  /// [acquisitionId]. The database decides whether it counts.
  Future<void> recordSignupCompleted(String acquisitionId);
}
