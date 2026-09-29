import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/locations/wilayat_adapter.dart';
import '../../features/locations/wilayat_models.dart';
import 'mappers/wilayat_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the Wilayat reference-data port.
///
/// Two plain table reads. `governorates` and `wilayats` (migration `0094`) are
/// readable by `anon` and `authenticated` and writable by neither, so the same
/// request answers for a visitor and a member.
class SupabaseWilayatAdapter implements WilayatAdapter {
  SupabaseWilayatAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<WilayatCatalog> fetchCatalog() => guarded(() async {
        final reads = await Future.wait([
          _client
              .from('governorates')
              .select('code, name_ar, name_en, sort_order')
              .order('sort_order'),
          _client
              .from('wilayats')
              .select(
                'code, governorate_code, name_ar, name_en, search_terms, '
                'sort_order, is_active',
              )
              .order('sort_order'),
        ]);
        return WilayatCatalog(
          governorates: [for (final row in reads[0]) governorateFromRow(row)],
          wilayats: [for (final row in reads[1]) wilayatFromRow(row)],
        );
      });
}
