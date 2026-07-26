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
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Concurrency');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  test('two people racing for the last seat produce one confirmed and one '
      'reserve', () async {
    // One starting place; the owner is not registered, so admin and player
    // are both going for it.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 7), startingPlayers: 2);

    // Fill the first seat so exactly one remains.
    final first = await owner.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    expect(first, 'confirmed');

    final results = await Future.wait([
      admin.client.rpc('register_for_match', params: {'p_match_id': matchId}),
      player.client.rpc('register_for_match', params: {'p_match_id': matchId}),
    ]);

    final statuses = results.map((r) => r as String).toList()..sort();
    expect(statuses, ['confirmed', 'reserve'],
        reason: 'the seat goes to exactly one of them');

    final rows = await owner.client
        .from('match_registrations')
        .select('user_id, status, registration_order')
        .eq('match_id', matchId);
    expect(rows, hasLength(3), reason: 'no registration was lost');
    expect(
      rows.where((r) => r['status'] == 'confirmed'),
      hasLength(2),
      reason: 'the two starting places are filled, no more',
    );

    final orders = rows.map((r) => r['registration_order'] as int).toList();
    expect(orders.toSet(), hasLength(3),
        reason: 'registration_order is unique per match');
  });

  test('racing withdrawals promote at most one reserve into the seat',
      () async {
    // Two seats: owner and admin start, player waits in reserve.
    final matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 8), startingPlayers: 2);

    await owner.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    await admin.client
        .rpc('register_for_match', params: {'p_match_id': matchId});
    await player.client
        .rpc('register_for_match', params: {'p_match_id': matchId});

    // The only confirmed player leaves while a reserve also leaves.
    await Future.wait([
      owner.client.rpc('withdraw_from_match', params: {'p_match_id': matchId}),
      player.client.rpc('withdraw_from_match', params: {'p_match_id': matchId}),
    ]);

    final rows = await admin.client
        .from('match_registrations')
        .select('user_id, status')
        .eq('match_id', matchId);

    expect(rows, hasLength(1), reason: 'both withdrawals took effect');
    expect(rows.first['user_id'], admin.id);
    expect(rows.first['status'], 'confirmed',
        reason: 'the remaining reserve was promoted into the freed seat');
  });
}
