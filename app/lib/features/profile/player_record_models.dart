import 'package:flutter/foundation.dart';

import 'profile_models.dart';

/// How one match went for one player.
///
/// Three values, because a recorded result has two scores and the three cases
/// are exhaustive over them. There is no "unknown": a match with no recorded
/// result is not in Recent Form at all rather than in it as a fourth kind.
enum MatchOutcome {
  win('WIN'),
  draw('DRAW'),
  loss('LOSS');

  const MatchOutcome(this.wireName);

  /// What `player_recent_form` writes in its `outcome` column.
  final String wireName;

  /// The outcome [name] refers to, or null when it refers to none.
  ///
  /// Null is what an adapter turns into a dropped row. A build that met a
  /// fourth outcome would be a build older than the database, and showing a
  /// badge it cannot name would be worse than showing four badges.
  static MatchOutcome? fromWireName(String? name) {
    for (final outcome in values) {
      if (outcome.wireName == name) return outcome;
    }
    return null;
  }
}

/// One completed match, as it appears in a player's recent form.
///
/// **The fields a public reader never receives are nullable, and that is the
/// disclosure boundary rather than an accident of modelling.**
/// `public_player_recent_form` returns an outcome, a goal count and an MVP
/// flag; `player_recent_form` adds which match, which community and when.
/// Both produce this type, and a null [matchId] is exactly what "the reader
/// has no session, so the fixtures behind this record are not theirs to see"
/// looks like in Dart.
@immutable
class RecentFormEntry {
  const RecentFormEntry({
    required this.outcome,
    required this.goals,
    required this.isMvp,
    this.matchId,
    this.communityId,
    this.communityName,
    this.occurredAt,
  });

  final MatchOutcome outcome;

  /// What the player scored in this match. Zero is ordinary.
  final int goals;

  /// Whether the player was this match's MVP.
  final bool isMvp;

  /// Which match, for a reader allowed to know. Null on the public read.
  final String? matchId;
  final String? communityId;
  final String? communityName;

  /// Kick-off. Null on the public read, where the order is carried by the
  /// position of the row rather than by a date.
  final DateTime? occurredAt;
}

/// A player's last few completed matches, newest first.
///
/// **The summary is derived, never carried.** Matches, goals and wins are
/// counted from [entries] here rather than read from a second place, so the
/// three figures under the badges cannot disagree with the badges above them —
/// which is the same argument that put the win/draw/loss decision in
/// `match_result_contribution` and not in two of them.
@immutable
class RecentForm {
  const RecentForm(this.entries);

  /// A player with no completed matches. The ordinary state of a new account,
  /// and never an error.
  static const empty = RecentForm(<RecentFormEntry>[]);

  /// Newest first, as the database returned them. Nothing re-sorts this: the
  /// order is part of what was read, and a second sort would be a second
  /// opinion about which match is the most recent.
  final List<RecentFormEntry> entries;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// How many matches this window covers — five at most, and fewer for a
  /// player who has played fewer.
  int get matches => entries.length;

  int get goals => entries.fold(0, (total, entry) => total + entry.goals);

  int get wins =>
      entries.where((entry) => entry.outcome == MatchOutcome.win).length;
}

/// What kind of achievement a highlight is.
///
/// **Declared in precedence order, and the order is the tie rule.** Team of
/// Period is first, so when two achievements fall on the same effective date
/// the one that wins is the one declared first — stated once, here, rather
/// than as a condition inside the comparison.
enum HighlightKind {
  teamOfPeriod,
  mvp,
}

/// Which period a Team of Period award describes. Null on an MVP, which is a
/// match rather than a period.
enum HighlightPeriod {
  week,
  month;

  /// The value `period_type` carries, or null for anything else.
  static HighlightPeriod? fromWireName(String? name) => switch (name) {
        'weekly' => HighlightPeriod.week,
        'monthly' => HighlightPeriod.month,
        _ => null,
      };
}

/// One football achievement worth putting on a profile.
///
/// At most one of these is ever shown. A player with none has no section at
/// all — [RecentHighlight.mostRecent] answers null and the screen draws
/// nothing, rather than drawing a card that says there is nothing to say.
@immutable
class RecentHighlight {
  const RecentHighlight({
    required this.kind,
    required this.occurredAt,
    this.communityName,
    this.period,
  });

  final HighlightKind kind;

  /// Week or month, for a Team of Period award. Null for an MVP.
  final HighlightPeriod? period;

  /// When it happened: the match's kick-off for an MVP, and the last instant of
  /// the period for a Team of Period (migration `0079`). Both are "the football this is about", which is how
  /// every other statistics surface dates an achievement.
  final DateTime occurredAt;

  /// Which community it happened in, where that is known and public. Null is
  /// ordinary and costs the card a line, never the highlight.
  final String? communityName;

  /// The one to show, out of whatever the callers could find.
  ///
  /// The approved rule, and the whole of it:
  ///
  ///  * the most recent by [occurredAt] wins;
  ///  * on the same effective date, Team of Period wins;
  ///  * with nothing eligible, there is no highlight.
  ///
  /// Nulls are accepted in [candidates] so that a caller with no MVP and no XI
  /// can simply pass what it has. "Same effective date" is compared on the
  /// calendar day rather than the instant: a Team of Period describes a period
  /// rather than a moment, and comparing it to a kick-off time to the second
  /// would let the rule turn on which hour a match started.
  static RecentHighlight? mostRecent(
    Iterable<RecentHighlight?> candidates,
  ) {
    RecentHighlight? best;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (best == null) {
        best = candidate;
        continue;
      }
      final day = _day(candidate.occurredAt);
      final bestDay = _day(best.occurredAt);
      if (day.isAfter(bestDay)) {
        best = candidate;
      } else if (day.isAtSameMomentAs(bestDay) &&
          candidate.kind.index < best.kind.index) {
        // The tie rule, and the only place it is decided: a lower index is a
        // higher precedence, which [HighlightKind] states by its declaration
        // order.
        best = candidate;
      }
    }
    return best;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Everything a public Player Profile shows, read in one pass.
///
/// **One value because it is one screen.** The three public contracts are
/// asked together and arrive together, so a card composed from this cannot
/// carry a rating from one read and a form from another taken a moment later.
///
/// [profile] is a [PlayerProfileView] with `isSelf` false, because there is no
/// session for it to be self against — a visitor is never looking at their own
/// record through a public link.
@immutable
class PublicPlayerRecord {
  const PublicPlayerRecord({
    required this.profile,
    required this.form,
    this.highlight,
  });

  final PlayerProfileView profile;
  final RecentForm form;

  /// Null when the player has no eligible achievement, which is the ordinary
  /// case and draws no section.
  final RecentHighlight? highlight;
}
