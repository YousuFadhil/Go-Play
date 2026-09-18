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

  /// How many results a public page shows. Five, which is a practical recent
  /// set rather than a history, and stated once so Discover and a community
  /// page ask for the same thing.
  static const recentResults = 5;

  /// Everything the Discover page shows, in one pass.
  ///
  /// Three lists now, and they still fail together: a guest who was shown
  /// upcoming matches but no results was the defect this read fixes, and
  /// leaving the results to a second request would let the page half-load into
  /// exactly that state again.
  Future<DiscoverOverview> fetchOverview() async {
    final results = await Future.wait([
      _adapter.fetchUpcomingMatches(),
      _adapter.fetchCommunities(),
      _adapter.fetchRecentResults(limit: recentResults),
    ]);
    return DiscoverOverview(
      matches: results[0] as List<PublicMatch>,
      communities: results[1] as List<PublicCommunity>,
      results: results[2] as List<PublicResult>,
    );
  }

  /// One publicly visible match — upcoming or completed — or null, with a
  /// completed match's lineup attached.
  ///
  /// The lineup is asked for only once the detail says the match was played,
  /// so an upcoming match costs one read and its roster is never requested.
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async {
    final detail = await _adapter.fetchMatchDetail(matchId);
    if (detail is! PublicCompletedMatch) return detail;
    final lineup = await _adapter.fetchMatchLineup(matchId);
    return PublicCompletedMatch(
      id: detail.id,
      communityId: detail.communityId,
      communityName: detail.communityName,
      communityLogoUrl: detail.communityLogoUrl,
      title: detail.title,
      location: detail.location,
      startAt: detail.startAt,
      endAt: detail.endAt,
      hasResult: detail.hasResult,
      teamAScore: detail.teamAScore,
      teamBScore: detail.teamBScore,
      mvpDisplayName: detail.mvpDisplayName,
      mvpAvatarUrl: detail.mvpAvatarUrl,
      lineup: lineup,
    );
  }

  /// One community and what it has scheduled — the guest's community details.
  Future<PublicCommunityDetails> fetchCommunityDetails(
    String communityId,
  ) async {
    final reads = await Future.wait([
      _adapter.fetchCommunity(communityId),
      _adapter.fetchUpcomingMatches(communityId: communityId),
      _adapter.fetchRecentResults(
        communityId: communityId,
        limit: recentResults,
      ),
    ]);
    return PublicCommunityDetails(
      community: reads[0] as PublicCommunity,
      matches: reads[1] as List<PublicMatch>,
      results: reads[2] as List<PublicResult>,
    );
  }
}

/// What the Discover page renders.
class DiscoverOverview {
  const DiscoverOverview({
    required this.matches,
    required this.communities,
    this.results = const [],
  });

  final List<PublicMatch> matches;
  final List<PublicCommunity> communities;

  /// The most recent completed results, newest first. Public, so a guest sees
  /// the football that has already been played rather than only what is next.
  final List<PublicResult> results;
}

/// What a guest sees when they open a community.
class PublicCommunityDetails {
  const PublicCommunityDetails({
    required this.community,
    required this.matches,
    this.results = const [],
  });

  final PublicCommunity community;
  final List<PublicMatch> matches;

  /// This community's most recent results. What keeps its public page from
  /// being nearly empty in a week with nothing scheduled.
  final List<PublicResult> results;
}
