import 'statistics_models.dart';

/// The statistics domain's port into the data provider.
///
/// Read-only, and permanently so. Every counter behind this port is written by
/// the database as a consequence of a result being recorded, corrected or
/// removed; there is no client write path to expose, so this contract has no
/// write method and no implementation may add one.
abstract interface class StatisticsAdapter {
  /// Every player's `overall` counters in one community, one row per player.
  ///
  /// Returns the community's whole population — including players who have
  /// since left, whose records are preserved. Filtering to current members is a
  /// product decision and belongs above this layer (OP-2); the dashboard
  /// deliberately does not filter, because a departed player's goals still
  /// happened.
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
  );

  /// How many matches the community has, of any status.
  ///
  /// Separate from the counters on purpose: this is a fact about matches, and
  /// the statistics table cannot answer it (see [CommunityDashboard]).
  Future<int> fetchTotalMatches(String communityId);

  /// The community's current members and the rating each holds.
  ///
  /// This is the population a leaderboard may rank. It is a separate read from
  /// the counters because the counters deliberately outlive membership — a
  /// record is preserved when a player leaves — and a board ranks people who
  /// are still here.
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  );
}
