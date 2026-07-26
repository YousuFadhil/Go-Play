import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

String formatMatchTime(BuildContext context, Match match) {
  final locale = Localizations.localeOf(context).toString();
  final day = DateFormat.yMMMEd(locale).format(match.startAt);
  return '$day • ${formatTimeRange(context, match.startAt, match.endAt)}';
}

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          child: Icon(completed ? Icons.event_available : Icons.sports_soccer),
        ),
        title: Text(
          match.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Home lists matches from several communities, so it still needs to
            // say which one — below the name rather than crowding into it.
            if (showCommunityName && match.communityName != null)
              Text(match.communityName!,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            if (hasName)
              Text(match.location,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(formatMatchTime(context, match)),
            // Playing capacity, which is startingPlayers. Not maxRegistration:
            // that is starting players plus the global reserve allowance
            // (DD-06), so it would promise a six-a-side match twelve players.
            Text(l10n.matchCapacityLabel(match.startingPlayers)),
          ],
        ),
        trailing: showStatus ? Text(matchStatusLabel(context, status)) : null,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MatchDetailsScreen(matchId: match.id),
            ),
          );
          onChanged?.call();
        },
      ),
    );
  }
}
