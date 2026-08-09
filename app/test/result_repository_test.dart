import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The result repository at the application boundary.
///
/// What is asserted is what reaches the port, because that is the whole of the
/// operation from here: the reversal of a previous result and the application of
/// the new one happen inside one database call, deliberately, so the repository
/// has exactly one thing to get right — refusing what the rules refuse, and
/// handing everything else on unchanged.
void main() {
  TeamAssignment at(String id, TeamId team) => TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: Position.mid,
        basis: AssignmentBasis.primary,
      );

  List<TeamAssignment> lineup() => [
        at('a1', TeamId.a),
        at('a2', TeamId.a),
        at('b1', TeamId.b),
        at('b2', TeamId.b),
      ];

  Future<void> record(
    FakeResultAdapter adapter, {
    int teamA = 2,
    int teamB = 1,
    String mvp = 'a1',
    List<GoalTally> goals = const [
      GoalTally(userId: 'a1', goals: 2),
      GoalTally(userId: 'b1', goals: 1),
    ],
    List<TeamAssignment>? players,
  }) =>
      ResultRepository(adapter).recordResult(
        matchId: 'm1',
        teamAScore: teamA,
        teamBScore: teamB,
        mvpUserId: mvp,
        goals: goals,
        lineup: players ?? lineup(),
      );

  group('recording a result', () {
    test('the numbers reach the port as they were given', () async {
      final adapter = FakeResultAdapter();

      await record(adapter);

      expect(adapter.lastMatchId, 'm1');
      expect(adapter.lastTeamAScore, 2);
      expect(adapter.lastTeamBScore, 1);
      expect(adapter.lastMvpUserId, 'a1');
      expect(
        {for (final tally in adapter.lastGoals!) tally.userId: tally.goals},
        {'a1': 2, 'b1': 1},
      );
    });

    test('a goalless draw is a result like any other', () async {
      final adapter = FakeResultAdapter();

      await record(adapter, teamA: 0, teamB: 0, goals: const []);

      expect(adapter.writes, 1);
      expect(adapter.lastGoals, isEmpty);
    });

    test('the lineup is not sent: the match already holds it', () async {
      // Who played is stored against the match. Sending it again would let a
      // result name a set of players the lineup does not agree with.
      final adapter = FakeResultAdapter();

      await record(adapter);

      expect(adapter.lastMatchId, isNotNull);
      expect(adapter.writes, 1);
    });
  });

  group('a refused result writes nothing', () {
    Future<void> expectRefusal(
      Future<void> Function(FakeResultAdapter) action,
      FailureReason reason,
    ) async {
      final adapter = FakeResultAdapter();

      await expectLater(
        action(adapter),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', reason)),
      );
      expect(adapter.writes, 0, reason: 'a refusal reaches no data provider');
    }

    test('goals that do not add up to the score', () async {
      await expectRefusal(
        (adapter) => record(adapter, teamA: 5),
        FailureReason.goalsDoNotMatchScore,
      );
    });

    test('a negative score', () async {
      await expectRefusal(
        (adapter) => record(adapter, teamA: -1, teamB: 0, goals: const []),
        FailureReason.invalidScore,
      );
    });

    test('a best player who did not play', () async {
      await expectRefusal(
        (adapter) => record(adapter, mvp: 'stranger'),
        FailureReason.mvpNotParticipant,
      );
    });

    test('a scorer who did not play', () async {
      await expectRefusal(
        (adapter) => record(
          adapter,
          teamA: 1,
          teamB: 0,
          goals: const [GoalTally(userId: 'stranger', goals: 1)],
        ),
        FailureReason.scorerNotParticipant,
      );
    });

    test('a match with no lineup', () async {
      await expectRefusal(
        (adapter) => record(
          adapter,
          teamA: 0,
          teamB: 0,
          goals: const [],
          players: const [],
        ),
        FailureReason.lineupRequired,
      );
    });

    test('the same scorer named twice', () async {
      await expectRefusal(
        (adapter) => record(
          adapter,
          teamA: 3,
          teamB: 0,
          goals: const [
            GoalTally(userId: 'a1', goals: 1),
            GoalTally(userId: 'a1', goals: 2),
          ],
        ),
        FailureReason.invalidGoals,
      );
    });
  });

  group('correcting a result', () {
    test('a correction takes the same path as the first recording', () async {
      // One operation, deliberately: the reversal of the previous ratings and
      // counters and the application of the new ones are one transaction below
      // this layer, so there is nothing here to sequence.
      final adapter = FakeResultAdapter(
        result: const MatchResult(
          matchId: 'm1',
          teamAScore: 1,
          teamBScore: 0,
          mvpUserId: 'a1',
          goals: [GoalTally(userId: 'a1', goals: 1)],
        ),
      );

      await record(adapter, teamA: 0, teamB: 2, mvp: 'b2', goals: const [
        GoalTally(userId: 'b1', goals: 2),
      ]);

      expect(adapter.writes, 1);
      expect(adapter.lastTeamBScore, 2);
      expect(adapter.lastMvpUserId, 'b2');
    });

    test('a correction is refused by the same rules', () async {
      final adapter = FakeResultAdapter(
        result: const MatchResult(
          matchId: 'm1',
          teamAScore: 1,
          teamBScore: 0,
          mvpUserId: 'a1',
          goals: [GoalTally(userId: 'a1', goals: 1)],
        ),
      );

      await expectLater(
        record(adapter, teamA: 4),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.writes, 0,
          reason: 'the recorded result is left exactly as it was');
    });
  });

  group('reading back', () {
    test('a match with no result reads as none', () async {
      expect(await ResultRepository(FakeResultAdapter()).fetchResult('m1'),
          isNull);
    });

    test('the audit is handed back whole, reversals and all', () async {
      // Filtering it down to what is currently in effect would be answering a
      // question the audit exists to leave open.
      final adapter = FakeResultAdapter(history: [
        change('h1', RatingChangeReason.win, 0.10, 5.0, 5.1),
        change('h2', RatingChangeReason.reversal, -0.10, 5.1, 5.0,
            reverses: 'h1'),
      ]);

      final history =
          await ResultRepository(adapter).fetchRatingHistory('m1');

      expect(history, hasLength(2));
      expect(history.last.isReversal, isTrue);
      expect(history.last.reversesId, 'h1');
    });

    test('a player who has finished no match has counters of zero', () async {
      final statistics =
          await ResultRepository(FakeResultAdapter()).fetchStatistics('a1');

      expect(statistics.matchesPlayed, 0);
      expect(statistics.wins, 0);
      expect(statistics.currentRating, 5.0,
          reason: 'the rating is the profile default, not a counter');
    });
  });
}

RatingChange change(
  String id,
  RatingChangeReason reason,
  double delta,
  double before,
  double after, {
  String? reverses,
}) =>
    RatingChange(
      id: id,
      userId: 'a1',
      matchId: 'm1',
      reason: reason,
      delta: delta,
      ratingBefore: before,
      ratingAfter: after,
      recordedAt: DateTime(2026, 8, 1),
      reversesId: reverses,
    );

/// Answers from memory and records what it was handed, as the fakes in
/// `repository_behaviour_test.dart` do.
class FakeResultAdapter implements ResultAdapter {
  FakeResultAdapter({
    this.result,
    this.history = const [],
    this.statistics,
  });

  final MatchResult? result;
  final List<RatingChange> history;
  final PlayerStatistics? statistics;

  int writes = 0;
  String? lastMatchId;
  int? lastTeamAScore;
  int? lastTeamBScore;
  String? lastMvpUserId;
  List<GoalTally>? lastGoals;

  @override
  Future<MatchResult?> fetchResult(String matchId) async => result;

  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) async {
    writes++;
    lastMatchId = matchId;
    lastTeamAScore = teamAScore;
    lastTeamBScore = teamBScore;
    lastMvpUserId = mvpUserId;
    lastGoals = goals;
  }

  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) async =>
      history;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async =>
      statistics ?? PlayerStatistics.none(userId, 5.0);
}
