import '../../../features/admin/admin_models.dart';

// Conversion from the `admin_list_*` RPC rows to the administration Domain
// Models. Counts arrive as numbers and are read as such; how a row is worded
// on screen is not this file's business (OP-3).

AdminUserSummary adminUserFromRow(Map<String, dynamic> row) => AdminUserSummary(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      isSystemAdmin: row['is_system_admin'] as bool? ?? false,
    );

AdminCommunitySummary adminCommunityFromRow(Map<String, dynamic> row) =>
    AdminCommunitySummary(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      ownerName: row['owner_name'] as String?,
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      matchCount: (row['match_count'] as num?)?.toInt() ?? 0,
    );

AdminMatchSummary adminMatchFromRow(Map<String, dynamic> row) =>
    AdminMatchSummary(
      id: row['id'] as String,
      title: row['title'] as String?,
      communityName: row['community_name'] as String?,
      location: row['location'] as String? ?? '',
      registrationCount: (row['registration_count'] as num?)?.toInt() ?? 0,
    );
