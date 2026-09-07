import '../../../core/failures.dart';
import '../../../features/statistics/team_of_period_models.dart';
import 'team_mapper.dart';

// Conversion between migration `0070`'s two read models and the Team of Period
// domain. Every column and JSON key those functions return appears here and
// nowhere else (OP-3).
//
// There is no `...ToRow` counterpart and there should never be one. Both
// functions are read-only projections over evidence the database owns; a
// payload built in the app could only describe a period that nobody played.
//
// **No arithmetic lives here.** The median, the shares and the slot allocation
// are the selector's, and the period boundaries are the database's. What this
// file does is read what arrived and refuse what cannot be read.

/// How the database spells a period kind.
///
/// `weekly` and `monthly` are the only two values `0070` accepts — it refuses
/// `overall` outright — and this is the one place the app knows that. The
/// domain enum carries no wire spelling of its own, exactly as
/// [StatisticsPeriodWindow] keeps `period_type` out of the statistics domain.
String teamOfPeriodKindToDb(TeamOfPeriodKind kind) => switch (kind) {
      TeamOfPeriodKind.weekly => 'weekly',
      TeamOfPeriodKind.monthly => 'monthly',
    };

/// The reverse, used to read back what the row says it is.
///
/// A value outside the two means the database and this build disagree about
/// the contract — an infrastructure fault, as an unreadable position is.
TeamOfPeriodKind teamOfPeriodKindFromDb(Object? value) => switch (value) {
      'weekly' => TeamOfPeriodKind.weekly,
      'monthly' => TeamOfPeriodKind.monthly,
      _ => throw const InfrastructureFailure(),
    };

/// The one row `community_period_xi_window` returns.
///
/// Nothing here recomputes a boundary. `period_start` and `period_end` are the
/// instants the database resolved in Asia/Muscat, and deriving them again in
/// Dart would be a second implementation of a frozen rule, free to disagree
/// with the first at exactly the week edges that are hardest to test.
TeamOfPeriodWindow teamOfPeriodWindowFromRow(Map<String, dynamic> row) =>
    TeamOfPeriodWindow(
      kind: teamOfPeriodKindFromDb(row['period_type']),
      periodKey: row['period_key'] as String,
      periodStart: _timestamp(row['period_start']),
      periodEnd: _timestamp(row['period_end']),
      qualifyingMatchCount: _count(row['qualifying_match_count']),
      requiredMatches: _count(row['required_matches']),
      // Null is the answer, not a gap: a period with no qualifying evidence
      // has no moment at which that evidence last changed.
      evidenceLastChangedAt: _optionalTimestamp(row['evidence_last_changed_at']),
      teamSizeObservations: _intArray(row['team_size_observations']),
      positionShapeObservations: [
        for (final observation in _jsonArray(row['position_shape_observations']))
          _shapeFromJson(observation),
      ],
    );

/// One row of `community_period_xi_evidence`.
///
/// The period identity is read from the row rather than taken from the window
/// beside it. `0070` repeats it on every candidate, and repeated data is only
/// worth carrying if somebody compares it — the repository does, which is how
/// a window and a candidate list read either side of a period rollover are
/// caught instead of shown.
///
/// `period_secondary_position` is nullable and stays null. It exists only when
/// the player actually played a second position in the period, so an absence
/// is the database's statement that there was none — never a gap to fill from
/// a profile.
TeamOfPeriodCandidate teamOfPeriodCandidateFromRow(Map<String, dynamic> row) {
  final secondary = row['period_secondary_position'] as String?;
  return TeamOfPeriodCandidate(
    userId: row['user_id'] as String,
    periodIdentity: TeamOfPeriodIdentity(
      kind: teamOfPeriodKindFromDb(row['period_type']),
      periodKey: row['period_key'] as String,
      periodStart: _timestamp(row['period_start']),
      periodEnd: _timestamp(row['period_end']),
      qualifyingMatchCount: _count(row['qualifying_match_count']),
      requiredMatches: _count(row['required_matches']),
    ),
    eligible: _boolean(row['eligible']),
    matchesPlayed: _count(row['matches_played']),
    participationRate: _numeric(row['participation_rate']),
    wins: _count(row['wins']),
    draws: _count(row['draws']),
    losses: _count(row['losses']),
    goals: _count(row['goals']),
    goalsPerMatch: _numeric(row['goals_per_match']),
    mvpCount: _count(row['mvp_count']),
    winRate: _numeric(row['win_rate']),
    pointsPerGame: _numeric(row['points_per_game']),
    periodFormScore: _numeric(row['period_form_score']),
    goalFormContributionTotal: _numeric(row['goal_form_contribution_total']),
    // A real candidate always has one: `0051` makes `assigned_position` a
    // CHECK constraint for any lineup row naming a user, so an absent Primary
    // is the schema disagreeing with this build rather than a player with no
    // position. Nothing is invented for them.
    periodPrimaryPosition:
        positionFromDb(row['period_primary_position'] as String),
    periodSecondaryPosition:
        secondary == null ? null : positionFromDb(secondary),
    currentOverallRating: _numeric(row['current_overall_rating']),
  );
}

/// One entry of `position_shape_observations`.
///
/// The keys are `0070`'s own, read from the migration rather than guessed:
/// `team_size`, the four upper-case position codes, and `unassigned`. The
/// `team` key each entry also carries is deliberately not read — which side of
/// which match a shape came from is not something the award needs, and the
/// function exposes no match id to pair it with anyway.
PositionShapeObservation _shapeFromJson(Map<String, dynamic> json) =>
    PositionShapeObservation(
      teamSize: _count(json['team_size']),
      gk: _count(json['GK']),
      def: _count(json['DEF']),
      mid: _count(json['MID']),
      fwd: _count(json['FWD']),
      unassigned: _count(json['unassigned']),
    );

/// A PostgreSQL `numeric`, read the way this codebase already reads one.
///
/// `numeric` reaches the client as a JSON number or as its text form depending
/// on the transport — `overall_rating` was observed arriving as the string
/// `"5.15"` — so both are accepted and anything else is refused.
///
/// Stated once, here, for all seven of the ratios and scores this file reads.
/// Casting at each site is how one of them ends up as a silent zero, and a
/// participation rate that quietly became zero would make an eligible player
/// rank last rather than fail visibly.
double _numeric(Object? value) => ratingFromDb(value);

/// An `int` column. Every one of them is `not null` in the projection, so a
/// null means the column was left out rather than that the figure is zero —
/// and reading it as zero would produce an award built on absent evidence.
int _count(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const InfrastructureFailure();
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  throw const InfrastructureFailure();
}

/// `timestamptz`, read as UTC so two of them compare by the instant rather than
/// by whatever offset the string was written in.
DateTime _timestamp(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw const InfrastructureFailure();
  return parsed.toUtc();
}

DateTime? _optionalTimestamp(Object? value) =>
    value == null ? null : _timestamp(value);

/// `int[]`, which PostgREST delivers as a JSON array.
List<int> _intArray(Object? value) {
  if (value is! List) throw const InfrastructureFailure();
  return [for (final element in value) _count(element)];
}

List<Map<String, dynamic>> _jsonArray(Object? value) {
  if (value is! List) throw const InfrastructureFailure();
  return [
    for (final element in value)
      if (element is Map<String, dynamic>)
        element
      else
        throw const InfrastructureFailure(),
  ];
}
