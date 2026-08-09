import '../../infrastructure/supabase/supabase_discover_adapter.dart';
import 'discover_adapter.dart';
import 'discover_models.dart';

/// Data access for the public Discover experience.
///
/// Thin on purpose. The repositories that sit over the other aggregates have
/// rules to apply before or after the port — what counts as joined, what a join
/// outcome means. Browsing has none: there is nothing to decide about a list of
/// communities a visitor may look at, and inventing something for symmetry would
/// be a rule the product never asked for.
///
/// What it does own is the one page-shaped read. Discover needs both lists and
/// is useless with one, so they are fetched together and fail together, rather
/// than leaving a screen to sequence two requests and decide what half a page
/// means.
class DiscoverRepository {
  DiscoverRepository([DiscoverAdapter? adapter])
      : _adapter = adapter ?? SupabaseDiscoverAdapter();

  final DiscoverAdapter _adapter;

  /// Everything the Discover page shows, in one pass.
  Future<DiscoverOverview> fetchOverview() async {
    final results = await Future.wait([
      _adapter.fetchUpcomingMatches(),
      _adapter.fetchCommunities(),
    ]);
    return DiscoverOverview(
      matches: results[0] as List<PublicMatch>,
      communities: results[1] as List<PublicCommunity>,
    );
  }

  /// One community and what it has scheduled — the guest's community details.
  Future<PublicCommunityDetails> fetchCommunityDetails(
    String communityId,
  ) async {
    final results = await Future.wait([
      _adapter.fetchCommunity(communityId),
      _adapter.fetchUpcomingMatches(communityId: communityId),
    ]);
    return PublicCommunityDetails(
      community: results[0] as PublicCommunity,
      matches: results[1] as List<PublicMatch>,
    );
  }
}

/// What the Discover page renders.
class DiscoverOverview {
  const DiscoverOverview({required this.matches, required this.communities});

  final List<PublicMatch> matches;
  final List<PublicCommunity> communities;
}

/// What a guest sees when they open a community.
class PublicCommunityDetails {
  const PublicCommunityDetails({required this.community, required this.matches});

  final PublicCommunity community;
  final List<PublicMatch> matches;
}
