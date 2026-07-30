import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/notifications/notification_adapter.dart';
import '../../features/notifications/notification_models.dart';
import 'mappers/notification_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the notifications port. RLS scopes every read
/// to the signed-in user, so none of these queries names them.
class SupabaseNotificationAdapter implements NotificationAdapter {
  SupabaseNotificationAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> fetchAll() => guarded(() async {
        final rows = await _client
            .from('notifications')
            .select('id, type, message, is_read, created_at, match_id')
            .order('created_at', ascending: false)
            .limit(100);
        return [for (final row in rows) notificationFromRow(row)];
      });

  @override
  Future<int> unreadCount() => guarded(() async {
        final rows = await _client
            .from('notifications')
            .select('id')
            .eq('is_read', false);
        return rows.length;
      });

  @override
  Future<void> markAllRead() => guarded(() async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return;
        await _client
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', userId)
            .eq('is_read', false);
      });
}
