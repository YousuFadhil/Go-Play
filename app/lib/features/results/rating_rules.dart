import 'dart:math' as math;

import 'package:btge/btge.dart';

import '../teams/team_models.dart';
import 'result_models.dart';

/// The approved rating engine, as arithmetic.
///
/// **This is not what moves a rating.** `OP-1` makes the rating system-managed,
/// so no policy lets a client write `users.overall_rating` and no client is
/// trusted to say what a win is worth: the database applies these changes inside
/// `record_match_result`, atomically with the result, the goals, the audit and
/// the counters.
///
/// What this is for is that the rule should be readable and testable in one
/// place rather than only observable through a round trip. The constants below
/// and the ones in migration `0035` are the same five numbers, and the
/// integration suite records a real result and holds the database to what this
/// predicts — so the copy is checked rather than merely intended.
class RatingRules {
  const RatingRules({
    required this.win,
    required this.loss,
    required this.goal,
    required this.goalCap,
    required this.mvp,
  });

  /// What each player on the winning side gains.
  final double win;

  /// What each player on the losing side is charged. Negative.
  final double loss;

  /// What one goal is worth to whoever scored it.
  final double goal;

  /// The most a player's goals may be worth in one match, however many they
  /// scored. The team result is the most influential factor, and an uncapped
  /// goal bonus is what would let a losing scorer out-earn a winner.
  final double goalCap;

  /// What being the best player on the pitch is worth.
  final double mvp;
}

/// The approved values. A draw is not among them: it is the absence of a win and
/// of a loss, so a drawn side gets no entry from the outcome at all.
///
/// The five hold together rather than standing alone: the goal bonus caps at
/// exactly what a loss costs, so a loser's goals can at best bring them back to
/// where they started, and the MVP award is smaller than a win — which is what
/// keeps a winner who did nothing else ahead of a losing top scorer who was also
/// named best on the pitch (+0.10 against +0.05).
const ratingRules = RatingRules(
  win: 0.10,
  loss: -0.10,
  goal: 0.02,
  goalCap: 0.10,
  mvp: 0.05,
);

/// The lowest and highest rating a player may hold (`OP-1`).
const minimumRating = 0.0;
const maximumRating = 10.0;

/// One change the engine says a result produces.
///
/// One per player per reason, which is the granularity the audit keeps: a player
/// who won, scored twice and was named best on the pitch produced three changes,
/// not one of 0.40.
class RatingDelta {
  const RatingDelta({
    required this.userId,
    required this.reason,
    required this.delta,
  });

  final String userId;
  final RatingChangeReason reason;
  final double delta;
}

/// Every rating change [result] produces for the players of [lineup].
///
/// The order is the one the database records them in — outcome, then goals, then
/// the MVP — so a prediction and an audit read the same way. Nothing is clamped
/// here: these are the changes the rules ask for, and what a rating at the end of
/// its range can actually absorb is [applyRatingDeltas]' business.
///
/// [rules] is a parameter rather than a constant read straight from the file
/// because a test that could not vary the numbers could not show that the
/// arithmetic follows them.
List<RatingDelta> ratingDeltasFor(
  MatchResult result,
  List<TeamAssignment> lineup, {
  RatingRules rules = ratingRules,
}) {
  final deltas = <RatingDelta>[];

  // A Professional Guest wins and loses the match and no rating moves: they
  // have no account, so there is no rating for one to move. This mirrors
  // migration `0046`, which filters the same participants out of the database's
  // own engine, and it is what keeps the two statements of the rules in step.
  if (!result.isDraw) {
    for (final assignment in lineup) {
      final userId = assignment.userId;
      if (userId == null) continue;
      final won = assignment.team == result.winner;
      deltas.add(RatingDelta(
        userId: userId,
        reason: won ? RatingChangeReason.win : RatingChangeReason.loss,
        delta: won ? rules.win : rules.loss,
      ));
    }
  }

  // Scorers in the lineup's order, so two runs over the same result produce the
  // same list. A tally for somebody outside the lineup is not scored here; that
  // is a refusal, and `validateResultInputs` has already made it one.
  //
  // One entry per scorer, carrying the whole of what their goals were worth —
  // held at [RatingRules.goalCap], so a sixth goal is worth nothing more than a
  // fifth. The cap is on the total, not on each goal: five goals reach it
  // exactly, and everything beyond stops there.
  for (final assignment in lineup) {
    final userId = assignment.userId;
    if (userId == null) continue;
    final scored = result.goalsBy(userId);
    if (scored == 0) continue;
    deltas.add(RatingDelta(
      userId: userId,
      reason: RatingChangeReason.goal,
      delta: math.min(rules.goal * scored, rules.goalCap),
    ));
  }

  // No MVP, no MVP delta. The absence of the entry is what "do not award"
  // means, here and in `apply_match_rating_effects` — the two are held to each
  // other by the integration suite, so they have to say it the same way.
  final mvpUserId = result.mvpUserId;
  if (mvpUserId != null) {
    deltas.add(RatingDelta(
      userId: mvpUserId,
      reason: RatingChangeReason.mvp,
      delta: rules.mvp,
    ));
  }

  return deltas;
}

/// The rating [before] ends at once [deltas] have been applied in order.
///
/// Each step is held inside the approved range, which is why this is a fold
/// rather than a sum: a player at the top of the scale absorbs part of a gain
/// and no more, and the next change starts from where that left them.
double applyRatingDeltas(double before, Iterable<double> deltas) {
  var rating = before;
  for (final delta in deltas) {
    rating = clampRating(rating + delta);
  }
  return rating;
}

/// [rating] held inside the approved range (`OP-1`).
double clampRating(double rating) =>
    rating.clamp(minimumRating, maximumRating).toDouble();

/// The team [userId] was on, or null when they were not in [lineup].
TeamId? teamOf(List<TeamAssignment> lineup, String userId) {
  for (final assignment in lineup) {
    if (assignment.userId == userId) return assignment.team;
  }
  return null;
}
