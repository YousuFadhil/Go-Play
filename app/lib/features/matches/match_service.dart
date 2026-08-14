import '../../core/diagnostics.dart';
import '../../infrastructure/supabase/supabase_match_adapter.dart';
import 'match_adapter.dart';
import 'match_models.dart';

/// Data access for matches: the schedule, the roster, registration, and the
/// global reserve setting.
///
/// Everything provider-specific is behind [MatchAdapter]. Capacity, locking
/// and promotion from the reserve queue are enforced by the database and read
/// back off the domain model, so nothing here recomputes them.
class MatchService {
  MatchService([MatchAdapter? adapter])
      : _adapter = adapter ?? SupabaseMatchAdapter();

  final MatchAdapter _adapter;

  /// Matches of one community, newest scheduled first.
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      _adapter.fetchCommunityMatches(communityId);

  /// Upcoming (not yet ended) matches across all my communities.
  Future<List<Match>> fetchUpcomingMatches() => _adapter.fetchUpcomingMatches();

  Future<Match> fetchMatch(String matchId) => _adapter.fetchMatch(matchId);

  /// Creates a match. Maximum registration is derived by the database from
  /// the starting players plus the global reserve setting.
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) =>
      _adapter.createMatch(
        communityId: communityId,
        title: title.trim(),
        location: location.trim(),
        startAt: startAt,
        endAt: endAt,
        startingPlayers: startingPlayers,
      );

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
  }) =>
      _adapter.updateMatch(
        matchId: matchId,
        title: title,
        location: location.trim(),
        startAt: startAt,
        endAt: endAt,
        startingPlayers: startingPlayers,
        description: description,
      );

  Future<void> removePlayer(String matchId, String userId) =>
      _adapter.removePlayer(matchId, userId);

  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      _adapter.addPlayerToMatch(matchId, userId);

  /// Deletes a match, after notifying registered players.
  ///
  /// Completion is no bar to it: `delete_match` has never checked, and the
  /// `before delete on matches` trigger gives back every rating and counter the
  /// match's result produced, so a played match is no harder to remove than an
  /// empty one — only tidier to.
  Future<void> deleteMatch(String matchId) async {
    Diagnostics.trace('service', 'deleteMatch $matchId');
    try {
      await _adapter.deleteMatch(matchId);
      Diagnostics.trace('service', 'deleteMatch ok');
    } catch (error) {
      Diagnostics.trace('service', 'deleteMatch threw $error');
      rethrow;
    }
  }

  /// The global reserve allowance. Capacity is enforced server-side; this is
  /// only so the create/edit screens can show the derived maximum.
  Future<int?> fetchReservePlayers() => _adapter.fetchReservePlayers();

  /// Roster of a match, in registration order.
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      _adapter.fetchRegistrations(matchId);

  /// Joins the current user to the match. Returns the resulting status
  /// (confirmed seat or reserve queue).
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      _adapter.registerForMatch(matchId);

  Future<void> withdrawFromMatch(String matchId) =>
      _adapter.withdrawFromMatch(matchId);
}
