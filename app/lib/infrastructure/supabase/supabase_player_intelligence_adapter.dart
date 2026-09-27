import '../../core/failures.dart';
import '../../features/statistics/player_intelligence_adapter.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the narrow Player Intelligence read port.
///
/// The RPC is additive (migration 0086), read-only, and returns one aggregate.
/// No rating-history row or match detail is exposed to the client.
class SupabasePlayerIntelligenceAdapter implements PlayerIntelligenceAdapter {
  @override
  Future<PlayerRatingTrend> fetchRatingTrend(String userId) => guarded(
        () async {
          final result = await SupabaseBootstrap.client.rpc(
            'player_rating_trend_v1',
            params: {'p_user_id': userId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();

          final row = rows.first;
          return PlayerRatingTrend(
            matchesCount: (row['matches_count'] as num?)?.toInt() ?? 0,
            ratingDelta: (row['rating_delta'] as num?)?.toDouble() ?? 0,
          );
        },
        operation: 'rpc player_rating_trend_v1',
      );
}
