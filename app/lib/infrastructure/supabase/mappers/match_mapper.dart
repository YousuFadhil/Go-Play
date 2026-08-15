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
      communityName: (row['community'] as Map<String, dynamic>?)?['name']
          as String?,
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

/// Reads a registration row joined with whichever participant it names.
///
/// Both embeds are nullable, and exactly one of them is present — the database
/// states that as a CHECK constraint, so a row with neither (or with both) is
/// the schema disagreeing with this build rather than something to guess at.
///
/// A guest carries no profile, so `position` stays null. That is the absence of
/// a position and not an unknown one, which is why nothing substitutes a
/// default here.
MatchRegistration matchRegistrationFromRow(Map<String, dynamic> row) {
  final status = registrationStatusFromDb(row['status'] as String);
  final order = row['registration_order'] as int;
  final user = row['user'] as Map<String, dynamic>?;
  if (user != null) {
    return MatchRegistration(
      userId: user['id'] as String,
      fullName: user['full_name'] as String,
      position: user['primary_position'] as String?,
      status: status,
      registrationOrder: order,
    );
  }

  final guest = row['guest'] as Map<String, dynamic>?;
  if (guest != null) {
    return MatchRegistration(
      professionalGuestId: guest['id'] as String,
      fullName: guest['display_name'] as String,
      status: status,
      registrationOrder: order,
    );
  }

  throw const InfrastructureFailure();
}
