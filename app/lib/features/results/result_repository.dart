import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_result_adapter.dart';
import '../teams/team_models.dart';
import 'result_adapter.dart';
import 'result_models.dart';

/// Data access for a match's result, and for what recording it did.
///
/// The rules are checked here before anything is sent, so an organizer is told
/// which number is wrong rather than being handed a refusal from a round trip.
/// The database asks the same questions again — it is the only writer, and the
/// one that has to be right — and this asking first is a convenience, never the
/// enforcement.
class ResultRepository {
  ResultRepository([ResultAdapter? adapter])
      : _adapter = adapter ?? SupabaseResultAdapter();

  final ResultAdapter _adapter;

  /// The recorded result of a match, or null when it has none yet.
  Future<MatchResult?> fetchResult(String matchId) =>
      _adapter.fetchResult(matchId);

  /// Records the result of [matchId], replacing any result already recorded.
  ///
  /// [lineup] is who played — the stored lineup, which `KB-017` makes the record
  /// of exactly that. It is what the MVP and the scorers are checked against and
  /// what says which side each of them was on, so it is passed in rather than
  /// guessed at: a result belongs to the lineup that produced it.
  ///
  /// A correction takes this same path. The reversal of the previous rating
  /// changes and counters, and the application of the new ones, all happen
  /// inside one database transaction — there is no state in which a match has
  /// the new score and the old ratings.
  ///
  /// [mvpUserId] is optional. A result saved without one is saved in full — the
  /// score, the goals, and every rating change that follows from them — and the
  /// only thing it omits is the MVP award and the MVP counter. Naming somebody
  /// afterwards is an ordinary correction through this same method.
  ///
  /// Throws [ValidationFailure] carrying the reason that names the number at
  /// fault: [FailureReason.lineupRequired] when the match has no stored lineup,
  /// [FailureReason.invalidScore], [FailureReason.invalidGoals],
  /// [FailureReason.goalsDoNotMatchScore], [FailureReason.mvpNotParticipant] or
  /// [FailureReason.scorerNotParticipant].
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
    required List<TeamAssignment> lineup,
  }) async {
    validateResultInputs(
      teamAScore: teamAScore,
      teamBScore: teamBScore,
      mvpUserId: mvpUserId,
      goals: goals,
      participantIds: {for (final assignment in lineup) assignment.userId},
    );

    await _adapter.recordResult(
      matchId: matchId,
      teamAScore: teamAScore,
      teamBScore: teamBScore,
      mvpUserId: mvpUserId,
      goals: goals,
    );
  }

  /// Every rating change a match produced, oldest first.
  ///
  /// A corrected match keeps all of it: what was recorded, the reversal of each
  /// of those changes, and what replaced them. That is the point of an audit,
  /// so nothing here filters it down to what is currently in effect.
  Future<List<RatingChange>> fetchRatingHistory(String matchId) =>
      _adapter.fetchRatingHistory(matchId);

  /// The counters and current rating of one player.
  Future<PlayerStatistics> fetchStatistics(String userId) =>
      _adapter.fetchStatistics(userId);
}
