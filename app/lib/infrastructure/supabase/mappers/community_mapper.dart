import '../../../features/communities/community_models.dart';

// Conversion between Supabase rows and the community Domain Models.
//
// Every column name in the community aggregate appears here and nowhere else
// (OP-3). The decode fallbacks below are deliberate: a stored value the app
// cannot read is resolved to the least privileged reading, because only this
// file ever sees the raw string.

/// An unrecognised value is treated as the stricter of the two: a policy the
/// app does not understand should not fall open.
JoinPolicy joinPolicyFromDb(String value) =>
    value == 'OPEN' ? JoinPolicy.open : JoinPolicy.codeRequired;

String joinPolicyToDb(JoinPolicy policy) =>
    policy == JoinPolicy.open ? 'OPEN' : 'CODE_REQUIRED';

/// Anything unrecognised falls back to the least privileged role rather than
/// granting something by accident. The retired `member` value is still
/// accepted so an old row cannot trip up the app.
CommunityRole communityRoleFromDb(String value) => switch (value) {
      'owner' => CommunityRole.owner,
      'admin' => CommunityRole.admin,
      _ => CommunityRole.player,
    };

String communityRoleToDb(CommunityRole role) => switch (role) {
      CommunityRole.owner => 'owner',
      CommunityRole.admin => 'admin',
      CommunityRole.player => 'player',
    };

Community communityFromRow(Map<String, dynamic> row) => Community(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      joinPolicy: joinPolicyFromDb(row['join_policy'] as String),
      joinCode: row['join_code'] as String,
    );

/// Reads a membership row joined with the player profile.
CommunityMember communityMemberFromRow(Map<String, dynamic> row) {
  final user = row['user'] as Map<String, dynamic>;
  return CommunityMember(
    userId: user['id'] as String,
    fullName: user['full_name'] as String,
    position: user['primary_position'] as String,
    role: communityRoleFromDb(row['role'] as String),
  );
}

CommunityInvitePreview invitePreviewFromRow(Map<String, dynamic> row) =>
    CommunityInvitePreview(
      isValid: row['state'] == 'valid',
      communityId: row['community_id'] as String?,
      communityName: row['community_name'] as String?,
      isMember: row['is_member'] as bool? ?? false,
    );
