import '../communities/community_models.dart';
import '../matches/match_models.dart';
import '../matches/match_service.dart';

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

/// Why a shareable invite link is or is not usable. Decided in SQL by
/// `invite_link_state` so the landing screen and redemption can never disagree.
enum InviteLinkState {
  valid,

  /// An admin revoked it. The preview deliberately carries nothing else.
  revoked,

  /// The attached match has kicked off.
  expired,

  /// The attached match was deleted, which ends the invitation with it.
  matchDeleted,
  notFound;

  static InviteLinkState fromDb(String value) {
    return switch (value) {
      'valid' => InviteLinkState.valid,
      'revoked' => InviteLinkState.revoked,
      'expired' => InviteLinkState.expired,
      'match_deleted' => InviteLinkState.matchDeleted,
      _ => InviteLinkState.notFound,
    };
  }
}

/// One shareable link as an organizer sees it, for the management list.
///
/// [matchStartAt] is null for a community link and also for a match link whose
/// match was deleted; [isMatchLink] is what tells those two apart, and it comes
/// from the stored `kind` rather than being inferred.
class InviteLinkSummary {
  const InviteLinkSummary({
    required this.id,
    required this.token,
    required this.isMatchLink,
    required this.createdAt,
    this.matchTitle,
    this.matchStartAt,
  });

  final String id;
  final String token;
  final bool isMatchLink;
  final DateTime createdAt;
  final String? matchTitle;
  final DateTime? matchStartAt;

  /// The match was deleted, which ends the invitation with it.
  bool get isMatchDeleted => isMatchLink && matchStartAt == null;

  /// Kick-off has passed, so the link no longer opens anything.
  bool get isExpired =>
      matchStartAt != null && !matchStartAt!.isAfter(DateTime.now());

  bool get isUsable => !isMatchDeleted && !isExpired;

  factory InviteLinkSummary.fromJson(Map<String, dynamic> json) {
    final match = json['match'] as Map<String, dynamic>?;
    final startAt = match?['start_at'] as String?;
    return InviteLinkSummary(
      id: json['id'] as String,
      token: json['token'] as String,
      isMatchLink: json['kind'] == 'match',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      matchTitle: match?['title'] as String?,
      matchStartAt: startAt == null ? null : DateTime.parse(startAt).toLocal(),
    );
  }
}

/// What an invitation shows before anyone commits to it. Readable without an
/// account, so it carries only what the landing screen needs.
class InviteLinkPreview {
  const InviteLinkPreview({
    required this.state,
    this.communityId,
    this.communityName,
    this.matchId,
    this.matchTitle,
    this.matchLocation,
    this.matchStartAt,
    this.matchEndAt,
    this.startingPlayers,
    this.seatsRemaining,
    this.wouldBeReserve = false,
    this.isMember = false,
    this.isRegistered = false,
  });

  final InviteLinkState state;
  final String? communityId;
  final String? communityName;
  final String? matchId;
  final String? matchTitle;
  final String? matchLocation;
  final DateTime? matchStartAt;
  final DateTime? matchEndAt;
  final int? startingPlayers;

  /// Places left before the match cannot take anyone at all.
  final int? seatsRemaining;

  /// True when joining now means the reserve list rather than a starting place.
  /// Computed by the same expression the registration RPC allocates seats with.
  final bool wouldBeReserve;

  /// Only meaningful for a signed-in viewer; false for a visitor.
  final bool isMember;
  final bool isRegistered;

  /// A Type B invitation: community and match. Otherwise it is community-only.
  bool get hasMatch => matchId != null;
  bool get isUsable => state == InviteLinkState.valid;

  factory InviteLinkPreview.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final raw = json[key] as String?;
      return raw == null ? null : DateTime.parse(raw).toLocal();
    }

    return InviteLinkPreview(
      state: InviteLinkState.fromDb(json['state'] as String),
      communityId: json['community_id'] as String?,
      communityName: json['community_name'] as String?,
      matchId: json['match_id'] as String?,
      matchTitle: json['match_title'] as String?,
      matchLocation: json['match_location'] as String?,
      matchStartAt: parse('match_start_at'),
      matchEndAt: parse('match_end_at'),
      startingPlayers: json['starting_players'] as int?,
      seatsRemaining: json['seats_remaining'] as int?,
      wouldBeReserve: json['would_be_reserve'] as bool? ?? false,
      isMember: json['is_member'] as bool? ?? false,
      isRegistered: json['is_registered'] as bool? ?? false,
    );
  }
}

/// The outcome of redeeming an invitation. Membership and registration are
/// separate outcomes on purpose: [registrationFailure] means the caller joined
/// the community but did not get a place, and the reason is theirs to see.
class InviteRedemption {
  const InviteRedemption({
    required this.communityId,
    this.matchId,
    this.registrationStatus,
    this.registrationFailure,
    this.failureCode,
  });

  final String communityId;
  final String? matchId;
  final RegistrationStatus? registrationStatus;

  /// Set when the failure is one the app has words for. A failure the app does
  /// not recognise still arrives in [failureCode], so the screen can say
  /// something true rather than nothing.
  final RegistrationError? registrationFailure;
  final String? failureCode;

  bool get joinedMatch => registrationStatus != null;
  bool get registrationFailed => failureCode != null;

  factory InviteRedemption.fromJson(Map<String, dynamic> json) {
    final status = json['registration_status'] as String?;
    final failure = json['failure_code'] as String?;
    return InviteRedemption(
      communityId: json['community_id'] as String,
      matchId: json['match_id'] as String?,
      registrationStatus:
          status == null ? null : RegistrationStatus.fromDb(status),
      registrationFailure:
          failure == null ? null : registrationErrorFrom(failure),
      failureCode: failure,
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
