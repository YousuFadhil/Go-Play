enum RegistrationStatus {
  confirmed('confirmed'),
  reserve('reserve');

  const RegistrationStatus(this.dbValue);

  final String dbValue;

  static RegistrationStatus fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value);
}

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

  factory MatchRegistration.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return MatchRegistration(
      userId: user['id'] as String,
      fullName: user['full_name'] as String,
      position: user['primary_position'] as String,
      status: RegistrationStatus.fromDb(json['status'] as String),
      registrationOrder: json['registration_order'] as int,
    );
  }
}

/// Match lifecycle: open -> full (registration closed) -> back to open when a
/// slot frees. Completed is automatic once the scheduled end time passes.
enum MatchStatus {
  open('open'),
  full('full'),
  completed('completed');

  const MatchStatus(this.dbValue);

  final String dbValue;

  static MatchStatus fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value,
          orElse: () => MatchStatus.open);
}

/// A football match scheduled inside a group.
class Match {
  const Match({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.startingPlayers,
    required this.maxRegistration,
    required this.status,
    this.title,
    this.description,
    this.groupName,
  });

  final String id;
  final String groupId;
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

  /// Present only when the query joins the group (e.g. Home screen).
  final String? groupName;

  /// What to show as the match's headline: the title if set, else location.
  String get displayName => (title != null && title!.isNotEmpty)
      ? title!
      : location;

  /// Completion is time-driven, so it is derived here as well as stored: a
  /// match whose end time has passed is completed even if the stored row has
  /// not been touched since.
  MatchStatus get effectiveStatus =>
      endAt.isAfter(DateTime.now()) ? status : MatchStatus.completed;

  bool get isCompleted => effectiveStatus == MatchStatus.completed;

  /// From the scheduled start until the end the match is locked: no
  /// registrations, withdrawals or organizer roster changes.
  bool get isLocked =>
      !isCompleted && !startAt.isAfter(DateTime.now());

  /// True while players can still register or withdraw.
  bool get isOpenForChanges => !isCompleted && !isLocked;

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String,
      location: json['location'] as String,
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      startingPlayers: json['starting_players'] as int,
      maxRegistration: json['max_registration'] as int,
      status: MatchStatus.fromDb(json['status'] as String),
      title: json['title'] as String?,
      description: json['description'] as String?,
      groupName: (json['group'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}
