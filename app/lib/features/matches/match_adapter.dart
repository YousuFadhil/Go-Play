import 'match_models.dart';

/// The match aggregate's port into the data provider: matches, their roster,
/// registration, and the global reserve setting.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Capacity, locking and promotion from the reserve
/// queue are enforced by the database and expressed in the domain model — an
/// adapter neither decides nor recomputes them (OP-2).
abstract interface class MatchAdapter {
  /// Matches of one community, newest scheduled first.
  Future<List<Match>> fetchCommunityMatches(String communityId);

  /// Matches that have not ended yet, across the user's communities.
  Future<List<Match>> fetchUpcomingMatches();

  Future<Match> fetchMatch(String matchId);

  /// Creates a match. Maximum registration is derived by the database from the
  /// starting players plus the global reserve setting.
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  });

  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  });

  Future<void> deleteMatch(String matchId);

  /// Roster of a match, in registration order.
  Future<List<MatchRegistration>> fetchRegistrations(String matchId);

  /// Registers the signed-in user and returns the seat they were given.
  Future<RegistrationStatus> registerForMatch(String matchId);

  Future<void> withdrawFromMatch(String matchId);

  Future<void> removePlayer(String matchId, String userId);

  /// The stored reserve allowance, or null when none is configured.
  Future<int?> fetchReservePlayers();
}
