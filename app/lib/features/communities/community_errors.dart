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
/// lives in exactly one place.
Future<void> callCommunityRpc(
  SupabaseClient client,
  String function,
  Map<String, dynamic> params,
) async {
  try {
    await client.rpc(function, params: params);
  } on PostgrestException catch (e) {
    throw CommunityActionException(communityActionErrorFrom(e.message));
  }
}
