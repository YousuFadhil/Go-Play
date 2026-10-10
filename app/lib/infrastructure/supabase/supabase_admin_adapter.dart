import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/admin/admin_adapter.dart';
import '../../features/admin/admin_models.dart';
import '../../features/auth/auth_models.dart' show PlayerPosition;
import '../../features/profile/profile_models.dart' show ProfileVisibility;
import 'mappers/admin_mapper.dart';
import 'supabase_avatars.dart';
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

  /// The Overview, in one round trip.
  ///
  /// `returns table` with one row, so PostgREST sends a one-element list. An
  /// empty one is not something the function can produce -- it always returns
  /// exactly one row -- but it is checked rather than indexed blindly, so a
  /// surprise arrives as a mapped [InfrastructureFailure] and the screen's
  /// retry, not as a range error.
  @override
  Future<AdminAnalyticsOverview> analyticsOverview() => guarded(
        () async {
          final result = await _client.rpc('admin_analytics_overview_v2');
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();
          return adminAnalyticsOverviewFromRow(rows.first);
        },
        operation: 'rpc admin_analytics_overview_v2',
      );

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

  /// One account in figures, through `0068`.
  ///
  /// `returns table` with one row, so a one-element list arrives. The function
  /// raises `USER_NOT_FOUND` rather than returning nothing, so an empty result
  /// is not a state it can reach -- checked anyway, so a surprise becomes a
  /// mapped failure and the screen's retry rather than a range error.
  @override
  Future<AdminUserActivitySummary> userActivitySummary(String userId) =>
      guarded(
        () async {
          final result = await _client.rpc(
            'admin_user_activity_summary',
            params: {'p_user_id': userId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();
          return adminUserActivityFromRow(rows.first);
        },
        operation: 'rpc admin_user_activity_summary',
      );

  /// The account's recent activity. `p_limit` is left to the function's own
  /// default and clamp -- how many rows a timeline is worth is a decision the
  /// database already makes, and passing one from here would be a second.
  @override
  Future<List<AdminUserActivityEvent>> userActivityTimeline(String userId) =>
      guarded(
        () async {
          final rows = await _client.rpc(
            'admin_user_activity_timeline',
            params: {'p_user_id': userId},
          ) as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminActivityEventFromRow(row),
          ];
        },
        operation: 'rpc admin_user_activity_timeline',
      );

  @override
  Future<List<AdminAuditEntry>> listAuditLog() => guarded(
        () async {
          final rows =
              await _client.rpc('admin_list_audit_log') as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminAuditEntryFromRow(row),
          ];
        },
        operation: 'rpc admin_list_audit_log',
      );

  /// The four drill-downs, through `0069`.
  ///
  /// `p_limit` is left to each function's own default and clamp. How many rows
  /// a page is worth is a decision the database already makes; passing one from
  /// here would be a second, free to disagree.
  @override
  Future<List<AdminDrilldownUser>> drilldownUsers(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      guarded(
        () async {
          final rows = await _client.rpc(
            'admin_analytics_users_v2',
            params: {'p_metric': metric.wireName, 'p_offset': offset},
          ) as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminDrilldownUserFromRow(row),
          ];
        },
        operation: 'rpc admin_analytics_users_v2',
      );

  @override
  Future<List<AdminDrilldownCommunity>> drilldownCommunities(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      guarded(
        () async {
          final rows = await _client.rpc(
            'admin_analytics_communities_v2',
            params: {'p_metric': metric.wireName, 'p_offset': offset},
          ) as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminDrilldownCommunityFromRow(row),
          ];
        },
        operation: 'rpc admin_analytics_communities_v2',
      );

  @override
  Future<List<AdminDrilldownMatch>> drilldownMatches(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      guarded(
        () async {
          final rows = await _client.rpc(
            'admin_analytics_matches_v2',
            params: {'p_metric': metric.wireName, 'p_offset': offset},
          ) as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminDrilldownMatchFromRow(row),
          ];
        },
        operation: 'rpc admin_analytics_matches_v2',
      );

  /// The one drill-down the database takes a window for rather than a metric
  /// name, because both registration figures are the same query over a
  /// different number of days.
  @override
  Future<List<AdminDrilldownRegistration>> drilldownRegistrations(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      guarded(
        () async {
          final rows = await _client.rpc(
            'admin_analytics_registrations_v2',
            params: {
              'p_period_days': metric.periodDays,
              'p_offset': offset,
            },
          ) as List<dynamic>;
          return [
            for (final row in rows.cast<Map<String, dynamic>>())
              adminDrilldownRegistrationFromRow(row),
          ];
        },
        operation: 'rpc admin_analytics_registrations_v2',
      );

  /// The two inspection reads. Each returns one row; the function raises
  /// `COMMUNITY_NOT_FOUND` / `MATCH_NOT_FOUND` rather than returning nothing,
  /// so an empty result is not a state it can reach -- checked anyway, so a
  /// surprise becomes a mapped failure and the screen's retry.
  @override
  Future<AdminCommunityInspection> communityInspection(String communityId) =>
      guarded(
        () async {
          final result = await _client.rpc(
            'admin_get_community_inspection',
            params: {'p_community_id': communityId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();
          return adminCommunityInspectionFromRow(rows.first);
        },
        operation: 'rpc admin_get_community_inspection',
      );

  @override
  Future<AdminMatchInspection> matchInspection(String matchId) => guarded(
        () async {
          final result = await _client.rpc(
            'admin_get_match_inspection',
            params: {'p_match_id': matchId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();
          return adminMatchInspectionFromRow(rows.first);
        },
        operation: 'rpc admin_get_match_inspection',
      );

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

  /// The id of the session, which is all the console asks of it. No request.
  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  /// One account's data and settings, through `0095`.
  ///
  /// `returns table` with one row, so a one-element list arrives. The function
  /// raises `USER_NOT_FOUND` rather than returning nothing, so an empty result
  /// is not a state it can reach -- checked anyway, so a surprise becomes a
  /// mapped failure and the section's retry rather than a range error.
  @override
  Future<AdminUserAccount> userAccount(String userId) => guarded(
        () async {
          final result = await _client.rpc(
            'admin_get_user_account',
            params: {'p_user_id': userId},
          );
          final rows = (result as List<dynamic>).cast<Map<String, dynamic>>();
          if (rows.isEmpty) throw const InfrastructureFailure();
          final row = rows.first;
          return adminUserAccountFromRow(
            row,
            avatarUrl: SupabaseAvatars.publicUrl(
              _client,
              row['avatar_path'] as String?,
            ),
          );
        },
        operation: 'rpc admin_get_user_account',
      );

  /// The five account edits, through `0095`. Each checks `is_system_admin()`
  /// server-side and refuses the caller themselves and any System Admin; each
  /// is a no-op, with no audit event, when nothing it carries would change.
  /// Nothing here is authorization and nothing here decides what a valid value
  /// is.
  @override
  Future<void> updateUserAccount(
    String userId, {
    required String fullName,
    required String phone,
    String? reason,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'admin_update_user_account',
            params: adminUpdateAccountParams(
              userId,
              fullName: fullName,
              phone: phone,
              reason: reason,
            ),
          );
        },
        operation: 'rpc admin_update_user_account',
      );

  @override
  Future<void> updateUserPlayerProfile(
    String userId, {
    required DateTime? dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
    String? reason,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'admin_update_user_player_profile',
            params: adminUpdatePlayerProfileParams(
              userId,
              dateOfBirth: dateOfBirth,
              primaryPosition: primaryPosition,
              secondaryPosition: secondaryPosition,
              reason: reason,
            ),
          );
        },
        operation: 'rpc admin_update_user_player_profile',
      );

  @override
  Future<void> updateUserPrivacy(
    String userId, {
    required ProfileVisibility visibility,
    required bool ageVisible,
    String? reason,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'admin_update_user_privacy',
            params: adminUpdatePrivacyParams(
              userId,
              visibility: visibility,
              ageVisible: ageVisible,
              reason: reason,
            ),
          );
        },
        operation: 'rpc admin_update_user_privacy',
      );

  @override
  Future<void> updateUserDefaultWilayat(
    String userId, {
    required int? wilayatCode,
    String? reason,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'admin_update_user_default_wilayat',
            params: adminUpdateDefaultWilayatParams(
              userId,
              wilayatCode: wilayatCode,
              reason: reason,
            ),
          );
        },
        operation: 'rpc admin_update_user_default_wilayat',
      );

  /// The two read-only previews, through `0096`. Each returns one jsonb
  /// document, which PostgREST sends as a JSON object; anything else is a
  /// surprise and becomes a mapped failure and the screen's retry. Nothing is
  /// written, and no audit event is recorded.
  @override
  Future<AdminMergePreview> previewAccountMerge({
    required String retainedUserId,
    required String sourceUserId,
  }) =>
      guarded(
        () async {
          final result = await _client.rpc(
            'admin_preview_account_merge',
            params: {
              'p_retained_user_id': retainedUserId,
              'p_source_user_id': sourceUserId,
            },
          );
          if (result is! Map) throw const InfrastructureFailure();
          return adminMergePreviewFromJson(result.cast<String, dynamic>());
        },
        operation: 'rpc admin_preview_account_merge',
      );

  /// The permanent merge (migration `0101`), requested through the
  /// `admin-merge-accounts` Edge Function. The function proves the caller is a System
  /// Admin, preflights the preview, removes the merged-in account's profile picture
  /// from Storage (which no SQL can do), and only then calls `admin_merge_accounts`:
  /// one database transaction that deletes the source's `auth.users` row itself, so
  /// there is no second call to make for the database or Auth side.
  ///
  /// **If the function answered 2xx, the merge happened.** The result is
  /// read leniently for that reason: a shape this build does not recognise is
  /// reported as a merge with an empty summary, never as a failure, because
  /// "failed" would invite a second attempt at something already done.
  @override
  Future<AdminMergeResult> mergeAccounts({
    required String retainedUserId,
    required String sourceUserId,
    required List<AdminMergeResolution> resolutions,
  }) =>
      guarded(
        () async {
          final response = await _client.functions.invoke(
            'admin-merge-accounts',
            body: adminMergeAccountsParams(
              retainedUserId: retainedUserId,
              sourceUserId: sourceUserId,
              resolutions: resolutions,
            ),
          );
          final result = response.data;
          return adminMergeResultFromJson(
            result is Map ? result.cast<String, dynamic>() : const {},
            retainedUserId: retainedUserId,
            sourceUserId: sourceUserId,
          );
        },
        operation: 'function admin-merge-accounts',
      );

  @override
  Future<AdminDeletionPreview> previewAccountDeletion(String userId) => guarded(
        () async {
          final result = await _client.rpc(
            'admin_preview_account_deletion',
            params: {'p_user_id': userId},
          );
          if (result is! Map) throw const InfrastructureFailure();
          return adminDeletionPreviewFromJson(result.cast<String, dynamic>());
        },
        operation: 'rpc admin_preview_account_deletion',
      );

  @override
  Future<void> updateUserPushPreferences(
    String userId, {
    required bool matchPush,
    required bool communityPush,
    required bool muteAll,
    String? reason,
  }) =>
      guarded(
        () async {
          await _client.rpc(
            'admin_update_user_push_preferences',
            params: adminUpdatePushPreferencesParams(
              userId,
              matchPush: matchPush,
              communityPush: communityPush,
              muteAll: muteAll,
              reason: reason,
            ),
          );
        },
        operation: 'rpc admin_update_user_push_preferences',
      );
}
