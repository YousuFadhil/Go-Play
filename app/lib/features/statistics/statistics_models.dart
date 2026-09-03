/// One player's counters inside one community.
///
/// This is a `community_statistics` row (migration `0028`) with the player's
/// name attached. Every counter here is a consequence of a recorded result and
/// nothing else — no screen writes one, and there is no port that could.
///
/// **The period is still not a field, and now for a sharper reason.** The table
/// keys every record by `(community, period_type, period_key, player)` and holds
/// three periods per player: `overall`, the week, and the month. Every read that
/// produces these fixes exactly one of them — a [StatisticsPeriod] goes into the
/// port and one period's rows come back — so a period carried on the row would
/// restate the question the caller already asked, and a list could never hold
/// two of them anyway. What changed in this cycle is which period a caller may
/// ask for, not how many arrive at once.
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
    this.avatarUrl,
  });

  final String userId;

  /// Null when the player's profile is not visible to the reader — a
  /// soft-deleted account, which the `users` policy hides while its statistics
  /// rows survive. The counters still count: they describe what happened, and
  /// the community's history does not change because someone left.
  final String? fullName;

  /// The player's picture, from the same embed the name comes through. Null
  /// where the name is null, for the same reason: there is no profile to read
  /// either from.
  final String? avatarUrl;

  /// Matches whose result was recorded and whose lineup included this player.
  /// Not registrations, not reserves, and not matches still awaiting a result.
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int goals;
  final int mvpCount;
}

/// One player's six counters over one bounded period, summed across every
/// community they play in.
///
/// **Six figures, not seven.** There is no rating here, and there must not be:
/// the Global Rating is a value the player holds now, not a thing that happened
/// during a week, and `OP-1` gives it no periodic form. The Player Statistics
/// screen shows the rating it has always shown alongside these and says which
/// of the two the period applies to.
///
/// Built by [StatisticsRepository] from the player's `community_statistics`
/// records for the period. A period record exists only where the player
/// actually played (`0028` §2.3), so a player with no records in the period has
/// [none] — genuinely zero, rather than missing.
class PlayerPeriodStatistics {
  const PlayerPeriodStatistics({
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.goals,
    required this.mvpCount,
  });

  /// A period the player did not play in. Every figure is zero because nothing
  /// happened, which is an answer and not an absence.
  const PlayerPeriodStatistics.none()
      : matchesPlayed = 0,
        wins = 0,
        losses = 0,
        draws = 0,
        goals = 0,
        mvpCount = 0;

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
    this.avatarUrl,
  });

  final String userId;
  final String fullName;

  /// The member's picture, looked up alongside the view read: the view carries
  /// the roster and the rating but not `avatar_path`.
  final String? avatarUrl;

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
    this.avatarUrl,
  });

  final String userId;
  final String fullName;

  /// The player's picture. Carried on the entry so a board row is a player
  /// identity like any other — avatar, name, and a way into the profile.
  final String? avatarUrl;

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
    this.avatarUrl,
  });

  final String userId;

  /// Null for a record that outlived the profile it describes — a soft-deleted
  /// account whose figures stayed. The measure is still true and is still
  /// shown; there is simply nobody left to name, or to open.
  final String? fullName;

  final int value;
  final String? avatarUrl;
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

/// When a player last did each of the things the boards rank.
///
/// The evidence behind tie-breaking, and nothing else: it never changes what a
/// player's value *is*, only which of two equal players is shown first.
///
/// Every field is `matches.start_at` — when the football happened, not when the
/// row was written. Recording last season's match today must not make it a more
/// recent achievement than yesterday's.
///
/// **Null means the measure has never happened to this player**, which sorts
/// after every real timestamp. A player with no goals has no last goal; a
/// player still on the opening 5.00 with no effective rating event has no
/// rating recency. Absence is not a very old date and is not treated as one.
///
/// [lastRatingAt] is global and periodless, because the rating it breaks ties
/// for is: Highest Rated shows the Global Rating in every period. The other
/// four describe the same period as the counter they order.
class PlayerAchievementRecency {
  const PlayerAchievementRecency({
    this.lastGoalAt,
    this.lastMvpAt,
    this.lastPlayedAt,
    this.lastWinAt,
    this.lastRatingAt,
  });

  /// A player nothing is known about. Every measure sorts last.
  static const none = PlayerAchievementRecency();

  final DateTime? lastGoalAt;
  final DateTime? lastMvpAt;
  final DateTime? lastPlayedAt;
  final DateTime? lastWinAt;
  final DateTime? lastRatingAt;

  /// The timestamp that breaks a tie on [kind].
  ///
  /// One place mapping measures to their evidence, so a board and a dashboard
  /// leader asking about the same measure cannot consult different fields.
  DateTime? forKind(LeaderboardKind kind) => switch (kind) {
        LeaderboardKind.topScorer => lastGoalAt,
        LeaderboardKind.mostMvp => lastMvpAt,
        LeaderboardKind.mostActive => lastPlayedAt,
        LeaderboardKind.mostWins => lastWinAt,
        LeaderboardKind.highestRated => lastRatingAt,
      };
}

/// Everything the Statistics tab shows for one community over one period.
///
/// **One snapshot, because there is one period.** The Dashboard and the
/// Leaderboards used to be two tabs, each with its own selector and its own
/// load, and a reader could leave one on the month and the other on the week.
/// They are one tab now, so the figures and the boards describe the same
/// stretch of time by construction rather than by the reader remembering to set
/// both — and the share card is made of this object, so a picture cannot
/// disagree with the screen it was taken from either.
///
/// The two halves are still the two models they were. Nothing was merged into a
/// new shape: [dashboard] is what `fetchDashboard` builds and [boards] is what
/// `fetchLeaderboards` builds, assembled from one set of reads instead of two.
class CommunityStatistics {
  const CommunityStatistics({required this.dashboard, required this.boards});

  /// The three community totals, and the three leaders the old Dashboard drew.
  ///
  /// Only the totals reach the screen now — the leader highlights were the same
  /// three players the boards below them already name, and saying it twice was
  /// the duplication this tab exists to end. They are still built because the
  /// share card names five leaders and two of them, Highest Rated and Most
  /// Wins, come from the boards; the other three are cheaper read from here
  /// than re-derived.
  final CommunityDashboard dashboard;

  /// The five boards, in the repository's order, exactly as the Leaderboards
  /// tab received them. A measure nobody has achieved yet produces no board,
  /// so this can be shorter than five and can be empty.
  final List<Leaderboard> boards;

  /// The board for [kind], or null where the measure has not happened yet.
  ///
  /// The one place that looks a board up by measure, so the tab and the share
  /// card cannot answer "who leads this" differently.
  Leaderboard? boardFor(LeaderboardKind kind) {
    for (final board in boards) {
      if (board.kind == kind) return board;
    }
    return null;
  }

  /// Whoever is first on [kind]'s board, or null where there is no board.
  ///
  /// First place only. This is what the share card carries: the runner-ups are
  /// on the screen, where somebody is reading, and off the card, which somebody
  /// is glancing at in a group chat.
  LeaderboardEntry? leaderOf(LeaderboardKind kind) {
    final entries = boardFor(kind)?.entries;
    return (entries == null || entries.isEmpty) ? null : entries.first;
  }

  /// Whether any measure has a leader at all.
  bool get hasLeaders => boards.any((board) => board.entries.isNotEmpty);
}
