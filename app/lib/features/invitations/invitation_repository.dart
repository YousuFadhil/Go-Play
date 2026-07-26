import 'package:supabase_flutter/supabase_flutter.dart';

import '../communities/community_errors.dart';
import '../communities/community_models.dart';
import 'invitation_models.dart';

/// Data access for invitations: issuing, revoking and accepting them, plus the
/// name lookup an organizer needs to choose an invitee.
class InvitationRepository {
  InvitationRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _columns =
      'id, community_id, invitee_id, role, status, expires_at';

  /// Admins may invite players; only an owner may offer the admin role.
  Future<void> createInvitation(
    String communityId,
    String inviteeId,
    CommunityRole role,
  ) =>
      callCommunityRpc(_client, 'create_invitation', {
        'p_community_id': communityId,
        'p_invitee_id': inviteeId,
        'p_role': role.dbValue,
      });

  Future<void> revokeInvitation(String invitationId) =>
      callCommunityRpc(_client, 'revoke_invitation', {
        'p_invitation_id': invitationId,
      });

  Future<void> acceptInvitation(String invitationId) =>
      callCommunityRpc(_client, 'accept_invitation', {
        'p_invitation_id': invitationId,
      });

  /// Invitations addressed to the current user.
  Future<List<Invitation>> fetchMyInvitations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('invitations')
        .select('$_columns, community:communities(name)')
        .eq('invitee_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return [for (final row in rows) Invitation.fromJson(row)];
  }

  /// Pending invitations an organizer has issued for one community.
  Future<List<Invitation>> fetchCommunityInvitations(String communityId) async {
    final rows = await _client
        .from('invitations')
        .select('$_columns, '
            'invitee:users!invitations_invitee_id_fkey(full_name)')
        .eq('community_id', communityId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return [for (final row in rows) Invitation.fromJson(row)];
  }

  /// Creates (or hands back) the shareable link for a community, or for one
  /// match within it. Owner and admin only, enforced in the RPC.
  Future<String> createInviteLink({
    required String communityId,
    String? matchId,
  }) async {
    final token = await callCommunityRpc(_client, 'create_invite_link', {
      'p_community_id': communityId,
      'p_match_id': matchId,
    });
    return token as String;
  }

  Future<void> revokeInviteLink(String linkId) =>
      callCommunityRpc(_client, 'revoke_invite_link', {
        'p_link_id': linkId,
      });

  /// The community's live links, for the organizer who shares and revokes them.
  /// Revoked links are not listed: revoking is how an organizer says they are
  /// done with one. RLS limits this to owners and admins.
  Future<List<InviteLinkSummary>> fetchInviteLinks(String communityId) async {
    final rows = await _client
        .from('community_invite_links')
        .select('id, token, kind, created_at, '
            'match:matches(title, start_at)')
        .eq('community_id', communityId)
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return [for (final row in rows) InviteLinkSummary.fromJson(row)];
  }

  /// What an invitation shows before anyone commits to it. Deliberately works
  /// signed out, so the person deciding whether to install the app can see what
  /// they are being invited to.
  Future<InviteLinkPreview> previewInviteLink(String token) async {
    final rows = await _client.rpc('preview_invite_link', params: {
      'p_token': token,
    }) as List<dynamic>;
    if (rows.isEmpty) {
      return const InviteLinkPreview(state: InviteLinkState.notFound);
    }
    return InviteLinkPreview.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Joins the community and, for a Type B invitation, registers for the match.
  /// A registration that fails does not undo the membership; the reason comes
  /// back in the result rather than as an exception.
  Future<InviteRedemption> redeemInviteLink(String token) async {
    final rows = await callCommunityRpc(_client, 'redeem_invite_link', {
      'p_token': token,
    }) as List<dynamic>;
    return InviteRedemption.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Finds players by name so an organizer can pick who to invite. Scoped to
  /// the invitation flow: profiles are already readable by any signed-in user,
  /// and this only searches them.
  Future<List<UserSummary>> searchUsers(String query) async {
    final term = query.trim();
    // Below two characters the search is not selective enough to be useful.
    if (term.length < 2) return const [];
    final rows = await _client
        .from('users')
        .select('id, full_name, primary_position')
        .ilike('full_name', '%$term%')
        .limit(20);
    return [for (final row in rows) UserSummary.fromJson(row)];
  }
}
