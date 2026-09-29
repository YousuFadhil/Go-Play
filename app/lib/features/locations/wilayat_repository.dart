import '../../infrastructure/supabase/supabase_wilayat_adapter.dart';
import 'wilayat_adapter.dart';
import 'wilayat_models.dart';

/// The Wilayat reference data, fetched once and held.
///
/// Thin on purpose, like [DiscoverRepository]: there is nothing to decide about a
/// list of places. What it owns is the cache -- one read per app session, shared
/// by Discover, the community screens and the profile through [shared], so the
/// picker opens instantly the second time and a name on a card never costs a
/// request of its own.
///
/// A failed read is not cached: the next caller asks again, which is what lets a
/// retry button work.
class WilayatRepository {
  WilayatRepository([WilayatAdapter? adapter]) : _adapter = adapter;

  /// The production instance. Tests construct their own with a fake port, and
  /// never share this one's cache.
  static final WilayatRepository shared = WilayatRepository();

  /// Built on first use rather than with this object. Constructing the
  /// production adapter reaches the data provider's client, which does not exist
  /// in a widget test -- and a label is not a reason for one to fail.
  WilayatAdapter? _adapter;
  WilayatCatalog? _catalog;
  Future<WilayatCatalog>? _inFlight;

  /// What has been read, or null. For a caller that wants a label if one is
  /// already there and has nothing to wait for.
  WilayatCatalog? get cached => _catalog;

  /// The catalog, from memory when it is already held.
  Future<WilayatCatalog> load() {
    final held = _catalog;
    if (held != null) return Future.value(held);
    return _inFlight ??= _read();
  }

  Future<WilayatCatalog> _read() async {
    try {
      final adapter = _adapter ??= SupabaseWilayatAdapter();
      return _catalog = await adapter.fetchCatalog();
    } finally {
      _inFlight = null;
    }
  }
}
