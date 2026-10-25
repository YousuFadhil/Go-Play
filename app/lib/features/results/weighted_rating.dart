/// Frozen corrected Global Rating v1. Database migration 0108 is the writer;
/// this arithmetic mirror is for validation. No attendance/activity factor.
enum MatchOutcome { win, draw, loss }

class RatedMatch {
  const RatedMatch(this.outcome, {this.goals = 0, this.mvp = false});
  final MatchOutcome outcome;
  final int goals;
  final bool mvp;

  double get score {
    if (goals < 0) throw ArgumentError.value(goals, 'goals');
    final (base, budget) = switch (outcome) {
      MatchOutcome.win => (8.8, 1.2),
      MatchOutcome.draw => (4.4, 0.6),
      MatchOutcome.loss => (0.0, 0.7),
    };
    return base + budget * ((2 / 3) * goals / (goals + 2) + (mvp ? 1 / 3 : 0));
  }
}

/// Matches must be ordered by start_at then match UUID, as in the database.
double weightedRating(Iterable<RatedMatch> chronologicalMatches) {
  var lifetimeNumerator = 70.0;
  var lifetimeDenominator = 14;
  var recentNumerator = 70.0;
  var recentDenominator = 14.0;
  const q = 26 / 27;
  for (final match in chronologicalMatches) {
    final score = match.score;
    lifetimeNumerator += score;
    lifetimeDenominator++;
    recentNumerator = q * recentNumerator + score;
    recentDenominator = q * recentDenominator + 1;
  }
  return (lifetimeNumerator / lifetimeDenominator +
          recentNumerator / recentDenominator) /
      2;
}

/// Existing three-decimal storage/API. H and E never use this rounded value.
double storedWeightedRating(double raw) =>
    ((raw * 1000).round() / 1000).clamp(0.0, 9.999);
