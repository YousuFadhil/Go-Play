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

enum MatchStatus {
  open('open'),
  cancelled('cancelled'),
  completed('completed');

  const MatchStatus(this.dbValue);

  final String dbValue;

  static MatchStatus fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value);
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
    required this.maxPlayers,
    required this.status,
    this.groupName,
  });

  final String id;
  final String groupId;
  final String createdBy;
  final String location;
  final DateTime startAt;
  final DateTime endAt;
  final int maxPlayers;
  final MatchStatus status;

  /// Present only when the query joins the group (e.g. Home screen).
  final String? groupName;

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String,
      location: json['location'] as String,
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      maxPlayers: json['max_players'] as int,
      status: MatchStatus.fromDb(json['status'] as String),
      groupName: (json['group'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}
