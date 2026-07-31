import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/communities/community_models.dart';
import '../../features/members/member_adapter.dart';
import 'mappers/community_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the membership port. Every write is an RPC that
/// carries its own authorization check server-side.
class SupabaseMemberAdapter implements MemberAdapter {
  SupabaseMemberAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) =>
      guarded(() async {
        final rows = await _client
            .from('community_members')
            .select('role, created_at, user:users(id, full_name, '
                'primary_position)')
            .eq('community_id', communityId)
            .order('created_at', ascending: true);

        return [for (final row in rows) communityMemberFromRow(row)];
      });

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) => guarded(() async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return null;
        final row = await _client
            .from('community_members')
            .select('role')
            .eq('community_id', communityId)
            .eq('user_id', userId)
            .maybeSingle();
        final role = row?['role'] as String?;
        return role == null ? null : communityRoleFromDb(role);
      });

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      guarded(() async {
        await _client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': userId,
          'p_role': communityRoleToDb(role),
        });
      });

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      guarded(() async {
        await _client.rpc('transfer_ownership', params: {
          'p_community_id': communityId,
          'p_new_owner_id': newOwnerId,
        });
      });

  @override
  Future<void> removeMember(String communityId, String userId) =>
      guarded(() async {
        await _client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': userId,
        });
      });
}
