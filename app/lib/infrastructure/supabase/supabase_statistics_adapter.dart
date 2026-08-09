import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/statistics/statistics_adapter.dart';
import '../../features/statistics/statistics_models.dart';
import 'mappers/statistics_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the statistics port.
///
/// Two reads against objects that already exist — `community_statistics` from
/// migration `0028` and `v_community_summary` from `0025`. No RPC, no view and
/// no table was added for this screen.
///
/// Authorization is the database's, not this class's.
/// `community_statistics_select_members` returns a community's records only to
/// its members, so a non-member reading another community's statistics gets an
/// empty list rather than a refusal — the same shape a community with no
/// records has. The `eq` filters below say which rows are meant, never who may
/// have them.
class SupabaseStatisticsAdapter implements StatisticsAdapter {
  SupabaseStatisticsAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// The counters, plus the player's name through the foreign key to `users`.
  ///
  /// `created_at` and `updated_at` are not read: nothing on the dashboard shows
  /// when a counter last moved. `period_type` and `period_key` are not read
  /// either — the filter below fixes them, so carrying them back would only
  /// restate the question.
  static const _columns = 'user_id, matches_played, wins, losses, draws, '
      'goals, mvp_count, user:users(full_name)';

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
  ) =>
      guarded(() async {
        // `overall` is a period like any other in this table, with a fixed key.
        // Naming it here is what makes this a career-in-this-community read
        // rather than a read of every period at once, which would return the
        // same player three times.
        final rows = await _client
            .from('community_statistics')
            .select(_columns)
            .eq('community_id', communityId)
            .eq('period_type', 'overall');

        return [
          for (final row in rows) communityPlayerStatisticsFromRow(row),
        ];
      });

  /// Reads the roster from `v_community_members` (migration `0025`).
  ///
  /// The view already inner-joins the roster to the profiles, so it answers
  /// "who is in this community, and what does each of them rate" in one read —
  /// which is exactly the population and the measure the Highest Rated board
  /// needs. Nothing was added to the database for it.
  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      guarded(() async {
        final rows = await _client
            .from('v_community_members')
            .select('user_id, full_name, overall_rating')
            .eq('community_id', communityId);

        return [for (final row in rows) communityMemberRatingFromRow(row)];
      });

  @override
  Future<int> fetchTotalMatches(String communityId) => guarded(() async {
        final row = await _client
            .from('v_community_summary')
            .select('total_matches')
            .eq('community_id', communityId)
            .maybeSingle();
        // The community is not there, or not visible to this caller. Either
        // way there is no figure to report, and reporting zero would state
        // something the read never established.
        if (row == null) throw const NotFoundFailure();
        return (row['total_matches'] as num).toInt();
      });
}
