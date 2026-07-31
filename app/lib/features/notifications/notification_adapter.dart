import 'notification_models.dart';

/// Notifications' port into the data provider.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Which events produce a notification is decided
/// by the database, not here.
abstract interface class NotificationAdapter {
  /// The signed-in user's notifications, newest first.
  Future<List<AppNotification>> fetchAll();

  Future<int> unreadCount();

  Future<void> markAllRead();
}
