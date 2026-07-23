import 'package:supabase_flutter/supabase_flutter.dart';

import 'match_models.dart';

/// Typed errors raised by the registration RPCs.
enum RegistrationError {
  overlappingMatch,
  matchClosed,
  alreadyRegistered,
  notRegistered,
}

class RegistrationException implements Exception {
  const RegistrationException(this.error);

  final RegistrationError error;
}

/// Typed errors raised by the organizer management RPCs.
enum ManageError {
  notOrganizer,
  matchReadOnly,
  matchCompleted,
  matchHasPlayers,
  invalidTimeRange,
  invalidMaxPlayers,
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
      'id, group_id, created_by, location, start_at, end_at, '
      'max_players, status, title, description';

  /// Matches of one group, newest scheduled first.
  Future<List<Match>> fetchGroupMatches(String groupId) async {
    final rows = await _client
        .from('matches')
        .select(_columns)
        .eq('group_id', groupId)
        .order('start_at', ascending: false);
    return [for (final row in rows) Match.fromJson(row)];
  }

  /// Upcoming, non-cancelled matches across all my groups (RLS scopes
  /// visibility to groups the user belongs to).
  Future<List<Match>> fetchUpcomingMatches() async {
    final rows = await _client
        .from('matches')
        .select('$_columns, group:groups(name)')
        .gte('start_at', DateTime.now().toUtc().toIso8601String())
        .neq('status', MatchStatus.cancelled.dbValue)
        .order('start_at', ascending: true);
    return [for (final row in rows) Match.fromJson(row)];
  }

  Future<Match> fetchMatch(String matchId) async {
    final row = await _client
        .from('matches')
        .select('$_columns, group:groups(name)')
        .eq('id', matchId)
        .single();
    return Match.fromJson(row);
  }

  Future<void> createMatch({
    required String groupId,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int maxPlayers,
  }) async {
    await _client.from('matches').insert({
      'group_id': groupId,
      'created_by': _client.auth.currentUser!.id,
      'location': location.trim(),
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'max_players': maxPlayers,
    });
  }

  // --- Organizer management (all via transactional, race-safe RPCs) ---

  /// Edits match details. Reducing the player limit demotes the latest
  /// confirmed players to reserve and notifies everyone affected.
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int maxPlayers,
    String? description,
  }) async {
    await _manage('update_match', {
      'p_match_id': matchId,
      'p_title': title,
      'p_location': location.trim(),
      'p_start_at': startAt.toUtc().toIso8601String(),
      'p_end_at': endAt.toUtc().toIso8601String(),
      'p_max_players': maxPlayers,
      'p_description': description,
    });
  }

  Future<void> removePlayer(String matchId, String userId) =>
      _manage('remove_player', {'p_match_id': matchId, 'p_user_id': userId});

  Future<void> cancelMatch(String matchId) =>
      _manage('cancel_match', {'p_match_id': matchId});

  Future<void> postponeMatch(String matchId) =>
      _manage('postpone_match', {'p_match_id': matchId});

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
    if (m.contains('MATCH_READ_ONLY')) {
      return const ManageException(ManageError.matchReadOnly);
    }
    if (m.contains('MATCH_COMPLETED')) {
      return const ManageException(ManageError.matchCompleted);
    }
    if (m.contains('MATCH_HAS_PLAYERS')) {
      return const ManageException(ManageError.matchHasPlayers);
    }
    if (m.contains('INVALID_TIME_RANGE')) {
      return const ManageException(ManageError.invalidTimeRange);
    }
    if (m.contains('INVALID_MAX_PLAYERS')) {
      return const ManageException(ManageError.invalidMaxPlayers);
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
    return e;
  }
}
