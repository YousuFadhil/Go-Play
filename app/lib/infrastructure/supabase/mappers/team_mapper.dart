import 'package:btge/btge.dart';

import '../../../core/failures.dart';
import '../../../features/teams/team_models.dart';

// Conversion between Supabase rows and the team-generation Domain Models.
//
// Every column name this aggregate reads or writes appears here and nowhere
// else (OP-3). The four vocabularies below are constrained by migration
// `0018`, so a value outside them means the database and this build disagree
// about the schema — an infrastructure fault rather than something to guess
// at, exactly as an unreadable registration status is.

Position positionFromDb(String value) => switch (value) {
      'GK' => Position.gk,
      'DEF' => Position.def,
      'MID' => Position.mid,
      'FWD' => Position.fwd,
      _ => throw const InfrastructureFailure(),
    };

String positionToDb(Position position) => position.code;

TeamId teamFromDb(String value) => switch (value) {
      'A' => TeamId.a,
      'B' => TeamId.b,
      _ => throw const InfrastructureFailure(),
    };

String teamToDb(TeamId team) => switch (team) {
      TeamId.a => 'A',
      TeamId.b => 'B',
    };

/// `GUEST` reads as null: a Professional Guest has no profile, so none of the
/// three profile-derived bases is true of them. `AssignmentBasis` is the
/// engine's own vocabulary and gains no fourth value for a participant the
/// engine never sees.
AssignmentBasis? assignmentBasisFromDb(String value) => switch (value) {
      'PRIMARY' => AssignmentBasis.primary,
      'SECONDARY' => AssignmentBasis.secondary,
      'TRANSITION' => AssignmentBasis.transition,
      'GUEST' => null,
      _ => throw const InfrastructureFailure(),
    };

String assignmentBasisToDb(AssignmentBasis? basis) => switch (basis) {
      AssignmentBasis.primary => 'PRIMARY',
      AssignmentBasis.secondary => 'SECONDARY',
      AssignmentBasis.transition => 'TRANSITION',
      null => 'GUEST',
    };

/// `numeric(3,1)` reaches the client as a JSON number or as its text form
/// depending on the transport, so both are read. The column is `NOT NULL`, so
/// anything else is the schema disagreeing with this build.
double ratingFromDb(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const InfrastructureFailure();
}

/// Reads a registration row joined with the player profile.
///
/// A null date of birth or secondary position stays null. Migration `0018`
/// left them nullable on purpose and §4.3 forbids inventing one, so nothing
/// here fills a gap in.
/// [avatarUrl] is composed by the adapter from the row's `avatar_path`: the
/// bucket and the host are provider knowledge, and a row does not carry them.
PlayerCoreInputs playerCoreInputsFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) {
  final user = row['user'] as Map<String, dynamic>;
  final dateOfBirth = user['date_of_birth'] as String?;
  final secondary = user['secondary_position'] as String?;
  return PlayerCoreInputs(
    userId: user['id'] as String,
    fullName: user['full_name'] as String,
    overallRating: ratingFromDb(user['overall_rating']),
    primaryPosition: positionFromDb(user['primary_position'] as String),
    dateOfBirth: dateOfBirth == null ? null : DateTime.parse(dateOfBirth),
    secondaryPosition: secondary == null ? null : positionFromDb(secondary),
    avatarUrl: avatarUrl?.call(user['avatar_path'] as String?),
  );
}

/// A lineup row, naming either a registered user or a Professional Guest.
///
/// `assigned_position` is null for a guest and never for a registered player —
/// migration `0051` makes that a CHECK constraint, so the absence here is the
/// database's statement that there is no position, not a gap to fill.
TeamAssignment teamAssignmentFromRow(Map<String, dynamic> row) {
  final position = row['assigned_position'] as String?;
  return TeamAssignment(
    userId: row['user_id'] as String?,
    professionalGuestId: row['professional_guest_id'] as String?,
    team: teamFromDb(row['team'] as String),
    assignedPosition: position == null ? null : positionFromDb(position),
    basis: assignmentBasisFromDb(row['assignment_basis'] as String),
    // Absent on a row read before migration `0058` added the column, and false
    // is what such a row means: nobody had chosen a side by hand yet.
    teamManuallyOverridden:
        row['team_manually_overridden'] as bool? ?? false,
  );
}

/// One player's place in the lineup, as `replace_match_lineup` reads it.
///
/// No `match_id`: the match is an argument of that function, which is what
/// keeps a row from naming a different match than the one being authorized.
/// Exactly one identity key is sent. Sending both, or neither, is what the
/// table's CHECK constraint refuses, so the payload is built to match it rather
/// than to be corrected by it.
Map<String, dynamic> teamAssignmentToRow(TeamAssignment assignment) => {
      if (assignment.userId != null) 'user_id': assignment.userId,
      if (assignment.professionalGuestId != null)
        'professional_guest_id': assignment.professionalGuestId,
      'team': teamToDb(assignment.team),
      // Null travels as null: a guest with no position is written as having
      // none, and the CHECK constraint refuses the same for a registered
      // player, whose position is never null in the first place.
      'assigned_position': assignment.assignedPosition == null
          ? null
          : positionToDb(assignment.assignedPosition!),
      'assignment_basis': assignmentBasisToDb(assignment.basis),
      // Whether an organizer chose this side by hand. It matters for a guest,
      // whose side is otherwise re-derived by the alternation on every write;
      // a community player carries false because the column is not nullable.
      'team_manually_overridden': assignment.teamManuallyOverridden,
      // out_of_position is deliberately not stored: §5.1 derives it from the
      // basis, and a stored copy could disagree with it.
    };

/// Reads a match row joined with its stored lineup.
///
/// Grouping the assignment rows by team is pure data composition, which is
/// what the adapter is allowed to do (OP-2): the shape comes from the rows,
/// not from a rule. Only the player ids survive — `BTGE-AX-2` bars everything
/// else in the row from reaching Diversity.
PastMatch pastMatchFromRow(Map<String, dynamic> row) {
  final rows = (row['assignments'] as List).cast<Map<String, dynamic>>();
  final byTeam = <String, Set<String>>{};
  for (final assignment in rows) {
    // Diversity counts who has played *with* whom, and a Professional Guest is
    // not somebody the engine can pair anyone with: they have no profile, no
    // history and are never a generation input. A guest row carries a null
    // `user_id` and is skipped rather than counted as a partner.
    final userId = assignment['user_id'] as String?;
    if (userId == null) continue;
    byTeam
        .putIfAbsent(assignment['team'] as String, () => <String>{})
        .add(userId);
  }
  final teams = <Set<String>>[];
  for (final team in const ['A', 'B']) {
    final members = byTeam[team];
    if (members != null) teams.add(members);
  }
  return PastMatch(
    playedAt: DateTime.parse(row['start_at'] as String).toLocal(),
    teams: teams,
  );
}
