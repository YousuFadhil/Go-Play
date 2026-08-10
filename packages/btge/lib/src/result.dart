/// Engine outputs — Specification §5 and §15.
library;

import 'models.dart';

/// One player's assignment. Specification §5.1.
class PlayerAssignment {
  const PlayerAssignment({
    required this.playerId,
    required this.team,
    required this.assignedPosition,
    required this.basis,
  });

  final String playerId;
  final TeamId team;
  final Position assignedPosition;
  final AssignmentBasis basis;

  /// True exactly when [basis] is `transition` (§5.1, `BTGE-PT-2`).
  bool get outOfPosition => basis == AssignmentBasis.transition;

  @override
  String toString() => '$playerId → ${team.name.toUpperCase()} '
      '${assignedPosition.code} (${basis.name})';
}

/// Metrics that map to an optimization priority. Specification §15.
///
/// These are **internal** (§5.2). Surfacing any of them in a user interface is
/// a separate product decision and is not authorized by the Specification.
class QualityMetrics {
  const QualityMetrics({
    required this.positionDistributionScore,
    required this.ratingDelta,
    required this.ratingDeltaTotal,
    required this.outOfPositionCount,
    required this.outOfPositionCost,
    required this.outOfPositionImbalance,
    required this.ageDelta,
    required this.ageSplitImbalance,
    required this.repeatPairCount,
  });

  /// Priority 1. Aggregate deviation from an even split of the pool's position
  /// lines. Lower is better.
  final double positionDistributionScore;

  /// Priority 2. Absolute difference in **mean** overall rating. Mean holds
  /// under unequal team sizes (`KB-C5`). Lower is better.
  final double ratingDelta;

  /// Priority 2, diagnostic only — not the ordering metric.
  final double ratingDeltaTotal;

  /// Priority 3. Number of players assigned by `TRANSITION`.
  final int outOfPositionCount;

  /// Priority 3. Sum of transition costs, weighted per `OP-4`.
  final double outOfPositionCost;

  /// Priority 3. Difference in out-of-position counts between the two teams
  /// (`BTGE-PT-3`) — four on one side is worse than two per side.
  final int outOfPositionImbalance;

  /// Priority 4. Absolute difference in mean age in years, from Date of Birth
  /// as of the match date.
  final double ageDelta;

  /// Priority 4. Difference in the count of above-median-age players
  /// (`BTGE-SC-5`). Guards against stacking the old on one side and the young
  /// on the other while the means happen to match.
  ///
  /// Reported as a raw number. There is deliberately no "wide spread" boolean:
  /// `OP-7` is an Implementation Detail and a threshold would carry strictly
  /// less information than this number.
  final int ageSplitImbalance;

  /// Priority 5. Teammate pairs in this result that also appeared together
  /// inside the lookback window. Zero when Match History is unavailable, which
  /// is the approved `BTGE-DV-5` path and not an error.
  final int repeatPairCount;

  @override
  String toString() => 'QualityMetrics(dist: $positionDistributionScore, '
      'rating: ${ratingDelta.toStringAsFixed(3)}, oop: $outOfPositionCount'
      '/${outOfPositionCost.toStringAsFixed(0)}/±$outOfPositionImbalance, '
      'age: ${ageDelta.toStringAsFixed(2)}/±$ageSplitImbalance, '
      'repeats: $repeatPairCount)';
}

/// Solver diagnostics. Specification §15, the rows with no priority.
class Diagnostics {
  const Diagnostics({
    required this.goalkeeperMode,
    required this.emergencyGoalkeeperCount,
    required this.solutionCountAtOptimum,
    required this.equallyOptimalSolutions,
    required this.variantIndex,
    required this.candidatesEvaluated,
    required this.searchWasExhaustive,
    required this.elapsedMs,
  });

  /// Which branch of §10 applied, counting natural goalkeepers.
  final GoalkeeperMode goalkeeperMode;

  /// How many goalkeepers were assigned as emergency rather than natural
  /// (`BTGE-GK-2`).
  final int emergencyGoalkeeperCount;

  /// How many solutions were tied at the optimum before diversity broke the
  /// tie. Diagnostic for whether the `OP-3` bands are usefully sized.
  final int solutionCountAtOptimum;

  /// How many partitions survived **every** priority, diversity included, and
  /// are therefore equally optimal by the whole of §7.
  ///
  /// This is the size of the set [BtgeEngine.generate]'s `variant` selects from:
  /// one means the search has a single answer and asking again cannot produce
  /// another, more means a regeneration has somewhere else to go.
  final int equallyOptimalSolutions;

  /// Which member of that set was returned, after the requested variant was
  /// wrapped into range. Always 0 when the caller asked for no variant.
  final int variantIndex;

  /// Partitions scored.
  final int candidatesEvaluated;

  /// True when every partition was scored, so the result is provably optimal
  /// (`BTGE-PF-4`). The engine never returns a result with this false.
  final bool searchWasExhaustive;

  /// A result is reproduced from its inputs alone — there is no seed
  /// (`BTGE-PF-6`).
  final int elapsedMs;

  @override
  String toString() => 'Diagnostics(gk: ${goalkeeperMode.name}, '
      'emergencyGk: $emergencyGoalkeeperCount, '
      'tiedAtOptimum: $solutionCountAtOptimum, '
      'equallyOptimal: $equallyOptimalSolutions, variant: $variantIndex, '
      'evaluated: $candidatesEvaluated, exhaustive: $searchWasExhaustive, '
      '${elapsedMs}ms)';
}

/// The engine's output. Specification §5.
class GenerationResult {
  GenerationResult({
    required Iterable<PlayerAssignment> assignments,
    required this.metrics,
    required this.diagnostics,
  }) : assignments = List.unmodifiable(assignments);

  final List<PlayerAssignment> assignments;
  final QualityMetrics metrics;
  final Diagnostics diagnostics;

  List<PlayerAssignment> teamOf(TeamId team) =>
      assignments.where((a) => a.team == team).toList();

  Iterable<PlayerAssignment> get outOfPositionPlayers =>
      assignments.where((a) => a.outOfPosition);

  @override
  String toString() {
    final buffer = StringBuffer();
    for (final team in TeamId.values) {
      buffer.writeln('Team ${team.name.toUpperCase()}:');
      for (final a in teamOf(team)) {
        buffer.writeln('  $a');
      }
    }
    buffer
      ..writeln(metrics)
      ..writeln(diagnostics);
    return buffer.toString();
  }
}
