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

/// One account, as the Platform Admin detail screen sees it.
///
/// **Three fields are nullable and must stay that way.** [lastSeenAt],
/// [latestAppVersion] and an empty [platforms] all mean "the product has never
/// observed this", which is the ordinary state of an account that has not been
/// back since analytics was deployed. Substituting a default -- the join date
/// for a last seen, the current build for a version -- would turn "we do not
/// know" into a statement of fact, and an administrator reading it would have
/// no way to tell the difference.
///
/// The counts default to zero because a count of nothing genuinely is zero.
class AdminUserActivitySummary {
  const AdminUserActivitySummary({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.createdAt,
    required this.isActive,
    required this.activeDays7d,
    required this.activeDays30d,
    required this.sessionsTotal,
    required this.platforms,
    required this.communityCount,
    required this.trackedRegistrations,
    required this.matchesPlayed,
    required this.trackedWithdrawals,
    this.suspendedAt,
    this.suspensionReason,
    this.lastSeenAt,
    this.latestAppVersion,
  });

  final String userId;
  final String fullName;
  final String email;

  /// When the account was created. Always present.
  final DateTime createdAt;

  /// The authoritative account state, the same `users.is_active` every database
  /// rule reads.
  final bool isActive;
  final DateTime? suspendedAt;
  final String? suspensionReason;

  /// The last thing the product actually watched this person do.
  ///
  /// Null when nothing has been observed. Deliberately **not** a sign-in
  /// timestamp: one of those moves when a token refreshes rather than when a
  /// person does something.
  final DateTime? lastSeenAt;

  /// Distinct local calendar days carrying at least one session.
  final int activeDays7d;
  final int activeDays30d;

  /// Sessions recorded since the analytics release. Never a guess at what came
  /// before it.
  final int sessionsTotal;

  /// The platforms this account has actually been seen on -- `web`, `android`,
  /// or both. Empty when none has been observed; never null, so the screen has
  /// one shape to render.
  final List<String> platforms;

  /// The build the most recent event carrying a version was recorded on.
  final String? latestAppVersion;

  /// Communities this account belongs to **now**. Not a history: leaving a
  /// community removes the row.
  final int communityCount;

  /// Registrations and withdrawals as tracked since the analytics release.
  /// Withdrawals exist nowhere else at all -- withdrawing deletes the
  /// registration row.
  final int trackedRegistrations;
  final int trackedWithdrawals;

  /// Matches actually played, from `player_statistics`. Historical and
  /// complete, and it stays visible for a suspended account.
  final int matchesPlayed;
}

/// One thing an account did, as the activity timeline sees it.
///
/// [eventName] is the raw stored value rather than a parsed enum, because a row
/// written by a newer release may name an event this build has never heard of.
/// Keeping the string is what lets the screen show such a row as it was
/// recorded instead of dropping it.
///
/// The context fields are nullable twice over: an event may never have carried
/// a community or a match, and one it did carry may since have been deleted --
/// `product_events` holds no foreign keys. A null [communityName] beside a
/// non-null [communityId] is exactly that second case.
class AdminUserActivityEvent {
  const AdminUserActivityEvent({
    required this.eventName,
    required this.createdAt,
    this.communityId,
    this.communityName,
    this.matchId,
    this.matchTitle,
    this.platform,
    this.appVersion,
  });

  final String eventName;
  final DateTime createdAt;

  final String? communityId;
  final String? communityName;
  final String? matchId;
  final String? matchTitle;

  final String? platform;
  final String? appVersion;
}

/// One administrative act, as the audit log sees it.
///
/// [action] is a raw string for the same reason [AdminUserActivityEvent.eventName]
/// is. The log is append-only and future-safe: a reader that recognised only
/// today's four actions would hide tomorrow's, which are the entries most worth
/// seeing.
///
/// The snapshots are what keep an entry legible after its subject is gone, and
/// both are nullable because the snapshot may not have been obtainable when the
/// act was recorded. `metadata` is deliberately absent from this model -- the
/// RPC does not return it.
class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    required this.action,
    required this.targetType,
    required this.createdAt,
    this.actorUserId,
    this.actorEmailSnapshot,
    this.targetId,
    this.targetLabelSnapshot,
    this.reason,
  });

  final String id;

  /// `USER_SUSPENDED`, `USER_REACTIVATED`, `COMMUNITY_SUSPENDED`,
  /// `COMMUNITY_REACTIVATED` -- or anything a later cycle records.
  final String action;

  /// `USER` or `COMMUNITY`.
  final String targetType;

  final DateTime createdAt;

  /// Who acted. The id has no foreign key, so it may name an account that no
  /// longer exists; the email snapshot is what stays readable when it does.
  final String? actorUserId;
  final String? actorEmailSnapshot;

  final String? targetId;
  final String? targetLabelSnapshot;

  /// Why, as the acting administrator wrote it. Present for a suspension,
  /// absent for a reactivation.
  final String? reason;
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
