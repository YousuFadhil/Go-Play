import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';

/// Manual Override at the application boundary (§13).
///
/// Three operations and what each one is allowed to touch. `BTGE-MO-2` is what
/// makes them possible at all — after generation the organizer may move or swap
/// a player **without rerunning the engine** — and `BTGE-MO-3` is what they
/// must not do: no re-optimisation, no compensating change, no refusal because
/// the result got worse.
///
/// What is asserted is the lineup handed to the port, because that is the whole
/// of the operation: the engine is never consulted, and no metric is computed.
void main() {
  TeamAssignment at(
    String id,
    TeamId team,
    Position position, {
    AssignmentBasis basis = AssignmentBasis.primary,
  }) =>
      TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: position,
        basis: basis,
      );

  /// Four players, two a side.
  List<TeamAssignment> lineup() => [
        at('u1', TeamId.a, Position.gk),
        at('u2', TeamId.a, Position.def),
        at('u3', TeamId.b, Position.mid),
        at('u4', TeamId.b, Position.fwd),
      ];

  PlayerCoreInputs profile(
    String id,
    Position primary, {
    Position? secondary,
  }) =>
      PlayerCoreInputs(
        userId: id,
        fullName: 'Player $id',
        overallRating: 6,
        primaryPosition: primary,
        secondaryPosition: secondary,
        dateOfBirth: DateTime(1995, 4, 17),
      );

  TeamAssignment saved(FakeTeamAdapter adapter, String userId) =>
      adapter.savedLineup!.singleWhere((a) => a.userId == userId);

  group('move a player (BTGE-MO-2)', () {
    test('A to B', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u2');

      expect(saved(adapter, 'u2').team, TeamId.b);
    });

    test('B to A', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u3');

      expect(saved(adapter, 'u3').team, TeamId.a);
    });

    test('the player keeps the position they were playing', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u2');

      final moved = saved(adapter, 'u2');
      expect(moved.assignedPosition, Position.def);
      expect(moved.basis, AssignmentBasis.primary);
    });

    test('everybody is still there, exactly once (BTGE-HC-1, -HC-2)', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u2');

      expect(adapter.savedLineup, hasLength(4));
      expect([for (final a in adapter.savedLineup!) a.userId],
          ['u1', 'u2', 'u3', 'u4']);
    });

    test('nobody else is touched (BTGE-MO-3)', () async {
      // No rebalancing, and nobody moved back to make the sides even again.
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u2');

      expect(saved(adapter, 'u1').team, TeamId.a);
      expect(saved(adapter, 'u3').team, TeamId.b);
      expect(saved(adapter, 'u4').team, TeamId.b);
      expect(adapter.savedLineup!.where((a) => a.team == TeamId.a),
          hasLength(1),
          reason: 'three against one is the organizer\'s to make');
    });

    test('a player who is not in the lineup is refused', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await expectLater(
        TeamRepository(adapter).movePlayer('m1', 'u9'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.savedLineup, isNull, reason: 'a refusal writes nothing');
    });

    test('a write that fails leaves the stored lineup as it was', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        saveFailure: const InfrastructureFailure(),
      );

      await expectLater(
        TeamRepository(adapter).movePlayer('m1', 'u2'),
        throwsA(isA<InfrastructureFailure>()),
      );
      expect(await adapter.fetchLineup('m1'), hasLength(4));
      expect((await adapter.fetchLineup('m1')).single1('u2').team, TeamId.a,
          reason: 'the replacement is one transaction: all of it or none');
    });

    test('a refused write reaches the caller as it was raised', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        saveFailure: const AuthorizationFailure(),
      );

      await expectLater(
        TeamRepository(adapter).movePlayer('m1', 'u2'),
        throwsA(isA<AuthorizationFailure>()),
        reason: 'the database is what authorizes, and it said no',
      );
    });
  });

  group('swap two players (BTGE-MO-2)', () {
    test('they exchange sides', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).swapPlayers('m1', 'u2', 'u3');

      expect(saved(adapter, 'u2').team, TeamId.b);
      expect(saved(adapter, 'u3').team, TeamId.a);
    });

    test('the order they are named in does not matter', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).swapPlayers('m1', 'u3', 'u2');

      expect(saved(adapter, 'u2').team, TeamId.b);
      expect(saved(adapter, 'u3').team, TeamId.a);
    });

    test('each keeps their own position', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).swapPlayers('m1', 'u2', 'u3');

      expect(saved(adapter, 'u2').assignedPosition, Position.def);
      expect(saved(adapter, 'u3').assignedPosition, Position.mid);
    });

    test('both are still there, exactly once', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).swapPlayers('m1', 'u2', 'u3');

      expect(adapter.savedLineup, hasLength(4));
      expect({for (final a in adapter.savedLineup!) a.userId},
          {'u1', 'u2', 'u3', 'u4'});
      expect(adapter.savedLineup!.where((a) => a.team == TeamId.a),
          hasLength(2),
          reason: 'a swap leaves the sides the size they were');
    });

    test('two players on the same team is not a swap', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await expectLater(
        TeamRepository(adapter).swapPlayers('m1', 'u1', 'u2'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.savedLineup, isNull);
    });

    test('a player cannot be swapped with themselves', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await expectLater(
        TeamRepository(adapter).swapPlayers('m1', 'u2', 'u2'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.savedLineup, isNull);
    });

    test('a player who is not in the lineup is refused', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await expectLater(
        TeamRepository(adapter).swapPlayers('m1', 'u2', 'u9'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.savedLineup, isNull);
    });

    test('a write that fails leaves the stored lineup as it was', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        saveFailure: const InfrastructureFailure(),
      );

      await expectLater(
        TeamRepository(adapter).swapPlayers('m1', 'u2', 'u3'),
        throwsA(isA<InfrastructureFailure>()),
      );
      final stored = await adapter.fetchLineup('m1');
      expect(stored.single1('u2').team, TeamId.a);
      expect(stored.single1('u3').team, TeamId.b);
    });
  });

  group('change an assigned position', () {
    test('the position of this match changes', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      expect(saved(adapter, 'u2').assignedPosition, Position.fwd);
    });

    test('the team is not touched', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      expect(saved(adapter, 'u2').team, TeamId.a);
    });

    test('the profile behind it is left alone', () async {
      // §7: the lineup records where they played. What the player declared —
      // and therefore every input a later generation reads (§4.1) — is theirs.
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def, secondary: Position.mid)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      final stored = adapter.roster.single;
      expect(stored.primaryPosition, Position.def);
      expect(stored.secondaryPosition, Position.mid);
      expect(stored.overallRating, 6);
      expect(adapter.rosterWrites, 0,
          reason: 'a lineup edit writes no profile');
    });

    test('their own position is recorded as primary (§5.1)', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def, secondary: Position.mid)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.def);

      expect(saved(adapter, 'u2').basis, AssignmentBasis.primary);
      expect(saved(adapter, 'u2').outOfPosition, isFalse);
    });

    test('their declared second position is not out of position (BTGE-PT-2)',
        () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def, secondary: Position.mid)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.mid);

      expect(saved(adapter, 'u2').basis, AssignmentBasis.secondary);
      expect(saved(adapter, 'u2').outOfPosition, isFalse);
    });

    test('anywhere else is a transition, and says so (§5.1)', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def, secondary: Position.mid)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      expect(saved(adapter, 'u2').basis, AssignmentBasis.transition);
      expect(saved(adapter, 'u2').outOfPosition, isTrue,
          reason: 'the marker on screen must describe where they now play');
    });

    test('a player whose profile cannot be read keeps the basis they had',
        () async {
      // Somebody who left the match after the lineup was stored. Nothing better
      // is known about them, and a basis is not something to invent.
      final adapter = FakeTeamAdapter(
        lineup: [
          at('u1', TeamId.a, Position.gk, basis: AssignmentBasis.secondary),
        ],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u1', Position.fwd);

      expect(saved(adapter, 'u1').basis, AssignmentBasis.secondary);
    });

    test('nobody else in the lineup is touched', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      expect(adapter.savedLineup, hasLength(4));
      expect(saved(adapter, 'u1').assignedPosition, Position.gk);
      expect(saved(adapter, 'u3').assignedPosition, Position.mid);
      expect(saved(adapter, 'u4').assignedPosition, Position.fwd);
    });

    test('a player who is not in the lineup is refused', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await expectLater(
        TeamRepository(adapter)
            .changeAssignedPosition('m1', 'u9', Position.fwd),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.savedLineup, isNull);
    });

    test('a write that fails leaves the stored lineup as it was', () async {
      final adapter = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def)],
        saveFailure: const InfrastructureFailure(),
      );

      await expectLater(
        TeamRepository(adapter)
            .changeAssignedPosition('m1', 'u2', Position.fwd),
        throwsA(isA<InfrastructureFailure>()),
      );
      expect(
          (await adapter.fetchLineup('m1')).single1('u2').assignedPosition,
          Position.def);
    });
  });

  group('what every edit writes', () {
    test('the whole lineup, so a stale row cannot survive it', () async {
      final adapter = FakeTeamAdapter(lineup: lineup());

      await TeamRepository(adapter).movePlayer('m1', 'u2');

      expect(adapter.savedLineup, hasLength(4),
          reason: 'the port replaces a lineup; it does not patch one');
      expect(adapter.lastMatchId, 'm1');
    });

    test('the stored lineup, not one the caller supplied', () async {
      // The organizer's screen may be older than the database. What is edited
      // is what is stored (`BTGE-MO-5`).
      final adapter = FakeTeamAdapter(lineup: lineup());
      await TeamRepository(adapter).movePlayer('m1', 'u2');

      expect(adapter.lineupReads, 1,
          reason: 'the operation reads before it writes');
    });

    test('the engine is never consulted', () async {
      final moved = FakeTeamAdapter(lineup: lineup());
      final swapped = FakeTeamAdapter(lineup: lineup());
      final positioned = FakeTeamAdapter(
        lineup: lineup(),
        roster: [profile('u2', Position.def)],
      );

      await TeamRepository(moved).movePlayer('m1', 'u2');
      await TeamRepository(swapped).swapPlayers('m1', 'u2', 'u3');
      await TeamRepository(positioned)
          .changeAssignedPosition('m1', 'u2', Position.fwd);

      for (final adapter in [moved, swapped, positioned]) {
        expect(adapter.historyReads, 0,
            reason: 'no generation, so no Auxiliary Data and no engine run');
      }
    });
  });
}

extension on List<TeamAssignment> {
  TeamAssignment single1(String userId) =>
      singleWhere((a) => a.userId == userId);
}

/// Answers from memory and records what it was handed, as the fakes in
/// `repository_behaviour_test.dart` do.
///
/// [saveFailure] stands in for the database refusing the replacement. Because
/// migration `0020` makes that replacement one transaction, a refusal leaves
/// the stored lineup untouched — which is what this fake reproduces by failing
/// before it changes anything.
class FakeTeamAdapter implements TeamAdapter {
  FakeTeamAdapter({
    List<TeamAssignment> lineup = const [],
    this.roster = const [],
    this.saveFailure,
  }) : _lineup = [...lineup];

  final List<PlayerCoreInputs> roster;
  final Failure? saveFailure;

  List<TeamAssignment> _lineup;

  int lineupReads = 0;
  int historyReads = 0;
  int rosterWrites = 0;
  String? lastMatchId;
  List<TeamAssignment>? savedLineup;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async {
    lineupReads++;
    return [..._lineup];
  }

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) async {
    if (saveFailure != null) throw saveFailure!;
    lastMatchId = matchId;
    savedLineup = lineup;
    _lineup = [...lineup];
  }

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
          String matchId) async =>
      roster;

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) async {
    historyReads++;
    return const [];
  }

  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) =>
      throw UnimplementedError();
}
