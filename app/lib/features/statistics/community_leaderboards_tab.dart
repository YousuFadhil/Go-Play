import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../profile/player_identity.dart';
import 'statistics_models.dart';

/// How one leaderboard is drawn.
///
/// This file used to hold the Leaderboards **tab** as well — its own period
/// selector, its own load and its own Share action. That tab is gone: the
/// Dashboard and the Leaderboards are one Statistics tab now, with one period
/// between them and one card to share, and a second selector was the thing that
/// let a reader leave the two halves describing different weeks.
///
/// What stays is the presentation, because the boards themselves did not
/// change. [CommunityStatisticsTab] draws exactly these cards, runner-ups and
/// all.

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
              padding:
                  const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
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
                        const Divider(
                            height: Gap.lg, indent: Gap.lg, endIndent: Gap.lg),
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
          // The identity is the control; the rank and the value are not. A
          // board row is a player like any other row that names one.
          Expanded(
            child: _BoardIdentity(
              entry: entry,
              style: theme.textTheme.titleMedium,
              radius: 18,
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
            child: _BoardIdentity(
              entry: entry,
              style: theme.textTheme.bodyMedium,
              radius: 14,
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

/// The player named by a board row: their face, their name, and the way into
/// their profile.
///
/// Only the identity is the control. The rank badge and the value sit outside
/// it, because neither is a player and a board is still a table of figures —
/// and the block is an `InkWell`, which loses the gesture arena to a scroll, so
/// the list still scrolls under a finger that starts on a name.
///
/// A board holds only registered community members: `v_community_members`
/// inner-joins active profiles, so there is no unnamed entry here and no
/// Professional Guest — they hold no membership and no career.
class _BoardIdentity extends StatelessWidget {
  const _BoardIdentity({
    required this.entry,
    required this.style,
    required this.radius,
  });

  final LeaderboardEntry entry;
  final TextStyle? style;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return PlayerIdentityTap(
      key: Key('boardIdentity_${entry.userId}'),
      userId: entry.userId,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: [
            PlayerAvatar(
              avatarUrl: entry.avatarUrl,
              fullName: entry.fullName,
              radius: radius,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                entry.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
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
