/// A notification addressed to the current user.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.matchId,
  });

  final String id;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final String? matchId;
}

/// The three switches a player has over push.
///
/// Three, and deliberately not one per notification type. These govern
/// **delivery only**: every notice is written to the Notification Center
/// whatever is set here, so turning something off quietens the phone rather
/// than losing the history.
///
/// The defaults are the defaults the database applies to an account that has
/// never opened the settings screen — push on, nothing muted — so a missing row
/// and an untouched row mean the same thing everywhere.
class PushPreferences {
  const PushPreferences({
    this.matchPush = true,
    this.communityPush = true,
    this.muteAll = false,
  });

  /// Medium-priority match notices. High-priority ones ignore this.
  final bool matchPush;

  /// Medium-priority community notices. High-priority ones ignore this.
  final bool communityPush;

  /// The master switch, which outranks the other two **and outranks high
  /// priority**: a player who muted everything asked for silence, not for
  /// silence except when the system disagrees.
  final bool muteAll;

  PushPreferences copyWith({
    bool? matchPush,
    bool? communityPush,
    bool? muteAll,
  }) =>
      PushPreferences(
        matchPush: matchPush ?? this.matchPush,
        communityPush: communityPush ?? this.communityPush,
        muteAll: muteAll ?? this.muteAll,
      );
}
