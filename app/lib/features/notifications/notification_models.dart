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
