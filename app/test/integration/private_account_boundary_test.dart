@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_community_adapter.dart';
import 'package:go_play/infrastructure/supabase/supabase_profile_adapter.dart';

import 'support.dart';

/// The private-account boundary, proved where it is enforced.
///
/// Migration `0056` closed two leaks, and it closed them with column
/// privileges rather than with policies, because a policy decides rows and the
/// leak was a column. That distinction is the reason this file exists and the
/// reason every assertion below is a *live* call: a widget test can only show
/// that the application does not ask for `join_code` or `phone`. It cannot show
/// that the server would refuse if something else did — and the something else
/// is the whole threat. A publishable key and an HTTP client are all it takes.
///
/// So each test here asks the database directly, in the shape an attacker would
/// use, and requires a refusal.
///
/// **Requires `0056_private_account_hardening.sql` to be applied.** Cycle 1
/// ships as two migrations against one shared database: `0055` adds the two
/// RPCs and takes nothing away, so the previously deployed client keeps
/// working; `0056` is what actually closes the leaks. Run this file against a
/// project with only `0055` applied and it will fail, correctly -- the columns
/// really are still readable at that point.
void main() {
  if (!integrationConfigured) {
    test('private account boundary', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser outsider;
  String? communityId;

  CommunityRepository communitiesFor(TestUser user) =>
      CommunityRepository(SupabaseCommunityAdapter(user.client));
  ProfileRepository profilesFor(TestUser user) =>
      ProfileRepository(SupabaseProfileAdapter(user.client));

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Boundary');
    await addMember(owner, communityId!, admin, role: 'admin');
    await addMember(owner, communityId!, player);
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    communityId = null;
  });

  // ==========================================================================
  // Requirement 1 — the join code is a credential
  // ==========================================================================
  group('the join code cannot be selected', () {
    /// The raw request an attacker makes: name the column and see what comes
    /// back. `outcomeOf` reports 'ALLOW' when the server accepted it, which is
    /// the failure this group is here to catch.
    Future<String> selectJoinCodeAs(dynamic client) => outcomeOf(() async {
          await client
              .from('communities')
              .select('id, join_code')
              .eq('id', communityId!);
        });

    test('anon cannot select it', () async {
      expect(await selectJoinCodeAs(anonClient()), isNot('ALLOW'));
    });

    test('an authenticated non-member cannot select it', () async {
      expect(await selectJoinCodeAs(outsider.client), isNot('ALLOW'));
    });

    test('an ordinary Player cannot select it', () async {
      // Being in the community is not the point and never was: the code lets a
      // holder hand the community to anybody, so membership does not earn it.
      expect(await selectJoinCodeAs(player.client), isNot('ALLOW'));
    });

    test('not even the owner can select the column', () async {
      // The privilege is gone for everyone, which is what makes the RPC the
      // *only* path rather than the polite one.
      expect(await selectJoinCodeAs(owner.client), isNot('ALLOW'));
    });

    test('and it cannot be smuggled out through a nested select', () async {
      expect(
        await outcomeOf(() async {
          await player.client
              .from('community_members')
              .select('role, community:communities(id, join_code)')
              .eq('community_id', communityId!);
        }),
        isNot('ALLOW'),
        reason: 'an embed is still a select on the column',
      );
    });

    test('nor read back through an update RETURNING it', () async {
      expect(
        await outcomeOf(() async {
          await owner.client
              .from('communities')
              .update({'join_policy': 'CODE_REQUIRED'})
              .eq('id', communityId!)
              .select('join_code');
        }),
        isNot('ALLOW'),
        reason: 'RETURNING needs SELECT on the column, and there is none',
      );
    });

    test('while the community itself stays readable', () async {
      // The boundary took a column, not the community. Everything the product
      // shows about a community still reads.
      final community =
          await communitiesFor(player).fetchCommunity(communityId!);

      expect(community.id, communityId);
      expect(community.name, 'ITest Boundary');
    });
  });

  group('the approved join-code administration path', () {
    test('the owner receives the code', () async {
      final code = await communitiesFor(owner).fetchJoinCode(communityId!);

      expect(code, isNotEmpty);
      expect(RegExp(r'^[1-9][0-9]{3}$').hasMatch(code), isTrue,
          reason: 'the shape migration 0030 issues');
    });

    test('an admin receives it too, because inviting is admin work', () async {
      final code = await communitiesFor(admin).fetchJoinCode(communityId!);
      expect(code, isNotEmpty);
    });

    test('an ordinary Player is refused', () async {
      await expectLater(
        communitiesFor(player).fetchJoinCode(communityId!),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('a non-member is refused', () async {
      await expectLater(
        communitiesFor(outsider).fetchJoinCode(communityId!),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('anon cannot execute the function at all', () async {
      expect(
        await outcomeOf(() async {
          await anonClient().rpc(
            'community_join_code',
            params: {'p_community_id': communityId},
          );
        }),
        isNot('ALLOW'),
      );
    });
  });

  group('joining by code still works', () {
    test('the code an organizer reads is the code that lets somebody in',
        () async {
      final code = await communitiesFor(owner).fetchJoinCode(communityId!);

      final joined = await outsider.client
          .rpc('join_community_by_code', params: {'p_code': code});

      expect(joined, communityId);
      addTearDown(() async {
        await owner.client.rpc('remove_member', params: {
          'p_community_id': communityId,
          'p_user_id': outsider.id,
        });
      });
    });

    test('and the invitation preview still resolves it', () async {
      final code = await communitiesFor(owner).fetchJoinCode(communityId!);

      final rows = await outsider.client
          .rpc('preview_community_invite', params: {'p_code': code})
              as List<dynamic>;

      expect((rows.first as Map<String, dynamic>)['state'], 'valid');
    });
  });

  // ==========================================================================
  // Requirement 2 — the phone number is the account owner's
  // ==========================================================================
  group('a phone number is self-only', () {
    Future<String> selectPhoneAs(dynamic client, String userId) =>
        outcomeOf(() async {
          await client.from('users').select('id, phone').eq('id', userId);
        });

    test('User A cannot select User B\'s phone from users', () async {
      expect(await selectPhoneAs(player.client, owner.id), isNot('ALLOW'));
    });

    test('and cannot select their own from users either', () async {
      // The column privilege is absolute; being the row's owner does not
      // restore it. The owner's path is my_profile(), below.
      expect(await selectPhoneAs(player.client, player.id), isNot('ALLOW'));
    });

    test('anon cannot select it', () async {
      expect(await selectPhoneAs(anonClient(), owner.id), isNot('ALLOW'));
    });

    test('v_user_profile does not carry it', () async {
      expect(
        await outcomeOf(() async {
          await player.client
              .from('v_user_profile')
              .select('user_id, phone')
              .eq('user_id', owner.id);
        }),
        isNot('ALLOW'),
        reason: 'the view was rebuilt without the column (migration 0056)',
      );
    });

    test('nor does a nested select through a member list', () async {
      expect(
        await outcomeOf(() async {
          await player.client
              .from('community_members')
              .select('role, user:users(id, phone)')
              .eq('community_id', communityId!);
        }),
        isNot('ALLOW'),
      );
    });

    test('nor a nested select through a registration', () async {
      expect(
        await outcomeOf(() async {
          await player.client
              .from('match_registrations')
              .select('status, user:users(id, phone)')
              .limit(1);
        }),
        isNot('ALLOW'),
      );
    });

    test('and the football profile has never carried one', () async {
      final rows = await player.client.rpc(
        'player_profile',
        params: {'p_user_id': owner.id},
      ) as List<dynamic>;

      expect((rows.first as Map<String, dynamic>).containsKey('phone'), isFalse);
    });

    // Requirement 7: the owner's own path still works.
    test('but a player reads their own through my_profile', () async {
      final profile = await profilesFor(player).fetchMyProfile();

      expect(profile.phone, isNotEmpty,
          reason: 'the account screen still has a number to show and edit');
      expect(profile.fullName, isNotEmpty);
    });

    test('my_profile takes no user id, so it cannot be aimed elsewhere',
        () async {
      final rows = await player.client.rpc('my_profile') as List<dynamic>;
      final row = rows.first as Map<String, dynamic>;

      expect(row['user_id'], player.id,
          reason: 'it reads auth.uid() and nothing else');
    });

    test('anon cannot call my_profile', () async {
      expect(
        await outcomeOf(() async => anonClient().rpc('my_profile')),
        isNot('ALLOW'),
      );
    });

    test('and writing a phone still works for its owner', () async {
      // Writing a column is not reading it. `0056` took SELECT and left the
      // named-column UPDATE grant from `0022` alone, which is what keeps the
      // account screen's save working.
      final before = await profilesFor(player).fetchMyProfile();
      await profilesFor(player)
          .saveMyAccount(fullName: before.fullName, phone: before.phone);

      expect((await profilesFor(player).fetchMyProfile()).phone, before.phone);
    });
  });

  // ==========================================================================
  // Requirement 4 — existing public discovery is untouched
  // ==========================================================================
  group('signed-out discovery still works', () {
    test('anon lists public communities', () async {
      final rows = await anonClient()
          .from('v_public_communities')
          .select('id, name, description, member_count, upcoming_match_count');

      expect(rows, isNotEmpty);
      expect(
        rows.first.containsKey('join_code'),
        isFalse,
        reason: 'the public read model never carried one',
      );
    });

    test('and the public view refuses a join_code projection', () async {
      expect(
        await outcomeOf(() async {
          await anonClient()
              .from('v_public_communities')
              .select('id, join_code');
        }),
        isNot('ALLOW'),
      );
    });

    test('anon lists public upcoming matches', () async {
      await createMatch(owner, communityId!, startsIn: const Duration(days: 3));

      final rows = await anonClient()
          .from('v_public_upcoming_matches')
          .select('id, community_id, community_name, title, location, '
              'start_at, end_at, starting_players, open_slots')
          .eq('community_id', communityId!);

      expect(rows, isNotEmpty);
    });
  });

  group('externally readable views are SELECT-only', () {
    // Migration `0034` recorded that Supabase grants ALL on a newly created
    // object in `public` before a migration's own grant is reached, and that
    // `v_public_communities` was briefly deletable by anon because of it.
    // `0056` recreates `v_user_profile`, so it inherits the same hazard and
    // carries the same revoke. This is that revoke, checked.
    for (final view in [
      'v_public_communities',
      'v_public_upcoming_matches',
      'v_user_profile',
    ]) {
      test('$view refuses a delete', () async {
        expect(
          await outcomeOf(() async {
            await anonClient()
                .from(view)
                .delete()
                .eq('00000000-0000-0000-0000-000000000000', 'never');
          }),
          isNot('ALLOW'),
        );
      });

      test('$view refuses an insert from authenticated', () async {
        expect(
          await outcomeOf(() async {
            await player.client.from(view).insert({'name': 'nope'});
          }),
          isNot('ALLOW'),
        );
      });
    }
  });
}
