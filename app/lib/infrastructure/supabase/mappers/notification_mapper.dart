import '../../../features/notifications/notification_models.dart';

/// Reads a notification row. `type` stays a string: the database decides what
/// kinds exist, and the app only displays the message it was sent.
AppNotification notificationFromRow(Map<String, dynamic> row) => AppNotification(
      id: row['id'] as String,
      type: row['type'] as String,
      message: row['message'] as String,
      isRead: row['is_read'] as bool,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      matchId: row['match_id'] as String?,
      matchTitle: _matchTitle(row),
    );

/// The embedded match's title, when the row was selected with one.
///
/// PostgREST returns an embedded to-one relation as a nested object, or null
/// when there is nothing to embed — a notice with no `match_id`, or one whose
/// match has been deleted. Reads defensively rather than casting, because the
/// same mapper serves selects that do not ask for the embed at all.
String? _matchTitle(Map<String, dynamic> row) {
  final match = row['matches'];
  if (match is! Map) return null;
  final title = match['title'];
  return title is String && title.trim().isNotEmpty ? title : null;
}

/// Reads a push-preferences row.
///
/// A null row is not an absence of preferences — it is an account that has
/// never opened the settings screen, and the answer is the same defaults the
/// column defaults give. Every field is coalesced for the same reason.
PushPreferences pushPreferencesFromRow(Map<String, dynamic>? row) =>
    PushPreferences(
      matchPush: row?['match_push'] as bool? ?? true,
      communityPush: row?['community_push'] as bool? ?? true,
      muteAll: row?['mute_all'] as bool? ?? false,
    );
