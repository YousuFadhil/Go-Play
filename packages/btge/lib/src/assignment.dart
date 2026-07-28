/// Position assignment — Specification §9 and §10.
///
/// Given the players on one team and that team's target shape, this finds the
/// **cost-minimal** way to fill the slots. Minimising globally rather than
/// walking the chain player by player is the faithful reading of §9: a greedy
/// walk can block a strictly better arrangement, and `BTGE-PT-3` asks for the
/// minimum, not the first acceptable answer.
library;

import 'configuration.dart';
import 'distribution.dart';
import 'models.dart';
import 'result.dart';

/// One team's filled shape.
class TeamPlan {
  const TeamPlan({
    required this.assignments,
    required this.cost,
    required this.outOfPositionCount,
    required this.transitionDistanceCost,
    required this.emergencyGoalkeepers,
  });

  final List<PlayerAssignment> assignments;

  /// Solver cost, including the ordering penalties of
  /// [BtgeConfiguration.placementCost]. Not a reported metric.
  final double cost;

  final int outOfPositionCount;

  /// Weighted transition distance only — the reported `out_of_position_cost`.
  final double transitionDistanceCost;

  /// Goalkeepers filled by a player who is not a natural goalkeeper
  /// (`BTGE-GK-2`).
  final int emergencyGoalkeepers;
}

/// Fills [target] with [players], minimising placement cost.
TeamPlan assignTeam({
  required List<Player> players,
  required TargetShape target,
  required TeamId team,
  required BtgeConfiguration config,
}) {
  final slots = target.toSlots();
  assert(slots.length == players.length,
      'target total ${slots.length} must equal team size ${players.length}');

  if (players.isEmpty) {
    return const TeamPlan(
      assignments: [],
      cost: 0,
      outOfPositionCount: 0,
      transitionDistanceCost: 0,
      emergencyGoalkeepers: 0,
    );
  }

  final costs = List.generate(
    players.length,
    (i) => List.generate(
      slots.length,
      (j) => config.placementCost(players[i], slots[j]),
      growable: false,
    ),
    growable: false,
  );

  final slotOfPlayer = _hungarian(costs);

  final assignments = <PlayerAssignment>[];
  var outOfPosition = 0;
  var distanceCost = 0.0;
  var emergencyGoalkeepers = 0;
  var total = 0.0;

  for (var i = 0; i < players.length; i++) {
    final player = players[i];
    final position = slots[slotOfPlayer[i]];
    final basis = BtgeConfiguration.basisFor(player, position);
    total += costs[i][slotOfPlayer[i]];

    if (basis == AssignmentBasis.transition) {
      outOfPosition++;
      distanceCost +=
          config.transitionCost(player.primaryPosition.distanceTo(position));
      // `BTGE-GK-7`: an emergency goalkeeper is a transition and counts as
      // out-of-position. A natural goalkeeper placed by secondary does not.
      if (position == Position.gk) emergencyGoalkeepers++;
    }

    assignments.add(PlayerAssignment(
      playerId: player.id,
      team: team,
      assignedPosition: position,
      basis: basis,
    ));
  }

  // Stable output order: by axis, then by player id, so the result never
  // depends on input collection order (`BTGE-PF-8`).
  assignments.sort((x, y) {
    final byAxis =
        x.assignedPosition.axisIndex.compareTo(y.assignedPosition.axisIndex);
    return byAxis != 0 ? byAxis : x.playerId.compareTo(y.playerId);
  });

  return TeamPlan(
    assignments: assignments,
    cost: total,
    outOfPositionCount: outOfPosition,
    transitionDistanceCost: distanceCost,
    emergencyGoalkeepers: emergencyGoalkeepers,
  );
}

/// Hungarian algorithm (Kuhn–Munkres) with potentials, O(n³).
///
/// Exact — it returns a provably minimum-cost assignment, which is what
/// `BTGE-PF-4` requires. Returns, for each row, its assigned column. The matrix
/// is built in canonical order, so the choice among equal-cost assignments is
/// itself deterministic (`BTGE-PF-6`).
List<int> _hungarian(List<List<double>> cost) {
  final n = cost.length;
  final m = cost[0].length;
  const inf = double.infinity;

  final u = List<double>.filled(n + 1, 0);
  final v = List<double>.filled(m + 1, 0);
  final p = List<int>.filled(m + 1, 0);
  final way = List<int>.filled(m + 1, 0);

  for (var i = 1; i <= n; i++) {
    p[0] = i;
    var j0 = 0;
    final minv = List<double>.filled(m + 1, inf);
    final used = List<bool>.filled(m + 1, false);

    do {
      used[j0] = true;
      final i0 = p[j0];
      var delta = inf;
      var j1 = 0;
      for (var j = 1; j <= m; j++) {
        if (used[j]) continue;
        final cur = cost[i0 - 1][j - 1] - u[i0] - v[j];
        if (cur < minv[j]) {
          minv[j] = cur;
          way[j] = j0;
        }
        if (minv[j] < delta) {
          delta = minv[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= m; j++) {
        if (used[j]) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else {
          minv[j] -= delta;
        }
      }
      j0 = j1;
    } while (p[j0] != 0);

    do {
      final j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }

  final rowToColumn = List<int>.filled(n, 0);
  for (var j = 1; j <= m; j++) {
    if (p[j] > 0) rowToColumn[p[j] - 1] = j - 1;
  }
  return rowToColumn;
}
