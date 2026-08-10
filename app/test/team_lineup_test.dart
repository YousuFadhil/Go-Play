import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The team-generation Domain Models on their own.
///
/// Two rules are asserted here because they are rules, not plumbing: a Core
/// Player Input is never invented when the profile does not hold it (§4.3),
/// and Out of Position is derived from the assignment basis rather than
/// carried alongside it (§5.1).
PlayerCoreInputs buildInputs({
  String userId = 'u1',
  String fullName = 'Sara Al Balushi',
  double overallRating = 6.5,
  Position primaryPosition = Position.mid,
  DateTime? dateOfBirth,
  Position? secondaryPosition,
}) {
  return PlayerCoreInputs(
    userId: userId,
    fullName: fullName,
    overallRating: overallRating,
    primaryPosition: primaryPosition,
    dateOfBirth: dateOfBirth,
    secondaryPosition: secondaryPosition,
  );
}

void main() {
  group('PlayerCoreInputs', () {
    test('a profile with a date of birth has everything the engine needs', () {
      final player = buildInputs(dateOfBirth: DateTime(1995, 4, 17));

      expect(player.hasEveryRequiredInput, isTrue);
    });

    test('a profile without a date of birth does not', () {
      expect(buildInputs().hasEveryRequiredInput, isFalse);
    });

    test('a missing secondary position is ordinary input (BTGE-SC-6)', () {
      final player = buildInputs(dateOfBirth: DateTime(1995, 4, 17));

      expect(player.hasEveryRequiredInput, isTrue,
          reason: 'no secondary position is normal, not incomplete');
      expect(player.toPlayer().secondaryPosition, isNull);
    });

    test('the engine sees the four Core Player Inputs and nothing else', () {
      final converted = buildInputs(
        userId: 'u7',
        fullName: 'Sara Al Balushi',
        overallRating: 7.5,
        primaryPosition: Position.fwd,
        secondaryPosition: Position.mid,
        dateOfBirth: DateTime(1990, 1, 2),
      ).toPlayer();

      expect(converted.id, 'u7');
      expect(converted.overallRating, 7.5);
      expect(converted.dateOfBirth, DateTime(1990, 1, 2));
      expect(converted.primaryPosition, Position.fwd);
      expect(converted.secondaryPosition, Position.mid);
    });

    test('a date of birth is never invented (§4.3)', () {
      expect(buildInputs().toPlayer, throwsA(isA<StateError>()),
          reason: 'a missing required input is refused, not defaulted');
    });
  });

  group('TeamAssignment', () {
    TeamAssignment assignmentWith(AssignmentBasis basis) =>
        TeamAssignment.fromAssignment(PlayerAssignment(
          playerId: 'u1',
          team: TeamId.b,
          assignedPosition: Position.def,
          basis: basis,
        ));

    test('carries the engine output across unchanged', () {
      final assignment = assignmentWith(AssignmentBasis.secondary);

      expect(assignment.userId, 'u1');
      expect(assignment.team, TeamId.b);
      expect(assignment.assignedPosition, Position.def);
      expect(assignment.basis, AssignmentBasis.secondary);
    });

    test('out of position is exactly a transition (§5.1)', () {
      expect(assignmentWith(AssignmentBasis.transition).outOfPosition, isTrue);
      expect(assignmentWith(AssignmentBasis.primary).outOfPosition, isFalse);
      expect(assignmentWith(AssignmentBasis.secondary).outOfPosition, isFalse,
          reason: 'a declared secondary is not penalised (BTGE-PT-2)');
    });
  });
}
