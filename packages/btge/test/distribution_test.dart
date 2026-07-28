/// Specification §16.3 — position distribution and transitions.
/// `TS-11` … `TS-17`.
///
/// The chain rules of §9 are exercised directly against [assignTeam], because
/// that is where they live. Testing them only through a whole generation would
/// confound them with the partition search.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.3 distribution (engine level)', () {
    test('TS-11: balanced pool splits every line evenly, nobody displaced', () {
      final pool = [
        ...many('g', Position.gk, 2),
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 6),
        ...many('f', Position.fwd, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.metrics.positionDistributionScore, 0); // BTGE-PD-3
      expect(result.metrics.outOfPositionCount, 0); // BTGE-PT-2
      for (final team in TeamId.values) {
        expect(result.countIn(team, Position.gk), 1);
        expect(result.countIn(team, Position.def), 2);
        expect(result.countIn(team, Position.mid), 3);
        expect(result.countIn(team, Position.fwd), 2);
      }
    });

    test('TS-12: an odd line splits 3/2 and the imbalance is reported', () {
      final pool = [
        ...many('d', Position.def, 5),
        ...many('m', Position.mid, 5),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      final defA = result.countIn(TeamId.a, Position.def);
      final defB = result.countIn(TeamId.b, Position.def);
      expect({defA, defB}, {2, 3}); // BTGE-PD-3

      // The parity that cannot be avoided surfaces in the metric rather than
      // being silently absorbed.
      expect(result.metrics.positionDistributionScore, 2);
    });

    test('TS-16: with emergency assignment off, nobody is moved into goal', () {
      final pool = [
        ...many('d', Position.def, 3),
        ...many('m', Position.mid, 5),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      // BTGE-PT-6: goal is reachable only via §10, never by plain distance.
      expect(result.at(Position.gk), isEmpty);
    });

    test('TS-17: forced displacement is spread across both teams', () {
      // No natural goalkeeper and emergency assignment on, so each side needs
      // one keeper. The shape scales evenly here, so nothing but BTGE-PT-3
      // decides how the displacement lands.
      final pool = [
        ...many('d', Position.def, 8),
        ...many('m', Position.mid, 2),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.metrics.outOfPositionCount, 2);
      // BTGE-PT-3: one per side, never both on one.
      expect(result.metrics.outOfPositionImbalance, 0);
      expect(result.countIn(TeamId.a, Position.gk), 1);
      expect(result.countIn(TeamId.b, Position.gk), 1);
    });

    test('an uneven outfield shape can force an imbalance, and it is reported',
        () {
      // 12 players and two keeper slots leave 10 outfield slots for a 4/4/4
      // pool — no integer split of that is symmetric, so BTGE-PT-3's spreading
      // clause cannot reach zero. The engine reports the imbalance rather than
      // hiding it.
      final pool = [
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.metrics.positionDistributionScore, 0);
      expect(result.metrics.outOfPositionImbalance, 1);
    });
  });

  group('§16.3 the assignment chain (§9, component level)', () {
    TeamPlan planFor(List<Player> players, Map<Position, int> target) =>
        assignTeam(
          players: players,
          target: TargetShape(target),
          team: TeamId.a,
          config: strict,
        );

    test('TS-13: secondary is used before any transition, and is not penalised',
        () {
      final players = [
        p('mid_def', Position.mid, secondary: Position.def),
        p('m2', Position.mid),
      ];
      final plan = planFor(players, {Position.def: 1, Position.mid: 1});

      final displaced =
          plan.assignments.firstWhere((a) => a.playerId == 'mid_def');
      expect(displaced.assignedPosition, Position.def);
      // BTGE-PT-1, BTGE-PT-2
      expect(displaced.basis, AssignmentBasis.secondary);
      expect(plan.outOfPositionCount, 0);
    });

    test('TS-14: the nearer line transitions, not the further one', () {
      final players = [
        p('m1', Position.mid),
        p('f1', Position.fwd),
      ];
      final plan = planFor(players, {Position.def: 1, Position.fwd: 1});

      // MID → DEF is distance 1; FWD → DEF is distance 2. BTGE-PT-4.
      final toDef = plan.assignments
          .firstWhere((a) => a.assignedPosition == Position.def);
      expect(toDef.playerId, 'm1');
      expect(plan.outOfPositionCount, 1);
    });

    test('TS-15: transition distance is measured from the primary', () {
      // Primary FWD, secondary DEF, forced into MID. Distance must be counted
      // FWD → MID (1), not DEF → MID (1 as well) — so the discriminating case
      // is the cost, checked against the primary.
      final players = [
        p('fwd_def', Position.fwd, secondary: Position.def),
        p('d1', Position.def),
      ];
      final plan = planFor(players, {Position.def: 1, Position.mid: 1});

      final displaced =
          plan.assignments.firstWhere((a) => a.playerId == 'fwd_def');
      expect(displaced.assignedPosition, Position.mid);
      expect(displaced.basis, AssignmentBasis.transition);
      // BTGE-PT-5: FWD → MID is one step, cost 1 under the OP-4 weights.
      expect(plan.transitionDistanceCost, 1);
    });

    test('convex weighting prefers two short moves over one long one', () {
      // OP-4, recorded as an Engineering Decision. Two distance-1 moves cost 2;
      // one distance-3 move costs 9.
      final players = [
        p('d1', Position.def),
        p('d2', Position.def),
      ];
      final plan = planFor(players, {Position.gk: 1, Position.mid: 1});

      expect(plan.outOfPositionCount, 2);
      expect(plan.transitionDistanceCost, 2); // DEF→GK (1) + DEF→MID (1)
    });

    test('primary is preferred over secondary when both fit', () {
      final players = [
        p('flex', Position.def, secondary: Position.mid),
        p('m1', Position.mid),
      ];
      final plan = planFor(players, {Position.def: 1, Position.mid: 1});

      expect(
        plan.assignments.firstWhere((a) => a.playerId == 'flex').basis,
        AssignmentBasis.primary,
      );
    });
  });
}
