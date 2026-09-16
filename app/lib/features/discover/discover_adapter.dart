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

  /// One publicly visible match, or null when there is not one at [matchId].
  ///
  /// **Null is the whole of the access answer.** A match that has been played,
  /// a match whose community has been deactivated and a match that never
  /// existed are one reply, because telling them apart is exactly what a
  /// guessed id must not be able to do. `public_match_detail` (migration
  /// `0078`) reads `v_public_upcoming_matches`, so what counts as publicly
  /// visible is that view's rule and not a second copy of it here.
  Future<PublicMatch?> fetchMatch(String matchId);

  /// Matches that have not ended yet, soonest first. Scoped to one community
  /// when [communityId] is given, otherwise across all of them.
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId});
}
