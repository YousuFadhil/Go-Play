import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/teams/formation.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The Product Owner's rules for arranging a lineup on a drawn pitch.
///
/// These are worth testing on their own precisely because they are not stored:
/// nothing in the database records that a fifth defender was drawn in midfield,
/// so the rules have no other witness. Every case below is a squad shape, and
/// what is asserted is which row each player lands in.
void main() {
  var counter = 0;

  /// A player in [position]. The id is generated so a test can name a squad by
  /// its shape rather than by inventing ids.
  TeamAssignment at(Position position, [String? id]) => TeamAssignment(
        userId: id ?? 'p${counter++}',
        team: TeamId.a,
        assignedPosition: position,
        basis: AssignmentBasis.primary,
      );

  List<TeamAssignment> squad({
    int gk = 0,
    int def = 0,
    int mid = 0,
    int fwd = 0,
  }) =>
      [
        for (var i = 0; i < gk; i++) at(Position.gk),
        for (var i = 0; i < def; i++) at(Position.def),
        for (var i = 0; i < mid; i++) at(Position.mid),
        for (var i = 0; i < fwd; i++) at(Position.fwd),
      ];

  /// How many players ended up in midfield across all its rows.
  int midfieldCount(PitchFormation f) =>
      f.midfieldRows.fold(0, (total, row) => total + row.length);

  setUp(() => counter = 0);

  group('nobody is lost or duplicated', () {
    test('every player is drawn exactly once', () {
      final players = squad(gk: 1, def: 5, mid: 6, fwd: 4);
      final formation = buildFormation(players);

      expect(formation.all, hasLength(players.length));
      expect(
        formation.all.map((a) => a.userId).toSet(),
        players.map((a) => a.userId).toSet(),
      );
    });

    test('an empty lineup draws nothing rather than failing', () {
      final formation = buildFormation([]);

      expect(formation.all, isEmpty);
      expect(formation.midfieldRows, isEmpty);
    });
  });

  group('defence is filled first', () {
    test('four defenders all stay at the back', () {
      final formation = buildFormation(squad(def: 4, mid: 4, fwd: 2));

      expect(formation.defence, hasLength(4));
      expect(
        formation.defence.every((a) => a.assignedPosition == Position.def),
        isTrue,
      );
    });

    test('a fifth defender is moved to midfield', () {
      final formation = buildFormation(squad(def: 6, mid: 2, fwd: 2));

      expect(formation.defence, hasLength(kDefenceMax));
      // The two beyond the cap fell through to midfield, alongside the two
      // actual midfielders.
      expect(midfieldCount(formation), 4);
    });

    test('too few defenders are made up with midfielders', () {
      final formation = buildFormation(squad(def: 1, mid: 6, fwd: 2));

      expect(formation.defence, hasLength(kDefenceMin));
      expect(
        formation.defence.where((a) => a.assignedPosition == Position.mid),
        hasLength(2),
      );
    });

    test('with no midfielders either, anyone fills the gap', () {
      // Defence is filled before attack, so the forwards are what is available.
      final formation = buildFormation(squad(def: 1, fwd: 5));

      expect(formation.defence, hasLength(kDefenceMin));
      expect(
        formation.defence.where((a) => a.assignedPosition == Position.fwd),
        hasLength(2),
      );
    });
  });

  group('attack is filled second', () {
    test('three forwards all stay up front', () {
      final formation = buildFormation(squad(def: 4, mid: 4, fwd: 3));

      expect(formation.attack, hasLength(3));
    });

    test('a fourth forward is moved to midfield', () {
      final formation = buildFormation(squad(def: 4, mid: 2, fwd: 5));

      expect(formation.attack, hasLength(kAttackMax));
      expect(midfieldCount(formation), 4);
    });

    test('too few forwards are made up with midfielders', () {
      final formation = buildFormation(squad(def: 4, mid: 6));

      expect(formation.attack, hasLength(kAttackMin));
      expect(
        formation.attack.every((a) => a.assignedPosition == Position.mid),
        isTrue,
      );
    });
  });

  group('a squad too small for the minimums takes what it has', () {
    test('four outfield players defend first', () {
      // Three at the back is the minimum, so one player is all that is left for
      // the two rows above it. Defence before attack is the Product Owner's
      // order, and this is where it shows. That last player is drawn in
      // midfield rather than in attack, because a lone attacker over an empty
      // midfield is exactly the arrangement the presentation rule forbids.
      final formation = buildFormation(squad(def: 2, mid: 1, fwd: 1));

      expect(formation.defence, hasLength(3));
      expect(formation.attack, isEmpty);
      expect(midfieldCount(formation), 1);
      expect(formation.all, hasLength(4));
    });

    test('two players do not invent a third', () {
      final formation = buildFormation(squad(def: 1, fwd: 1));

      expect(formation.defence, hasLength(2));
      expect(formation.attack, isEmpty);
      expect(formation.all, hasLength(2));
    });
  });

  group('the goalkeeper is drawn in goal, not counted as a defender', () {
    test('a keeper is kept out of the outfield rules', () {
      final formation = buildFormation(squad(gk: 1, def: 3, mid: 4, fwd: 2));

      expect(formation.goalkeepers, hasLength(1));
      // The three real defenders still make the back line; the keeper did not
      // take one of their places.
      expect(formation.defence, hasLength(3));
      expect(
        formation.defence.every((a) => a.assignedPosition == Position.def),
        isTrue,
      );
    });

    test('a lineup with no keeper has an empty goal row', () {
      final formation = buildFormation(squad(def: 3, mid: 3, fwd: 2));

      expect(formation.goalkeepers, isEmpty);
    });
  });

  group('midfield wraps at four to a row', () {
    /// The row sizes for a midfield of [n], with defence and attack already
    /// satisfied so the remainder lands in midfield untouched.
    ///
    /// Two forwards rather than three, so that every [n] here already satisfies
    /// `attack < midfield` and no player is moved between the two lines. What is
    /// being measured is the wrapping, not the thinning.
    List<int> rowsFor(int n) => buildFormation(squad(def: 4, mid: n, fwd: 2))
        .midfieldRows
        .map((row) => row.length)
        .toList();

    test('three fit on one row', () => expect(rowsFor(3), [3]));
    test('four fit on one row', () => expect(rowsFor(4), [4]));
    test('five become four and one', () => expect(rowsFor(5), [4, 1]));
    test('seven become four and three', () => expect(rowsFor(7), [4, 3]));
    test('eight become four and four', () => expect(rowsFor(8), [4, 4]));

    test('an empty midfield has no rows at all', () {
      // A side of three, all of whom the back line takes. There is nothing
      // above it to draw, in either row.
      expect(buildFormation(squad(def: 3)).midfieldRows, isEmpty);
    });
  });

  group('ordering within a row', () {
    test('a comparator is applied to every line', () {
      final players = [
        at(Position.def, 'zoe'),
        at(Position.def, 'adam'),
        at(Position.def, 'mia'),
        at(Position.def, 'sara'),
        at(Position.mid, 'nadia'),
        at(Position.mid, 'omar'),
        at(Position.mid, 'basma'),
        at(Position.mid, 'karim'),
        at(Position.fwd, 'zack'),
        at(Position.fwd, 'ali'),
        at(Position.fwd, 'huda'),
      ];

      final formation = buildFormation(
        players,
        order: (a, b) => a.userId.compareTo(b.userId),
      );

      expect(formation.defence.map((a) => a.userId),
          ['adam', 'mia', 'sara', 'zoe']);
      expect(formation.attack.map((a) => a.userId), ['ali', 'huda', 'zack']);
    });
  });

  // --- The presentation rule ------------------------------------------------
  //
  // The Teams screen must never draw a team with as many attackers as
  // midfielders. It is a rule about the *drawing* and nothing else: the stored
  // lineup, the assigned positions and the size of each side are untouched by
  // it, which is what the "nobody is lost" assertions below are for.

  group('the attack is never drawn as large as the midfield', () {
    /// Every squad shape worth checking, as (defenders, midfielders, forwards).
    const shapes = <(int, int, int)>[
      (4, 4, 3), // already satisfied: nothing moves
      (4, 3, 3), // equal lines: one attacker drops
      (4, 2, 5), // three up front against two in midfield
      (4, 0, 6), // no recognised midfielders at all
      (3, 0, 4), // a thin squad, defence filled first
      (2, 1, 1), // the smallest side the minimums cannot satisfy
      (5, 5, 5),
      (1, 6, 2),
      (6, 2, 2),
    ];

    for (final (def, mid, fwd) in shapes) {
      test('$def/$mid/$fwd draws fewer attackers than midfielders', () {
        final players = squad(def: def, mid: mid, fwd: fwd);
        final formation = buildFormation(players);

        expect(
          formation.attack.length,
          lessThan(midfieldCount(formation)),
          reason: 'the top row must be smaller than the middle',
        );
        // And the whole point: it was achieved by moving players between rows,
        // never by dropping one.
        expect(formation.all, hasLength(players.length));
        expect(
          formation.all.map((a) => a.userId).toSet(),
          players.map((a) => a.userId).toSet(),
        );
      });
    }

    test('an attacker moved into midfield keeps the position they were given',
        () {
      // The stored assignment is untouched — `KB-017` makes it the record of
      // what played, and a drawing does not edit a record. A forward drawn in
      // midfield is still a forward.
      final formation = buildFormation(squad(def: 4, mid: 2, fwd: 5));
      final midfielders = [for (final row in formation.midfieldRows) ...row];

      expect(
        midfielders.where((a) => a.assignedPosition == Position.fwd),
        isNotEmpty,
        reason: 'the surplus forwards are the ones that moved',
      );
      expect(
        formation.all.where((a) => a.assignedPosition == Position.fwd),
        hasLength(5),
        reason: 'five forwards went in and five come out',
      );
    });

    test('the fewest players are moved, not the most', () {
      // Three and three: moving one makes it two against four, which already
      // satisfies the rule. A second move would be an attack emptied on
      // principle.
      final formation = buildFormation(squad(def: 4, mid: 3, fwd: 3));

      expect(formation.attack, hasLength(2));
      expect(midfieldCount(formation), 4);
    });

    test('a forward moved into midfield is recorded as one', () {
      // The presentation marker's source. It is a fact about the *drawing* —
      // where the card ended up — and it changes nothing about the assignment
      // that put the player there.
      final formation = buildFormation(squad(def: 3, mid: 2, fwd: 2));
      final midfield = [for (final row in formation.midfieldRows) ...row];
      final moved = midfield.where((a) => a.assignedPosition == Position.fwd);

      expect(moved, hasLength(1), reason: 'one forward came down');
      expect(formation.movedFrom.keys, {moved.single.userId});
      expect(formation.movedFrom[moved.single.userId], Position.fwd,
          reason: 'the marker names the position the player actually holds');
    });

    test('the moved player still holds the position the lineup gave them', () {
      final formation = buildFormation(squad(def: 3, mid: 2, fwd: 2));
      final markedId = formation.movedFrom.keys.single;
      final drawn = formation.all.singleWhere((a) => a.userId == markedId);

      expect(drawn.assignedPosition, Position.fwd,
          reason: 'the drawing marks the card; it does not rewrite it');
      expect(drawn.outOfPosition, isFalse,
          reason: 'the engine played them in their own position, so the '
              'out-of-position marker is a different answer and stays false');
    });

    test('a real midfielder in midfield is not marked', () {
      final formation = buildFormation(squad(def: 3, mid: 2, fwd: 2));
      final midfield = [for (final row in formation.midfieldRows) ...row];
      final realMidfielders =
          midfield.where((a) => a.assignedPosition == Position.mid);

      expect(realMidfielders, hasLength(2));
      for (final midfielder in realMidfielders) {
        expect(formation.movedFrom.containsKey(midfielder.userId), isFalse);
      }
    });

    test('a pitch that moved nobody marks nobody', () {
      // Three up front against four in midfield already satisfies the rule, so
      // no forward comes down and no card claims to have.
      final formation = buildFormation(squad(def: 4, mid: 4, fwd: 3));

      expect(formation.attack, hasLength(3));
      expect(formation.movedFrom, isEmpty);
    });

    test('a forward that overflowed the attack cap is marked too', () {
      // It reached midfield by a different route — beyond `kAttackMax` rather
      // than through the thinning — but it is in the same place, and two
      // identical cards must not say different things.
      final formation = buildFormation(squad(def: 4, mid: 2, fwd: 5));
      final midfield = [for (final row in formation.midfieldRows) ...row];
      final forwardsInMidfield =
          midfield.where((a) => a.assignedPosition == Position.fwd);

      expect(forwardsInMidfield, isNotEmpty);
      for (final forward in forwardsInMidfield) {
        expect(formation.movedFrom[forward.userId], Position.fwd);
      }
      expect(formation.movedFrom, hasLength(forwardsInMidfield.length),
          reason: 'nobody else is marked');
    });

    test('nobody in the attack, defence or goal is marked', () {
      final formation = buildFormation(squad(gk: 1, def: 5, mid: 2, fwd: 4));
      final marked = formation.movedFrom.keys.toSet();

      for (final line in [
        formation.attack,
        formation.defence,
        formation.goalkeepers,
      ]) {
        for (final assignment in line) {
          expect(marked.contains(assignment.userId), isFalse);
        }
      }
    });

    test('a side with no row above the defence is drawn as it always was', () {
      // The one shape the rule cannot satisfy: every outfield player was
      // absorbed by the back line, so there is nobody to move and no attack row
      // and no midfield row to compare. Nothing is invented and nobody is
      // hidden — all three are still drawn.
      final formation = buildFormation(squad(def: 3));

      expect(formation.attack, isEmpty);
      expect(midfieldCount(formation), 0);
      expect(formation.all, hasLength(3));
    });
  });
}
