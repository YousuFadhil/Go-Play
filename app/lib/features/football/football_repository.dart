import '../../infrastructure/supabase/supabase_football_adapter.dart';
import 'football_adapter.dart';
import 'football_models.dart';

/// Data access for public football activity.
///
/// Thin, and deliberately so. The repositories over the other aggregates have
/// rules to apply before or after the port — what counts as joined, what a
/// registration outcome means, which measure leads a leaderboard. Reading
/// football history has almost none: there is nothing to decide about a list of
/// matches that have been played.
///
/// What it does own is the one page-shaped read. A match's football detail is
/// three questions that are useless apart — the match, its roster, its lineup —
/// so they are asked together and fail together, rather than leaving a caller to
/// sequence three requests and decide what two thirds of an answer means.
class FootballRepository {
  FootballRepository([FootballAdapter? adapter])
      : _adapter = adapter ?? SupabaseFootballAdapter();

  final FootballAdapter _adapter;

  /// Matches that have been played, most recent first.
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) =>
      _adapter.fetchCompletedMatches(communityId: communityId, limit: limit);

  /// Everything one completed match shows, in one pass.
  Future<CompletedMatchDetail> fetchMatchDetail(String matchId) async {
    final results = await Future.wait([
      _adapter.fetchCompletedMatch(matchId),
      _adapter.fetchMatchRoster(matchId),
      _adapter.fetchMatchLineup(matchId),
    ]);
    return CompletedMatchDetail(
      match: results[0] as CompletedMatch,
      roster: results[1] as List<MatchRosterEntry>,
      lineup: results[2] as List<LineupSlot>,
    );
  }

  Future<CommunityFootballStats> fetchCommunityStats(String communityId) =>
      _adapter.fetchCommunityStats(communityId);

  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
    String communityId,
  ) =>
      _adapter.fetchCommunityPlayerStats(communityId);
}

/// One completed match, whole.
class CompletedMatchDetail {
  const CompletedMatchDetail({
    required this.match,
    required this.roster,
    required this.lineup,
  });

  final CompletedMatch match;

  /// Everybody who registered, in saved order.
  final List<MatchRosterEntry> roster;

  /// The stored lineup. Empty when none was saved — a match can be played and
  /// recorded without one having survived.
  final List<LineupSlot> lineup;

  /// The stored lineup, split by side. Computed rather than stored: it is one
  /// reading of [lineup] and a second field could disagree with it.
  List<LineupSlot> get teamA =>
      [for (final s in lineup) if (s.team == FootballTeam.a) s];
  List<LineupSlot> get teamB =>
      [for (final s in lineup) if (s.team == FootballTeam.b) s];
}
