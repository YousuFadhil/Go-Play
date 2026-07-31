import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/auth_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/community_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/notification_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/team_mapper.dart';

/// Mapping between provider rows and Domain Models (OP-3). These tests are the
/// only place a column name and a model field are asserted against each other,
/// which is the point: if the schema moves, exactly one suite goes red.
void main() {
  group('joinPolicy', () {
    test('reads both values', () {
      expect(joinPolicyFromDb('OPEN'), JoinPolicy.open);
      expect(joinPolicyFromDb('CODE_REQUIRED'), JoinPolicy.codeRequired);
    });

    test('an unknown policy is treated as the stricter one', () {
      expect(joinPolicyFromDb('SOMETHING_NEW'), JoinPolicy.codeRequired,
          reason: 'a policy the app cannot read must not open the door');
    });

    test('writes what it reads', () {
      expect(joinPolicyToDb(JoinPolicy.open), 'OPEN');
      expect(joinPolicyToDb(JoinPolicy.codeRequired), 'CODE_REQUIRED');
      for (final policy in JoinPolicy.values) {
        expect(joinPolicyFromDb(joinPolicyToDb(policy)), policy);
      }
    });
  });

  group('communityRole', () {
    test('reads every role', () {
      expect(communityRoleFromDb('owner'), CommunityRole.owner);
      expect(communityRoleFromDb('admin'), CommunityRole.admin);
      expect(communityRoleFromDb('player'), CommunityRole.player);
    });

    test('maps the legacy member value to player', () {
      expect(communityRoleFromDb('member'), CommunityRole.player);
    });

    test('an unknown role falls back to the least privileged one', () {
      expect(communityRoleFromDb('superuser'), CommunityRole.player,
          reason: 'an unreadable role must not grant anything');
      expect(communityRoleFromDb(''), CommunityRole.player);
    });

    test('writes what it reads', () {
      for (final role in CommunityRole.values) {
        expect(communityRoleFromDb(communityRoleToDb(role)), role);
      }
    });
  });

  group('communityFromRow', () {
    test('reads the row the adapter selects', () {
      final community = communityFromRow(const {
        'id': 'c1',
        'owner_id': 'u1',
        'name': 'Friday Football',
        'description': 'Weekly game',
        'join_policy': 'CODE_REQUIRED',
        'join_code': 'AB12CD',
      });

      expect(community.id, 'c1');
      expect(community.ownerId, 'u1');
      expect(community.name, 'Friday Football');
      expect(community.description, 'Weekly game');
      expect(community.joinPolicy, JoinPolicy.codeRequired);
      expect(community.joinCode, 'AB12CD');
    });

    test('accepts a null description', () {
      final community = communityFromRow(const {
        'id': 'c1',
        'owner_id': 'u1',
        'name': 'No description',
        'description': null,
        'join_policy': 'OPEN',
        'join_code': 'EF34GH',
      });
      expect(community.description, isNull);
    });
  });

  group('communityMemberFromRow', () {
    test('reads the joined profile and the role', () {
      final member = communityMemberFromRow(const {
        'role': 'admin',
        'user': {
          'id': 'u2',
          'full_name': 'Sara',
          'primary_position': 'MID',
        },
      });

      expect(member.userId, 'u2');
      expect(member.fullName, 'Sara');
      expect(member.position, 'MID');
      expect(member.role, CommunityRole.admin);
      expect(member.isOwner, isFalse);
    });

    test('still reads the legacy member value as player', () {
      final member = communityMemberFromRow(const {
        'role': 'member',
        'user': {'id': 'u3', 'full_name': 'Ali', 'primary_position': 'GK'},
      });
      expect(member.role, CommunityRole.player);
    });
  });

  group('invitePreviewFromRow', () {
    test('reads a valid invitation', () {
      final preview = invitePreviewFromRow(const {
        'state': 'valid',
        'community_id': 'c1',
        'community_name': 'Friday Football',
        'is_member': true,
      });

      expect(preview.isValid, isTrue);
      expect(preview.communityId, 'c1');
      expect(preview.communityName, 'Friday Football');
      expect(preview.isMember, isTrue);
    });

    test('any state but valid is an invalid invitation', () {
      final preview = invitePreviewFromRow(const {
        'state': 'expired',
        'community_id': null,
        'community_name': null,
      });

      expect(preview.isValid, isFalse);
      expect(preview.isMember, isFalse,
          reason: 'a missing flag must not read as membership');
    });
  });

  group('matchStatusFromDb', () {
    test('reads every status', () {
      expect(matchStatusFromDb('open'), MatchStatus.open);
      expect(matchStatusFromDb('full'), MatchStatus.full);
      expect(matchStatusFromDb('completed'), MatchStatus.completed);
    });

    test('an unknown status reads as open', () {
      expect(matchStatusFromDb('archived'), MatchStatus.open);
    });
  });

  group('registrationStatusFromDb', () {
    test('reads both seats', () {
      expect(registrationStatusFromDb('confirmed'), RegistrationStatus.confirmed);
      expect(registrationStatusFromDb('reserve'), RegistrationStatus.reserve);
    });

    test('an unreadable seat is an infrastructure failure, not a guess', () {
      expect(() => registrationStatusFromDb('waitlisted'),
          throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('matchFromRow', () {
    const row = {
      'id': 'm1',
      'community_id': 'c1',
      'created_by': 'u1',
      'location': 'Al Amerat Pitch',
      'start_at': '2026-08-01T17:00:00Z',
      'end_at': '2026-08-01T19:00:00Z',
      'starting_players': 10,
      'max_registration': 16,
      'status': 'open',
      'title': 'Friday Game',
      'description': 'Bring both kits',
      'community': {'name': 'Friday Football'},
    };

    test('reads the row the adapter selects', () {
      final match = matchFromRow(row);

      expect(match.id, 'm1');
      expect(match.communityId, 'c1');
      expect(match.createdBy, 'u1');
      expect(match.location, 'Al Amerat Pitch');
      expect(match.startingPlayers, 10);
      expect(match.maxRegistration, 16);
      expect(match.status, MatchStatus.open);
      expect(match.title, 'Friday Game');
      expect(match.description, 'Bring both kits');
      expect(match.communityName, 'Friday Football');
    });

    test('times arrive local but still mean the stored instant', () {
      final match = matchFromRow(row);

      expect(match.startAt.isUtc, isFalse);
      expect(match.startAt.toUtc(), DateTime.utc(2026, 8, 1, 17));
      expect(match.endAt.toUtc(), DateTime.utc(2026, 8, 1, 19));
    });

    test('the community name is null when the query did not join it', () {
      final match = matchFromRow({...row}..remove('community'));
      expect(match.communityName, isNull);
    });
  });

  group('matchRegistrationFromRow', () {
    test('reads the joined profile, the seat and the order', () {
      final registration = matchRegistrationFromRow(const {
        'status': 'reserve',
        'registration_order': 12,
        'user': {'id': 'u4', 'full_name': 'Khalid', 'primary_position': 'FWD'},
      });

      expect(registration.userId, 'u4');
      expect(registration.fullName, 'Khalid');
      expect(registration.position, 'FWD');
      expect(registration.status, RegistrationStatus.reserve);
      expect(registration.registrationOrder, 12);
    });
  });

  group('notificationFromRow', () {
    test('reads the row the adapter selects', () {
      final notification = notificationFromRow(const {
        'id': 'n1',
        'type': 'promoted_from_reserve',
        'message': 'You are in the starting eleven',
        'is_read': false,
        'created_at': '2026-07-30T08:30:00Z',
        'match_id': 'm1',
      });

      expect(notification.id, 'n1');
      expect(notification.type, 'promoted_from_reserve');
      expect(notification.message, 'You are in the starting eleven');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt.toUtc(), DateTime.utc(2026, 7, 30, 8, 30));
      expect(notification.matchId, 'm1');
    });

    test('a notification not tied to a match has no match id', () {
      final notification = notificationFromRow(const {
        'id': 'n2',
        'type': 'community_invite',
        'message': 'You were added to Friday Football',
        'is_read': true,
        'created_at': '2026-07-30T08:30:00Z',
        'match_id': null,
      });
      expect(notification.matchId, isNull);
    });
  });

  group('admin mappers', () {
    test('read a user row', () {
      final user = adminUserFromRow(const {
        'id': 'u1',
        'full_name': 'Sara',
        'email': 'sara@example.com',
        'is_system_admin': true,
      });

      expect(user.id, 'u1');
      expect(user.fullName, 'Sara');
      expect(user.email, 'sara@example.com');
      expect(user.isSystemAdmin, isTrue);
    });

    test('a user row missing its optional fields still reads', () {
      final user = adminUserFromRow(const {'id': 'u2'});

      expect(user.fullName, '');
      expect(user.email, '');
      expect(user.isSystemAdmin, isFalse,
          reason: 'a missing flag must not protect an account by accident');
    });

    test('read a community row, keeping a missing owner name null', () {
      final community = adminCommunityFromRow(const {
        'id': 'c1',
        'name': 'Friday Football',
        'owner_name': null,
        'member_count': 24,
        'match_count': 7,
      });

      expect(community.name, 'Friday Football');
      expect(community.ownerName, isNull,
          reason: 'what stands in for a missing name is the screen\'s choice');
      expect(community.memberCount, 24);
      expect(community.matchCount, 7);
    });

    test('read a match row', () {
      final match = adminMatchFromRow(const {
        'id': 'm1',
        'title': 'Friday Game',
        'community_name': 'Friday Football',
        'location': 'Al Amerat Pitch',
        'registration_count': 14,
      });

      expect(match.title, 'Friday Game');
      expect(match.communityName, 'Friday Football');
      expect(match.location, 'Al Amerat Pitch');
      expect(match.registrationCount, 14);
    });
  });

  group('playerPositionToDb', () {
    test('writes the stored code for every position', () {
      expect(playerPositionToDb(PlayerPosition.gk), 'GK');
      expect(playerPositionToDb(PlayerPosition.def), 'DEF');
      expect(playerPositionToDb(PlayerPosition.mid), 'MID');
      expect(playerPositionToDb(PlayerPosition.fwd), 'FWD');
    });
  });

  group('the team-generation vocabularies', () {
    test('positions read and write the same four codes', () {
      expect(positionFromDb('GK'), Position.gk);
      expect(positionFromDb('DEF'), Position.def);
      expect(positionFromDb('MID'), Position.mid);
      expect(positionFromDb('FWD'), Position.fwd);
      for (final position in Position.values) {
        expect(positionFromDb(positionToDb(position)), position);
      }
    });

    test('teams read and write both labels', () {
      expect(teamFromDb('A'), TeamId.a);
      expect(teamFromDb('B'), TeamId.b);
      for (final team in TeamId.values) {
        expect(teamFromDb(teamToDb(team)), team);
      }
    });

    test('the assignment basis reads and writes all three steps', () {
      expect(assignmentBasisFromDb('PRIMARY'), AssignmentBasis.primary);
      expect(assignmentBasisFromDb('SECONDARY'), AssignmentBasis.secondary);
      expect(assignmentBasisFromDb('TRANSITION'), AssignmentBasis.transition);
      for (final basis in AssignmentBasis.values) {
        expect(assignmentBasisFromDb(assignmentBasisToDb(basis)), basis);
      }
    });

    test('a value outside a constrained vocabulary is an infrastructure fault',
        () {
      // Migration 0018 constrains all three columns, so reaching here means
      // the database and this build disagree about the schema.
      expect(() => positionFromDb('SWEEPER'), throwsA(isA<InfrastructureFailure>()));
      expect(() => teamFromDb('C'), throwsA(isA<InfrastructureFailure>()));
      expect(() => assignmentBasisFromDb('GUESS'),
          throwsA(isA<InfrastructureFailure>()));
    });

    test('a rating arrives as a number or as its text form', () {
      expect(ratingFromDb(5), 5.0);
      expect(ratingFromDb(7.5), 7.5);
      expect(ratingFromDb('7.5'), 7.5);
    });

    test('a rating that is neither is an infrastructure fault', () {
      // The column is NOT NULL, so nothing here may stand in for it (§4.3).
      expect(() => ratingFromDb(null), throwsA(isA<InfrastructureFailure>()));
      expect(() => ratingFromDb('good'), throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('playerCoreInputsFromRow', () {
    test('reads the whole profile the engine needs', () {
      final player = playerCoreInputsFromRow(const {
        'user': {
          'id': 'u1',
          'full_name': 'Sara Al Balushi',
          'overall_rating': 7.5,
          'date_of_birth': '1995-04-17',
          'primary_position': 'MID',
          'secondary_position': 'DEF',
        },
      });

      expect(player.userId, 'u1');
      expect(player.fullName, 'Sara Al Balushi');
      expect(player.overallRating, 7.5);
      expect(player.dateOfBirth, DateTime(1995, 4, 17));
      expect(player.primaryPosition, Position.mid);
      expect(player.secondaryPosition, Position.def);
      expect(player.hasEveryRequiredInput, isTrue);
    });

    test('a profile that has neither optional field invents neither', () {
      final player = playerCoreInputsFromRow(const {
        'user': {
          'id': 'u2',
          'full_name': 'Ahmed',
          'overall_rating': 5.0,
          'date_of_birth': null,
          'primary_position': 'GK',
          'secondary_position': null,
        },
      });

      expect(player.dateOfBirth, isNull);
      expect(player.secondaryPosition, isNull);
      expect(player.hasEveryRequiredInput, isFalse,
          reason: 'a missing date of birth travels up, it is not filled in');
    });
  });

  group('the stored lineup', () {
    test('an assignment row reads into the model', () {
      final assignment = teamAssignmentFromRow(const {
        'user_id': 'u1',
        'team': 'B',
        'assigned_position': 'DEF',
        'assignment_basis': 'TRANSITION',
      });

      expect(assignment.userId, 'u1');
      expect(assignment.team, TeamId.b);
      expect(assignment.assignedPosition, Position.def);
      expect(assignment.basis, AssignmentBasis.transition);
      expect(assignment.outOfPosition, isTrue);
    });

    test('an assignment writes back the row it was read from', () {
      const row = {
        'user_id': 'u1',
        'team': 'A',
        'assigned_position': 'GK',
        'assignment_basis': 'PRIMARY',
      };

      expect(teamAssignmentToRow('m1', teamAssignmentFromRow(row)),
          {'match_id': 'm1', ...row});
    });

    test('out of position is derived, never written', () {
      final row = teamAssignmentToRow(
          'm1',
          teamAssignmentFromRow(const {
            'user_id': 'u1',
            'team': 'A',
            'assigned_position': 'MID',
            'assignment_basis': 'TRANSITION',
          }));

      expect(row.containsKey('out_of_position'), isFalse,
          reason: 'a stored copy could disagree with the basis (§5.1)');
    });
  });

  group('pastMatchFromRow', () {
    test('groups the stored lineup into its two sides', () {
      final past = pastMatchFromRow(const {
        'start_at': '2026-07-01T17:00:00Z',
        'assignments': [
          {'user_id': 'u1', 'team': 'A'},
          {'user_id': 'u2', 'team': 'B'},
          {'user_id': 'u3', 'team': 'A'},
        ],
      });

      expect(past.teams, hasLength(2));
      expect(past.teams[0], {'u1', 'u3'});
      expect(past.teams[1], {'u2'});
      expect(past.playedAt,
          DateTime.parse('2026-07-01T17:00:00Z').toLocal());
    });

    test('the pairs it yields are the teammates and no one else', () {
      final past = pastMatchFromRow(const {
        'start_at': '2026-07-01T17:00:00Z',
        'assignments': [
          {'user_id': 'u1', 'team': 'A'},
          {'user_id': 'u2', 'team': 'A'},
          {'user_id': 'u3', 'team': 'B'},
        ],
      });

      expect(past.teammatePairs(), {'u1|u2'},
          reason: 'opponents are not teammates');
    });

    test('a one-sided lineup still reads', () {
      final past = pastMatchFromRow(const {
        'start_at': '2026-07-01T17:00:00Z',
        'assignments': [
          {'user_id': 'u1', 'team': 'A'},
        ],
      });

      expect(past.teams, hasLength(1));
      expect(past.teammatePairs(), isEmpty);
    });
  });
}
