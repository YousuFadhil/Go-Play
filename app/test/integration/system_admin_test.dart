@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The internal administration role.
///
/// None of the four test accounts is a System Admin, and this suite does not
/// make one: granting the role is a manual SQL act by design. So what is
/// asserted here is the half that matters most — that an ordinary account is
/// refused by every admin function, and that `is_system_admin` says no.
///
/// The granting path and the delete cascades are exercised by hand against a
/// real System Admin account; see the manual verification in the release notes.
void main() {
  if (!integrationConfigured) {
    test('system admin', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player;
  late String communityId;
  late String matchId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Admin');
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 16));
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  test('an ordinary account is not a system admin', () async {
    expect(await owner.client.rpc('is_system_admin'), isFalse);
    expect(await player.client.rpc('is_system_admin'), isFalse);
  });

  group('every admin function refuses an ordinary account', () {
    test('listing', () async {
      for (final fn in [
        'admin_list_users',
        'admin_list_communities',
        'admin_list_matches',
      ]) {
        expect(
          await outcomeOf(() async {
            await owner.client.rpc(fn, params: {'p_search': null});
          }),
          'NOT_AUTHORIZED',
          reason: fn,
        );
      }
    });

    test('deleting', () async {
      expect(
        await outcomeOf(() async {
          await owner.client
              .rpc('admin_delete_user', params: {'p_user_id': player.id});
        }),
        'NOT_AUTHORIZED',
      );
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('admin_delete_community',
              params: {'p_community_id': communityId});
        }),
        'NOT_AUTHORIZED',
      );
      expect(
        await outcomeOf(() async {
          await owner.client
              .rpc('admin_delete_match', params: {'p_match_id': matchId});
        }),
        'NOT_AUTHORIZED',
      );
    });

    test('and the refusal changes nothing', () async {
      await outcomeOf(() async {
        await owner.client.rpc('admin_delete_community',
            params: {'p_community_id': communityId});
      });
      final rows = await owner.client
          .from('communities')
          .select('id')
          .eq('id', communityId);
      expect(rows, hasLength(1), reason: 'the community is still there');
    });
  });

  test('the system_admins table is not readable from the client', () async {
    // No RLS policy exists, so a select returns nothing rather than the roster.
    final rows = await owner.client.from('system_admins').select('user_id');
    expect(rows, isEmpty,
        reason: 'who administers the system is not the app\'s business');
  });
}
