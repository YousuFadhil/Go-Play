import 'package:btge/btge.dart';

import 'team_of_period_models.dart';

/// A Team of Period result, in the shape `record_team_of_period_snapshot`
/// stores (migration `0079`).
///
/// **A translation, not a decision.** Everything here is read off a
/// [TeamOfPeriod] that `TeamOfPeriodSelector.select` already produced: the
/// period, the state, the target size and the seats, in the order the
/// selector put them. Nothing is ranked, filtered or recomputed, which is what
/// keeps the selector the only place a seat is decided — the stored award is
/// its output written down, and a snapshot built any other way would be a
/// second algorithm.
///
/// Pure Dart on purpose. The selector and its models import only `btge`, so a
/// trusted writer can build this outside the Flutter app without porting a
/// line of the selection.
class TeamOfPeriodSnapshot {
  const TeamOfPeriodSnapshot({
    required this.communityId,
    required this.periodType,
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    required this.state,
    required this.targetSize,
    required this.selectorVersion,
    required this.awards,
    this.evidenceLastChangedAt,
  });

  /// The snapshot for [team], which [communityId]'s evidence produced.
  ///
  /// [selectorVersion] names the selector build that decided it, so a stored
  /// award can always be traced to the code that chose it.
  factory TeamOfPeriodSnapshot.fromSelection({
    required String communityId,
    required TeamOfPeriod team,
    required String selectorVersion,
  }) {
    final window = team.window;

    // The selector lists seats GK, DEF, MID, FWD and, within each role, in the
    // approved candidate ranking. The rank is that position within the role,
    // read rather than re-derived.
    final nextRank = <Position, int>{};
    final awards = [
      for (final seat in team.selected)
        TeamOfPeriodAward(
          userId: seat.userId,
          assignedPosition: seat.assignedPosition,
          rankInRole: nextRank.update(
            seat.assignedPosition,
            (rank) => rank + 1,
            ifAbsent: () => 1,
          ),
        ),
    ];

    return TeamOfPeriodSnapshot(
      communityId: communityId,
      periodType: switch (window.kind) {
        TeamOfPeriodKind.weekly => 'weekly',
        TeamOfPeriodKind.monthly => 'monthly',
      },
      periodKey: window.periodKey,
      periodStart: window.periodStart,
      periodEnd: window.periodEnd,
      state: switch (team.state) {
        TeamOfPeriodState.selected => 'SELECTED',
        TeamOfPeriodState.noQualifyingMatches => 'NO_QUALIFYING_MATCHES',
        TeamOfPeriodState.insufficientEligiblePlayers =>
          'INSUFFICIENT_ELIGIBLE_PLAYERS',
      },
      targetSize: team.targetSize,
      evidenceLastChangedAt: window.evidenceLastChangedAt,
      selectorVersion: selectorVersion,
      awards: awards,
    );
  }

  final String communityId;
  final String periodType;
  final String periodKey;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String state;
  final int targetSize;
  final DateTime? evidenceLastChangedAt;
  final String selectorVersion;
  final List<TeamOfPeriodAward> awards;

  /// The named parameters of `record_team_of_period_snapshot`.
  ///
  /// Instants are sent in UTC ISO-8601: the database compares them with its
  /// own canonical period bounds, and a local-time rendering would be the same
  /// instant written a way that invites a mistake.
  Map<String, Object?> toRpcParams() => {
        'p_community_id': communityId,
        'p_period_type': periodType,
        'p_period_key': periodKey,
        'p_period_start': periodStart.toUtc().toIso8601String(),
        'p_period_end': periodEnd.toUtc().toIso8601String(),
        'p_state': state,
        'p_target_size': targetSize,
        'p_evidence_last_changed_at':
            evidenceLastChangedAt?.toUtc().toIso8601String(),
        'p_selector_version': selectorVersion,
        'p_awards': [
          for (final award in awards)
            {
              'user_id': award.userId,
              'assigned_position': award.assignedPosition.code,
              'rank_in_role': award.rankInRole,
            },
        ],
      };
}

/// One seat in a stored Team of Period.
class TeamOfPeriodAward {
  const TeamOfPeriodAward({
    required this.userId,
    required this.assignedPosition,
    required this.rankInRole,
  });

  final String userId;
  final Position assignedPosition;

  /// 1 for the first player the selector seated in this role.
  final int rankInRole;
}
