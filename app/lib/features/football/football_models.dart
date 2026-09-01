// Domain Models for public football activity (OP-3).
//
// These are deliberately not the match, team and statistics models the rest of
// the product uses. Those carry things a cross-community reader is not given —
// a match's creator and capacity, a registration's queue mechanics, a
// community's join policy — and widening them with nullable fields would leave
// every reader guessing which are populated on which screen. A separate set
// says it once, in the type: this is football that has been played, and there is
// nothing else in it.
//
// Everything here is read-only. Nothing has a write path, because reading
// football activity is the whole of what Cycle 2 does; registering, arranging
// and recording all still belong to the member-only paths that already own them.

/// Which kind of participant a row describes.
///
/// A Professional Guest (migration `0044`) has no account, so none of the
/// columns an account supplies is available for them. This is what tells a
/// caller which of the two it is holding without inspecting for nulls, and it
/// is what stops a guest being followed to a profile that does not exist.
enum ParticipantType { user, professionalGuest }

/// Where a participant stood.
enum FootballTeam { a, b }

/// Whether somebody made the starting side or the reserve queue.
enum ParticipationStatus { confirmed, reserve }

/// A match that has been played, as football history shows it.
///
/// "Completed" is the database's rule and not this model's: a match counts once
/// its status says so or its end time has passed (migrations `0029`, `0037`), so
/// a historical fixture (`0054`) qualifies the moment it is recorded.
class CompletedMatch {
  const CompletedMatch({
    required this.matchId,
    required this.communityId,
    required this.communityName,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.isHistorical,
    required this.hasResult,
    this.title,
    this.teamAScore,
    this.teamBScore,
    this.mvp,
  });

  final String matchId;
  final String communityId;
  final String communityName;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  /// True when this is the record of a fixture that had already been played
  /// when it was created. It is football either way; the flag exists because
  /// the product labels it.
  final bool isHistorical;

  /// Whether a score has been recorded. False is the ordinary state of a match
  /// that finished an hour ago and has not been written up yet — not an error,
  /// and not a match to hide.
  final bool hasResult;

  final String? title;

  /// Null exactly when [hasResult] is false. Held apart rather than defaulted
  /// to zero, because 0–0 is a result somebody recorded and "not yet recorded"
  /// is not.
  final int? teamAScore;
  final int? teamBScore;

  /// Best on the pitch, or null. Optional since migration `0033`: an organizer
  /// may record a score without naming one, and may name one later or never.
  final FootballParticipant? mvp;

  /// What to show as the headline: the title if it has one, else the location.
  /// The same rule `Match.displayName` uses, so a match reads the same way
  /// wherever it appears.
  String get displayName =>
      (title != null && title!.isNotEmpty) ? title! : location;
}

/// Somebody who took part in a match, of either kind.
///
/// The identity is the pair [type] and [userId]/[guestId]: exactly one of the
/// two ids is set, and which one is set is what [type] reports. [displayName] is
/// what to draw in both cases, so a caller that only renders a name never has to
/// branch.
///
/// There is no phone, no email, no authentication identifier and no date of
/// birth here, and there is nowhere to put one — the server does not send them
/// (migration `0057`) and this model could not carry them if it did.
class FootballParticipant {
  const FootballParticipant({
    required this.type,
    required this.displayName,
    this.userId,
    this.guestId,
    this.avatarUrl,
    this.primaryPosition,
    this.secondaryPosition,
    this.overallRating,
  });

  final ParticipantType type;
  final String displayName;

  /// Set for a registered player, null for a Professional Guest.
  final String? userId;

  /// Set for a Professional Guest, null for a registered player. Match-scoped:
  /// the same person guesting twice is two guests, because a guest is a name on
  /// one team sheet and not an account.
  final String? guestId;

  /// Null for a guest, who has no picture to have, and null for a player who
  /// has not set one.
  final String? avatarUrl;

  /// All null for a guest: none of the Core Player Inputs (§4.1) exists for
  /// somebody without a profile.
  final String? primaryPosition;
  final String? secondaryPosition;
  final double? overallRating;

  /// Whether this participant has a profile to open. A guest does not, which is
  /// the one rule every screen showing a participant has to honour.
  bool get opensProfile => type == ParticipantType.user && userId != null;
}

/// One participant's place in a completed match's roster.
class MatchRosterEntry {
  const MatchRosterEntry({
    required this.matchId,
    required this.participant,
    required this.status,
    required this.rosterPosition,
  });

  final String matchId;
  final FootballParticipant participant;
  final ParticipationStatus status;

  /// The order the organizer arranged, or arrival order where they did not
  /// (migration `0053`). Carried so a roster is shown in the order it was saved.
  final int rosterPosition;
}

/// One participant's place in the stored lineup.
class LineupSlot {
  const LineupSlot({
    required this.matchId,
    required this.participant,
    required this.team,
    required this.goals,
    required this.isMvp,
    required this.isOutOfPosition,
    this.assignedPosition,
  });

  final String matchId;
  final FootballParticipant participant;
  final FootballTeam team;

  /// Where the engine put them. Null is possible for a guest, whose position is
  /// nullable by migration `0051`.
  final String? assignedPosition;

  /// Goals credited to this participant in this match. Zero is the ordinary
  /// case and is not an absence.
  final int goals;

  final bool isMvp;

  /// Playing away from their primary position, per BTGE §5.1. Always false for
  /// a guest, whose assignment basis is GUEST rather than TRANSITION.
  final bool isOutOfPosition;
}

/// A community's football record.
///
/// The three figures the Community Dashboard already reports, plus the MVP
/// count that sits beside them in the same table. No new measure is introduced:
/// Cycle 2 publishes what the product already counts.
class CommunityFootballStats {
  const CommunityFootballStats({
    required this.communityId,
    required this.communityName,
    required this.completedMatches,
    required this.players,
    required this.goals,
    required this.mvpCount,
  });

  final String communityId;
  final String communityName;

  /// Matches played, under the database's completed rule.
  final int completedMatches;

  /// How many players have an all-time record in this community. Not the
  /// roster: somebody who has joined but never finished a match has no record
  /// and is not counted.
  final int players;

  final int goals;
  final int mvpCount;
}

/// One player's all-time record inside one community.
///
/// The population a leaderboard ranks, carrying the counters it ranks on and
/// the Global Rating (`OP-1`) it reads for Highest Rated. Guests never appear:
/// the statistics tables are keyed by user, and a guest has no user.
class CommunityPlayerStats {
  const CommunityPlayerStats({
    required this.communityId,
    required this.userId,
    required this.displayName,
    required this.overallRating,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goals,
    required this.mvpCount,
    this.avatarUrl,
    this.primaryPosition,
    this.secondaryPosition,
  });

  final String communityId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? primaryPosition;
  final String? secondaryPosition;
  final double overallRating;
  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int goals;
  final int mvpCount;
}
