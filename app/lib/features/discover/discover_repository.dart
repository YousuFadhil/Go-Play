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

  /// How many results a page loads. Six, the approved recent set rather than
  /// a history, and stated once so Discover -- signed in or not -- and a
  /// community page ask for the same thing. Discover shows three of them until
  /// the reader asks for all.
  static const recentResults = 6;

  /// How many Top Players a community page shows. Eleven, a football side --
  /// stated once and enforced twice: the database function caps its answer at
  /// the same number, and [fetchCommunityFootball] trims to it again so a
  /// misbehaving adapter cannot draw a longer list than the approved one.
  static const topPlayers = 11;

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

  /// One community's football: the record above the tabs and the Top Players
  /// tab, from the narrow public contracts of migration `0093`.
  ///
  /// **The same read for a guest and for a signed-in non-member.** Neither
  /// reaches the authenticated football views, so the two audiences see one
  /// record and one ranking.
  ///
  /// Fetched apart from [fetchCommunityDetails] on purpose: the community's
  /// name and fixtures must not disappear because a football read failed, and
  /// the football must not be held up by the fixtures. The two reads here are
  /// one section of the page and are useless in pieces, so they succeed or fail
  /// together.
  ///
  /// The players are taken in the order the database ranked them -- nothing is
  /// re-sorted here, because a second ranking rule is a rule that can drift.
  Future<PublicCommunityFootball> fetchCommunityFootball(
    String communityId,
  ) async {
    final reads = await Future.wait([
      _adapter.fetchCommunityFootballRecord(communityId),
      _adapter.fetchCommunityTopPlayers(communityId),
    ]);
    return PublicCommunityFootball(
      record: reads[0] as PublicCommunityFootballRecord,
      topPlayers: (reads[1] as List<PublicCommunityTopPlayer>)
          .take(topPlayers)
          .toList(),
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

/// The football half of a community page: what sits above the tabs and what
/// fills the Top Players tab.
class PublicCommunityFootball {
  const PublicCommunityFootball({
    required this.record,
    required this.topPlayers,
  });

  final PublicCommunityFootballRecord record;

  /// At most [DiscoverRepository.topPlayers], best first. Empty is an ordinary
  /// answer: a community nobody has finished a match in has nobody to rank.
  final List<PublicCommunityTopPlayer> topPlayers;
}
