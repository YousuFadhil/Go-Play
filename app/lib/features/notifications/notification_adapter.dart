import 'notification_models.dart';

/// Notifications' port into the data provider.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Which events produce a notification is decided
/// by the database, not here — and so is which of them is worth a push.
abstract interface class NotificationAdapter {
  /// The signed-in user's notifications, newest first.
  Future<List<AppNotification>> fetchAll();

  Future<int> unreadCount();

  Future<void> markAllRead();

  /// Marks one notice read, for a reader who acted on that one.
  ///
  /// Opening the Notification Center still marks everything read; this is the
  /// narrower case of tapping a single notice, where marking the rest read
  /// would claim something the reader never did. Harmless on a notice that is
  /// already read.
  Future<void> markRead(String notificationId);

  /// The player's push switches, or the defaults when they have never set any.
  Future<PushPreferences> fetchPushPreferences();

  Future<void> savePushPreferences(PushPreferences preferences);

  /// Records this device as somewhere the player can be reached.
  ///
  /// [token] identifies the device to Firebase and is unique across accounts,
  /// so registering a token that already belongs to somebody else moves it
  /// rather than duplicating it — a shared or resold phone stops receiving the
  /// previous owner's notices.
  Future<void> registerDevice({required String token, required String platform});

  /// Forgets a device. Push stops; the notification history is untouched.
  Future<void> removeDevice(String token);
}
