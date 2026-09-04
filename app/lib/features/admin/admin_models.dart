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

/// The Platform Admin Overview: every figure on the dashboard, in one object.
///
/// One model for one RPC, because `admin_analytics_overview()` returns one row
/// and splitting it into three would suggest three calls the dashboard does not
/// make.
///
/// **Every count is non-negative and present.** The database counts, and a
/// count of nothing is zero. The single exception is [weeklyRetentionPercent],
/// which is genuinely absent when there is nothing to compute it from — see
/// below.
class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.totalUsers,
    required this.newUsersToday,
    required this.newUsers7d,
    required this.newUsers30d,
    required this.dau,
    required this.wau,
    required this.mau,
    required this.weeklyActiveCommunities,
    required this.matches7d,
    required this.matches30d,
    required this.registrations7d,
    required this.registrations30d,
    required this.results7d,
    required this.results30d,
    required this.retentionPreviousWeekUsers,
    required this.retentionReturningUsers,
    this.weeklyRetentionPercent,
  });

  /// Accounts. Historically complete: `users.created_at` exists for every row
  /// that ever existed, so these four are correct from the first day.
  final int totalUsers;
  final int newUsersToday;
  final int newUsers7d;
  final int newUsers30d;

  /// Distinct people who started a session in the day, the week, the month.
  ///
  /// **Partial by design until tracking accumulates.** There has never been a
  /// session table, so these begin at zero on the day analytics is deployed and
  /// climb from there. The alternative — reading `auth.last_sign_in_at` — would
  /// report one stale timestamp per account as though it were activity.
  final int dau;
  final int wau;
  final int mau;

  /// Communities where football actually happened in the last seven days: a
  /// match organised, a registration, a withdrawal, or a result recorded.
  /// Looking at a community is not activity in it.
  final int weeklyActiveCommunities;

  /// Matches organised. From `matches.created_at`, so historically complete.
  final int matches7d;
  final int matches30d;

  /// Registrations recorded. From the events, not from `match_registrations`:
  /// that table loses the row when a player withdraws, so counting it would
  /// report only the registrations nobody changed their mind about.
  final int registrations7d;
  final int registrations30d;

  /// Results written up. From `match_results.created_at`, historically
  /// complete.
  final int results7d;
  final int results30d;

  /// The two halves of the retention fraction, kept so the dashboard can show
  /// what the percentage is made of rather than only the percentage.
  final int retentionPreviousWeekUsers;
  final int retentionReturningUsers;

  /// How many of last week's people came back this week.
  ///
  /// **Null is not zero, and the difference matters.** Null means there was no
  /// previous-week cohort to return — nobody to measure — which is the normal
  /// state of a product that has just started recording sessions. Zero would
  /// mean a cohort existed and none of them came back. The screen shows an em
  /// dash for the first and a real figure for the second.
  final double? weeklyRetentionPercent;
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
