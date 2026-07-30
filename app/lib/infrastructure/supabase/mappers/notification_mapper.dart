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
    );
