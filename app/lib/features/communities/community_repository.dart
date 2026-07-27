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
      'id, owner_id, name, description, join_policy, join_code';

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
  /// [discover] is everything else. Every community is visible now; what
  /// differs is whether joining needs the code.
  Future<({List<Community> mine, List<Community> discover})>
      fetchCommunitiesOverview() async {
    final mine = await fetchMyCommunities();
    final myIds = {for (final c in mine) c.id};

    final rows = await _client
        .from('communities')
        .select(_columns)
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
    required JoinPolicy joinPolicy,
  }) async {
    final result = await _client.rpc('create_community', params: {
      'p_name': name.trim(),
      'p_description':
          description?.trim().isEmpty ?? true ? null : description!.trim(),
      'p_join_policy': joinPolicy.dbValue,
    });
    return result as String;
  }

  /// Joins a community whose policy is OPEN. A CODE_REQUIRED community refuses
  /// here and is joined through [joinCommunityByCode] instead.
  Future<String> joinCommunity(String communityId) async {
    try {
      final result = await _client
          .rpc('join_community', params: {'p_community_id': communityId});
      return result as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('JOIN_CODE_REQUIRED')) {
        throw JoinCodeRequiredException();
      }
      if (e.message.contains('COMMUNITY_NOT_FOUND')) {
        throw CommunityNotFoundException();
      }
      if (e.message.contains('ALREADY_MEMBER')) {
        throw AlreadyMemberOfCommunityException();
      }
      rethrow;
    }
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

  /// Owner only. The `communities_update_owner` policy is what enforces that;
  /// RLS filters the row out for anyone else, so the update would silently
  /// match nothing — asking for the row back is how that becomes an error
  /// instead of a no-op that looks like success.
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) async {
    final rows = await _client
        .from('communities')
        .update({'join_policy': joinPolicy.dbValue})
        .eq('id', communityId)
        .select('id');
    if (rows.isEmpty) {
      throw const CommunityActionException(CommunityActionError.notAuthorized);
    }
  }

  /// What a shared invitation offers. Works signed out, which is the point:
  /// someone deciding whether to install the app can see what they are joining.
  Future<CommunityInvitePreview> previewInvite(String code) async {
    final rows = await _client.rpc('preview_community_invite', params: {
      'p_code': code,
    }) as List<dynamic>;
    if (rows.isEmpty) return const CommunityInvitePreview(isValid: false);
    return CommunityInvitePreview.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Issues a new join code, which is how a leaked invitation is invalidated:
  /// the code is the only invitation identifier, so replacing it retires the
  /// old one. Members, matches and registrations are untouched. Owner and admin.
  Future<String> regenerateJoinCode(String communityId) async {
    final code = await callCommunityRpc(_client, 'regenerate_join_code', {
      'p_community_id': communityId,
    });
    return code as String;
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
