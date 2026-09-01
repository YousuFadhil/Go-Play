import '../../../features/football/football_models.dart';

// Conversion between the Cycle 2 read models and the football Domain Models.
//
// Every column name the football feature reads appears here and nowhere else
// (OP-3). Every row comes from a view added by migration `0057`
// (`v_football_completed_matches`, `v_football_match_participants`,
// `v_football_match_lineup`, `v_football_community_stats`,
// `v_football_community_player_stats`) rather than from a table, which is why
// nothing is filtered on this side: the views decide what a caller is given, and
// none of them carries a phone, an email, an auth identifier, a date of birth or
// a join code. There is no column here that could read one out by mistake.

/// An unrecognised value reads as a Professional Guest rather than as a user.
///
/// The stricter of the two: a guest opens no profile and enters no statistics,
/// so a row the app cannot classify is treated as the one that grants least.
ParticipantType participantTypeFromDb(String? value) =>
    value == 'USER' ? ParticipantType.user : ParticipantType.professionalGuest;

/// Anything that is not team B is team A. The column is a CHECK-constrained
/// `'A'`/`'B'`, so this is a total function over what the database can store.
FootballTeam footballTeamFromDb(String value) =>
    value == 'B' ? FootballTeam.b : FootballTeam.a;

/// Anything that is not a confirmed place is a reserve one — the stricter
/// reading, and the one a roster row falls back to.
ParticipationStatus participationStatusFromDb(String value) =>
    value == 'confirmed'
        ? ParticipationStatus.confirmed
        : ParticipationStatus.reserve;

/// Reads a numeric column that Postgres may hand over as `int`, `double` or a
/// stringified numeric. `overall_rating` is `numeric(4,2)`, which the client
/// library surfaces inconsistently depending on the transport.
double? _ratingOf(Object? value) => switch (value) {
      null => null,
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

/// Builds the participant identity carried by the three match-scoped views.
///
/// The three share one shape on purpose — `participant_type`, the two ids,
/// `display_name` and the profile columns — so this reads all of them and a
/// caller never has to know which view a participant came from.
///
/// [avatarUrl] turns the stored path into somewhere it can be fetched from.
/// Passed in rather than resolved here, exactly as the team and member mappers
/// take it: where a picture lives is the data provider's business.
FootballParticipant footballParticipantFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) {
  final type = participantTypeFromDb(row['participant_type'] as String?);
  return FootballParticipant(
    type: type,
    displayName: row['display_name'] as String? ?? '',
    userId: row['user_id'] as String?,
    guestId: row['professional_guest_id'] as String?,
    // A guest has no picture to have. Asking for one would compose a URL for a
    // null path, which is harmless, but not asking says the rule out loud.
    avatarUrl: type == ParticipantType.user
        ? avatarUrl?.call(row['avatar_path'] as String?)
        : null,
    primaryPosition: row['primary_position'] as String?,
    secondaryPosition: row['secondary_position'] as String?,
    overallRating: _ratingOf(row['overall_rating']),
  );
}

/// Reads one row of `v_football_completed_matches`.
///
/// The MVP is assembled from the four `mvp_*` columns and is null when no MVP
/// was recorded — which migration `0033` made an ordinary outcome. It is built
/// as a [FootballParticipant] like any other so a screen draws the best player
/// the same way it draws everybody else.
CompletedMatch completedMatchFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) {
  final mvpType = row['mvp_participant_type'] as String?;
  return CompletedMatch(
    matchId: row['match_id'] as String,
    communityId: row['community_id'] as String,
    communityName: row['community_name'] as String? ?? '',
    location: row['location'] as String? ?? '',
    startAt: DateTime.parse(row['start_at'] as String).toLocal(),
    endAt: DateTime.parse(row['end_at'] as String).toLocal(),
    isHistorical: row['is_historical'] as bool? ?? false,
    hasResult: row['has_result'] as bool? ?? false,
    title: row['title'] as String?,
    teamAScore: row['team_a_score'] as int?,
    teamBScore: row['team_b_score'] as int?,
    mvp: mvpType == null
        ? null
        : FootballParticipant(
            type: participantTypeFromDb(mvpType),
            displayName: row['mvp_display_name'] as String? ?? '',
            userId: row['mvp_user_id'] as String?,
            guestId: row['mvp_professional_guest_id'] as String?,
            avatarUrl: avatarUrl?.call(row['mvp_avatar_path'] as String?),
          ),
  );
}

/// Reads one row of `v_football_match_participants`.
MatchRosterEntry matchRosterEntryFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) =>
    MatchRosterEntry(
      matchId: row['match_id'] as String,
      participant: footballParticipantFromRow(row, avatarUrl: avatarUrl),
      status: participationStatusFromDb(row['status'] as String),
      rosterPosition: row['roster_position'] as int? ?? 0,
    );

/// Reads one row of `v_football_match_lineup`.
LineupSlot lineupSlotFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) =>
    LineupSlot(
      matchId: row['match_id'] as String,
      participant: footballParticipantFromRow(row, avatarUrl: avatarUrl),
      team: footballTeamFromDb(row['team'] as String),
      assignedPosition: row['assigned_position'] as String?,
      goals: row['goals'] as int? ?? 0,
      isMvp: row['is_mvp'] as bool? ?? false,
      isOutOfPosition: row['is_out_of_position'] as bool? ?? false,
    );

/// Reads one row of `v_football_community_stats`.
CommunityFootballStats communityFootballStatsFromRow(
  Map<String, dynamic> row,
) =>
    CommunityFootballStats(
      communityId: row['community_id'] as String,
      communityName: row['community_name'] as String? ?? '',
      completedMatches: row['completed_matches'] as int? ?? 0,
      players: row['players'] as int? ?? 0,
      goals: row['goals'] as int? ?? 0,
      mvpCount: row['mvp_count'] as int? ?? 0,
    );

/// Reads one row of `v_football_community_player_stats`.
///
/// The view joins active users only, so `display_name` is always present and a
/// missing rating falls back to the column default the engine starts everybody
/// on (`OP-1`).
CommunityPlayerStats communityPlayerStatsFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) =>
    CommunityPlayerStats(
      communityId: row['community_id'] as String,
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String? ?? '',
      avatarUrl: avatarUrl?.call(row['avatar_path'] as String?),
      primaryPosition: row['primary_position'] as String?,
      secondaryPosition: row['secondary_position'] as String?,
      overallRating: _ratingOf(row['overall_rating']) ?? 5.0,
      matchesPlayed: row['matches_played'] as int? ?? 0,
      wins: row['wins'] as int? ?? 0,
      draws: row['draws'] as int? ?? 0,
      losses: row['losses'] as int? ?? 0,
      goals: row['goals'] as int? ?? 0,
      mvpCount: row['mvp_count'] as int? ?? 0,
    );
