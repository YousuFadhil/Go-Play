import '../../infrastructure/supabase/supabase_player_record_adapter.dart';
import 'player_record_adapter.dart';
import 'player_record_models.dart';

/// A player's football record: their recent form, and the achievements a
/// profile shows.
///
/// **Which achievements those are is the database's answer, and deliberately.**
/// The rule — the latest MVP, plus every Team of Period award for the last
/// *closed* week and month, one per community — is a question about stored
/// snapshots and closed periods, and `player_recent_achievements` (migration
/// `0081`) is where both already live. Choosing here would mean reading every
/// award a player ever won in order to discard almost all of them, and
/// re-deciding in the client what the snapshot writer already settled.
class PlayerRecordRepository {
  PlayerRecordRepository([PlayerRecordAdapter? adapter])
      : _adapter = adapter ?? SupabasePlayerRecordAdapter();

  final PlayerRecordAdapter _adapter;

  /// How many matches Recent Form is about. Five, which is the approved
  /// window, and stated once so the screen, the card and the read agree.
  static const formWindow = 5;

  /// How many achievement cards a profile shows at most. Five, approved, and
  /// stated once so the read, the screen and the public contract agree.
  static const achievementWindow = 5;

  /// The player's recent form, for a signed-in reader.
  Future<RecentForm> recentForm(String userId) =>
      _adapter.fetchRecentForm(userId, limit: formWindow);

  /// The achievements to show a signed-in reader, newest first. Empty draws no
  /// section.
  ///
  /// A Team of Period award is present only for a period whose snapshot has
  /// been written, and only for the last closed one. The screen's live Team of
  /// Period is not consulted: it may describe a week still in progress, and an
  /// award that could change tomorrow is not an achievement.
  Future<List<RecentHighlight>> recentAchievements(String userId) =>
      _adapter.fetchRecentAchievements(userId, limit: achievementWindow);

  /// Everything a public Player Profile shows, for a reader with no session.
  ///
  /// Null when there is no public profile at that id — the player does not
  /// exist, or is not active. The two are the same answer on purpose: a
  /// guessed id must not be able to tell a suspended account from a fictional
  /// one.
  Future<PublicPlayerRecord?> publicRecord(String userId) =>
      _adapter.fetchPublicRecord(
        userId,
        limit: formWindow,
        achievements: achievementWindow,
      );
}
