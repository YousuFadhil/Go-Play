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
  /// [historyLookback] is `OP-6` and deliberately has no default here: §18.1
  /// forbids letting one stand in for a Product Decision, so the approved
  /// value is supplied by the caller from `team_generation_settings.dart`.
  /// Null means the window is unset, which is the approved `BTGE-DV-5` path —
  /// Diversity sees no history and contributes nothing. Absence of history is
  /// never an error, so nothing is read and nothing fails.
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
  /// [configuration] carries the parameters of §18.1 — `OP-2`, `OP-3`, `OP-5`
  /// and `OP-6`, all now approved and recorded in §18.1.1. None of them is
  /// this layer's to choose: `BtgeConfiguration` still gives them no defaults,
  /// so the caller states them, and the approved set lives in
  /// `team_generation_settings.dart` as `approvedTeamGeneration`.
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
  /// [avoiding] is the lineup the organizer is looking at, and is how
  /// regeneration stops handing back the teams it just produced. The engine
  /// settles on a set of splits it rates equally, and returning the first of
  /// them every time made a second press of the button a no-op even where the
  /// engine itself saw no reason to prefer those teams. When the first answer
  /// repeats [avoiding] and the engine reports another that is just as good,
  /// that one is taken instead.
  ///
  /// Nothing about this is random (`BTGE-PF-6`): the alternative is the next
  /// member of a canonically ordered set, so the same match with the same stored
  /// lineup always regenerates to the same teams. When the search has only one
  /// optimal answer there is nothing to offer, and the organizer is given it
  /// again rather than a worse split — `BTGE-PF-4` does not bend to make a
  /// button feel productive.
  ///
  /// Throws [ValidationFailure] when the engine refuses the input — too few or
  /// too many players (`BTGE-PF-2`), a duplicate id, or a Core Player Input it
  /// will not invent (§4.3).
  Future<List<TeamAssignment>> generateTeams(
    Match match, {
    required BtgeConfiguration configuration,
    required int? historyLookback,
    List<TeamAssignment> avoiding = const [],
  }) async {
    final inputs =
        await fetchGenerationInputs(match, historyLookback: historyLookback);
    final engine = BtgeEngine(configuration);

    GenerationResult run(int variant) {
      try {
        return engine.generate(
          players: inputs.players,
          settings: inputs.settings,
          history: inputs.history,
          variant: variant,
        );
      } on BtgeInputError catch (error) {
        throw _refusalFor(error);
      }
    }

    var result = run(0);
    // One further search at most. Each variant is a different partition, so the
    // next one is necessarily a different split — there is nothing to gain from
    // walking the whole set, and the search is exhaustive enough to be worth
    // running twice rather than many times.
    if (result.diagnostics.equallyOptimalSolutions > 1 &&
        _isSameSplit(result.assignments, avoiding)) {
      result = run(1);
    }

    return [
      for (final assignment in result.assignments)
        TeamAssignment.fromAssignment(assignment),
    ];
  }

  /// Whether [assignments] puts exactly the same players on exactly the same
  /// sides as [lineup].
  ///
  /// Sides, and nothing else: a lineup that moved somebody between positions is
  /// the same distribution of players, and `KB-D6` gives `A` and `B` no meaning
  /// beyond telling the two apart. An empty [lineup] is not a distribution, so
  /// nothing repeats it.
  bool _isSameSplit(
    List<PlayerAssignment> assignments,
    List<TeamAssignment> lineup,
  ) {
    if (lineup.isEmpty || lineup.length != assignments.length) return false;
    final before = {for (final a in lineup) a.userId: a.team};
    return assignments.every((a) => before[a.playerId] == a.team);
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

  /// The confirmed players of [matchId] with the profile behind each one.
  ///
  /// The same read generation makes, offered to the screen that draws the
  /// lineup: a pitch shows a face, a name and a rating, and whether a goalkeeper
  /// position exists at all depends on §10.1's natural-goalkeeper test, which is
  /// a fact about the profiles rather than about the assignments. Reading it
  /// through the port keeps the screen from asking the provider anything.
  ///
  /// Unlike [fetchGenerationInputs] this refuses nothing. A profile with no date
  /// of birth cannot be generated around, but it can certainly be *drawn* — the
  /// player is in the match either way.
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayers(String matchId) =>
      _adapter.fetchConfirmedPlayerInputs(matchId);

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
  ///
  /// This is the generation half of that path — the Teams screen calls it with
  /// what the engine just produced — so it is where the guests give up any side
  /// an organizer chose around the previous teams. The manual operations below
  /// go through `_replace`, which does not.
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) =>
      _adapter.saveLineup(matchId, lineup, fromGeneration: true);

  // --- Correcting who played (completed matches) -----------------------------
  //
  // A played match's record can be wrong about more than which side somebody was
  // on: a member who turned up may never have registered, and a registered
  // player may not have played. Both are corrections to `KB-017`'s record of
  // what actually happened, so both belong here — and both change what the
  // result is worth, which is why the write is one operation the database
  // recalculates around rather than two calls this layer sequences.

  /// Records that [userId] played [matchId] on [team] at [position].
  ///
  /// Also for moving somebody already in the lineup: a lineup row says where a
  /// player played, and correcting it is the same statement made again.
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) =>
      _adapter.addPlayedPlayer(
        matchId,
        userId,
        team: team,
        position: position,
      );

  /// Records that [userId] did not play [matchId] after all.
  Future<void> removePlayedPlayer(String matchId, String userId) =>
      _adapter.removePlayedPlayer(matchId, userId);

  /// Records that the Professional Guest [guestId] did not play [matchId] after
  /// all: the lineup row goes with the roster seat.
  ///
  /// Refused with [FailureReason.resultParticipantRemoved] when they scored in
  /// the recorded result. No goal is deleted and no score is changed by the
  /// attempt — the organizer corrects the result first, and the invariant that
  /// the goals recorded equal the score is never weakened to make a removal
  /// possible.
  Future<void> removePlayedProfessionalGuest(String matchId, String guestId) =>
      _adapter.removePlayedProfessionalGuest(matchId, guestId);

  // --- Manual Override (§13) -------------------------------------------------
  //
  // `BTGE-MO-1` requires manual override to remain supported, and `BTGE-MO-2`
  // says what it costs: the organizer may move a player or swap two of them
  // **without rerunning the engine**. Nothing below consults `BtgeEngine`,
  // recomputes a metric, or compensates for what the organizer did —
  // `BTGE-MO-3` makes their decision stand even when it worsens every metric.
  //
  // Each operation reads the stored lineup, changes exactly what it was asked
  // to, and writes the whole lineup back. Reading first is deliberate: the
  // lineup on an organizer's screen may be older than the stored one, and
  // `BTGE-MO-5` makes the stored one authoritative. Writing the whole lineup is
  // what the port already does, and migration `0020` made it a single
  // transaction, so a refused edit leaves the previous lineup as it was.

  /// Moves [participantId] to the other team, keeping their assigned position.
  ///
  /// Only that participant moves. `BTGE-MO-3` forbids rebalancing the sides
  /// afterwards or moving somebody back in compensation: the organizer asked
  /// for this, and the result is theirs.
  ///
  /// Takes a participant id, not a user id. A Professional Guest is moved by
  /// the same operation as anybody else on the pitch — the two differ in which
  /// column names them, which is exactly what `participantId` exists to stop
  /// mattering here.
  ///
  /// Throws [ValidationFailure] when the participant is not in the stored
  /// lineup.
  Future<void> movePlayer(String matchId, String participantId) async {
    final lineup = await _adapter.fetchLineup(matchId);
    final player = _find(lineup, participantId);

    await _replace(matchId, lineup, {
      participantId: player.movedToOtherTeam(manualOverride: true),
    });
  }

  /// Exchanges the teams of [firstParticipantId] and [secondParticipantId].
  ///
  /// Each keeps their assigned position — a swap is about which side somebody
  /// is on, and §13 gives it no authority over anything else. A guest keeps a
  /// null position, because that is the position they have.
  ///
  /// Either side may be a Professional Guest, including both.
  ///
  /// Throws [ValidationFailure] when either participant is absent from the
  /// stored lineup, when they are the same participant, or when they are
  /// already on the same team: there is no swap to perform, and silently doing
  /// nothing would report success for an operation that never happened.
  Future<void> swapPlayers(
    String matchId,
    String firstParticipantId,
    String secondParticipantId,
  ) async {
    if (firstParticipantId == secondParticipantId) {
      throw const ValidationFailure();
    }

    final lineup = await _adapter.fetchLineup(matchId);
    final first = _find(lineup, firstParticipantId);
    final second = _find(lineup, secondParticipantId);
    if (first.team == second.team) throw const ValidationFailure();

    await _replace(matchId, lineup, {
      firstParticipantId: first.movedToOtherTeam(manualOverride: true),
      secondParticipantId: second.movedToOtherTeam(manualOverride: true),
    });
  }

  /// Gives [userId] the assigned position [position] in this match's lineup.
  ///
  /// This is the lineup's record of where they played, and nothing else: the
  /// profile's primary and secondary positions, the rating, and therefore every
  /// input a later generation reads (§4.1) are untouched.
  ///
  /// The assignment basis follows. §5.1 defines it as which rule produced the
  /// assigned position, and defines Out of Position as exactly `TRANSITION`, so
  /// a basis left behind would describe a position the player no longer holds
  /// and the screen would mark the wrong people. It is therefore re-read from
  /// the same profile §4.1 already defines it against — a derivation, not a new
  /// rule — and kept as it was when that profile cannot be read.
  ///
  /// Throws [ValidationFailure] when the player is not in the stored lineup.
  Future<void> changeAssignedPosition(
    String matchId,
    String userId,
    Position position,
  ) async {
    final lineup = await _adapter.fetchLineup(matchId);
    final player = _find(lineup, userId);

    await _replace(matchId, lineup, {
      userId: player.withPosition(
        position,
        await _basisFor(matchId, userId, position, player.basis),
      ),
    });
  }

  /// The stored assignment of [participantId], or a refusal.
  ///
  /// A manual edit only ever rearranges participants who are already in the
  /// lineup. One who is not is not something to add — `BTGE-HC-3` says the
  /// engine never drops a player, and the reverse holds here: an edit does not
  /// recruit one. A Professional Guest reaches the lineup through the roster
  /// and the guest alternation, never through an edit.
  ///
  /// Matched on `participantId`, so a guest is found by the id that names them.
  /// Matching on `userId` meant a guest was never found at all, and a null
  /// `userId` would have matched every other guest at once.
  TeamAssignment _find(List<TeamAssignment> lineup, String participantId) {
    final found = lineup.where((a) => a.participantId == participantId);
    if (found.length != 1) throw const ValidationFailure();
    return found.single;
  }

  /// Writes [lineup] back with [changes] applied, in the order it was read.
  ///
  /// The guard is the point: what is stored must hold every player of the
  /// lineup it replaces, exactly once. The database says the same through
  /// `unique (match_id, user_id)`, and this says it before the write, so a
  /// mistake here is a refusal rather than a lineup that lost somebody.
  Future<void> _replace(
    String matchId,
    List<TeamAssignment> lineup,
    Map<String, TeamAssignment> changes,
  ) {
    final updated = [
      for (final assignment in lineup)
        changes[assignment.participantId] ?? assignment,
    ];

    final before = {for (final a in lineup) a.participantId};
    final after = {for (final a in updated) a.participantId};
    if (updated.length != lineup.length ||
        after.length != before.length ||
        !after.containsAll(before)) {
      throw const ValidationFailure();
    }

    return _adapter.saveLineup(matchId, updated);
  }

  /// Which rule §5.1 says produced [position] for [userId].
  ///
  /// [fallback] is returned when the player's profile is not among the
  /// confirmed roster — someone who left after the lineup was stored. Nothing
  /// better is known about them, and inventing a basis would be inventing the
  /// out-of-position marker with it.
  Future<AssignmentBasis?> _basisFor(
    String matchId,
    String userId,
    Position position,
    AssignmentBasis? fallback,
  ) async {
    final roster = await _adapter.fetchConfirmedPlayerInputs(matchId);
    final profile = roster.where((p) => p.userId == userId).firstOrNull;
    if (profile == null) return fallback;

    if (position == profile.primaryPosition) return AssignmentBasis.primary;
    if (position == profile.secondaryPosition) {
      return AssignmentBasis.secondary;
    }
    return AssignmentBasis.transition;
  }

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
