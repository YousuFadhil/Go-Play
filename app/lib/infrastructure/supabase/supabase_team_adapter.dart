import 'package:btge/btge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/teams/team_adapter.dart';
import '../../features/teams/team_models.dart';
import 'mappers/team_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the team-generation port.
///
/// The reads here are plain table reads, gated by the RLS migration `0018` put
/// in place: a lineup is a member's to read. The write goes through
/// `replace_match_lineup` (migration `0020`) because replacing a lineup has to
/// be one transaction, and that function asks the same
/// `is_match_community_admin` predicate the table's policies ask. Nothing in
/// this class decides who may do what.
class SupabaseTeamAdapter implements TeamAdapter {
  SupabaseTeamAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _assignmentColumns = 'user_id, professional_guest_id, team, '
      'assigned_position, assignment_basis';

  /// The generation set: **registered community players only**.
  ///
  /// `user_id is not null` is what keeps a Professional Guest out of the engine,
  /// and it is not a filter of convenience. A guest has no profile, so none of
  /// the Core Player Inputs §4.1 requires exists for them — no rating, no date
  /// of birth, no primary position — and §4.3 rejects a missing input rather
  /// than substituting one. They are added to a lineup after generation, never
  /// as an input to it.
  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(String matchId) =>
      guarded(() async {
        final rows = await _client
            .from('match_registrations')
            .select('user:users(id, full_name, overall_rating, date_of_birth, '
                'primary_position, secondary_position, avatar_path)')
            .eq('match_id', matchId)
            .eq('status', 'confirmed')
            .not('user_id', 'is', null)
            .order('registration_order', ascending: true);
        return [
          for (final row in rows)
            playerCoreInputsFromRow(
              row,
              // Unversioned on purpose: a pitch is a screenful of faces, and
              // busting the cache on every read would refetch all of them each
              // time the lineup is opened.
              avatarUrl: (path) => SupabaseAvatars.publicUrl(_client, path),
            ),
        ];
      });

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) =>
      guarded(() async {
        // `!inner` drops matches with no stored lineup before the limit is
        // applied, so [limit] counts lineups rather than matches.
        // Guest rows come back and are dropped in the mapper rather than
        // filtered here: the embed's filter would apply to the *match* rows, so
        // excluding them at this level would drop whole matches instead of
        // whole participants.
        final rows = await _client
            .from('matches')
            .select('start_at, assignments:match_team_assignments!inner('
                'user_id, team)')
            .eq('community_id', communityId)
            .neq('id', excludeMatchId)
            .lt('end_at', DateTime.now().toUtc().toIso8601String())
            .order('start_at', ascending: false)
            .limit(limit);
        return [for (final row in rows) pastMatchFromRow(row)];
      });

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) => guarded(() async {
        final rows = await _client
            .from('match_team_assignments')
            .select(_assignmentColumns)
            .eq('match_id', matchId)
            .order('team', ascending: true)
            .order('user_id', ascending: true);
        return [for (final row in rows) teamAssignmentFromRow(row)];
      });

  /// Replaces the stored lineup through `replace_match_lineup` (migration
  /// `0020`).
  ///
  /// One call, one transaction. Storing a lineup replaces the previous one, and
  /// doing that from here as a delete followed by an insert made it two: a
  /// failure in between destroyed the stored lineup and reported nothing about
  /// it. Every manual adjustment rewrites the whole lineup, so that window sat
  /// under routine edits until the function took it away.
  ///
  /// The function also states the permission rule rather than leaving it to be
  /// inferred. It asks `is_match_community_admin`, the same predicate `0018`
  /// gates the table's policies on, and raises `NOT_AUTHORIZED` — which the
  /// failure mapper already knows. That replaces the pre-flight check this
  /// class used to make, which existed only because a delete refused by RLS
  /// matches zero rows and succeeds silently.
  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) =>
      guarded(() async {
        await _client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            for (final assignment in lineup) teamAssignmentToRow(assignment),
          ],
        });
      });

  /// Both of these go through `set_completed_match_player` (migration `0029`).
  ///
  /// One function for adding and removing, because they are the same operation:
  /// the roster row and the lineup row move together, and whatever result the
  /// match already has is reversed and reapplied around the change so that the
  /// ratings, the player counters and the community leaderboards never describe
  /// a lineup that has moved on without them.
  ///
  /// A null team is how removal is said. The function reads it as "this player
  /// did not play after all" and takes both rows away.
  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) =>
      guarded(() async {
        await _client.rpc('set_completed_match_player', params: {
          'p_match_id': matchId,
          'p_user_id': userId,
          'p_team': teamToDb(team),
          'p_assigned_position': positionToDb(position),
        });
      });

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) =>
      guarded(() async {
        await _client.rpc('set_completed_match_player', params: {
          'p_match_id': matchId,
          'p_user_id': userId,
          'p_team': null,
          'p_assigned_position': null,
        });
      });
}
