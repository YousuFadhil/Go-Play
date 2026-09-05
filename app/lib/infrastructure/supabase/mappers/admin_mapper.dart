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

/// A required timestamp, which the two `created_at` columns always carry.
///
/// Distinct from [_adminTimestamp] on purpose: that one describes a suspension
/// that may never have happened, and this one a row that could not exist
/// without a time on it. Falls back to the epoch rather than throwing, because
/// losing a whole detail screen over one unparseable date would be the worse
/// failure -- and the value is displayed, never computed with.
DateTime _adminRequiredTimestamp(Object? value) =>
    _adminTimestamp(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

/// The observed platforms, as a list the screen can always iterate.
///
/// The RPC coalesces to an empty array, so null should not arrive; it is still
/// handled, because "no platform observed" and "the column was absent" are the
/// same thing to a reader and neither is worth an exception. Non-string members
/// are dropped rather than stringified.
List<String> _adminPlatforms(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is String && entry.isNotEmpty) entry,
  ];
}

AdminUserActivitySummary adminUserActivityFromRow(Map<String, dynamic> row) =>
    AdminUserActivitySummary(
      userId: row['user_id'] as String,
      fullName: row['full_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      createdAt: _adminRequiredTimestamp(row['created_at']),
      isActive: row['is_active'] as bool? ?? true,
      suspendedAt: _adminTimestamp(row['suspended_at']),
      suspensionReason: _adminReason(row['suspension_reason']),
      // Null is carried through untouched. A missing Last Seen means the
      // product has never observed this account, and substituting the join
      // date would state something the database did not say.
      lastSeenAt: _adminTimestamp(row['last_seen_at']),
      activeDays7d: _adminCount(row['active_days_7d']),
      activeDays30d: _adminCount(row['active_days_30d']),
      sessionsTotal: _adminCount(row['sessions_total']),
      platforms: _adminPlatforms(row['platforms']),
      // Also carried through. An unknown build is not the current build.
      latestAppVersion: _adminReason(row['latest_app_version']),
      communityCount: _adminCount(row['community_count']),
      trackedRegistrations: _adminCount(row['tracked_registrations']),
      matchesPlayed: _adminCount(row['matches_played']),
      trackedWithdrawals: _adminCount(row['tracked_withdrawals']),
    );

AdminUserActivityEvent adminActivityEventFromRow(Map<String, dynamic> row) =>
    AdminUserActivityEvent(
      // Kept as the database wrote it. Parsing here would mean deciding what to
      // do with a name this build does not know, and that decision belongs to
      // the screen, which can show it rather than lose it.
      eventName: row['event_name'] as String? ?? '',
      createdAt: _adminRequiredTimestamp(row['created_at']),
      communityId: row['community_id'] as String?,
      communityName: _adminReason(row['community_name']),
      matchId: row['match_id'] as String?,
      matchTitle: _adminReason(row['match_title']),
      platform: _adminReason(row['platform']),
      appVersion: _adminReason(row['app_version']),
    );

AdminAuditEntry adminAuditEntryFromRow(Map<String, dynamic> row) =>
    AdminAuditEntry(
      id: row['id'] as String,
      // Raw, for the same reason as above: the log is append-only and a reader
      // that only understood today's actions would hide tomorrow's.
      action: row['action'] as String? ?? '',
      targetType: row['target_type'] as String? ?? '',
      createdAt: _adminRequiredTimestamp(row['created_at']),
      actorUserId: row['actor_user_id'] as String?,
      actorEmailSnapshot: _adminReason(row['actor_email_snapshot']),
      targetId: row['target_id'] as String?,
      targetLabelSnapshot: _adminReason(row['target_label_snapshot']),
      reason: _adminReason(row['reason']),
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

// ---------------------------------------------------------------------------
// Drill-down rows (migration 0069)
//
// The rule running through all of these: **a null stays a null.** A drill-down
// exists to list exactly what its Overview figure counted, and
// `product_events` has no foreign keys -- so a counted event can name a user,
// match or community that has since been deleted. The database returns those
// rows with null labels on purpose. Substituting a placeholder name here would
// make a deleted record indistinguishable from a live one, and substituting a
// row-dropping fallback would make the list disagree with the number above it.
// ---------------------------------------------------------------------------

/// A nullable count -- a score, a squad size. Distinct from [_adminCount],
/// which is for figures where absence genuinely means zero.
int? _adminOptionalCount(Object? value) => (value as num?)?.toInt();

AdminDrilldownUser adminDrilldownUserFromRow(Map<String, dynamic> row) =>
    AdminDrilldownUser(
      userId: row['user_id'] as String,
      fullName: _adminReason(row['full_name']),
      email: _adminReason(row['email']),
      createdAt: _adminTimestamp(row['created_at']),
      isActive: row['is_active'] as bool?,
      isSystemAdmin: row['is_system_admin'] as bool?,
      lastSeenAt: _adminTimestamp(row['last_seen_at']),
      // Null and false are different claims here: null means the metric does
      // not ask about returning, false means this cohort member did not.
      returnedInCurrentWeek: row['returned_in_current_week'] as bool?,
    );

AdminDrilldownCommunity adminDrilldownCommunityFromRow(
  Map<String, dynamic> row,
) =>
    AdminDrilldownCommunity(
      communityId: row['community_id'] as String,
      name: row['name'] as String? ?? '',
      ownerName: _adminReason(row['owner_name']),
      memberCount: _adminCount(row['member_count']),
      matchCount: _adminCount(row['match_count']),
      isActive: row['is_active'] as bool? ?? true,
      lastActivityAt: _adminTimestamp(row['last_activity_at']),
    );

AdminDrilldownMatch adminDrilldownMatchFromRow(Map<String, dynamic> row) =>
    AdminDrilldownMatch(
      matchId: row['match_id'] as String,
      title: _adminReason(row['title']),
      communityId: row['community_id'] as String? ?? '',
      communityName: _adminReason(row['community_name']),
      location: row['location'] as String? ?? '',
      startAt: _adminRequiredTimestamp(row['start_at']),
      status: row['status'] as String? ?? '',
      matchCreatedAt: _adminRequiredTimestamp(row['match_created_at']),
      // Null for a match nobody has written up, which is an ordinary state in
      // a matches list and never one in a results list.
      resultCreatedAt: _adminTimestamp(row['result_created_at']),
      scoreA: _adminOptionalCount(row['score_a']),
      scoreB: _adminOptionalCount(row['score_b']),
    );

AdminDrilldownRegistration adminDrilldownRegistrationFromRow(
  Map<String, dynamic> row,
) =>
    AdminDrilldownRegistration(
      eventId: row['event_id'] as String,
      createdAt: _adminRequiredTimestamp(row['created_at']),
      userId: row['user_id'] as String?,
      fullName: _adminReason(row['full_name']),
      email: _adminReason(row['email']),
      matchId: row['match_id'] as String?,
      matchTitle: _adminReason(row['match_title']),
      communityId: row['community_id'] as String?,
      communityName: _adminReason(row['community_name']),
    );

AdminCommunityInspection adminCommunityInspectionFromRow(
  Map<String, dynamic> row,
) =>
    AdminCommunityInspection(
      communityId: row['community_id'] as String,
      name: row['name'] as String? ?? '',
      description: _adminReason(row['description']),
      joinPolicy: row['join_policy'] as String? ?? '',
      logoUrl: _adminReason(row['logo_url']),
      createdAt: _adminRequiredTimestamp(row['created_at']),
      ownerId: row['owner_id'] as String?,
      ownerName: _adminReason(row['owner_name']),
      memberCount: _adminCount(row['member_count']),
      matchCount: _adminCount(row['match_count']),
      isActive: row['is_active'] as bool? ?? true,
      suspendedAt: _adminTimestamp(row['suspended_at']),
      suspensionReason: _adminReason(row['suspension_reason']),
    );

AdminMatchInspection adminMatchInspectionFromRow(Map<String, dynamic> row) =>
    AdminMatchInspection(
      matchId: row['match_id'] as String,
      title: _adminReason(row['title']),
      description: _adminReason(row['description']),
      location: row['location'] as String? ?? '',
      startAt: _adminRequiredTimestamp(row['start_at']),
      endAt: _adminTimestamp(row['end_at']),
      status: row['status'] as String? ?? '',
      communityId: row['community_id'] as String? ?? '',
      communityName: _adminReason(row['community_name']),
      createdAt: _adminRequiredTimestamp(row['created_at']),
      createdBy: row['created_by'] as String?,
      creatorName: _adminReason(row['creator_name']),
      registrationCount: _adminCount(row['registration_count']),
      startingPlayers: _adminOptionalCount(row['starting_players']),
      maxRegistration: _adminOptionalCount(row['max_registration']),
      scoreA: _adminOptionalCount(row['score_a']),
      scoreB: _adminOptionalCount(row['score_b']),
      resultCreatedAt: _adminTimestamp(row['result_created_at']),
      mvpName: _adminReason(row['mvp_name']),
    );
