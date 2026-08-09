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
      // Three at the back is the minimum, so the fourth is all the attack can
      // have and midfield goes empty. Defence before attack is the Product
      // Owner's order, and this is where it shows.
      final formation = buildFormation(squad(def: 2, mid: 1, fwd: 1));

      expect(formation.defence, hasLength(3));
      expect(formation.attack, hasLength(1));
      expect(midfieldCount(formation), 0);
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
    List<int> rowsFor(int n) => buildFormation(squad(def: 4, mid: n, fwd: 3))
        .midfieldRows
        .map((row) => row.length)
        .toList();

    test('three fit on one row', () => expect(rowsFor(3), [3]));
    test('four fit on one row', () => expect(rowsFor(4), [4]));
    test('five become four and one', () => expect(rowsFor(5), [4, 1]));
    test('seven become four and three', () => expect(rowsFor(7), [4, 3]));
    test('eight become four and four', () => expect(rowsFor(8), [4, 4]));

    test('an empty midfield has no rows at all', () {
      expect(buildFormation(squad(def: 3, fwd: 2)).midfieldRows, isEmpty);
    });
  });

  group('ordering within a row', () {
    test('a comparator is applied to every line', () {
      final players = [
        at(Position.def, 'zoe'),
        at(Position.def, 'adam'),
        at(Position.def, 'mia'),
        at(Position.fwd, 'zack'),
        at(Position.fwd, 'ali'),
      ];

      final formation = buildFormation(
        players,
        order: (a, b) => a.userId.compareTo(b.userId),
      );

      expect(formation.defence.map((a) => a.userId), ['adam', 'mia', 'zoe']);
      expect(formation.attack.map((a) => a.userId), ['ali', 'zack']);
    });
  });
}
