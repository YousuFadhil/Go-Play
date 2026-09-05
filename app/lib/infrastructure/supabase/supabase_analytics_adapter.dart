import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/build_info.dart';
import '../../features/analytics/analytics_adapter.dart';
import '../../features/analytics/analytics_models.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the analytics port.
///
/// One RPC, `record_product_event` (migration `0067`), which is the only way a
/// row reaches `product_events` — no client holds INSERT on that table, so
/// there is no direct-write path for this class to take even if it wanted one.
class SupabaseAnalyticsAdapter implements AnalyticsAdapter {
  SupabaseAnalyticsAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// Sends the event, with the build that produced it.
  ///
  /// **Who acted is not sent.** The RPC reads `auth.uid()` itself; there is no
  /// parameter here for a user id and adding one would defeat the point of the
  /// server deriving it.
  ///
  /// Platform and version come from [BuildInfo] rather than from the caller, so
  /// every event carries the same answer and no screen has to remember to.
  @override
  Future<void> record(
    ProductEvent event, {
    String? communityId,
    String? matchId,
  }) =>
      guarded(
        () async {
          await _client.rpc('record_product_event', params: {
            'p_event_name': event.wireName,
            'p_community_id': communityId,
            'p_match_id': matchId,
            'p_platform': BuildInfo.platform,
            'p_app_version': BuildInfo.appVersion,
          });
        },
        operation: 'rpc record_product_event',
      );
}
