import 'player_record_models.dart';

/// The port for a player's football *record*, as opposed to their profile row.
///
/// **A second port rather than five more methods on `ProfileAdapter`, and
/// deliberately.** That port is the signed-in player's own account — the row
/// they edit, the picture they upload, the preferences they set — and it is
/// implemented by every screen test that puts a profile on screen. What is
/// here is a different question with a different audience: what a player has
/// done, read by anyone the server will answer, including a visitor with no
/// session at all. Keeping them apart is what lets a public read exist without
/// every account fake growing a method about it.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5).
///
/// **Two of everything, and the pairs are not interchangeable.** The `public`
/// reads go to the narrow contracts migration `0079` grants `anon`; the others
/// go to the authenticated ones. Which pair a caller uses is decided by whether
/// there is a session, never by what the caller would like to show — a screen
/// cannot reach for the richer read to fill a gap in the public one.
abstract interface class PlayerRecordAdapter {
  /// The player's last [limit] completed matches, newest first, for a signed-in
  /// reader.
  ///
  /// The server clamps [limit]; passing a larger number returns the clamp
  /// rather than an error, because a bounded read is the contract and refusing
  /// would make a caller's arithmetic mistake a visible failure for the reader.
  Future<RecentForm> fetchRecentForm(String userId, {int limit});

  /// The player's most recent MVP award, or null when they have none.
  ///
  /// Null is an ordinary answer: most players have no MVP, and a profile
  /// without one simply has no highlight from this source.
  /// The achievements a profile shows, newest first, at most [limit].
  ///
  /// **The database chooses them, not the client** (`player_recent_achievements`,
  /// migration `0081`): the player's latest MVP, and every Team of Period award
  /// they hold for the last *closed* week and the last closed month — one row
  /// per community they were selected in. An older period is never substituted
  /// for one they were not selected in, and no selection is recomputed here.
  Future<List<RecentHighlight>> fetchRecentAchievements(
    String userId, {
    int limit = 5,
  });

  /// The same player's record as a visitor with no session sees it.
  ///
  /// What comes back is narrower by construction rather than by this layer
  /// leaving fields out: the public contracts carry no match id, no community
  /// id and no kick-off time, so there is nothing here to withhold.
  Future<PublicPlayerRecord?> fetchPublicRecord(
    String userId, {
    int limit,
    int achievements,
  });
}
