import 'package:btge/btge.dart';

/// Which completed period a Team of Period award describes.
///
/// **Not [StatisticsPeriod], and deliberately not.** That enum names the period
/// a screen is *currently* showing — this week, this month, all time — and its
/// weekly value means the week now running. An award is always about a period
/// that has finished: migration `0070` resolves the last completed ISO week or
/// calendar month itself and refuses to be handed a timestamp. Reusing the
/// statistics enum would have let a caller ask for an award for `allTime`, or
/// read "weekly" as "so far this week", and both are questions this feature
/// does not have an answer to.
///
/// There is no `allTime` here for the same reason: an all-time XI is not a
/// period, and the read model has no such window.
enum TeamOfPeriodKind {
  /// The last completed ISO week, in Asia/Muscat.
  weekly,

  /// The last completed calendar month, in Asia/Muscat.
  monthly,
}

/// One actual played side of one qualifying match.
///
/// The unit of positional evidence, and the reason it is a *side* rather than a
/// player row: a match played eleven-a-side writes twenty-two lineup rows and a
/// five-a-side writes ten, so counting rows would let one big fixture outvote a
/// month of small-sided ones. Each side observed is one observation, whatever
/// its size (§7.1).
///
/// [unassigned] is a participant who played with no recorded position — a
/// Professional Guest an organizer never placed. They are part of how big the
/// side was and contribute nothing to what shape it had, because inventing a
/// position for them would be guessing at football that nobody recorded.
class PositionShapeObservation {
  const PositionShapeObservation({
    required this.teamSize,
    required this.gk,
    required this.def,
    required this.mid,
    required this.fwd,
    required this.unassigned,
  });

  final int teamSize;
  final int gk;
  final int def;
  final int mid;
  final int fwd;
  final int unassigned;

  /// How many of this side's players had a recorded position.
  int get known => gk + def + mid + fwd;

  /// Whether this side says anything about shape.
  ///
  /// A side of nothing but unpositioned guests is a real side — it counts
  /// toward the squad size — and it is silent about roles. It is skipped when
  /// the shares are averaged rather than counted as a side of zero defenders.
  bool get hasKnownPositions => known > 0;

  /// This side's share of [position] among the players whose position is known.
  ///
  /// Only meaningful when [hasKnownPositions]; the selector never asks
  /// otherwise.
  double shareOf(Position position) => switch (position) {
        Position.gk => gk / known,
        Position.def => def / known,
        Position.mid => mid / known,
        Position.fwd => fwd / known,
      };
}

/// The period an award describes, and the community's football inside it.
///
/// The `community_period_xi_window` row of migration `0070`, as a domain value.
/// It exists even when nobody played: a week with no qualifying matches is
/// still a week the screen has to be able to name, which is why the period
/// identity lives here and not on a candidate row that would not exist.
class TeamOfPeriodWindow {
  const TeamOfPeriodWindow({
    required this.kind,
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    required this.qualifyingMatchCount,
    required this.requiredMatches,
    required this.evidenceLastChangedAt,
    required this.teamSizeObservations,
    required this.positionShapeObservations,
  });

  final TeamOfPeriodKind kind;

  /// `2026-W31` or `2026-08`, as the database bucketed it.
  final String periodKey;

  /// Half-open: `[periodStart, periodEnd)`.
  final DateTime periodStart;
  final DateTime periodEnd;

  final int qualifyingMatchCount;

  /// How many of those matches a candidate had to play. One for a week; half
  /// the month rounded up. Zero when the period held no football at all.
  final int requiredMatches;

  /// When the evidence inside this period last changed, or null when there is
  /// none. Carried for auditing and for a later cache to invalidate against; the
  /// selector does not read it.
  final DateTime? evidenceLastChangedAt;

  /// One entry per played side, guests included, because they played.
  final List<int> teamSizeObservations;

  /// The same sides, with their positional make-up.
  final List<PositionShapeObservation> positionShapeObservations;
}

/// One real player's evidence for the period.
///
/// The `community_period_xi_evidence` row of migration `0070`, whole. More than
/// the selector reads, deliberately: Cycle 3 maps this and Cycle 4 shows it, and
/// a second model carrying "the bits the pitch needs" would be a second place
/// for the same period to be described slightly differently.
///
/// **[currentOverallRating] is presentation evidence and the selector must not
/// read it.** It is the player's live global rating, so a match played next
/// month would move it — and an award for a week that has closed cannot be
/// allowed to change because of football played after it ended. The pitch may
/// display it; the ranking may not consider it.
///
/// The two period positions are authoritative and come from the lineup rows of
/// this period. The selector never reads a profile's primary or secondary
/// position: those are today's answer to a question about a week that is over.
class TeamOfPeriodCandidate {
  const TeamOfPeriodCandidate({
    required this.userId,
    required this.eligible,
    required this.matchesPlayed,
    required this.participationRate,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goals,
    required this.goalsPerMatch,
    required this.mvpCount,
    required this.winRate,
    required this.pointsPerGame,
    required this.periodFormScore,
    required this.goalFormContributionTotal,
    required this.periodPrimaryPosition,
    this.periodSecondaryPosition,
    required this.currentOverallRating,
  });

  final String userId;

  /// Whether they played enough of the period to be selectable. The threshold
  /// is the database's and is not relaxed here for any reason.
  final bool eligible;

  final int matchesPlayed;
  final double participationRate;

  final int wins;
  final int draws;
  final int losses;

  final int goals;
  final double goalsPerMatch;

  final int mvpCount;
  final double winRate;
  final double pointsPerGame;

  /// Period Form Score v1, the average per-match contribution.
  final double periodFormScore;

  /// The capped goal contribution summed across the period — the same cap the
  /// form score is built from, never the raw goal count.
  final double goalFormContributionTotal;

  /// Where they actually played most in this period.
  final Position periodPrimaryPosition;

  /// The second position they actually played, or null when they only ever
  /// played one. Never manufactured from a profile.
  final Position? periodSecondaryPosition;

  /// Presentation only. See the class comment.
  final double currentOverallRating;
}

/// One player in the awarded team, and where they were awarded.
class TeamOfPeriodSelection {
  const TeamOfPeriodSelection({
    required this.candidate,
    required this.assignedPosition,
  });

  final TeamOfPeriodCandidate candidate;

  /// The role this player occupies in the award. Always a position they
  /// actually played in the period — their Period Primary, or their Period
  /// Secondary where that role ran short of Primaries.
  final Position assignedPosition;

  String get userId => candidate.userId;
}

/// What the selector concluded.
enum TeamOfPeriodState {
  /// A team was chosen. It may hold fewer players than the target size; that is
  /// the community's football, not an error.
  selected,

  /// The period held no qualifying match. There is no size and no shape to
  /// derive, and no team.
  noQualifyingMatches,

  /// Matches were played, and nobody met the participation threshold. The
  /// threshold is not relaxed to produce a team.
  insufficientEligiblePlayers,
}

/// The award, as the selector computed it.
class TeamOfPeriod {
  const TeamOfPeriod({
    required this.window,
    required this.state,
    required this.targetSize,
    required this.initialSlotCounts,
    required this.finalSlotCounts,
    required this.selected,
  });

  final TeamOfPeriodWindow window;
  final TeamOfPeriodState state;

  /// The median actual side size, capped at eleven. Zero when there was no
  /// football to take a median of.
  final int targetSize;

  /// The shape the period's football implied, before candidates were consulted.
  /// Kept for diagnostics: it is what a shortage is a shortage *against*.
  final Map<Position, int> initialSlotCounts;

  /// The shape actually awarded, after shortages released seats and
  /// reallocation attached them to roles with real remaining candidates.
  final Map<Position, int> finalSlotCounts;

  /// GK, DEF, MID, FWD, and within each role the approved candidate ranking —
  /// never the order the phases happened to pick people in.
  final List<TeamOfPeriodSelection> selected;

  TeamOfPeriodKind get kind => window.kind;
  String get periodKey => window.periodKey;
}
