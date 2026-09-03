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
      _adapter.fetchAchievementRecency(communityId, period),
    ]);
    final players = results[0] as List<CommunityPlayerStatistics>;
    final completedMatches = results[1] as int;
    final recency = results[2] as Map<String, PlayerAchievementRecency>;

    // The population is unchanged: these are the community's records for the
    // period, players who have since left included. Recency decides which of
    // two equal players leads, and nothing about who is eligible to.
    return CommunityDashboard(
      completedMatches: completedMatches,
      totalPlayers: players.length,
      totalGoals: players.fold(0, (sum, player) => sum + player.goals),
      topScorer: _leaderBy(players, recency, LeaderboardKind.topScorer,
          (player) => player.goals),
      mostActivePlayer: _leaderBy(players, recency, LeaderboardKind.mostActive,
          (player) => player.matchesPlayed),
      mostMvp: _leaderBy(players, recency, LeaderboardKind.mostMvp,
          (player) => player.mvpCount),
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
      _adapter.fetchAchievementRecency(communityId, period),
    ]);
    final members = results[0] as List<CommunityMemberRating>;
    final recency = results[2] as Map<String, PlayerAchievementRecency>;
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
      final board =
          _buildBoard(kind, members, recency, (m) => measure(m, kind));
      if (board != null) boards.add(board);
    }
    return boards;
  }

  /// The whole Statistics tab for [period]: the totals and the five boards.
  ///
  /// **Four reads, where the two calls above make six between them.** Asked
  /// separately, [fetchDashboard] and [fetchLeaderboards] each fetch the
  /// community's player counters and each fetch the achievement recency for the
  /// same period — the same two questions, asked twice, because they were two
  /// tabs that did not know about each other. One tab asks once.
  ///
  /// **Nothing about the answers changes.** The counters, the totals, the
  /// leaders and the boards are built by the same helpers from the same rows,
  /// so this returns exactly what the two calls returned; it is the asking that
  /// was consolidated, not the arithmetic. That matters more than the saved
  /// round trips: a reader who compares the totals with the boards must not be
  /// comparing two reads taken a moment apart.
  Future<CommunityStatistics> fetchCommunityStatistics(
    String communityId, [
    StatisticsPeriod period = StatisticsPeriod.allTime,
  ]) async {
    final results = await Future.wait([
      _adapter.fetchCommunityPlayerStatistics(communityId, period),
      _adapter.fetchCompletedMatches(communityId, period),
      _adapter.fetchAchievementRecency(communityId, period),
      // Periodless, exactly as it is in `fetchLeaderboards`: membership is a
      // fact about now, and the rating it carries is the Global Rating, which
      // has no weekly form.
      _adapter.fetchCommunityMemberRatings(communityId),
    ]);
    final players = results[0] as List<CommunityPlayerStatistics>;
    final completedMatches = results[1] as int;
    final recency = results[2] as Map<String, PlayerAchievementRecency>;
    final members = results[3] as List<CommunityMemberRating>;

    return CommunityStatistics(
      dashboard: _dashboardOf(players, completedMatches, recency),
      boards: _boardsOf(members, players, recency),
    );
  }

  /// The totals and the three counted leaders, from rows already read.
  ///
  /// Extracted so [fetchDashboard] and [fetchCommunityStatistics] compose the
  /// same figures out of the same rows rather than two similar blocks that
  /// could drift.
  static CommunityDashboard _dashboardOf(
    List<CommunityPlayerStatistics> players,
    int completedMatches,
    Map<String, PlayerAchievementRecency> recency,
  ) =>
      CommunityDashboard(
        completedMatches: completedMatches,
        totalPlayers: players.length,
        totalGoals: players.fold(0, (sum, player) => sum + player.goals),
        topScorer: _leaderBy(
            players, recency, LeaderboardKind.topScorer, (p) => p.goals),
        mostActivePlayer: _leaderBy(players, recency,
            LeaderboardKind.mostActive, (p) => p.matchesPlayed),
        mostMvp: _leaderBy(
            players, recency, LeaderboardKind.mostMvp, (p) => p.mvpCount),
      );

  /// The five boards, from rows already read. The counterpart of [_dashboardOf].
  static List<Leaderboard> _boardsOf(
    List<CommunityMemberRating> members,
    List<CommunityPlayerStatistics> players,
    Map<String, PlayerAchievementRecency> recency,
  ) {
    final counters = {for (final row in players) row.userId: row};

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
      final board =
          _buildBoard(kind, members, recency, (m) => measure(m, kind));
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
    Map<String, PlayerAchievementRecency> recency,
    num Function(CommunityMemberRating) measure,
  ) {
    final ranked = [
      for (final member in members)
        if (measure(member) > 0) member,
    ]..sort((a, b) {
        // Highest first, then the shared tie-break. The comparison below the
        // value decides display order only: equal values still share a rank,
        // which `_rankOf` computes from the value alone.
        final byValue = measure(b).compareTo(measure(a));
        if (byValue != 0) return byValue;
        return _breakTie(
          kind,
          recency,
          aId: a.userId,
          aName: a.fullName,
          bId: b.userId,
          bName: b.fullName,
        );
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
  /// Ties go to whoever did it most recently, through the same [_breakTie] the
  /// boards use. That is what makes the dashboard's Top Scorer and the Top
  /// Scorer board name the same player out of a tie: one rule, asked twice,
  /// rather than two rules that happen to agree.
  static StatisticLeader? _leaderBy(
    List<CommunityPlayerStatistics> players,
    Map<String, PlayerAchievementRecency> recency,
    LeaderboardKind kind,
    int Function(CommunityPlayerStatistics) measure,
  ) {
    CommunityPlayerStatistics? best;
    for (final player in players) {
      if (measure(player) <= 0) continue;
      if (best == null || _beats(player, best, recency, kind, measure)) {
        best = player;
      }
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
    Map<String, PlayerAchievementRecency> recency,
    LeaderboardKind kind,
    int Function(CommunityPlayerStatistics) measure,
  ) {
    final difference = measure(candidate) - measure(incumbent);
    if (difference != 0) return difference > 0;
    // A dashboard record may carry no name (`CommunityPlayerStatistics.fullName`
    // is nullable where the profile could not be read); the boards' names never
    // are. Empty stands in so the same comparison serves both.
    return _breakTie(
          kind,
          recency,
          aId: candidate.userId,
          aName: candidate.fullName ?? '',
          bId: incumbent.userId,
          bName: incumbent.fullName ?? '',
        ) <
        0;
  }

  /// **The tie-break, and the only one.** Both the dashboard leaders and the
  /// five boards come through here, so a value that is level in one place is
  /// ordered the same way in the other — and a share surface reading either
  /// gets that ordering without asking for it.
  ///
  /// Returns a comparator result for two players already known to be level on
  /// the measure. It decides **display order only**: ranks are computed from
  /// the value alone, so nothing here can turn equals into different places.
  ///
  /// In order:
  ///
  ///   1. the newer achievement of *this* measure first;
  ///   2. `fullName`, when the two achieved it in the same match or neither
  ///      ever has;
  ///   3. `userId`, so the answer is total and repeated reads never swap.
  ///
  /// **Null sorts last.** A missing timestamp means the measure has never
  /// happened to that player — a rating still at its opening 5.00 with no
  /// effective event behind it — and "never" is not a very old date. A player
  /// with a real event therefore comes before one without, and two players with
  /// neither fall through to the name.
  static int _breakTie(
    LeaderboardKind kind,
    Map<String, PlayerAchievementRecency> recency, {
    required String aId,
    required String aName,
    required String bId,
    required String bName,
  }) {
    final a = (recency[aId] ?? PlayerAchievementRecency.none).forKind(kind);
    final b = (recency[bId] ?? PlayerAchievementRecency.none).forKind(kind);

    if (a != null && b != null) {
      // Newest first.
      final byRecency = b.compareTo(a);
      if (byRecency != 0) return byRecency;
    } else if (a != null) {
      return -1;
    } else if (b != null) {
      return 1;
    }

    final byName = aName.compareTo(bName);
    return byName != 0 ? byName : aId.compareTo(bId);
  }
}
