import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/admin/admin_adapter.dart';
import '../../features/admin/admin_models.dart';
import 'mappers/admin_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the administration port.
///
/// Every method goes through an `admin_*` RPC that checks `is_system_admin()`
/// server-side. Nothing here is authorization: the database refuses regardless
/// of what this class returns.
class SupabaseAdminAdapter implements AdminAdapter {
  SupabaseAdminAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// Without a session there is nobody to ask about, so this reports that
  /// rather than spending a request to be told the same thing. What to do with
  /// an unanswered question is the repository's call, not this layer's.
  @override
  Future<bool> isSystemAdmin() => guarded(() async {
        if (_client.auth.currentUser == null) {
          throw const AuthenticationFailure();
        }
        final result = await _client.rpc('is_system_admin');
        return result == true;
      });

  @override
  Future<List<AdminUserSummary>> listUsers(String? search) => guarded(() async {
        final rows = await _client.rpc(
          'admin_list_users',
          params: {'p_search': search},
        ) as List<dynamic>;
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            adminUserFromRow(row),
        ];
      });

  @override
  Future<List<AdminCommunitySummary>> listCommunities(String? search) =>
      guarded(() async {
        final rows = await _client.rpc(
          'admin_list_communities',
          params: {'p_search': search},
        ) as List<dynamic>;
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            adminCommunityFromRow(row),
        ];
      });

  @override
  Future<List<AdminMatchSummary>> listMatches(String? search) =>
      guarded(() async {
        final rows = await _client.rpc(
          'admin_list_matches',
          params: {'p_search': search},
        ) as List<dynamic>;
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            adminMatchFromRow(row),
        ];
      });

  /// Suspension and reactivation, through the four `0064` / `0065` RPCs.
  ///
  /// Each checks `is_system_admin()` server-side and each is idempotent: asking
  /// for a state a record is already in succeeds and writes nothing. Nothing
  /// here is authorization, and nothing here decides what a valid reason is --
  /// the reason arrives already trimmed and non-empty.
  @override
  Future<void> suspendUser(String id, String reason) => guarded(
        () async {
          await _client.rpc('admin_suspend_user', params: {
            'p_user_id': id,
            'p_reason': reason,
          });
        },
        operation: 'rpc admin_suspend_user',
      );

  @override
  Future<void> reactivateUser(String id) => guarded(
        () async {
          await _client.rpc('admin_reactivate_user', params: {
            'p_user_id': id,
          });
        },
        operation: 'rpc admin_reactivate_user',
      );

  @override
  Future<void> suspendCommunity(String id, String reason) => guarded(
        () async {
          await _client.rpc('admin_suspend_community', params: {
            'p_community_id': id,
            'p_reason': reason,
          });
        },
        operation: 'rpc admin_suspend_community',
      );

  @override
  Future<void> reactivateCommunity(String id) => guarded(
        () async {
          await _client.rpc('admin_reactivate_community', params: {
            'p_community_id': id,
          });
        },
        operation: 'rpc admin_reactivate_community',
      );
}
