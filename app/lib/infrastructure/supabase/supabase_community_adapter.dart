import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/communities/community_adapter.dart';
import '../../features/communities/community_models.dart';
import 'mappers/community_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the community port.
///
/// Writes go through Postgres RPCs so multi-step operations stay atomic and
/// RLS stays simple (no custom backend).
class SupabaseCommunityAdapter implements CommunityAdapter {
  SupabaseCommunityAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// What a community read is allowed to ask for.
  ///
  /// `join_code` is not on this list and cannot be put back: migration `0055`
  /// revoked SELECT on the column for both client roles, so a request naming it
  /// is refused by the server rather than filtered here. The organizer's read is
  /// [fetchJoinCode].
  static const _columns =
      'id, owner_id, name, description, join_policy';

  @override
  Future<List<Community>> fetchMyCommunities() => guarded(() async {
        final userId = _client.auth.currentUser!.id;
        final rows = await _client
            .from('community_members')
            .select('community:communities($_columns)')
            .eq('user_id', userId)
            .order('created_at', ascending: false);

        return [
          for (final row in rows)
            communityFromRow(row['community'] as Map<String, dynamic>),
        ];
      });

  @override
  Future<List<Community>> fetchAllCommunities() => guarded(() async {
        final rows = await _client
            .from('communities')
            .select(_columns)
            .order('created_at', ascending: false);
        return [for (final row in rows) communityFromRow(row)];
      });

  @override
  Future<Community> fetchCommunity(String communityId) => guarded(() async {
        final row = await _client
            .from('communities')
            .select(_columns)
            .eq('id', communityId)
            .single();
        return communityFromRow(row);
      });

  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) =>
      guarded(() async {
        final result = await _client.rpc('create_community', params: {
          'p_name': name,
          'p_description': description,
          'p_join_policy': joinPolicyToDb(joinPolicy),
        });
        return result as String;
      });

  @override
  Future<String> joinCommunity(String communityId) => guarded(() async {
        final result = await _client
            .rpc('join_community', params: {'p_community_id': communityId});
        return result as String;
      });

  @override
  Future<String> joinCommunityByCode(String code) => guarded(() async {
        final result = await _client
            .rpc('join_community_by_code', params: {'p_code': code});
        return result as String;
      });

  /// The `communities_update_owner` policy is what enforces ownership here;
  /// RLS filters the row out for anyone else, so the update would silently
  /// match nothing — asking for the row back is how that becomes an error
  /// instead of a no-op that looks like success.
  @override
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
      guarded(() async {
        final rows = await _client
            .from('communities')
            .update({'join_policy': joinPolicyToDb(joinPolicy)})
            .eq('id', communityId)
            .select('id');
        if (rows.isEmpty) throw const AuthorizationFailure();
      });

  /// The join code, through `community_join_code` (migration `0055`).
  ///
  /// An RPC rather than a column, because the question is not "which row" but
  /// "may this caller hold the credential" — and the function is what decides,
  /// from `has_community_role(..., 'admin')`. It refuses with `NOT_AUTHORIZED`,
  /// which reaches this layer as an `AuthorizationFailure`.
  @override
  Future<String> fetchJoinCode(String communityId) => guarded(
        () async {
          final code = await _client.rpc(
            'community_join_code',
            params: {'p_community_id': communityId},
          );
          return code as String;
        },
        operation: 'rpc community_join_code',
      );

  @override
  Future<CommunityInvitePreview> previewInvite(String code) => guarded(() async {
        final rows = await _client.rpc('preview_community_invite', params: {
          'p_code': code,
        }) as List<dynamic>;
        if (rows.isEmpty) return const CommunityInvitePreview(isValid: false);
        return invitePreviewFromRow(rows.first as Map<String, dynamic>);
      });

  @override
  Future<String> regenerateJoinCode(String communityId) => guarded(() async {
        final code = await _client.rpc('regenerate_join_code', params: {
          'p_community_id': communityId,
        });
        return code as String;
      });

  @override
  Future<void> deleteCommunity(String communityId) => guarded(() async {
        await _client.rpc('delete_community', params: {
          'p_community_id': communityId,
        });
      });
}
