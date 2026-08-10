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

  /// Matches that have not ended yet, soonest first. Scoped to one community
  /// when [communityId] is given, otherwise across all of them.
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId});
}
