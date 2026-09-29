import 'wilayat_models.dart';

/// The reference-data port into the data provider.
///
/// Public by contract: a guest chooses a Wilayat too, so this read must succeed
/// with no session. Domain Models only (OP-3); an implementation raises a
/// `Failure` rather than a provider exception (OP-5).
abstract interface class WilayatAdapter {
  /// Every Governorate and every Wilayat, active or not.
  ///
  /// Not filtered here: a retired Wilayat still names a community that already
  /// carries it, and what may be *offered* is the catalog's decision.
  Future<WilayatCatalog> fetchCatalog();
}
