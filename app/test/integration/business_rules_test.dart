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
  late TestUser player2;
  late TestUser player3;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    player2 = await signInTestUser('player2');
    player3 = await signInTestUser('player3');
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
    // Four starting places — the approved minimum match (OP-2) — and five
    // sign-ups, which is what it now takes to produce a reserve.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 4);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);

    for (final user in [owner, admin, player, player2, player3]) {
      final status = await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      expect(status, isIn(['confirmed', 'reserve']));
    }

    final rows = await roster(matchId);
    expect(rows, hasLength(5));
    for (var i = 0; i < 4; i++) {
      expect(rows[i]['status'], 'confirmed',
          reason: 'the first four registrations take the four seats');
    }
    expect(rows[4]['status'], 'reserve', reason: 'fifth exceeds the four seats');
  });

  test('DD-01 withdrawing deletes the row and promotes the first reserve',
      () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 4);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    // Four confirmed and one reserve, so a withdrawal has someone to promote.
    for (final user in [owner, admin, player, player2, player3]) {
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
    // Five participants exist, so this only closes when the cap is tiny.
    if (reserve > 0) {
      // With a reserve allowance there is always room for five; assert the
      // cap is what the trigger derived rather than forcing an artificial one.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 6), startingPlayers: 4);
      final row = await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single();
      expect(row['max_registration'], 4 + reserve);
      return;
    }
    // No reserve allowance: the four seats are the whole cap, so the fifth
    // registration is refused outright rather than queued.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 6), startingPlayers: 4);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    for (final user in [owner, admin, player, player2]) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }
    final result = await outcomeOf(() async {
      await player3.client
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

  // SUPERSEDED (migration 0045): this asserted `MATCH_LOCKED`, because
  // `update_match` refused a match from its scheduled start onwards. The
  // approved decision is now that an owner or admin retains full administrative
  // control in every match state, so the lock no longer applies to them — it
  // applies to self-service, which `DD-04` above still proves.
  //
  // The rule the lock was protecting is kept and asserted here instead: an edit
  // to a match that has already started must not disturb the roster it has.
  test('DD-04 an organizer may edit a started match, and the roster stands',
      () async {
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(hours: -1),
        duration: const Duration(hours: 3),
        startingPlayers: 4);
    for (final user in [owner, admin, player]) {
      await owner.client.rpc('admin_add_player_to_match', params: {
        'p_match_id': matchId,
        'p_user_id': user.id,
      });
    }
    final before = await roster(matchId);
    final start = DateTime.now().toUtc().add(const Duration(days: 2));

    final result = await outcomeOf(() async {
      await owner.client.rpc('update_match', params: {
        'p_match_id': matchId,
        'p_title': 'ITest edited match',
        'p_location': 'Edited in progress',
        'p_start_at': start.toIso8601String(),
        'p_end_at': start.add(const Duration(hours: 2)).toIso8601String(),
        'p_starting_players': 10,
        'p_description': null,
      });
    });
    expect(result, 'ALLOW');

    final row = await owner.client
        .from('matches')
        .select('title, starting_players')
        .eq('id', matchId)
        .single();
    expect(row['title'], 'ITest edited match');
    expect(row['starting_players'], 10);

    final after = await roster(matchId);
    expect(after.length, before.length);
    expect(
      [for (final r in after) r['status']],
      [for (final r in before) r['status']],
      reason: 'nobody is demoted by an edit',
    );
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
        startsIn: const Duration(days: 4), startingPlayers: 4);
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
    // Four seats, five sign-ups: the first four start, player3 waits.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 4), startingPlayers: 4);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    for (final user in [owner, admin, player, player2, player3]) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }

    await owner.client.rpc('remove_player', params: {
      'p_match_id': matchId,
      'p_user_id': admin.id,
    });

    final removed = await admin.client
        .from('notifications')
        .select('id')
        .eq('type', 'removed')
        .eq('match_id', matchId);
    final promoted = await player3.client
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

  group('OP-2 minimum match size', () {
    // The approved minimum is 4 players (2 v 2), enforced twice: the CHECK on
    // matches.starting_players and the guard inside update_match. Migration
    // 0019 moved both from the original lower bound of 2.
    Future<String> createWith(int startingPlayers) => outcomeOf(() async {
          await owner.client.from('matches').insert({
            'community_id': communityId,
            'created_by': owner.id,
            'title': 'ITest bound $startingPlayers',
            'location': 'ITest pitch',
            'start_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 9))
                .toIso8601String(),
            'end_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 9, hours: 2))
                .toIso8601String(),
            'starting_players': startingPlayers,
          });
        });

    test('a match below the minimum cannot be created', () async {
      expect(await createWith(2), isNot('ALLOW'));
      expect(await createWith(3), isNot('ALLOW'));
    });

    test('the minimum itself, and everything up to 30, is accepted', () async {
      expect(await createWith(4), 'ALLOW');
      expect(await createWith(30), 'ALLOW');
    });

    test('above 30 is still rejected', () async {
      expect(await createWith(31), isNot('ALLOW'));
    });

    test('capacity is still derived at the new minimum (DD-06)', () async {
      // The reserve rule is untouched by 0019: max_registration remains
      // starting_players + the global reserve allowance.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 9, hours: 6), startingPlayers: 4);
      final reserve = await owner.client
          .from('app_settings')
          .select('reserve_players')
          .limit(1)
          .single();
      final row = await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single();

      expect(row['max_registration'], 4 + (reserve['reserve_players'] as int));
    });

    test('editing a match below the minimum is refused, at 4 it is not',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 9, hours: 9), startingPlayers: 6);
      final start = DateTime.now().toUtc().add(const Duration(days: 9, hours: 9));

      Future<String> editTo(int startingPlayers) => outcomeOf(() async {
            await owner.client.rpc('update_match', params: {
              'p_match_id': matchId,
              'p_title': 'ITest bound edit',
              'p_location': 'ITest pitch',
              'p_start_at': start.toIso8601String(),
              'p_end_at':
                  start.add(const Duration(hours: 2)).toIso8601String(),
              'p_starting_players': startingPlayers,
              'p_description': null,
            });
          });

      expect(await editTo(3), 'INVALID_STARTING_PLAYERS');
      expect(await editTo(4), 'ALLOW');
    });
  });
}
