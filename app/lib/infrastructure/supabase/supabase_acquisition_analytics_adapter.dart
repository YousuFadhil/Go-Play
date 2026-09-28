import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/build_info.dart';
import '../../features/analytics/acquisition_analytics_adapter.dart';
import '../../features/sharing/public_link.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the acquisition port: the two narrow RPCs of
/// migration `0089`, both writing the existing `product_events` table.
///
/// Nothing about the reader is sent. The anonymous open carries the link kind,
/// the platform word and the build version; the completion carries the
/// acquisition id and nothing else, because the database takes the account
/// from the session itself.
class SupabaseAcquisitionAnalyticsAdapter
    implements AcquisitionAnalyticsAdapter {
  SupabaseAcquisitionAnalyticsAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<String> recordAnonymousOpen(PublicLinkKind kind) => guarded(
        () async {
          final id = await _client.rpc(
            'record_anonymous_public_link_open',
            params: {
              'p_kind': kind.segment,
              'p_platform': BuildInfo.platform,
              'p_app_version': BuildInfo.appVersion,
            },
          );
          return id as String;
        },
        operation: 'rpc record_anonymous_public_link_open',
      );

  @override
  Future<void> recordSignupCompleted(String acquisitionId) => guarded(
        () async {
          await _client.rpc(
            'record_public_link_signup_completed',
            params: {'p_acquisition_id': acquisitionId},
          );
        },
        operation: 'rpc record_public_link_signup_completed',
      );
}
