import 'package:btge/btge.dart';

import '../../core/failures.dart';

/// Domain Models for what a played match leaves behind (OP-3): the score, the
/// goals behind it, the best player, the rating changes that followed, and the
/// counters they feed.
///
/// `TeamId` comes from `package:btge` rather than being restated here. The two
/// sides of a match are the two sides of its lineup — `KB-D6` already says what
/// `A` and `B` mean, and a second enum for the same thing is exactly what OP-3
/// forbids.

/// How many goals one player scored in one match.
///
/// A hat-trick is one tally of three. No approved document asks for the minute a
/// goal was scored or the order of them, and three tallies of one would record
/// the same fact three times without adding either.
class GoalTally {
  const GoalTally({required this.userId, required this.goals});

  final String userId;

  /// Always at least one: the tally asserts that this player scored. Nobody
  /// scoring nothing is the absence of a tally, which is why a goalless match
  /// carries an empty list rather than a list of zeroes.
  final int goals;
}

/// The recorded result of one match.
///
/// [mvpUserId] is nullable, which is how "at most one MVP per match" is said in
/// a model. It was not-null while naming a best player was a condition of the
/// result existing at all; it is not any more. A result with no MVP is a
/// complete result — the score stands, the goals stand, the ratings for winning,
/// losing and scoring are all applied — and the one thing it does not do is
/// award the MVP bonus or move an MVP counter.
///
/// Null is therefore "nobody was named", never "not loaded". Naming somebody
/// later is an ordinary correction, and because no MVP entry was written there
/// is none to reverse.
class MatchResult {
  const MatchResult({
    required this.matchId,
    required this.teamAScore,
    required this.teamBScore,
    required this.mvpUserId,
    required this.goals,
  });

  final String matchId;
  final int teamAScore;
  final int teamBScore;

  /// Who was best on the pitch, or null when the organizer named nobody.
  final String? mvpUserId;

  /// One entry per scorer, and only for players who scored.
  final List<GoalTally> goals;

  /// The goals actually attributed to a player. The approved rules require this
  /// to equal [teamAScore] + [teamBScore]; nothing here enforces that, because
  /// [validateResultInputs] is where the rules are stated.
  int get recordedGoals =>
      goals.fold(0, (total, tally) => total + tally.goals);

  bool get isDraw => teamAScore == teamBScore;

  /// The side that won, or null when the match was drawn.
  TeamId? get winner {
    if (isDraw) return null;
    return teamAScore > teamBScore ? TeamId.a : TeamId.b;
  }

  /// How many goals [userId] is credited with; zero when they scored none.
  int goalsBy(String userId) {
    for (final tally in goals) {
      if (tally.userId == userId) return tally.goals;
    }
    return 0;
  }
}

/// Why a rating moved.
///
/// [reversal] is not an outcome of a match but the undoing of one: a correction
/// records the reversal of every change the previous result made rather than
/// editing what was already written.
enum RatingChangeReason { win, loss, goal, mvp, reversal }

/// One entry of the rating audit — a change that was applied, and the ratings
/// it moved between.
///
/// Immutable in the strong sense: the row behind this is never updated, and a
/// correction adds entries rather than rewriting them. [reversesId] is how a
/// reversal names what it undid, so "still in effect" stays a question the
/// history can answer on its own.
class RatingChange {
  const RatingChange({
    required this.id,
    required this.userId,
    required this.matchId,
    required this.reason,
    required this.delta,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.recordedAt,
    this.reversesId,
  });

  final String id;
  final String userId;
  final String matchId;
  final RatingChangeReason reason;

  /// The change that was *applied*, which is what makes a reversal exact. It is
  /// the approved constant except at the ends of the 0.0-10.0 range, where a
  /// player who cannot gain any more gains nothing — and giving back the
  /// constant later would invent a rating they never held.
  final double delta;

  final double ratingBefore;
  final double ratingAfter;
  final DateTime recordedAt;

  /// The entry this one undoes, or null for an entry that recorded a result.
  final String? reversesId;

  bool get isReversal => reason == RatingChangeReason.reversal;
}

/// A player's career counters, with the rating they currently hold.
///
/// The rating is read from the profile rather than stored beside the counters:
/// `users.overall_rating` is the one the engine reads (`OP-1`) and a copy here
/// would be a second number for the same thing, free to disagree with it.
class PlayerStatistics {
  const PlayerStatistics({
    required this.userId,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.goals,
    required this.mvpCount,
    required this.currentRating,
  });

  /// The counters a player starts with: someone who has played nothing has
  /// nothing recorded, and their rating is whatever their profile holds.
  const PlayerStatistics.none(this.userId, this.currentRating)
      : matchesPlayed = 0,
        wins = 0,
        losses = 0,
        draws = 0,
        goals = 0,
        mvpCount = 0;

  final String userId;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int goals;
  final int mvpCount;
  final double currentRating;
}

/// The rules a recorded result is held to, stated once.
///
/// Both the screen and the database ask the same questions of the same numbers,
/// so they are asked here rather than answered twice. Every refusal is a
/// [ValidationFailure] carrying the reason that names which number is wrong —
/// behaviour still follows the type, as OP-5 requires.
///
/// [participantIds] is who played: the stored lineup, which `KB-017` makes the
/// record of exactly that. An empty set is [FailureReason.lineupRequired] — with
/// no sides there is no winner to reward, so the result cannot be taken at all.
///
/// [mvpUserId] may be null: naming a best player is optional, and a result
/// without one is refused for nothing. Naming somebody who did not play is still
/// [FailureReason.mvpNotParticipant] — the rule was never weakened, only the
/// requirement to invoke it.
void validateResultInputs({
  required int teamAScore,
  required int teamBScore,
  required String? mvpUserId,
  required List<GoalTally> goals,
  required Set<String> participantIds,
}) {
  if (participantIds.isEmpty) {
    throw const ValidationFailure(FailureReason.lineupRequired);
  }
  if (teamAScore < 0 || teamBScore < 0) {
    throw const ValidationFailure(FailureReason.invalidScore);
  }
  if (goals.any((tally) => tally.goals <= 0)) {
    throw const ValidationFailure(FailureReason.invalidGoals);
  }
  // Two tallies for one player is not a bigger number, it is the same fact
  // recorded twice, and which of them counted would be arbitrary.
  if ({for (final tally in goals) tally.userId}.length != goals.length) {
    throw const ValidationFailure(FailureReason.invalidGoals);
  }
  final recorded = goals.fold(0, (total, tally) => total + tally.goals);
  if (recorded != teamAScore + teamBScore) {
    throw const ValidationFailure(FailureReason.goalsDoNotMatchScore);
  }
  if (mvpUserId != null && !participantIds.contains(mvpUserId)) {
    throw const ValidationFailure(FailureReason.mvpNotParticipant);
  }
  // A goal is credited to somebody who played it. Otherwise a rating could be
  // raised for a player who was never in the match.
  if (goals.any((tally) => !participantIds.contains(tally.userId))) {
    throw const ValidationFailure(FailureReason.scorerNotParticipant);
  }
}
