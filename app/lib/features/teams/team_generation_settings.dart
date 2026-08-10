import 'package:btge/btge.dart';

/// The approved Product Decisions for team generation, expressed as
/// configuration.
///
/// Every value below is a Product Owner decision recorded in §18.1.1 of
/// `Docs/engineering/BTGE_Engineering_Specification.md`. `BtgeConfiguration`
/// deliberately gives none of them a default, so the decision has to be stated
/// somewhere the *product* owns — this file is that place.
///
/// It is **not** an engine default. `packages/btge` still requires every caller
/// to supply its own configuration, which is what keeps an unmade decision a
/// compile error rather than a silent assumption (§18.1). Nothing here may be
/// reinterpreted, rounded or tuned: changing a value means amending §18.1.1
/// first (`BTGE-CC-7`).
const BtgeConfiguration approvedTeamGeneration = BtgeConfiguration(
  // OP-3, priority 1 — position distribution, in the integer units of
  // position_distribution_score.
  distributionBand: ToleranceBand(absolute: 2),

  // OP-3, priority 2 — rating balance, in Overall Rating points on the OP-1
  // scale of 0.0 … 10.0.
  ratingBand: ToleranceBand(absolute: 0.10),

  // OP-3, priority 3 — out-of-position, in weighted transition cost.
  outOfPositionBand: ToleranceBand(absolute: 2),

  // OP-3, priority 4 — age balance, in years of mean age.
  ageBand: ToleranceBand(absolute: 1.00),

  // OP-5 — on an odd count the extra player joins the team otherwise weaker on
  // rating.
  oddCountRule: OddCountRule.weakerTeamGetsExtra,

  // OP-2 — the minimum supported match is 4 players, 2 v 2. The same bound
  // governs matches.starting_players, because the rule is product-wide and not
  // generation-only.
  minPlayers: 4,

  // OP-6 — the last 5 matches. The match-count form is the approved one; no
  // time-based window was approved, so diversityWithin stays unset.
  diversityLastNMatches: 5,
);

/// How many played lineups to read for Diversity.
///
/// This is the fetch side of `OP-6`, derived from the one approved value rather
/// than restated, so the read bound and the window the engine applies cannot
/// drift apart. It is `final` rather than `const` because Dart cannot read an
/// instance field of a const object inside a constant expression.
final int? approvedHistoryLookback =
    approvedTeamGeneration.diversityLastNMatches;
