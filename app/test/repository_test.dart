import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/communities/community_errors.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/invitations/invitation_models.dart';
import 'package:go_play/features/invitations/invitation_repository.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A client pointed at nowhere. Constructing it performs no I/O, so it is
/// enough to prove the repositories take an injected client and to exercise
/// the paths that return before any request is made.
SupabaseClient stubClient() =>
    SupabaseClient('https://stub.invalid', 'stub-key');

void main() {
  group('constructor injection', () {
    test('each repository accepts an injected client', () {
      final client = stubClient();
      expect(CommunityRepository(client), isA<CommunityRepository>());
      expect(MemberRepository(client), isA<MemberRepository>());
      expect(InvitationRepository(client), isA<InvitationRepository>());
    });
  });

  group('InvitationRepository.searchUsers', () {
    // Guards run before the query, so no request reaches the stub client.
    test('returns nothing for a query shorter than two characters', () async {
      final repository = InvitationRepository(stubClient());
      expect(await repository.searchUsers(''), isEmpty);
      expect(await repository.searchUsers('a'), isEmpty);
      expect(await repository.searchUsers('  b  '), isEmpty);
    });
  });

  group('communityActionErrorFrom', () {
    test('maps every RPC error code to its typed error', () {
      const cases = <String, CommunityActionError>{
        'NOT_AUTHORIZED': CommunityActionError.notAuthorized,
        'CANNOT_CHANGE_OWN_ROLE': CommunityActionError.cannotChangeOwnRole,
        'CANNOT_REMOVE_SELF': CommunityActionError.cannotRemoveSelf,
        'CANNOT_REMOVE_OWNER': CommunityActionError.cannotRemoveOwner,
        'ALREADY_OWNER': CommunityActionError.alreadyOwner,
        'MEMBER_NOT_FOUND': CommunityActionError.memberNotFound,
        'ALREADY_MEMBER': CommunityActionError.alreadyMember,
        'INVITATION_EXISTS': CommunityActionError.invitationExists,
        'INVITATION_NOT_FOUND': CommunityActionError.invitationNotFound,
        'INVITATION_NOT_PENDING': CommunityActionError.invitationNotPending,
        'INVITATION_EXPIRED': CommunityActionError.invitationExpired,
        'INVALID_ROLE': CommunityActionError.invalidRole,
      };
      cases.forEach((code, expected) {
        expect(communityActionErrorFrom(code), expected, reason: code);
      });
    });

    test('finds the code inside a full Postgres message', () {
      expect(
        communityActionErrorFrom(
            'postgrest: NOT_AUTHORIZED raised by set_member_role'),
        CommunityActionError.notAuthorized,
      );
    });

    test('falls back to unknown for anything unrecognised', () {
      expect(communityActionErrorFrom('connection reset'),
          CommunityActionError.unknown);
      expect(communityActionErrorFrom(''), CommunityActionError.unknown);
    });
  });

  group('Community.fromJson', () {
    test('reads the row the repository selects', () {
      final community = Community.fromJson(const {
        'id': 'c1',
        'owner_id': 'u1',
        'name': 'Friday Football',
        'description': 'Weekly game',
        'is_private': true,
        'join_code': 'AB12CD',
      });

      expect(community.id, 'c1');
      expect(community.ownerId, 'u1');
      expect(community.name, 'Friday Football');
      expect(community.description, 'Weekly game');
      expect(community.isPrivate, isTrue);
      expect(community.joinCode, 'AB12CD');
    });

    test('accepts a null description', () {
      final community = Community.fromJson(const {
        'id': 'c1',
        'owner_id': 'u1',
        'name': 'No description',
        'description': null,
        'is_private': false,
        'join_code': 'EF34GH',
      });
      expect(community.description, isNull);
    });
  });

  group('CommunityMember.fromJson', () {
    test('reads the joined profile and the role', () {
      final member = CommunityMember.fromJson(const {
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
      final member = CommunityMember.fromJson(const {
        'role': 'member',
        'user': {'id': 'u3', 'full_name': 'Ali', 'primary_position': 'GK'},
      });
      expect(member.role, CommunityRole.player);
    });
  });

  group('Invitation.fromJson', () {
    test('reads an invitation addressed to the current user', () {
      final invitation = Invitation.fromJson({
        'id': 'i1',
        'community_id': 'c1',
        'invitee_id': 'u4',
        'role': 'player',
        'status': 'pending',
        'expires_at':
            DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'community': const {'name': 'Friday Football'},
      });

      expect(invitation.id, 'i1');
      expect(invitation.role, CommunityRole.player);
      expect(invitation.status, InvitationStatus.pending);
      expect(invitation.communityName, 'Friday Football');
      expect(invitation.isActionable, isTrue);
    });

    test('an expired pending invitation is not actionable', () {
      final invitation = Invitation.fromJson({
        'id': 'i2',
        'community_id': 'c1',
        'invitee_id': 'u4',
        'role': 'player',
        'status': 'pending',
        'expires_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      });
      expect(invitation.status, InvitationStatus.pending);
      expect(invitation.isActionable, isFalse);
    });

    test('a revoked invitation is not actionable', () {
      final invitation = Invitation.fromJson({
        'id': 'i3',
        'community_id': 'c1',
        'invitee_id': 'u4',
        'role': 'admin',
        'status': 'revoked',
        'expires_at':
            DateTime.now().add(const Duration(days: 3)).toIso8601String(),
      });
      expect(invitation.status, InvitationStatus.revoked);
      expect(invitation.isActionable, isFalse);
    });

    test('reads the invitee name an organizer sees', () {
      final invitation = Invitation.fromJson({
        'id': 'i4',
        'community_id': 'c1',
        'invitee_id': 'u5',
        'role': 'player',
        'status': 'pending',
        'expires_at':
            DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'invitee': const {'full_name': 'Khalid'},
      });
      expect(invitation.inviteeName, 'Khalid');
    });
  });

  group('UserSummary.fromJson', () {
    test('reads a searchable profile', () {
      final user = UserSummary.fromJson(const {
        'id': 'u6',
        'full_name': 'Omar',
        'primary_position': 'FWD',
      });
      expect(user.id, 'u6');
      expect(user.fullName, 'Omar');
      expect(user.position, 'FWD');
    });
  });
}
