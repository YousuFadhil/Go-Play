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

  /// Why [matchId] could not be read, when the reason is membership.
  ///
  /// Asked only after a read came back empty. It answers a question about the
  /// caller and about the community, never about the match — see
  /// [MatchAccessContext].
  Future<MatchAccessContext> fetchAccessContext(String matchId);

  /// Creates a match. Maximum registration is derived by the database from the
  /// starting players plus the global reserve setting.
  /// [isHistorical] records a fixture that has already been played, and is what
  /// selects the temporal rule the database applies: an ordinary match must
  /// start in the future, a historical one must already have ended.
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    bool isHistorical,
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

  /// Roster of a match, in the authoritative participant order.
  ///
  /// That order is the owner/admin arrangement when the match has one and
  /// arrival order otherwise, and it is computed server-side by the same
  /// expression the starting/reserve split is cut over. An implementation
  /// returns it as it came; nothing above re-sorts it.
  Future<List<MatchRegistration>> fetchRegistrations(String matchId);

  /// Registers the signed-in user and returns the seat they were given.
  Future<RegistrationStatus> registerForMatch(String matchId);

  Future<void> withdrawFromMatch(String matchId);

  Future<void> removePlayer(String matchId, String userId);

  /// Registers [userId] in the match on an owner/admin's behalf.
  ///
  /// The same registration as a player doing it themselves — same capacity,
  /// reserve, ordering, overlap and duplicate rules — so it answers with the
  /// same `confirmed`/`reserve` the player would have got. Who is allowed to
  /// ask is decided in the database against the caller's own session; nothing
  /// here is trusted to have checked.
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId);

  // --- Administrative roster arrangement --------------------------------------
  //
  // Two operations, both owner/admin only and both decided in the database
  // against the caller's own session. Neither carries a seat: starting and
  // reserve are derived from position by the server cutting one order at
  // `starting_players`, so there is no input either could take that produces
  // more starting participants than the match has starting slots.
  //
  // The first arrangement of a match activates administrative ordering for the
  // rest of its life. That is the server's decision to record, not something an
  // implementation here flags.

  /// Writes the authoritative participant order of [matchId].
  ///
  /// [registrationIds] is every seat of the match exactly once, starting
  /// participants first. Sending the whole order rather than a move is what
  /// makes a roster that changed underneath refusable: the server compares the
  /// list against its own participants and refuses a mismatch instead of
  /// applying it to a roster the caller never saw.
  Future<void> setRosterOrder(String matchId, List<String> registrationIds);

  /// Exchanges the positions of two seats.
  ///
  /// The approved mechanism for moving a participant into a full starting
  /// lineup: two positions are exchanged, so the number above the cut is the
  /// number that was above it. Works in either direction and for either kind of
  /// participant, because both are seats in one order.
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  );

  // --- Professional Guests ---------------------------------------------------
  //
  // A guest is match-scoped and has no account, so these three name a match and
  // a guest id and nothing else. Who may call them is decided in the database
  // against the caller's own session, and none of them asks whether the match
  // has started or finished: an owner or admin manages guests in every state,
  // which is the approved rule and is enforced server-side.

  /// Adds a Professional Guest to [matchId] and returns their new id.
  ///
  /// The seat they land in — starting or reserve — is the database's decision,
  /// so it is read back with the roster rather than inferred here.
  Future<String> addProfessionalGuest(String matchId, String name);

  /// Removes a Professional Guest from the **current roster**.
  ///
  /// Anything they did in a match that was played — the side they were on, the
  /// goals they scored, an MVP award — is preserved. This frees their seat, it
  /// does not erase them from the record.
  Future<void> removeProfessionalGuest(String matchId, String guestId);

  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  );

  /// The stored reserve allowance, or null when none is configured.
  Future<int?> fetchReservePlayers();
}
