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

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      message: json['message'] as String,
      isRead: json['is_read'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      matchId: json['match_id'] as String?,
    );
  }
}
