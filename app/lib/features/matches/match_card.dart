import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/time_format.dart';
import 'match_details_screen.dart';
import 'match_models.dart';

String matchStatusLabelValue(AppLocalizations l10n, MatchStatus status) {
  return switch (status) {
    MatchStatus.open => l10n.matchStatusOpen,
    MatchStatus.full => l10n.matchStatusFull,
    MatchStatus.completed => l10n.matchStatusCompleted,
  };
}

String matchStatusLabel(BuildContext context, MatchStatus status) =>
    matchStatusLabelValue(context.l10n, status);

String formatMatchTime(BuildContext context, Match match) =>
    formatDayAndTimeRange(context, match.startAt, match.endAt);

/// Shared list tile for a match; used on Home and in community details.
class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    this.showCommunityName = false,
    this.onChanged,
  });

  final Match match;
  final bool showCommunityName;

  /// Called when the match may have changed (e.g. cancelled in details).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = match.effectiveStatus;
    final completed = status == MatchStatus.completed;
    // Show a status chip whenever the match is not simply open.
    final showStatus = status != MatchStatus.open;
    // displayName falls back to the location when a match has no name, so the
    // location only earns its own line when the title is a real name.
    final hasName = match.title?.isNotEmpty ?? false;

    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageMargin,
        vertical: Gap.xs + 2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MatchDetailsScreen(matchId: match.id),
              ),
            );
            onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The same date tile the public card leads with, so a match
                // reads as the same object before and after signing in. A
                // played match shows a tick instead: its date has stopped being
                // the useful thing about it.
                _MatchLeading(match: match, completed: completed),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      // Home lists matches from several communities, so it
                      // still needs to say which one — below the name rather
                      // than crowding into it.
                      if (showCommunityName && match.communityName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          match.communityName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: Gap.sm),
                      if (hasName) ...[
                        _Line(icon: Icons.place_outlined, text: match.location),
                        const SizedBox(height: Gap.xs),
                      ],
                      _Line(
                        icon: Icons.schedule_outlined,
                        text: formatMatchTime(context, match),
                      ),
                      const SizedBox(height: Gap.xs),
                      // Playing capacity, which is startingPlayers. Not
                      // maxRegistration: that is starting players plus the
                      // global reserve allowance (DD-06), so it would promise a
                      // six-a-side match twelve players.
                      _Line(
                        icon: Icons.groups_outlined,
                        text: l10n.matchCapacityLabel(match.startingPlayers),
                      ),
                    ],
                  ),
                ),
                if (showStatus) ...[
                  const SizedBox(width: Gap.sm),
                  _StatusChip(label: matchStatusLabel(context, status)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The date a match is on, or a tick once it has been played.
class _MatchLeading extends StatelessWidget {
  const _MatchLeading({required this.match, required this.completed});

  final Match match;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final container =
        completed ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final onContainer =
        completed ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: completed
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              child: Icon(Icons.event_available, size: 24, color: onContainer),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatWeekdayShort(context, match.startAt).toUpperCase(),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onContainer.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  formatDayNumber(context, match.startAt),
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: onContainer, height: 1.1),
                ),
                Text(
                  formatMonthShort(context, match.startAt),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onContainer.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
