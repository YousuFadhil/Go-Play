/// One player's counters inside one community.
///
/// This is a `community_statistics` row (migration `0028`) with the player's
/// name attached. Every counter here is a consequence of a recorded result and
/// nothing else — no screen writes one, and there is no port that could.
///
/// **The period is not a field.** The table keys every record by
/// `(community, period_type, period_key, player)` and holds three periods per
/// player: `overall`, the week, and the month. The MVP dashboard reads only
/// `overall`, so every instance the app holds today describes the same period —
/// and a field that always carries one value invites code that branches on it
/// as though it might carry another. When a weekly or monthly view is built, the
/// period arrives here with a reader that needs it.
class CommunityPlayerStatistics {
  const CommunityPlayerStatistics({
    required this.userId,
    required this.fullName,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.goals,
    required this.mvpCount,
  });

  final String userId;

  /// Null when the player's profile is not visible to the reader — a
  /// soft-deleted account, which the `users` policy hides while its statistics
  /// rows survive. The counters still count: they describe what happened, and
  /// the community's history does not change because someone left.
  final String? fullName;

  /// Matches whose result was recorded and whose lineup included this player.
  /// Not registrations, not reserves, and not matches still awaiting a result.
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int goals;
  final int mvpCount;
}

/// A current member of a community, with the rating they hold.
///
/// Read from `v_community_members`, which inner-joins the roster to the
/// profiles — so it is both the ratings and the **eligibility list**: exactly
/// the people a board may rank, and nobody who has left.
class CommunityMemberRating {
  const CommunityMemberRating({
    required this.userId,
    required this.fullName,
    required this.rating,
  });

  final String userId;
  final String fullName;

  /// The **Global** Rating (`users.overall_rating`) — the player's rating
  /// across every community, not a per-community one. The Community Rating is
  /// a separate entity that is not built, so this is the only rating there is
  /// to rank by.
  final double rating;
}

/// Which measure a board ranks. The five the MVP shows, and no others.
enum LeaderboardKind {
  highestRated,
  topScorer,
  mostMvp,
  mostActive,
  mostWins;

  /// True where the measure is a rating rather than a count, which is the only
  /// thing that differs about how a row is presented.
  bool get isRating => this == LeaderboardKind.highestRated;
}

/// One row of a board: who, where they placed, and on what.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.fullName,
    required this.rank,
    required this.value,
  });

  final String userId;
  final String fullName;

  /// Competition ranking: equal values share a rank, and the next distinct
  /// value takes the place its position implies. Three players tied at the top
  /// are all rank 1, and the next is rank 4.
  final int rank;

  /// `double` for a rating, `int` for a count. The screen formats it by kind.
  final num value;
}

/// One board: a measure, and the top three who lead it.
class Leaderboard {
  const Leaderboard({required this.kind, required this.entries});

  final LeaderboardKind kind;

  /// At most three, best first. Never empty — a board with nothing to say is
  /// not built at all.
  final List<LeaderboardEntry> entries;
}

/// Who leads one measure in a community, and by how much.
///
/// A leader exists only where the measure has actually happened — see
/// [CommunityDashboard]. `null` is how "nobody has scored yet" is carried, so
/// no screen has to decide whether a zero is a leader.
class StatisticLeader {
  const StatisticLeader({
    required this.userId,
    required this.fullName,
    required this.value,
  });

  final String userId;
  final String? fullName;
  final int value;
}

/// Every figure the Community Dashboard shows.
///
/// The six figures come from two places, and the split is not incidental —
/// it is the one recorded in the Community Statistics specification (§19.2):
///
/// * [completedMatches] is a fact about **matches**, and is read from the Match
///   domain. It cannot come from the statistics counters, because summing
///   `matches_played` counts player-appearances: ten players in one match sum
///   to ten.
/// * everything else is a fact about **players**, and comes from
///   `community_statistics`.
///
/// **Nothing here counts a match that is not officially completed.**
/// Statistics describe a community's settled history, and a match still open or
/// full is not history yet — it can be edited, filled, emptied or deleted. Nor
/// is one whose end time has passed without the status being moved: it is
/// awaiting its result, and counting it would make the dashboard move for
/// reasons that are not results.
///
/// The two sources still answer slightly different questions, which is why
/// [completedMatches] can exceed what the player figures appear to account for:
/// a played match with no recorded result is a match the community played host
/// to and a match no counter knows about.
class CommunityDashboard {
  const CommunityDashboard({
    required this.completedMatches,
    required this.totalPlayers,
    required this.totalGoals,
    required this.topScorer,
    required this.mostActivePlayer,
    required this.mostMvp,
  });

  /// Matches whose official status is completed. Open and full matches are
  /// excluded, and so is a match that has merely run past its end time without
  /// being marked completed.
  final int completedMatches;

  /// Everyone who holds a record in this community. A record is created when a
  /// player first joins and is preserved when they leave, so this counts the
  /// community's history rather than its current roster.
  final int totalPlayers;

  final int totalGoals;

  /// Null until somebody has actually scored / played / been named MVP.
  final StatisticLeader? topScorer;
  final StatisticLeader? mostActivePlayer;
  final StatisticLeader? mostMvp;
}
