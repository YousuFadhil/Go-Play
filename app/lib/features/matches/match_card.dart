import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/football_components.dart';
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

/// A profile position as a localized word.
///
/// Here rather than in each screen for the reason [participantLabel] is here:
/// two screens showing the same roster must not be free to word it differently.
/// An unrecognised value is passed through, which is what a column carrying
/// something this build does not know about should show.
String positionLabelValue(AppLocalizations l10n, String position) =>
    switch (position) {
      'GK' => l10n.positionGk,
      'DEF' => l10n.positionDef,
      'MID' => l10n.positionMid,
      'FWD' => l10n.positionFwd,
      _ => position,
    };

/// What to call a participant on a roster or in a lineup.
///
/// A registered player is their own name. A Professional Guest is named through
/// the approved sentence — `محترف (الاسم)` in Arabic — which is why this is one
/// function and not a string built at each call site: the wording is a product
/// decision and the two screens that show a roster must not be free to differ.
String participantLabel(AppLocalizations l10n, MatchRegistration registration) =>
    registration.isProfessionalGuest
        ? l10n.professionalGuestName(registration.fullName)
        : registration.fullName;

/// The subtitle under a participant. A guest has no profile and therefore no
/// position: saying what they are is more use than leaving the line blank, and
/// it is the second place the roster makes the distinction visible.
String participantSubtitle(
  AppLocalizations l10n,
  MatchRegistration registration,
  String Function(String position) positionLabel,
) =>
    registration.isProfessionalGuest
        ? l10n.professionalGuestLabel
        : positionLabel(registration.position ?? '');

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
                  GoStatusChip(
                    label: matchStatusLabel(context, status),
                    tone: status.chipTone,
                  ),
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
