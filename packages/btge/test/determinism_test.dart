/// Specification §16.8 — determinism. `TS-37`, `TS-38`, `TS-40`.
///
/// `BTGE-PF-6`: identical inputs always produce identical outputs, and
/// randomness is not part of BTGE — no generator, no seed, no shuffling.
library;

import 'dart:io';

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.8 determinism', () {
    List<Player> pool() => [
          p('g1', Position.gk, rating: 40, age: 31),
          p('d1', Position.def, rating: 55, age: 24),
          p('d2', Position.def, rating: 62, age: 38),
          p('m1', Position.mid, rating: 71, age: 27, secondary: Position.def),
          p('m2', Position.mid, rating: 48, age: 19),
          p('m3', Position.mid, rating: 53, age: 45),
          p('f1', Position.fwd, rating: 66, age: 22),
          p('f2', Position.fwd, rating: 34, age: 33),
        ];

    test('TS-37: same inputs, run twice, byte-identical', () {
      final first = const BtgeEngine(strict)
          .generate(players: pool(), settings: settings);
      final second = const BtgeEngine(strict)
          .generate(players: pool(), settings: settings);

      expect(second.signature(), first.signature());
    });

    test('TS-38: input collection order has no effect', () {
      final forwards = pool();
      final backwards = pool().reversed.toList();
      final rotated = [...pool().skip(3), ...pool().take(3)];

      final a = const BtgeEngine(strict)
          .generate(players: forwards, settings: settings);
      final b = const BtgeEngine(strict)
          .generate(players: backwards, settings: settings);
      final c = const BtgeEngine(strict)
          .generate(players: rotated, settings: settings);

      // BTGE-PF-8: the canonical ordering is over the data, not the collection.
      expect(b.signature(), a.signature());
      expect(c.signature(), a.signature());
    });

    test('TS-40: no randomness is reachable from the generation path', () {
      final banned = RegExp(r'\bRandom\b|\.shuffle\(|dart:math');
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (banned.hasMatch(source)) offenders.add(entity.path);
      }

      expect(offenders, isEmpty,
          reason: 'BTGE-PF-6 forbids randomness anywhere in the engine.');
    });

    test('ties resolve by canonical ordering, not by arrival order', () {
      // Four indistinguishable players: every split ties on priorities 1–5, so
      // only BTGE-PF-7 decides. The answer must not move when the input does.
      final tied = many('m', Position.mid, 4, rating: 50, age: 25);

      final straight = BtgeEngine(banded(emergencyGk: false))
          .generate(players: tied, settings: settings);
      final shuffled = BtgeEngine(banded(emergencyGk: false))
          .generate(players: tied.reversed.toList(), settings: settings);

      expect(shuffled.signature(), straight.signature());
    });

    test('diagnostics never claim a truncated search', () {
      final result = const BtgeEngine(strict)
          .generate(players: pool(), settings: settings);
      expect(result.diagnostics.searchWasExhaustive, isTrue);
    });
  });
}
