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
