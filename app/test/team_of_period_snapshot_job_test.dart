import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_snapshot_job.dart';

/// The Team of Period snapshot job, against a fake database.
///
/// The rows below are shaped exactly as `community_period_xi_closed_window`
/// and `community_period_xi_closed_evidence` return them (migration `0079`),
/// so what is exercised is the app's real mapper, the real selector and the
/// real snapshot builder — the job adds orchestration and nothing else.
void main() {
  const community = '1976fb37-6b44-49f0-84f5-3a8a68d02110';

  Map<String, dynamic> window({String key = '2026-W37', int matches = 3}) => {
        'period_type': 'weekly',
        'period_key': key,
        'period_start': '2026-09-06T20:00:00+00:00',
        'period_end': '2026-09-13T20:00:00+00:00',
        'qualifying_match_count': matches,
        'required_matches': 2,
        'evidence_last_changed_at': '2026-09-12T15:05:00+00:00',
        'team_size_observations': [5, 5],
        'position_shape_observations': [
          {
            'team': 'A',
            'team_size': 5,
            'GK': 1,
            'DEF': 2,
            'MID': 1,
            'FWD': 1,
            'unassigned': 0
          },
          {
            'team': 'B',
            'team_size': 5,
            'GK': 1,
            'DEF': 2,
            'MID': 1,
            'FWD': 1,
            'unassigned': 0
          },
        ],
        'position_shape': {
          'GK': 2,
          'DEF': 4,
          'MID': 2,
          'FWD': 2,
          'unassigned': 0
        },
      };

  Map<String, dynamic> candidate(
    String id,
    String position, {
    double form = 0.05,
    String key = '2026-W37',
    int matches = 3,
    bool eligible = true,
  }) =>
      {
        'period_type': 'weekly',
        'period_key': key,
        'period_start': '2026-09-06T20:00:00+00:00',
        'period_end': '2026-09-13T20:00:00+00:00',
        'qualifying_match_count': matches,
        'required_matches': 2,
        'matches_played': 2,
        'participation_rate': '0.6666666666666666',
        'eligible': eligible,
        'wins': 1,
        'draws': 0,
        'losses': 1,
        'goals': 1,
        'goals_per_match': 0.5,
        'mvp_count': 0,
        'win_rate': 0.5,
        'points_per_game': 1.5,
        'period_form_score': form,
        'goal_form_contribution_total': 0.02,
        'period_primary_position': position,
        'period_secondary_position': null,
        'position_appearances': {position: 2},
        'position_basis_evidence': <String, dynamic>{},
        'current_overall_rating': '5.10',
        'user_id': id,
      };

  List<Map<String, dynamic>> squad() => [
        candidate('gk-1', 'GK'),
        candidate('def-1', 'DEF', form: 0.09),
        candidate('def-2', 'DEF', form: 0.07),
        candidate('mid-1', 'MID'),
        candidate('fwd-1', 'FWD'),
      ];

  group('a dry run', () {
    test('builds the snapshot from the selector and writes nothing', () async {
      final port = _FakePort({community: (window(), squad())});

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: false);

      expect(outcomes.single.status, SnapshotStatus.planned);
      expect(outcomes.single.snapshot!.state, 'SELECTED');
      expect(outcomes.single.snapshot!.awards, isNotEmpty);
      expect(port.written, isEmpty);
      // It asks for the closed period, never the running one.
      expect(port.periodTypes, everyElement('weekly'));
    });
  });

  group('a write', () {
    test('sends exactly the snapshot the selector produced', () async {
      final port = _FakePort({community: (window(), squad())});

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly,
          selectorVersion: 'abc123',
          write: true);

      expect(outcomes.single.status, SnapshotStatus.written);
      expect(port.written.single, outcomes.single.snapshot!.toRpcParams());
      expect(port.written.single['p_period_key'], '2026-W37');
      expect(port.written.single['p_selector_version'], 'abc123');
    });

    test('an already-stored period is success: final means final', () async {
      final port = _FakePort({community: (window(), squad())},
          refuseWith: 'SNAPSHOT_ALREADY_FINAL');

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: true);

      expect(outcomes.single.status, SnapshotStatus.alreadyFinal);
      expect(outcomes.single.ok, isTrue);
    });

    test('any other refusal is a failure, reported by its token', () async {
      final port = _FakePort({community: (window(), squad())},
          refuseWith: 'PERIOD_NOT_CLOSED');

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: true);

      expect(outcomes.single.status, SnapshotStatus.failed);
      expect(outcomes.single.detail, 'PERIOD_NOT_CLOSED');
    });

    test('a period with nobody eligible is stored as that, with no seats',
        () async {
      final port = _FakePort({
        community: (
          window(),
          [
            for (final row in squad()) {...row, 'eligible': false}
          ],
        ),
      });

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: true);

      expect(outcomes.single.snapshot!.state, 'INSUFFICIENT_ELIGIBLE_PLAYERS');
      expect(port.written.single['p_awards'], isEmpty);
    });
  });

  group('what is refused before anything is written', () {
    test('evidence and window from two different periods', () async {
      final port = _FakePort({
        community: (window(), [candidate('p1', 'MID', key: '2026-W38')]),
      });

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: true);

      expect(outcomes.single.status, SnapshotStatus.failed);
      expect(port.written, isEmpty);
    });

    test('one failing community does not stop the others', () async {
      final port = _FakePort({
        'broken': (window(), [candidate('p1', 'MID', key: '2026-W38')]),
        community: (window(), squad()),
      });

      final outcomes = await TeamOfPeriodSnapshotJob(port).run(
          kind: TeamOfPeriodKind.weekly, selectorVersion: 'v', write: true);

      expect(outcomes.map((o) => o.status),
          [SnapshotStatus.failed, SnapshotStatus.written]);
      expect(port.written, hasLength(1));
    });
  });

  group('the runner and its workflow', () {
    final tool = File('tool/snapshot_team_of_period.dart').readAsStringSync();
    // Comment lines removed: the workflow's own header explains why there is
    // no schedule, and prose must not satisfy -- or fail -- a check on YAML.
    final workflow = File('../.github/workflows/team-of-period-snapshot.yml')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');

    test('the runner is a dry run unless told to write', () {
      expect(tool, contains("final write = args.contains('--write');"));
    });

    test('the runner reads only the service-role closed-period functions', () {
      expect(tool, contains("'community_period_xi_closed_window'"));
      expect(tool, contains("'community_period_xi_closed_evidence'"));
      expect(tool, contains('rpc/record_team_of_period_snapshot'));
      // Never the member-facing reads, which describe the running week.
      expect(tool, isNot(contains("'community_period_xi_evidence'")));
      expect(tool, isNot(contains("'community_period_xi_window'")));
    });

    test('the workflow is manual only: no schedule during validation', () {
      expect(workflow, contains('workflow_dispatch:'));
      expect(workflow, isNot(contains('schedule:')));
      expect(workflow, isNot(contains('cron')));
    });

    test('the workflow defaults to a dry run and writes only when chosen', () {
      expect(workflow, contains('default: dry-run'));
      expect(workflow, contains("if [ \"\$MODE\" = \"write\" ]"));
    });

    test('the workflow never touches a web build or deployment', () {
      for (final forbidden in ['flutter build', 'wrangler', 'pages deploy']) {
        expect(workflow, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}

class _FakePort implements TeamOfPeriodSnapshotPort {
  _FakePort(this.communities, {this.refuseWith});

  final Map<String, (Map<String, dynamic>, List<Map<String, dynamic>>)>
      communities;
  final String? refuseWith;

  final List<Map<String, Object?>> written = [];
  final List<String> periodTypes = [];

  @override
  Future<List<String>> activeCommunityIds() async => communities.keys.toList();

  @override
  Future<Map<String, dynamic>> closedWindow(
    String communityId,
    String periodType,
  ) async {
    periodTypes.add(periodType);
    return communities[communityId]!.$1;
  }

  @override
  Future<List<Map<String, dynamic>>> closedEvidence(
    String communityId,
    String periodType,
  ) async {
    periodTypes.add(periodType);
    return communities[communityId]!.$2;
  }

  @override
  Future<void> record(Map<String, Object?> params) async {
    if (refuseWith != null) throw SnapshotRefused(refuseWith!);
    written.add(params);
  }
}
