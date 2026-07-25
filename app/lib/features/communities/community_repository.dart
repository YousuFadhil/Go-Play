import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_errors.dart';
import 'community_models.dart';

/// Data access for the community aggregate itself: what exists, what the user
/// can see, and creating, joining or deleting one. Membership lives in
/// MemberRepository and invitations in InvitationRepository.
///
/// Writes go through Postgres RPCs so multi-step operations stay atomic and
/// RLS stays simple (no custom backend).
class CommunityRepository {
  CommunityRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _columns =
      'id, owner_id, name, description, is_private, join_code';

  /// Communities the current user belongs to (RLS scopes the membership rows).
  Future<List<Community>> fetchMyCommunities() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('community_members')
        .select('community:communities($_columns)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        Community.fromJson(row['community'] as Map<String, dynamic>),
    ];
  }

  /// What the user can see and act on: [mine] are joined communities,
  /// [discover] are public ones not joined yet. RLS already returns only
  /// public communities here, so private ones never leak.
  Future<({List<Community> mine, List<Community> discover})>
      fetchCommunitiesOverview() async {
    final mine = await fetchMyCommunities();
    final myIds = {for (final c in mine) c.id};

    final rows = await _client
        .from('communities')
        .select(_columns)
        .eq('is_private', false)
        .order('created_at', ascending: false);

    final discover = [
      for (final row in rows)
        if (!myIds.contains(row['id'] as String)) Community.fromJson(row),
    ];
    return (mine: mine, discover: discover);
  }

  /// Creates a community and adds the creator as owner. Returns its id.
  Future<String> createCommunity({
    required String name,
    String? description,
    required bool isPrivate,
  }) async {
    final result = await _client.rpc('create_community', params: {
      'p_name': name.trim(),
      'p_description':
          description?.trim().isEmpty ?? true ? null : description!.trim(),
      'p_is_private': isPrivate,
    });
    return result as String;
  }

  /// Joins a community by its join code. Returns the community id.
  Future<String> joinCommunityByCode(String code) async {
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

  Future<Community> fetchCommunity(String communityId) async {
    final row = await _client
        .from('communities')
        .select(_columns)
        .eq('id', communityId)
        .single();
    return Community.fromJson(row);
  }

  /// Owner only. Removes the community and everything belonging to it.
  Future<void> deleteCommunity(String communityId) =>
      callCommunityRpc(_client, 'delete_community', {
        'p_community_id': communityId,
      });
}
