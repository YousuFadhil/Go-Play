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
/// community is entered with, and migration `0056` revoked SELECT on the column
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
    this.logoUrl,
  });

  final String id;

  /// Reporting only — never used to decide what a user may do.
  final String ownerId;
  final String name;
  final String? description;
  final JoinPolicy joinPolicy;

  /// Where the community's picture is, when it has one.
  ///
  /// Null is the ordinary case and not a missing value: a community without a
  /// picture is drawn as its initials, which is what a community's crest has
  /// always been. Every community that predates migration `0061` has null here
  /// and is unaffected.
  ///
  /// A URL rather than a storage path, unlike a player's avatar. A logo is
  /// versioned — a new object name on every replacement, so that a cache cannot
  /// keep serving the old picture — and a versioned name cannot be derived from
  /// the community's id the way an avatar's path can be derived from a player's.
  final String? logoUrl;

  /// The same community with a different picture, or with none.
  ///
  /// Only the logo, because only the logo can be changed without generic
  /// community UPDATE: an admin may set this and may not touch the name, the
  /// description or the join policy. A general `copyWith` would suggest
  /// otherwise.
  Community withLogo(String? url) => Community(
        id: id,
        ownerId: ownerId,
        name: name,
        joinPolicy: joinPolicy,
        description: description,
        logoUrl: url,
      );
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
    this.communityLogoUrl,
    this.isMember = false,
  });

  final bool isValid;
  final String? communityId;
  final String? communityName;

  /// The community's picture, so the landing page shows the community somebody
  /// was actually invited to rather than two letters standing in for it.
  final String? communityLogoUrl;

  final bool isMember;
}
