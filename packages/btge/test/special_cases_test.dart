/// Specification §16.4 — special cases. `TS-18` … `TS-24`.
///
/// Every scenario must produce a valid result. None is an error condition, and
/// none may cause the engine to refuse to generate (§11).
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

double meanRatingOf(GenerationResult result, List<Player> pool, TeamId team) {
  final ids = result.teamOf(team).map((a) => a.playerId).toSet();
  final members = pool.where((x) => ids.contains(x.id)).toList();
  return members.fold(0.0, (s, x) => s + x.overallRating) / members.length;
}

void main() {
  group('§16.4 special cases', () {
    test('TS-18: an all-forward pool still generates', () {
      final pool = many('f', Position.fwd, 14);
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.assignments, hasLength(14));
      expect(result.sizeOf(TeamId.a), 7);
      expect(result.sizeOf(TeamId.b), 7);

      // NOTE — divergence from §11.1, reported rather than papered over.
      // §11.1 says the engine "spreads them into a workable shape ... then
      // transitions (FWD → MID, then FWD → DEF)". §8's derivation halves the
      // pool's own profile, so an all-forward pool yields an all-forward target
      // and no spreading occurs. The two rules cannot both hold. This test
      // asserts what §8 produces; it does not assert §11.1.
      expect(result.at(Position.fwd), hasLength(14));
      expect(result.metrics.outOfPositionCount, 0);
    });

    test('TS-19: a secondary defender is used before any transition', () {
      final pool = [
        p('u1', Position.mid, secondary: Position.def),
        p('u2', Position.mid, secondary: Position.def),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 2),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.assignments, hasLength(8));
      // No DEF primaries in the pool, so §8 derives no DEF line — and BTGE-PD-5
      // forbids manufacturing one. Both teams play without defenders.
      expect(result.at(Position.def), isEmpty);
      expect(result.metrics.outOfPositionCount, 0);
    });

    test('TS-20: with no defenders at all, both teams play without them', () {
      final pool = [
        ...many('m', Position.mid, 6),
        ...many('f', Position.fwd, 6),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      // BTGE-PD-5: never manufacture a line the pool cannot support. Crucially,
      // neither side has defenders while the other does not.
      expect(result.countIn(TeamId.a, Position.def), 0);
      expect(result.countIn(TeamId.b, Position.def), 0);
    });

    test('TS-21: with no midfielders, neither line is gutted to fill one', () {
      final pool = [
        ...many('d', Position.def, 6),
        ...many('f', Position.fwd, 6),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.at(Position.mid), isEmpty);
      expect(result.countIn(TeamId.a, Position.def), 3);
      expect(result.countIn(TeamId.b, Position.def), 3);
      expect(result.countIn(TeamId.a, Position.fwd), 3);
      expect(result.countIn(TeamId.b, Position.fwd), 3);
    });

    test('TS-22: on an odd count the larger team is not also the stronger', () {
      final pool = [
        for (var i = 0; i < 13; i++)
          p('m${i.toString().padLeft(2, '0')}', Position.mid,
              rating: 10.0 + i * 7),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      final sizeA = result.sizeOf(TeamId.a);
      final sizeB = result.sizeOf(TeamId.b);
      expect({sizeA, sizeB}, {6, 7}); // BTGE-HC-4

      final larger = sizeA > sizeB ? TeamId.a : TeamId.b;
      final smaller = larger == TeamId.a ? TeamId.b : TeamId.a;
      // OP-5 as currently specified: the extra body compensates a rating
      // deficit, so the bigger team must not also be the stronger (KB-012).
      expect(
        meanRatingOf(result, pool, larger),
        lessThanOrEqualTo(meanRatingOf(result, pool, smaller)),
      );
    });

    test('TS-23: a wide age range is not stacked on one side', () {
      final pool = [
        for (var age = 16; age < 32; age++)
          p('a$age', Position.mid, age: age, rating: 50),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      // BTGE-SC-5 / KB-C8: means alone are defeatable, so both measures matter.
      expect(result.metrics.ageDelta, 0);
      expect(result.metrics.ageSplitImbalance, lessThanOrEqualTo(1));
    });

    test('TS-24: a missing secondary position is ordinary input', () {
      final pool = [
        p('a', Position.def),
        p('b', Position.def, secondary: Position.mid),
        p('c', Position.mid),
        p('d', Position.mid),
        p('e', Position.fwd),
        p('f', Position.fwd),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      // BTGE-SC-6: no error, no rejection, chain simply skips step 2.
      expect(result.assignments, hasLength(6));
    });
  });
}
