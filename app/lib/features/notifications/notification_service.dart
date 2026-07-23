import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_models.dart';

class NotificationService {
  NotificationService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<AppNotification>> fetchAll() async {
    final rows = await _client
        .from('notifications')
        .select('id, type, message, is_read, created_at, match_id')
        .order('created_at', ascending: false)
        .limit(100);
    return [for (final row in rows) AppNotification.fromJson(row)];
  }

  Future<int> unreadCount() async {
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('is_read', false);
    return rows.length;
  }

  Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}
