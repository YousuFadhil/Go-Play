import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/communities/community_errors.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/invitations/invitation_models.dart';
import 'package:go_play/features/invitations/invitation_repository.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
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

  group('InviteLink', () {
    test('formats a token as the app own link', () {
      expect(InviteLink.format('a' * 32), 'goplay://invite/${'a' * 32}');
    });

    test('reads a token back out of a link', () {
      const token = '0123456789abcdef0123456789abcdef';
      expect(InviteLink.parse('goplay://invite/$token'), token);
    });

    test('accepts a bare token, since some apps flatten the link to text', () {
      const token = '0123456789abcdef0123456789abcdef';
      expect(InviteLink.parse(token), token);
    });

    test('finds the link inside a pasted message', () {
      const token = 'abcdef0123456789abcdef0123456789';
      expect(
        InviteLink.parse('Join us on Go Play:\ngoplay://invite/$token\n'),
        token,
      );
    });

    test('normalises case so a retyped token still works', () {
      expect(InviteLink.parse('ABCDEF0123456789ABCDEF0123456789'),
          'abcdef0123456789abcdef0123456789');
    });

    test('rejects anything that is not token-shaped', () {
      expect(InviteLink.parse(null), isNull);
      expect(InviteLink.parse('   '), isNull);
      expect(InviteLink.parse('goplay://invite/short'), isNull);
      expect(InviteLink.parse('https://example.com/i/abc'), isNull);
      // 31 hex characters: one short, and not a token.
      expect(InviteLink.parse('a' * 31), isNull);
    });
  });

  group('PendingInvite', () {
    tearDown(PendingInvite.instance.clear);

    test('holds a token offered as a link', () {
      PendingInvite.instance.offer('goplay://invite/${'b' * 32}');
      expect(PendingInvite.instance.token.value, 'b' * 32);
    });

    test('ignores a route that is not an invitation', () {
      PendingInvite.instance.offer('/');
      expect(PendingInvite.instance.token.value, isNull);
    });

    test('keeps the previous token when handed nonsense', () {
      PendingInvite.instance.offer('c' * 32);
      PendingInvite.instance.offer('nonsense');
      expect(PendingInvite.instance.token.value, 'c' * 32,
          reason: 'an unrelated route must not cancel a real invitation');
    });
  });

  group('InviteLinkPreview.fromJson', () {
    test('reads a community-only invitation', () {
      final preview = InviteLinkPreview.fromJson(const {
        'state': 'valid',
        'community_id': 'c1',
        'community_name': 'Muscat FC',
        'match_id': null,
        'match_title': null,
        'match_location': null,
        'match_start_at': null,
        'match_end_at': null,
        'starting_players': null,
        'seats_remaining': null,
        'would_be_reserve': null,
        'is_member': false,
        'is_registered': false,
      });
      expect(preview.state, InviteLinkState.valid);
      expect(preview.isUsable, isTrue);
      expect(preview.hasMatch, isFalse);
      expect(preview.communityName, 'Muscat FC');
      expect(preview.wouldBeReserve, isFalse);
    });

    test('reads a match invitation, including the reserve warning', () {
      final preview = InviteLinkPreview.fromJson({
        'state': 'valid',
        'community_id': 'c1',
        'community_name': 'Muscat FC',
        'match_id': 'm1',
        'match_title': 'Friday game',
        'match_location': 'Al Amerat',
        'match_start_at': DateTime.utc(2026, 8, 1, 18).toIso8601String(),
        'match_end_at': DateTime.utc(2026, 8, 1, 20).toIso8601String(),
        'starting_players': 10,
        'seats_remaining': 3,
        'would_be_reserve': true,
        'is_member': true,
        'is_registered': false,
      });
      expect(preview.hasMatch, isTrue);
      expect(preview.matchTitle, 'Friday game');
      expect(preview.seatsRemaining, 3);
      expect(preview.wouldBeReserve, isTrue);
      expect(preview.isMember, isTrue);
      expect(preview.matchStartAt, isNotNull);
    });

    test('a revoked invitation carries its state and nothing else', () {
      final preview = InviteLinkPreview.fromJson(const {
        'state': 'revoked',
        'community_id': null,
        'community_name': null,
        'match_id': null,
        'match_title': null,
        'match_location': null,
        'match_start_at': null,
        'match_end_at': null,
        'starting_players': null,
        'seats_remaining': null,
        'would_be_reserve': null,
        'is_member': false,
        'is_registered': false,
      });
      expect(preview.state, InviteLinkState.revoked);
      expect(preview.isUsable, isFalse);
      expect(preview.communityName, isNull);
    });

    test('an unrecognised state is treated as not found', () {
      final preview =
          InviteLinkPreview.fromJson(const {'state': 'something_new'});
      expect(preview.state, InviteLinkState.notFound);
      expect(preview.isUsable, isFalse);
    });
  });

  group('InviteRedemption.fromJson', () {
    test('a confirmed place', () {
      final result = InviteRedemption.fromJson(const {
        'community_id': 'c1',
        'match_id': 'm1',
        'registration_status': 'confirmed',
        'failure_code': null,
      });
      expect(result.joinedMatch, isTrue);
      expect(result.registrationStatus, RegistrationStatus.confirmed);
      expect(result.registrationFailed, isFalse);
    });

    test('a reserve place is still a joined match', () {
      final result = InviteRedemption.fromJson(const {
        'community_id': 'c1',
        'match_id': 'm1',
        'registration_status': 'reserve',
        'failure_code': null,
      });
      expect(result.joinedMatch, isTrue);
      expect(result.registrationStatus, RegistrationStatus.reserve);
    });

    test('joined the community but not the match, with the reason', () {
      final result = InviteRedemption.fromJson(const {
        'community_id': 'c1',
        'match_id': 'm1',
        'registration_status': null,
        'failure_code': 'OVERLAPPING_MATCH',
      });
      expect(result.communityId, 'c1');
      expect(result.joinedMatch, isFalse);
      expect(result.registrationFailed, isTrue);
      expect(result.registrationFailure, RegistrationError.overlappingMatch);
    });

    test('an unrecognised reason still reaches the screen as a code', () {
      final result = InviteRedemption.fromJson(const {
        'community_id': 'c1',
        'match_id': 'm1',
        'registration_status': null,
        'failure_code': 'SOMETHING_NEW',
      });
      expect(result.registrationFailure, isNull);
      expect(result.failureCode, 'SOMETHING_NEW',
          reason: 'so the screen can say something true rather than nothing');
    });

    test('a community-only invitation has no registration at all', () {
      final result = InviteRedemption.fromJson(const {
        'community_id': 'c1',
        'match_id': null,
        'registration_status': null,
        'failure_code': null,
      });
      expect(result.matchId, isNull);
      expect(result.joinedMatch, isFalse);
      expect(result.registrationFailed, isFalse);
    });
  });

  group('registrationErrorFrom', () {
    test('maps every code the registration RPCs raise', () {
      expect(registrationErrorFrom('OVERLAPPING_MATCH'),
          RegistrationError.overlappingMatch);
      expect(
          registrationErrorFrom('MATCH_CLOSED'), RegistrationError.matchClosed);
      expect(registrationErrorFrom('ALREADY_REGISTERED'),
          RegistrationError.alreadyRegistered);
      expect(registrationErrorFrom('NOT_REGISTERED'),
          RegistrationError.notRegistered);
      expect(registrationErrorFrom('REGISTRATION_CLOSED'),
          RegistrationError.registrationClosed);
      expect(
          registrationErrorFrom('MATCH_LOCKED'), RegistrationError.matchLocked);
      expect(registrationErrorFrom('NOT_COMMUNITY_MEMBER'),
          RegistrationError.notCommunityMember);
      expect(registrationErrorFrom('SOMETHING_ELSE'), isNull);
    });
  });

  group('communityActionErrorFrom', () {
    test('tells an invite-link code apart from a directed-invitation one', () {
      expect(communityActionErrorFrom('INVITE_NOT_FOUND'),
          CommunityActionError.inviteNotFound);
      expect(communityActionErrorFrom('INVITATION_NOT_FOUND'),
          CommunityActionError.invitationNotFound);
      expect(communityActionErrorFrom('INVITE_EXPIRED'),
          CommunityActionError.inviteExpired);
      expect(communityActionErrorFrom('INVITATION_EXPIRED'),
          CommunityActionError.invitationExpired);
      expect(communityActionErrorFrom('INVITE_REVOKED'),
          CommunityActionError.inviteRevoked);
      expect(communityActionErrorFrom('INVITE_MATCH_DELETED'),
          CommunityActionError.inviteMatchDeleted);
    });
  });

  group('InviteLinkSummary.fromJson', () {
    Map<String, dynamic> row({
      String kind = 'community',
      Map<String, dynamic>? match,
    }) =>
        {
          'id': 'l1',
          'token': 'a' * 32,
          'kind': kind,
          'created_at': DateTime.utc(2026, 7, 1).toIso8601String(),
          'match': match,
        };

    test('a community link is live and has no match', () {
      final link = InviteLinkSummary.fromJson(row());
      expect(link.isMatchLink, isFalse);
      expect(link.isMatchDeleted, isFalse);
      expect(link.isExpired, isFalse);
      expect(link.isUsable, isTrue);
    });

    test('a match link before kick-off is live', () {
      final link = InviteLinkSummary.fromJson(row(kind: 'match', match: {
        'title': 'Friday game',
        'start_at':
            DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(),
      }));
      expect(link.isMatchLink, isTrue);
      expect(link.matchTitle, 'Friday game');
      expect(link.isUsable, isTrue);
    });

    test('a match link past kick-off has expired', () {
      final link = InviteLinkSummary.fromJson(row(kind: 'match', match: {
        'title': 'Friday game',
        'start_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      }));
      expect(link.isExpired, isTrue);
      expect(link.isMatchDeleted, isFalse);
      expect(link.isUsable, isFalse);
    });

    test('a match link with no match left reads as deleted, not as expired', () {
      final link = InviteLinkSummary.fromJson(row(kind: 'match'));
      expect(link.isMatchDeleted, isTrue,
          reason: 'kind survives the deletion, which is how the two differ');
      expect(link.isExpired, isFalse);
      expect(link.isUsable, isFalse);
    });
  });
}
