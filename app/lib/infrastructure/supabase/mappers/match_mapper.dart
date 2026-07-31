import '../../../core/failures.dart';
import '../../../features/matches/match_models.dart';

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

/// Reads a registration row joined with the player profile.
MatchRegistration matchRegistrationFromRow(Map<String, dynamic> row) {
  final user = row['user'] as Map<String, dynamic>;
  return MatchRegistration(
    userId: user['id'] as String,
    fullName: user['full_name'] as String,
    position: user['primary_position'] as String,
    status: registrationStatusFromDb(row['status'] as String),
    registrationOrder: row['registration_order'] as int,
  );
}
