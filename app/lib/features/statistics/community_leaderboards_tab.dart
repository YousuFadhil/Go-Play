import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'statistics_models.dart';
import 'statistics_repository.dart';

/// The community's leaderboards: five measures, the top three on each.
///
/// It owns its own load rather than joining the details screen's, for the same
/// reason the dashboard does — a recorded result changes these standings and
/// nothing else on that screen, so pulling down here refreshes them.
class CommunityLeaderboardsTab extends StatefulWidget {
  const CommunityLeaderboardsTab({
    super.key,
    required this.communityId,
    this.repository,
  });

  final String communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final StatisticsRepository? repository;

  @override
  State<CommunityLeaderboardsTab> createState() =>
      _CommunityLeaderboardsTabState();
}

class _CommunityLeaderboardsTabState extends State<CommunityLeaderboardsTab> {
  late final StatisticsRepository _statistics =
      widget.repository ?? StatisticsRepository();
  late Future<List<Leaderboard>> _boardsFuture;

  @override
  void initState() {
    super.initState();
    _boardsFuture = _statistics.fetchLeaderboards(widget.communityId);
  }

  Future<void> _refresh() async {
    final future = _statistics.fetchLeaderboards(widget.communityId);
    // A block body, not an arrow: an arrow returns the assigned Future, and
    // setState asserts when its callback returns one.
    setState(() {
      _boardsFuture = future;
    });
    // Awaited only so the refresh indicator stays up until the boards land. A
    // failure is swallowed here rather than ignored: the builder below is
    // already showing it.
    await future.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return FutureBuilder<List<Leaderboard>>(
      future: _boardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.loadFailed),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _refresh,
                  child: Text(l10n.retryButton),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: _BoardsBody(boards: snapshot.data!),
        );
      },
    );
  }
}

class _BoardsBody extends StatelessWidget {
  const _BoardsBody({required this.boards});

  final List<Leaderboard> boards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Every board was hidden, which means nothing has happened here yet rather
    // than that something is wrong. One message says so once, instead of five
    // empty cards saying it five times.
    if (boards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: Column(
              children: [
                Icon(
                  Icons.leaderboard_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(l10n.leaderboardsEmpty, textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      );
    }

    final showsRating =
        boards.any((board) => board.kind == LeaderboardKind.highestRated);

    return ListView(
      // Always scrollable, so pulling down refreshes even when the content is
      // shorter than the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final board in boards) LeaderboardCard(board: board),
        // Said once, and only when a rating is actually on screen: the figure
        // is the player's rating everywhere, not their rating here.
        if (showsRating)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l10n.leaderboardRatingNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
      ],
    );
  }
}

/// One board: its measure, and the players who lead it.
class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({super.key, required this.board});

  final Leaderboard board;

  String _title(AppLocalizations l10n) => switch (board.kind) {
        LeaderboardKind.highestRated => l10n.leaderboardHighestRated,
        LeaderboardKind.topScorer => l10n.leaderboardTopScorer,
        LeaderboardKind.mostMvp => l10n.leaderboardMostMvp,
        LeaderboardKind.mostActive => l10n.leaderboardMostActive,
        LeaderboardKind.mostWins => l10n.leaderboardMostWins,
      };

  IconData get _icon => switch (board.kind) {
        LeaderboardKind.highestRated => Icons.military_tech,
        LeaderboardKind.topScorer => Icons.sports_soccer,
        LeaderboardKind.mostMvp => Icons.star,
        LeaderboardKind.mostActive => Icons.directions_run,
        LeaderboardKind.mostWins => Icons.emoji_events,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(_icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _title(context.l10n),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          for (final entry in board.entries)
            _LeaderboardRow(entry: entry, isRating: board.kind.isRating),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isRating});

  final LeaderboardEntry entry;
  final bool isRating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: _RankBadge(rank: entry.rank),
      title: Text(entry.fullName),
      trailing: Text(
        // A rating keeps its one decimal (`OP-1`); a count is a whole number
        // and showing it as "5.0" would read as a different kind of figure.
        isRating
            ? (entry.value as double).toStringAsFixed(1)
            : '${entry.value.toInt()}',
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// The place a player holds. Equal values share a badge, which is the whole
/// point of showing the number rather than the row's position.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop = rank == 1;

    return CircleAvatar(
      radius: 16,
      backgroundColor: isTop
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      child: Text(
        '$rank',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color:
              isTop ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
