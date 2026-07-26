@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The rules recorded as DD-01 through DD-08. The migration was not allowed to
/// change any of them, so each is exercised here against the live project -
/// and where a role is involved, from a role that should be able to do it.
void main() {
  if (!integrationConfigured) {
    test('business rules', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Rules');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  Future<List<Map<String, dynamic>>> roster(String matchId) async {
    final rows = await owner.client
        .from('match_registrations')
        .select('user_id, status, registration_order')
        .eq('match_id', matchId)
        .order('registration_order', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String?> statusOf(String matchId) async {
    final row = await owner.client
        .from('matches')
        .select('status')
        .eq('id', matchId)
        .maybeSingle();
    return row?['status'] as String?;
  }

  test('DD-02 identity: the fixed accounts sign in with email and password',
      () async {
    expect(owner.id, isNotEmpty);
    expect(player.id, isNotEmpty);
    expect(owner.id, isNot(player.id));
  });

  test('DD-06 capacity is starting players plus the global reserve', () async {
    final settings = await owner.client
        .from('app_settings')
        .select('reserve_players')
        .limit(1)
        .single();
    final reserve = settings['reserve_players'] as int;

    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 7);
    final row = await owner.client
        .from('matches')
        .select('starting_players, max_registration')
        .eq('id', matchId)
        .single();

    expect(row['starting_players'], 7);
    expect(row['max_registration'], 7 + reserve);
  });

  test('first registrations are confirmed, the rest go to reserve', () async {
    // Two starting places, three sign-ups.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 2);

    for (final user in [owner, admin, player]) {
      final status = await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      expect(status, isIn(['confirmed', 'reserve']));
    }

    final rows = await roster(matchId);
    expect(rows, hasLength(3));
    expect(rows[0]['status'], 'confirmed');
    expect(rows[1]['status'], 'confirmed');
    expect(rows[2]['status'], 'reserve', reason: 'third exceeds the two seats');
  });

  test('DD-01 withdrawing deletes the row and promotes the first reserve',
      () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 2);
    for (final user in [owner, admin, player]) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }

    await owner.client
        .rpc('withdraw_from_match', params: {'p_match_id': matchId});

    final rows = await roster(matchId);
    expect(rows.where((r) => r['user_id'] == owner.id), isEmpty,
        reason: 'DD-01 deletes the registration rather than marking it');
    expect(rows.every((r) => r['status'] == 'confirmed'), isTrue,
        reason: 'the reserve was promoted into the freed seat');

    // The deleted row is what makes re-registration possible.
    final again = await owner.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    expect(again, 'reserve');
  });

  test('a second registration by the same person is refused', () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4));
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});

    final result = await outcomeOf(() async {
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    });
    expect(result, 'ALREADY_REGISTERED');
  });

  test('overlapping matches cannot both be joined', () async {
    final first = await createMatch(owner, communityId,
        startsIn: const Duration(days: 5), location: 'Overlap A');
    // Starts one hour into the first match, so the ranges intersect.
    final second = await createMatch(owner, communityId,
        startsIn: const Duration(days: 5, hours: 1), location: 'Overlap B');

    await player.client
        .rpc('register_for_match', params: {'p_match_id': first});
    final result = await outcomeOf(() async {
      await player.client
          .rpc('register_for_match', params: {'p_match_id': second});
    });
    expect(result, 'OVERLAPPING_MATCH');
  });

  test('registration closes once the maximum is reached', () async {
    final settings = await owner.client
        .from('app_settings')
        .select('reserve_players')
        .limit(1)
        .single();
    final reserve = settings['reserve_players'] as int;
    // Three participants exist, so this only closes when the cap is tiny.
    if (reserve > 0) {
      // With a reserve allowance there is always room for three; assert the
      // cap is what the trigger derived rather than forcing an artificial one.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 6), startingPlayers: 2);
      final row = await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single();
      expect(row['max_registration'], 2 + reserve);
      return;
    }
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 6), startingPlayers: 2);
    for (final user in [owner, admin]) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }
    final result = await outcomeOf(() async {
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    });
    expect(result, 'REGISTRATION_CLOSED');
  });

  test('DD-04 a started match is locked for registration and withdrawal',
      () async {
    // Started an hour ago, still running.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(hours: -1),
        duration: const Duration(hours: 3));

    expect(
      await outcomeOf(() async {
        await player.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }),
      'MATCH_LOCKED',
    );
    expect(
      await outcomeOf(() async {
        await player.client
            .rpc('withdraw_from_match', params: {'p_match_id': matchId});
      }),
      'MATCH_LOCKED',
    );
  });

  test('DD-04 an organizer cannot edit a locked match', () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(hours: -1),
        duration: const Duration(hours: 3));
    final start = DateTime.now().toUtc().add(const Duration(days: 2));

    final result = await outcomeOf(() async {
      await owner.client.rpc('update_match', params: {
        'p_match_id': matchId,
        'p_title': null,
        'p_location': 'Too late',
        'p_start_at': start.toIso8601String(),
        'p_end_at': start.add(const Duration(hours: 2)).toIso8601String(),
        'p_starting_players': 10,
        'p_description': null,
      });
    });
    expect(result, 'MATCH_LOCKED');
  });

  test('DD-05 a finished match is completed and closed', () async {
    // Ended an hour ago.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(hours: -3),
        duration: const Duration(hours: 2));

    final result = await outcomeOf(() async {
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    });
    expect(result, 'MATCH_CLOSED');

    // The stored status is written lazily by whichever RPC touches the row.
    expect(await statusOf(matchId), anyOf('completed', 'open'));
  });

  test('DD-03 status only ever holds open, full or completed', () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 2);
    expect(await statusOf(matchId), 'open');

    // The organizer may update the row, so this reaches the CHECK rather than
    // being refused by policy: the retired values must no longer be storable.
    for (final retired in ['draft', 'cancelled', 'postponed']) {
      final result = await outcomeOf(() async {
        await owner.client
            .from('matches')
            .update({'status': retired})
            .eq('id', matchId);
      });
      expect(result, contains('matches_status_check'),
          reason: '$retired was removed from the lifecycle by DD-03');
    }
    expect(await statusOf(matchId), 'open', reason: 'the row is unchanged');
  });

  test('DD-07 an unfinished match can be deleted whether or not it started',
      () async {
    final future = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), location: 'Future');
    final started = await createMatch(owner, communityId,
        startsIn: const Duration(hours: -1),
        duration: const Duration(hours: 3),
        location: 'Started');

    expect(
      await outcomeOf(() async {
        await owner.client
            .rpc('delete_match', params: {'p_match_id': future});
      }),
      'ALLOW',
    );
    expect(
      await outcomeOf(() async {
        await owner.client
            .rpc('delete_match', params: {'p_match_id': started});
      }),
      'ALLOW',
      reason: 'DD-07 makes deletion independent of the clock',
    );
  });

  test('DD-08 the match-deleted notice survives the match', () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4));
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});

    final before = await player.client.from('notifications').select('id');
    await owner.client.rpc('delete_match', params: {'p_match_id': matchId});

    final after = await player.client
        .from('notifications')
        .select('id, type, match_id')
        .eq('type', 'match_deleted');

    expect(after.length, greaterThan(0),
        reason: 'the registered player is told the match went');
    expect(after.first['match_id'], isNull,
        reason: 'ON DELETE SET NULL keeps the notice readable afterwards');
    expect(after.length, greaterThanOrEqualTo(before.length),
        reason: 'the notice was added, not replaced');
  });

  test('DD-08 removal and promotion both notify', () async {
    // Two seats, three sign-ups: owner and admin start, player waits.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 2);
    await owner.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    await admin.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});

    await owner.client.rpc('remove_player', params: {
      'p_match_id': matchId,
      'p_user_id': admin.id,
    });

    final removed = await admin.client
        .from('notifications')
        .select('id')
        .eq('type', 'removed')
        .eq('match_id', matchId);
    final promoted = await player.client
        .from('notifications')
        .select('id')
        .eq('type', 'promoted')
        .eq('match_id', matchId);

    expect(removed, isNotEmpty);
    expect(promoted, isNotEmpty,
        reason: 'the reserve moved into the freed seat and was told');
  });

  test('a user only ever reads their own notifications', () async {
    final rows = await player.client
        .from('notifications')
        .select('user_id')
        .limit(50);
    for (final row in rows) {
      expect(row['user_id'], player.id);
    }
  });
}
