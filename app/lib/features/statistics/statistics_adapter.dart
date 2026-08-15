import 'statistics_models.dart';
import 'statistics_period.dart';

/// The statistics domain's port into the data provider.
///
/// Read-only, and permanently so. Every counter behind this port is written by
/// the database as a consequence of a result being recorded, corrected or
/// removed; there is no client write path to expose, so this contract has no
/// write method and no implementation may add one.
///
/// **The period is a parameter, never a default.** The table has always held
/// three periods per player and the app read one of them; making the caller
/// name which is what stops a screen from silently getting the running total
/// when it asked for a week. [StatisticsPeriod] is a domain value — how a
/// period is spelled on the wire is the implementation's business alone.
abstract interface class StatisticsAdapter {
  /// Every player's counters in one community for [period], one row per player.
  ///
  /// Returns the community's whole population for that period — including
  /// players who have since left, whose records are preserved. Filtering to
  /// current members is a product decision and belongs above this layer (OP-2);
  /// the dashboard deliberately does not filter, because a departed player's
  /// goals still happened.
  ///
  /// **A bounded period returns fewer rows, and that is the data rather than a
  /// filter.** `overall` records exist for every member from the moment they
  /// join, but a weekly or monthly record exists only where the player actually
  /// played in it (`0028` §2.3). A week nobody played returns nothing at all.
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  );

  /// How many **completed** matches the community has within [period].
  ///
  /// Separate from the counters on purpose: this is a fact about matches, and
  /// the statistics table cannot answer it (see [CommunityDashboard]).
  ///
  /// **Completed as the rest of the product defines it.** A match counts when
  /// its stored status is `completed` or its end time has passed — the rule
  /// migration `0029` made authoritative and the match list already shows. The
  /// stored status alone is not the measure: nothing marks a match completed
  /// once it simply finishes, so counting on it would report zero for a
  /// community whose matches have all been played.
  ///
  /// A match falls in the period its start does, which is the same thing the
  /// database decided when it bucketed that match's counters — so this figure
  /// and the player figures beside it describe one window.
  Future<int> fetchCompletedMatches(String communityId, StatisticsPeriod period);

  /// The community's current members and the rating each holds.
  ///
  /// This is the population a leaderboard may rank. It is a separate read from
  /// the counters because the counters deliberately outlive membership — a
  /// record is preserved when a player leaves — and a board ranks people who
  /// are still here.
  ///
  /// **No period, and not by omission.** The rating is the Global Rating the
  /// player holds now (`OP-1`) and has no periodic form; so does membership,
  /// which is a fact about today rather than about a week. Both answers are the
  /// same whichever period the screen is showing.
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  );

  /// One player's records for [period], one row per community they hold one in.
  ///
  /// The rows the Player Statistics screen sums for a week or a month. It is
  /// the same table read along its other axis — the index `0028` added for
  /// exactly this ("a player's own records in a community") — rather than a new
  /// database object, and the summing is left to the repository because a total
  /// across communities is a product decision (OP-2).
  ///
  /// Not for All Time. The player's career figures have a source already, in
  /// the Result domain, and a second one built by summing these rows could
  /// disagree with it.
  ///
  /// The reader sees a community's records only while they are a member of it
  /// (`community_statistics_select_members`), so a player who has left a
  /// community no longer counts what they did there. That is `CS-D3`, accepted
  /// where the policy was written, and this port does not work around it.
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  );
}
