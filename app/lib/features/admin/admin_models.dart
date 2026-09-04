// Domain models for the internal administration screens.
//
// Each carries the fields the record actually has. How a row reads — the
// separator between counts, what stands in for a missing name — is wording,
// and belongs to the screen (OP-3: what leaves the adapter is a Domain Model,
// not a pre-formatted view row).

/// A user account, as the administration list sees it.
class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isSystemAdmin,
    required this.isActive,
    this.suspendedAt,
    this.suspensionReason,
  });

  final String id;
  final String fullName;
  final String email;

  /// A System Admin account, which the normal Admin path may not suspend.
  final bool isSystemAdmin;

  /// The authoritative account state. False means the account is suspended --
  /// `users.is_active` is what every database rule reads, and the metadata
  /// below only describes it.
  final bool isActive;

  /// When the suspension was recorded, or null when the account has never been
  /// suspended through the Platform Admin path.
  final DateTime? suspendedAt;

  /// Why it was suspended, as the acting administrator wrote it.
  final String? suspensionReason;
}

/// A community, as the administration list sees it.
class AdminCommunitySummary {
  const AdminCommunitySummary({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.matchCount,
    required this.isActive,
    this.ownerName,
    this.suspendedAt,
    this.suspensionReason,
  });

  final String id;
  final String name;
  final String? ownerName;
  final int memberCount;
  final int matchCount;

  /// The authoritative community state. False means suspended.
  final bool isActive;

  final DateTime? suspendedAt;
  final String? suspensionReason;
}

/// A match, as the administration list sees it.
class AdminMatchSummary {
  const AdminMatchSummary({
    required this.id,
    required this.location,
    required this.registrationCount,
    this.title,
    this.communityName,
  });

  final String id;
  final String? title;
  final String? communityName;
  final String location;
  final int registrationCount;
}
