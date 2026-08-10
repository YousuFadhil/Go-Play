/// Position distribution — Specification §8.
///
/// `BTGE-PD-1` forbids fixed formations and `BTGE-PD-2` requires the target
/// shape of each team to be computed from the position profile of the
/// generation set. The derivation below is the §8 worked illustration
/// generalised: halve the pool's lines, then split each line as evenly as the
/// parity allows (`BTGE-PD-3`).
library;

import 'configuration.dart';
import 'models.dart';

const List<Position> outfieldPositions = [Position.def, Position.mid, Position.fwd];

/// How many slots of each position one team must field.
class TargetShape {
  TargetShape(Map<Position, int> counts)
      : counts = Map.unmodifiable({
          for (final p in Position.values) p: counts[p] ?? 0,
        });

  final Map<Position, int> counts;

  int get total => counts.values.fold(0, (a, b) => a + b);

  int operator [](Position p) => counts[p] ?? 0;

  /// The target expanded into one entry per slot, in axis order. Feeding the
  /// assignment solver a flat slot list keeps it independent of §8.
  List<Position> toSlots() => [
        for (final p in Position.values) ...List.filled(counts[p] ?? 0, p),
      ];

  String get key => Position.values.map((p) => '${p.code}${counts[p]}').join('/');

  @override
  String toString() => key;
}

/// A pair of per-team targets that together consume the whole pool.
class TargetPair {
  const TargetPair(this.a, this.b);

  final TargetShape a;
  final TargetShape b;

  TargetShape of(TeamId team) => team == TeamId.a ? a : b;

  @override
  String toString() => 'A[$a] B[$b]';
}

/// Derives every valid target pair for a pool of [players] split into teams of
/// [sizeA] and [sizeB].
///
/// More than one pair can be valid: when a line holds an odd number of players
/// the surplus may sit on either side (`BTGE-PD-3`). Rather than pick one, the
/// engine returns all of them and lets the optimization priorities choose —
/// that keeps the search exact instead of quietly discarding solutions.
List<TargetPair> deriveTargets({
  required List<Player> players,
  required int sizeA,
  required int sizeB,
  required BtgeConfiguration config,
}) {
  final naturalGoalkeepers = players.where((p) => p.isNaturalGoalkeeper).length;

  // §10 governs goalkeeper slots — never the halving rule, because `BTGE-HC-6`
  // caps a team at one goalkeeper however many the pool holds.
  final goalkeeperSplits = _goalkeeperSplits(
    naturalGoalkeepers: naturalGoalkeepers,
    sizeA: sizeA,
    sizeB: sizeB,
    config: config,
  );

  final pairs = <TargetPair>[];
  for (final (gkA, gkB) in goalkeeperSplits) {
    final outfieldSlotsA = sizeA - gkA;
    final outfieldSlotsB = sizeB - gkB;
    final totalOutfieldSlots = outfieldSlotsA + outfieldSlotsB;

    final poolShape = _outfieldPoolShape(players, totalOutfieldSlots);

    for (final split in _splitLines(poolShape, outfieldSlotsA)) {
      pairs.add(TargetPair(
        TargetShape({...split.a, Position.gk: gkA}),
        TargetShape({...split.b, Position.gk: gkB}),
      ));
    }
  }
  return pairs;
}

/// Goalkeeper slots per team, per §10.
///
/// A pool holding **no** natural goalkeeper gets no goalkeeper slot at all, and
/// that decision outranks [BtgeConfiguration.assignEmergencyGoalkeeper].
/// `BTGE-GK-2`'s emergency keeper stands in for a goalkeeper the pool has but
/// cannot spare — with nobody naming the position at all, filling a goal would
/// be the engine inventing the role rather than covering an absence. `BTGE-GK-3`
/// is unaffected: generation still succeeds, it simply produces an outfield-only
/// shape, and `BTGE-GK-4` already forbids reading a promise of a filled goal
/// into §10.
///
/// With natural goalkeepers present and
/// [BtgeConfiguration.assignEmergencyGoalkeeper] set, each team is given a
/// goalkeeper slot and an emergency keeper may fill the side the single natural
/// one does not take. With it unset, only teams that can be served by a natural
/// goalkeeper get a slot.
List<(int, int)> _goalkeeperSplits({
  required int naturalGoalkeepers,
  required int sizeA,
  required int sizeB,
  required BtgeConfiguration config,
}) {
  final canA = sizeA >= 1;
  final canB = sizeB >= 1;

  if (naturalGoalkeepers == 0) return [(0, 0)];
  if (config.assignEmergencyGoalkeeper) {
    return [(canA ? 1 : 0, canB ? 1 : 0)];
  }
  if (naturalGoalkeepers >= 2) return [(canA ? 1 : 0, canB ? 1 : 0)];
  // `BTGE-GK-9` / `BTGE-GK-10`: the single natural goalkeeper serves one side.
  // Which side is decided by the remaining priorities (`BTGE-GK-11`), so both
  // arrangements are offered to the search.
  return [if (canA) (1, 0), if (canB) (0, 1)];
}

/// The pool's outfield profile, scaled to the number of outfield slots.
///
/// Slots and outfield players do not always match: goalkeeper slots consume
/// players, and surplus goalkeepers beyond `BTGE-HC-6`'s cap need outfield
/// slots. Largest-remainder scaling keeps the shape proportional to the pool,
/// which is what `BTGE-PD-2` requires.
Map<Position, int> _outfieldPoolShape(List<Player> players, int totalSlots) {
  if (totalSlots <= 0) return {for (final p in outfieldPositions) p: 0};

  final counts = <Position, int>{for (final p in outfieldPositions) p: 0};
  for (final player in players) {
    if (player.primaryPosition != Position.gk) {
      counts[player.primaryPosition] = counts[player.primaryPosition]! + 1;
    }
  }
  final totalOutfieldPlayers = counts.values.fold(0, (a, b) => a + b);

  if (totalOutfieldPlayers == 0) {
    // An all-goalkeeper pool. `BTGE-PT-7` sends a goalkeeper who cannot be used
    // in goal outward along the axis, `GK → DEF` first, so the slots are DEF.
    return {Position.def: totalSlots, Position.mid: 0, Position.fwd: 0};
  }
  if (totalOutfieldPlayers == totalSlots) return counts;

  final scaled = <Position, int>{};
  final remainders = <(Position, double)>[];
  var assigned = 0;
  for (final p in outfieldPositions) {
    final exact = counts[p]! * totalSlots / totalOutfieldPlayers;
    final floor = exact.floor();
    scaled[p] = floor;
    assigned += floor;
    remainders.add((p, exact - floor));
  }
  // Largest remainder first; ties resolve by axis order so the result is a pure
  // function of the pool (`BTGE-PF-8`).
  remainders.sort((x, y) {
    final byRemainder = y.$2.compareTo(x.$2);
    return byRemainder != 0 ? byRemainder : x.$1.axisIndex.compareTo(y.$1.axisIndex);
  });
  for (var i = 0; assigned < totalSlots; i = (i + 1) % remainders.length) {
    scaled[remainders[i].$1] = scaled[remainders[i].$1]! + 1;
    assigned++;
  }
  return scaled;
}

class _LineSplit {
  const _LineSplit(this.a, this.b);
  final Map<Position, int> a;
  final Map<Position, int> b;
}

/// Splits each outfield line as evenly as possible (`BTGE-PD-3`), returning
/// every arrangement whose team-A total matches [slotsA].
List<_LineSplit> _splitLines(Map<Position, int> shape, int slotsA) {
  final base = <Position, int>{};
  final oddLines = <Position>[];
  var baseTotal = 0;
  for (final p in outfieldPositions) {
    final count = shape[p] ?? 0;
    base[p] = count ~/ 2;
    baseTotal += count ~/ 2;
    if (count.isOdd) oddLines.add(p);
  }

  final surplusToA = slotsA - baseTotal;
  if (surplusToA < 0 || surplusToA > oddLines.length) return const [];

  final splits = <_LineSplit>[];
  for (final chosen in _combinations(oddLines, surplusToA)) {
    final a = <Position, int>{};
    final b = <Position, int>{};
    for (final p in outfieldPositions) {
      final extra = chosen.contains(p) ? 1 : 0;
      a[p] = base[p]! + extra;
      b[p] = (shape[p] ?? 0) - a[p]!;
    }
    splits.add(_LineSplit(a, b));
  }
  return splits;
}

Iterable<Set<Position>> _combinations(List<Position> source, int take) sync* {
  if (take == 0) {
    yield <Position>{};
    return;
  }
  if (take > source.length) return;
  for (var i = 0; i <= source.length - take; i++) {
    for (final rest in _combinations(source.sublist(i + 1), take - 1)) {
      yield {source[i], ...rest};
    }
  }
}
