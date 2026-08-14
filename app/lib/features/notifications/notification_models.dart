/// A notification addressed to the current user.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.matchId,
    this.matchTitle,
  });

  final String id;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final String? matchId;

  /// The title of the match this notice is about, read through
  /// `notifications.match_id -> matches.id`.
  ///
  /// Null for a notice that names no match, **and for one whose match has since
  /// been deleted** — `match_id` is `on delete set null`, so there is nothing
  /// left to join to. Both are the same absence to a reader and are rendered
  /// the same way: no subtitle.
  ///
  /// Separate from [message] rather than replacing it. `message` is what the
  /// database wrote, in one language, and is the push body; this is the join's
  /// answer and is what the Notification Center shows. They currently agree for
  /// match-scoped notices, and nothing depends on them continuing to.
  final String? matchTitle;
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
