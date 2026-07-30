import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/matches/match_adapter.dart';
import '../../features/matches/match_models.dart';
import 'mappers/match_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the match port. Creation is a direct insert
/// guarded by RLS; everything that touches a roster is a transactional,
/// race-safe RPC.
class SupabaseMatchAdapter implements MatchAdapter {
  SupabaseMatchAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static const _columns =
      'id, community_id, created_by, location, start_at, end_at, '
      'starting_players, max_registration, status, title, description';

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      guarded(() async {
        final rows = await _client
            .from('matches')
            .select(_columns)
            .eq('community_id', communityId)
            .order('start_at', ascending: false);
        return [for (final row in rows) matchFromRow(row)];
      });

  @override
  Future<List<Match>> fetchUpcomingMatches() => guarded(() async {
        final rows = await _client
            .from('matches')
            .select('$_columns, community:communities(name)')
            .gt('end_at', DateTime.now().toUtc().toIso8601String())
            .order('start_at', ascending: true);
        return [for (final row in rows) matchFromRow(row)];
      });

  @override
  Future<Match> fetchMatch(String matchId) => guarded(() async {
        final row = await _client
            .from('matches')
            .select('$_columns, community:communities(name)')
            .eq('id', matchId)
            .single();
        return matchFromRow(row);
      });

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) =>
      guarded(() async {
        await _client.from('matches').insert({
          'community_id': communityId,
          'created_by': _client.auth.currentUser!.id,
          'title': title,
          'location': location,
          'start_at': startAt.toUtc().toIso8601String(),
          'end_at': endAt.toUtc().toIso8601String(),
          'starting_players': startingPlayers,
        });
      });

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) =>
      guarded(() async {
        await _client.rpc('update_match', params: {
          'p_match_id': matchId,
          'p_title': title,
          'p_location': location,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
          'p_starting_players': startingPlayers,
          'p_description': description,
        });
      });

  @override
  Future<void> deleteMatch(String matchId) => guarded(() async {
        await _client.rpc('delete_match', params: {'p_match_id': matchId});
      });

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      guarded(() async {
        final rows = await _client
            .from('match_registrations')
            .select('status, registration_order, '
                'user:users(id, full_name, primary_position)')
            .eq('match_id', matchId)
            .order('registration_order', ascending: true);
        return [for (final row in rows) matchRegistrationFromRow(row)];
      });

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      guarded(() async {
        final result = await _client
            .rpc('register_for_match', params: {'p_match_id': matchId});
        return registrationStatusFromDb(result as String);
      });

  @override
  Future<void> withdrawFromMatch(String matchId) => guarded(() async {
        await _client
            .rpc('withdraw_from_match', params: {'p_match_id': matchId});
      });

  @override
  Future<void> removePlayer(String matchId, String userId) => guarded(() async {
        await _client.rpc('remove_player', params: {
          'p_match_id': matchId,
          'p_user_id': userId,
        });
      });

  @override
  Future<int?> fetchReservePlayers() => guarded(() async {
        final row = await _client
            .from('app_settings')
            .select('reserve_players')
            .limit(1)
            .maybeSingle();
        return row?['reserve_players'] as int?;
      });
}
