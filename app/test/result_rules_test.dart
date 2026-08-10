import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/results/rating_rules.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The approved result rules and the approved rating engine, as arithmetic.
///
/// Both are stated twice — here in Dart and in migration `0035` — because a
/// client cannot be trusted to move a rating (`OP-1`) and a rule that only
/// exists behind a round trip cannot be read. What holds the two statements to
/// each other is `integration/result_test.dart`, which records a real result and
/// checks the database against the predictions made here.
void main() {
  TeamAssignment at(String id, TeamId team) => TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: Position.mid,
        basis: AssignmentBasis.primary,
      );

  /// Four players, two a side.
  List<TeamAssignment> lineup() => [
        at('a1', TeamId.a),
        at('a2', TeamId.a),
        at('b1', TeamId.b),
        at('b2', TeamId.b),
      ];

  MatchResult result({
    int teamA = 1,
    int teamB = 0,
    String? mvp = 'a1',
    List<GoalTally> goals = const [GoalTally(userId: 'a1', goals: 1)],
  }) =>
      MatchResult(
        matchId: 'm1',
        teamAScore: teamA,
        teamBScore: teamB,
        mvpUserId: mvp,
        goals: goals,
      );

  void validate({
    int teamA = 1,
    int teamB = 0,
    String? mvp = 'a1',
    List<GoalTally> goals = const [GoalTally(userId: 'a1', goals: 1)],
    Set<String>? participants,
  }) =>
      validateResultInputs(
        teamAScore: teamA,
        teamBScore: teamB,
        mvpUserId: mvp,
        goals: goals,
        participantIds: participants ?? {'a1', 'a2', 'b1', 'b2'},
      );

  Matcher refusedBecause(FailureReason reason) => throwsA(
        isA<ValidationFailure>().having((f) => f.reason, 'reason', reason),
      );

  group('the goals must add up to the score', () {
    test('a result whose goals match the score is accepted', () {
      expect(() => validate(teamA: 2, teamB: 1, goals: const [
            GoalTally(userId: 'a1', goals: 2),
            GoalTally(userId: 'b1', goals: 1),
          ]), returnsNormally);
    });

    test('too few goals is refused', () {
      expect(
        () => validate(teamA: 3, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 2),
        ]),
        refusedBecause(FailureReason.goalsDoNotMatchScore),
      );
    });

    test('too many goals is refused', () {
      expect(
        () => validate(teamA: 1, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 2),
        ]),
        refusedBecause(FailureReason.goalsDoNotMatchScore),
      );
    });

    test('a goalless match records no scorers at all', () {
      expect(
        () => validate(teamA: 0, teamB: 0, goals: const []),
        returnsNormally,
      );
    });

    test('a goalless match with a scorer is refused', () {
      expect(
        () => validate(teamA: 0, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 1),
        ]),
        refusedBecause(FailureReason.goalsDoNotMatchScore),
      );
    });

    test('one player may score several of them', () {
      expect(
        () => validate(teamA: 3, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 3),
        ]),
        returnsNormally,
      );
    });

    test('the same player twice is refused, not added up', () {
      // Two tallies for one player is the same fact recorded twice, and which
      // of them counted would be arbitrary — even when the total is right.
      expect(
        () => validate(teamA: 3, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 1),
          GoalTally(userId: 'a1', goals: 2),
        ]),
        refusedBecause(FailureReason.invalidGoals),
      );
    });
  });

  group('the numbers cannot be negative', () {
    test('a negative score is refused', () {
      expect(
        () => validate(teamA: -1, teamB: 1, goals: const []),
        refusedBecause(FailureReason.invalidScore),
      );
    });

    test('a negative goal tally is refused', () {
      expect(
        () => validate(teamA: 0, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: -1),
        ]),
        refusedBecause(FailureReason.invalidGoals),
      );
    });

    test('a tally of nothing is refused', () {
      // The tally asserts that this player scored. Nobody scoring nothing is
      // the absence of a tally.
      expect(
        () => validate(teamA: 1, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 1),
          GoalTally(userId: 'a2', goals: 0),
        ]),
        refusedBecause(FailureReason.invalidGoals),
      );
    });
  });

  group('at most one MVP, and one who played', () {
    test('a participant is accepted', () {
      expect(() => validate(mvp: 'b2'), returnsNormally);
    });

    test('somebody who did not play is refused', () {
      expect(
        () => validate(mvp: 'stranger'),
        refusedBecause(FailureReason.mvpNotParticipant),
      );
    });

    test('naming nobody is accepted', () {
      // Sprint 1: the best player is optional. A result without one is a
      // complete result, so there is nothing here to refuse.
      expect(() => validate(mvp: null), returnsNormally);
    });

    test('naming nobody does not excuse the rest', () {
      // The MVP becoming optional is one rule relaxing, not the validation
      // giving up: the goals still have to add up.
      expect(
        () => validate(mvp: null, teamA: 3, teamB: 0, goals: const [
          GoalTally(userId: 'a1', goals: 1),
        ]),
        refusedBecause(FailureReason.goalsDoNotMatchScore),
      );
    });

    test('a scorer who did not play is refused', () {
      expect(
        () => validate(teamA: 1, teamB: 0, goals: const [
          GoalTally(userId: 'stranger', goals: 1),
        ]),
        refusedBecause(FailureReason.scorerNotParticipant),
      );
    });
  });

  group('a result needs a lineup', () {
    test('no participants is refused before anything else is read', () {
      expect(
        () => validate(participants: const {}),
        refusedBecause(FailureReason.lineupRequired),
      );
    });
  });

  group('the rating engine (WIN, LOSS, GOAL, MVP)', () {
    /// Everything [userId] was credited with, added up.
    double net(List<RatingDelta> deltas, String userId) => deltas
        .where((d) => d.userId == userId)
        .fold(0.0, (sum, d) => sum + d.delta);

    test('the approved constants', () {
      expect(ratingRules.win, 0.10);
      expect(ratingRules.loss, -0.10);
      expect(ratingRules.goal, 0.02);
      expect(ratingRules.goalCap, 0.10);
      expect(ratingRules.mvp, 0.05);
    });

    test('every winner gains, every loser is charged', () {
      final deltas = ratingDeltasFor(result(), lineup());

      expect(deltaFor(deltas, 'a2', RatingChangeReason.win), 0.10);
      expect(deltaFor(deltas, 'b1', RatingChangeReason.loss), -0.10);
      expect(deltaFor(deltas, 'b2', RatingChangeReason.loss), -0.10);
    });

    test('team B winning reverses who gains', () {
      final deltas = ratingDeltasFor(
        result(
          teamA: 0,
          teamB: 1,
          mvp: 'b1',
          goals: const [GoalTally(userId: 'b1', goals: 1)],
        ),
        lineup(),
      );

      expect(deltaFor(deltas, 'b1', RatingChangeReason.win), 0.10);
      expect(deltaFor(deltas, 'a1', RatingChangeReason.loss), -0.10);
    });

    test('a draw produces neither a win nor a loss', () {
      final deltas = ratingDeltasFor(
        result(
          teamA: 1,
          teamB: 1,
          goals: const [
            GoalTally(userId: 'a1', goals: 1),
            GoalTally(userId: 'b1', goals: 1),
          ],
        ),
        lineup(),
      );

      expect(
        deltas.where((d) =>
            d.reason == RatingChangeReason.win ||
            d.reason == RatingChangeReason.loss),
        isEmpty,
      );
      // The goals and the best player still count.
      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal), 0.02);
      expect(deltaFor(deltas, 'a1', RatingChangeReason.mvp), 0.05);
    });

    test('a drawn player with neither a goal nor the MVP moves nothing', () {
      // A draw is worth 0.00, and "worth nothing" is the absence of an entry
      // rather than an entry of zero: a zero would still be a rating change
      // credited to somebody.
      final deltas = ratingDeltasFor(
        result(
          teamA: 1,
          teamB: 1,
          mvp: null,
          goals: const [
            GoalTally(userId: 'a1', goals: 1),
            GoalTally(userId: 'b1', goals: 1),
          ],
        ),
        lineup(),
      );

      expect(deltas.where((d) => d.userId == 'a2'), isEmpty);
      expect(net(deltas, 'a2'), 0.0);
      expect(net(deltas, 'b2'), 0.0);
    });

    test('a goal is worth 0.02 to whoever scored it', () {
      final deltas = ratingDeltasFor(result(), lineup());

      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal), 0.02);
      expect(deltaFor(deltas, 'a2', RatingChangeReason.goal), isNull,
          reason: 'a player who scored nothing gets no goal entry');
    });

    test('three goals by one player are one entry of 0.06', () {
      final deltas = ratingDeltasFor(
        result(teamA: 3, goals: const [GoalTally(userId: 'a1', goals: 3)]),
        lineup(),
      );

      expect(
        deltas.where((d) => d.reason == RatingChangeReason.goal),
        hasLength(1),
      );
      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal),
          closeTo(0.06, 1e-9));
    });

    test('five goals reach the cap exactly', () {
      final deltas = ratingDeltasFor(
        result(teamA: 5, goals: const [GoalTally(userId: 'a1', goals: 5)]),
        lineup(),
      );

      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal),
          closeTo(0.10, 1e-9));
    });

    test('a sixth goal is worth nothing more than the fifth', () {
      // The cap is on the total, not on each goal, so the entry stops at 0.10
      // however far the tally runs past five.
      for (final scored in const [6, 7, 12]) {
        final deltas = ratingDeltasFor(
          result(
            teamA: scored,
            goals: [GoalTally(userId: 'a1', goals: scored)],
          ),
          lineup(),
        );

        expect(
          deltaFor(deltas, 'a1', RatingChangeReason.goal),
          closeTo(0.10, 1e-9),
          reason: '$scored goals must still be worth the capped 0.10',
        );
      }
    });

    test('the cap is per player, not per match', () {
      // Two scorers each hold their own total. One being capped does not spend
      // anything the other could have had.
      final deltas = ratingDeltasFor(
        result(
          teamA: 6,
          goals: const [
            GoalTally(userId: 'a1', goals: 5),
            GoalTally(userId: 'a2', goals: 1),
          ],
        ),
        lineup(),
      );

      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal),
          closeTo(0.10, 1e-9));
      expect(deltaFor(deltas, 'a2', RatingChangeReason.goal),
          closeTo(0.02, 1e-9));
    });

    test('the best player gains 0.05, once', () {
      final deltas = ratingDeltasFor(result(), lineup());

      expect(deltas.where((d) => d.reason == RatingChangeReason.mvp),
          hasLength(1));
      expect(deltaFor(deltas, 'a1', RatingChangeReason.mvp), 0.05);
    });

    test('a result with no best player awards no MVP bonus', () {
      // "Do not award MVP" is the absence of the entry, not an entry of zero:
      // a zero would still be a rating change credited to somebody.
      final deltas = ratingDeltasFor(result(mvp: null), lineup());

      expect(deltas.where((d) => d.reason == RatingChangeReason.mvp), isEmpty);
      // Everything the match itself was worth is still there.
      expect(deltaFor(deltas, 'a1', RatingChangeReason.win), 0.10);
      expect(deltaFor(deltas, 'b1', RatingChangeReason.loss), -0.10);
      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal), 0.02);
    });

    test('one player can collect all three', () {
      // Won, scored, and was named best on the pitch: three entries, not one.
      final deltas = [
        for (final delta in ratingDeltasFor(result(), lineup()))
          if (delta.userId == 'a1') delta,
      ];

      expect(deltas.map((d) => d.reason), [
        RatingChangeReason.win,
        RatingChangeReason.goal,
        RatingChangeReason.mvp,
      ]);
      expect(
        deltas.fold(0.0, (sum, d) => sum + d.delta),
        closeTo(0.17, 1e-9),
      );
    });

    test('the losing side may still hold the best player', () {
      final deltas = ratingDeltasFor(result(mvp: 'b1'), lineup());

      expect(deltaFor(deltas, 'b1', RatingChangeReason.loss), -0.10);
      expect(deltaFor(deltas, 'b1', RatingChangeReason.mvp), 0.05);
    });

    test('the changes follow the rules handed in, not a constant', () {
      final deltas = ratingDeltasFor(
        result(),
        lineup(),
        rules: const RatingRules(
          win: 1,
          loss: -2,
          goal: 3,
          goalCap: 100,
          mvp: 4,
        ),
      );

      expect(deltaFor(deltas, 'a2', RatingChangeReason.win), 1);
      expect(deltaFor(deltas, 'b1', RatingChangeReason.loss), -2);
      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal), 3);
      expect(deltaFor(deltas, 'a1', RatingChangeReason.mvp), 4);
    });

    test('the cap follows the rules handed in too', () {
      final deltas = ratingDeltasFor(
        result(teamA: 4, goals: const [GoalTally(userId: 'a1', goals: 4)]),
        lineup(),
        rules: const RatingRules(
          win: 1,
          loss: -2,
          goal: 3,
          goalCap: 7,
          mvp: 4,
        ),
      );

      expect(deltaFor(deltas, 'a1', RatingChangeReason.goal), 7);
    });
  });

  group('the team result stays the most influential factor', () {
    test('a winner who did nothing else beats a losing top scorer with the MVP',
        () {
      // The rule the numbers exist to serve: b1 loses, scores five and is named
      // best on the pitch, and still ends below a2, who only won.
      final deltas = ratingDeltasFor(
        result(
          teamA: 6,
          teamB: 5,
          mvp: 'b1',
          goals: const [
            GoalTally(userId: 'a1', goals: 6),
            GoalTally(userId: 'b1', goals: 5),
          ],
        ),
        lineup(),
      );

      double net(String userId) => deltas
          .where((d) => d.userId == userId)
          .fold(0.0, (sum, d) => sum + d.delta);

      expect(net('a2'), closeTo(0.10, 1e-9), reason: 'a win and nothing else');
      expect(net('b1'), closeTo(0.05, 1e-9),
          reason: 'loss -0.10, goals capped at +0.10, MVP +0.05');
      expect(net('b1'), lessThan(net('a2')));
    });

    test('a loser with five goals is brought back to level, no further', () {
      final deltas = ratingDeltasFor(
        result(
          teamA: 6,
          teamB: 5,
          mvp: null,
          goals: const [
            GoalTally(userId: 'a1', goals: 6),
            GoalTally(userId: 'b1', goals: 5),
          ],
        ),
        lineup(),
      );

      expect(
        deltas
            .where((d) => d.userId == 'b1')
            .fold(0.0, (sum, d) => sum + d.delta),
        closeTo(0.0, 1e-9),
      );
    });

    test('no number of goals lifts a loser past a winner', () {
      for (final scored in const [5, 6, 20]) {
        final deltas = ratingDeltasFor(
          result(
            teamA: scored + 1,
            teamB: scored,
            mvp: 'b1',
            goals: [
              GoalTally(userId: 'a1', goals: scored + 1),
              GoalTally(userId: 'b1', goals: scored),
            ],
          ),
          lineup(),
        );

        double net(String userId) => deltas
            .where((d) => d.userId == userId)
            .fold(0.0, (sum, d) => sum + d.delta);

        expect(net('b1'), lessThan(net('a2')),
            reason: '$scored goals must not carry a loser past a winner');
      }
    });
  });

  group('a rating stays inside the approved range', () {
    test('an ordinary change is the sum of its deltas', () {
      // A win, a goal and the best player on the pitch.
      expect(applyRatingDeltas(5.0, const [0.10, 0.02, 0.05]),
          closeTo(5.17, 1e-9));
    });

    test('a rating cannot pass 10.0', () {
      expect(applyRatingDeltas(9.95, const [0.10, 0.05]), 10.0);
    });

    test('a rating cannot fall below 0.0', () {
      expect(applyRatingDeltas(0.05, const [-0.10]), 0.0);
    });

    test('each step is held, so a clamp is not undone by the next', () {
      // 10.0 absorbs the win, then the loss of 0.10 comes off the clamped
      // value rather than off an imaginary 10.10.
      expect(applyRatingDeltas(10.0, const [0.10, -0.10]), closeTo(9.9, 1e-9));
    });
  });

  group('reading the result', () {
    test('a win, a loss and a draw', () {
      expect(result(teamA: 2, teamB: 1).winner, TeamId.a);
      expect(result(teamA: 1, teamB: 2).winner, TeamId.b);
      expect(result(teamA: 1, teamB: 1).winner, isNull);
      expect(result(teamA: 1, teamB: 1).isDraw, isTrue);
    });

    test('recorded goals add the tallies up', () {
      expect(
        result(teamA: 4, goals: const [
          GoalTally(userId: 'a1', goals: 3),
          GoalTally(userId: 'a2', goals: 1),
        ]).recordedGoals,
        4,
      );
    });

    test('a player who scored nothing is credited with nothing', () {
      expect(result().goalsBy('b2'), 0);
    });

    test('the team of a player who was not in the lineup is unknown', () {
      expect(teamOf(lineup(), 'a1'), TeamId.a);
      expect(teamOf(lineup(), 'stranger'), isNull);
    });
  });
}

/// The delta recorded for [userId] under [reason], or null when there is none.
double? deltaFor(
  List<RatingDelta> deltas,
  String userId,
  RatingChangeReason reason,
) {
  for (final delta in deltas) {
    if (delta.userId == userId && delta.reason == reason) return delta.delta;
  }
  return null;
}
