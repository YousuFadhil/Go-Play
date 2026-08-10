import 'result_models.dart';

/// The result aggregate's port into the data provider: a match's recorded
/// result, the audit of what it did to the players' ratings, and the counters
/// that followed.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Nothing here decides anything (OP-2): whether the
/// goals add up to the score, who counts as a participant and what a win is
/// worth are answered above this layer and inside the database, never in an
/// adapter.
abstract interface class ResultAdapter {
  /// The stored result of [matchId], or null when none has been recorded.
  Future<MatchResult?> fetchResult(String matchId);

  /// Records the result of [matchId], replacing whatever was recorded before.
  ///
  /// One operation for both, because they are the same one: correcting a result
  /// reverses the rating changes and the counters the previous one produced and
  /// applies the new ones, and a separate path for the first recording would be
  /// a second chance for the two to drift. Everything it touches moves together
  /// or not at all.
  ///
  /// [mvpUserId] is null when the organizer named nobody, which the provider is
  /// expected to store as such rather than refuse.
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  });

  /// Every rating change [matchId] produced, oldest first — including the
  /// reversals a correction added. Nothing is ever removed from it.
  Future<List<RatingChange>> fetchRatingHistory(String matchId);

  /// The counters of [userId], with the rating they currently hold. A player who
  /// has not finished a match yet has counters of zero rather than nothing.
  Future<PlayerStatistics> fetchStatistics(String userId);
}
