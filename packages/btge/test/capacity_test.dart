/// Specification §16.1 — `TS-03`, full capacity.
///
/// Slow by design. `BTGE-PF-4` forbids abandoning the search to save time, so
/// this genuinely scores every partition. Skip it in the fast loop with
/// `dart test --exclude-tags capacity`.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'TS-03: 30 players (15v15) — exhaustive search completes',
    () {
      // Distinct ratings and ages, as a real community has. Pools where a whole
      // line shares one rating are covered separately below.
      const shape = [
        (Position.gk, 2),
        (Position.def, 9),
        (Position.mid, 11),
        (Position.fwd, 8),
      ];
      final pool = <Player>[];
      var index = 0;
      for (final (position, count) in shape) {
        for (var i = 0; i < count; i++) {
          pool.add(p(
            'p${index.toString().padLeft(2, '0')}',
            position,
            rating: 31 + index * 1.7,
            age: 18 + (index * 3) % 27,
          ));
          index++;
        }
      }

      final result = const BtgeEngine(strict)
          .generate(players: pool, settings: settings);

      expect(result.assignments, hasLength(30)); // BTGE-HC-1, BTGE-PF-1
      expect(result.sizeOf(TeamId.a), 15);
      expect(result.sizeOf(TeamId.b), 15);
      expect(result.countIn(TeamId.a, Position.gk), 1); // BTGE-HC-6
      expect(result.countIn(TeamId.b, Position.gk), 1);

      // BTGE-PF-4: the whole space was scored, so the result is provably
      // optimal — not the best found before a budget ran out.
      expect(result.diagnostics.searchWasExhaustive, isTrue);
      expect(result.diagnostics.candidatesEvaluated, 77558760);

      // ignore: avoid_print
      print('TS-03: ${result.diagnostics.elapsedMs}ms for '
          '${result.diagnostics.candidatesEvaluated} partitions');
    },
    tags: 'capacity',
  );

  test(
    'known gap: a degenerate pool fails loudly rather than truncating',
    () {
      // Every player in a line sharing one rating makes millions of partitions
      // tie exactly on priorities 1 and 2, so the candidate set outgrows the
      // retention limit. The engine refuses rather than sampling: truncating
      // would silently turn the exact search into a heuristic and breach
      // BTGE-PF-4.
      //
      // This is a real gap against BTGE-HC-7, which requires a valid result for
      // any valid input. Closing it means streaming priorities 3 and 4 as
      // priorities 1 and 2 already are. Recorded here so it is visible.
      final pool = [
        ...many('g', Position.gk, 2, rating: 44, age: 30),
        ...many('d', Position.def, 9, rating: 58, age: 27),
        ...many('m', Position.mid, 11, rating: 63, age: 24),
        ...many('f', Position.fwd, 8, rating: 55, age: 21),
      ];

      expect(
        () => const BtgeEngine(strict)
            .generate(players: pool, settings: settings),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('BTGE-PF-4'),
        )),
      );
    },
    tags: 'capacity',
  );
}
