import '../communities/community_models.dart';

/// Where an invitation is in its life: it is created pending and ends up
/// accepted, revoked by an organizer, or expired.
enum InvitationStatus {
  pending('pending'),
  accepted('accepted'),
  revoked('revoked'),
  expired('expired');

  const InvitationStatus(this.dbValue);

  final String dbValue;

  static InvitationStatus fromDb(String value) {
    return switch (value) {
      'accepted' => InvitationStatus.accepted,
      'revoked' => InvitationStatus.revoked,
      'expired' => InvitationStatus.expired,
      _ => InvitationStatus.pending,
    };
  }
}

/// An offer of membership in a community. The offered role is never owner:
/// ownership only moves by transfer.
class Invitation {
  const Invitation({
    required this.id,
    required this.communityId,
    required this.inviteeId,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.communityName,
    this.inviteeName,
  });

  final String id;
  final String communityId;
  final String inviteeId;
  final CommunityRole role;
  final InvitationStatus status;
  final DateTime expiresAt;

  /// Present when the query joins the community (the invitee's own list).
  final String? communityName;

  /// Present when the query joins the invitee (an organizer's list).
  final String? inviteeName;

  /// Still open, and not past its expiry.
  bool get isActionable =>
      status == InvitationStatus.pending && expiresAt.isAfter(DateTime.now());

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String,
      communityId: json['community_id'] as String,
      inviteeId: json['invitee_id'] as String,
      role: CommunityRole.fromDb(json['role'] as String),
      status: InvitationStatus.fromDb(json['status'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      communityName:
          (json['community'] as Map<String, dynamic>?)?['name'] as String?,
      inviteeName:
          (json['invitee'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

/// A player who can be invited, from the shared profile directory.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.fullName,
    required this.position,
  });

  final String id;
  final String fullName;
  final String position;

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      position: json['primary_position'] as String,
    );
  }
}
