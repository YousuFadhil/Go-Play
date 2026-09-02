import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_generation_settings.dart';
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
/// Most configurations below are **test** configurations chosen to isolate one
/// behaviour; they propose nothing. The approved Product Decisions live in
/// `team_generation_settings.dart`, and the group at the end exercises that
/// configuration as the product will actually use it.
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
    List<TeamAssignment> avoiding = const [],
  }) =>
      TeamRepository(adapter).generateTeams(
        forMatch ?? match,
        configuration: configuration,
        historyLookback: historyLookback,
        avoiding: avoiding,
      );

  /// Which side each player ended on, which is what "a different distribution"
  /// means: positions may move without the split changing (`KB-D6`).
  Map<String, TeamId> splitOf(List<TeamAssignment> lineup) =>
      {for (final a in lineup) a.participantId: a.team};

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
      // Engine output only, so the position and the basis are always present;
      // the null-safe reads are the type's, not a case this test provokes.
      String signatureOf(List<TeamAssignment> lineup) => ([
            for (final a in lineup)
              '${a.participantId}:${a.team.name}:${a.assignedPosition?.code}'
                  ':${a.basis?.name}',
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
        final player = declared[assignment.participantId]!;
        // The engine only ever produces registered players, so a null basis
        // (the database's GUEST) cannot appear in generated output.
        expect(assignment.basis, isNotNull);
        switch (assignment.basis!) {
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
  });

  group('regenerating', () {
    /// Six indistinguishable players, so every split ties on all five
    /// priorities and the engine genuinely has more than one answer.
    List<PlayerCoreInputs> sixAlike() => [
          for (var i = 1; i <= 6; i++) input('u$i', Position.mid),
        ];

    const banded = BtgeConfiguration(
      distributionBand: ToleranceBand(absolute: 2),
      ratingBand: ToleranceBand(absolute: 1),
      outOfPositionBand: ToleranceBand(absolute: 2),
      ageBand: ToleranceBand(absolute: 1),
      oddCountRule: OddCountRule.weakerTeamGetsExtra,
      minPlayers: 4,
      assignEmergencyGoalkeeper: false,
    );

    test('asking again for the teams on screen produces a different split',
        () async {
      final adapter = FakeTeamAdapter(roster: sixAlike());
      final first = await generate(adapter, configuration: banded);

      final second =
          await generate(adapter, configuration: banded, avoiding: first);

      expect(splitOf(second), isNot(splitOf(first)),
          reason: 'regenerate is a request for other teams, not the same ones');
      expect(second, hasLength(6),
          reason: 'a different answer, not a smaller one (BTGE-HC-3)');
    });

    test('the alternative is a function of the inputs, not a roll of a die',
        () async {
      final adapter = FakeTeamAdapter(roster: sixAlike());
      final first = await generate(adapter, configuration: banded);

      final a = await generate(adapter, configuration: banded, avoiding: first);
      final b = await generate(adapter, configuration: banded, avoiding: first);

      // `BTGE-PF-6`: the same match with the same stored lineup always
      // regenerates to the same teams.
      expect(splitOf(b), splitOf(a));
    });

    test('a lineup that is not what the engine would produce is left alone',
        () async {
      final adapter = FakeTeamAdapter(roster: sixAlike());
      final plain = await generate(adapter, configuration: banded);

      // An organizer's own arrangement: everybody on one side. The first answer
      // does not repeat it, so nothing is varied away from.
      final manual = [
        for (final a in plain)
          TeamAssignment(
            userId: a.userId,
            team: TeamId.a,
            assignedPosition: a.assignedPosition,
            basis: a.basis,
          ),
      ];

      final regenerated =
          await generate(adapter, configuration: banded, avoiding: manual);

      expect(splitOf(regenerated), splitOf(plain));
    });

    test('a search with one optimal answer returns it rather than a worse one',
        () async {
      // Distinct ratings, so priority 2 settles it outright. `BTGE-PF-4` does
      // not bend to make the button feel productive.
      final roster = [
        input('u1', Position.def, rating: 10),
        input('u2', Position.def, rating: 20),
        input('u3', Position.mid, rating: 30),
        input('u4', Position.mid, rating: 44),
      ];
      final adapter = FakeTeamAdapter(roster: roster);
      final first = await generate(adapter);

      final again = await generate(adapter, avoiding: first);

      expect(splitOf(again), splitOf(first));
    });
  });

  group('correcting who played', () {
    test('adding a player is a pass-through to the port', () async {
      final adapter = FakeTeamAdapter();

      await TeamRepository(adapter).addPlayedPlayer(
        'm1',
        'u9',
        team: TeamId.b,
        position: Position.def,
      );

      expect(adapter.addedUserId, 'u9');
      expect(adapter.addedTeam, TeamId.b);
      expect(adapter.addedPosition, Position.def);
    });

    test('removing one is too', () async {
      final adapter = FakeTeamAdapter();

      await TeamRepository(adapter).removePlayedPlayer('m1', 'u9');

      expect(adapter.removedUserId, 'u9');
    });
  });

  group('the repository driving the engine, continued', () {
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

    test('the approved configuration is the one the product will use', () async {
      // Not a test configuration: these are the values recorded in §18.1.1.
      expect(approvedTeamGeneration.minPlayers, 4, reason: 'OP-2');
      expect(approvedTeamGeneration.distributionBand.absolute, 2, reason: 'OP-3');
      expect(approvedTeamGeneration.ratingBand.absolute, 0.10, reason: 'OP-3');
      expect(approvedTeamGeneration.outOfPositionBand.absolute, 2,
          reason: 'OP-3');
      expect(approvedTeamGeneration.ageBand.absolute, 1.00, reason: 'OP-3');
      expect(approvedTeamGeneration.oddCountRule,
          OddCountRule.weakerTeamGetsExtra,
          reason: 'OP-5');
      expect(approvedTeamGeneration.diversityLastNMatches, 5, reason: 'OP-6');
      expect(approvedTeamGeneration.diversityWithin, isNull,
          reason: 'OP-6 approved no time-based window');
      expect(approvedHistoryLookback, 5,
          reason: 'the read bound follows the approved window');
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

  _minimumMatchSizeTests();
}

/// The approved minimum match size, exercised through the real product
/// configuration rather than a test one.
///
/// `OP-2` is 4 — a 2 v 2 — and it is a product rule, not an engine one: the
/// engine stays configurable, and what fixes the bound is the configuration the
/// product supplies.
void _minimumMatchSizeTests() {
  final kickOff = DateTime(2026, 8, 7, 20);
  final match = Match(
    id: 'm1',
    communityId: 'c1',
    createdBy: 'u1',
    location: 'Al Amerat Pitch',
    startAt: kickOff,
    endAt: kickOff.add(const Duration(hours: 2)),
    startingPlayers: 4,
    maxRegistration: 10,
    status: MatchStatus.open,
  );

  PlayerCoreInputs player(String id, Position primary) => PlayerCoreInputs(
        userId: id,
        fullName: 'Player $id',
        overallRating: 5 + id.hashCode % 3,
        primaryPosition: primary,
        dateOfBirth: DateTime(kickOff.year - 25, kickOff.month, kickOff.day),
      );

  Future<List<TeamAssignment>> generateUnderApproved(
    List<PlayerCoreInputs> roster,
  ) =>
      TeamRepository(FakeTeamAdapter(roster: roster)).generateTeams(
        match,
        configuration: approvedTeamGeneration,
        historyLookback: approvedHistoryLookback,
      );

  group('the approved minimum match size (OP-2 = 4)', () {
    test('three confirmed players are refused', () async {
      await expectLater(
        generateUnderApproved([
          player('u1', Position.gk),
          player('u2', Position.def),
          player('u3', Position.mid),
        ]),
        throwsA(isA<ValidationFailure>()),
        reason: 'below the minimum supported match, the product does not '
            'generate',
      );
    });

    test('four confirmed players are accepted and make 2 v 2', () async {
      final lineup = await generateUnderApproved([
        player('u1', Position.gk),
        player('u2', Position.def),
        player('u3', Position.mid),
        player('u4', Position.fwd),
      ]);

      expect(lineup, hasLength(4));
      expect(lineup.where((a) => a.team == TeamId.a), hasLength(2));
      expect(lineup.where((a) => a.team == TeamId.b), hasLength(2));
      expect({for (final a in lineup) a.userId}, {'u1', 'u2', 'u3', 'u4'},
          reason: 'every player assigned exactly once (BTGE-HC-1, -HC-2)');
    });

    test('an odd count above the minimum still follows OP-5 (BTGE-HC-4)',
        () async {
      final lineup = await generateUnderApproved([
        player('u1', Position.gk),
        player('u2', Position.def),
        player('u3', Position.def),
        player('u4', Position.mid),
        player('u5', Position.fwd),
      ]);

      final a = lineup.where((x) => x.team == TeamId.a).length;
      final b = lineup.where((x) => x.team == TeamId.b).length;
      expect({a, b}, {3, 2},
          reason: 'five players split by exactly one, never more');
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

  /// Whether the last save said it followed a generation. It is the one
  /// thing that clears a guest's chosen side (migration `0058`).
  bool? lastFromGeneration;

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
  Future<void> saveLineup(
    String matchId,
    List<TeamAssignment> lineup, {
    bool fromGeneration = false,
  }) async {
    lastMatchId = matchId;
    savedLineup = lineup;
    lastFromGeneration = fromGeneration;
  }

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) =>
      throw UnimplementedError();

  String? addedUserId;
  TeamId? addedTeam;
  Position? addedPosition;
  String? removedUserId;

  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) async {
    lastMatchId = matchId;
    addedUserId = userId;
    addedTeam = team;
    addedPosition = position;
  }

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) async {
    lastMatchId = matchId;
    removedUserId = userId;
  }
}
