import '../../../features/profile/player_record_models.dart';

/// Rows from the recent-form and highlight functions, as Domain Models.
///
/// **A row whose outcome this build cannot name is dropped, not guessed.**
/// `MatchOutcome.fromWireName` answers null for a value added by a newer
/// database, and a badge the app cannot label would be worse on a profile than
/// four badges where there were five. The same rule the analytics enum applies
/// to an unknown event name.

/// The authenticated form: outcome, goals, MVP, and which match it was.
RecentForm recentFormFromRows(List<dynamic> rows) {
  final entries = <RecentFormEntry>[];
  for (final row in rows.cast<Map<String, dynamic>>()) {
    final outcome = MatchOutcome.fromWireName(row['outcome'] as String?);
    if (outcome == null) continue;
    entries.add(RecentFormEntry(
      outcome: outcome,
      goals: row['goals'] as int? ?? 0,
      isMvp: row['is_mvp'] as bool? ?? false,
      matchId: row['match_id'] as String?,
      communityId: row['community_id'] as String?,
      communityName: row['community_name'] as String?,
      occurredAt: _instant(row['start_at']),
      scoreFor: row['score_for'] as int?,
      scoreAgainst: row['score_against'] as int?,
    ));
  }
  // Ordered by the function, never re-sorted here. See [RecentForm.entries].
  return RecentForm(entries);
}

/// The public form: the same three facts, and nothing that names a fixture.
///
/// The rows arrive ordered by `sequence_no`, which exists precisely so that a
/// caller can put five badges in the right order without being told when any
/// of the matches was played.
RecentForm publicRecentFormFromRows(List<dynamic> rows) {
  final entries = <RecentFormEntry>[];
  for (final row in rows.cast<Map<String, dynamic>>()) {
    final outcome = MatchOutcome.fromWireName(row['outcome'] as String?);
    if (outcome == null) continue;
    entries.add(RecentFormEntry(
      outcome: outcome,
      goals: row['goals'] as int? ?? 0,
      isMvp: row['is_mvp'] as bool? ?? false,
      // The public contract carries the scoreline too (`0080`) and nothing
      // else about the fixture: two numbers and a W name no match.
      scoreFor: row['score_for'] as int?,
      scoreAgainst: row['score_against'] as int?,
    ));
  }
  return RecentForm(entries);
}

/// The highlight candidates `player_recent_highlights` or
/// `public_player_recent_highlight` returned — at most one of each kind.
///
/// **Candidates, not the answer.** Which one a profile shows is
/// [RecentHighlight.mostRecent]'s decision, and nothing here pre-empts it by
/// dropping one.
///
/// Each row names its own kind, so a kind added to the contract later arrives
/// named rather than assumed; one this build does not know is skipped, for the
/// same reason an unknown outcome is no badge. A row with no date is skipped
/// too: it cannot take part in "the most recent wins", and a rule that cannot
/// be applied is better answered with no candidate than with an arbitrary one.
List<RecentHighlight> highlightCandidatesFromRows(List<dynamic> rows) => [
      for (final row in rows.cast<Map<String, dynamic>>())
        if (_highlightFromRow(row) case final highlight?) highlight,
    ];

RecentHighlight? _highlightFromRow(Map<String, dynamic> row) {
  final kind = switch (row['highlight_type'] as String?) {
    'MVP' => HighlightKind.mvp,
    'TEAM_OF_PERIOD' => HighlightKind.teamOfPeriod,
    _ => null,
  };
  if (kind == null) return null;
  final occurredAt = _instant(row['occurred_at']);
  if (occurredAt == null) return null;
  return RecentHighlight(
    kind: kind,
    occurredAt: occurredAt,
    communityName: row['community_name'] as String?,
    periodKey: row['period_key'] as String?,
    period: kind == HighlightKind.teamOfPeriod
        ? HighlightPeriod.fromWireName(row['period_type'] as String?)
        : null,
  );
}

/// A `timestamptz` as the device reads it.
///
/// Local, as every other timestamp in this app is: the profile shows a date to
/// the person holding the phone, and the comparison the highlight rule makes is
/// between two values that went through this same function.
DateTime? _instant(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}
