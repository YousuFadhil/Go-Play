import 'package:supabase_flutter/supabase_flutter.dart';

/// Raised when a join code does not match any active community.
class CommunityNotFoundException implements Exception {}

/// Raised when a community's policy is CODE_REQUIRED and no code was given.
class JoinCodeRequiredException implements Exception {}

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
