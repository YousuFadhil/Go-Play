import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/invitations/invite_link.dart';
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
    });
  });



  group('JoinPolicy', () {
    test('reads both values', () {
      expect(JoinPolicy.fromDb('OPEN'), JoinPolicy.open);
      expect(JoinPolicy.fromDb('CODE_REQUIRED'), JoinPolicy.codeRequired);
    });

    test('an unknown policy is treated as the stricter one', () {
      expect(JoinPolicy.fromDb('SOMETHING_NEW'), JoinPolicy.codeRequired,
          reason: 'a policy the app cannot read must not open the door');
    });
  });

  group('Community.fromJson', () {
    test('reads the row the repository selects', () {
      final community = Community.fromJson(const {
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
      final community = Community.fromJson(const {
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




  group('InviteLink', () {
    // Twelve characters from the join-code alphabet, which omits I, L, O, 0
    // and 1 because people mistype them.
    const code = 'ABCDEFGH2345';

    test('shares the web form, so it survives the domain landing', () {
      expect(InviteLink.format(code), 'https://goplay.app/join/$code');
    });

    test('the app scheme is what opens the app today', () {
      expect(InviteLink.appLink(code), 'goplay://join/$code');
    });

    test('reads a code back out of either link shape', () {
      expect(InviteLink.parse('https://goplay.app/join/$code'), code);
      expect(InviteLink.parse('goplay://join/$code'), code);
    });

    test('accepts a bare code, since a link can arrive flattened to text', () {
      expect(InviteLink.parse(code), code);
    });

    test('finds the link inside a pasted message', () {
      expect(
        InviteLink.parse('Join us on Go Play:\nhttps://goplay.app/join/$code\n'),
        code,
      );
    });

    test('normalises case, so a code read aloud and retyped still works', () {
      expect(InviteLink.parse(code.toLowerCase()), code);
    });

    test('rejects anything that is not a code', () {
      expect(InviteLink.parse(null), isNull);
      expect(InviteLink.parse('   '), isNull);
      expect(InviteLink.parse('ABC'), isNull, reason: 'too short');
      // An unrelated URL must not have a code read out of its path.
      expect(InviteLink.parse('https://example.com/ABCDEFGH2345'), isNull);
      // The excluded glyphs are not in the alphabet.
      expect(InviteLink.parse('ABCDEFGHI011'), isNull);
    });
  });


  group('PendingInvite', () {
    tearDown(PendingInvite.instance.clear);

    test('holds a code offered as a link', () {
      PendingInvite.instance.offer('https://goplay.app/join/ABCDEFGH2345');
      expect(PendingInvite.instance.code.value, 'ABCDEFGH2345');
    });

    test('ignores a route that is not an invitation', () {
      PendingInvite.instance.offer('/');
      expect(PendingInvite.instance.code.value, isNull);
    });

    test('keeps the previous code when handed nonsense', () {
      PendingInvite.instance.offer('ABCDEFGH2345');
      PendingInvite.instance.offer('nonsense');
      expect(PendingInvite.instance.code.value, 'ABCDEFGH2345',
          reason: 'an unrelated route must not cancel a real invitation');
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


}
