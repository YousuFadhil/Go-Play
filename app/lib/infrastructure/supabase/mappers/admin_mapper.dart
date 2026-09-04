import '../../../features/admin/admin_models.dart';

// Conversion from the `admin_list_*` RPC rows to the administration Domain
// Models. Counts arrive as numbers and are read as such; how a row is worded
// on screen is not this file's business (OP-3).
//
// The suspension columns arrive from migration `0066`. `is_active` is read
// defensively as `?? true`: a row that somehow arrives without it is treated as
// an ordinary active account rather than as a suspended one, because inventing
// a suspension is the worse of the two mistakes. `suspended_at` is a timestamp
// string and is parsed leniently -- an unparseable value becomes null rather
// than failing the whole list.

/// The timestamp a suspension column carries, or null when it is absent or
/// unparseable. A malformed date is not worth losing the row over.
DateTime? _adminTimestamp(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// A reason the record does not carry reads as an absence, not as an empty
/// string, so the screen has one thing to test rather than two.
String? _adminReason(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A count, as the Overview reads one.
///
/// Every figure in `admin_analytics_overview()` is a `bigint` and PostgREST
/// sends those as numbers; a missing key reads as zero rather than failing the
/// whole dashboard, because a metric that could not be read is better shown as
/// nothing than as a screen the administrator cannot open at all.
int _adminCount(Object? value) => (value as num?)?.toInt() ?? 0;

/// The retention percentage, which is genuinely nullable.
///
/// **Null is preserved, never defaulted to zero.** The database returns null
/// when there was no previous-week cohort, and turning that into 0 here would
/// tell the administrator that nobody came back when the truth is that there
/// was nobody to come back. Arrives as a `numeric`, which PostgREST may send as
/// a JSON number or as a string depending on precision, so both are accepted.
double? _adminPercent(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

AdminAnalyticsOverview adminAnalyticsOverviewFromRow(
  Map<String, dynamic> row,
) =>
    AdminAnalyticsOverview(
      totalUsers: _adminCount(row['total_users']),
      newUsersToday: _adminCount(row['new_users_today']),
      newUsers7d: _adminCount(row['new_users_7d']),
      newUsers30d: _adminCount(row['new_users_30d']),
      dau: _adminCount(row['dau']),
      wau: _adminCount(row['wau']),
      mau: _adminCount(row['mau']),
      weeklyActiveCommunities: _adminCount(row['weekly_active_communities']),
      matches7d: _adminCount(row['matches_7d']),
      matches30d: _adminCount(row['matches_30d']),
      registrations7d: _adminCount(row['registrations_7d']),
      registrations30d: _adminCount(row['registrations_30d']),
      results7d: _adminCount(row['results_7d']),
      results30d: _adminCount(row['results_30d']),
      retentionPreviousWeekUsers:
          _adminCount(row['retention_previous_week_users']),
      retentionReturningUsers: _adminCount(row['retention_returning_users']),
      weeklyRetentionPercent: _adminPercent(row['weekly_retention_percent']),
    );

AdminUserSummary adminUserFromRow(Map<String, dynamic> row) => AdminUserSummary(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      isSystemAdmin: row['is_system_admin'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? true,
      suspendedAt: _adminTimestamp(row['suspended_at']),
      suspensionReason: _adminReason(row['suspension_reason']),
    );

AdminCommunitySummary adminCommunityFromRow(Map<String, dynamic> row) =>
    AdminCommunitySummary(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      ownerName: row['owner_name'] as String?,
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      matchCount: (row['match_count'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] as bool? ?? true,
      suspendedAt: _adminTimestamp(row['suspended_at']),
      suspensionReason: _adminReason(row['suspension_reason']),
    );

AdminMatchSummary adminMatchFromRow(Map<String, dynamic> row) =>
    AdminMatchSummary(
      id: row['id'] as String,
      title: row['title'] as String?,
      communityName: row['community_name'] as String?,
      location: row['location'] as String? ?? '',
      registrationCount: (row['registration_count'] as num?)?.toInt() ?? 0,
    );
