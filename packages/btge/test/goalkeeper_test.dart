/// Specification §16.2 — goalkeepers. `TS-06` … `TS-10`, `TS-39`.
///
/// `BTGE-GK-4` caps what may be asserted here: §10 does not establish that
/// every goal is filled, nor that a goalkeeper-free match can never occur. The
/// tests below assert the guarantee and nothing beyond it.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.2 goalkeepers', () {
    test('TS-06: no natural GK — generation succeeds and nobody keeps goal', () {
      final pool = [
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      // BTGE-GK-3: it must not fail for want of a natural goalkeeper.
      expect(result.assignments, hasLength(12));
      expect(result.diagnostics.goalkeeperMode, GoalkeeperMode.none);

      // Product Decision: an emergency keeper covers for a goalkeeper the pool
      // has and cannot spare. A pool naming none has no goal to fill, and the
      // emergency setting does not create one.
      expect(result.at(Position.gk), isEmpty);
      expect(result.diagnostics.emergencyGoalkeeperCount, 0);
    });

    test('TS-06a: the same holds when every player is a FWD', () {
      // The shape has to come from somewhere even when one line holds the whole
      // pool; it is still not allowed to come from goal.
      final result = const BtgeEngine(strict)
          .generate(players: many('f', Position.fwd, 8), settings: settings);

      expect(result.assignments, hasLength(8));
      expect(result.at(Position.gk), isEmpty);
      expect(result.diagnostics.emergencyGoalkeeperCount, 0);
    });

    test('TS-06b: with emergency assignment disabled, no goal is filled', () {
      final pool = [
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.at(Position.gk), isEmpty);
      expect(result.diagnostics.emergencyGoalkeeperCount, 0);
      expect(result.assignments, hasLength(8));
    });

    test('TS-07: one natural GK is used in goal and never passed over', () {
      final pool = [
        p('gk1', Position.gk),
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 3),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.diagnostics.goalkeeperMode, GoalkeeperMode.single);

      // BTGE-GK-5, BTGE-GK-9: the natural goalkeeper keeps the gloves.
      final keeper = result.forPlayer('gk1');
      expect(keeper.assignedPosition, Position.gk);
      expect(keeper.basis, AssignmentBasis.primary);

      // BTGE-GK-10: if the other side gets one, it is an emergency keeper.
      final others =
          result.at(Position.gk).where((a) => a.playerId != 'gk1').toList();
      for (final other in others) {
        expect(other.basis, AssignmentBasis.transition);
      }
      // No assertion on whether `others` is empty — BTGE-GK-4.
    });

    test('TS-08: two natural GKs, one per team', () {
      final pool = [
        ...many('g', Position.gk, 2),
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 2),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.diagnostics.goalkeeperMode, GoalkeeperMode.even);
      // BTGE-GK-12, BTGE-GK-13
      expect(result.countIn(TeamId.a, Position.gk), 1);
      expect(result.countIn(TeamId.b, Position.gk), 1);
      expect(result.diagnostics.emergencyGoalkeeperCount, 0);
      for (final keeper in result.at(Position.gk)) {
        expect(keeper.basis, AssignmentBasis.primary);
      }
    });

    test('TS-09: three natural GKs — two in goal, the third outfield', () {
      final pool = [
        ...many('g', Position.gk, 3),
        ...many('d', Position.def, 3),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 2),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.diagnostics.goalkeeperMode, GoalkeeperMode.surplus);
      // BTGE-GK-14, BTGE-HC-6
      expect(result.at(Position.gk), hasLength(2));

      final outfieldKeepers = ['g01', 'g02', 'g03']
          .map(result.forPlayer)
          .where((a) => a.assignedPosition != Position.gk)
          .toList();
      expect(outfieldKeepers, hasLength(1));
      // BTGE-PT-7: a goalkeeper who cannot be used in goal goes GK → DEF first.
      expect(outfieldKeepers.single.assignedPosition, Position.def);
    });

    test('TS-10: five natural GKs — exactly two goalkeeper assignments', () {
      final pool = [
        ...many('g', Position.gk, 5),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 3),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.at(Position.gk), hasLength(2));
      expect(result.countIn(TeamId.a, Position.gk), 1);
      expect(result.countIn(TeamId.b, Position.gk), 1);
      expect(result.assignments, hasLength(12));
    });

    test('TS-39: an emergency keeper is a DEF, never a FWD', () {
      // One natural goalkeeper, so the other side needs an emergency one. DEF is
      // one step from GK, FWD is three.
      final pool = [
        p('gk1', Position.gk),
        ...many('d', Position.def, 3),
        ...many('f', Position.fwd, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      final emergency =
          result.at(Position.gk).where((a) => a.playerId != 'gk1');
      expect(emergency, isNotEmpty);
      for (final keeper in emergency) {
        final player = pool.firstWhere((x) => x.id == keeper.playerId);
        // BTGE-GK-6, BTGE-PT-4: selection is by transition distance only.
        expect(player.primaryPosition, Position.def);
      }
    });

    test('a GK-secondary player counts as natural and is not out of position',
        () {
      final pool = [
        p('util', Position.def, secondary: Position.gk),
        ...many('d', Position.def, 3),
        ...many('m', Position.mid, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.diagnostics.goalkeeperMode, GoalkeeperMode.single);
      final keeper = result.forPlayer('util');
      expect(keeper.assignedPosition, Position.gk);
      // BTGE-PT-2: a secondary placement is not penalised.
      expect(keeper.basis, AssignmentBasis.secondary);
      expect(keeper.outOfPosition, isFalse);
    });
  });
}
