import '../communities/community_models.dart';

/// Membership's port into the data provider: who belongs to a community, what
/// role they hold, and the writes that change that.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Whether a role is *sufficient* for an action is
/// decided by the database and, for what the screens offer, above this layer —
/// an adapter never determines permissions (OP-2).
abstract interface class MemberAdapter {
  Future<List<CommunityMember>> fetchMembers(String communityId);

  /// The signed-in user's role in [communityId], or null when they are not a
  /// member or there is no session.
  Future<CommunityRole?> fetchMyRole(String communityId);

  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  );

  Future<void> transferOwnership(String communityId, String newOwnerId);

  Future<void> removeMember(String communityId, String userId);
}
