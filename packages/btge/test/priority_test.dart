/// Specification §16.5 — priority ordering. `TS-25` … `TS-28`.
///
/// The ordering is lexicographic with tolerance bands (§7.1): a solution better
/// at priority k can never be beaten by one better only at k+1.
library;

import 'package:btge/btge.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('§16.5 priority ordering', () {
    test('TS-25: position distribution beats rating balance', () {
      // Two defenders, wildly apart on rating, and six identical midfielders.
      // Splitting the defenders (distribution 0) forces a rating gap of 25.
      // Stacking both defenders on one side closes the gap to 20 — and must
      // lose anyway, because priority 1 outranks priority 2 (KB-002).
      final pool = [
        p('d1', Position.def, rating: 100),
        p('d2', Position.def, rating: 0),
        ...many('m', Position.mid, 6, rating: 10),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.metrics.positionDistributionScore, 0);
      expect(result.countIn(TeamId.a, Position.def), 1);
      expect(result.countIn(TeamId.b, Position.def), 1);
      // The better-rated split was available and was not taken.
      expect(result.metrics.ratingDelta, 25);
    });

    test('TS-26: rating balance beats age balance', () {
      // {a,b} balances age perfectly but costs 20 on rating. {a,d} is perfect
      // on rating and off by 5 on age. Priority 2 outranks priority 4.
      final pool = [
        p('a', Position.mid, rating: 10, age: 20),
        p('b', Position.mid, rating: 10, age: 40),
        p('c', Position.mid, rating: 30, age: 25),
        p('d', Position.mid, rating: 30, age: 35),
      ];
      final result = const BtgeEngine(noEmergencyGk)
          .generate(players: pool, settings: settings);

      expect(result.metrics.ratingDelta, 0);
      expect(result.metrics.ageDelta, 5);

      final teamOfA = result.forPlayer('a').team;
      expect(result.forPlayer('d').team, teamOfA);
      expect(result.forPlayer('b').team, isNot(teamOfA));
    });

    test('a tolerance band lets a lower priority decide, and only then', () {
      // Same pool. With no band on rating, {a,d} wins on priority 2. Widen the
      // rating band past 20 and {a,b} — better on age — becomes reachable.
      // This is the mechanism KB-C1 describes: without bands, priorities 3–5
      // are unreachable.
      final pool = [
        p('a', Position.mid, rating: 10, age: 20),
        p('b', Position.mid, rating: 10, age: 40),
        p('c', Position.mid, rating: 30, age: 25),
        p('d', Position.mid, rating: 30, age: 35),
      ];

      final tight = BtgeEngine(banded(rating: 0, age: 0, emergencyGk: false))
          .generate(players: pool, settings: settings);
      expect(tight.metrics.ageDelta, 5);

      final loose = BtgeEngine(banded(rating: 25, age: 0, emergencyGk: false))
          .generate(players: pool, settings: settings);
      expect(loose.metrics.ageDelta, 0);
      expect(loose.metrics.ratingDelta, 20);
    });

    test('TS-28: diversity never lowers quality', () {
      // {a,d} is the single optimum on priorities 1–4. Make it the most
      // repetitive pairing available and it must still be returned.
      final pool = [
        p('a', Position.mid, rating: 10, age: 20),
        p('b', Position.mid, rating: 10, age: 40),
        p('c', Position.mid, rating: 30, age: 25),
        p('d', Position.mid, rating: 30, age: 35),
      ];
      final history = MatchHistory([
        PastMatch(
          playedAt: matchDay.subtract(const Duration(days: 7)),
          teams: [
            {'a', 'd'},
            {'b', 'c'},
          ],
        ),
      ]);

      final result = BtgeEngine(banded(rating: 0, age: 0, emergencyGk: false, lastNMatches: 5))
          .generate(players: pool, settings: settings, history: history);

      // BTGE-DV-3: one optimal solution, so diversity does not get a vote.
      expect(result.forPlayer('d').team, result.forPlayer('a').team);
      expect(result.metrics.repeatPairCount, greaterThan(0));
    });
  });
}
