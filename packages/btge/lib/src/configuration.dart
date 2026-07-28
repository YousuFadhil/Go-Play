/// Engine configuration — the Open Parameters of Specification §18.1.
///
/// Every value here is **configuration, not a decision**. §18.1 is explicit
/// that no default may be silently treated as a decision, so the fields that
/// are still Product Decisions have **no default** and must be supplied by the
/// caller. That is deliberate: it makes an unmade decision a compile error
/// rather than a quiet assumption.
library;

import 'models.dart';

/// How close two solutions must be at a priority to count as equally good and
/// pass to the next priority. Specification §7.1, `OP-3`.
///
/// Tolerance bands are what make priorities 3–5 reachable at all: without them
/// the first priority decides everything and "if multiple optimal solutions
/// exist" is never true (`KB-C1`).
class ToleranceBand {
  const ToleranceBand({this.absolute = 0, this.relative = 0})
      : assert(absolute >= 0, 'absolute band must not be negative'),
        assert(relative >= 0, 'relative band must not be negative');

  /// No tolerance — only exactly equal scores tie.
  const ToleranceBand.exact()
      : absolute = 0,
        relative = 0;

  /// Width in the metric's own units (rating points, years, slots).
  final double absolute;

  /// Width as a fraction of the best score at this priority.
  final double relative;

  /// Whether [score] is close enough to [best] to survive this priority.
  bool admits(double score, double best) {
    final width = absolute + (best.abs() * relative);
    return score <= best + width + _epsilon;
  }

  static const double _epsilon = 1e-9;

  @override
  String toString() => 'ToleranceBand(abs: $absolute, rel: $relative)';
}

/// Which team receives the extra player when the count is odd. `OP-5`.
///
/// `KB-012` approves that compensation must happen; *how* is an open Product
/// Decision. These are the options as recorded, not a choice made here.
enum OddCountRule {
  /// Extra player joins the team otherwise weaker on mean rating.
  weakerTeamGetsExtra,

  /// Extra player joins whichever team yields the better final balance.
  bestFinalBalance,
}

/// The Open Parameters, supplied by the caller.
class BtgeConfiguration {
  const BtgeConfiguration({
    required this.distributionBand,
    required this.ratingBand,
    required this.outOfPositionBand,
    required this.ageBand,
    required this.oddCountRule,
    required this.minPlayers,
    this.transitionCostByDistance = defaultTransitionCost,
    this.diversityLastNMatches,
    this.diversityWithin,
    this.assignEmergencyGoalkeeper = true,
  });

  /// A configuration with no tolerance at any priority.
  ///
  /// Useful for tests that assert strict priority ordering. **Not** a proposed
  /// production setting: with exact bands, priorities 3–5 are effectively
  /// unreachable (`KB-C1`).
  const BtgeConfiguration.strictLexicographic({
    this.oddCountRule = OddCountRule.weakerTeamGetsExtra,
    this.minPlayers = 2,
    this.transitionCostByDistance = defaultTransitionCost,
    this.diversityLastNMatches,
    this.diversityWithin,
    this.assignEmergencyGoalkeeper = true,
  })  : distributionBand = const ToleranceBand.exact(),
        ratingBand = const ToleranceBand.exact(),
        outOfPositionBand = const ToleranceBand.exact(),
        ageBand = const ToleranceBand.exact();

  /// `OP-3`, priority 1. **Product Decision — no default.**
  final ToleranceBand distributionBand;

  /// `OP-3`, priority 2. **Product Decision — no default.**
  final ToleranceBand ratingBand;

  /// `OP-3`, priority 3. **Product Decision — no default.**
  final ToleranceBand outOfPositionBand;

  /// `OP-3`, priority 4. **Product Decision — no default.**
  final ToleranceBand ageBand;

  /// `OP-5`. **Product Decision — no default.**
  final OddCountRule oddCountRule;

  /// `OP-2`. **Product Decision — no default.**
  final int minPlayers;

  /// `OP-6`. **Product Decision.** Null means the window is unset, in which
  /// case Diversity sees no history and contributes nothing — which is the
  /// approved `BTGE-DV-5` path, not an error.
  final int? diversityLastNMatches;

  /// `OP-6`, time-span form. May be combined with [diversityLastNMatches].
  final Duration? diversityWithin;

  /// `OP-4` — cost per transition distance, indexed by distance 0…3.
  ///
  /// **Engineering Decision**, settled here as recorded in §18.1: the weighting
  /// is *convex*. `KB-003` ranks "logical fallback" (step 3) and "emergency
  /// placement" (step 4) as distinct, and only a superlinear cost reproduces
  /// that ranking inside a single scalar — a linear cost would let the engine
  /// trade one emergency placement for two ordinary fallbacks.
  final List<double> transitionCostByDistance;

  /// `BTGE-GK-2` says the engine **may** assign an emergency goalkeeper.
  ///
  /// The latitude in "may" is exposed here rather than resolved in code.
  /// `BTGE-GK-4` forbids deriving a stronger guarantee than §10 states, so this
  /// flag must not be read as a promise that every goal is filled.
  final bool assignEmergencyGoalkeeper;

  static const List<double> defaultTransitionCost = [0, 1, 3, 9];

  double transitionCost(int distance) =>
      transitionCostByDistance[distance.clamp(0, transitionCostByDistance.length - 1)];

  /// Cost of placing [player] at [position] under the assignment chain (§9).
  ///
  /// A transition always costs at least 1, and a secondary placement costs a
  /// token amount that no accumulation can reach — 30 players × 0.001 stays
  /// well under the cheapest transition. So minimising total cost minimises
  /// weighted transition distance first and, among arrangements that tie there,
  /// prefers primary over secondary. That is `BTGE-PT-1`'s ordering.
  ///
  /// The weighting is deliberately *not* dominated by transition count. Under
  /// the convex weights of `OP-4`, two distance-1 moves (2) cost less than one
  /// distance-3 move (9) — which is the whole point of choosing convexity, and
  /// is what `BTGE-PT-4` asks for when it prefers the shorter transition.
  double placementCost(Player player, Position position) {
    if (player.primaryPosition == position) return 0;
    if (player.secondaryPosition == position) return _secondaryCost;
    return transitionCost(player.primaryPosition.distanceTo(position));
  }

  /// Token cost, strictly below the cheapest transition even when every player
  /// is placed on their secondary.
  static const double _secondaryCost = 0.001;

  /// True when the placement counts as out-of-position (`BTGE-PT-2`).
  static bool isOutOfPosition(Player player, Position position) =>
      player.primaryPosition != position && player.secondaryPosition != position;

  static AssignmentBasis basisFor(Player player, Position position) {
    if (player.primaryPosition == position) return AssignmentBasis.primary;
    if (player.secondaryPosition == position) return AssignmentBasis.secondary;
    return AssignmentBasis.transition;
  }
}
