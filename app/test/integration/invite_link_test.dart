@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

/// Shareable invitation links, both types.
///
/// The behaviour that matters most here is the split outcome: joining the
/// community and registering for the match succeed or fail independently, and a
/// failed registration must never take the membership down with it.
void main() {
  if (!integrationConfigured) {
    test('invitation links', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser outsider;

  /// An unauthenticated client, which is what someone opening an invitation
  /// before they have an account actually is.
  late SupabaseClient visitor;

  String? communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
    visitor = SupabaseClient(supabaseUrl, supabaseAnonKey,
        authOptions:
            const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    communityId = null;
  });

  Future<String> newCommunity({bool isPrivate = true}) async {
    final id = await createCommunity(
        owner, 'ITest invite ${DateTime.now().microsecondsSinceEpoch}',
        isPrivate: isPrivate);
    communityId = id;
    return id;
  }

  Future<String> createLink(TestUser as, String community,
          {String? matchId}) async =>
      await as.client.rpc('create_invite_link', params: {
        'p_community_id': community,
        'p_match_id': matchId,
      }) as String;

  Future<Map<String, dynamic>> preview(SupabaseClient client, String token) async {
    final rows = await client
        .rpc('preview_invite_link', params: {'p_token': token}) as List<dynamic>;
    return rows.first as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> redeem(TestUser as, String token) async {
    final rows = await as.client
        .rpc('redeem_invite_link', params: {'p_token': token}) as List<dynamic>;
    return rows.first as Map<String, dynamic>;
  }

  group('creating a link', () {
    test('owner and admin may create one; a player may not', () async {
      final community = await newCommunity();
      await addMember(owner, community, admin, role: 'admin');
      await addMember(owner, community, player);

      expect(await outcomeOf(() => createLink(owner, community)), 'ALLOW');
      expect(await outcomeOf(() => createLink(admin, community)), 'ALLOW');
      expect(await outcomeOf(() => createLink(player, community)),
          'NOT_AUTHORIZED');
      expect(await outcomeOf(() => createLink(outsider, community)),
          'NOT_AUTHORIZED');
    });

    test('sharing the same thing twice hands back the same link', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);

      expect(await createLink(owner, community),
          await createLink(owner, community));
      expect(await createLink(owner, community, matchId: match),
          await createLink(owner, community, matchId: match));
      expect(await createLink(owner, community),
          isNot(await createLink(owner, community, matchId: match)),
          reason: 'the community link and the match link are different things');
    });

    test('a match link cannot point outside its community', () async {
      final community = await newCommunity();
      final other = await createCommunity(owner, 'ITest invite other');
      try {
        final match = await createMatch(owner, other,
            startsIn: const Duration(days: 3));
        expect(
          await outcomeOf(() => createLink(owner, community, matchId: match)),
          'MATCH_NOT_IN_COMMUNITY',
        );
      } finally {
        await disposeCommunity(owner, other);
      }
    });

    test('a match that has already kicked off cannot be shared', () async {
      final community = await newCommunity();
      final started = await createMatch(owner, community,
          startsIn: const Duration(hours: -1));
      expect(
        await outcomeOf(() => createLink(owner, community, matchId: started)),
        'MATCH_LOCKED',
      );
    });
  });

  group('preview', () {
    test('a visitor with no account sees the community and the match',
        () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      final row = await preview(visitor, token);
      expect(row['state'], 'valid');
      expect(row['community_name'], startsWith('ITest invite'));
      expect(row['match_location'], 'ITest pitch');
      expect(row['starting_players'], 2);
      expect(row['seats_remaining'], isNotNull);
      expect(row['would_be_reserve'], isFalse);
      // A visitor is nobody yet, and the preview must not pretend otherwise.
      expect(row['is_member'], isFalse);
      expect(row['is_registered'], isFalse);
    });

    test('the preview never carries anything but the invitation', () async {
      final community = await newCommunity();
      final token = await createLink(owner, community);
      final row = await preview(visitor, token);

      expect(row.keys, isNot(contains('join_code')));
      expect(row.keys, isNot(contains('created_by')));
      expect(row.keys, isNot(contains('token')));
    });

    test('a signed-in viewer learns where they already stand', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);
      await addMember(owner, community, player);
      await player.client.rpc('register_for_match', params: {'p_match_id': match});

      final row = await preview(player.client, token);
      expect(row['is_member'], isTrue);
      expect(row['is_registered'], isTrue);
    });

    test('says reserve when the starting places are gone', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      expect((await preview(visitor, token))['would_be_reserve'], isFalse);
      await addMember(owner, community, player);
      await addMember(owner, community, admin);
      await player.client.rpc('register_for_match', params: {'p_match_id': match});
      await admin.client.rpc('register_for_match', params: {'p_match_id': match});

      final row = await preview(visitor, token);
      expect(row['would_be_reserve'], isTrue,
          reason: 'two starting places, both taken');
      expect(row['seats_remaining'], greaterThan(0),
          reason: 'the reserve list still has room');
    });

    test('an unknown token is not found', () async {
      expect((await preview(visitor, 'not-a-real-token'))['state'],
          'not_found');
    });
  });

  group('redeeming a community invitation', () {
    test('joins as a player and nothing more', () async {
      final community = await newCommunity();
      final token = await createLink(owner, community);

      final result = await redeem(outsider, token);
      expect(result['community_id'], community);
      expect(result['match_id'], isNull);
      expect(result['registration_status'], isNull);
      expect(result['failure_code'], isNull);

      final rows = await owner.client
          .from('community_members')
          .select('role')
          .eq('community_id', community)
          .eq('user_id', outsider.id);
      expect(rows.single['role'], 'player',
          reason: 'a shared link can never confer more than the lowest role');
    });

    test('redeeming twice changes nothing', () async {
      final community = await newCommunity();
      final token = await createLink(owner, community);

      await redeem(outsider, token);
      await redeem(outsider, token);

      final rows = await owner.client
          .from('community_members')
          .select('id')
          .eq('community_id', community)
          .eq('user_id', outsider.id);
      expect(rows, hasLength(1));
    });

    test('a visitor with no account cannot redeem', () async {
      final community = await newCommunity();
      final token = await createLink(owner, community);
      await expectLater(
        visitor.rpc('redeem_invite_link', params: {'p_token': token}),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('redeeming a community + match invitation', () {
    test('joins the community and takes a starting place', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      final result = await redeem(outsider, token);
      expect(result['registration_status'], 'confirmed');
      expect(result['failure_code'], isNull);
      expect(result['match_id'], match);

      final regs = await owner.client
          .from('match_registrations')
          .select('status')
          .eq('match_id', match)
          .eq('user_id', outsider.id);
      expect(regs.single['status'], 'confirmed');
    });

    test('lands on the reserve list once the starting places are taken',
        () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      await redeem(player, token);
      await redeem(admin, token);
      final third = await redeem(outsider, token);

      expect(third['registration_status'], 'reserve',
          reason: 'automatic registration obeys the same seat allocation');
      expect(third['failure_code'], isNull);
    });

    test('redeeming twice keeps the one registration', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      await redeem(outsider, token);
      final again = await redeem(outsider, token);

      expect(again['registration_status'], 'confirmed',
          reason: 'an existing registration is an outcome, not a failure');
      expect(again['failure_code'], isNull);
      final regs = await owner.client
          .from('match_registrations')
          .select('id')
          .eq('match_id', match)
          .eq('user_id', outsider.id);
      expect(regs, hasLength(1));
    });
  });

  group('a registration that fails leaves the membership standing', () {
    test('an overlapping match reports the reason and keeps the member',
        () async {
      // The player is busy at exactly this time in another community.
      final busy = await createCommunity(owner, 'ITest invite busy');
      try {
        final clash = await createMatch(owner, busy,
            startsIn: const Duration(days: 4), startingPlayers: 5);
        await addMember(owner, busy, outsider);
        await outsider.client
            .rpc('register_for_match', params: {'p_match_id': clash});

        final community = await newCommunity();
        final match = await createMatch(owner, community,
            startsIn: const Duration(days: 4), startingPlayers: 5);
        final token = await createLink(owner, community, matchId: match);

        final result = await redeem(outsider, token);
        expect(result['failure_code'], 'OVERLAPPING_MATCH',
            reason: 'the real reason, not a generic failure');
        expect(result['registration_status'], isNull);

        final members = await owner.client
            .from('community_members')
            .select('id')
            .eq('community_id', community)
            .eq('user_id', outsider.id);
        expect(members, hasLength(1),
            reason: 'joining is not rolled back by a failed registration');

        final regs = await owner.client
            .from('match_registrations')
            .select('id')
            .eq('match_id', match)
            .eq('user_id', outsider.id);
        expect(regs, isEmpty, reason: 'and no half-made registration is left');
      } finally {
        await disposeCommunity(owner, busy);
      }
    });

    test('a full match reports it and still adds the member', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 2);
      final token = await createLink(owner, community, matchId: match);

      await redeem(player, token);
      await redeem(admin, token);
      // Close registration by shrinking capacity to what is already taken,
      // rather than inventing users to fill the reserve list.
      await owner.client
          .from('matches')
          .update({'max_registration': 2}).eq('id', match);

      final result = await redeem(outsider, token);
      expect(result['failure_code'], 'REGISTRATION_CLOSED');
      expect(result['registration_status'], isNull);

      final members = await owner.client
          .from('community_members')
          .select('id')
          .eq('community_id', community)
          .eq('user_id', outsider.id);
      expect(members, hasLength(1),
          reason: 'membership survives whatever registration decides');
    });
  });

  group('a link stops working when it should', () {
    test('revoked: the preview goes quiet and redemption is refused', () async {
      final community = await newCommunity();
      final token = await createLink(owner, community);
      final link = (await owner.client
          .from('community_invite_links')
          .select('id')
          .eq('community_id', community)
          .single())['id'] as String;

      expect(await outcomeOf(() async {
        await player.client.rpc('revoke_invite_link', params: {'p_link_id': link});
      }), 'NOT_AUTHORIZED', reason: 'revoking is an organizer action');

      await owner.client.rpc('revoke_invite_link', params: {'p_link_id': link});

      final row = await preview(visitor, token);
      expect(row['state'], 'revoked');
      expect(row['community_name'], isNull,
          reason: 'a revoked link stops telling strangers what it pointed at');
      expect(await outcomeOf(() => redeem(outsider, token)), 'INVITE_REVOKED');
    });

    test('revoking frees the slot for a fresh link', () async {
      final community = await newCommunity();
      final first = await createLink(owner, community);
      final link = (await owner.client
          .from('community_invite_links')
          .select('id')
          .eq('community_id', community)
          .single())['id'] as String;
      await owner.client.rpc('revoke_invite_link', params: {'p_link_id': link});

      expect(await createLink(owner, community), isNot(first));
    });

    test('expired: a match link dies at kick-off', () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(minutes: 2), startingPlayers: 5);
      final token = await createLink(owner, community, matchId: match);

      // Move kick-off into the past the way the clock would.
      await owner.client.from('matches').update({
        'start_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      }).eq('id', match);

      expect((await preview(visitor, token))['state'], 'expired');
      expect(await outcomeOf(() => redeem(outsider, token)), 'INVITE_EXPIRED');
    });

    test('deleted match: the link ends with it rather than degrading',
        () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 5);
      final token = await createLink(owner, community, matchId: match);

      await owner.client.rpc('delete_match', params: {'p_match_id': match});

      expect((await preview(visitor, token))['state'], 'match_deleted',
          reason: 'not silently downgraded to a community invitation');
      expect(
          await outcomeOf(() => redeem(outsider, token)), 'INVITE_MATCH_DELETED');
    });
  });

  group('the links table itself', () {
    test('is readable by organizers only', () async {
      final community = await newCommunity();
      await createLink(owner, community);
      await addMember(owner, community, admin, role: 'admin');
      await addMember(owner, community, player);

      Future<int> visibleTo(SupabaseClient client) async {
        final rows = await client
            .from('community_invite_links')
            .select('id')
            .eq('community_id', community);
        return rows.length;
      }

      expect(await visibleTo(owner.client), 1);
      expect(await visibleTo(admin.client), 1);
      expect(await visibleTo(player.client), 0,
          reason: 'a member is not an organizer');
      expect(await visibleTo(outsider.client), 0);
      expect(await visibleTo(visitor), 0, reason: 'and a visitor is nobody');
    });

    test('the management list shows live links and drops revoked ones',
        () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 5);
      await createLink(owner, community);
      await createLink(owner, community, matchId: match);
      await addMember(owner, community, admin, role: 'admin');

      Future<List<dynamic>> listedTo(TestUser as) async => await as.client
          .from('community_invite_links')
          .select('id, token, kind, created_at, match:matches(title, start_at)')
          .eq('community_id', community)
          .eq('is_active', true);

      final forOwner = await listedTo(owner);
      expect(forOwner, hasLength(2));
      expect(forOwner.map((r) => r['kind']), containsAll(['community', 'match']));
      expect(
        forOwner.firstWhere((r) => r['kind'] == 'match')['match']['start_at'],
        isNotNull,
        reason: 'the list needs the match to tell a live link from a dead one',
      );
      expect(await listedTo(admin), hasLength(2));

      await owner.client.rpc('revoke_invite_link',
          params: {'p_link_id': forOwner.first['id']});
      expect(await listedTo(owner), hasLength(1),
          reason: 'a revoked link drops off the organizer list');
    });

    test('a link whose match was deleted still lists, with no match attached',
        () async {
      final community = await newCommunity();
      final match = await createMatch(owner, community,
          startsIn: const Duration(days: 3), startingPlayers: 5);
      await createLink(owner, community, matchId: match);
      await owner.client.rpc('delete_match', params: {'p_match_id': match});

      final rows = await owner.client
          .from('community_invite_links')
          .select('kind, match:matches(title, start_at)')
          .eq('community_id', community)
          .eq('is_active', true);
      expect(rows.single['kind'], 'match');
      expect(rows.single['match'], isNull,
          reason: 'which is exactly how the list knows to say the match is gone');
    });

    test('cannot be written directly', () async {
      final community = await newCommunity();
      await expectLater(
        outsider.client.from('community_invite_links').insert({
          'community_id': community,
          'kind': 'community',
          'created_by': outsider.id,
        }),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
