import '../../../core/failures.dart';
import '../../../features/matches/match_models.dart';
import 'community_mapper.dart';

// Conversion between Supabase rows and the match Domain Models.
//
// Every column name the match aggregate reads appears here and nowhere else
// (OP-3). Lifecycle questions — is the match locked, is it effectively
// completed — are answered by the Domain Model, not here.

/// An unrecognised status reads as open, which is what the row said before any
/// newer state existed.
MatchStatus matchStatusFromDb(String value) => switch (value) {
      'full' => MatchStatus.full,
      'completed' => MatchStatus.completed,
      _ => MatchStatus.open,
    };

/// A seat is either confirmed or reserve. Anything else means the database and
/// this build disagree about the schema, which is an infrastructure fault
/// rather than something to guess at.
RegistrationStatus registrationStatusFromDb(String value) => switch (value) {
      'confirmed' => RegistrationStatus.confirmed,
      'reserve' => RegistrationStatus.reserve,
      _ => throw const InfrastructureFailure(),
    };

/// Which ordering a match's roster is under (migration `0053`).
///
/// Anything unrecognised reads as the default, which is the state every match
/// created before the column existed is in and the only state a match can be in
/// without somebody having deliberately left it.
RosterOrderMode rosterOrderModeFromDb(String? value) =>
    value == 'manual' ? RosterOrderMode.manual : RosterOrderMode.registration;

Match matchFromRow(Map<String, dynamic> row) => Match(
      id: row['id'] as String,
      communityId: row['community_id'] as String,
      createdBy: row['created_by'] as String,
      location: row['location'] as String,
      startAt: DateTime.parse(row['start_at'] as String).toLocal(),
      endAt: DateTime.parse(row['end_at'] as String).toLocal(),
      startingPlayers: row['starting_players'] as int,
      maxRegistration: row['max_registration'] as int,
      status: matchStatusFromDb(row['status'] as String),
      title: row['title'] as String?,
      description: row['description'] as String?,
      // Present only when the query joins the community.
      communityLogoUrl:
          (row['community'] as Map<String, dynamic>?)?['logo_url'] as String?,
      communityName:
          (row['community'] as Map<String, dynamic>?)?['name'] as String?,
      rosterOrderMode:
          rosterOrderModeFromDb(row['roster_order_mode'] as String?),
      // Absent from a row read by a build that predates migration `0054`, and
      // false is what such a row means: before the column existed no match
      // could be created in the past.
      isHistorical: row['is_historical'] as bool? ?? false,
    );

/// Reads one row of `match_membership_context` (migration `0042`).
///
/// A row that says the match does not exist carries nulls for everything else,
/// which is what the model reports back: there is no community to name.
MatchAccessContext matchAccessContextFromRow(Map<String, dynamic> row) {
  final policy = row['join_policy'] as String?;
  return MatchAccessContext(
    matchExists: row['match_exists'] as bool? ?? false,
    isMember: row['is_member'] as bool? ?? false,
    communityId: row['community_id'] as String?,
    communityName: row['community_name'] as String?,
    joinPolicy: policy == null ? null : joinPolicyFromDb(policy),
  );
}

/// Reads one row of `v_match_registrations` (migrations `0048`, `0053`).
///
/// The read model rather than the table, because the roster is read in the
/// authoritative participant order and that order is a rule — the owner/admin
/// arrangement when the match has one, arrival order otherwise. The view holds
/// it as `roster_position`, computed by the same expression `rebalance_roster`
/// cuts at `starting_players`, so the list this produces is in the order the
/// starting/reserve split was made over. Re-deriving that here would be a
/// second implementation of one rule.
///
/// `participant_type` is the view's projection of which identity column is set
/// — the same XOR the table states as a CHECK constraint. A row that names
/// neither participant is the schema disagreeing with this build rather than
/// something to guess at.
///
/// A guest carries no profile, so `primary_position` is null. That is the
/// absence of a position and not an unknown one, which is why nothing
/// substitutes a default here.
/// [avatarUrl] is supplied by the adapter rather than read from [row]: the view
/// carries the profile columns a roster needs but not the picture's path, so the
/// face is looked up alongside and joined here. It is never passed for a guest.
MatchRegistration matchRegistrationFromRow(
  Map<String, dynamic> row, {
  String? avatarUrl,
}) {
  final status = registrationStatusFromDb(row['status'] as String);
  final registrationId = row['registration_id'] as String?;
  final displayName = row['display_name'] as String?;
  if (registrationId == null || displayName == null) {
    throw const InfrastructureFailure();
  }

  final common = (
    registrationId: registrationId,
    fullName: displayName,
    status: status,
    registrationOrder: row['registration_order'] as int,
    adminOrder: row['admin_order'] as int?,
  );

  final guestId = row['professional_guest_id'] as String?;
  if (row['participant_type'] == 'PROFESSIONAL' && guestId != null) {
    return MatchRegistration(
      registrationId: common.registrationId,
      professionalGuestId: guestId,
      fullName: common.fullName,
      status: common.status,
      registrationOrder: common.registrationOrder,
      adminOrder: common.adminOrder,
    );
  }

  final userId = row['user_id'] as String?;
  if (userId != null) {
    return MatchRegistration(
      registrationId: common.registrationId,
      userId: userId,
      fullName: common.fullName,
      position: row['primary_position'] as String?,
      status: common.status,
      registrationOrder: common.registrationOrder,
      adminOrder: common.adminOrder,
      avatarUrl: avatarUrl,
    );
  }

  throw const InfrastructureFailure();
}
