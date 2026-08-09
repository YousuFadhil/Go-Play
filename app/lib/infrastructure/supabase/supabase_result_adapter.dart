import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/results/result_adapter.dart';
import '../../features/results/result_models.dart';
import 'mappers/result_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the result port.
///
/// The reads are plain table reads, gated by the RLS migration `0022` put in
/// place: a result, its goals and the ratings it moved are a member's to read.
/// The write goes through `record_match_result` because it is not one write —
/// the previous result's effects come off, the new result goes on, every rating
/// change is recorded and every counter is adjusted, and a client that could do
/// half of that could leave a match with the new score and the old ratings.
///
/// The rating arithmetic is deliberately not here. `OP-1` makes the rating
/// system-managed, so no policy lets this class write `users.overall_rating` and
/// nothing in it decides what a win is worth.
class SupabaseResultAdapter implements ResultAdapter {
  SupabaseResultAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _resultColumns =
      'match_id, team_a_score, team_b_score, mvp_user_id, '
      'goals:match_goals(user_id, goals)';

  static const _ratingColumns =
      'id, user_id, match_id, change_reason, delta, rating_before, '
      'rating_after, reverses_id, created_at';

  @override
  Future<MatchResult?> fetchResult(String matchId) => guarded(() async {
        final row = await _client
            .from('match_results')
            .select(_resultColumns)
            .eq('match_id', matchId)
            .maybeSingle();
        if (row == null) return null;
        return matchResultFromRow(row);
      });

  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) =>
      guarded(() async {
        // Null is sent rather than omitted: `p_mvp_user_id` has no default, and
        // leaving it out would be a call the function does not have a signature
        // for. Migration `0033` is what makes the null acceptable to it.
        await _client.rpc('record_match_result', params: {
          'p_match_id': matchId,
          'p_team_a_score': teamAScore,
          'p_team_b_score': teamBScore,
          'p_mvp_user_id': mvpUserId,
          'p_goals': [for (final tally in goals) goalTallyToRow(tally)],
        });
      });

  /// Oldest first, so the audit reads in the order it happened: what a result
  /// did, then the reversal of each of those changes, then what replaced them.
  /// The order is `entry_no` rather than `created_at`, because a whole recording
  /// happens in one transaction and shares one timestamp.
  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) =>
      guarded(() async {
        final rows = await _client
            .from('rating_history')
            .select(_ratingColumns)
            .eq('match_id', matchId)
            .order('entry_no', ascending: true);
        return [for (final row in rows) ratingChangeFromRow(row)];
      });

  /// Reads the profile and its counters together, through `v_user_profile`
  /// (migration `0025`).
  ///
  /// The profile is the row that must exist — it holds the current rating — and
  /// the counters may be absent, because a player who has not finished a match
  /// has none yet. That absence is the starting point, not a missing record, and
  /// the mapper reads it as such.
  ///
  /// **`v_player_statistics` is deliberately not the source here.** It joins
  /// `player_statistics` to `users` with an INNER join, so a player with no
  /// counters is not in it at all — this read would answer `NotFoundFailure`
  /// for every player who has yet to finish a match, which is the ordinary case
  /// and not an error. `v_user_profile` LEFT-joins the same two tables, which is
  /// the shape this read has always had. The other view is the career record of
  /// players who have one, and belongs to the leaderboard reads that migration
  /// `0025` defers.
  ///
  /// The view is `security_invoker = on`, so the policies that governed the
  /// previous embed still govern this: `authenticated_select_active_users` on
  /// `users`, which is the stricter of the two and therefore what decides
  /// whether a row comes back at all.
  @override
  Future<PlayerStatistics> fetchStatistics(String userId) => guarded(() async {
        final row = await _client
            .from('v_user_profile')
            .select('user_id, overall_rating, matches_played, wins, losses, '
                'draws, goals, mvp_count')
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) throw const NotFoundFailure();
        return playerStatisticsFromRow(row);
      });
}
