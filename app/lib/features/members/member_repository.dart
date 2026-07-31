import '../../infrastructure/supabase/supabase_member_adapter.dart';
import '../communities/community_models.dart';
import 'member_adapter.dart';

/// Data access for membership of a community: who belongs to it, what role
/// they hold, and the owner-or-admin operations that change that.
///
/// Every operation here is a straight pass-through: the database decides who
/// may do what, and this layer adds no product reasoning of its own.
class MemberRepository {
  MemberRepository([MemberAdapter? adapter])
      : _adapter = adapter ?? SupabaseMemberAdapter();

  final MemberAdapter _adapter;

  Future<List<CommunityMember>> fetchMembers(String communityId) =>
      _adapter.fetchMembers(communityId);

  /// The caller's role in [communityId], or null when they are not a member.
  /// Used to decide which controls to show; the server enforces the real rule.
  Future<CommunityRole?> fetchMyRole(String communityId) =>
      _adapter.fetchMyRole(communityId);

  /// Owner only. Promotes [userId] to admin or demotes to player.
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      _adapter.setMemberRole(communityId, userId, role);

  /// Owner only. The caller becomes an admin and [newOwnerId] becomes owner.
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      _adapter.transferOwnership(communityId, newOwnerId);

  /// Owner removes admins and players; an admin removes players only. The
  /// member is also withdrawn from every match in the community.
  Future<void> removeMember(String communityId, String userId) =>
      _adapter.removeMember(communityId, userId);
}
