import 'dart:io';

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_selector.dart';
import 'package:go_play/features/statistics/team_of_period_snapshot.dart';

/// The stored Team of Period snapshot, built from the selector's own result.
///
/// Every snapshot below is built from what `TeamOfPeriodSelector.select`
/// actually returned for a period's evidence — never from a hand-written team.
/// That is the property that matters: the stored award is the selector's
/// output written down, so the only way to make these tests fail by changing a
/// seat is to change the selector.
void main() {
  final identity = TeamOfPeriodIdentity(
    kind: TeamOfPeriodKind.weekly,
    periodKey: '2026-W31',
    periodStart: DateTime.utc(2026, 7, 26, 20),
    periodEnd: DateTime.utc(2026, 8, 2, 20),
    qualifyingMatchCount: 4,
    requiredMatches: 1,
  );

  TeamOfPeriodWindow windowOf({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    int matches = 4,
  }) =>
      TeamOfPeriodWindow(
        kind: kind,
        periodKey: kind == TeamOfPeriodKind.weekly ? '2026-W31' : '2026-07',
        periodStart: identity.periodStart,
        periodEnd: identity.periodEnd,
        qualifyingMatchCount: matches,
        requiredMatches: 1,
        evidenceLastChangedAt: DateTime.utc(2026, 8, 2, 18),
        teamSizeObservations: matches == 0 ? const [] : const [5, 5, 5],
        positionShapeObservations: matches == 0
            ? const []
            : const [
                PositionShapeObservation(
                  teamSize: 5,
                  gk: 1,
                  def: 2,
                  mid: 1,
                  fwd: 1,
                  unassigned: 0,
                ),
              ],
      );

  TeamOfPeriodCandidate player(
    String id,
    Position primary, {
    double form = 0.10,
    bool eligible = true,
  }) =>
      TeamOfPeriodCandidate(
        userId: id,
        periodIdentity: identity,
        eligible: eligible,
        matchesPlayed: 4,
        participationRate: 1,
        wins: 2,
        draws: 1,
        losses: 1,
        goals: 0,
        goalsPerMatch: 0,
        mvpCount: 0,
        winRate: 0.5,
        pointsPerGame: 1.75,
        periodFormScore: form,
        goalFormContributionTotal: 0,
        periodPrimaryPosition: primary,
        periodSecondaryPosition: null,
        currentOverallRating: 5,
      );

  final squad = [
    player('gk1', Position.gk),
    player('def1', Position.def, form: 0.30),
    player('def2', Position.def, form: 0.20),
    player('mid1', Position.mid),
    player('fwd1', Position.fwd),
  ];

  TeamOfPeriodSnapshot snapshotOf(TeamOfPeriod team) =>
      TeamOfPeriodSnapshot.fromSelection(
        communityId: 'c1',
        team: team,
        selectorVersion: 'test-1',
      );

  group('a snapshot is the selector\'s result written down', () {
    test('the seats are exactly the selector\'s seats, in its order', () {
      final team = TeamOfPeriodSelector.select(
        window: windowOf(),
        candidates: squad,
      );
      final snapshot = snapshotOf(team);

      expect(snapshot.state, 'SELECTED');
      expect(
        [for (final award in snapshot.awards) award.userId],
        [for (final seat in team.selected) seat.userId],
      );
      expect(
        [for (final award in snapshot.awards) award.assignedPosition],
        [for (final seat in team.selected) seat.assignedPosition],
      );
      expect(snapshot.targetSize, team.targetSize);
    });

    test('the rank is the position within the role the selector gave', () {
      final team = TeamOfPeriodSelector.select(
        window: windowOf(),
        candidates: squad,
      );
      final defenders = [
        for (final award in snapshotOf(team).awards)
          if (award.assignedPosition == Position.def) award,
      ];
      final selectorDefenders = [
        for (final seat in team.selected)
          if (seat.assignedPosition == Position.def) seat.userId,
      ];

      expect([for (final d in defenders) d.userId], selectorDefenders);
      expect([for (final d in defenders) d.rankInRole], [1, 2]);
    });

    test('a period with no football is stored as evaluated, with no seats', () {
      final team = TeamOfPeriodSelector.select(
        window: windowOf(matches: 0),
        candidates: const [],
      );
      final snapshot = snapshotOf(team);

      expect(snapshot.state, 'NO_QUALIFYING_MATCHES');
      expect(snapshot.awards, isEmpty);
    });

    test('nobody eligible is stored as that, never as a relaxed team', () {
      final team = TeamOfPeriodSelector.select(
        window: windowOf(),
        candidates: [
          for (final candidate in squad)
            player(
              candidate.userId,
              candidate.periodPrimaryPosition,
              eligible: false,
            ),
        ],
      );
      final snapshot = snapshotOf(team);

      expect(snapshot.state, 'INSUFFICIENT_ELIGIBLE_PLAYERS');
      expect(snapshot.awards, isEmpty);
    });

    test('the period is the window the evidence described', () {
      final snapshot = snapshotOf(
        TeamOfPeriodSelector.select(
          window: windowOf(kind: TeamOfPeriodKind.monthly),
          candidates: squad,
        ),
      );
      expect(snapshot.periodType, 'monthly');
      expect(snapshot.periodKey, '2026-07');
      expect(snapshot.periodStart, identity.periodStart);
      expect(snapshot.periodEnd, identity.periodEnd);
    });
  });

  group('what the writer is sent', () {
    test('the named parameters of record_team_of_period_snapshot', () {
      final params = snapshotOf(
        TeamOfPeriodSelector.select(window: windowOf(), candidates: squad),
      ).toRpcParams();

      expect(params.keys, {
        'p_community_id',
        'p_period_type',
        'p_period_key',
        'p_period_start',
        'p_period_end',
        'p_state',
        'p_target_size',
        'p_evidence_last_changed_at',
        'p_selector_version',
        'p_awards',
      });
      expect(params['p_period_start'], '2026-07-26T20:00:00.000Z');
      expect(params['p_selector_version'], 'test-1');

      final awards = params['p_awards']! as List;
      expect(awards.first, containsPair('assigned_position', 'GK'));
      expect(
        (awards.first as Map).keys,
        {'user_id', 'assigned_position', 'rank_in_role'},
      );
    });

    test('every parameter is one the migration declares', () {
      final sql = File(
        '../supabase/migrations/0079_package_five_public_sharing.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final signature = sql.substring(
        sql.indexOf('function public.record_team_of_period_snapshot('),
        sql.indexOf('returns uuid'),
      );
      final params = snapshotOf(
        TeamOfPeriodSelector.select(window: windowOf(), candidates: squad),
      ).toRpcParams();
      for (final name in params.keys) {
        expect(signature, contains(name), reason: '$name is not declared');
      }
    });
  });

  group('there is still exactly one selection algorithm', () {
    test('the builder imports only the selector\'s own models and btge', () {
      final source =
          File('lib/features/statistics/team_of_period_snapshot.dart')
              .readAsLinesSync()
              .where((line) => line.startsWith('import '))
              .toList();
      expect(source, [
        "import 'package:btge/btge.dart';",
        "import 'team_of_period_models.dart';",
      ]);
    });

    test('the builder never sorts, filters or scores a candidate', () {
      final code = File('lib/features/statistics/team_of_period_snapshot.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final forbidden in [
        '.sort(',
        'periodFormScore',
        'participationRate',
        'eligible',
        'currentOverallRating',
        'TeamOfPeriodSelector',
      ]) {
        expect(code, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}
