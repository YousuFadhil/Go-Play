@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// PD-11 (who may remove whom, and what it does to their matches) and PD-12
/// (who may leave), plus ownership transfer and visibility.
///
/// PD-10 is gone with the directed invitation it governed: there is one way
/// into a community now, the join code, and it always grants player.
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


  Future<String?> roleOf(TestUser user) async {
    final row = await owner.client
        .from('community_members')
        .select('role')
        .eq('community_id', communityId)
        .eq('user_id', user.id)
        .maybeSingle();
    return row?['role'] as String?;
  }



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
    // A window no other test file uses: the four accounts are shared, and the
    // files run concurrently, so a match at the same hour as another file's
    // would fail the overlap rule rather than the thing under test.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 12));
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});

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

  group('join policy', () {
    Future<String> policy() async => (await owner.client
        .from('communities')
        .select('join_policy')
        .eq('id', communityId)
        .single())['join_policy'] as String;

    /// Everyone can see every community now; the policy only decides how a
    /// non-member gets in.
    Future<bool> visibleTo(TestUser user) async {
      final rows = await user.client
          .from('communities')
          .select('id')
          .eq('id', communityId);
      return rows.isNotEmpty;
    }

    test('a community is visible to everyone under either policy', () async {
      expect(await policy(), 'CODE_REQUIRED');
      expect(await visibleTo(outsider), isTrue,
          reason: 'code required is not hidden');

      await owner.client
          .from('communities')
          .update({'join_policy': 'OPEN'})
          .eq('id', communityId);
      expect(await visibleTo(outsider), isTrue);
    });

    test('OPEN can be joined directly; CODE_REQUIRED cannot', () async {
      expect(
        await outcomeOf(() async {
          await outsider.client.rpc('join_community',
              params: {'p_community_id': communityId});
        }),
        'JOIN_CODE_REQUIRED',
      );

      await owner.client
          .from('communities')
          .update({'join_policy': 'OPEN'})
          .eq('id', communityId);

      final joined = await outsider.client
          .rpc('join_community', params: {'p_community_id': communityId});
      expect(joined, communityId);
    });

    test('the code works under either policy, which is what a link carries',
        () async {
      final code = (await owner.client
          .from('communities')
          .select('join_code')
          .eq('id', communityId)
          .single())['join_code'] as String;

      for (final value in ['CODE_REQUIRED', 'OPEN']) {
        await owner.client
            .from('communities')
            .update({'join_policy': value})
            .eq('id', communityId);
        final rows = await outsider.client
            .rpc('preview_community_invite', params: {'p_code': code})
            as List<dynamic>;
        expect((rows.first as Map<String, dynamic>)['state'], 'valid');
      }

      final joined = await outsider.client
          .rpc('join_community_by_code', params: {'p_code': code});
      expect(joined, communityId);
    });

    test('an admin and a player cannot change the policy', () async {
      for (final user in [admin, player]) {
        final rows = await user.client
            .from('communities')
            .update({'join_policy': 'OPEN'})
            .eq('id', communityId)
            .select('id');
        expect(rows, isEmpty);
      }
      expect(await policy(), 'CODE_REQUIRED', reason: 'and nothing changed');
    });

    test('an invalid policy is refused at creation', () async {
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('create_community', params: {
            'p_name': 'ITest Bad Policy',
            'p_description': null,
            'p_join_policy': 'SOMETHING_ELSE',
          });
        }),
        'INVALID_JOIN_POLICY',
      );
    });
  });

  group('regenerating the join code', () {
    Future<String> codeOf() async => (await owner.client
        .from('communities')
        .select('join_code')
        .eq('id', communityId)
        .single())['join_code'] as String;

    Future<String> regenerateAs(TestUser user) async =>
        await user.client.rpc('regenerate_join_code',
            params: {'p_community_id': communityId}) as String;

    test('the owner gets a new code, and the old one stops working', () async {
      final before = await codeOf();
      final issued = await regenerateAs(owner);

      expect(issued, isNot(before));
      expect(issued, await codeOf(), reason: 'the RPC returns what it stored');
      expect(issued, hasLength(12));
      expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$').hasMatch(issued),
          isTrue,
          reason: 'same alphabet as every other code');

      // The old code is gone, not merely superseded.
      final preview = await outsider.client
          .rpc('preview_community_invite', params: {'p_code': before})
          as List<dynamic>;
      expect((preview.first as Map<String, dynamic>)['state'], 'not_found');
      expect(
        await outcomeOf(() async {
          await outsider.client
              .rpc('join_community_by_code', params: {'p_code': before});
        }),
        'COMMUNITY_NOT_FOUND',
      );
    });

    test('the new code works immediately', () async {
      final issued = await regenerateAs(owner);

      final preview = await outsider.client
          .rpc('preview_community_invite', params: {'p_code': issued})
          as List<dynamic>;
      expect((preview.first as Map<String, dynamic>)['state'], 'valid');

      final joined = await outsider.client
          .rpc('join_community_by_code', params: {'p_code': issued});
      expect(joined, communityId);
    });

    test('an admin may regenerate; a player and an outsider may not', () async {
      expect(await outcomeOf(() => regenerateAs(admin)), 'ALLOW');
      expect(await outcomeOf(() => regenerateAs(player)), 'NOT_AUTHORIZED');
      expect(await outcomeOf(() => regenerateAs(outsider)), 'NOT_AUTHORIZED');
    });

    test('nothing else about the community changes', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 14));
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});

      Future<List<dynamic>> members() async => await owner.client
          .from('community_members')
          .select('user_id, role')
          .eq('community_id', communityId)
          .order('user_id', ascending: true);
      Future<List<dynamic>> registrations() async => await owner.client
          .from('match_registrations')
          .select('user_id, status')
          .eq('match_id', matchId);

      final membersBefore = await members();
      final registrationsBefore = await registrations();
      final community = await owner.client
          .from('communities')
          .select('name, description, join_policy, owner_id')
          .eq('id', communityId)
          .single();

      await regenerateAs(owner);

      expect(await members(), membersBefore,
          reason: 'people already in stay in, with the roles they had');
      expect(await registrations(), registrationsBefore,
          reason: 'the code controls joining, not registering');
      expect(
        await owner.client
            .from('communities')
            .select('name, description, join_policy, owner_id')
            .eq('id', communityId)
            .single(),
        community,
        reason: 'and nothing else on the community moved',
      );
      final match = await owner.client
          .from('matches')
          .select('id')
          .eq('id', matchId);
      expect(match, hasLength(1));
    });
  });
}
