import '../../infrastructure/supabase/supabase_statistics_adapter.dart';
import 'statistics_adapter.dart';
import 'statistics_models.dart';
import 'statistics_period.dart';

/// Data access for a community's statistics, and the reasoning that turns rows
/// into the figures a dashboard shows.
///
/// Everything provider-specific is behind [StatisticsAdapter]. What remains
/// here is the product's own reasoning: which measures lead, what a tie means,
/// and when a number is worth showing at all.
///
/// **A period changes which rows arrive, and nothing else.** Every rule below —
/// that a zero never leads, that a board ranks current members only, that ties
/// break deterministically, that a board with nobody on it is not built — is
/// asked of one period's rows exactly as it was asked of the running total. The
/// period is a parameter to the reads, not a branch in the reasoning.
class StatisticsRepository {
  StatisticsRepository([StatisticsAdapter? adapter])
      : _adapter = adapter ?? SupabaseStatisticsAdapter();

  final StatisticsAdapter _adapter;

  /// Assembles the Community Dashboard for [period].
  ///
  /// Two reads, issued together because neither depends on the other and the
  /// screen shows them as one thing. The totals are summed here rather than in
  /// the database: the population is one row per player in one community, which
  /// at the sizes this product targets is tens of rows, and summing them in
  /// Dart avoids adding a read model for arithmetic a client can do. If a
  /// community ever grows to where that stops being true, the fix is a view —
  /// not a wider port.
  ///
  /// **Both reads take the period, and they have to.** The match count is a
  /// fact about matches and the rest are facts about players; asking one of
  /// them about a week and the other about all history would produce a
  /// dashboard describing two different stretches of time at once.
  ///
  /// For a bounded period `totalPlayers` is who played in it, not who is in the
  /// community: a periodic record exists only where a player actually played
  /// (`0028` §2.3). That is the honest reading of "players" beside "goals in
  /// this week", and it is why a quiet week reports zero players rather than
  /// the full roster with nothing next to their names.
  Future<CommunityDashboard> fetchDashboard(
    String communityId, [
    StatisticsPeriod period = StatisticsPeriod.allTime,
  ]) async {
    final results = await Future.wait([
      _adapter.fetchCommunityPlayerStatistics(communityId, period),
      _adapter.fetchCompletedMatches(communityId, period),
    ]);
    final players = results[0] as List<CommunityPlayerStatistics>;
    final completedMatches = results[1] as int;

    return CommunityDashboard(
      completedMatches: completedMatches,
      totalPlayers: players.length,
      totalGoals: players.fold(0, (sum, player) => sum + player.goals),
      topScorer: _leaderBy(players, (player) => player.goals),
      mostActivePlayer: _leaderBy(players, (player) => player.matchesPlayed),
      mostMvp: _leaderBy(players, (player) => player.mvpCount),
    );
  }

  /// The community's leaderboards for [period]: the five measures, top three
  /// each.
  ///
  /// Two reads against objects that already exist — the roster with its ratings
  /// and the community counters. Nothing was added to the database for this.
  ///
  /// **The roster is the population, not the counters.** A statistics record is
  /// preserved when a player leaves, so ranking the counters directly would put
  /// people who have left on a board of who is doing well here. Every board
  /// therefore ranks current members — and of those, only the ones the measure
  /// has actually happened to (see [_buildBoard]).
  ///
  /// **Only the counters are period-scoped.** The roster read takes no period
  /// because neither of the things it carries has one: membership is a fact
  /// about now, and the rating is the Global Rating (`OP-1`), which has no
  /// weekly form and is not invented one here. So Highest Rated reads the same
  /// in every period — deliberately, and the footnote on the screen has always
  /// said what that figure is. The four counted boards change completely, which
  /// is the point.
  Future<List<Leaderboard>> fetchLeaderboards(
    String communityId, [
    StatisticsPeriod period = StatisticsPeriod.allTime,
  ]) async {
    final results = await Future.wait([
      _adapter.fetchCommunityMemberRatings(communityId),
      _adapter.fetchCommunityPlayerStatistics(communityId, period),
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

  /// One player's totals for [period], across every community they play in.
  ///
  /// **A career already has a source, and this is not a second one.** The Result
  /// domain answers All Time from `v_user_profile`, which is where the player's
  /// career and their rating have always come from; summing `overall` records
  /// here would build a rival total free to disagree with it. So this is for the
  /// bounded periods only, and asking it for All Time is a programming error
  /// rather than a request it quietly serves.
  ///
  /// The sum is here rather than in the database because a total across
  /// communities is a product decision (OP-2) — and because the rows are one
  /// per community the player belongs to, which is a handful.
  ///
  /// A player with no records in the period played no match in it, so every
  /// figure is zero. That is [PlayerPeriodStatistics.none] and it is an answer:
  /// the database deletes a periodic record that has nothing in it (`0028`
  /// §2.3), so "no rows" and "all zeros" are the same statement.
  Future<PlayerPeriodStatistics> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) async {
    if (!period.isBounded) {
      throw ArgumentError.value(
        period,
        'period',
        'All Time is answered by the player career read, not by summing '
            'community records',
      );
    }

    final records = await _adapter.fetchPlayerPeriodStatistics(userId, period);
    if (records.isEmpty) return const PlayerPeriodStatistics.none();

    var matchesPlayed = 0, wins = 0, losses = 0, draws = 0, goals = 0, mvp = 0;
    for (final record in records) {
      matchesPlayed += record.matchesPlayed;
      wins += record.wins;
      losses += record.losses;
      draws += record.draws;
      goals += record.goals;
      mvp += record.mvpCount;
    }

    return PlayerPeriodStatistics(
      matchesPlayed: matchesPlayed,
      wins: wins,
      losses: losses,
      draws: draws,
      goals: goals,
      mvpCount: mvp,
    );
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
        avatarUrl: member.avatarUrl,
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
      avatarUrl: best.avatarUrl,
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
