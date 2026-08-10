import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/states.dart';
import 'statistics_models.dart';
import 'statistics_repository.dart';

/// The community's leaderboards: five measures, led by one player each.
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
    return FutureBuilder<List<Leaderboard>>(
      future: _boardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return ErrorState(onRetry: _refresh);
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
          EmptyState(
            icon: Icons.leaderboard_outlined,
            message: l10n.leaderboardsEmpty,
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
      padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.xxl),
      children: [
        for (final board in boards) LeaderboardCard(board: board),
        // Said once, and only when a rating is actually on screen: the figure
        // is the player's rating everywhere, not their rating here.
        if (showsRating) FootNote(l10n.leaderboardRatingNote),
      ],
    );
  }
}

/// One board: its measure, who leads it, and — on request — who is behind them.
///
/// **Collapsed is the default, and the collapsed board is the leader alone.**
/// Five boards of three rows is fifteen names on a phone screen, which is a
/// table; what a community actually opens this tab to see is who is top of each
/// measure. The rest is one tap away and stays out of the way until it is
/// asked for.
///
/// A board with nobody behind the leader shows no control at all. "Show more"
/// that reveals nothing is worse than no button.
class LeaderboardCard extends StatefulWidget {
  const LeaderboardCard({super.key, required this.board});

  final Leaderboard board;

  @override
  State<LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<LeaderboardCard> {
  bool _expanded = false;

  Leaderboard get _board => widget.board;

  String _title(AppLocalizations l10n) => switch (_board.kind) {
        LeaderboardKind.highestRated => l10n.leaderboardHighestRated,
        LeaderboardKind.topScorer => l10n.leaderboardTopScorer,
        LeaderboardKind.mostMvp => l10n.leaderboardMostMvp,
        LeaderboardKind.mostActive => l10n.leaderboardMostActive,
        LeaderboardKind.mostWins => l10n.leaderboardMostWins,
      };

  IconData get _icon => switch (_board.kind) {
        LeaderboardKind.highestRated => Icons.military_tech,
        LeaderboardKind.topScorer => Icons.sports_soccer,
        LeaderboardKind.mostMvp => Icons.star,
        LeaderboardKind.mostActive => Icons.directions_run,
        LeaderboardKind.mostWins => Icons.emoji_events,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final entries = _board.entries;
    final rest = entries.skip(1).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kPageMargin,
        Gap.xs + 2,
        kPageMargin,
        Gap.xs + 2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
              child: Row(
                children: [
                  Icon(_icon, size: 20, color: scheme.primary),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      _title(l10n),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            // The leader, always, and given the room a leader deserves.
            _LeaderRow(entry: entries.first, isRating: _board.kind.isRating),
            // The rest, at their own size, behind the control below.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: Gap.lg, indent: Gap.lg,
                            endIndent: Gap.lg),
                        for (final entry in rest)
                          _RunnerUpRow(
                            entry: entry,
                            isRating: _board.kind.isRating,
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            if (rest.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(
                      _expanded ? l10n.showLessLabel : l10n.showMoreLabel,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
  }
}

/// The player at the top of a board.
///
/// Deliberately not the same row as the ones below it. The whole point of the
/// collapsed board is that one name is the answer, and a leader drawn like a
/// list item makes the reader look for the list.
class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.isRating});

  final LeaderboardEntry entry;
  final bool isRating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              entry.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            formatBoardValue(entry.value, isRating: isRating),
            style: theme.textTheme.titleLarge?.copyWith(color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// A player behind the leader. Same information, quieter.
class _RunnerUpRow extends StatelessWidget {
  const _RunnerUpRow({required this.entry, required this.isRating});

  final LeaderboardEntry entry;
  final bool isRating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.xs),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              entry.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            formatBoardValue(entry.value, isRating: isRating),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A rating keeps its one decimal (`OP-1`); a count is a whole number and
/// showing it as "5.0" would read as a different kind of figure.
String formatBoardValue(num value, {required bool isRating}) =>
    isRating ? (value as double).toStringAsFixed(1) : '${value.toInt()}';

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
      radius: 14,
      backgroundColor: isTop
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      child: Text(
        '$rank',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isTop
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
