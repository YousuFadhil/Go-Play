/// The engine facade and its search.
///
/// The search is **exact**. It enumerates every valid partition and evaluates
/// the five priorities in strict lexicographic order with tolerance bands
/// (§7.1). `BTGE-PF-4` forbids returning a good-enough result when a better one
/// exists, so there is no time budget, no early exit, and no heuristic — and
/// `BTGE-PF-6` forbids randomness, so there is no seed anywhere in this file.
library;

import 'assignment.dart';
import 'configuration.dart';
import 'distribution.dart';
import 'errors.dart';
import 'models.dart';
import 'result.dart';
import 'scoring.dart';

/// Upper bound on players. `BTGE-PF-1`, `BTGE-PF-2`.
const int maxSupportedPlayers = 30;

/// Guard against a tolerance band so wide that survivors exhaust memory.
///
/// Exceeding it throws. It never silently truncates the candidate set, because
/// truncation would quietly turn the exact search into a heuristic and breach
/// `BTGE-PF-4`.
const int candidateRetentionLimit = 2000000;

class BtgeEngine {
  const BtgeEngine(this.config);

  final BtgeConfiguration config;

  /// Generates the two teams.
  ///
  /// [variant] chooses **which** of the equally optimal solutions to return. The
  /// search settles on a set of partitions that every priority rates the same,
  /// and until now the first of them in canonical order was always the answer —
  /// so asking again for the same match returned the same teams even where the
  /// engine itself saw no reason to prefer them. `variant` indexes that set
  /// (wrapping, so any integer is valid), which is what lets a regeneration
  /// offer a genuinely different but equally good split.
  ///
  /// This is **not** randomness. `BTGE-PF-6` still holds: the survivor set is
  /// canonically ordered and the same inputs with the same `variant` produce the
  /// same result, every time, with no seed anywhere. The default of 0 is exactly
  /// the behaviour that came before.
  ///
  /// [Diagnostics.equallyOptimalSolutions] reports how large that set was, so a
  /// caller can tell "there is another answer" from "this is the only one".
  GenerationResult generate({
    required List<Player> players,
    required MatchSettings settings,
    MatchHistory history = const MatchHistory.empty(),
    int variant = 0,
  }) {
    final stopwatch = Stopwatch()..start();
    _validate(players);

    // Canonical input order. Everything downstream is a function of this list,
    // so the caller's collection order cannot affect the result (`BTGE-PF-8`).
    final pool = [...players]..sort((a, b) => a.id.compareTo(b.id));
    final n = pool.length;

    // `BTGE-HC-4`: equal sizes, or differing by exactly one when odd. Team A is
    // the larger side whenever they differ, which makes the labels a pure
    // function of the partition.
    final sizeA = (n + 1) ~/ 2;
    final sizeB = n ~/ 2;
    final isEven = sizeA == sizeB;

    final targets = deriveTargets(
      players: pool,
      sizeA: sizeA,
      sizeB: sizeB,
      config: config,
    );
    if (targets.isEmpty) {
      throw StateError('No valid target distribution for $n players');
    }

    final primaryMasks = {
      for (final p in Position.values)
        p: _maskWhere(pool, (player) => player.primaryPosition == p),
    };

    // Priorities 1 and 2 are the only stages that see the whole search space,
    // so they are streamed: each is a pass that keeps a threshold, never a list.
    // Nothing is materialised until the candidate set has been narrowed twice,
    // which is what keeps memory bounded at full capacity (`BTGE-PF-1`).

    // ---- Priority 1: position distribution -------------------------------
    var bestDistribution = double.infinity;
    var evaluated = 0;
    _forEachPartition(n, sizeA, isEven, (mask) {
      if (!_satisfiesOddCountRule(mask, pool, sizeA, sizeB)) return;
      evaluated++;
      final score = _distributionScore(mask, primaryMasks, n);
      if (score < bestDistribution) bestDistribution = score;
    });
    if (evaluated == 0) {
      throw StateError('No partition satisfied the odd-count rule');
    }

    bool admittedByDistribution(int mask) =>
        _satisfiesOddCountRule(mask, pool, sizeA, sizeB) &&
        config.distributionBand.admits(
          _distributionScore(mask, primaryMasks, n),
          bestDistribution,
        );

    // ---- Priority 2: rating balance --------------------------------------
    var bestRating = double.infinity;
    _forEachPartition(n, sizeA, isEven, (mask) {
      if (!admittedByDistribution(mask)) return;
      final (a, b) = _split(mask, pool);
      final delta = ratingDelta(a, b);
      if (delta < bestRating) bestRating = delta;
    });

    var survivors = <int>[];
    _forEachPartition(n, sizeA, isEven, (mask) {
      if (!admittedByDistribution(mask)) return;
      final (a, b) = _split(mask, pool);
      if (!config.ratingBand.admits(ratingDelta(a, b), bestRating)) return;
      if (survivors.length >= candidateRetentionLimit) {
        throw StateError(
          'Tolerance bands on priorities 1 and 2 retained more than '
          '$candidateRetentionLimit candidates. Narrow OP-3 rather than '
          'truncating: truncation would breach BTGE-PF-4.',
        );
      }
      survivors.add(mask);
    });

    // ---- Priority 3: minimise out-of-position ----------------------------
    final plans = <int, _CandidatePlan>{};
    for (final mask in survivors) {
      final (a, b) = _split(mask, pool);
      plans[mask] = _bestPlan(a, b, targets);
    }
    survivors = _filter(
      survivors,
      (mask) => plans[mask]!.transitionDistanceCost,
      config.outOfPositionBand,
    );
    // `BTGE-PT-3`'s second clause: spread what remains as evenly as possible.
    survivors = _filterExact(
      survivors,
      (mask) => plans[mask]!.outOfPositionImbalance.toDouble(),
    );

    // ---- Priority 4: age balance -----------------------------------------
    survivors = _filter(
      survivors,
      (mask) {
        final (a, b) = _split(mask, pool);
        return ageDelta(a, b, settings.matchDate);
      },
      config.ageBand,
    );
    survivors = _filterExact(
      survivors,
      (mask) {
        final (a, b) = _split(mask, pool);
        return ageSplitImbalance(a, b, settings.matchDate).toDouble();
      },
    );

    final tiedAtOptimum = survivors.length;

    // ---- Priority 5: social diversity ------------------------------------
    // Match History enters here and nowhere else (`BTGE-AX-1`, `BTGE-AX-3`).
    final pairs = history.pairsInWindow(
      asOf: settings.matchDate,
      lastNMatches: config.diversityLastNMatches,
      within: config.diversityWithin,
    );
    survivors = _filterExact(
      survivors,
      (mask) {
        final (a, b) = _split(mask, pool);
        return repeatPairCount(a, b, pairs).toDouble();
      },
    );

    // ---- Deterministic canonical ordering (`BTGE-PF-7`) -------------------
    // The order is what makes `variant` an index rather than a lottery: the same
    // inputs produce the same list, so the same variant produces the same teams.
    survivors.sort((x, y) => _canonicalKey(x, pool).compareTo(_canonicalKey(y, pool)));
    // Dart's `%` on a negative left operand still returns a non-negative result,
    // so a caller counting backwards lands inside the set rather than off it.
    final variantIndex = survivors.length == 1 ? 0 : variant % survivors.length;
    final winner = survivors[variantIndex];

    final (teamA, teamB) = _split(winner, pool);
    final plan = plans[winner]!;
    final naturalGoalkeepers = pool.where((p) => p.isNaturalGoalkeeper).length;

    stopwatch.stop();
    return GenerationResult(
      assignments: [...plan.a.assignments, ...plan.b.assignments],
      metrics: QualityMetrics(
        positionDistributionScore: positionDistributionScore(teamA, teamB),
        ratingDelta: ratingDelta(teamA, teamB),
        ratingDeltaTotal: ratingDeltaTotal(teamA, teamB),
        outOfPositionCount: plan.outOfPositionCount,
        outOfPositionCost: plan.transitionDistanceCost,
        outOfPositionImbalance: plan.outOfPositionImbalance,
        ageDelta: ageDelta(teamA, teamB, settings.matchDate),
        ageSplitImbalance: ageSplitImbalance(teamA, teamB, settings.matchDate),
        repeatPairCount: repeatPairCount(teamA, teamB, pairs),
      ),
      diagnostics: Diagnostics(
        goalkeeperMode: switch (naturalGoalkeepers) {
          0 => GoalkeeperMode.none,
          1 => GoalkeeperMode.single,
          2 => GoalkeeperMode.even,
          _ => GoalkeeperMode.surplus,
        },
        emergencyGoalkeeperCount:
            plan.a.emergencyGoalkeepers + plan.b.emergencyGoalkeepers,
        solutionCountAtOptimum: tiedAtOptimum,
        equallyOptimalSolutions: survivors.length,
        variantIndex: variantIndex,
        candidatesEvaluated: evaluated,
        searchWasExhaustive: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  void _validate(List<Player> players) {
    if (players.length < config.minPlayers) {
      throw BtgeInputError(
        BtgeErrorCode.tooFewPlayers,
        '${players.length} players is below the configured minimum '
        '${config.minPlayers} (OP-2).',
      );
    }
    if (players.length > maxSupportedPlayers) {
      throw BtgeInputError(
        BtgeErrorCode.tooManyPlayers,
        '${players.length} players exceeds the supported maximum '
        '$maxSupportedPlayers (BTGE-PF-1).',
      );
    }
    final seen = <String>{};
    for (final player in players) {
      if (!seen.add(player.id)) {
        throw BtgeInputError(
          BtgeErrorCode.duplicatePlayerId,
          'Player id "${player.id}" appears more than once.',
        );
      }
      if (player.id.isEmpty) {
        throw const BtgeInputError(
          BtgeErrorCode.missingRequiredInput,
          'Player id is empty.',
        );
      }
      if (player.overallRating.isNaN || player.overallRating.isInfinite) {
        throw BtgeInputError(
          BtgeErrorCode.missingRequiredInput,
          'Player "${player.id}" has no usable overall rating. The engine '
          'never substitutes a default (§4.3).',
        );
      }
    }
  }

  /// `OP-5`. With [OddCountRule.weakerTeamGetsExtra], the larger team must not
  /// also be the stronger one — `KB-012` requires the numerical advantage to be
  /// compensated, and this is the compensation as currently specified.
  bool _satisfiesOddCountRule(int mask, List<Player> pool, int sizeA, int sizeB) {
    if (sizeA == sizeB) return true;
    if (config.oddCountRule == OddCountRule.bestFinalBalance) return true;
    final (a, b) = _split(mask, pool);
    return _mean(a) <= _mean(b);
  }

  double _mean(List<Player> team) => team.isEmpty
      ? 0
      : team.fold(0.0, (s, p) => s + p.overallRating) / team.length;

  _CandidatePlan _bestPlan(
    List<Player> teamA,
    List<Player> teamB,
    List<TargetPair> targets,
  ) {
    _CandidatePlan? best;
    for (final target in targets) {
      if (target.a.total != teamA.length || target.b.total != teamB.length) {
        continue;
      }
      final planA = assignTeam(
        players: teamA,
        target: target.a,
        team: TeamId.a,
        config: config,
      );
      final planB = assignTeam(
        players: teamB,
        target: target.b,
        team: TeamId.b,
        config: config,
      );
      final candidate = _CandidatePlan(planA, planB, target);
      if (best == null || candidate.isBetterThan(best)) best = candidate;
    }
    if (best == null) {
      throw StateError('No target shape fitted the team sizes');
    }
    return best;
  }
}

class _CandidatePlan {
  const _CandidatePlan(this.a, this.b, this.target);

  final TeamPlan a;
  final TeamPlan b;
  final TargetPair target;

  int get outOfPositionCount => a.outOfPositionCount + b.outOfPositionCount;

  double get transitionDistanceCost =>
      a.transitionDistanceCost + b.transitionDistanceCost;

  int get outOfPositionImbalance =>
      (a.outOfPositionCount - b.outOfPositionCount).abs();

  double get _solverCost => a.cost + b.cost;

  bool isBetterThan(_CandidatePlan other) {
    if (_solverCost != other._solverCost) {
      return _solverCost < other._solverCost;
    }
    if (outOfPositionImbalance != other.outOfPositionImbalance) {
      return outOfPositionImbalance < other.outOfPositionImbalance;
    }
    // Stable fallback so the chosen target is a function of the data.
    return target.toString().compareTo(other.target.toString()) < 0;
  }
}

// ---------------------------------------------------------------------------
// Partition enumeration
// ---------------------------------------------------------------------------

/// Visits every partition of [n] players into a team of [sizeA] and the rest.
///
/// When the sizes are equal, a partition and its mirror are the same split with
/// the labels swapped, so only those containing player 0 are visited — that
/// removes the duplicate and fixes the labels deterministically (`KB-D6`).
void _forEachPartition(int n, int sizeA, bool isEven, void Function(int) visit) {
  if (sizeA == 0 || sizeA > n) return;
  final limit = 1 << n;
  var mask = (1 << sizeA) - 1;
  while (mask < limit) {
    if (!isEven || (mask & 1) != 0) visit(mask);
    mask = _nextCombination(mask);
    if (mask <= 0) break;
  }
}

/// Gosper's hack — the next integer with the same population count.
int _nextCombination(int v) {
  final c = v & -v;
  final r = v + c;
  return r | (((v ^ r) >> 2) ~/ c);
}

int _maskWhere(List<Player> pool, bool Function(Player) test) {
  var mask = 0;
  for (var i = 0; i < pool.length; i++) {
    if (test(pool[i])) mask |= 1 << i;
  }
  return mask;
}

double _distributionScore(int mask, Map<Position, int> primaryMasks, int n) {
  final all = (1 << n) - 1;
  var score = 0.0;
  for (final p in Position.values) {
    final positionMask = primaryMasks[p]!;
    final a = _popcount(mask & positionMask);
    final b = _popcount((all & ~mask) & positionMask);
    score += (a - b).abs();
  }
  return score;
}

int _popcount(int x) {
  var v = x;
  v = v - ((v >> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
  v = (v + (v >> 4)) & 0x0F0F0F0F;
  return ((v * 0x01010101) >> 24) & 0xFF;
}

(List<Player>, List<Player>) _split(int mask, List<Player> pool) {
  final a = <Player>[];
  final b = <Player>[];
  for (var i = 0; i < pool.length; i++) {
    ((mask >> i) & 1 == 1 ? a : b).add(pool[i]);
  }
  return (a, b);
}

String _canonicalKey(int mask, List<Player> pool) {
  final ids = <String>[];
  for (var i = 0; i < pool.length; i++) {
    if ((mask >> i) & 1 == 1) ids.add(pool[i].id);
  }
  return ids.join(',');
}

List<int> _filter(
  List<int> candidates,
  double Function(int) score,
  ToleranceBand band,
) {
  if (candidates.isEmpty) return candidates;
  final scores = {for (final c in candidates) c: score(c)};
  final best = scores.values.reduce((a, b) => a < b ? a : b);
  return candidates.where((c) => band.admits(scores[c]!, best)).toList();
}

List<int> _filterExact(List<int> candidates, double Function(int) score) =>
    _filter(candidates, score, const ToleranceBand.exact());
