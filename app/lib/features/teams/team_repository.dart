import 'package:btge/btge.dart';

import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_team_adapter.dart';
import '../matches/match_models.dart';
import 'team_adapter.dart';
import 'team_models.dart';

/// Data access for team generation.
///
/// It does two things, and they are the two ends of the engine: it turns what
/// the schema holds into the approved input contract (§4), and it writes a
/// lineup back (§5.1). It does **not** run the engine — generating teams is
/// the next milestone, and this layer exists so that when it arrives the
/// engine still sees nothing but `package:btge` types.
class TeamRepository {
  TeamRepository([TeamAdapter? adapter])
      : _adapter = adapter ?? SupabaseTeamAdapter();

  final TeamAdapter _adapter;

  /// Assembles the engine's inputs for [match] from the confirmed roster.
  ///
  /// [historyLookback] is `OP-6` and deliberately has no default: §18.1
  /// forbids letting one stand in for a Product Decision. Null means the
  /// window is unset, which is the approved `BTGE-DV-5` path — Diversity sees
  /// no history and contributes nothing. Absence of history is never an error,
  /// so nothing is read and nothing fails.
  ///
  /// Throws [ValidationFailure] carrying [FailureReason.missingPlayerInputs]
  /// when a confirmed player has no date of birth. §4.3 rejects a missing Core
  /// Player Input rather than substituting a default, and migration `0018`
  /// placed that judgement above the schema deliberately — this is where it
  /// lives.
  Future<GenerationInputs> fetchGenerationInputs(
    Match match, {
    required int? historyLookback,
  }) async {
    final roster = await _adapter.fetchConfirmedPlayerInputs(match.id);
    if (roster.any((player) => !player.hasEveryRequiredInput)) {
      throw const ValidationFailure(FailureReason.missingPlayerInputs);
    }

    return GenerationInputs(
      players: [for (final player in roster) player.toPlayer()],
      // Age is computed as of the match date, read in the device's local time
      // (§15, `DD-11`). The match model already holds it that way.
      settings: MatchSettings(matchDate: match.startAt),
      history: await _historyFor(match, historyLookback),
    );
  }

  /// The confirmed players of [matchId] whose profile is missing a Core Player
  /// Input (§4.1). Empty when the match has everything the engine needs.
  ///
  /// This is the readable half of the rejection above: the failure says that
  /// something is missing, and this says whose profile to finish.
  Future<List<PlayerCoreInputs>> fetchPlayersMissingInputs(
    String matchId,
  ) async {
    final roster = await _adapter.fetchConfirmedPlayerInputs(matchId);
    return [
      for (final player in roster)
        if (!player.hasEveryRequiredInput) player,
    ];
  }

  /// The stored lineup of a match: what actually played (`KB-017`), whether
  /// the engine produced it or the organizer adjusted it afterwards.
  Future<List<TeamAssignment>> fetchLineup(String matchId) =>
      _adapter.fetchLineup(matchId);

  /// Records [lineup] as the lineup of [matchId], replacing whatever was
  /// stored before.
  ///
  /// A generated result reaches this through [TeamAssignment.fromAssignment];
  /// an organizer's adjustment reaches it directly. `BTGE-MO-5` makes both the
  /// authoritative lineup for the match, so both take the same path.
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) =>
      _adapter.saveLineup(matchId, lineup);

  Future<MatchHistory> _historyFor(Match match, int? lookback) async {
    // A window of nothing is the same as no window: there is no match to read
    // and so no pair to count.
    if (lookback == null || lookback <= 0) return const MatchHistory.empty();
    return MatchHistory(await _adapter.fetchPlayedLineups(
      communityId: match.communityId,
      excludeMatchId: match.id,
      limit: lookback,
    ));
  }
}
