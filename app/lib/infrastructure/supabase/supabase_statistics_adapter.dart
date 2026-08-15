import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/statistics/statistics_adapter.dart';
import '../../features/statistics/statistics_models.dart';
import '../../features/statistics/statistics_period.dart';
import 'mappers/statistics_mapper.dart';
import 'statistics_period_window.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the statistics port.
///
/// Reads against objects that already exist — `community_statistics` from
/// migration `0028`, `v_community_members` from `0025`, and
/// `v_completed_matches` from `0037`. No RPC, no view and no table was added
/// for this screen, and none for the periods either: the weekly and monthly
/// figures were already stored and simply were not being read.
///
/// **This class is where a period becomes a `period_type` and a `period_key`,
/// and it is the only place that knows either word.** [StatisticsPeriodWindow]
/// holds the translation, including the Asia/Muscat rule the database froze.
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
  /// either — the filters below fix them, so carrying them back would only
  /// restate the question.
  ///
  /// `avatar_path` joins the embed rather than arriving through a second read:
  /// the query already reaches `users` for the name, and a player's picture is
  /// readable by exactly the people who can read it.
  static const _columns = 'user_id, matches_played, wins, losses, draws, '
      'goals, mvp_count, user:users(full_name, avatar_path)';

  /// The same counters without the profile embed. The player's own totals are
  /// summed into six numbers and never name anybody, so the join would be
  /// fetching a name nothing displays — once per community they belong to.
  static const _counterColumns =
      'user_id, matches_played, wins, losses, draws, goals, mvp_count';

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) =>
      guarded(() async {
        // Both halves of the key are named, always. `overall` is a period like
        // any other in this table, with a fixed key; naming it is what makes
        // All Time a career-in-this-community read rather than a read of every
        // period at once, which would return the same player three times. For a
        // week or a month the key is what makes it *this* week rather than
        // every week the community has ever played.
        final rows = await _client
            .from('community_statistics')
            .select(_columns)
            .eq('community_id', communityId)
            .eq('period_type', StatisticsPeriodWindow.periodType(period))
            .eq('period_key', StatisticsPeriodWindow.periodKey(period));

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

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      guarded(() async {
        // Along the other axis of the same table: one player, every community,
        // one period. `0028` added the index for exactly this read.
        final rows = await _client
            .from('community_statistics')
            .select(_counterColumns)
            .eq('user_id', userId)
            .eq('period_type', StatisticsPeriodWindow.periodType(period))
            .eq('period_key', StatisticsPeriodWindow.periodKey(period));

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

  /// How many matches this community has completed within the period.
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
  /// The period narrows it by `start_at`, which is the same field and the same
  /// boundary the database used to bucket that match's counters (`CS-C15`). All
  /// Time adds no bound at all — it is every completed match, exactly as before.
  ///
  /// It is a filter, not an authorization — the `matches` policies decide whose
  /// rows come back through the view's `security_invoker`, and a caller who
  /// cannot see a community's matches counts none of them.
  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) =>
      guarded(() async {
        var query = _client
            .from('v_completed_matches')
            .select('match_id')
            .eq('community_id', communityId);

        final bounds = StatisticsPeriodWindow.bounds(period);
        if (bounds != null) {
          // Half-open, so a match starting exactly at midnight belongs to the
          // period beginning then and to no other.
          query = query
              .gte('start_at', bounds.from.toIso8601String())
              .lt('start_at', bounds.to.toIso8601String());
        }

        final response = await query.count(CountOption.exact);
        return response.count;
      });
}
