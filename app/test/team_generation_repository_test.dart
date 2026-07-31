import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';

/// The repository driving the engine, with the provider out of the way.
///
/// What is asserted here is the seam, not the engine: that the confirmed
/// roster becomes the generation set, that the engine's refusals arrive in the
/// application's error language, and that the result comes back as Domain
/// Models. The engine's own rules are covered by `packages/btge/test`, and
/// nothing here re-asserts them beyond the hard constraints that prove the
/// mapping kept the output intact.
///
/// Every configuration below is a **test** configuration. `OP-2`, `OP-3`,
/// `OP-5` and `OP-6` are open Product Decisions, and none of these values
/// proposes one.
void main() {
  final kickOff = DateTime(2026, 8, 7, 20);

  Match matchAt(DateTime start) => Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u1',
        location: 'Al Amerat Pitch',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: MatchStatus.open,
      );

  final match = matchAt(kickOff);

  PlayerCoreInputs input(
    String id,
    Position primary, {
    Position? secondary,
    double rating = 50,
    int age = 25,
    bool withoutDateOfBirth = false,
  }) =>
      PlayerCoreInputs(
        userId: id,
        fullName: 'Player $id',
        overallRating: rating,
        primaryPosition: primary,
        secondaryPosition: secondary,
        dateOfBirth: withoutDateOfBirth
            ? null
            : DateTime(kickOff.year - age, kickOff.month, kickOff.day),
      );

  /// Six players in an ordinary shape: one keeper, two at the back, two in
  /// midfield, one up front.
  List<PlayerCoreInputs> sixPlayers() => [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.def),
        input('u4', Position.mid),
        input('u5', Position.mid),
        input('u6', Position.fwd),
      ];

  /// No tolerance at any priority. The engine's own documented test setting,
  /// explicitly *not* a proposed production one (`KB-C1`).
  const strict = BtgeConfiguration.strictLexicographic();

  Future<List<TeamAssignment>> generate(
    TeamAdapter adapter, {
    BtgeConfiguration configuration = strict,
    int? historyLookback,
    Match? forMatch,
  }) =>
      TeamRepository(adapter).generateTeams(
        forMatch ?? match,
        configuration: configuration,
        historyLookback: historyLookback,
      );

  group('a generation that succeeds', () {
    test('every confirmed player is assigned exactly once (BTGE-HC-1, -HC-2)',
        () async {
      final lineup = await generate(FakeTeamAdapter(roster: sixPlayers()));

      expect(lineup, hasLength(6));
      expect({for (final a in lineup) a.userId},
          {'u1', 'u2', 'u3', 'u4', 'u5', 'u6'});
    });

    test('the two sides are balanced in size (BTGE-HC-4)', () async {
      final lineup = await generate(FakeTeamAdapter(roster: sixPlayers()));

      final a = lineup.where((x) => x.team == TeamId.a).length;
      final b = lineup.where((x) => x.team == TeamId.b).length;
      expect(a, 3);
      expect(b, 3);
    });

    test('an odd count differs by exactly one, never more (BTGE-HC-4)',
        () async {
      final roster = sixPlayers()..add(input('u7', Position.mid));

      final lineup = await generate(FakeTeamAdapter(roster: roster));

      final a = lineup.where((x) => x.team == TeamId.a).length;
      final b = lineup.where((x) => x.team == TeamId.b).length;
      expect({a, b}, {4, 3});
    });

    test('no team is given two goalkeepers (BTGE-HC-6)', () async {
      final roster = sixPlayers()..add(input('u7', Position.gk));

      final lineup = await generate(FakeTeamAdapter(roster: roster));

      for (final team in TeamId.values) {
        expect(
          lineup
              .where((a) =>
                  a.team == team && a.assignedPosition == Position.gk)
              .length,
          lessThanOrEqualTo(1),
        );
      }
    });

    test('the same input generates the same lineup (BTGE-PF-6)', () async {
      String signatureOf(List<TeamAssignment> lineup) => ([
            for (final a in lineup)
              '${a.userId}:${a.team.name}:${a.assignedPosition.code}'
                  ':${a.basis.name}',
          ]..sort())
              .join('|');

      final first = await generate(FakeTeamAdapter(roster: sixPlayers()));
      final second = await generate(FakeTeamAdapter(roster: sixPlayers()));

      expect(signatureOf(first), signatureOf(second));
    });
  });

  group('the output mapped back into Domain Models (§5.1)', () {
    test('each assignment carries a team, a position and a basis', () async {
      final lineup = await generate(FakeTeamAdapter(roster: sixPlayers()));

      for (final assignment in lineup) {
        expect(TeamId.values, contains(assignment.team));
        expect(Position.values, contains(assignment.assignedPosition));
        expect(AssignmentBasis.values, contains(assignment.basis));
      }
    });

    test('the basis always agrees with what the player declared (BTGE-PT-2)',
        () async {
      // Deliberately no assertion about how many players are moved, nor about
      // whether either team gets a goalkeeper: `TS-06` and `TS-07` forbid
      // both, because an emergency goalkeeper is approved but not guaranteed
      // (`BTGE-GK-4`). What the mapping owes is that a basis and a position
      // still describe the same player after the crossing.
      final roster = [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.def, secondary: Position.mid),
        input('u4', Position.mid),
        input('u5', Position.mid),
        input('u6', Position.fwd),
      ];
      final declared = {for (final player in roster) player.userId: player};

      final lineup = await generate(FakeTeamAdapter(roster: roster));

      for (final assignment in lineup) {
        final player = declared[assignment.userId]!;
        switch (assignment.basis) {
          case AssignmentBasis.primary:
            expect(assignment.assignedPosition, player.primaryPosition);
          case AssignmentBasis.secondary:
            expect(assignment.assignedPosition, player.secondaryPosition);
          case AssignmentBasis.transition:
            expect(assignment.assignedPosition, isNot(player.primaryPosition));
            expect(
                assignment.assignedPosition, isNot(player.secondaryPosition));
        }
      }
    });

    test('a transition is reported as out of position (§5.1)', () async {
      // Nobody plays in midfield, so somebody has to be moved there.
      final roster = [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.def),
        input('u4', Position.def),
        input('u5', Position.fwd),
        input('u6', Position.fwd),
      ];

      final lineup = await generate(FakeTeamAdapter(roster: roster));

      for (final assignment in lineup) {
        expect(assignment.outOfPosition,
            assignment.basis == AssignmentBasis.transition,
            reason: 'out of position is exactly a transition, never stored');
      }
    });
  });

  group('input the engine refuses', () {
    test('too few players is a validation failure (OP-2, BTGE-PF-2)', () async {
      final adapter = FakeTeamAdapter(roster: [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.mid),
      ]);

      await expectLater(
        generate(adapter,
            configuration:
                const BtgeConfiguration.strictLexicographic(minPlayers: 4)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('the configured minimum is the caller\'s, not the engine\'s', () async {
      // The same three players are enough when the caller says they are. OP-2
      // is a Product Decision; nothing in this layer holds an opinion on it.
      final adapter = FakeTeamAdapter(roster: [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.mid),
      ]);

      expect(
        await generate(adapter,
            configuration:
                const BtgeConfiguration.strictLexicographic(minPlayers: 3)),
        hasLength(3),
      );
    });

    test('more than thirty players is refused (BTGE-PF-1, -PF-2)', () async {
      final roster = [
        for (var i = 0; i < 31; i++)
          input('u${i.toString().padLeft(2, '0')}', Position.mid),
      ];

      await expectLater(
        generate(FakeTeamAdapter(roster: roster)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a duplicate player id is refused (§4.3)', () async {
      final adapter = FakeTeamAdapter(roster: [
        input('u1', Position.gk),
        input('u1', Position.def),
        input('u3', Position.mid),
        input('u4', Position.fwd),
      ]);

      await expectLater(
        generate(adapter),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a rating the engine cannot use names the missing input (§4.3)',
        () async {
      final roster = sixPlayers()
        ..[2] = input('u3', Position.def, rating: double.nan);

      await expectLater(
        generate(FakeTeamAdapter(roster: roster)),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.missingPlayerInputs)),
      );
    });

    test('a missing date of birth stops it before the engine (§4.3)', () async {
      final roster = sixPlayers()
        ..[1] = input('u2', Position.def, withoutDateOfBirth: true);

      await expectLater(
        generate(FakeTeamAdapter(roster: roster)),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.missingPlayerInputs)),
        reason: 'the engine is never handed an invented date of birth',
      );
    });

    test('a refused generation stores nothing', () async {
      final adapter = FakeTeamAdapter(roster: [input('u1', Position.gk)]);

      await expectLater(generate(adapter), throwsA(isA<ValidationFailure>()));
      expect(adapter.savedLineup, isNull);
    });
  });

  group('the repository driving the engine', () {
    test('the generation set is the roster the port returned', () async {
      final adapter = FakeTeamAdapter(roster: sixPlayers());

      final lineup = await generate(adapter);

      expect(adapter.lastMatchId, 'm1');
      expect({for (final a in lineup) a.userId},
          {for (final p in adapter.roster) p.userId});
    });

    test('the lookback window reaches the port as given (OP-6)', () async {
      final adapter = FakeTeamAdapter(
        roster: sixPlayers(),
        played: [
          PastMatch(playedAt: DateTime(2026, 7, 31), teams: const [
            {'u1', 'u2', 'u3'},
            {'u4', 'u5', 'u6'},
          ]),
        ],
      );

      await generate(adapter,
          configuration: const BtgeConfiguration(
            distributionBand: ToleranceBand.exact(),
            ratingBand: ToleranceBand(absolute: 5),
            outOfPositionBand: ToleranceBand.exact(),
            ageBand: ToleranceBand(absolute: 5),
            oddCountRule: OddCountRule.weakerTeamGetsExtra,
            minPlayers: 2,
            diversityLastNMatches: 4,
          ),
          historyLookback: 4);

      expect(adapter.lastLimit, 4);
      expect(adapter.lastCommunityId, 'c1');
      expect(adapter.lastExcludedMatchId, 'm1');
    });

    test('an unset window reads no history and still generates (BTGE-DV-5)',
        () async {
      final adapter = FakeTeamAdapter(roster: sixPlayers());

      expect(await generate(adapter, historyLookback: null), hasLength(6));
      expect(adapter.lastLimit, isNull,
          reason: 'no history is the approved path, not an error');
    });

    test('generating stores nothing on its own', () async {
      final adapter = FakeTeamAdapter(roster: sixPlayers());

      await generate(adapter);

      expect(adapter.savedLineup, isNull,
          reason: 'the organizer may still move a player (BTGE-MO-2)');
    });

    test('the lineup it returns is what saveLineup takes', () async {
      final adapter = FakeTeamAdapter(roster: sixPlayers());
      final repository = TeamRepository(adapter);

      final lineup = await repository.generateTeams(match,
          configuration: strict, historyLookback: null);
      await repository.saveLineup('m1', lineup);

      expect(adapter.savedLineup, hasLength(6));
      expect({for (final a in adapter.savedLineup!) a.userId},
          {for (final a in lineup) a.userId});
    });

    test('age is measured against the match date, not today (§4.2)', () async {
      // The same roster generated for two different kick-offs asks the engine
      // two different questions; what is asserted is only that the repository
      // passes the match date through rather than reaching for the clock.
      final adapter = FakeTeamAdapter(roster: sixPlayers());
      final inputs = await TeamRepository(adapter)
          .fetchGenerationInputs(matchAt(DateTime(2030, 1, 1)),
              historyLookback: null);

      expect(inputs.settings.matchDate, DateTime(2030, 1, 1));
      expect(inputs.players.first.ageAt(inputs.settings.matchDate), 28,
          reason: 'a 25-year-old at the 2026 kick-off is 28 in 2030');
    });
  });
}

/// Answers from memory and records what it was handed, exactly as the fakes in
/// `repository_behaviour_test.dart` do. `fetchLineup` is left unimplemented
/// because generation never reads a stored lineup — if that changes, this
/// should break loudly rather than pass silently.
class FakeTeamAdapter implements TeamAdapter {
  FakeTeamAdapter({this.roster = const [], this.played = const []});

  final List<PlayerCoreInputs> roster;
  final List<PastMatch> played;

  String? lastMatchId;
  String? lastCommunityId;
  String? lastExcludedMatchId;
  int? lastLimit;
  List<TeamAssignment>? savedLineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
      String matchId) async {
    lastMatchId = matchId;
    return roster;
  }

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) async {
    lastCommunityId = communityId;
    lastExcludedMatchId = excludeMatchId;
    lastLimit = limit;
    return played;
  }

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) async {
    lastMatchId = matchId;
    savedLineup = lineup;
  }

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) =>
      throw UnimplementedError();
}
