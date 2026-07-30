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
  });

  final String id;
  final String fullName;
  final String email;

  /// A System Admin account, which the app may not delete.
  final bool isSystemAdmin;
}

/// A community, as the administration list sees it.
class AdminCommunitySummary {
  const AdminCommunitySummary({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.matchCount,
    this.ownerName,
  });

  final String id;
  final String name;
  final String? ownerName;
  final int memberCount;
  final int matchCount;
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
