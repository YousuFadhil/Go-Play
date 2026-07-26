/// Role a user holds inside a community. Roles are cumulative: an owner can do
/// everything an admin can, and an admin everything a player can.
enum CommunityRole {
  player('player'),
  admin('admin'),
  owner('owner');

  const CommunityRole(this.dbValue);

  final String dbValue;

  /// Anything unrecognised falls back to the least privileged role rather
  /// than granting something by accident. The retired `member` value is still
  /// accepted so an old client cannot be tripped up by it.
  static CommunityRole fromDb(String value) {
    return switch (value) {
      'owner' => CommunityRole.owner,
      'admin' => CommunityRole.admin,
      _ => CommunityRole.player,
    };
  }

  /// True when this role includes everything [other] can do.
  bool atLeast(CommunityRole other) => index >= other.index;
}

/// A community of players.
class Community {
  const Community({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPrivate,
    required this.joinCode,
    this.description,
  });

  final String id;

  /// Reporting only — never used to decide what a user may do.
  final String ownerId;
  final String name;
  final String? description;
  final bool isPrivate;
  final String joinCode;

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isPrivate: json['is_private'] as bool,
      joinCode: json['join_code'] as String,
    );
  }
}

/// A membership row inside a community, joined with the player profile.
class CommunityMember {
  const CommunityMember({
    required this.userId,
    required this.fullName,
    required this.position,
    required this.role,
  });

  final String userId;
  final String fullName;
  final String position;
  final CommunityRole role;

  bool get isOwner => role == CommunityRole.owner;

  factory CommunityMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return CommunityMember(
      userId: user['id'] as String,
      fullName: user['full_name'] as String,
      position: user['primary_position'] as String,
      role: CommunityRole.fromDb(json['role'] as String),
    );
  }
}
