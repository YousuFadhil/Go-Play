import 'package:supabase_flutter/supabase_flutter.dart';

/// Raised when a join code does not match any active community.
class CommunityNotFoundException implements Exception {}

/// Raised when the user is already a member of the community.
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
  inviteNotFound,
  inviteRevoked,
  inviteExpired,
  inviteMatchDeleted,
  matchNotFound,
  matchNotInCommunity,
  matchLocked,
  unknown,
}

class CommunityActionException implements Exception {
  const CommunityActionException(this.error);

  final CommunityActionError error;
}

const _actionErrors = <String, CommunityActionError>{
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
  // Shareable invite links. Distinct from the INVITATION_* codes above: those
  // belong to a directed invitation, these to a link.
  'INVITE_NOT_FOUND': CommunityActionError.inviteNotFound,
  'INVITE_REVOKED': CommunityActionError.inviteRevoked,
  'INVITE_EXPIRED': CommunityActionError.inviteExpired,
  'INVITE_MATCH_DELETED': CommunityActionError.inviteMatchDeleted,
  'MATCH_NOT_FOUND': CommunityActionError.matchNotFound,
  'MATCH_NOT_IN_COMMUNITY': CommunityActionError.matchNotInCommunity,
  'MATCH_LOCKED': CommunityActionError.matchLocked,
};

/// Maps a Postgres error message onto the typed error it carries.
CommunityActionError communityActionErrorFrom(String message) {
  for (final entry in _actionErrors.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return CommunityActionError.unknown;
}

/// Calls a community RPC and converts its failure into a typed exception.
/// Shared by the community, member and invitation repositories so the mapping
/// lives in exactly one place. Returns whatever the RPC returned, which most
/// callers ignore.
Future<dynamic> callCommunityRpc(
  SupabaseClient client,
  String function,
  Map<String, dynamic> params,
) async {
  try {
    return await client.rpc(function, params: params);
  } on PostgrestException catch (e) {
    throw CommunityActionException(communityActionErrorFrom(e.message));
  }
}
