/// Specification §16.1 — hard constraints. `TS-01` … `TS-05`.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.1 hard constraints', () {
    test('TS-01: every player assigned exactly once, sizes 5/5', () {
      final pool = [
        ...many('g', Position.gk, 2),
        ...many('d', Position.def, 3),
        ...many('m', Position.mid, 3),
        ...many('f', Position.fwd, 2),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      // BTGE-HC-1, BTGE-HC-2
      expect(result.assignments, hasLength(10));
      expect(
        result.assignments.map((a) => a.playerId).toSet(),
        pool.map((x) => x.id).toSet(),
      );
      // BTGE-HC-4
      expect(result.sizeOf(TeamId.a), 5);
      expect(result.sizeOf(TeamId.b), 5);
      // BTGE-HC-5
      expect(
        result.assignments.every((a) => Position.values.contains(a.assignedPosition)),
        isTrue,
      );
      // BTGE-HC-6
      expect(result.countIn(TeamId.a, Position.gk), lessThanOrEqualTo(1));
      expect(result.countIn(TeamId.b, Position.gk), lessThanOrEqualTo(1));
    });

    test('TS-02: 11 players split 6/5, never 7/4', () {
      final pool = [
        ...many('g', Position.gk, 1),
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
        ...many('f', Position.fwd, 2),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      final sizes = [result.sizeOf(TeamId.a), result.sizeOf(TeamId.b)]..sort();
      expect(sizes, [5, 6]); // BTGE-HC-4
      expect(result.assignments, hasLength(11)); // BTGE-HC-3
    });

    test('TS-04: 31 players rejected, no partial result', () {
      final pool = many('x', Position.mid, 31);
      expect(
        () => const BtgeEngine(strict).generate(players: pool, settings: settings),
        throwsA(
          isA<BtgeInputError>().having(
            (e) => e.code,
            'code',
            BtgeErrorCode.tooManyPlayers,
          ),
        ),
      );
    });

    test('TS-04b: below the configured minimum is rejected', () {
      expect(
        () => const BtgeEngine(strict)
            .generate(players: [p('solo', Position.mid)], settings: settings),
        throwsA(isA<BtgeInputError>()
            .having((e) => e.code, 'code', BtgeErrorCode.tooFewPlayers)),
      );
    });

    test('TS-05: unusable rating is rejected, never defaulted', () {
      final pool = [
        ...many('m', Position.mid, 3),
        Player(
          id: 'broken',
          overallRating: double.nan,
          dateOfBirth: DateTime(2000),
          primaryPosition: Position.def,
        ),
      ];
      expect(
        () => const BtgeEngine(strict).generate(players: pool, settings: settings),
        throwsA(isA<BtgeInputError>()
            .having((e) => e.code, 'code', BtgeErrorCode.missingRequiredInput)),
      );
    });

    test('TS-05b: duplicate player ids are rejected', () {
      final pool = [
        p('same', Position.mid),
        p('same', Position.def),
        p('other', Position.fwd),
        p('another', Position.def),
      ];
      expect(
        () => const BtgeEngine(strict).generate(players: pool, settings: settings),
        throwsA(isA<BtgeInputError>()
            .having((e) => e.code, 'code', BtgeErrorCode.duplicatePlayerId)),
      );
    });

    test('BTGE-HC-7: a difficult pool still yields a valid solution', () {
      // Nothing but goalkeepers — the hardest shape the vocabulary allows.
      final pool = many('g', Position.gk, 8);
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.assignments, hasLength(8));
      expect(result.countIn(TeamId.a, Position.gk), lessThanOrEqualTo(1));
      expect(result.countIn(TeamId.b, Position.gk), lessThanOrEqualTo(1));
    });

    test('the search is exhaustive, so the result is provably optimal', () {
      final pool = [
        ...many('d', Position.def, 4),
        ...many('m', Position.mid, 4),
      ];
      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      // BTGE-PF-4: no early exit, no best-found-so-far.
      expect(result.diagnostics.searchWasExhaustive, isTrue);
      expect(result.diagnostics.candidatesEvaluated, greaterThan(0));
    });
  });
}
