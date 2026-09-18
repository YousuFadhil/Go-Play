import '../../../features/discover/discover_models.dart';

// Conversion between the public read models and the Discover Domain Models.
//
// Every column name the Discover feature reads appears here and nowhere else
// (OP-3). Both rows come from views (`v_public_communities`,
// `v_public_upcoming_matches`, migration `0033`) rather than from tables, which
// is why the counts arrive already computed: an aggregate is what a guest is
// given instead of the rows behind it, and recomputing one here would mean
// reading those rows.

PublicCommunity publicCommunityFromRow(Map<String, dynamic> row) =>
    PublicCommunity(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      logoUrl: row['logo_url'] as String?,
      memberCount: row['member_count'] as int,
      upcomingMatchCount: row['upcoming_match_count'] as int,
    );

/// Reads a public match row.
///
/// `community_name` is a plain column rather than an embedded object: the view
/// has already joined the community, so there is no nested map to unwrap and no
/// query that could arrive without it.
PublicMatch publicMatchFromRow(Map<String, dynamic> row) => PublicMatch(
      id: row['id'] as String,
      communityId: row['community_id'] as String,
      communityName: row['community_name'] as String,
      location: row['location'] as String,
      startAt: DateTime.parse(row['start_at'] as String).toLocal(),
      endAt: DateTime.parse(row['end_at'] as String).toLocal(),
      startingPlayers: row['starting_players'] as int,
      openSlots: row['open_slots'] as int,
      title: row['title'] as String?,
    );

/// Reads one row of `public_recent_results` / `public_community_recent_results`
/// (migration `0081`).
///
/// A row without both scores is not a result and is not mapped: the contract
/// only returns matches whose result was recorded, so this is a guard against a
/// shape nobody should be able to produce rather than a case with a
/// presentation.
PublicResult publicResultFromRow(Map<String, dynamic> row) => PublicResult(
      matchId: row['match_id'] as String,
      communityId: row['community_id'] as String,
      communityName: row['community_name'] as String? ?? '',
      communityLogoUrl: row['community_logo_url'] as String?,
      title: row['title'] as String?,
      location: row['location'] as String?,
      startAt: DateTime.parse(row['start_at'] as String).toLocal(),
      teamAScore: row['team_a_score'] as int? ?? 0,
      teamBScore: row['team_b_score'] as int? ?? 0,
      mvpDisplayName: row['mvp_display_name'] as String?,
    );

/// Reads a `public_match_detail` row, or null when it names a state this build
/// does not know.
///
/// [avatarUrl] turns a stored picture path into an address, which is provider
/// knowledge the adapter holds.
PublicMatchDetail? publicMatchDetailFromRow(
  Map<String, dynamic> row, {
  required String? Function(String? path) avatarUrl,
  List<PublicLineupEntry> lineup = const [],
}) {
  final logo = row['community_logo_url'] as String?;
  switch (row['public_state'] as String?) {
    case 'UPCOMING':
      return PublicUpcomingMatch(
        // The function names the id `match_id`; the view and the existing
        // mapper call it `id`. Renamed here, at the edge.
        match: publicMatchFromRow({...row, 'id': row['match_id']}),
        communityLogoUrl: logo,
      );
    case 'COMPLETED':
      return PublicCompletedMatch(
        id: row['match_id'] as String,
        communityId: row['community_id'] as String,
        communityName: row['community_name'] as String,
        communityLogoUrl: logo,
        title: row['title'] as String?,
        location: row['location'] as String?,
        startAt: DateTime.parse(row['start_at'] as String).toLocal(),
        endAt: DateTime.parse(row['end_at'] as String).toLocal(),
        hasResult: row['has_result'] as bool? ?? false,
        teamAScore: row['team_a_score'] as int?,
        teamBScore: row['team_b_score'] as int?,
        mvpDisplayName: row['mvp_display_name'] as String?,
        mvpAvatarUrl: avatarUrl(row['mvp_avatar_path'] as String?),
        lineup: lineup,
      );
    default:
      return null;
  }
}

/// Reads a `public_match_lineup` row.
PublicLineupEntry publicLineupEntryFromRow(
  Map<String, dynamic> row, {
  required String? Function(String? path) avatarUrl,
}) =>
    PublicLineupEntry(
      team: row['team'] as String,
      assignedPosition: row['assigned_position'] as String?,
      displayName: row['display_name'] as String? ?? '',
      avatarUrl: avatarUrl(row['avatar_path'] as String?),
      isProfessionalGuest: row['participant_type'] == 'PROFESSIONAL',
      goals: row['goals'] as int? ?? 0,
      isMvp: row['is_mvp'] as bool? ?? false,
      playerId: row['player_id'] as String?,
    );
