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

  // --- Professional Guests -----------------------------------------------------
  //
  // A guest is on a side like anybody else, and which side is `KB-D6`'s
  // question rather than a profile's. What differs is which column names them,
  // and that is exactly what these assert cannot be lost.

  TeamAssignment guestAt(String guestId, TeamId team) => TeamAssignment(
        professionalGuestId: guestId,
        team: team,
        assignedPosition: null,
        basis: null,
      );

  /// Two players and two guests, one of each a side.
  List<TeamAssignment> mixedLineup() => [
        at('u1', TeamId.a, Position.gk),
        guestAt('g1', TeamId.a),
        at('u3', TeamId.b, Position.mid),
        guestAt('g2', TeamId.b),
      ];

  TeamAssignment savedParticipant(FakeTeamAdapter adapter, String id) =>
      adapter.savedLineup!.singleWhere((a) => a.participantId == id);

  group('the identity a move carries', () {
    // The latent bug this closes: the moved assignment used to be rebuilt from
    // `userId` alone, which dropped `professionalGuestId`. For a guest that
    // produced a row naming nobody -- refused by the table's XOR check -- and
    // nothing caught it because a guest could not be moved in the first place.

    test('a community player keeps their user id and gains no guest id',
        () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'u1');

      final moved = savedParticipant(adapter, 'u1');
      expect(moved.userId, 'u1');
      expect(moved.professionalGuestId, isNull);
      expect(moved.isProfessionalGuest, isFalse);
      expect(moved.team, TeamId.b);
    });

    test('a Professional Guest keeps their guest id and gains no user id',
        () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      final moved = savedParticipant(adapter, 'g1');
      expect(moved.professionalGuestId, 'g1');
      expect(moved.userId, isNull);
      expect(moved.isProfessionalGuest, isTrue);
      expect(moved.team, TeamId.b);
    });

    test('every saved row still names exactly one participant', () async {
      // The XOR the schema states, asserted over the whole lineup rather than
      // the row that moved: a rebuild that lost an identity would show up here
      // whichever row it happened to.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'g2');

      for (final a in adapter.savedLineup!) {
        expect((a.userId == null) != (a.professionalGuestId == null), isTrue,
            reason: 'exactly one identity, never both and never neither');
      }
    });
  });

  group('move a Professional Guest', () {
    test('A to B', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      expect(savedParticipant(adapter, 'g1').team, TeamId.b);
    });

    test('B to A', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g2');

      expect(savedParticipant(adapter, 'g2').team, TeamId.a);
    });

    test('no position is invented for them', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      final moved = savedParticipant(adapter, 'g1');
      expect(moved.assignedPosition, isNull,
          reason: 'a guest has no profile for a position to be derived from');
      expect(moved.basis, isNull);
    });

    test('the side is marked as one a person chose', () async {
      // What `assign_professional_guest_teams` reads to stop re-alternating
      // this row (migration `0058`). Without it the move is undone by the very
      // write that saves it.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      expect(savedParticipant(adapter, 'g1').teamManuallyOverridden, isTrue);
    });

    test('a community player is not marked', () async {
      // The flag governs the guest alternation. Nothing re-derives a player's
      // side, so there is nothing for it to protect them from.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'u1');

      expect(savedParticipant(adapter, 'u1').teamManuallyOverridden, isFalse);
    });

    test('nobody else is touched (BTGE-MO-3)', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      expect(savedParticipant(adapter, 'u1').team, TeamId.a);
      expect(savedParticipant(adapter, 'u3').team, TeamId.b);
      expect(savedParticipant(adapter, 'g2').team, TeamId.b);
      expect(adapter.savedLineup, hasLength(4));
    });

    test('a guest who is not in the lineup is refused', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      expect(
        () => TeamRepository(adapter).movePlayer('m1', 'g9'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('swap with a Professional Guest', () {
    test('a guest and a community player exchange sides', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'u3');

      expect(savedParticipant(adapter, 'g1').team, TeamId.b);
      expect(savedParticipant(adapter, 'u3').team, TeamId.a);
      expect(savedParticipant(adapter, 'g1').professionalGuestId, 'g1');
      expect(savedParticipant(adapter, 'u3').userId, 'u3');
    });

    test('two guests exchange sides', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'g2');

      expect(savedParticipant(adapter, 'g1').team, TeamId.b);
      expect(savedParticipant(adapter, 'g2').team, TeamId.a);
    });

    test('each keeps the position they had, guests included', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'u3');

      expect(savedParticipant(adapter, 'g1').assignedPosition, isNull);
      expect(savedParticipant(adapter, 'u3').assignedPosition, Position.mid);
    });

    test('each guest involved is marked, the player is not', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'u3');

      expect(savedParticipant(adapter, 'g1').teamManuallyOverridden, isTrue);
      expect(savedParticipant(adapter, 'u3').teamManuallyOverridden, isFalse);
    });

    test('both guests are marked in a guest-to-guest swap', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'g2');

      expect(savedParticipant(adapter, 'g1').teamManuallyOverridden, isTrue);
      expect(savedParticipant(adapter, 'g2').teamManuallyOverridden, isTrue);
    });

    test('two guests already on the same side are refused', () async {
      final adapter = FakeTeamAdapter(lineup: [
        at('u1', TeamId.a, Position.gk),
        guestAt('g1', TeamId.a),
        guestAt('g2', TeamId.a),
        at('u3', TeamId.b, Position.mid),
      ]);

      expect(
        () => TeamRepository(adapter).swapPlayers('m1', 'g1', 'g2'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a guest swapped with themselves is refused', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      expect(
        () => TeamRepository(adapter).swapPlayers('m1', 'g1', 'g1'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('the whole lineup is written once, atomically', () async {
      // One `saveLineup`, not two updates. `replace_match_lineup` is one
      // transaction, and a swap that took two calls could leave both
      // participants on the same side in between.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'u3');

      expect(adapter.saveCount, 1);
      expect(adapter.savedLineup, hasLength(4));
    });
  });

  group('a Professional Guest takes a match-scoped position', () {
    test('the position is stored and the identity is not disturbed', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'g1', Position.mid);

      final saved = savedParticipant(adapter, 'g1');
      expect(saved.assignedPosition, Position.mid);
      expect(saved.professionalGuestId, 'g1');
      expect(saved.userId, isNull,
          reason: 'a position does not turn a guest into a user');
      expect(saved.team, TeamId.a, reason: 'the side is not what changed');
    });

    test('any of the four positions is accepted', () async {
      for (final position in Position.values) {
        final adapter = FakeTeamAdapter(lineup: mixedLineup());

        await TeamRepository(adapter)
            .changeAssignedPosition('m1', 'g1', position);

        expect(savedParticipant(adapter, 'g1').assignedPosition, position);
      }
    });

    test('the basis stays absent, so no profile is implied', () async {
      // §5.1 defines the basis against a profile. A guest has none, and a
      // position for this match does not give them one — `replace_match_lineup`
      // writes `GUEST` for any row naming a guest regardless.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'g1', Position.fwd);

      expect(savedParticipant(adapter, 'g1').basis, isNull);
    });

    test('it does not make them an engine input', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'g1', Position.gk);

      expect(adapter.historyReads, 0,
          reason: 'no Auxiliary Data read, so no generation happened');
      expect(adapter.savedLineup!.where((a) => a.isProfessionalGuest),
          hasLength(2), reason: 'both guests are still guests');
    });

    test('a community player still derives a basis from their profile',
        () async {
      // Unchanged: the derivation §5.1 defines still runs for somebody who has
      // a profile to derive it from.
      final adapter = FakeTeamAdapter(
        lineup: mixedLineup(),
        roster: [profile('u1', Position.gk, secondary: Position.def)],
      );

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'u1', Position.def);

      final saved = savedParticipant(adapter, 'u1');
      expect(saved.assignedPosition, Position.def);
      expect(saved.basis, AssignmentBasis.secondary);
    });

    test('an ordinary save keeps it: it is not a generation', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter)
          .changeAssignedPosition('m1', 'g1', Position.mid);

      expect(adapter.lastFromGeneration, isFalse,
          reason: 'only a generation gives a chosen position back');
    });
  });

  group('which save clears a chosen side', () {
    test('a manual move does not say it came from a generation', () async {
      // The distinction migration `0058` reads. A manual save must keep every
      // chosen side, so it must not claim to be a generation.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).movePlayer('m1', 'g1');

      expect(adapter.lastFromGeneration, isFalse);
    });

    test('a swap does not either', () async {
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).swapPlayers('m1', 'g1', 'u3');

      expect(adapter.lastFromGeneration, isFalse);
    });

    test('saving a generated lineup does', () async {
      // `BTGE-MO-2`: a fresh search discards what was adjusted around the
      // previous teams, and a guest's chosen side is such an adjustment.
      final adapter = FakeTeamAdapter(lineup: mixedLineup());

      await TeamRepository(adapter).saveLineup('m1', lineup());

      expect(adapter.lastFromGeneration, isTrue);
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

  /// Whether the last save said it followed a generation. It is the one
  /// thing that clears a guest's chosen side (migration `0058`).
  bool? lastFromGeneration;

  /// How many times the lineup was written. A swap is one write.
  int saveCount = 0;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async {
    lineupReads++;
    return [..._lineup];
  }

  @override
  Future<void> saveLineup(
    String matchId,
    List<TeamAssignment> lineup, {
    bool fromGeneration = false,
  }) async {
    if (saveFailure != null) throw saveFailure!;
    lastMatchId = matchId;
    savedLineup = lineup;
    lastFromGeneration = fromGeneration;
    saveCount++;
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

  @override
  Future<void> removePlayedProfessionalGuest(String matchId, String guestId) =>
      throw UnimplementedError();
}
