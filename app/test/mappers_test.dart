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
}
