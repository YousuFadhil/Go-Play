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

  /// Why a match could not be read: a missing match, or one whose community the
  /// reader has not joined. Asked only after a read failed — see
  /// [MatchAccessContext].
  Future<MatchAccessContext> fetchAccessContext(String matchId) =>
      _adapter.fetchAccessContext(matchId);

  /// Creates a match. Maximum registration is derived by the database from
  /// the starting players plus the global reserve setting.
  ///
  /// [isHistorical] records a fixture the community has already played rather
  /// than scheduling one (migration `0054`). It changes exactly one thing here —
  /// which temporal rule `create_match` applies — and nothing about what
  /// follows: the participants, the two sides and the result of a recorded match
  /// are entered through the same screens and the same functions as any other
  /// match that has been played.
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    bool isHistorical = false,
  }) =>
      _adapter.createMatch(
        communityId: communityId,
        title: title.trim(),
        location: location.trim(),
        startAt: startAt,
        endAt: endAt,
        startingPlayers: startingPlayers,
        isHistorical: isHistorical,
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

  /// Roster of a match, in the authoritative participant order: the owner/admin
  /// arrangement when there is one, arrival order otherwise. Never re-sorted
  /// here — the order is a server-side rule and arrives applied.
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      _adapter.fetchRegistrations(matchId);

  /// Joins the current user to the match. Returns the resulting status
  /// (confirmed seat or reserve queue).
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      _adapter.registerForMatch(matchId);

  Future<void> withdrawFromMatch(String matchId) =>
      _adapter.withdrawFromMatch(matchId);

  // --- Administrative roster arrangement -----------------------------------------
  //
  // Only an owner or a community admin may arrange a roster, and the database
  // decides that against the caller's own session. Every rule these touch —
  // which participant starts, whether the arrangement has been activated, what
  // happens to a stored lineup — is applied in one server-side transaction, so
  // both of these are followed by a fresh read rather than a local guess.

  /// Stores the authoritative participant order of a match.
  ///
  /// [registrationIds] is every seat exactly once, starting participants first.
  /// The starting/reserve split is not sent and cannot be: the server derives
  /// it by cutting this order at the match's starting-player count.
  Future<void> setRosterOrder(String matchId, List<String> registrationIds) =>
      _adapter.setRosterOrder(matchId, registrationIds);

  /// Exchanges two participants' positions — the approved way to move somebody
  /// into a starting lineup that is already full, in either direction and for
  /// either kind of participant.
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) =>
      _adapter.swapParticipants(
        matchId,
        firstRegistrationId,
        secondRegistrationId,
      );

  // --- Professional Guests -----------------------------------------------------
  //
  // Match-scoped stand-ins with no account, no membership and no profile. Only
  // an owner or a community admin may manage them, and the database decides
  // that against the caller's own session — nothing here is trusted to have
  // checked. Capacity, the community-first ordering and the starting/reserve
  // placement are all the server's, so every one of these is followed by a
  // roster refresh rather than by a local guess.

  /// Adds a Professional Guest and returns their new id. The name is trimmed
  /// the same way every other name this service sends is.
  Future<String> addProfessionalGuest(String matchId, String name) =>
      _adapter.addProfessionalGuest(matchId, name.trim());

  /// Frees a Professional Guest's roster seat. What they did in a match that
  /// was already played is preserved by the database.
  Future<void> removeProfessionalGuest(String matchId, String guestId) =>
      _adapter.removeProfessionalGuest(matchId, guestId);

  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) =>
      _adapter.renameProfessionalGuest(matchId, guestId, name.trim());
}
