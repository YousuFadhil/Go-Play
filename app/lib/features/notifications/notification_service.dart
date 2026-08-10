import '../../infrastructure/supabase/supabase_notification_adapter.dart';
import 'notification_adapter.dart';
import 'notification_models.dart';

/// The user's own notifications. A straight pass-through: which events produce
/// a notification is decided by the database.
///
/// The push half is here too, and it is only ever *delivery*. The Notification
/// Center is the history and the source of truth; a push is a copy of one of
/// its rows that happened to leave the building. Nothing below can suppress a
/// notice, and nothing below is consulted when one is written.
class NotificationService {
  NotificationService([NotificationAdapter? adapter])
      : _adapter = adapter ?? SupabaseNotificationAdapter();

  final NotificationAdapter _adapter;

  Future<List<AppNotification>> fetchAll() => _adapter.fetchAll();

  Future<int> unreadCount() => _adapter.unreadCount();

  Future<void> markAllRead() => _adapter.markAllRead();

  Future<PushPreferences> fetchPushPreferences() =>
      _adapter.fetchPushPreferences();

  Future<void> savePushPreferences(PushPreferences preferences) =>
      _adapter.savePushPreferences(preferences);

  Future<void> registerDevice({
    required String token,
    required String platform,
  }) =>
      _adapter.registerDevice(token: token, platform: platform);

  Future<void> removeDevice(String token) => _adapter.removeDevice(token);
}
