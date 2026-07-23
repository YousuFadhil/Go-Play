import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
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
  final start = DateFormat.Hm(locale).format(match.startAt);
  final end = DateFormat.Hm(locale).format(match.endAt);
  return '$day • $start - $end';
}

/// Shared list tile for a match; used on Home and in Group Details.
class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    this.showGroupName = false,
    this.onChanged,
  });

  final Match match;
  final bool showGroupName;

  /// Called when the match may have changed (e.g. cancelled in details).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final status = match.effectiveStatus;
    final completed = status == MatchStatus.completed;
    // Show a status chip whenever the match is not simply open.
    final showStatus = status != MatchStatus.open;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(completed ? Icons.event_available : Icons.sports_soccer),
        ),
        title: Text(
          showGroupName && match.groupName != null
              ? '${match.groupName} • ${match.displayName}'
              : match.displayName,
        ),
        subtitle: Text(formatMatchTime(context, match)),
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
