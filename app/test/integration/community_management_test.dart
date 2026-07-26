@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// PD-10 (who may invite as what), PD-11 (who may remove whom, and what it
/// does to their matches) and PD-12 (who may leave), plus the invitation
/// lifecycle and ownership transfer.
void main() {
  if (!integrationConfigured) {
    test('community management', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser outsider;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Management');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
  });

  tearDown(() async {
    // Ownership may have moved during a test, so try both.
    await disposeCommunity(owner, communityId);
    await disposeCommunity(admin, communityId);
  });

  Future<String> inviteAs(TestUser inviter, TestUser invitee, String role) =>
      outcomeOf(() async {
        await inviter.client.rpc('create_invitation', params: {
          'p_community_id': communityId,
          'p_invitee_id': invitee.id,
          'p_role': role,
        });
      });

  Future<String?> pendingInvitationFor(TestUser invitee) async {
    final rows = await invitee.client
        .from('invitations')
        .select('id')
        .eq('invitee_id', invitee.id)
        .eq('community_id', communityId)
        .eq('status', 'pending');
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<String?> roleOf(TestUser user) async {
    final row = await owner.client
        .from('community_members')
        .select('role')
        .eq('community_id', communityId)
        .eq('user_id', user.id)
        .maybeSingle();
    return row?['role'] as String?;
  }

  group('who may invite as what (PD-10)', () {
    test('an owner may invite as admin', () async {
      expect(await inviteAs(owner, outsider, 'admin'), 'ALLOW');
    });

    test('an admin may invite as player', () async {
      expect(await inviteAs(admin, outsider, 'player'), 'ALLOW');
    });

    test('an admin may not invite as admin', () async {
      expect(await inviteAs(admin, outsider, 'admin'), 'NOT_AUTHORIZED');
    });

    test('a player may not invite at all', () async {
      expect(await inviteAs(player, outsider, 'player'), 'NOT_AUTHORIZED');
    });

    test('nobody may invite as owner', () async {
      expect(await inviteAs(owner, outsider, 'owner'), 'INVALID_ROLE');
    });

    test('an existing member cannot be invited', () async {
      expect(await inviteAs(owner, player, 'player'), 'ALREADY_MEMBER');
    });

    test('a second pending invitation is refused', () async {
      expect(await inviteAs(owner, outsider, 'player'), 'ALLOW');
      expect(await inviteAs(owner, outsider, 'player'), 'INVITATION_EXISTS');
    });
  });

  group('invitation lifecycle', () {
    test('only the invitee can accept, and the role is applied', () async {
      await inviteAs(owner, outsider, 'admin');
      final invitationId = await pendingInvitationFor(outsider);
      expect(invitationId, isNotNull);

      // An admin can see the invitation but is not the invitee.
      final wrongUser = await outcomeOf(() async {
        await admin.client.rpc('accept_invitation',
            params: {'p_invitation_id': invitationId});
      });
      expect(wrongUser, 'NOT_AUTHORIZED');

      final accepted = await outcomeOf(() async {
        await outsider.client.rpc('accept_invitation',
            params: {'p_invitation_id': invitationId});
      });
      expect(accepted, 'ALLOW');
      expect(await roleOf(outsider), 'admin',
          reason: 'the invited role is what the membership gets');

      // Leave again so the fixture is stable for the next test.
      await outsider.client
          .from('community_members')
          .delete()
          .eq('community_id', communityId)
          .eq('user_id', outsider.id);
    });

    test('accepting twice is refused', () async {
      await inviteAs(owner, outsider, 'player');
      final invitationId = await pendingInvitationFor(outsider);
      await outsider.client
          .rpc('accept_invitation', params: {'p_invitation_id': invitationId});

      final second = await outcomeOf(() async {
        await outsider.client.rpc('accept_invitation',
            params: {'p_invitation_id': invitationId});
      });
      expect(second, 'INVITATION_NOT_PENDING');

      await outsider.client
          .from('community_members')
          .delete()
          .eq('community_id', communityId)
          .eq('user_id', outsider.id);
    });

    test('a revoked invitation cannot be accepted', () async {
      await inviteAs(owner, outsider, 'player');
      final invitationId = await pendingInvitationFor(outsider);

      expect(
        await outcomeOf(() async {
          await admin.client.rpc('revoke_invitation',
              params: {'p_invitation_id': invitationId});
        }),
        'ALLOW',
        reason: 'an admin may revoke',
      );
      expect(
        await outcomeOf(() async {
          await outsider.client.rpc('accept_invitation',
              params: {'p_invitation_id': invitationId});
        }),
        'INVITATION_NOT_PENDING',
      );
    });

    test('a player cannot revoke an invitation', () async {
      await inviteAs(owner, outsider, 'player');
      final invitationId = await pendingInvitationFor(outsider);
      final result = await outcomeOf(() async {
        await player.client
            .rpc('revoke_invitation', params: {'p_invitation_id': invitationId});
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('an invitation is visible to its invitee and to organizers only',
        () async {
      await inviteAs(owner, outsider, 'player');

      final asInvitee = await outsider.client
          .from('invitations')
          .select('id')
          .eq('community_id', communityId);
      final asAdmin = await admin.client
          .from('invitations')
          .select('id')
          .eq('community_id', communityId);
      final asPlayer = await player.client
          .from('invitations')
          .select('id')
          .eq('community_id', communityId);

      expect(asInvitee, isNotEmpty);
      expect(asAdmin, isNotEmpty);
      expect(asPlayer, isEmpty);
    });
  });

  group('leaving (PD-12)', () {
    Future<int> leave(TestUser user) async {
      final rows = await user.client
          .from('community_members')
          .delete()
          .eq('community_id', communityId)
          .eq('user_id', user.id)
          .select();
      return rows.length;
    }

    test('a player may leave', () async {
      expect(await leave(player), 1);
    });

    test('an admin may leave', () async {
      expect(await leave(admin), 1);
    });

    test('an owner may not', () async {
      expect(await leave(owner), 0,
          reason: 'ownership has to move first');
    });
  });

  group('removing a member (PD-11)', () {
    test('an admin may remove a player', () async {
      final result = await outcomeOf(() async {
        await admin.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': player.id,
        });
      });
      expect(result, 'ALLOW');
      expect(await roleOf(player), isNull);
    });

    test('an admin may not remove another admin', () async {
      await addMember(owner, communityId, outsider, role: 'admin');
      final result = await outcomeOf(() async {
        await admin.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': outsider.id,
        });
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('an owner may remove an admin', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': admin.id,
        });
      });
      expect(result, 'ALLOW');
      expect(await roleOf(admin), isNull);
    });

    test('the owner cannot be removed', () async {
      final result = await outcomeOf(() async {
        await admin.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': owner.id,
        });
      });
      expect(result, 'CANNOT_REMOVE_OWNER');
    });

    test('nobody removes themselves through this path', () async {
      final result = await outcomeOf(() async {
        await admin.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': admin.id,
        });
      });
      expect(result, 'CANNOT_REMOVE_SELF');
    });

    test('a player cannot remove anyone', () async {
      final result = await outcomeOf(() async {
        await player.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': admin.id,
        });
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('removal withdraws them from the community\'s matches and promotes '
        'the reserve', () async {
      // Two seats: player and admin start, owner waits in reserve.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 4), startingPlayers: 2);
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      await admin.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      await owner.client
          .rpc('register_for_match', params: {'p_match_id': matchId});

      await owner.client.rpc('remove_member', params: {
        'p_community_id': communityId,
        'p_user_id': player.id,
      });

      final rows = await owner.client
          .from('match_registrations')
          .select('user_id, status')
          .eq('match_id', matchId);

      expect(rows.where((r) => r['user_id'] == player.id), isEmpty,
          reason: 'the removed member leaves the roster too');
      final ownerRow = rows.firstWhere((r) => r['user_id'] == owner.id);
      expect(ownerRow['status'], 'confirmed',
          reason: 'the freed seat goes to the first reserve');
    });
  });

  group('ownership transfer', () {
    test('an admin cannot transfer ownership', () async {
      final result = await outcomeOf(() async {
        await admin.client.rpc('transfer_ownership', params: {
          'p_community_id': communityId,
          'p_new_owner_id': admin.id,
        });
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('ownership cannot go to a non-member', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('transfer_ownership', params: {
          'p_community_id': communityId,
          'p_new_owner_id': outsider.id,
        });
      });
      expect(result, 'MEMBER_NOT_FOUND');
    });

    test('the owner cannot transfer to themselves', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('transfer_ownership', params: {
          'p_community_id': communityId,
          'p_new_owner_id': owner.id,
        });
      });
      expect(result, 'ALREADY_OWNER');
    });

    test('transfer promotes the new owner, demotes the old one to admin, '
        'and leaves exactly one owner', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('transfer_ownership', params: {
          'p_community_id': communityId,
          'p_new_owner_id': admin.id,
        });
      });
      expect(result, 'ALLOW');

      expect(await roleOf(admin), 'owner');
      expect(await roleOf(owner), 'admin');

      final owners = await admin.client
          .from('community_members')
          .select('user_id')
          .eq('community_id', communityId)
          .eq('role', 'owner');
      expect(owners, hasLength(1));

      // owner_id is a derived reporting field and must follow (PD-15).
      final row = await admin.client
          .from('communities')
          .select('owner_id')
          .eq('id', communityId)
          .single();
      expect(row['owner_id'], admin.id);

      // The former owner can no longer delete the community.
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('delete_community',
              params: {'p_community_id': communityId});
        }),
        'NOT_AUTHORIZED',
      );
    });
  });

  test('deleting a community removes everything under it', () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4));
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    await inviteAs(owner, outsider, 'player');

    await owner.client
        .rpc('delete_community', params: {'p_community_id': communityId});

    final community = await owner.client
        .from('communities')
        .select('id')
        .eq('id', communityId);
    final members = await owner.client
        .from('community_members')
        .select('user_id')
        .eq('community_id', communityId);
    final matches =
        await owner.client.from('matches').select('id').eq('id', matchId);

    expect(community, isEmpty);
    expect(members, isEmpty);
    expect(matches, isEmpty);
  });

  group('visibility', () {
    Future<bool?> isPrivate() async {
      final rows = await owner.client
          .from('communities')
          .select('is_private')
          .eq('id', communityId);
      return rows.single['is_private'] as bool?;
    }

    /// What the discovery list actually returns: RLS only exposes public
    /// communities there, so this is the real test of the setting.
    Future<bool> discoverableBy(TestUser user) async {
      final rows = await user.client
          .from('communities')
          .select('id')
          .eq('is_private', false)
          .eq('id', communityId);
      return rows.isNotEmpty;
    }

    test('the owner can switch a community to public and back', () async {
      expect(await isPrivate(), isTrue,
          reason: 'the fixture is created private');
      expect(await discoverableBy(outsider), isFalse);

      await owner.client
          .from('communities')
          .update({'is_private': false})
          .eq('id', communityId);
      expect(await isPrivate(), isFalse);
      expect(await discoverableBy(outsider), isTrue,
          reason: 'a public community is what discovery is for');

      await owner.client
          .from('communities')
          .update({'is_private': true})
          .eq('id', communityId);
      expect(await isPrivate(), isTrue);
      expect(await discoverableBy(outsider), isFalse);
    });

    test('an admin cannot change visibility', () async {
      final rows = await admin.client
          .from('communities')
          .update({'is_private': false})
          .eq('id', communityId)
          .select('id');
      expect(rows, isEmpty,
          reason: 'RLS filters the row out rather than raising, which is why '
              'the repository asks for the row back');
      expect(await isPrivate(), isTrue, reason: 'and nothing changed');
    });

    test('a player cannot change visibility', () async {
      final rows = await player.client
          .from('communities')
          .update({'is_private': false})
          .eq('id', communityId)
          .select('id');
      expect(rows, isEmpty);
      expect(await isPrivate(), isTrue);
    });

    test('an invite link keeps working across a visibility change', () async {
      final token = await owner.client.rpc('create_invite_link', params: {
        'p_community_id': communityId,
        'p_match_id': null,
      }) as String;

      // Public, then private again: the link is a bearer token either way.
      for (final private in [false, true]) {
        await owner.client
            .from('communities')
            .update({'is_private': private})
            .eq('id', communityId);
        final rows = await outsider.client
            .rpc('preview_invite_link', params: {'p_token': token})
            as List<dynamic>;
        expect((rows.first as Map<String, dynamic>)['state'], 'valid',
            reason: 'visibility does not gate an invitation');
      }

      final result = await outsider.client
          .rpc('redeem_invite_link', params: {'p_token': token})
          as List<dynamic>;
      expect((result.first as Map<String, dynamic>)['community_id'],
          communityId);
    });
  });
}
