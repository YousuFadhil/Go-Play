import 'package:supabase_flutter/supabase_flutter.dart';

import '../invitations/invitation_models.dart';
import 'community_models.dart';

/// Raised when a join code does not match any active group.
class CommunityNotFoundException implements Exception {}

/// Raised when the user is already a member of the group.
class AlreadyMemberOfCommunityException implements Exception {}

/// Failures raised by the community-management and invitation RPCs.
enum CommunityActionError {
  notAuthorized,
  cannotChangeOwnRole,
  cannotRemoveSelf,
  cannotRemoveOwner,
  alreadyOwner,
  memberNotFound,
  alreadyMember,
  invitationExists,
  invitationNotFound,
  invitationNotPending,
  invitationExpired,
  invalidRole,
  unknown,
}

class CommunityActionException implements Exception {
  const CommunityActionException(this.error);

  final CommunityActionError error;
}

/// Data access for groups. Writes go through Postgres RPC functions so that
/// multi-step operations stay atomic and RLS stays simple (no custom backend).
class GroupService {
  GroupService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Groups the current user belongs to (RLS scopes the membership rows).
  Future<List<Community>> fetchMyGroups() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('community_members')
        .select('community:communities(id, owner_id, name, description, '
            'is_private, join_code)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        Community.fromJson(row['community'] as Map<String, dynamic>),
    ];
  }

  /// Groups the user can see and act on: [mine] are joined groups, [discover]
  /// are public groups the user has not joined yet. RLS already returns only
  /// public groups (plus the user's own) here, so private groups never leak.
  Future<({List<Community> mine, List<Community> discover})>
      fetchGroupsOverview() async {
    final mine = await fetchMyGroups();
    final myIds = {for (final g in mine) g.id};

    final rows = await _client
        .from('communities')
        .select('id, owner_id, name, description, is_private, join_code')
        .eq('is_private', false)
        .order('created_at', ascending: false);

    final discover = [
      for (final row in rows)
        if (!myIds.contains(row['id'] as String)) Community.fromJson(row),
    ];
    return (mine: mine, discover: discover);
  }

  /// Creates a group and adds the creator as owner. Returns the group id.
  Future<String> createGroup({
    required String name,
    String? description,
    required bool isPrivate,
  }) async {
    final result = await _client.rpc('create_community', params: {
      'p_name': name.trim(),
      'p_description': description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      'p_is_private': isPrivate,
    });
    return result as String;
  }

  /// Joins a group by its join code. Returns the group id.
  Future<String> joinGroupByCode(String code) async {
    try {
      final result = await _client.rpc('join_community_by_code', params: {
        'p_code': code.trim().toUpperCase(),
      });
      return result as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('COMMUNITY_NOT_FOUND')) {
        throw CommunityNotFoundException();
      }
      if (e.message.contains('ALREADY_MEMBER')) {
        throw AlreadyMemberOfCommunityException();
      }
      rethrow;
    }
  }

  Future<Community> fetchGroup(String communityId) async {
    final row = await _client
        .from('communities')
        .select('id, owner_id, name, description, is_private, join_code')
        .eq('id', communityId)
        .single();
    return Community.fromJson(row);
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

  Future<List<CommunityMember>> fetchMembers(String communityId) async {
    final rows = await _client
        .from('community_members')
        .select('role, created_at, user:users(id, full_name, '
            'primary_position)')
        .eq('community_id', communityId)
        .order('created_at', ascending: true);

    return [for (final row in rows) CommunityMember.fromJson(row)];
  }

  // --- Community management (Phase 3 RPCs) ---

  /// Owner only. Promotes [userId] to admin or demotes to player.
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      _action('set_member_role', {
        'p_community_id': communityId,
        'p_user_id': userId,
        'p_role': role.dbValue,
      });

  /// Owner only. The caller becomes an admin and [newOwnerId] becomes owner.
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      _action('transfer_ownership', {
        'p_community_id': communityId,
        'p_new_owner_id': newOwnerId,
      });

  /// Owner removes admins and players; an admin removes players only. The
  /// member is also withdrawn from every match in the community.
  Future<void> removeMember(String communityId, String userId) =>
      _action('remove_member', {
        'p_community_id': communityId,
        'p_user_id': userId,
      });

  /// Owner only. Removes the community and everything belonging to it.
  Future<void> deleteCommunity(String communityId) =>
      _action('delete_community', {'p_community_id': communityId});

  // --- Invitations ---

  /// Admins may invite players; only an owner may offer the admin role.
  Future<void> createInvitation(
    String communityId,
    String inviteeId,
    CommunityRole role,
  ) =>
      _action('create_invitation', {
        'p_community_id': communityId,
        'p_invitee_id': inviteeId,
        'p_role': role.dbValue,
      });

  Future<void> revokeInvitation(String invitationId) =>
      _action('revoke_invitation', {'p_invitation_id': invitationId});

  Future<void> acceptInvitation(String invitationId) =>
      _action('accept_invitation', {'p_invitation_id': invitationId});

  /// Invitations addressed to the current user.
  Future<List<Invitation>> fetchMyInvitations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('invitations')
        .select('id, community_id, invitee_id, role, status, expires_at, '
            'community:communities(name)')
        .eq('invitee_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return [for (final row in rows) Invitation.fromJson(row)];
  }

  /// Pending invitations an organizer has issued for one community.
  Future<List<Invitation>> fetchCommunityInvitations(String communityId) async {
    final rows = await _client
        .from('invitations')
        .select('id, community_id, invitee_id, role, status, expires_at, '
            'invitee:users!invitations_invitee_id_fkey(full_name)')
        .eq('community_id', communityId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return [for (final row in rows) Invitation.fromJson(row)];
  }

  /// Finds players by name so an organizer can pick who to invite. Profiles
  /// are already readable by any signed-in user; this only searches them.
  Future<List<UserSummary>> searchUsers(String query) async {
    final term = query.trim();
    if (term.length < 2) return const [];
    final rows = await _client
        .from('users')
        .select('id, full_name, primary_position')
        .ilike('full_name', '%$term%')
        .limit(20);
    return [for (final row in rows) UserSummary.fromJson(row)];
  }

  Future<void> _action(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw CommunityActionException(_mapActionError(e.message));
    }
  }

  CommunityActionError _mapActionError(String message) {
    for (final entry in _actionErrors.entries) {
      if (message.contains(entry.key)) return entry.value;
    }
    return CommunityActionError.unknown;
  }

  static const _actionErrors = <String, CommunityActionError>{
    'NOT_AUTHORIZED': CommunityActionError.notAuthorized,
    'CANNOT_CHANGE_OWN_ROLE': CommunityActionError.cannotChangeOwnRole,
    'CANNOT_REMOVE_SELF': CommunityActionError.cannotRemoveSelf,
    'CANNOT_REMOVE_OWNER': CommunityActionError.cannotRemoveOwner,
    'ALREADY_OWNER': CommunityActionError.alreadyOwner,
    'MEMBER_NOT_FOUND': CommunityActionError.memberNotFound,
    'ALREADY_MEMBER': CommunityActionError.alreadyMember,
    'INVITATION_EXISTS': CommunityActionError.invitationExists,
    'INVITATION_NOT_FOUND': CommunityActionError.invitationNotFound,
    'INVITATION_NOT_PENDING': CommunityActionError.invitationNotPending,
    'INVITATION_EXPIRED': CommunityActionError.invitationExpired,
    'INVALID_ROLE': CommunityActionError.invalidRole,
  };
}
