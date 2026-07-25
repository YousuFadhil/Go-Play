import 'package:supabase_flutter/supabase_flutter.dart';

import 'match_models.dart';

/// Typed errors raised by the registration RPCs.
enum RegistrationError {
  overlappingMatch,
  matchClosed,
  alreadyRegistered,
  notRegistered,
  registrationClosed,
  matchLocked,
}

class RegistrationException implements Exception {
  const RegistrationException(this.error);

  final RegistrationError error;
}

/// Typed errors raised by the organizer management RPCs.
enum ManageError {
  notOrganizer,
  matchCompleted,
  matchLocked,
  invalidTimeRange,
  invalidStartingPlayers,
  maxBelowRegistered,
  notRegistered,
}

class ManageException implements Exception {
  const ManageException(this.error);

  final ManageError error;
}

/// Data access for matches. Single-row writes use direct inserts/updates
/// guarded by RLS; multi-step registration logic (Sprint 4) will use RPCs.
class MatchService {
  MatchService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _columns =
      'id, community_id, created_by, location, start_at, end_at, '
      'starting_players, max_registration, status, title, description';

  /// Matches of one group, newest scheduled first.
  Future<List<Match>> fetchGroupMatches(String communityId) async {
    final rows = await _client
        .from('matches')
        .select(_columns)
        .eq('community_id', communityId)
        .order('start_at', ascending: false);
    return [for (final row in rows) Match.fromJson(row)];
  }

  /// Upcoming (not yet ended) matches across all my groups. RLS scopes
  /// visibility to groups the user belongs to.
  Future<List<Match>> fetchUpcomingMatches() async {
    final rows = await _client
        .from('matches')
        .select('$_columns, community:communities(name)')
        .gt('end_at', DateTime.now().toUtc().toIso8601String())
        .order('start_at', ascending: true);
    return [for (final row in rows) Match.fromJson(row)];
  }

  Future<Match> fetchMatch(String matchId) async {
    final row = await _client
        .from('matches')
        .select('$_columns, community:communities(name)')
        .eq('id', matchId)
        .single();
    return Match.fromJson(row);
  }

  /// Creates a match. Maximum registration is derived by the database from
  /// the starting players plus the global reserve setting.
  Future<void> createMatch({
    required String communityId,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) async {
    await _client.from('matches').insert({
      'community_id': communityId,
      'created_by': _client.auth.currentUser!.id,
      'location': location.trim(),
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'starting_players': startingPlayers,
    });
  }

  // --- Organizer management (all via transactional, race-safe RPCs) ---

  /// Edits match details. Changing the starting-player count re-sorts the
  /// roster (demotions and promotions) and notifies everyone affected.
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) async {
    await _manage('update_match', {
      'p_match_id': matchId,
      'p_title': title,
      'p_location': location.trim(),
      'p_start_at': startAt.toUtc().toIso8601String(),
      'p_end_at': endAt.toUtc().toIso8601String(),
      'p_starting_players': startingPlayers,
      'p_description': description,
    });
  }

  Future<void> removePlayer(String matchId, String userId) =>
      _manage('remove_player', {'p_match_id': matchId, 'p_user_id': userId});

  /// Deletes a match that is not completed, after notifying registered players.
  Future<void> deleteMatch(String matchId) =>
      _manage('delete_match', {'p_match_id': matchId});

  Future<void> _manage(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw _mapManageError(e);
    }
  }

  Exception _mapManageError(PostgrestException e) {
    final m = e.message;
    if (m.contains('NOT_ORGANIZER')) {
      return const ManageException(ManageError.notOrganizer);
    }
    if (m.contains('MATCH_COMPLETED')) {
      return const ManageException(ManageError.matchCompleted);
    }
    if (m.contains('MATCH_LOCKED')) {
      return const ManageException(ManageError.matchLocked);
    }
    if (m.contains('MAX_BELOW_REGISTERED')) {
      return const ManageException(ManageError.maxBelowRegistered);
    }
    if (m.contains('INVALID_STARTING_PLAYERS')) {
      return const ManageException(ManageError.invalidStartingPlayers);
    }
    if (m.contains('INVALID_TIME_RANGE')) {
      return const ManageException(ManageError.invalidTimeRange);
    }
    if (m.contains('NOT_REGISTERED')) {
      return const ManageException(ManageError.notRegistered);
    }
    return e;
  }

  /// Roster of a match, in registration order.
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async {
    final rows = await _client
        .from('match_registrations')
        .select('status, registration_order, '
            'user:users(id, full_name, primary_position)')
        .eq('match_id', matchId)
        .order('registration_order', ascending: true);
    return [for (final row in rows) MatchRegistration.fromJson(row)];
  }

  /// Joins the current user to the match. Returns the resulting status
  /// (confirmed seat or reserve queue).
  Future<RegistrationStatus> registerForMatch(String matchId) async {
    try {
      final result = await _client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      return RegistrationStatus.fromDb(result as String);
    } on PostgrestException catch (e) {
      throw _mapRegistrationError(e);
    }
  }

  Future<void> withdrawFromMatch(String matchId) async {
    try {
      await _client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});
    } on PostgrestException catch (e) {
      throw _mapRegistrationError(e);
    }
  }

  Exception _mapRegistrationError(PostgrestException e) {
    if (e.message.contains('OVERLAPPING_MATCH')) {
      return const RegistrationException(RegistrationError.overlappingMatch);
    }
    if (e.message.contains('MATCH_CLOSED')) {
      return const RegistrationException(RegistrationError.matchClosed);
    }
    if (e.message.contains('ALREADY_REGISTERED')) {
      return const RegistrationException(RegistrationError.alreadyRegistered);
    }
    if (e.message.contains('NOT_REGISTERED')) {
      return const RegistrationException(RegistrationError.notRegistered);
    }
    if (e.message.contains('REGISTRATION_CLOSED')) {
      return const RegistrationException(RegistrationError.registrationClosed);
    }
    if (e.message.contains('MATCH_LOCKED')) {
      return const RegistrationException(RegistrationError.matchLocked);
    }
    return e;
  }
}
