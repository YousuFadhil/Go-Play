/// A football group (community of players).
class Group {
  const Group({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isPrivate,
    required this.joinCode,
    this.description,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final bool isPrivate;
  final String joinCode;

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isPrivate: json['is_private'] as bool,
      joinCode: json['join_code'] as String,
    );
  }
}

/// A member row inside a group, joined with the player profile.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.fullName,
    required this.position,
    required this.role,
  });

  final String userId;
  final String fullName;
  final String position;
  final String role;

  bool get isOwner => role == 'owner';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return GroupMember(
      userId: user['id'] as String,
      fullName: user['full_name'] as String,
      position: user['primary_position'] as String,
      role: json['role'] as String,
    );
  }
}
