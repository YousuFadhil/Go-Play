@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The approved permission matrix (AMS v1.2 section 4.2), exercised as the
/// three roles against a live project. Denials matter as much as grants: a
/// permission that silently widens is the failure this suite exists to catch.
void main() {
  if (!integrationConfigured) {
    test('authorization matrix', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser outsider;
  late String communityId;
  late String publicId;
  late String matchId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Private');
    publicId = await createCommunity(owner, 'ITest Public', isPrivate: false);
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    // Created by the player so the tests prove management follows role and
    // not authorship (PD-07).
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 3));
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    await disposeCommunity(owner, publicId);
  });

  Future<String> updateMatchAs(TestUser user) => outcomeOf(() async {
        final start = DateTime.now().toUtc().add(const Duration(days: 3));
        await user.client.rpc('update_match', params: {
          'p_match_id': matchId,
          'p_title': null,
          'p_location': 'Moved pitch',
          'p_start_at': start.toIso8601String(),
          'p_end_at':
              start.add(const Duration(hours: 2)).toIso8601String(),
          'p_starting_players': 10,
          'p_description': null,
        });
      });

  Future<String> insertMatchAs(TestUser user) => outcomeOf(() async {
        final start = DateTime.now().toUtc().add(const Duration(days: 9));
        await user.client.from('matches').insert({
          'community_id': communityId,
          'created_by': user.id,
          'location': 'Attempted',
          'start_at': start.toIso8601String(),
          'end_at': start.add(const Duration(hours: 2)).toIso8601String(),
          'starting_players': 10,
        });
      });

  Future<int> updateSettingsAs(TestUser user) async {
    final rows = await user.client
        .from('communities')
        .update({'description': 'touched by ${user.label}'})
        .eq('id', communityId)
        .select();
    return rows.length;
  }

  group('community settings (PD-05)', () {
    test('the owner can edit them', () async {
      expect(await updateSettingsAs(owner), 1);
    });

    test('an admin cannot', () async {
      expect(await updateSettingsAs(admin), 0);
    });

    test('a player cannot', () async {
      expect(await updateSettingsAs(player), 0);
    });
  });

  group('creating a match (PD-06)', () {
    test('the owner can', () async {
      expect(await insertMatchAs(owner), 'ALLOW');
    });

    test('an admin can', () async {
      expect(await insertMatchAs(admin), 'ALLOW');
    });

    test('a player cannot', () async {
      expect(await insertMatchAs(player), isNot('ALLOW'));
    });

    test('an outsider cannot', () async {
      expect(await insertMatchAs(outsider), isNot('ALLOW'));
    });
  });

  group('managing a match follows role, not authorship (PD-07)', () {
    test('an admin can edit a match they did not create', () async {
      expect(await updateMatchAs(admin), 'ALLOW');
    });

    test('a player cannot edit it', () async {
      expect(await updateMatchAs(player), 'NOT_AUTHORIZED');
    });

    test('a player cannot remove someone from it', () async {
      final result = await outcomeOf(() async {
        await player.client.rpc('remove_player', params: {
          'p_match_id': matchId,
          'p_user_id': player.id,
        });
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('a player cannot delete it', () async {
      final result = await outcomeOf(() async {
        await player.client
            .rpc('delete_match', params: {'p_match_id': matchId});
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('an outsider cannot edit it', () async {
      expect(await updateMatchAs(outsider), 'NOT_AUTHORIZED');
    });
  });

  group('role assignment is the owner\'s (PD-02, PD-03)', () {
    test('the owner can promote a player to admin', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': player.id,
          'p_role': 'admin',
        });
      });
      expect(result, 'ALLOW');
    });

    test('an admin cannot change a role', () async {
      final result = await outcomeOf(() async {
        await admin.client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': player.id,
          'p_role': 'admin',
        });
      });
      expect(result, 'NOT_AUTHORIZED');
    });

    test('the owner can demote an admin back to player', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': admin.id,
          'p_role': 'player',
        });
      });
      expect(result, 'ALLOW');

      final rows = await owner.client
          .from('community_members')
          .select('role')
          .eq('community_id', communityId)
          .eq('user_id', admin.id);
      expect(rows.single['role'], 'player');
    });

    test('nobody can grant the owner role', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': player.id,
          'p_role': 'owner',
        });
      });
      expect(result, 'INVALID_ROLE');
    });

    test('the owner cannot change their own role', () async {
      final result = await outcomeOf(() async {
        await owner.client.rpc('set_member_role', params: {
          'p_community_id': communityId,
          'p_user_id': owner.id,
          'p_role': 'admin',
        });
      });
      expect(result, 'CANNOT_CHANGE_OWN_ROLE');
    });
  });

  group('visibility is unchanged (PD-14)', () {
    test('an outsider cannot see a private community', () async {
      final rows = await outsider.client
          .from('communities')
          .select('id')
          .eq('id', communityId);
      expect(rows, isEmpty);
    });

    test('an outsider can see a public community', () async {
      final rows = await outsider.client
          .from('communities')
          .select('id')
          .eq('id', publicId);
      expect(rows, hasLength(1));
    });

    test('an outsider cannot see its matches', () async {
      final rows = await outsider.client
          .from('matches')
          .select('id')
          .eq('id', matchId);
      expect(rows, isEmpty);
    });

    test('a member can see its matches', () async {
      final rows =
          await player.client.from('matches').select('id').eq('id', matchId);
      expect(rows, hasLength(1));
    });

    test('an outsider cannot register for a match', () async {
      final result = await outcomeOf(() async {
        await outsider.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      });
      expect(result, 'NOT_COMMUNITY_MEMBER');
    });
  });
}
