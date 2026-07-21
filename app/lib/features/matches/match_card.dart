import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'match_details_screen.dart';
import 'match_models.dart';

String matchStatusLabel(BuildContext context, MatchStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    MatchStatus.open => l10n.matchStatusOpen,
    MatchStatus.cancelled => l10n.matchStatusCancelled,
    MatchStatus.completed => l10n.matchStatusCompleted,
  };
}

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
    final cancelled = match.status == MatchStatus.cancelled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(cancelled ? Icons.event_busy : Icons.sports_soccer),
        ),
        title: Text(
          showGroupName && match.groupName != null
              ? '${match.groupName} • ${match.location}'
              : match.location,
          style: cancelled
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(formatMatchTime(context, match)),
        trailing: cancelled
            ? Text(matchStatusLabel(context, match.status))
            : null,
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
