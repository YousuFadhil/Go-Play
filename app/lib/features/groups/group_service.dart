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
  Future<List<Group>> fetchMyGroups() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('group_members')
        .select('group:groups(id, owner_id, name, description, '
            'is_private, join_code)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        Group.fromJson(row['group'] as Map<String, dynamic>),
    ];
  }

  /// Creates a group and adds the creator as owner. Returns the group id.
  Future<String> createGroup({
    required String name,
    String? description,
    required bool isPrivate,
  }) async {
    final result = await _client.rpc('create_group', params: {
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
      final result = await _client.rpc('join_group_by_code', params: {
        'p_code': code.trim().toUpperCase(),
      });
      return result as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('GROUP_NOT_FOUND')) {
        throw GroupNotFoundException();
      }
      if (e.message.contains('ALREADY_MEMBER')) {
        throw AlreadyMemberException();
      }
      rethrow;
    }
  }

  Future<Group> fetchGroup(String groupId) async {
    final row = await _client
        .from('groups')
        .select('id, owner_id, name, description, is_private, join_code')
        .eq('id', groupId)
        .single();
    return Group.fromJson(row);
  }

  Future<List<GroupMember>> fetchMembers(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('role, created_at, user:users(id, full_name, '
            'primary_position)')
        .eq('group_id', groupId)
        .order('created_at', ascending: true);

    return [for (final row in rows) GroupMember.fromJson(row)];
  }
}
