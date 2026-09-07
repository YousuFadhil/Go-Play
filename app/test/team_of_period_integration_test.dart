import 'dart:io';

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/team_of_period_mapper.dart';

/// Wiring migration `0070`'s two read models into the Statistics architecture.
///
/// Three things are checked and they are deliberately different in kind:
///
///   * **The mapping**, row by row, because a column name and a model field are
///     asserted against each other here and nowhere else (OP-3).
///   * **What the adapter asks for**, by reading its source — the same choice
///     `product_analytics_test.dart` makes, and for the same reason: a fake
///     `SupabaseClient` would only prove that a mock behaves the way the mock
///     was written, while the RPC name and the parameter names are in the text.
///   * **What the repository composes**, through a fake port, because the join
///     between two reads and a pure selector is product reasoning rather than
///     provider behaviour.
///
/// The selector's own 52 tests are not repeated. What is checked here is that
/// it is reached with the right evidence.
void main() {
  Map<String, dynamic> shapeJson({
    String team = 'A',
    int gk = 1,
    int def = 2,
    int mid = 1,
    int fwd = 1,
    int unassigned = 0,
  }) =>
      {
        'team': team,
        'team_size': gk + def + mid + fwd + unassigned,
        'GK': gk,
        'DEF': def,
        'MID': mid,
        'FWD': fwd,
        'unassigned': unassigned,
      };

  Map<String, dynamic> windowRow({
    String periodType = 'weekly',
    Object? evidenceChanged = '2026-08-01T15:30:00+00:00',
    List<Object?> sizes = const [5, 5, 6],
    List<Object?>? shapes,
  }) =>
      {
        'period_type': periodType,
        'period_key': '2026-W31',
        'period_start': '2026-07-26T20:00:00+00:00',
        'period_end': '2026-08-02T20:00:00+00:00',
        'qualifying_match_count': 3,
        'required_matches': 1,
        'evidence_last_changed_at': evidenceChanged,
        'team_size_observations': sizes,
        'position_shape_observations': shapes ?? [shapeJson()],
      };

  Map<String, dynamic> candidateRow({
    String userId = 'u1',
    String primary = 'MID',
    Object? secondary,
    Object? participation = 0.75,
    Object? formScore = '0.1200000000000000',
    Object? rating = '6.4',
    bool eligible = true,
    int matches = 3,
  }) =>
      {
        'period_type': 'weekly',
        'period_key': '2026-W31',
        'period_start': '2026-07-26T20:00:00+00:00',
        'period_end': '2026-08-02T20:00:00+00:00',
        'qualifying_match_count': 3,
        'required_matches': 1,
        'user_id': userId,
        'eligible': eligible,
        'matches_played': matches,
        'participation_rate': participation,
        'wins': 2,
        'draws': 0,
        'losses': 1,
        'goals': 4,
        'goals_per_match': '1.3333333333333333',
        'mvp_count': 1,
        'win_rate': '0.6666666666666667',
        'points_per_game': 2,
        'period_form_score': formScore,
        'goal_form_contribution_total': '0.08',
        'period_primary_position': primary,
        'period_secondary_position': secondary,
        'current_overall_rating': rating,
      };

  group('the period kind reaches the database in its own vocabulary', () {
    test('weekly and monthly are the two the function accepts', () {
      expect(teamOfPeriodKindToDb(TeamOfPeriodKind.weekly), 'weekly');
      expect(teamOfPeriodKindToDb(TeamOfPeriodKind.monthly), 'monthly');
    });

    test('the same two are read back', () {
      expect(teamOfPeriodKindFromDb('weekly'), TeamOfPeriodKind.weekly);
      expect(teamOfPeriodKindFromDb('monthly'), TeamOfPeriodKind.monthly);
    });

    test('anything else is the schema disagreeing with this build', () {
      // `overall` is refused by `0070` itself, so seeing it here would mean the
      // contract had moved underneath the app.
      expect(() => teamOfPeriodKindFromDb('overall'),
          throwsA(isA<InfrastructureFailure>()));
      expect(() => teamOfPeriodKindFromDb(null),
          throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('the window row', () {
    test('maps every field the read model returns', () {
      final window = teamOfPeriodWindowFromRow(windowRow());

      expect(window.kind, TeamOfPeriodKind.weekly);
      expect(window.periodKey, '2026-W31');
      expect(window.periodStart, DateTime.utc(2026, 7, 26, 20));
      expect(window.periodEnd, DateTime.utc(2026, 8, 2, 20));
      expect(window.qualifyingMatchCount, 3);
      expect(window.requiredMatches, 1);
      expect(window.evidenceLastChangedAt, DateTime.utc(2026, 8, 1, 15, 30));
      expect(window.teamSizeObservations, [5, 5, 6]);
    });

    test('a monthly window is read as monthly', () {
      expect(
        teamOfPeriodWindowFromRow(windowRow(periodType: 'monthly')).kind,
        TeamOfPeriodKind.monthly,
      );
    });

    test('the period boundaries are read, never recomputed', () {
      // A second derivation in Dart would be a second implementation of a
      // frozen Asia/Muscat rule, free to disagree at exactly the week edges
      // that are hardest to test. The instants arrive and are kept.
      final source = File(
        'lib/infrastructure/supabase/mappers/team_of_period_mapper.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('DateTime.now')));
      expect(source, isNot(contains('subtract')));
      expect(source, isNot(contains('Duration(')));
    });

    test('empty arrays are empty, not absent', () {
      // What an empty period returns: `\'{}\'::int[]` and `\'[]\'::jsonb`.
      final window = teamOfPeriodWindowFromRow(
        windowRow(sizes: const [], shapes: const []),
      );

      expect(window.teamSizeObservations, isEmpty);
      expect(window.positionShapeObservations, isEmpty);
    });

    test('a per-side shape maps by 0070 own keys', () {
      final window = teamOfPeriodWindowFromRow(windowRow(shapes: [
        shapeJson(gk: 1, def: 3, mid: 2, fwd: 1),
        shapeJson(team: 'B', gk: 0, def: 2, mid: 2, fwd: 1, unassigned: 2),
      ]));

      final first = window.positionShapeObservations.first;
      expect(first.teamSize, 7);
      expect(first.gk, 1);
      expect(first.def, 3);
      expect(first.mid, 2);
      expect(first.fwd, 1);
      expect(first.unassigned, 0);

      final second = window.positionShapeObservations.last;
      expect(second.teamSize, 7);
      expect(second.gk, 0);
      expect(second.unassigned, 2);
      expect(second.known, 5, reason: 'an unplaced guest is size, not shape');
    });

    test('a null evidence timestamp is the answer, not a gap', () {
      // A period with no qualifying evidence has no moment at which that
      // evidence last changed.
      final window =
          teamOfPeriodWindowFromRow(windowRow(evidenceChanged: null));

      expect(window.evidenceLastChangedAt, isNull);
    });

    test('a malformed array is refused rather than emptied', () {
      expect(
        () => teamOfPeriodWindowFromRow(windowRow(sizes: const ['five'])),
        throwsA(isA<InfrastructureFailure>()),
      );
    });
  });

  group('a candidate row', () {
    test('maps every field the award reads', () {
      final candidate = teamOfPeriodCandidateFromRow(candidateRow());

      expect(candidate.userId, 'u1');
      expect(candidate.eligible, isTrue);
      expect(candidate.matchesPlayed, 3);
      expect(candidate.participationRate, closeTo(0.75, 1e-9));
      expect(candidate.wins, 2);
      expect(candidate.draws, 0);
      expect(candidate.losses, 1);
      expect(candidate.goals, 4);
      expect(candidate.goalsPerMatch, closeTo(1.3333333333, 1e-9));
      expect(candidate.mvpCount, 1);
      expect(candidate.winRate, closeTo(0.6666666666, 1e-9));
      expect(candidate.pointsPerGame, closeTo(2, 1e-9));
      expect(candidate.periodFormScore, closeTo(0.12, 1e-9));
      expect(candidate.goalFormContributionTotal, closeTo(0.08, 1e-9));
      expect(candidate.currentOverallRating, closeTo(6.4, 1e-9));
    });

    test('a numeric arrives as a number or as its text form', () {
      // `numeric` reaches the client either way depending on the transport --
      // `overall_rating` was observed arriving as the string "5.15" -- so both
      // are read by one convention rather than cast at each site.
      final asText = teamOfPeriodCandidateFromRow(
          candidateRow(participation: '0.5', formScore: '-0.1'));
      final asNumber = teamOfPeriodCandidateFromRow(
          candidateRow(participation: 0.5, formScore: -0.1));

      expect(asText.participationRate, closeTo(0.5, 1e-9));
      expect(asText.periodFormScore, closeTo(-0.1, 1e-9));
      expect(asNumber.participationRate, asText.participationRate);
      expect(asNumber.periodFormScore, asText.periodFormScore);
    });

    test('all four positions map', () {
      for (final (code, position) in [
        ('GK', Position.gk),
        ('DEF', Position.def),
        ('MID', Position.mid),
        ('FWD', Position.fwd),
      ]) {
        expect(
          teamOfPeriodCandidateFromRow(candidateRow(primary: code))
              .periodPrimaryPosition,
          position,
        );
      }
    });

    test('a null secondary stays null', () {
      // It exists only when the player actually played a second position, so
      // an absence is the database saying there was none.
      expect(
        teamOfPeriodCandidateFromRow(candidateRow()).periodSecondaryPosition,
        isNull,
      );
      expect(
        teamOfPeriodCandidateFromRow(candidateRow(secondary: 'DEF'))
            .periodSecondaryPosition,
        Position.def,
      );
    });

    test('the period identity is read from the row itself', () {
      final candidate = teamOfPeriodCandidateFromRow(candidateRow());

      expect(candidate.periodIdentity.kind, TeamOfPeriodKind.weekly);
      expect(candidate.periodIdentity.periodKey, '2026-W31');
      expect(candidate.periodIdentity.qualifyingMatchCount, 3);
      expect(candidate.periodIdentity.requiredMatches, 1);
    });

    test('a malformed numeric fails instead of becoming zero', () {
      // A participation rate that quietly became zero would make an eligible
      // player rank last rather than fail visibly.
      expect(
        () => teamOfPeriodCandidateFromRow(candidateRow(participation: 'n/a')),
        throwsA(isA<InfrastructureFailure>()),
      );
      expect(
        () => teamOfPeriodCandidateFromRow(candidateRow(participation: null)),
        throwsA(isA<InfrastructureFailure>()),
      );
    });

    test('a missing or unknown primary position is refused', () {
      // `0051` makes a position a CHECK constraint for any lineup row naming a
      // user, so an absent Primary is the schema disagreeing with this build.
      // Nothing is invented.
      expect(
        () => teamOfPeriodCandidateFromRow(candidateRow(primary: 'STRIKER')),
        throwsA(isA<InfrastructureFailure>()),
      );
      final row = candidateRow()..['period_primary_position'] = null;
      expect(() => teamOfPeriodCandidateFromRow(row), throwsA(anything));
    });

    test('no profile position is read', () {
      final source = File(
        'lib/infrastructure/supabase/mappers/team_of_period_mapper.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("'primary_position'")));
      expect(source, isNot(contains("'secondary_position'")));
    });
  });

  group('the adapter asks for the right thing', () {
    // A static review of the adapter's source, as `product_analytics_test.dart`
    // does: what matters is the RPC name and the parameter names, and both are
    // in the text.
    final source = File(
      'lib/infrastructure/supabase/supabase_statistics_adapter.dart',
    ).readAsStringSync();

    test('the window comes from community_period_xi_window', () {
      expect(source, contains("'community_period_xi_window'"));
    });

    test('the candidates come from community_period_xi_evidence', () {
      expect(source, contains("'community_period_xi_evidence'"));
    });

    /// Only the two Team of Period reads. The rest of this class legitimately
    /// sends `p_period_key` -- that is `community_statistics_recency`, which
    /// asks about the running period and has to name it.
    final teamOfPeriod = source.substring(source.indexOf('fetchTeamOfPeriodWindow'));

    test('both send the community and the period type, and nothing else', () {
      expect(teamOfPeriod, contains("'p_community_id': communityId"));
      expect(
        teamOfPeriod,
        contains("'p_period_type': teamOfPeriodKindToDb(kind)"),
      );
      // No timestamp and no key: the database resolves which period this is
      // and refuses to be handed one.
      expect(teamOfPeriod, isNot(contains('p_period_key')));
      expect(teamOfPeriod, isNot(contains('p_period_start')));
      expect(teamOfPeriod, isNot(contains('p_now')));
      expect(
        RegExp("'p_period_type'").allMatches(teamOfPeriod).length,
        2,
        reason: 'one per read path',
      );
    });

    test('both go through the failure mapper like every other adapter', () {
      expect(source, contains("operation: 'community_period_xi_window'"));
      expect(source, contains("operation: 'community_period_xi_evidence'"));
      expect(source, isNot(contains('PostgrestException')));
    });

    test('the running-period vocabulary is not reused for the award', () {
      // `StatisticsPeriodWindow` answers "which bucket is current"; the award
      // is always about the last period that finished.
      final window = source.substring(
        source.indexOf('fetchTeamOfPeriodWindow'),
        source.indexOf('fetchTeamOfPeriodCandidates'),
      );
      expect(window, isNot(contains('StatisticsPeriodWindow')));
    });
  });

  group('the repository composes the two reads into one award', () {
    TeamOfPeriodWindow windowOf({
      int matches = 3,
      String key = '2026-W31',
      int required = 1,
    }) =>
        teamOfPeriodWindowFromRow({
          ...windowRow(),
          'period_key': key,
          'qualifying_match_count': matches,
          'required_matches': required,
        });

    TeamOfPeriodCandidate candidateOf({
      String id = 'u1',
      String primary = 'MID',
      bool eligible = true,
      Object? formScore = '0.12',
      Object? rating = '6.4',
      String key = '2026-W31',
      int matches = 3,
    }) =>
        teamOfPeriodCandidateFromRow({
          ...candidateRow(
            userId: id,
            primary: primary,
            eligible: eligible,
            formScore: formScore,
            rating: rating,
          ),
          'period_key': key,
          'qualifying_match_count': matches,
        });

    test('it reads both and hands them to the selector', () async {
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(),
        candidates: [
          candidateOf(id: 'gk1', primary: 'GK', formScore: '0.30'),
          candidateOf(id: 'd1', primary: 'DEF', formScore: '0.20'),
          candidateOf(id: 'm1', primary: 'MID', formScore: '0.10'),
        ],
      );

      final team = await StatisticsRepository(adapter)
          .fetchTeamOfPeriod('c1', TeamOfPeriodKind.monthly);

      expect(adapter.windowCalls, [('c1', TeamOfPeriodKind.monthly)]);
      expect(adapter.candidateCalls, [('c1', TeamOfPeriodKind.monthly)]);
      expect(team.state, TeamOfPeriodState.selected);
      expect(team.targetSize, 5, reason: 'the median of 5, 5 and 6');
      expect([for (final e in team.selected) e.userId], ['gk1', 'd1', 'm1']);
    });

    test('a period nobody played propagates as its own state', () async {
      final adapter = _FakeStatisticsAdapter(
        window: teamOfPeriodWindowFromRow({
          ...windowRow(sizes: const [], shapes: const []),
          'qualifying_match_count': 0,
          'required_matches': 0,
        }),
        candidates: const [],
      );

      final team = await StatisticsRepository(adapter)
          .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly);

      expect(team.state, TeamOfPeriodState.noQualifyingMatches);
      expect(team.selected, isEmpty);
      expect(team.periodKey, '2026-W31');
    });

    test('matches with nobody eligible propagate as the other state', () async {
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(),
        candidates: [
          candidateOf(id: 'u1', eligible: false),
          candidateOf(id: 'u2', eligible: false),
        ],
      );

      final team = await StatisticsRepository(adapter)
          .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly);

      expect(team.state, TeamOfPeriodState.insufficientEligiblePlayers);
      expect(team.selected, isEmpty);
      // The carry-over: the period still had a shape, and it is reported.
      expect(team.targetSize, 5);
      expect(
        team.initialSlotCounts.values.reduce((a, b) => a + b),
        team.targetSize,
      );
    });

    test('a rating that moves cannot move the awarded team', () async {
      Future<List<String>> award(double Function(String) rating) async {
        final adapter = _FakeStatisticsAdapter(
          window: windowOf(),
          candidates: [
            for (final id in ['a', 'b', 'c'])
              candidateOf(
                id: id,
                primary: 'MID',
                formScore: '0.10',
                rating: rating(id),
              ),
          ],
        );
        final team = await StatisticsRepository(adapter)
            .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly);
        return [for (final e in team.selected) e.userId];
      }

      expect(await award((id) => 9.9), await award((id) => 1));
    });

    test('two reads describing different periods are refused', () async {
      // A window resolved at 23:59:59 on Sunday and candidates resolved a
      // moment later describe different weeks. The team assembled from them
      // would be a plausible answer to no question at all.
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(key: '2026-W31'),
        candidates: [candidateOf(id: 'u1', key: '2026-W32')],
      );

      expect(
        () => StatisticsRepository(adapter)
            .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly),
        throwsStateError,
      );
    });

    test('a qualifying count that moved between the reads is refused', () async {
      // Same week, and still not one snapshot: a historical match entered
      // between the two calls changes the denominator every participation rate
      // on those candidate rows was taken over.
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(matches: 3),
        candidates: [candidateOf(id: 'u1', matches: 4)],
      );

      expect(
        () => StatisticsRepository(adapter)
            .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly),
        throwsStateError,
      );
    });

    test('no candidate rows is not an inconsistency', () async {
      // There is nothing to check the window against, and that is a legitimate
      // period rather than a contract failure.
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(),
        candidates: const [],
      );

      final team = await StatisticsRepository(adapter)
          .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly);

      expect(team.state, TeamOfPeriodState.insufficientEligiblePlayers);
    });

    test('a provider failure is not swallowed', () async {
      final adapter = _FakeStatisticsAdapter(
        window: windowOf(),
        candidates: const [],
        candidateFailure: const AuthorizationFailure(),
      );

      expect(
        () => StatisticsRepository(adapter)
            .fetchTeamOfPeriod('c1', TeamOfPeriodKind.weekly),
        throwsA(isA<AuthorizationFailure>()),
      );
    });
  });
}

/// Answers from memory and records what it was asked, as the statistics fakes
/// elsewhere in this suite do. Only the two Team of Period reads are
/// implemented; nothing here reaches the rest of the port.
class _FakeStatisticsAdapter implements StatisticsAdapter {
  _FakeStatisticsAdapter({
    required this.window,
    required this.candidates,
    this.candidateFailure,
  });

  final TeamOfPeriodWindow window;
  final List<TeamOfPeriodCandidate> candidates;
  final Failure? candidateFailure;

  final List<(String, TeamOfPeriodKind)> windowCalls = [];
  final List<(String, TeamOfPeriodKind)> candidateCalls = [];

  @override
  Future<TeamOfPeriodWindow> fetchTeamOfPeriodWindow(
    String communityId,
    TeamOfPeriodKind kind,
  ) async {
    windowCalls.add((communityId, kind));
    return window;
  }

  @override
  Future<List<TeamOfPeriodCandidate>> fetchTeamOfPeriodCandidates(
    String communityId,
    TeamOfPeriodKind kind,
  ) async {
    candidateCalls.add((communityId, kind));
    if (candidateFailure != null) throw candidateFailure!;
    return candidates;
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('no dashboard read here');

  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('no match count here');

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) =>
      throw UnimplementedError('no roster here');

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('no recency here');

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('no player totals here');
}
