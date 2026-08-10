import '../../../core/failures.dart';
import '../../../features/results/result_models.dart';
import 'team_mapper.dart';

// Conversion between Supabase rows and the result Domain Models.
//
// Every column name this aggregate reads or writes appears here and nowhere else
// (OP-3). `change_reason` is constrained by migration `0022`, so a value outside
// its vocabulary means the database and this build disagree about the schema —
// an infrastructure fault rather than something to guess at, exactly as an
// unreadable assigned position is.
//
// `ratingFromDb` is reused from the team mapper: `numeric` reaches the client as
// a JSON number or as its text form depending on the transport, and a rating, a
// delta and a rating boundary are all the same problem.

RatingChangeReason ratingChangeReasonFromDb(String value) => switch (value) {
      'WIN' => RatingChangeReason.win,
      'LOSS' => RatingChangeReason.loss,
      'GOAL' => RatingChangeReason.goal,
      'MVP' => RatingChangeReason.mvp,
      'REVERSAL' => RatingChangeReason.reversal,
      _ => throw const InfrastructureFailure(),
    };

/// Reads a result row joined with its goals.
///
/// A match with no goals joins to an empty list, which is the whole of "nobody
/// scored" — there is no row saying so and none is expected.
///
/// `mvp_user_id` is nullable since migration `0033`, and a null is read as what
/// it is: a result whose organizer named nobody best on the pitch.
MatchResult matchResultFromRow(Map<String, dynamic> row) {
  final goals = (row['goals'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  return MatchResult(
    matchId: row['match_id'] as String,
    teamAScore: row['team_a_score'] as int,
    teamBScore: row['team_b_score'] as int,
    mvpUserId: row['mvp_user_id'] as String?,
    goals: [for (final goal in goals) goalTallyFromRow(goal)],
  );
}

GoalTally goalTallyFromRow(Map<String, dynamic> row) => GoalTally(
      userId: row['user_id'] as String,
      goals: row['goals'] as int,
    );

/// One scorer, as `record_match_result` reads them.
///
/// No `match_id`: the match is an argument of that function, which is what keeps
/// a tally from naming a different match than the one being authorized.
Map<String, dynamic> goalTallyToRow(GoalTally tally) => {
      'user_id': tally.userId,
      'goals': tally.goals,
    };

RatingChange ratingChangeFromRow(Map<String, dynamic> row) => RatingChange(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      matchId: row['match_id'] as String,
      reason: ratingChangeReasonFromDb(row['change_reason'] as String),
      delta: ratingFromDb(row['delta']),
      ratingBefore: ratingFromDb(row['rating_before']),
      ratingAfter: ratingFromDb(row['rating_after']),
      recordedAt: DateTime.parse(row['created_at'] as String).toLocal(),
      reversesId: row['reverses_id'] as String?,
    );

/// Reads a `v_user_profile` row: the profile and its counters, flat.
///
/// The row carries the current rating because that is where it lives (`OP-1`),
/// and the counters beside it. The view LEFT-joins them, so every counter column
/// is null together until the player has finished a match. A player with no
/// counters has counters of zero, not no statistics — so the absence is read as
/// the starting point rather than as a missing record.
///
/// `matches_played` is the sentinel for that absence. Every counter is `not
/// null` in `player_statistics`, so a null here can only mean the LEFT join
/// found nothing; testing one column rather than all six says the same thing
/// once.
PlayerStatistics playerStatisticsFromRow(Map<String, dynamic> row) {
  final userId = row['user_id'] as String;
  final rating = ratingFromDb(row['overall_rating']);
  final matchesPlayed = row['matches_played'] as int?;
  if (matchesPlayed == null) return PlayerStatistics.none(userId, rating);

  return PlayerStatistics(
    userId: userId,
    matchesPlayed: matchesPlayed,
    wins: row['wins'] as int,
    losses: row['losses'] as int,
    draws: row['draws'] as int,
    goals: row['goals'] as int,
    mvpCount: row['mvp_count'] as int,
    currentRating: rating,
  );
}
