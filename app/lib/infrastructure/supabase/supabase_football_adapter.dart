import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/football/football_adapter.dart';
import '../../features/football/football_models.dart';
import 'mappers/football_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the public-football port.
///
/// Every read here goes through a view added by migration `0057`, and that is
/// the design rather than a convenience. The five relations below are not
/// `security_invoker`, so they execute with the view owner's privileges and
/// answer a caller who is in no community at all — which is what makes
/// cross-community football history readable without loosening a single policy
/// on `matches`, `match_results`, `match_team_assignments` or
/// `community_statistics`.
///
/// The views also decide what is given. None carries a phone, an email, an
/// authentication identifier, a date of birth, a join code, or the organizer and
/// recorder of a match — so there is no column list here that could accidentally
/// ask for one, and every projection below is written out by name rather than
/// with `*` for the same reason.
class SupabaseFootballAdapter implements FootballAdapter {
  SupabaseFootballAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _matchColumns =
      'match_id, community_id, community_name, title, location, start_at, '
      'end_at, is_historical, has_result, team_a_score, team_b_score, '
      'mvp_participant_type, mvp_user_id, mvp_professional_guest_id, '
      'mvp_display_name, mvp_avatar_path';

  /// The identity columns the two match-scoped views share, named once so the
  /// roster and the lineup cannot drift into reading different things about the
  /// same participant.
  static const _participantColumns =
      'participant_type, user_id, professional_guest_id, display_name, '
      'avatar_path, primary_position, secondary_position, overall_rating';

  static const _rosterColumns =
      'match_id, status, roster_position, $_participantColumns';

  static const _lineupColumns =
      'match_id, team, assigned_position, is_out_of_position, goals, is_mvp, '
      '$_participantColumns';

  static const _communityStatsColumns =
      'community_id, community_name, completed_matches, players, goals, '
      'mvp_count';

  static const _playerStatsColumns =
      'community_id, user_id, display_name, avatar_path, primary_position, '
      'secondary_position, overall_rating, matches_played, wins, draws, '
      'losses, goals, mvp_count';

  /// Unversioned avatar URLs throughout this adapter, as everywhere a list of
  /// faces is read: a roster is a screenful of pictures, and busting the cache
  /// on every read would refetch all of them each time.
  String? _avatar(String? path) => SupabaseAvatars.publicUrl(_client, path);

  /// Most recent first: football history is read backwards from now.
  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) =>
      guarded(
        () async {
          var query = _client
              .from('v_football_completed_matches')
              .select(_matchColumns);
          if (communityId != null) {
            query = query.eq('community_id', communityId);
          }
          final rows =
              await query.order('start_at', ascending: false).limit(limit);
          return [
            for (final row in rows)
              completedMatchFromRow(row, avatarUrl: _avatar),
          ];
        },
        operation: 'select v_football_completed_matches',
      );

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) => guarded(
        () async {
          final row = await _client
              .from('v_football_completed_matches')
              .select(_matchColumns)
              .eq('match_id', matchId)
              .maybeSingle();
          if (row == null) throw const NotFoundFailure();
          return completedMatchFromRow(row, avatarUrl: _avatar);
        },
        operation: 'select v_football_completed_matches by id',
      );

  /// Ordered by the saved roster position, which is the organizer's arrangement
  /// where there is one and arrival order where there is not (migration `0053`).
  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) => guarded(
        () async {
          final rows = await _client
              .from('v_football_match_participants')
              .select(_rosterColumns)
              .eq('match_id', matchId)
              .order('roster_position', ascending: true);
          return [
            for (final row in rows)
              matchRosterEntryFromRow(row, avatarUrl: _avatar),
          ];
        },
        operation: 'select v_football_match_participants',
      );

  /// Ordered by side, then by name, so the two teams read in a stable order.
  /// Which side leads is presentation and stays above this layer; this only
  /// guarantees the order does not change between two reads of the same match.
  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) => guarded(
        () async {
          final rows = await _client
              .from('v_football_match_lineup')
              .select(_lineupColumns)
              .eq('match_id', matchId)
              .order('team', ascending: true)
              .order('display_name', ascending: true);
          return [
            for (final row in rows) lineupSlotFromRow(row, avatarUrl: _avatar),
          ];
        },
        operation: 'select v_football_match_lineup',
      );

  @override
  Future<CommunityFootballStats> fetchCommunityStats(String communityId) =>
      guarded(
        () async {
          final row = await _client
              .from('v_football_community_stats')
              .select(_communityStatsColumns)
              .eq('community_id', communityId)
              .maybeSingle();
          if (row == null) throw const NotFoundFailure();
          return communityFootballStatsFromRow(row);
        },
        operation: 'select v_football_community_stats',
      );

  @override
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
    String communityId,
  ) =>
      guarded(
        () async {
          final rows = await _client
              .from('v_football_community_player_stats')
              .select(_playerStatsColumns)
              .eq('community_id', communityId);
          return [
            for (final row in rows)
              communityPlayerStatsFromRow(row, avatarUrl: _avatar),
          ];
        },
        operation: 'select v_football_community_player_stats',
      );
}
