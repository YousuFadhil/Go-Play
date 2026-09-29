import '../../core/failures.dart';
import '../../features/communities/community_insights_adapter.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

class SupabaseCommunityInsightsAdapter implements CommunityInsightsAdapter {
  @override
  Future<CommunityInsights> fetch(String communityId) => guarded(
        () async {
          final result = await SupabaseBootstrap.client.rpc(
            'community_insights_v1',
            params: {'p_community_id': communityId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();

          final row = rows.first;
          double? decimal(String key) => (row[key] as num?)?.toDouble();

          return CommunityInsights(
            eligibleMembers: (row['eligible_members'] as num?)?.toInt() ?? 0,
            activeMembers30d: (row['active_members_30d'] as num?)?.toInt() ?? 0,
            participationRate30d: decimal('participation_rate_30d'),
            matches30d: (row['matches_30d'] as num?)?.toInt() ?? 0,
            matchesPerWeek: (row['matches_per_week'] as num?)?.toDouble() ?? 0,
            avgCapacityUtilization: decimal('avg_capacity_utilization'),
            guestDependency: decimal('guest_dependency'),
          );
        },
        operation: 'rpc community_insights_v1',
      );
}
