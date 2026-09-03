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
