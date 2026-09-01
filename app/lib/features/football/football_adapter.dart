import 'football_models.dart';

/// The public-football port into the data provider.
///
/// Every type named here is a Domain Model (OP-3), and every implementation
/// converts its provider's exceptions into a `Failure` before returning (OP-5).
///
/// What separates this port from [MatchAdapter], [TeamAdapter] and
/// [StatisticsAdapter] is not the shape of the data but who is asking. Those
/// three answer a member about their own community. Every read here must succeed
/// for a signed-in caller who is in **no** community at all — that is a
/// contract, not an implementation detail, and an implementation that needs
/// membership does not satisfy it.
///
/// It is equally a contract that a session *is* required. Cycle 2 publishes
/// football history to people with an account and to nobody else; an
/// implementation that answered a signed-out caller would be exceeding it.
abstract interface class FootballAdapter {
  /// Matches that have been played, most recent first. Scoped to one community
  /// when [communityId] is given, otherwise across all of them.
  ///
  /// [limit] bounds the read because this is the one call whose population
  /// grows without limit as the product is used.
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit,
  });

  /// One completed match, or a `NotFoundFailure` when the id names none.
  Future<CompletedMatch> fetchCompletedMatch(String matchId);

  /// Everybody who registered for a completed match, confirmed and reserve
  /// alike, in the order the roster was saved.
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId);

  /// The stored lineup of a completed match: both sides, with goals and the MVP
  /// flag. Empty when no lineup was saved, which is an ordinary state and not an
  /// error.
  Future<List<LineupSlot>> fetchMatchLineup(String matchId);

  /// A community's football record.
  Future<CommunityFootballStats> fetchCommunityStats(String communityId);

  /// Every player with an all-time record in one community, unordered.
  ///
  /// Unordered by design: which measure ranks and how ties break is a product
  /// decision and belongs above this layer (OP-2).
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
    String communityId,
  );
}
