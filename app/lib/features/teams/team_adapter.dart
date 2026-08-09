import 'package:btge/btge.dart';

import 'team_models.dart';

/// The team-generation aggregate's port into the data provider: the Core
/// Player Inputs behind a match's confirmed seats, the played lineups
/// Diversity is allowed to consult, and the stored lineup itself.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Nothing here decides anything (OP-2): which rows
/// make up the generation set, what a missing input means, and which lineup is
/// worth storing are all answered above this layer. An implementation reads
/// and writes the rows it is asked for, and converts.
abstract interface class TeamAdapter {
  /// The Core Player Inputs (§4.1) behind the **confirmed** seats of
  /// [matchId], in registration order.
  ///
  /// Reserves are excluded because they hold no seat, not because this layer
  /// judged them: it reads confirmed rows, the same way the match port reads
  /// matches that have not ended.
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(String matchId);

  /// The lineups of matches in [communityId] that have already ended, most
  /// recent first, excluding [excludeMatchId] and capped at [limit] matches.
  ///
  /// Auxiliary Data (§4.2.1): the factual record of who played together, and
  /// nothing else. [limit] is supplied by the caller rather than chosen here:
  /// the lookback window is `OP-6`, a Product Decision, and this layer does not
  /// hold product decisions (OP-2). The approved value lives in
  /// `team_generation_settings.dart`.
  ///
  /// Matches with no stored lineup are absent rather than empty: there is
  /// nothing to record about who played with whom.
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  });

  /// The stored lineup of [matchId]; empty when none was saved.
  Future<List<TeamAssignment>> fetchLineup(String matchId);

  /// Replaces the stored lineup of [matchId] with [lineup].
  ///
  /// One path for both a generated and a manually adjusted lineup: `KB-017`
  /// and `BTGE-MO-5` make the lineup that actually played the thing recorded,
  /// however it came to be. An empty [lineup] clears what was stored.
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup);

  /// Records that [userId] played [matchId] on [team] at [position].
  ///
  /// For a **completed** match only: correcting who was on the pitch is a
  /// different operation from claiming a seat in a match still to come, and the
  /// roster of a live match belongs to capacity, the reserve queue and the
  /// player's own decision to join. An implementation raises rather than
  /// applying this to one.
  ///
  /// The assignment basis is not a parameter. §5.1 defines it as which rule
  /// produced the position, so it is derived from the player's profile where
  /// that profile is authoritative — in the database, alongside the write.
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  });

  /// Records that [userId] did not play [matchId] after all, removing them from
  /// both the lineup and the roster. Completed matches only, for the same
  /// reason.
  Future<void> removePlayedPlayer(String matchId, String userId);
}
