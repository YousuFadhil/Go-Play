/// Metric computation — Specification §15.
///
/// Each function here computes exactly one optimization priority. They are kept
/// separate and side-effect free so the staged search can evaluate a priority
/// without touching the ones below it — which is how `BTGE-AX-2` is enforced
/// structurally: Match History is simply not in scope until priority 5.
library;

import 'models.dart';

/// Priority 1 — how evenly the pool's position lines are split.
///
/// `BTGE-PD-3` requires each line present in the generation set to be split as
/// evenly as possible, with the surplus of an odd line carried into this
/// metric. Lines are counted by the player's **primary** position: that is the
/// player's line, independent of where they end up assigned.
double positionDistributionScore(List<Player> teamA, List<Player> teamB) {
  var score = 0.0;
  for (final p in Position.values) {
    final a = teamA.where((x) => x.primaryPosition == p).length;
    final b = teamB.where((x) => x.primaryPosition == p).length;
    score += (a - b).abs();
  }
  return score;
}

/// Priority 2 — absolute difference in mean overall rating.
///
/// Mean, not sum: with odd player counts the teams differ in size and summed
/// ratings compare unlike quantities (`KB-C5`).
double ratingDelta(List<Player> teamA, List<Player> teamB) {
  if (teamA.isEmpty || teamB.isEmpty) return 0;
  return (_mean(teamA.map((p) => p.overallRating)) -
          _mean(teamB.map((p) => p.overallRating)))
      .abs();
}

/// Priority 2, diagnostic only — never the ordering metric.
double ratingDeltaTotal(List<Player> teamA, List<Player> teamB) {
  final sumA = teamA.fold(0.0, (s, p) => s + p.overallRating);
  final sumB = teamB.fold(0.0, (s, p) => s + p.overallRating);
  return (sumA - sumB).abs();
}

/// Priority 4a — absolute difference in mean age, in completed years.
double ageDelta(List<Player> teamA, List<Player> teamB, DateTime asOf) {
  if (teamA.isEmpty || teamB.isEmpty) return 0;
  return (_mean(teamA.map((p) => p.ageAt(asOf).toDouble())) -
          _mean(teamB.map((p) => p.ageAt(asOf).toDouble())))
      .abs();
}

/// Priority 4b — difference in the count of above-median-age players.
///
/// Comparing means alone is defeatable: a team of the oldest and a team of the
/// youngest can produce nearly identical means (`KB-C8`). This catches that.
int ageSplitImbalance(
  List<Player> teamA,
  List<Player> teamB,
  DateTime asOf,
) {
  final all = [...teamA, ...teamB];
  if (all.isEmpty) return 0;
  final ages = all.map((p) => p.ageAt(asOf)).toList()..sort();
  final median = ages[ages.length ~/ 2];
  final aboveA = teamA.where((p) => p.ageAt(asOf) > median).length;
  final aboveB = teamB.where((p) => p.ageAt(asOf) > median).length;
  return (aboveA - aboveB).abs();
}

/// Priority 5 — teammate pairs repeated from the lookback window.
///
/// [pairsInWindow] is supplied by the caller from [MatchHistory], already
/// scoped by `OP-6`. When it is empty — a first match, a new community, an
/// unset window — this returns zero for every candidate, so Diversity
/// contributes nothing and the tie falls through to canonical ordering. That is
/// `BTGE-DV-5`, and it is never an error.
int repeatPairCount(
  List<Player> teamA,
  List<Player> teamB,
  Set<String> pairsInWindow,
) {
  if (pairsInWindow.isEmpty) return 0;
  var repeats = 0;
  for (final team in [teamA, teamB]) {
    final ids = team.map((p) => p.id).toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        if (pairsInWindow.contains('${ids[i]}|${ids[j]}')) repeats++;
      }
    }
  }
  return repeats;
}

double _mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final v in values) {
    sum += v;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}
