/// Shared test fixtures. Pure data — no database, no adapters.
library;

import 'package:btge/btge.dart';

/// Fixed reference date so ages are stable across runs.
final DateTime matchDay = DateTime(2026, 7, 1);

final MatchSettings settings = MatchSettings(matchDate: matchDay);

/// Builds a player. [age] is converted to a date of birth, because the engine
/// derives age and never accepts it directly (`KB-C7`).
Player p(
  String id,
  Position primary, {
  Position? secondary,
  double rating = 50,
  int age = 25,
}) =>
    Player(
      id: id,
      overallRating: rating,
      dateOfBirth: DateTime(matchDay.year - age, matchDay.month, matchDay.day),
      primaryPosition: primary,
      secondaryPosition: secondary,
    );

/// [count] players of one position, ids prefixed so they sort predictably.
List<Player> many(
  String prefix,
  Position position,
  int count, {
  Position? secondary,
  double rating = 50,
  int age = 25,
}) =>
    List.generate(
      count,
      (i) => p(
        '$prefix${(i + 1).toString().padLeft(2, '0')}',
        position,
        secondary: secondary,
        rating: rating,
        age: age,
      ),
    );

/// Strict ordering, no tolerance anywhere. Used where a test asserts that a
/// higher priority beats a lower one outright.
const BtgeConfiguration strict = BtgeConfiguration.strictLexicographic();

/// Strict, but without emergency goalkeepers, so `BTGE-GK-2`'s "may" is
/// exercised in both directions.
const BtgeConfiguration noEmergencyGk =
    BtgeConfiguration.strictLexicographic(assignEmergencyGoalkeeper: false);

/// A configuration with real tolerance bands, so priorities 3–5 are reachable
/// (`KB-C1`). The widths are test values, not a proposed `OP-3` setting.
BtgeConfiguration banded({
  double distribution = 0,
  double rating = 5,
  double outOfPosition = 0,
  double age = 5,
  int? lastNMatches,
  Duration? within,
  OddCountRule oddRule = OddCountRule.weakerTeamGetsExtra,
  bool emergencyGk = true,
}) =>
    BtgeConfiguration(
      distributionBand: ToleranceBand(absolute: distribution),
      ratingBand: ToleranceBand(absolute: rating),
      outOfPositionBand: ToleranceBand(absolute: outOfPosition),
      ageBand: ToleranceBand(absolute: age),
      oddCountRule: oddRule,
      minPlayers: 2,
      diversityLastNMatches: lastNMatches,
      diversityWithin: within,
      assignEmergencyGoalkeeper: emergencyGk,
    );

extension ResultQueries on GenerationResult {
  Iterable<PlayerAssignment> at(Position position) =>
      assignments.where((a) => a.assignedPosition == position);

  PlayerAssignment forPlayer(String id) =>
      assignments.firstWhere((a) => a.playerId == id);

  int countIn(TeamId team, Position position) => assignments
      .where((a) => a.team == team && a.assignedPosition == position)
      .length;

  int sizeOf(TeamId team) => assignments.where((a) => a.team == team).length;

  /// Everything determinism covers, and nothing it does not.
  ///
  /// `BTGE-PF-6` is about the result being a function of the inputs. Wall-clock
  /// diagnostics such as `elapsedMs` are excluded — they are measurements of
  /// the run, not part of the answer.
  String signature() => [
        for (final a in assignments) a.toString(),
        metrics.toString(),
        diagnostics.goalkeeperMode.name,
        'emergencyGk=${diagnostics.emergencyGoalkeeperCount}',
        'tied=${diagnostics.solutionCountAtOptimum}',
        'evaluated=${diagnostics.candidatesEvaluated}',
      ].join('\n');
}
