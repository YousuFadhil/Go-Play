import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/auth_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/community_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/notification_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/profile_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/result_mapper.dart';
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
    test('reads the profile, the seat, the order and the arrangement', () {
      final registration = matchRegistrationFromRow(const {
        'registration_id': 'reg-4',
        'user_id': 'u4',
        'professional_guest_id': null,
        'participant_type': 'USER',
        'display_name': 'Khalid',
        'primary_position': 'FWD',
        'status': 'reserve',
        'registration_order': 12,
        'admin_order': 5,
        'roster_position': 5,
      });

      expect(registration.registrationId, 'reg-4');
      expect(registration.userId, 'u4');
      expect(registration.fullName, 'Khalid');
      expect(registration.position, 'FWD');
      expect(registration.status, RegistrationStatus.reserve);
      expect(registration.registrationOrder, 12);
      expect(registration.adminOrder, 5);
    });

    test('a match nobody has arranged carries no administrative position', () {
      final registration = matchRegistrationFromRow(const {
        'registration_id': 'reg-1',
        'user_id': 'u1',
        'professional_guest_id': null,
        'participant_type': 'USER',
        'display_name': 'Sara',
        'primary_position': 'GK',
        'status': 'confirmed',
        'registration_order': 1,
        'admin_order': null,
        'roster_position': 1,
      });

      expect(registration.adminOrder, isNull);
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

    test('reads every code back to the position it was written from', () {
      expect(playerPositionFromDb('GK'), PlayerPosition.gk);
      for (final position in PlayerPosition.values) {
        expect(playerPositionFromDb(playerPositionToDb(position)), position);
      }
    });

    test('a code outside the vocabulary is the schema disagreeing', () {
      expect(() => playerPositionFromDb('SWEEPER'),
          throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('dateOnlyToDb', () {
    test('writes the date column form, zero-padded', () {
      expect(dateOnlyToDb(DateTime(1995, 4, 17)), '1995-04-17');
      expect(dateOnlyToDb(DateTime(2001, 12, 5)), '2001-12-05');
    });

    test('a time of day is not part of what is written', () {
      // The column is a `date`. Sent as an instant, a birthday east of
      // Greenwich arrives as the previous day.
      expect(dateOnlyToDb(DateTime(1995, 4, 17, 23, 30)), '1995-04-17');
    });
  });

  group('the player profile', () {
    test('reads the three inputs the player owns', () {
      final profile = playerProfileFromRow({
        'full_name': 'Salim Al Harthy',
        'phone': '+96890123456',
        'date_of_birth': '1995-04-17',
        'primary_position': 'GK',
        'secondary_position': 'DEF',
      });

      expect(profile.dateOfBirth, DateTime(1995, 4, 17));
      expect(profile.primaryPosition, PlayerPosition.gk);
      expect(profile.secondaryPosition, PlayerPosition.def);
      expect(profile.isComplete, isTrue);
    });

    test('the account fields come off the same row', () {
      final profile = playerProfileFromRow({
        'full_name': 'Salim Al Harthy',
        'phone': '+96890123456',
        'primary_position': 'MID',
      });

      expect(profile.fullName, 'Salim Al Harthy');
      expect(profile.phone, '+96890123456');
    });

    test('the avatar url is the adapter\'s to supply, not the row\'s', () {
      // The bucket and the host are provider knowledge; the row carries only a
      // path, so the URL arrives beside it rather than inside it.
      final withPicture = playerProfileFromRow(
        {
          'full_name': 'Salim',
          'phone': '+96890123456',
          'primary_position': 'MID',
        },
        avatarUrl: 'https://example.test/u1/avatar.jpg',
      );
      final without = playerProfileFromRow({
        'full_name': 'Salim',
        'phone': '+96890123456',
        'primary_position': 'MID',
      });

      expect(withPicture.avatarUrl, 'https://example.test/u1/avatar.jpg');
      expect(without.avatarUrl, isNull);
    });

    test('an unfinished profile keeps its gaps', () {
      final profile = playerProfileFromRow({
        'full_name': 'Salim Al Harthy',
        'phone': '+96890123456',
        'date_of_birth': null,
        'primary_position': 'MID',
        'secondary_position': null,
      });

      expect(profile.dateOfBirth, isNull);
      expect(profile.secondaryPosition, isNull);
      expect(profile.isComplete, isFalse);
    });

    test('age is derived from the date of birth as of a given day', () {
      final profile = _ageFixture;

      // The day before the birthday and the day of it.
      expect(profile.ageOn(DateTime(2026, 4, 16)), 30);
      expect(profile.ageOn(DateTime(2026, 4, 17)), 31);
    });

    test('a profile with no date of birth has no age', () {
      const profile = PlayerProfile(
        fullName: 'Salim',
        phone: '+96890123456',
        primaryPosition: PlayerPosition.mid,
      );

      expect(profile.ageOn(DateTime(2026, 4, 17)), isNull,
          reason: '§4.3 refuses a substituted input, and zero would be one');
    });

    test('the account write carries the two columns and no others', () {
      final row = accountUpdateToRow(
        fullName: 'Salim Al Harthy',
        phone: '+96890123456',
      );

      expect(row, {'full_name': 'Salim Al Harthy', 'phone': '+96890123456'});
      // The playing inputs are written by their own call, so a name change can
      // never rewrite the date of birth the engine depends on.
      expect(row.containsKey('date_of_birth'), isFalse);
      expect(row.containsKey('overall_rating'), isFalse);
    });

    test('removing a picture writes the absence itself', () {
      expect(avatarUpdateToRow('u1/avatar.jpg'),
          {'avatar_path': 'u1/avatar.jpg'});
      expect(avatarUpdateToRow(null), {'avatar_path': null});
    });

    test('a write carries the three columns and no others', () {
      final row = profileUpdateToRow(
        dateOfBirth: DateTime(1995, 4, 17),
        primaryPosition: PlayerPosition.gk,
        secondaryPosition: PlayerPosition.def,
      );

      expect(row, {
        'date_of_birth': '1995-04-17',
        'primary_position': 'GK',
        'secondary_position': 'DEF',
      });
      // OP-1 makes the rating system-managed and the column default sets it.
      // A payload that cannot carry it is what keeps a screen from sending one.
      expect(row.containsKey('overall_rating'), isFalse);
    });

    test('no secondary position is written as the absence itself', () {
      final row = profileUpdateToRow(
        dateOfBirth: DateTime(1995, 4, 17),
        primaryPosition: PlayerPosition.gk,
        secondaryPosition: null,
      );

      expect(row['secondary_position'], isNull,
          reason: 'migration 0018 chose null over a NONE value, so clearing '
              'writes null rather than inventing one');
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

    // Migration 0051. A Professional Guest has no profile for a position to be
    // derived against, so their lineup row carries none — and `Position` gains
    // no fifth value to say so, because it is the engine's enum and the engine
    // never sees a guest.
    group('a lineup row for either kind of participant', () {
      Map<String, dynamic> row({
        String? userId,
        String? guestId,
        String? position,
        String basis = 'TRANSITION',
      }) =>
          {
            'user_id': userId,
            'professional_guest_id': guestId,
            'team': 'A',
            'assigned_position': position,
            'assignment_basis': basis,
          };

      test('1. a registered player keeps their position', () {
        final assignment =
            teamAssignmentFromRow(row(userId: 'u1', position: 'DEF'));

        expect(assignment.userId, 'u1');
        expect(assignment.professionalGuestId, isNull);
        expect(assignment.assignedPosition, Position.def);
        expect(assignment.basis, AssignmentBasis.transition);
        expect(assignment.isProfessionalGuest, isFalse);
      });

      test('2/3. a guest has no position and the GUEST basis', () {
        final assignment = teamAssignmentFromRow(
          row(guestId: 'g1', position: null, basis: 'GUEST'),
        );

        expect(assignment.professionalGuestId, 'g1');
        expect(assignment.userId, isNull);
        expect(assignment.assignedPosition, isNull,
            reason: 'the absence of a position, never an invented MID');
        expect(assignment.basis, isNull,
            reason: 'GUEST reads as null: AssignmentBasis is the engine\'s');
        expect(assignment.isProfessionalGuest, isTrue);
        expect(assignment.outOfPosition, isFalse,
            reason: 'no position of theirs to be out of');
      });

      test('a guest an administrator gave a position keeps it', () {
        final assignment = teamAssignmentFromRow(
          row(guestId: 'g1', position: 'GK', basis: 'GUEST'),
        );

        expect(assignment.assignedPosition, Position.gk,
            reason: 'optional for a guest, not forbidden');
      });

      test('null travels back as null, and a position as itself', () {
        expect(
          teamAssignmentToRow(const TeamAssignment(
            professionalGuestId: 'g1',
            team: TeamId.b,
            assignedPosition: null,
            basis: null,
          )),
          {
            'professional_guest_id': 'g1',
            'team': 'B',
            'assigned_position': null,
            'assignment_basis': 'GUEST',
          },
        );

        expect(
          teamAssignmentToRow(const TeamAssignment(
            userId: 'u1',
            team: TeamId.a,
            assignedPosition: Position.mid,
            basis: AssignmentBasis.primary,
          )),
          {
            'user_id': 'u1',
            'team': 'A',
            'assigned_position': 'MID',
            'assignment_basis': 'PRIMARY',
          },
        );
      });
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

      // No match_id: `replace_match_lineup` takes the match as its own
      // argument, so a row never names one.
      expect(teamAssignmentToRow(teamAssignmentFromRow(row)), row);
    });

    test('out of position is derived, never written', () {
      final row = teamAssignmentToRow(teamAssignmentFromRow(const {
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

  group('ratingChangeReasonFromDb', () {
    test('reads the whole vocabulary of migration 0022', () {
      expect(ratingChangeReasonFromDb('WIN'), RatingChangeReason.win);
      expect(ratingChangeReasonFromDb('LOSS'), RatingChangeReason.loss);
      expect(ratingChangeReasonFromDb('GOAL'), RatingChangeReason.goal);
      expect(ratingChangeReasonFromDb('MVP'), RatingChangeReason.mvp);
      expect(ratingChangeReasonFromDb('REVERSAL'),
          RatingChangeReason.reversal);
    });

    test('anything else is the schema disagreeing with this build', () {
      expect(() => ratingChangeReasonFromDb('BONUS'),
          throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('the recorded result', () {
    test('a result row reads into the model, goals and all', () {
      final result = matchResultFromRow(const {
        'match_id': 'm1',
        'team_a_score': 3,
        'team_b_score': 1,
        'mvp_user_id': 'u2',
        'goals': [
          {'user_id': 'u2', 'goals': 2},
          {'user_id': 'u3', 'goals': 1},
          {'user_id': 'u4', 'goals': 1},
        ],
      });

      expect(result.matchId, 'm1');
      expect(result.teamAScore, 3);
      expect(result.teamBScore, 1);
      expect(result.mvpUserId, 'u2');
      expect(result.recordedGoals, 4);
      expect(result.goalsBy('u2'), 2);
    });

    test('a goalless match reads as no scorers, not as missing', () {
      final result = matchResultFromRow(const {
        'match_id': 'm1',
        'team_a_score': 0,
        'team_b_score': 0,
        'mvp_user_id': 'u2',
        'goals': <Map<String, dynamic>>[],
      });

      expect(result.goals, isEmpty);
      expect(result.recordedGoals, 0);
      expect(result.isDraw, isTrue);
    });

    test('a tally writes back the row it was read from', () {
      const row = {'user_id': 'u1', 'goals': 2};

      // No match_id: `record_match_result` takes the match as its own
      // argument, so a tally never names one.
      expect(goalTallyToRow(goalTallyFromRow(row)), row);
    });
  });

  group('ratingChangeFromRow', () {
    test('an entry reads into the model', () {
      final change = ratingChangeFromRow(const {
        'id': 'h1',
        'user_id': 'u1',
        'match_id': 'm1',
        'change_reason': 'WIN',
        'delta': 0.10,
        'rating_before': 5.00,
        'rating_after': 5.10,
        'reverses_id': null,
        'created_at': '2026-07-01T19:00:00Z',
      });

      expect(change.id, 'h1');
      expect(change.reason, RatingChangeReason.win);
      expect(change.delta, 0.10);
      expect(change.ratingBefore, 5.00);
      expect(change.ratingAfter, 5.10);
      expect(change.reversesId, isNull);
      expect(change.isReversal, isFalse);
    });

    test('a numeric that arrives as text still reads', () {
      final change = ratingChangeFromRow(const {
        'id': 'h2',
        'user_id': 'u1',
        'match_id': 'm1',
        'change_reason': 'REVERSAL',
        'delta': '-0.10',
        'rating_before': '5.10',
        'rating_after': '5.00',
        'reverses_id': 'h1',
        'created_at': '2026-07-01T19:00:00Z',
      });

      expect(change.delta, -0.10);
      expect(change.isReversal, isTrue);
      expect(change.reversesId, 'h1');
    });
  });

  group('playerStatisticsFromRow', () {
    // The row is a `v_user_profile` row: the counters are flat columns beside
    // the profile, not a nested object, because the view LEFT-joins them.
    test('a profile with counters reads both', () {
      final statistics = playerStatisticsFromRow(const {
        'user_id': 'u1',
        'overall_rating': 5.35,
        'matches_played': 4,
        'wins': 2,
        'losses': 1,
        'draws': 1,
        'goals': 5,
        'mvp_count': 1,
      });

      expect(statistics.userId, 'u1');
      expect(statistics.matchesPlayed, 4);
      expect(statistics.wins, 2);
      expect(statistics.losses, 1);
      expect(statistics.draws, 1);
      expect(statistics.goals, 5);
      expect(statistics.mvpCount, 1);
      expect(statistics.currentRating, 5.35);
    });

    test('a player with no counters starts at zero, keeping their rating', () {
      // The absence of a counters row is the starting point, not a missing
      // record: nobody has finished a match yet. Through the view that absence
      // arrives as every counter column being null at once.
      final statistics = playerStatisticsFromRow(const {
        'user_id': 'u1',
        'overall_rating': 5.0,
        'matches_played': null,
        'wins': null,
        'losses': null,
        'draws': null,
        'goals': null,
        'mvp_count': null,
      });

      expect(statistics.userId, 'u1');
      expect(statistics.matchesPlayed, 0);
      expect(statistics.mvpCount, 0);
      expect(statistics.currentRating, 5.0);
    });
  });
}

/// A profile whose only interesting field is the date of birth: age is derived
/// from it and from nothing else (`KB-C7`).
final _ageFixture = PlayerProfile(
  fullName: 'Salim Al Harthy',
  phone: '+96890123456',
  primaryPosition: PlayerPosition.mid,
  dateOfBirth: DateTime(1995, 4, 17),
);
