import '../../infrastructure/supabase/supabase_statistics_adapter.dart';
import 'statistics_adapter.dart';
import 'statistics_models.dart';

/// Data access for a community's statistics, and the reasoning that turns rows
/// into the figures a dashboard shows.
///
/// Everything provider-specific is behind [StatisticsAdapter]. What remains
/// here is the product's own reasoning: which measures lead, what a tie means,
/// and when a number is worth showing at all.
class StatisticsRepository {
  StatisticsRepository([StatisticsAdapter? adapter])
      : _adapter = adapter ?? SupabaseStatisticsAdapter();

  final StatisticsAdapter _adapter;

  /// Assembles the Community Dashboard.
  ///
  /// Two reads, issued together because neither depends on the other and the
  /// screen shows them as one thing. The totals are summed here rather than in
  /// the database: the population is one row per player in one community, which
  /// at the sizes this product targets is tens of rows, and summing them in
  /// Dart avoids adding a read model for arithmetic a client can do. If a
  /// community ever grows to where that stops being true, the fix is a view —
  /// not a wider port.
  Future<CommunityDashboard> fetchDashboard(String communityId) async {
    final results = await Future.wait([
      _adapter.fetchCommunityPlayerStatistics(communityId),
      _adapter.fetchTotalMatches(communityId),
    ]);
    final players = results[0] as List<CommunityPlayerStatistics>;
    final totalMatches = results[1] as int;

    return CommunityDashboard(
      totalMatches: totalMatches,
      totalPlayers: players.length,
      totalGoals: players.fold(0, (sum, player) => sum + player.goals),
      topScorer: _leaderBy(players, (player) => player.goals),
      mostActivePlayer: _leaderBy(players, (player) => player.matchesPlayed),
      mostMvp: _leaderBy(players, (player) => player.mvpCount),
    );
  }

  /// The community's leaderboards: the five measures, top three each.
  ///
  /// Two reads against objects that already exist — the roster with its ratings
  /// and the community counters. Nothing was added to the database for this.
  ///
  /// **The roster is the population, not the counters.** A statistics record is
  /// preserved when a player leaves, so ranking the counters directly would put
  /// people who have left on a board of who is doing well here. Every board
  /// therefore ranks current members — and of those, only the ones the measure
  /// has actually happened to (see [_buildBoard]).
  Future<List<Leaderboard>> fetchLeaderboards(String communityId) async {
    final results = await Future.wait([
      _adapter.fetchCommunityMemberRatings(communityId),
      _adapter.fetchCommunityPlayerStatistics(communityId),
    ]);
    final members = results[0] as List<CommunityMemberRating>;
    final counters = {
      for (final row in results[1] as List<CommunityPlayerStatistics>)
        row.userId: row,
    };

    num measure(CommunityMemberRating member, LeaderboardKind kind) {
      if (kind == LeaderboardKind.highestRated) return member.rating;
      final row = counters[member.userId];
      if (row == null) return 0;
      return switch (kind) {
        LeaderboardKind.topScorer => row.goals,
        LeaderboardKind.mostMvp => row.mvpCount,
        LeaderboardKind.mostActive => row.matchesPlayed,
        LeaderboardKind.mostWins => row.wins,
        LeaderboardKind.highestRated => 0,
      };
    }

    final boards = <Leaderboard>[];
    for (final kind in LeaderboardKind.values) {
      final board = _buildBoard(kind, members, (m) => measure(m, kind));
      if (board != null) boards.add(board);
    }
    return boards;
  }

  /// One board, or null when it has nothing to say.
  ///
  /// **A zero never takes a place on a board.** Every member holds a record
  /// from the moment they join, so a board built from the whole roster would
  /// fill its lower places with people the measure has not happened to — a
  /// player with no goals sitting second on Top Scorer reads as a ranking and
  /// is not one. Only players above zero are ranked, and a board with nobody
  /// left to rank is not built at all.
  static Leaderboard? _buildBoard(
    LeaderboardKind kind,
    List<CommunityMemberRating> members,
    num Function(CommunityMemberRating) measure,
  ) {
    final ranked = [
      for (final member in members)
        if (measure(member) > 0) member,
    ]..sort((a, b) {
        // Highest first. The rest of the comparison decides nothing about who
        // is better — it exists so that two players on the same value come
        // back in the same order every time the board is read, rather than
        // swapping places between refreshes.
        final byValue = measure(b).compareTo(measure(a));
        if (byValue != 0) return byValue;
        final byName = a.fullName.compareTo(b.fullName);
        return byName != 0 ? byName : a.userId.compareTo(b.userId);
      });

    if (ranked.isEmpty) return null;

    final entries = <LeaderboardEntry>[];
    for (var i = 0; i < ranked.length && entries.length < _boardDepth; i++) {
      final member = ranked[i];
      final value = measure(member);
      // Competition ranking: a player's rank is one more than the number of
      // players strictly ahead of them, so equals share a rank and the next
      // distinct value skips the places they used up.
      final ahead = ranked.where((other) => measure(other) > value).length;
      entries.add(LeaderboardEntry(
        userId: member.userId,
        fullName: member.fullName,
        rank: ahead + 1,
        value: value,
      ));
    }

    return Leaderboard(kind: kind, entries: entries);
  }

  /// Top three. A social board for a group that plays together, not a table.
  static const _boardDepth = 3;

  /// The player with the highest [measure], or null when nobody has any.
  ///
  /// **Zero is not a leader.** Every member of a community holds a record from
  /// the moment they join, so without this a community that has never recorded
  /// a result would name a "top scorer" with no goals — picked out of a table
  /// of ties by nothing more than the order rows came back in. Absence is the
  /// honest answer, and the screen says so.
  ///
  /// Ties are broken by name, then by id. Neither is meaningful — the point is
  /// only that repeated reads of unchanged data name the same player, rather
  /// than swapping between equals every time the screen is opened.
  static StatisticLeader? _leaderBy(
    List<CommunityPlayerStatistics> players,
    int Function(CommunityPlayerStatistics) measure,
  ) {
    CommunityPlayerStatistics? best;
    for (final player in players) {
      if (measure(player) <= 0) continue;
      if (best == null || _beats(player, best, measure)) best = player;
    }
    if (best == null) return null;
    return StatisticLeader(
      userId: best.userId,
      fullName: best.fullName,
      value: measure(best),
    );
  }

  static bool _beats(
    CommunityPlayerStatistics candidate,
    CommunityPlayerStatistics incumbent,
    int Function(CommunityPlayerStatistics) measure,
  ) {
    final difference = measure(candidate) - measure(incumbent);
    if (difference != 0) return difference > 0;
    final byName =
        (candidate.fullName ?? '').compareTo(incumbent.fullName ?? '');
    if (byName != 0) return byName < 0;
    return candidate.userId.compareTo(incumbent.userId) < 0;
  }
}
