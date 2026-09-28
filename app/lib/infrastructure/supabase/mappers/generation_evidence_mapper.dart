import 'package:btge/btge.dart';

import '../../../features/teams/generation_evidence.dart';
import 'team_mapper.dart';

/// The arguments of `save_generated_lineup_v1` (migration `0089`) for
/// [evidence] on [matchId].
///
/// The key sets below are the ones the function accepts exactly; a field added
/// here without the migration is refused there rather than silently stored.
Map<String, dynamic> generatedLineupParams(
  String matchId,
  GenerationEvidence evidence,
) =>
    {
      'p_match_id': matchId,
      'p_generated_lineup': [
        for (final assignment in evidence.generatedLineup)
          {
            'user_id': assignment.userId,
            'team': teamToDb(assignment.team),
            'assigned_position': positionToDb(assignment.assignedPosition!),
            'assignment_basis': assignmentBasisToDb(assignment.basis),
          },
      ],
      'p_variant_index': evidence.variantIndex,
      'p_configuration': btgeConfigurationToJson(evidence.configuration),
      'p_player_inputs': [
        for (final player in evidence.playerInputs)
          {
            'user_id': player.userId,
            'overall_rating': player.overallRating,
            'age_at_match': player.ageAtMatch,
            'primary_position': positionToDb(player.primaryPosition),
            'secondary_position': player.secondaryPosition == null
                ? null
                : positionToDb(player.secondaryPosition!),
          },
      ],
      'p_history_context': {
        'history_lookback': evidence.historyLookback,
        'teammate_pairs': [
          for (final (first, second) in evidence.teammatePairs) [first, second],
        ],
      },
    };

/// Every [BtgeConfiguration] value, as the evidence records it.
Map<String, dynamic> btgeConfigurationToJson(BtgeConfiguration configuration) =>
    {
      'distribution_band': _band(configuration.distributionBand),
      'rating_band': _band(configuration.ratingBand),
      'out_of_position_band': _band(configuration.outOfPositionBand),
      'age_band': _band(configuration.ageBand),
      'odd_count_rule': switch (configuration.oddCountRule) {
        OddCountRule.weakerTeamGetsExtra => 'weaker_team_gets_extra',
        OddCountRule.bestFinalBalance => 'best_final_balance',
      },
      'min_players': configuration.minPlayers,
      'transition_cost_by_distance': configuration.transitionCostByDistance,
      'diversity_last_n_matches': configuration.diversityLastNMatches,
      'diversity_within_seconds': configuration.diversityWithin?.inSeconds,
      'assign_emergency_goalkeeper': configuration.assignEmergencyGoalkeeper,
    };

Map<String, double> _band(ToleranceBand band) => {
      'absolute': band.absolute,
      'relative': band.relative,
    };
