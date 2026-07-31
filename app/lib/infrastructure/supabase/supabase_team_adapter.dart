import 'package:btge/btge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/teams/team_adapter.dart';
import '../../features/teams/team_models.dart';
import 'mappers/team_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the team-generation port.
///
/// Everything here is a plain table read or write. Migration `0018` put the
/// permission rules in RLS — members read a lineup, community admins write
/// one — so there is no RPC to call and no permission for this class to check.
class SupabaseTeamAdapter implements TeamAdapter {
  SupabaseTeamAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _assignmentColumns =
      'user_id, team, assigned_position, assignment_basis';

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(String matchId) =>
      guarded(() async {
        final rows = await _client
            .from('match_registrations')
            .select('user:users(id, full_name, overall_rating, date_of_birth, '
                'primary_position, secondary_position)')
            .eq('match_id', matchId)
            .eq('status', 'confirmed')
            .order('registration_order', ascending: true);
        return [for (final row in rows) playerCoreInputsFromRow(row)];
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
        final rows = await _client
            .from('matches')
            .select('start_at, '
                'assignments:match_team_assignments!inner(user_id, team)')
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

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) =>
      guarded(() async {
        // Replace rather than upsert: a shrunken roster must not leave a
        // stale row behind, and clearing first is also what keeps the
        // one-goalkeeper-per-team index from tripping on an intermediate
        // state while two lineups overlap.
        await _client
            .from('match_team_assignments')
            .delete()
            .eq('match_id', matchId);
        if (lineup.isEmpty) return;
        await _client.from('match_team_assignments').insert([
          for (final assignment in lineup)
            teamAssignmentToRow(matchId, assignment),
        ]);
      });
}
