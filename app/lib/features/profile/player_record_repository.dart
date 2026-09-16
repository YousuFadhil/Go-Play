import '../../infrastructure/supabase/supabase_player_record_adapter.dart';
import 'player_record_adapter.dart';
import 'player_record_models.dart';

/// A player's football record: their recent form, and the one achievement
/// worth showing.
///
/// **The highlight is decided here, not in the database and not on the
/// screen.** Which of two achievements a profile shows is a product rule —
/// most recent wins, Team of Period breaks a tie — and `OP-2` puts a product
/// rule above the adapter and out of the widget. So the sources are read and
/// [RecentHighlight.mostRecent] is applied to whatever they returned, in one
/// place, whichever screen asked.
class PlayerRecordRepository {
  PlayerRecordRepository([PlayerRecordAdapter? adapter])
      : _adapter = adapter ?? SupabasePlayerRecordAdapter();

  final PlayerRecordAdapter _adapter;

  /// How many matches Recent Form is about. Five, which is the approved
  /// window, and stated once so the screen, the card and the read agree.
  static const formWindow = 5;

  /// The player's recent form, for a signed-in reader.
  Future<RecentForm> recentForm(String userId) =>
      _adapter.fetchRecentForm(userId, limit: formWindow);

  /// The one highlight to show a signed-in reader, or null when there is none.
  ///
  /// **Team of Period is not among the candidates yet, and the shape of this
  /// method is where it will be.** A Period XI is selected by
  /// `TeamOfPeriodSelector` from evidence the database returns per community
  /// and period; nothing stores a selected XI, so there is no bounded read that
  /// answers "was this player in one" and re-running the selection for every
  /// community a player belongs to would be a dozen round trips on a profile
  /// open. Until that source exists this returns the MVP leg, and the tie rule
  /// below already handles both — see [RecentHighlight.mostRecent].
  Future<RecentHighlight?> recentHighlight(String userId) async {
    final mvp = await _adapter.fetchRecentMvp(userId);
    return RecentHighlight.mostRecent([mvp]);
  }

  /// Everything a public Player Profile shows, for a reader with no session.
  ///
  /// Null when there is no public profile at that id — the player does not
  /// exist, or is not active. The two are the same answer on purpose: a
  /// guessed id must not be able to tell a suspended account from a fictional
  /// one.
  Future<PublicPlayerRecord?> publicRecord(String userId) =>
      _adapter.fetchPublicRecord(userId, limit: formWindow);
}
