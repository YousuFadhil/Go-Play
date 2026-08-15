import '../../../features/statistics/statistics_models.dart';
import 'team_mapper.dart';

// Conversion from a `community_statistics` row into the statistics domain
// model. Every column the dashboard reads appears here and nowhere else (OP-3).
//
// There is no `...ToRow` counterpart, and there should never be one. The
// counters are written by the database as a consequence of a recorded result;
// a payload built in the app could only describe a number nobody earned, and
// the table grants no client the privilege to send one anyway.

/// Reads one player's counters in one community.
///
/// The name arrives through the embedded `user` object rather than as a column,
/// because `community_statistics` stores no name — it identifies a player by id
/// and leaves the profile where it belongs.
///
/// **A null embed is expected, not defensive.** PostgREST resolves the embed
/// under the caller's own policies, and the `users` policy returns active
/// profiles only. A soft-deleted account keeps its statistics rows and loses
/// its profile, so the row arrives with `user: null`. That is a player whose
/// figures still count and whose name cannot be shown, which is exactly what a
/// null [CommunityPlayerStatistics.fullName] means.
CommunityPlayerStatistics communityPlayerStatisticsFromRow(
  Map<String, dynamic> row, {
  String? Function(String? path)? avatarUrl,
}) {
  final user = row['user'] as Map<String, dynamic>?;
  return CommunityPlayerStatistics(
    userId: row['user_id'] as String,
    fullName: user?['full_name'] as String?,
    // From the same embed as the name, so the two are absent together: a
    // soft-deleted account has neither a name to show nor a face.
    avatarUrl: avatarUrl?.call(user?['avatar_path'] as String?),
    matchesPlayed: _counter(row['matches_played']),
    wins: _counter(row['wins']),
    losses: _counter(row['losses']),
    draws: _counter(row['draws']),
    goals: _counter(row['goals']),
    mvpCount: _counter(row['mvp_count']),
  );
}

/// Reads a roster row from `v_community_members`.
///
/// `full_name` is `not null` on `users` and the view inner-joins it, so unlike
/// a `community_statistics` row there is no unnamed case to carry here: a
/// member whose profile is hidden is not in this view at all.
/// [avatarUrl] is supplied by the adapter rather than read from [row]: the view
/// carries the roster and the rating but not the picture's path.
CommunityMemberRating communityMemberRatingFromRow(
  Map<String, dynamic> row, {
  String? avatarUrl,
}) {
  return CommunityMemberRating(
    userId: row['user_id'] as String,
    fullName: row['full_name'] as String,
    avatarUrl: avatarUrl,
    // `ratingFromDb` rather than a cast: `numeric` reaches the client as a JSON
    // number or as its text form depending on the transport, and
    // `overall_rating` was observed arriving as the string "5.15".
    rating: ratingFromDb(row['overall_rating']),
  );
}

/// Every counter is `int not null default 0` in the database, so a null here
/// would mean the column was left out of the projection rather than that the
/// player has none. Reading it as zero keeps a mistake in the column list from
/// crashing a screen, and the totals it produces are visibly wrong rather than
/// silently plausible.
int _counter(Object? value) => (value as num?)?.toInt() ?? 0;
