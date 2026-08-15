import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/statistics/statistics_adapter.dart';
import '../../features/statistics/statistics_models.dart';
import 'mappers/statistics_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the statistics port.
///
/// Reads against objects that already exist — `community_statistics` from
/// migration `0028`, `v_community_members` from `0025`, and the `matches` table
/// itself. No RPC, no view and no table was added for this screen.
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
  ///
  /// `avatar_path` joins the embed rather than arriving through a second read:
  /// the query already reaches `users` for the name, and a player's picture is
  /// readable by exactly the people who can read it.
  static const _columns = 'user_id, matches_played, wins, losses, draws, '
      'goals, mvp_count, user:users(full_name, avatar_path)';

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
          for (final row in rows)
            communityPlayerStatisticsFromRow(
              row,
              // Unversioned, as everywhere a list of faces is read: busting the
              // cache on every read would refetch all of them each time.
              avatarUrl: (path) => SupabaseAvatars.publicUrl(_client, path),
            ),
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

        // The view carries the roster and the rating; it does not carry
        // `avatar_path`. The faces are looked up alongside it rather than
        // widened into the view, which is the same thing the match roster does
        // and for the same reason — `users.avatar_path` is already readable by
        // everyone who can read the name beside it.
        final avatars = await SupabaseAvatars.urlsForUsers(_client, [
          for (final row in rows) row['user_id'] as String,
        ]);

        return [
          for (final row in rows)
            communityMemberRatingFromRow(
              row,
              avatarUrl: avatars[row['user_id']],
            ),
        ];
      });

  /// How many matches this community has completed.
  ///
  /// Reads `v_completed_matches` (migration `0037`), which applies the rule
  /// `0029` made authoritative: a match is completed when its status says so
  /// **or** its end time has passed.
  ///
  /// This class does not restate that rule. An earlier version of this method
  /// filtered on `status = 'completed'` alone and returned zero for communities
  /// with finished matches — nothing marks a match completed once it merely
  /// finishes, because every path that would has already refused to run by
  /// then. The condition lives in the database, in one place, so this count and
  /// the match list cannot report different histories.
  ///
  /// It is a filter, not an authorization — the `matches` policies decide whose
  /// rows come back through the view's `security_invoker`, and a caller who
  /// cannot see a community's matches counts none of them.
  @override
  Future<int> fetchCompletedMatches(String communityId) => guarded(() async {
        final response = await _client
            .from('v_completed_matches')
            .select('match_id')
            .eq('community_id', communityId)
            .count(CountOption.exact);
        return response.count;
      });
}
