import 'package:supabase_flutter/supabase_flutter.dart';

import '../communities/community_errors.dart';
import '../communities/community_models.dart';

/// Data access for membership of a community: who belongs to it, what role
/// they hold, and the owner-or-admin operations that change that.
class MemberRepository {
  MemberRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<CommunityMember>> fetchMembers(String communityId) async {
    final rows = await _client
        .from('community_members')
        .select('role, created_at, user:users(id, full_name, '
            'primary_position)')
        .eq('community_id', communityId)
        .order('created_at', ascending: true);

    return [for (final row in rows) CommunityMember.fromJson(row)];
  }

  /// The caller's role in [communityId], or null when they are not a member.
  /// Used to decide which controls to show; the server enforces the real rule.
  Future<CommunityRole?> fetchMyRole(String communityId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('community_members')
        .select('role')
        .eq('community_id', communityId)
        .eq('user_id', userId)
        .maybeSingle();
    final role = row?['role'] as String?;
    return role == null ? null : CommunityRole.fromDb(role);
  }

  /// Owner only. Promotes [userId] to admin or demotes to player.
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      callCommunityRpc(_client, 'set_member_role', {
        'p_community_id': communityId,
        'p_user_id': userId,
        'p_role': role.dbValue,
      });

  /// Owner only. The caller becomes an admin and [newOwnerId] becomes owner.
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      callCommunityRpc(_client, 'transfer_ownership', {
        'p_community_id': communityId,
        'p_new_owner_id': newOwnerId,
      });

  /// Owner removes admins and players; an admin removes players only. The
  /// member is also withdrawn from every match in the community.
  Future<void> removeMember(String communityId, String userId) =>
      callCommunityRpc(_client, 'remove_member', {
        'p_community_id': communityId,
        'p_user_id': userId,
      });
}
