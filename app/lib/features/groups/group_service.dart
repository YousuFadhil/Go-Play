import 'package:supabase_flutter/supabase_flutter.dart';

import 'group_models.dart';

/// Raised when a join code does not match any active group.
class GroupNotFoundException implements Exception {}

/// Raised when the user is already a member of the group.
class AlreadyMemberException implements Exception {}

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
        throw GroupNotFoundException();
      }
      if (e.message.contains('ALREADY_MEMBER')) {
        throw AlreadyMemberException();
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
}
