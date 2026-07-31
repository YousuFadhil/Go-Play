/// A seat in a match: a starting place, or a place in the reserve queue.
enum RegistrationStatus { confirmed, reserve }

/// A player registered in a match (confirmed seat or reserve queue).
class MatchRegistration {
  const MatchRegistration({
    required this.userId,
    required this.fullName,
    required this.position,
    required this.status,
    required this.registrationOrder,
  });

  final String userId;
  final String fullName;
  final String position;
  final RegistrationStatus status;
  final int registrationOrder;
}

/// Match lifecycle: open -> full (registration closed) -> back to open when a
/// slot frees. Completed is automatic once the scheduled end time passes.
enum MatchStatus { open, full, completed }

/// A football match scheduled inside a community.
class Match {
  const Match({
    required this.id,
    required this.communityId,
    required this.createdBy,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.startingPlayers,
    required this.maxRegistration,
    required this.status,
    this.title,
    this.description,
    this.communityName,
  });

  final String id;
  final String communityId;
  final String createdBy;
  final String location;
  final DateTime startAt;
  final DateTime endAt;

  /// The first [startingPlayers] registrations are starting players; the rest
  /// are reserve, up to [maxRegistration] where registration closes.
  final int startingPlayers;
  final int maxRegistration;
  final MatchStatus status;
  final String? title;
  final String? description;

  /// Present only when the query joins the community (e.g. Home screen).
  final String? communityName;

  /// What to show as the match's headline: the title if set, else location.
  String get displayName =>
      (title != null && title!.isNotEmpty) ? title! : location;

  /// Completion is time-driven, so it is derived here as well as stored: a
  /// match whose end time has passed is completed even if the stored row has
  /// not been touched since.
  MatchStatus get effectiveStatus =>
      endAt.isAfter(DateTime.now()) ? status : MatchStatus.completed;

  bool get isCompleted => effectiveStatus == MatchStatus.completed;

  /// From the scheduled start until the end the match is locked: no
  /// registrations, withdrawals or organizer roster changes.
  bool get isLocked => !isCompleted && !startAt.isAfter(DateTime.now());

  /// True while players can still register or withdraw.
  bool get isOpenForChanges => !isCompleted && !isLocked;
}
