import 'package:btge/btge.dart';

import 'team_models.dart';

/// One account player as BTGE received them, reduced to what balancing used.
///
/// The minimal input snapshot of the Wave 3 design (§3.2): the four Core
/// Player Inputs, with age already derived at the match date exactly as the
/// engine derives it. No name, contact detail, avatar or date of birth — the
/// engine never needed the birthday itself, only the age it implies.
class GenerationPlayerInput {
  const GenerationPlayerInput({
    required this.userId,
    required this.overallRating,
    required this.ageAtMatch,
    required this.primaryPosition,
    this.secondaryPosition,
  });

  /// [player] as the engine saw it, with its age at [matchDate] computed by
  /// the engine's own rule ([Player.ageAt]).
  GenerationPlayerInput.fromPlayer(Player player, DateTime matchDate)
      : userId = player.id,
        overallRating = player.overallRating,
        ageAtMatch = player.ageAt(matchDate),
        primaryPosition = player.primaryPosition,
        secondaryPosition = player.secondaryPosition;

  final String userId;
  final double overallRating;
  final int ageAtMatch;
  final Position primaryPosition;
  final Position? secondaryPosition;
}

/// What BTGE generated, captured before any human edit (Wave 3, §3).
///
/// Built once, from the **same** [GenerationInputs] and the **same**
/// [GenerationResult] that produced the lineup being saved — see
/// [GenerationEvidence.capture]. There is no second read behind it.
///
/// It deliberately carries no quality metric and no diagnostic beyond the
/// variant the engine returned: every score of §15 can be recomputed from the
/// inputs, the configuration and the proposal, and the approved contract says
/// not to persist what can be recalculated.
class GenerationEvidence {
  GenerationEvidence._({
    required this.variantIndex,
    required this.configuration,
    required this.historyLookback,
    required List<GenerationPlayerInput> playerInputs,
    required List<(String, String)> teammatePairs,
    required List<TeamAssignment> generatedLineup,
  })  : playerInputs = List.unmodifiable(playerInputs),
        teammatePairs = List.unmodifiable(teammatePairs),
        generatedLineup = List.unmodifiable(generatedLineup);

  /// The evidence of one engine run.
  ///
  /// [inputs] and [result] must be the pair the engine was given and returned;
  /// [configuration] and [historyLookback] the values the caller supplied for
  /// that run. Nothing here reads or re-derives them from anywhere else.
  factory GenerationEvidence.capture({
    required GenerationInputs inputs,
    required GenerationResult result,
    required BtgeConfiguration configuration,
    required int? historyLookback,
  }) {
    final matchDate = inputs.settings.matchDate;

    // Exactly the set priority 5 is handed: `BtgeEngine` asks the history for
    // the pairs in its window with these three arguments and no others.
    final pairs = inputs.history
        .pairsInWindow(
      asOf: matchDate,
      lastNMatches: configuration.diversityLastNMatches,
      within: configuration.diversityWithin,
    )
        .map((pair) {
      final ids = pair.split('|');
      return (ids[0], ids[1]);
    }).toList()
      ..sort((a, b) {
        final first = a.$1.compareTo(b.$1);
        return first != 0 ? first : a.$2.compareTo(b.$2);
      });

    return GenerationEvidence._(
      variantIndex: result.diagnostics.variantIndex,
      configuration: configuration,
      historyLookback: historyLookback,
      playerInputs: [
        for (final player in inputs.players)
          GenerationPlayerInput.fromPlayer(player, matchDate),
      ],
      teammatePairs: pairs,
      generatedLineup: [
        for (final assignment in result.assignments)
          TeamAssignment.fromAssignment(assignment),
      ],
    );
  }

  /// Which of the engine's equally optimal answers was returned.
  final int variantIndex;

  /// The exact configuration the engine ran with.
  final BtgeConfiguration configuration;

  /// How many played lineups were read for Diversity; null when unset.
  final int? historyLookback;

  /// Every account player the engine received, in the order it received them.
  final List<GenerationPlayerInput> playerInputs;

  /// The teammate pairs priority 5 was given, each pair ordered and the list
  /// sorted, so the same context always serialises the same way.
  final List<(String, String)> teammatePairs;

  /// The engine's proposal: account players only, before guests are seated
  /// around it and before any manual edit.
  final List<TeamAssignment> generatedLineup;
}

/// A generated lineup together with the evidence of how it was generated.
///
/// The lineup *is* the evidence's proposal rather than a copy of it, so what is
/// shown, what is saved and what is captured cannot drift apart.
class GeneratedTeams {
  const GeneratedTeams(this.evidence);

  final GenerationEvidence evidence;

  /// The lineup to save: the engine's proposal, account players only.
  List<TeamAssignment> get lineup => evidence.generatedLineup;
}
