import 'discover_models.dart';

/// The public browsing port into the data provider.
///
/// Every type named here is a Domain Model (OP-3), and every implementation
/// converts its provider's exceptions into a `Failure` before returning (OP-5).
///
/// What separates this port from [CommunityAdapter] and [MatchAdapter] is not
/// the shape of the data but who is asking: every read here must succeed with no
/// session at all. That is a contract, not an implementation detail — an
/// implementation that needs a signed-in user does not satisfy it.
abstract interface class DiscoverAdapter {
  /// Every community that has not been deleted, newest first.
  ///
  /// Unfiltered by design: the join policy decides how someone gets in, never
  /// whether they are shown a community exists.
  Future<List<PublicCommunity>> fetchCommunities();

  Future<PublicCommunity> fetchCommunity(String communityId);

  /// One publicly visible match — upcoming or completed — or null when there is
  /// not one at [matchId].
  ///
  /// **Null is the whole of the access answer.** A match whose community is
  /// inactive or suspended and a match that never existed are one reply,
  /// because telling them apart is exactly what a guessed id must not be able
  /// to do. `public_match_detail` (migration `0079`) decides visibility; this
  /// port only carries its answer.
  ///
  /// A completed match arrives without its lineup; see [fetchMatchLineup].
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId);

  /// The lineup of a completed public match, or empty.
  ///
  /// Always empty for an upcoming match: its roster is not public, and the
  /// database returns no rows for it rather than this port declining to ask.
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId);

  /// Matches that have not ended yet, soonest first. Scoped to one community
  /// when [communityId] is given, otherwise across all of them.
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId});

  /// The most recent completed matches with a recorded result, newest first.
  ///
  /// [communityId] scopes the list to one community's page; null is Discover's
  /// list across every active community. Both read the narrow public contracts
  /// migration `0081` grants `anon`, so a guest gets the same answer a member
  /// does and neither is asked to sign in to see a result that is already
  /// public.
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 6,
  });

  /// One active community's football record, from the narrow contract
  /// migration `0093` grants `anon`.
  ///
  /// **Not `v_football_community_stats`.** That view is one of a closed family
  /// granted to `authenticated` only, and widening it would expose more than a
  /// community page draws. A signed-in non-member reads this same contract, so
  /// both audiences see one record.
  Future<PublicCommunityFootballRecord> fetchCommunityFootballRecord(
    String communityId,
  );

  /// One active community's Top Players -- at most eleven, best first.
  ///
  /// The ranking is the database's (rating, then goals, then MVPs, then name)
  /// and the list arrives in that order; a caller renders it as given.
  Future<List<PublicCommunityTopPlayer>> fetchCommunityTopPlayers(
    String communityId,
  );
}
