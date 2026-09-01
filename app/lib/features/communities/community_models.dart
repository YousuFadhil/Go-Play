/// How someone is allowed to join a community. Every community is visible;
/// this is the only thing that differs between them.
enum JoinPolicy {
  /// Anyone who can see the community can join it.
  open,

  /// Joining needs the join code, typed or carried by an invitation link.
  codeRequired,
}

/// Role a user holds inside a community. Roles are cumulative: an owner can do
/// everything an admin can, and an admin everything a player can — which is
/// what [atLeast] reads, so the declaration order is the hierarchy.
enum CommunityRole {
  player,
  admin,
  owner;

  /// True when this role includes everything [other] can do.
  bool atLeast(CommunityRole other) => index >= other.index;
}

/// What happened when someone asked to join a community.
///
/// All three are normal answers to the question, so none of them is a Failure:
/// a community is allowed to require its code, and asking to join one you are
/// already in is not an error. Failures stay reserved for the abnormal.
sealed class JoinCommunityOutcome {
  const JoinCommunityOutcome();
}

/// The user is now a member of [communityId].
final class JoinedCommunity extends JoinCommunityOutcome {
  const JoinedCommunity(this.communityId);

  final String communityId;
}

/// The community's policy requires its join code, which was not supplied.
final class NeedsJoinCode extends JoinCommunityOutcome {
  const NeedsJoinCode();
}

/// Already a member. The destination is the same; only the wording differs.
final class AlreadyMember extends JoinCommunityOutcome {
  const AlreadyMember();
}

/// A community of players.
///
/// The join code is deliberately absent. It is the credential a CODE_REQUIRED
/// community is entered with, and migration `0055` revoked SELECT on the column
/// so that no community read carries one — for a member or anybody else. An
/// organizer asks for it separately, through
/// [CommunityAdapter.fetchJoinCode], which is the only path that exists.
class Community {
  const Community({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.joinPolicy,
    this.description,
  });

  final String id;

  /// Reporting only — never used to decide what a user may do.
  final String ownerId;
  final String name;
  final String? description;
  final JoinPolicy joinPolicy;
}

/// A membership row inside a community, joined with the player profile.
class CommunityMember {
  const CommunityMember({
    required this.userId,
    required this.fullName,
    required this.position,
    required this.role,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String position;
  final CommunityRole role;

  /// Where this member's picture is, when they have set one. Null is an
  /// initials avatar rather than a missing one.
  final String? avatarUrl;

  bool get isOwner => role == CommunityRole.owner;
}

/// What an invitation link offers, readable before anyone signs in.
///
/// Deliberately thin: the community's name and whether the viewer is already a
/// member. The join code is the credential, so the preview never echoes it back,
/// and it says nothing about the roster or the matches.
class CommunityInvitePreview {
  const CommunityInvitePreview({
    required this.isValid,
    this.communityId,
    this.communityName,
    this.isMember = false,
  });

  final bool isValid;
  final String? communityId;
  final String? communityName;
  final bool isMember;
}
