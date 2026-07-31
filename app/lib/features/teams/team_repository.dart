import 'package:btge/btge.dart';

import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_team_adapter.dart';
import '../matches/match_models.dart';
import 'team_adapter.dart';
import 'team_models.dart';

/// Data access and team generation.
///
/// It turns what the schema holds into the approved input contract (§4), runs
/// the engine over it, and maps the result back into Domain Models. The engine
/// sees nothing but `package:btge` types; no layer above sees anything else
/// either.
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

  /// Generates the two teams for [match] and returns the lineup.
  ///
  /// [configuration] carries the Open Parameters of §18.1 — `OP-2`, `OP-3`,
  /// `OP-5` and `OP-6` are Product Decisions still open, and none of them is
  /// this layer's to make. `BtgeConfiguration` gives them no defaults, so an
  /// unmade decision is a compile error at the call site rather than a silent
  /// assumption, which is exactly what §18.1 asks for.
  ///
  /// [historyLookback] is how many played lineups to read. The window the
  /// engine then applies over them is `configuration.diversityLastNMatches`
  /// and `diversityWithin`. Both are `OP-6` seen from either side — one is how
  /// much to fetch, the other how much of it counts — and the caller states
  /// both.
  ///
  /// **Nothing is stored.** `BTGE-MO-2` lets the organizer move a player
  /// before the lineup is settled, and `KB-017` records what actually played,
  /// so saving is a separate deliberate call to [saveLineup] with whatever the
  /// organizer ended up with.
  ///
  /// The quality metrics of §15 are not returned: §5.2 makes surfacing any of
  /// them a separate product decision, and this milestone does not carry one.
  ///
  /// Throws [ValidationFailure] when the engine refuses the input — too few or
  /// too many players (`BTGE-PF-2`), a duplicate id, or a Core Player Input it
  /// will not invent (§4.3).
  Future<List<TeamAssignment>> generateTeams(
    Match match, {
    required BtgeConfiguration configuration,
    required int? historyLookback,
  }) async {
    final inputs =
        await fetchGenerationInputs(match, historyLookback: historyLookback);

    final GenerationResult result;
    try {
      result = BtgeEngine(configuration).generate(
        players: inputs.players,
        settings: inputs.settings,
        history: inputs.history,
      );
    } on BtgeInputError catch (error) {
      throw _refusalFor(error);
    }

    return [
      for (final assignment in result.assignments)
        TeamAssignment.fromAssignment(assignment),
    ];
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

  /// The engine's input rejections, in the application's error language.
  ///
  /// Every `BtgeInputError` is a caller error about the data handed in (§4.3),
  /// which is what `ValidationFailure` already means — one of the eight
  /// approved types, not a new one. A missing Core Player Input reuses the
  /// reason [fetchGenerationInputs] raises for the same thing; the rest carry
  /// none, because a reason per error code would be product vocabulary no
  /// approved document asks for.
  ///
  /// A `StateError` from the engine is deliberately not caught. It is not an
  /// input rejection but the documented refusal to truncate an exact search
  /// (`BTGE-PF-4`), and classifying it into one of the eight types is a
  /// decision no approved document makes.
  Failure _refusalFor(BtgeInputError error) => switch (error.code) {
        BtgeErrorCode.missingRequiredInput =>
          const ValidationFailure(FailureReason.missingPlayerInputs),
        _ => const ValidationFailure(),
      };

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
