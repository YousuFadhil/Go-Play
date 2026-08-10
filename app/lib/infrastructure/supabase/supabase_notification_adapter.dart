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

  @override
  Future<PushPreferences> fetchPushPreferences() => guarded(() async {
        // No row is the ordinary state of an account that never opened the
        // settings screen, so it is the defaults rather than an error.
        final row = await _client
            .from('notification_push_preferences')
            .select('match_push, community_push, mute_all')
            .maybeSingle();
        return pushPreferencesFromRow(row);
      });

  @override
  Future<void> savePushPreferences(PushPreferences preferences) =>
      guarded(() async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return;
        // The row is created on first save. `user_id` is the primary key, so
        // an upsert is the whole of "set my preferences" whether or not the
        // account has any yet.
        await _client.from('notification_push_preferences').upsert({
          'user_id': userId,
          'match_push': preferences.matchPush,
          'community_push': preferences.communityPush,
          'mute_all': preferences.muteAll,
        });
      });

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) =>
      guarded(() async {
        // An RPC rather than an upsert: the same device signing in as somebody
        // else has to take the token away from the previous holder, and that
        // row is invisible to this session under the table's own read rule.
        await _client.rpc(
          'register_push_token',
          params: {'p_token': token, 'p_platform': platform},
        );
      });

  @override
  Future<void> removeDevice(String token) => guarded(() async {
        await _client
            .from('notification_push_tokens')
            .delete()
            .eq('token', token);
      });
}
