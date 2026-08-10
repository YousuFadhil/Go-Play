@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The last-seat race. register_for_match locks the match row and then the
/// user row, in that order, so two people going for the same final place must
/// come out as one confirmed and one reserve - never two confirmed, and never
/// a lost registration.
void main() {
  if (!integrationConfigured) {
    test('concurrency', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Concurrency');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    // Both scenarios in this file need five genuine members: the approved
    // minimum of four seats (OP-2) means a reserve only exists at the fifth
    // registration.
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  test('two people racing for the last seat produce one confirmed and one '
      'reserve', () async {
    // Four starting places; owner, admin and player take three of them, so
    // player2 and player3 are both going for the last one.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 7), startingPlayers: 4);

    // Fill the first three seats so exactly one remains.
    for (final user in [owner, admin, player]) {
      final seat = await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      expect(seat, 'confirmed');
    }

    final results = await Future.wait([
      player2.client.rpc('register_for_match', params: {'p_match_id': matchId}),
      player3.client.rpc('register_for_match', params: {'p_match_id': matchId}),
    ]);

    final statuses = results.map((r) => r as String).toList()..sort();
    expect(statuses, ['confirmed', 'reserve'],
        reason: 'the seat goes to exactly one of them');

    final rows = await owner.client
        .from('match_registrations')
        .select('user_id, status, registration_order')
        .eq('match_id', matchId);
    expect(rows, hasLength(5), reason: 'no registration was lost');
    expect(
      rows.where((r) => r['status'] == 'confirmed'),
      hasLength(4),
      reason: 'the four starting places are filled, no more',
    );

    final orders = rows.map((r) => r['registration_order'] as int).toList();
    expect(orders.toSet(), hasLength(5),
        reason: 'registration_order is unique per match');
  });

  test('racing withdrawals promote at most one reserve into the seat',
      () async {
    // Four seats: owner, admin, player and player2 start, player3 waits in
    // reserve.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 8), startingPlayers: 4);

    for (final user in [owner, admin, player, player2, player3]) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }

    // A confirmed player leaves while the only reserve also leaves.
    await Future.wait([
      owner.client.rpc('withdraw_from_match', params: {'p_match_id': matchId}),
      player3.client.rpc('withdraw_from_match', params: {'p_match_id': matchId}),
    ]);

    final rows = await admin.client
        .from('match_registrations')
        .select('user_id, status')
        .eq('match_id', matchId);

    expect(rows, hasLength(3), reason: 'both withdrawals took effect');
    expect({for (final r in rows) r['user_id']},
        {admin.id, player.id, player2.id});
    expect(rows.every((r) => r['status'] == 'confirmed'), isTrue,
        reason: 'the freed seat left everyone remaining inside the four, and '
            'the reserve that withdrew was not promoted into it');
  });
}
