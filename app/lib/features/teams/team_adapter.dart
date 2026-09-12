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
  ///
  /// [fromGeneration] is the one thing the two callers do not share. A
  /// generated lineup is a fresh search, and `BTGE-MO-2` makes it discard what
  /// was adjusted around the previous one — so the guests give up the sides an
  /// organizer chose for them and re-alternate around the new teams. A manual
  /// save is the adjustment itself, and must keep them.
  ///
  /// A flag rather than a second method: it changes one thing about one write,
  /// and the two callers are already distinct above this layer — generation
  /// reaches here through `TeamRepository.saveLineup`, every manual operation
  /// through its private replace.
  ///
  /// [completedCorrection] is the second, and it answers a different question:
  /// not *how* this lineup was arrived at, but *what it is for*. A match that
  /// has been played has a factual record of who was on the pitch, and an
  /// owner or admin may still correct it — someone who actually played was
  /// missing, someone who did not is listed, a side or a position is wrong.
  /// That is the only kind of write a completed match accepts, and migration
  /// `0071` refuses every other.
  ///
  /// The two flags are independent but not freely combinable, and the database
  /// enforces the shape:
  ///
  ///   * `fromGeneration` on a completed match → `MATCH_COMPLETED`, even with
  ///     [completedCorrection] set. A generation is the engine proposing teams;
  ///     it is never a statement about what happened.
  ///   * no [completedCorrection] on a completed match → `MATCH_COMPLETED`.
  ///   * [completedCorrection] on a match that is *not* completed →
  ///     `MATCH_NOT_COMPLETED`. There is no history to correct yet, and letting
  ///     it pass would turn the flag into something callers set by habit.
  ///
  /// **It is intent, never inference.** No implementation may decide this by
  /// looking at the assignments — a correction and a regeneration can produce
  /// identical payloads, and what separates them is what the caller meant.
  Future<void> saveLineup(
    String matchId,
    List<TeamAssignment> lineup, {
    bool fromGeneration = false,
    bool completedCorrection = false,
  });

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

  /// Corrects several community players of a **completed** [matchId] at once:
  /// each entry of [corrections] places one player in the lineup or takes one
  /// out of it.
  ///
  /// One operation rather than a loop over [addPlayedPlayer] and
  /// [removePlayedPlayer], and the difference is not convenience. Every single
  /// correction reverses the match's ratings and statistics and reapplies them,
  /// so N calls would recalculate N times over intermediate lineups that nobody
  /// ever played, and a refusal partway through would leave the earlier changes
  /// standing. An implementation passes the whole list down in one go, and the
  /// database validates all of it, recalculates once from the lineup it adds up
  /// to, and refuses all of it or none of it.
  ///
  /// Professional Guests keep their places: they are corrected by their own
  /// operations, not by this one.
  Future<void> correctCompletedPlayers(
    String matchId,
    List<CompletedPlayerCorrection> corrections,
  );

  /// The same correction for a Professional Guest: this guest did not play
  /// [matchId] after all, so the lineup row goes along with the roster seat.
  ///
  /// Deliberately **not** `remove_professional_guest`. That function means
  /// something else and says so: it takes the seat and *keeps* the lineup row,
  /// the goals and the MVP, because on a played match those are the record of
  /// what happened. Wiring this to it would take a guest off the roster while
  /// still showing them on the pitch.
  ///
  /// Refused when the guest scored in the recorded result, rather than deleting
  /// their goals: the goals recorded have to equal the score, and taking a
  /// scorer out silently would either break that or quietly rewrite the score.
  /// The organizer corrects the result first.
  Future<void> removePlayedProfessionalGuest(String matchId, String guestId);
}
