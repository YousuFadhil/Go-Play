import '../../infrastructure/supabase/supabase_notification_adapter.dart';
import 'notification_adapter.dart';
import 'notification_models.dart';

/// The user's own notifications. A straight pass-through: which events produce
/// a notification is decided by the database.
class NotificationService {
  NotificationService([NotificationAdapter? adapter])
      : _adapter = adapter ?? SupabaseNotificationAdapter();

  final NotificationAdapter _adapter;

  Future<List<AppNotification>> fetchAll() => _adapter.fetchAll();

  Future<int> unreadCount() => _adapter.unreadCount();

  Future<void> markAllRead() => _adapter.markAllRead();
}
