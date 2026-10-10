import '../../../features/admin/admin_models.dart';
import '../../../features/auth/auth_models.dart' show PlayerPosition;
import '../../../features/profile/profile_models.dart' show ProfileVisibility;
import 'auth_mapper.dart';
import 'profile_mapper.dart';

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
      matches7d: _adminCount(row['matches_created_7d'] ?? row['matches_7d']),
      matches30d: _adminCount(row['matches_created_30d'] ?? row['matches_30d']),
      registrations7d: _adminCount(
          row['tracked_registrations_7d'] ?? row['registrations_7d']),
      registrations30d: _adminCount(
          row['tracked_registrations_30d'] ?? row['registrations_30d']),
      results7d: _adminCount(row['results_recorded_7d'] ?? row['results_7d']),
      results30d:
          _adminCount(row['results_recorded_30d'] ?? row['results_30d']),
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
      // Absent from a database that predates `0091`, which reads as null: the
      // row is still shown, as the event it was recorded as.
      targetUserId: row['target_user_id'] as String?,
      targetUserName: _adminReason(row['target_user_name']),
      shareType: _adminReason(row['share_type']),
      source: _adminReason(row['source']),
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

/// One account's data and settings (`admin_get_user_account`, migration `0095`).
///
/// Every column the RPC returns is read here and nowhere else (OP-3). The
/// booleans fall back to the column defaults -- an account that is active, shows
/// its age, wants both kinds of push and has not muted -- so a row that somehow
/// arrives without one is treated as the ordinary account rather than as a
/// suspended or muted one. A null date of birth, secondary position and Default
/// Location stay null: they are states the schema allows, not gaps to fill.
///
/// `sign_in_providers` is read with the same tolerance as the platforms list: a
/// list the screen can always iterate, with anything that is not a string
/// dropped rather than stringified.
///
/// [avatarUrl] is composed by the adapter from `avatar_path`, because the bucket
/// and the host are provider knowledge and a row does not carry them.
AdminUserAccount adminUserAccountFromRow(
  Map<String, dynamic> row, {
  String? avatarUrl,
}) {
  final dateOfBirth = row['date_of_birth'];
  final secondary = row['secondary_position'] as String?;
  return AdminUserAccount(
    id: row['id'] as String,
    fullName: row['full_name'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    dateOfBirth: dateOfBirth is String ? DateTime.tryParse(dateOfBirth) : null,
    primaryPosition: playerPositionFromDb(row['primary_position'] as String),
    secondaryPosition:
        secondary == null ? null : playerPositionFromDb(secondary),
    profileVisibility:
        profileVisibilityFromDb(row['profile_visibility'] as String?),
    ageVisible: row['age_visible'] as bool? ?? true,
    defaultWilayatCode: (row['default_wilayat_code'] as num?)?.toInt(),
    avatarUrl: avatarUrl,
    isActive: row['is_active'] as bool? ?? true,
    suspendedAt: _adminTimestamp(row['suspended_at']),
    suspensionReason: _adminReason(row['suspension_reason']),
    isSystemAdmin: row['is_system_admin'] as bool? ?? false,
    matchPush: row['match_push'] as bool? ?? true,
    communityPush: row['community_push'] as bool? ?? true,
    muteAll: row['mute_all'] as bool? ?? false,
    signInProviders: _adminPlatforms(row['sign_in_providers']),
    emailConfirmedAt: _adminTimestamp(row['email_confirmed_at']),
    lastSignInAt: _adminTimestamp(row['last_sign_in_at']),
    createdAt: _adminRequiredTimestamp(row['created_at']),
  );
}

/// The arguments of the five account edits (migration `0095`).
///
/// One builder per RPC, so a payload cannot carry a column its RPC does not own:
/// the name and phone call cannot also send a date of birth. Each group is sent
/// whole -- a null in it means "clear" only for the three columns the schema
/// lets be empty. A date of birth travels as a date, never an instant.
Map<String, dynamic> adminUpdateAccountParams(
  String userId, {
  required String fullName,
  required String phone,
  String? reason,
}) =>
    {
      'p_user_id': userId,
      'p_full_name': fullName,
      'p_phone': phone,
      'p_reason': reason,
    };

Map<String, dynamic> adminUpdatePlayerProfileParams(
  String userId, {
  required DateTime? dateOfBirth,
  required PlayerPosition primaryPosition,
  required PlayerPosition? secondaryPosition,
  String? reason,
}) =>
    {
      'p_user_id': userId,
      'p_date_of_birth': dateOfBirth == null ? null : dateOnlyToDb(dateOfBirth),
      'p_primary_position': playerPositionToDb(primaryPosition),
      'p_secondary_position': secondaryPosition == null
          ? null
          : playerPositionToDb(secondaryPosition),
      'p_reason': reason,
    };

Map<String, dynamic> adminUpdatePrivacyParams(
  String userId, {
  required ProfileVisibility visibility,
  required bool ageVisible,
  String? reason,
}) =>
    {
      'p_user_id': userId,
      'p_profile_visibility': profileVisibilityToDb(visibility),
      'p_age_visible': ageVisible,
      'p_reason': reason,
    };

Map<String, dynamic> adminUpdateDefaultWilayatParams(
  String userId, {
  required int? wilayatCode,
  String? reason,
}) =>
    {
      'p_user_id': userId,
      'p_wilayat_code': wilayatCode,
      'p_reason': reason,
    };

Map<String, dynamic> adminUpdatePushPreferencesParams(
  String userId, {
  required bool matchPush,
  required bool communityPush,
  required bool muteAll,
  String? reason,
}) =>
    {
      'p_user_id': userId,
      'p_match_push': matchPush,
      'p_community_push': communityPush,
      'p_mute_all': muteAll,
      'p_reason': reason,
    };

// ---------------------------------------------------------------------------
// Account preflight (`admin_preview_account_merge` / `_deletion`, migration
// `0096`). Both return one jsonb document. Every reader below is tolerant in
// the way the rest of this file is: a missing key reads as empty or zero, and a
// value of an unexpected type is dropped rather than failing the whole preview.
// A finding code or severity this build does not know is kept (the screen shows
// a code it cannot word), never discarded.
// ---------------------------------------------------------------------------

Map<String, dynamic> _previewMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<Map<String, dynamic>> _previewRows(Object? value) => value is List
    ? [
        for (final row in value)
          if (row is Map) row.cast<String, dynamic>()
      ]
    : const [];

List<String> _previewStrings(Object? value) => value is List
    ? [
        for (final entry in value)
          if (entry is String && entry.isNotEmpty) entry
      ]
    : const [];

Map<String, int> _previewCounts(Object? value) => {
      for (final entry in _previewMap(value).entries)
        if (entry.value is num) entry.key: (entry.value as num).toInt(),
    };

AdminFindingSeverity _previewSeverity(Object? value) => switch (value) {
      'BLOCKER' => AdminFindingSeverity.blocker,
      'CONSTRAINT' => AdminFindingSeverity.constraint,
      // 'CONFLICT', and anything newer: asking for attention is the safer
      // reading of a severity this build does not know.
      _ => AdminFindingSeverity.conflict,
    };

List<AdminPreviewFinding> _previewFindings(Object? value) => [
      for (final row in _previewRows(value))
        AdminPreviewFinding(
          code: row['code'] as String? ?? '',
          severity: _previewSeverity(row['severity']),
          category: row['category'] as String? ?? '',
          count: _adminCount(row['count']),
        ),
    ];

List<AdminPreviewRecord> _previewRecords(Object? value) => [
      for (final row in _previewRows(value))
        AdminPreviewRecord(
          code: row['code'] as String? ?? '',
          records: _adminCount(row['records']),
          treatment: row['treatment'] as String?,
        ),
    ];

/// Whether a preview has blockers. **Understating them is the one mistake a
/// safety screen cannot make**, so this is true unless the database said, in so
/// many words, that there are none -- a missing or malformed flag reads as
/// blocked -- and it is true whenever any finding is a blocker, whatever the
/// flag says.
bool _previewHasBlockers(Object? flag, List<AdminPreviewFinding> findings) =>
    (flag is bool ? flag : true) ||
    findings.any((f) => f.severity == AdminFindingSeverity.blocker);

AdminPreviewList<T> _previewList<T>(
  Object? value,
  T Function(Map<String, dynamic> row) read,
) {
  final map = _previewMap(value);
  return AdminPreviewList(
    total: _adminCount(map['total']),
    items: [for (final row in _previewRows(map['items'])) read(row)],
  );
}

/// One account of a preview: the `{account, counts}` document the database's
/// snapshot helper builds.
AdminPreviewAccount adminPreviewAccountFromJson(Map<String, dynamic> json) {
  final account = _previewMap(json['account']);
  final counts = _previewMap(json['counts']);
  return AdminPreviewAccount(
    id: account['id'] as String? ?? '',
    fullName: account['full_name'] as String? ?? '',
    email: account['email'] as String? ?? '',
    isActive: account['is_active'] as bool? ?? true,
    isSystemAdmin: account['is_system_admin'] as bool? ?? false,
    isCaller: account['is_caller'] as bool? ?? false,
    createdAt: _adminRequiredTimestamp(account['created_at']),
    lastSignInAt: _adminTimestamp(account['last_sign_in_at']),
    signInProviders: _previewStrings(account['sign_in_providers']),
    counts: _previewCounts(counts)..remove('rating'),
    rating: (counts['rating'] as num?)?.toDouble(),
  );
}

AdminMergePreview adminMergePreviewFromJson(Map<String, dynamic> json) {
  final findings = _previewFindings(json['findings']);
  final overlap = _previewMap(json['overlapping_communities']);
  final shared = _previewMap(json['shared_matches']);
  final statistics = _previewMap(json['statistics_overlap']);
  final plan = _previewMap(json['plan']);
  return AdminMergePreview(
    retained: adminPreviewAccountFromJson(_previewMap(json['retained'])),
    source: adminPreviewAccountFromJson(_previewMap(json['source'])),
    overlappingCommunities: _previewList(
      overlap,
      (row) => AdminCommunityOverlap(
        communityId: row['community_id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        retainedRole: row['retained_role'] as String? ?? '',
        sourceRole: row['source_role'] as String? ?? '',
        roleConflict: row['role_conflict'] as bool? ?? false,
        sourceOwns: row['source_owns'] as bool? ?? false,
        retainedOwns: row['retained_owns'] as bool? ?? false,
      ),
    ),
    roleConflictsTotal: _adminCount(overlap['role_conflicts_total']),
    sourceOwnedCommunities: _previewList(
      json['source_owned_communities'],
      (row) => AdminSourceOwnedCommunity(
        communityId: row['community_id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        retainedIsMember: row['retained_is_member'] as bool? ?? false,
        retainedRole: row['retained_role'] as String?,
      ),
    ),
    sharedMatches: _previewList(
      shared,
      (row) => AdminSharedMatch(
        matchId: row['match_id'] as String? ?? '',
        title: row['title'] as String? ?? '',
        communityName: row['community_name'] as String?,
        startAt: _adminTimestamp(row['start_at']),
        status: row['status'] as String? ?? '',
        isHistorical: row['is_historical'] as bool? ?? false,
        retainedEvidence: _previewStrings(row['retained_evidence']),
        sourceEvidence: _previewStrings(row['source_evidence']),
        retainedDropBlockers: _previewStrings(row['retained_drop_blockers']),
        sourceDropBlockers: _previewStrings(row['source_drop_blockers']),
        // Absent means "no": a side is never offered on a guess.
        canKeepRetained: row['can_keep_retained'] as bool? ?? false,
        canKeepSource: row['can_keep_source'] as bool? ?? false,
      ),
    ),
    unresolvableMatchesTotal: _adminCount(shared['unresolvable_total']),
    sharedLimit: _adminCount(json['shared_limit']),
    communityStatisticsCollisions:
        _adminCount(statistics['community_statistics_collisions']),
    teamAwardCollisions: _adminCount(statistics['team_award_collisions']),
    plan: AdminMergePlan(
      communitiesTransferred: _adminCount(plan['communities_transferred']),
      membershipsMoved: _adminCount(plan['memberships_moved']),
      membershipsMerged: _adminCount(plan['memberships_merged']),
      rolesUpgraded: _adminCount(plan['roles_upgraded']),
      registrationsMoved: _adminCount(plan['registrations_moved']),
      lineupPlacesMoved: _adminCount(plan['lineup_places_moved']),
      goalRowsMoved: _adminCount(plan['goal_rows_moved']),
      mvpAwardsMoved: _adminCount(plan['mvp_awards_moved']),
      teamAwardsMoved: _adminCount(plan['team_awards_moved']),
      createdMatchesReattributed:
          _adminCount(plan['created_matches_reattributed']),
      sharedMatches: _adminCount(plan['shared_matches']),
    ),
    findings: findings,
    hasBlockers: _previewHasBlockers(json['has_blockers'], findings),
    coverageNotes: _previewStrings(json['coverage_notes']),
  );
}

/// The arguments of `admin_merge_accounts` (migration `0101`).
Map<String, dynamic> adminMergeAccountsParams({
  required String retainedUserId,
  required String sourceUserId,
  required List<AdminMergeResolution> resolutions,
}) =>
    {
      'p_retained_user_id': retainedUserId,
      'p_source_user_id': sourceUserId,
      'p_resolutions': [for (final r in resolutions) r.toJson()],
    };

/// A count in a result document, or 0 when it is anything else. Total: a cast would throw on a
/// value of the wrong type, and a throw here would be reported as an action that failed.
int _resultCount(Object? value) => value is num ? value.toInt() : 0;

/// What `admin_merge_accounts` returned. **Never throws:** a merge that returned
/// happened, and a result this build cannot fully read must still be reported as a
/// merge that happened.
AdminMergeResult adminMergeResultFromJson(
  Map<String, dynamic> json, {
  required String retainedUserId,
  required String sourceUserId,
}) {
  final dropped = _previewMap(json['dropped']);
  final rating = _previewMap(json['rating']);
  // Pattern tests, not casts: a cast that fails would throw, and a throw here
  // would be reported as a merge that failed.
  final retainedId = json['retained_user_id'];
  final sourceId = json['source_user_id'];
  final before = rating['before'];
  final after = rating['after'];
  return AdminMergeResult(
    retainedUserId: retainedId is String && retainedId.isNotEmpty
        ? retainedId
        : retainedUserId,
    sourceUserId:
        sourceId is String && sourceId.isNotEmpty ? sourceId : sourceUserId,
    droppedRegistrations: _resultCount(dropped['registrations']),
    droppedLineupPlaces: _resultCount(dropped['lineup_places']),
    moved: _previewCounts(json['moved']),
    ratingBefore: before is num ? before.toDouble() : null,
    ratingAfter: after is num ? after.toDouble() : null,
    matchesReplayed: _resultCount(rating['matches_replayed']),
  );
}

/// The body of the `delete-account` request for an administrator: the account to delete.
/// (Without it the same function deletes the caller's own account.)
Map<String, dynamic> adminDeleteAccountParams(String userId) =>
    {'p_user_id': userId};

/// What `delete-account` returned. **Never throws:** a deletion that returned
/// happened, and a result this build cannot fully read must still be reported as a
/// deletion that happened.
AdminDeletionResult adminDeletionResultFromJson(
  Map<String, dynamic> json, {
  required String userId,
}) {
  final withdrawn = _previewMap(json['withdrawn']);
  final id = json['user_id'];
  return AdminDeletionResult(
    userId: id is String && id.isNotEmpty ? id : userId,
    withdrawnRegistrations: _resultCount(withdrawn['registrations']),
    withdrawnLineupPlaces: _resultCount(withdrawn['lineup_places']),
    membershipsRemoved: _resultCount(json['memberships_removed']),
    auditEntriesRedacted: _resultCount(json['audit_entries_redacted']),
    avatarFilesRemoved: _resultCount(json['avatar_files_removed']),
  );
}

AdminDeletionPreview adminDeletionPreviewFromJson(Map<String, dynamic> json) {
  final findings = _previewFindings(json['findings']);
  final created = _previewMap(json['created_matches']);
  return AdminDeletionPreview(
    account: adminPreviewAccountFromJson(_previewMap(json['account'])),
    personalData: _previewRecords(json['personal_data']),
    ownedCommunities: _previewList(
      json['owned_communities'],
      (row) => AdminOwnedCommunity(
        communityId: row['community_id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        isActive: row['is_active'] as bool? ?? true,
        memberCount: _adminCount(row['member_count']),
        otherAdminCount: _adminCount(row['other_admin_count']),
        matchCount: _adminCount(row['match_count']),
      ),
    ),
    createdMatches: _previewList(
      created,
      (row) => AdminCreatedMatch(
        matchId: row['match_id'] as String? ?? '',
        title: row['title'] as String? ?? '',
        communityName: row['community_name'] as String?,
        startAt: _adminTimestamp(row['start_at']),
        status: row['status'] as String? ?? '',
        isHistorical: row['is_historical'] as bool? ?? false,
        hasResult: row['has_result'] as bool? ?? false,
      ),
    ),
    createdMatchesByStatus: _previewCounts(created['by_status']),
    historicalRecords: _previewRecords(json['historical_records']),
    preservedRecords: _previewRecords(json['preserved_records']),
    findings: findings,
    hasBlockers: _previewHasBlockers(json['has_blockers'], findings),
    coverageNotes: _previewStrings(json['coverage_notes']),
  );
}
