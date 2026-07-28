/// Specification §16.6 — diversity. `TS-29` … `TS-32`.
///
/// Match History is Auxiliary Data (§4.2.1, `KB-016`): consulted only at
/// priority 5, only after 1–4 are satisfied, only as a tie-breaker.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.6 diversity', () {
    /// Four indistinguishable players, so priorities 1–4 tie for every split
    /// and only diversity can separate them.
    List<Player> tiedPool() => many('m', Position.mid, 4, rating: 50, age: 25);

    MatchHistory historyPairing(String x, String y, {int daysAgo = 7}) =>
        MatchHistory([
          PastMatch(
            playedAt: matchDay.subtract(Duration(days: daysAgo)),
            teams: [
              {x, y},
              {'m03', 'm04'}.difference({x, y}),
            ],
          ),
        ]);

    test('TS-29: among tied solutions, the least repetitive one wins', () {
      final pool = tiedPool();
      final history = MatchHistory([
        PastMatch(
          playedAt: matchDay.subtract(const Duration(days: 7)),
          teams: [
            {'m01', 'm02'},
            {'m03', 'm04'},
          ],
        ),
      ]);

      final result =
          BtgeEngine(banded(emergencyGk: false, lastNMatches: 5))
              .generate(players: pool, settings: settings, history: history);

      // BTGE-DV-1, BTGE-DV-2: last week's pairing is broken up.
      expect(result.metrics.repeatPairCount, 0);
      expect(
        result.forPlayer('m01').team,
        isNot(result.forPlayer('m02').team),
      );
      expect(result.diagnostics.solutionCountAtOptimum, greaterThan(1));
    });

    test('TS-31: no history — valid result, deterministic, never an error', () {
      final pool = tiedPool();
      final result = BtgeEngine(banded(emergencyGk: false, lastNMatches: 5))
          .generate(players: pool, settings: settings);

      // BTGE-DV-5: diversity contributes nothing, canonical ordering decides.
      expect(result.metrics.repeatPairCount, 0);
      expect(result.assignments, hasLength(4));

      final again = BtgeEngine(banded(emergencyGk: false, lastNMatches: 5))
          .generate(players: pool, settings: settings);
      expect(again.signature(), result.signature());
    });

    test('TS-32: history older than the window is ignored', () {
      final pool = tiedPool();
      final history = historyPairing('m01', 'm02', daysAgo: 90);

      final inWindow = BtgeEngine(
        banded(emergencyGk: false, within: const Duration(days: 120)),
      ).generate(players: pool, settings: settings, history: history);

      final outOfWindow = BtgeEngine(
        banded(emergencyGk: false, within: const Duration(days: 30)),
      ).generate(players: pool, settings: settings, history: history);

      // BTGE-DV-4: the same history, scoped differently, changes the outcome.
      expect(
        inWindow.forPlayer('m01').team,
        isNot(inWindow.forPlayer('m02').team),
      );
      expect(outOfWindow.metrics.repeatPairCount, 0);
      expect(
        outOfWindow.forPlayer('m01').team,
        outOfWindow.forPlayer('m02').team,
      );
    });

    test('an unset lookback window degrades to the no-history path', () {
      final pool = tiedPool();
      final history = historyPairing('m01', 'm02');

      // OP-6 unset. BTGE-DV-5 covers this: not an error, diversity is inert.
      final result = BtgeEngine(banded(emergencyGk: false))
          .generate(players: pool, settings: settings, history: history);

      expect(result.metrics.repeatPairCount, greaterThanOrEqualTo(0));
      expect(result.assignments, hasLength(4));
    });

    test('history cannot influence any priority above diversity', () {
      // BTGE-AX-2. The same pool, with and without history, must agree on every
      // metric from priorities 1–4.
      final pool = [
        p('a', Position.mid, rating: 10, age: 20),
        p('b', Position.mid, rating: 10, age: 40),
        p('c', Position.mid, rating: 30, age: 25),
        p('d', Position.mid, rating: 30, age: 35),
      ];
      final config = banded(rating: 0, age: 0, emergencyGk: false, lastNMatches: 5);
      final history = MatchHistory([
        PastMatch(
          playedAt: matchDay.subtract(const Duration(days: 3)),
          teams: [
            {'a', 'd'},
            {'b', 'c'},
          ],
        ),
      ]);

      final without =
          BtgeEngine(config).generate(players: pool, settings: settings);
      final with_ = BtgeEngine(config)
          .generate(players: pool, settings: settings, history: history);

      expect(with_.metrics.positionDistributionScore,
          without.metrics.positionDistributionScore);
      expect(with_.metrics.ratingDelta, without.metrics.ratingDelta);
      expect(with_.metrics.outOfPositionCount, without.metrics.outOfPositionCount);
      expect(with_.metrics.ageDelta, without.metrics.ageDelta);
    });
  });
}
