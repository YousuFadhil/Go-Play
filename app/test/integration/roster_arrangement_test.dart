@Timeout(Duration(minutes: 8))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0053` — the administrative arrangement of a match roster.
///
/// The rules this suite exists for are the ones that cannot be seen from the
/// client, because they are one SQL transaction:
///
///   1. **Default, then authoritative.** A match nobody has arranged behaves
///      exactly as it did before this migration — community players before
///      Professional Guests, each in arrival order. The first arrangement
///      activates administrative ordering for the rest of the match's life, and
///      nothing puts it back.
///   2. **Position decides the seat.** Starting and reserve are never sent;
///      they are derived by cutting one order at `starting_players`. So the
///      starting list cannot gain a participant however the lists are
///      rearranged, and a participant cannot hold two seats.
///   3. **A deliberately starting guest stays starting.** Not displaced by a
///      community player waiting on the reserve, and not displaced by a
///      withdrawal from the starting list, which fills the seat it actually
///      vacated.
///   4. **BTGE is untouched.** A guest never becomes an engine input; a change
///      to the starting *community* set clears the stored lineup through the
///      existing reconciliation, and a change that leaves that set alone does
///      not.
///
/// Everything created here lives under one community per test and is removed by
/// `disposeCommunity`, whose cascade takes the matches and registrations with
/// it.
void main() {
  if (!integrationConfigured) {
    test('administrative roster arrangement', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser player2;
  late TestUser player3;
  late TestUser outsider;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    player2 = await signInTestUser('player2');
    player3 = await signInTestUser('player3');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Arrangement');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  // --- helpers -----------------------------------------------------------------

  Future<void> register(TestUser user, String matchId) async {
    await user.client.rpc('register_for_match', params: {'p_match_id': matchId});
  }

  Future<String> addGuest(String matchId, String name) async {
    final id = await owner.client.rpc('add_professional_guest', params: {
      'p_match_id': matchId,
      'p_name': name,
    });
    return id as String;
  }

  /// The whole roster in the authoritative order, read through the same view
  /// the app reads. `roster_position` is the ordering under test, so asserting
  /// over it asserts the thing the starting/reserve cut was made from.
  Future<List<Map<String, dynamic>>> roster(String matchId) async {
    final rows = await owner.client
        .from('v_match_registrations')
        .select('registration_id, user_id, professional_guest_id, status, '
            'registration_order, admin_order, roster_position')
        .eq('match_id', matchId)
        .order('roster_position', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> seatOfUser(String matchId, String userId) async {
    final rows = await roster(matchId);
    return rows.firstWhere((r) => r['user_id'] == userId)['status'] as String;
  }

  Future<String> seatOfGuest(String matchId, String guestId) async {
    final rows = await roster(matchId);
    return rows
        .firstWhere((r) => r['professional_guest_id'] == guestId)['status']
        as String;
  }

  Future<String> registrationOfUser(String matchId, String userId) async {
    final rows = await roster(matchId);
    return rows.firstWhere((r) => r['user_id'] == userId)['registration_id']
        as String;
  }

  Future<String> registrationOfGuest(String matchId, String guestId) async {
    final rows = await roster(matchId);
    return rows.firstWhere(
        (r) => r['professional_guest_id'] == guestId)['registration_id'] as String;
  }

  Future<String> orderModeOf(String matchId) async {
    final row = await owner.client
        .from('matches')
        .select('roster_order_mode')
        .eq('id', matchId)
        .single();
    return row['roster_order_mode'] as String;
  }

  Future<void> arrange(
    TestUser actor,
    String matchId,
    List<String> registrationIds,
  ) async {
    await actor.client.rpc('set_match_roster_order', params: {
      'p_match_id': matchId,
      'p_registration_ids': registrationIds,
    });
  }

  Future<void> swap(
    TestUser actor,
    String matchId,
    String first,
    String second,
  ) async {
    await actor.client.rpc('swap_match_participants', params: {
      'p_match_id': matchId,
      'p_first_registration_id': first,
      'p_second_registration_id': second,
    });
  }

  /// Four community players and one Professional Guest in a match of four
  /// starting places. Default ordering puts the four players in the starting
  /// list and the guest on the reserve, which is the state every approved
  /// example begins from.
  ///
  /// [startsIn] is deliberately far out: the permanent accounts are used by
  /// every suite, and a match months away cannot clash with one another test
  /// left behind.
  Future<String> matchWithGuest({
    Duration startsIn = const Duration(days: 120),
  }) async {
    final matchId = await createMatch(owner, communityId,
        startsIn: startsIn, startingPlayers: 4);
    for (final user in [owner, admin, player, player2]) {
      await register(user, matchId);
    }
    await addGuest(matchId, 'ITest Guest');
    return matchId;
  }

  // --- 1. the default is untouched ------------------------------------------------

  group('1. a match nobody has arranged', () {
    test('keeps registration order, and records that nobody has arranged it',
        () async {
      final matchId = await matchWithGuest();

      expect(await orderModeOf(matchId), 'registration');
      final rows = await roster(matchId);
      expect(rows.every((r) => r['admin_order'] == null), isTrue,
          reason: 'no arrangement exists, so no participant has a place in one');
      expect(rows.map((r) => r['status']), [
        'confirmed',
        'confirmed',
        'confirmed',
        'confirmed',
        'reserve',
      ]);
      expect(rows.last['professional_guest_id'], isNotNull,
          reason: 'community players precede a guest by default');
      // Arrival order and authoritative order are the same thing here.
      expect(
        rows.map((r) => r['registration_order']),
        [1, 2, 3, 4, 5],
      );
    });

    test('still promotes a community reserve ahead of a guest', () async {
      final matchId = await matchWithGuest();
      final guestId = (await roster(matchId)).last['professional_guest_id'];
      await register(player3, matchId);
      // player3 arrives after the guest but is a community player, so the
      // approved default puts them ahead of it.
      expect(await seatOfUser(matchId, player3.id), 'reserve');

      await owner.client.rpc('remove_player',
          params: {'p_match_id': matchId, 'p_user_id': player2.id});

      expect(await seatOfUser(matchId, player3.id), 'confirmed');
      expect(await seatOfGuest(matchId, guestId as String), 'reserve',
          reason: 'the Professional Guest fallback is untouched while nobody '
              'has arranged the match');
      expect(await orderModeOf(matchId), 'registration',
          reason: 'a removal is not an arrangement');
    });
  });

  // --- 2. activation ----------------------------------------------------------------

  group('2. the first arrangement activates administrative ordering', () {
    test('a reorder switches the match and seeds every participant', () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      final ids = [
        for (final r in rows) r['registration_id'] as String
      ];

      await arrange(owner, matchId, [ids[1], ids[0], ...ids.sublist(2)]);

      expect(await orderModeOf(matchId), 'manual');
      final after = await roster(matchId);
      expect(after.every((r) => r['admin_order'] != null), isTrue);
      expect(after.map((r) => r['admin_order']), [1, 2, 3, 4, 5]);
      expect(after.first['registration_id'], ids[1]);
      expect(after[1]['registration_id'], ids[0]);
    });

    test('a swap activates it just as a reorder does', () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);

      await swap(owner, matchId, rows[3]['registration_id'] as String,
          rows[4]['registration_id'] as String);

      expect(await orderModeOf(matchId), 'manual');
    });

    test('it is never put back, even by an order identical to arrival order',
        () async {
      final matchId = await matchWithGuest();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];
      await arrange(owner, matchId, [ids[1], ids[0], ...ids.sublist(2)]);

      // Arranged back into the order it started in. The approved rule is that
      // this is an arrangement and not a reset.
      await arrange(owner, matchId, ids);
      expect(await orderModeOf(matchId), 'manual');

      // And the column itself refuses to go back, whoever writes it.
      expect(
        await outcomeOf(() async {
          await owner.client
              .from('matches')
              .update({'roster_order_mode': 'registration'}).eq('id', matchId);
        }),
        'ROSTER_ORDER_MODE_LOCKED',
      );
    });
  });

  // --- 3. reordering ------------------------------------------------------------------

  group('3. an arrangement is stored and obeyed', () {
    test('the starting list keeps the order it was given', () async {
      final matchId = await matchWithGuest();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      // The four starting participants reversed; the reserve untouched.
      await arrange(owner, matchId, [ids[3], ids[2], ids[1], ids[0], ids[4]]);

      final after = await roster(matchId);
      expect(
        [for (final r in after) r['registration_id']],
        [ids[3], ids[2], ids[1], ids[0], ids[4]],
      );
      expect(after.take(4).every((r) => r['status'] == 'confirmed'), isTrue,
          reason: 'reordering inside the starting list moves nobody out of it');
    });

    test('the reserve keeps the order it was given, and promotion follows it',
        () async {
      final matchId = await matchWithGuest();
      await register(player3, matchId);
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];
      // Five participants and a guest; the reserve is the last two. Put the
      // guest ahead of the waiting community player.
      await arrange(owner, matchId, [...ids.sublist(0, 4), ids[5], ids[4]]);

      final reserve = (await roster(matchId))
          .where((r) => r['status'] == 'reserve')
          .toList();
      expect(reserve.first['professional_guest_id'], isNotNull);

      // A starting player leaves; the seat goes to the top of the reserve as
      // the administrator arranged it, which is the guest.
      await owner.client.rpc('remove_player',
          params: {'p_match_id': matchId, 'p_user_id': player2.id});

      expect(
        (await roster(matchId))
            .firstWhere((r) => r['registration_id'] == ids[5])['status'],
        'confirmed',
        reason: 'automatic promotion uses the administrative reserve order',
      );
    });
  });

  // --- 4. swapping ---------------------------------------------------------------------

  group('4. a swap is the way across a full starting list', () {
    test('a reserve participant swapped onto a starting one takes their place',
        () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      final lastStarting = rows[3]['registration_id'] as String;
      final firstReserve = rows[4]['registration_id'] as String;

      await swap(owner, matchId, firstReserve, lastStarting);

      final after = await roster(matchId);
      expect(
        after.firstWhere((r) => r['registration_id'] == firstReserve)['status'],
        'confirmed',
      );
      expect(
        after.firstWhere((r) => r['registration_id'] == lastStarting)['status'],
        'reserve',
      );
      expect(after.where((r) => r['status'] == 'confirmed'), hasLength(4),
          reason: 'a swap exchanges two positions and creates none');
    });

    test('the reverse direction is the same operation', () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      final starting = rows[0]['registration_id'] as String;
      final reserve = rows[4]['registration_id'] as String;

      await swap(owner, matchId, starting, reserve);

      final after = await roster(matchId);
      expect(after.firstWhere((r) => r['registration_id'] == starting)['status'],
          'reserve');
      expect(after.firstWhere((r) => r['registration_id'] == reserve)['status'],
          'confirmed');
    });

    test('the same seat twice is refused', () async {
      final matchId = await matchWithGuest();
      final id = (await roster(matchId)).first['registration_id'] as String;

      expect(await outcomeOf(() => swap(owner, matchId, id, id)),
          'INVALID_SWAP');
    });

    test('a seat from another match is refused', () async {
      final matchId = await matchWithGuest();
      final other = await createMatch(owner, communityId,
          startsIn: const Duration(days: 200), startingPlayers: 4);
      await register(player3, other);
      final foreign = await registrationOfUser(other, player3.id);
      final mine = (await roster(matchId)).first['registration_id'] as String;

      expect(await outcomeOf(() => swap(owner, matchId, mine, foreign)),
          'INVALID_SWAP');
    });
  });

  // --- 5. the Professional Guest, deliberately started -----------------------------------

  group('5. a guest an administrator put in the starting list', () {
    /// The approved example: a guest swapped into the starting list while
    /// community players wait on the reserve.
    Future<(String matchId, String guestId)> guestStarting() async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      final guestId = rows[4]['professional_guest_id'] as String;
      await swap(owner, matchId, rows[4]['registration_id'] as String,
          rows[3]['registration_id'] as String);
      expect(await seatOfGuest(matchId, guestId), 'confirmed');
      expect(await seatOfUser(matchId, player2.id), 'reserve');
      return (matchId, guestId);
    }

    test('is not displaced by a community player waiting on the reserve',
        () async {
      final (matchId, guestId) = await guestStarting();

      // An edit re-cuts the roster, which is the moment a guest would have been
      // pushed out before this migration.
      await owner.client.rpc('update_match', params: {
        'p_match_id': matchId,
        'p_title': 'ITest match',
        'p_location': 'ITest pitch',
        'p_start_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 120))
            .toIso8601String(),
        'p_end_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 120, hours: 2))
            .toIso8601String(),
        'p_starting_players': 4,
        'p_description': null,
      });

      expect(await seatOfGuest(matchId, guestId), 'confirmed');
      expect(await seatOfUser(matchId, player2.id), 'reserve');
    });

    test('is not displaced by a community player registering', () async {
      final (matchId, guestId) = await guestStarting();

      await register(player3, matchId);

      expect(await seatOfGuest(matchId, guestId), 'confirmed');
      expect(await seatOfUser(matchId, player3.id), 'reserve',
          reason: 'a new arrival joins the end of the arrangement');
    });

    test('is not displaced when a starting community player withdraws',
        () async {
      final (matchId, guestId) = await guestStarting();

      // The vacant seat is the one `player` left, and it is filled from the top
      // of the current reserve — not by taking the guest off the pitch.
      await player.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});

      expect(await seatOfGuest(matchId, guestId), 'confirmed');
      expect(await seatOfUser(matchId, player2.id), 'confirmed',
          reason: 'the top of the administrative reserve fills the vacancy');
      final confirmed = (await roster(matchId))
          .where((r) => r['status'] == 'confirmed')
          .length;
      expect(confirmed, 4);
    });

    test('survives several withdrawals and promotions in a row', () async {
      final (matchId, guestId) = await guestStarting();
      await register(player3, matchId);

      await player.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});
      await admin.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});

      final after = await roster(matchId);
      expect(after.where((r) => r['status'] == 'confirmed'), hasLength(4));
      expect(await seatOfGuest(matchId, guestId), 'confirmed');
      // Everybody still holds exactly one seat.
      final ids = after.map((r) => r['registration_id']).toSet();
      expect(ids, hasLength(after.length));
    });
  });

  // --- 6. what cannot be asked for ---------------------------------------------------------

  group('6. an arrangement cannot break the roster', () {
    test('the starting list never exceeds the configured capacity', () async {
      final matchId = await matchWithGuest();
      await register(player3, matchId);
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      // Every permutation is a legal request, and none of them can produce a
      // fifth starting participant: the seat is derived from position.
      await arrange(owner, matchId, ids.reversed.toList());

      final after = await roster(matchId);
      expect(after.where((r) => r['status'] == 'confirmed'), hasLength(4));
      expect(after.where((r) => r['status'] == 'reserve'), hasLength(2));
    });

    test('an order that is not the whole roster is refused', () async {
      final matchId = await matchWithGuest();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      expect(await outcomeOf(() => arrange(owner, matchId, ids.sublist(0, 3))),
          'ROSTER_MISMATCH');
      expect(
        await outcomeOf(
            () => arrange(owner, matchId, [ids[0], ids[0], ...ids.sublist(2)])),
        'ROSTER_MISMATCH',
      );
      expect(await orderModeOf(matchId), 'registration',
          reason: 'a refused arrangement activates nothing');
    });

    test('an order naming a seat from another match is refused', () async {
      final matchId = await matchWithGuest();
      final other = await createMatch(owner, communityId,
          startsIn: const Duration(days: 220), startingPlayers: 4);
      await register(player3, other);
      final foreign = await registrationOfUser(other, player3.id);
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      expect(
        await outcomeOf(
            () => arrange(owner, matchId, [...ids.sublist(0, 4), foreign])),
        'ROSTER_MISMATCH',
      );
    });
  });

  // --- 7. who may arrange -------------------------------------------------------------------

  group('7. only an owner or an admin arranges', () {
    test('an owner may', () async {
      final matchId = await matchWithGuest();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];
      expect(await outcomeOf(() => arrange(owner, matchId, ids.reversed.toList())),
          'ALLOW');
    });

    test('an admin may', () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      expect(
        await outcomeOf(() => swap(admin, matchId,
            rows[3]['registration_id'] as String,
            rows[4]['registration_id'] as String)),
        'ALLOW',
      );
    });

    test('an ordinary player may not, even one in the match', () async {
      final matchId = await matchWithGuest();
      final rows = await roster(matchId);
      final ids = [for (final r in rows) r['registration_id'] as String];

      expect(await outcomeOf(() => arrange(player, matchId, ids)),
          'NOT_AUTHORIZED');
      expect(
        await outcomeOf(() => swap(player, matchId, ids[0], ids[1])),
        'NOT_AUTHORIZED',
      );
      expect(await orderModeOf(matchId), 'registration');
    });

    test('a non-member may not', () async {
      final matchId = await matchWithGuest();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      expect(await outcomeOf(() => arrange(outsider, matchId, ids)),
          'NOT_AUTHORIZED');
    });
  });

  // --- 8. a match that has been played ---------------------------------------------------------

  group('8. a completed match', () {
    Future<String> playedMatch() async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(hours: -6),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      for (final user in [owner, admin, player, player2]) {
        // Self-registration is refused once a match has started, so the
        // administrative path is the one that builds a played roster.
        await owner.client.rpc('admin_add_player_to_match',
            params: {'p_match_id': matchId, 'p_user_id': user.id});
      }
      return matchId;
    }

    test('is still arranged by an owner and by an admin', () async {
      final matchId = await playedMatch();
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      expect(await outcomeOf(() => arrange(owner, matchId, ids.reversed.toList())),
          'ALLOW');
      expect(await outcomeOf(() => swap(admin, matchId, ids[0], ids[1])),
          'ALLOW');
      expect(await orderModeOf(matchId), 'manual');
    });

    test('keeps the starting list it played with', () async {
      final matchId = await playedMatch();
      final before = await roster(matchId);
      final ids = [for (final r in before) r['registration_id'] as String];

      await arrange(owner, matchId, ids.reversed.toList());

      final after = await roster(matchId);
      expect(after.every((r) => r['status'] == 'confirmed'), isTrue,
          reason: 'everyone in the record played; a played roster is not '
              're-cut');
      expect(
        [for (final r in after) r['registration_id']],
        ids.reversed.toList(),
        reason: 'the arrangement itself is stored',
      );
    });
  });

  // --- 9. teams and BTGE ---------------------------------------------------------------------------

  group('9. the BTGE boundary', () {
    Future<void> storeLineup(String matchId, List<TestUser> users) async {
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          for (var i = 0; i < users.length; i++)
            {
              'user_id': users[i].id,
              'team': i.isEven ? 'A' : 'B',
              'assigned_position': 'MID',
              'assignment_basis': 'PRIMARY',
            }
        ],
      });
    }

    Future<List<Map<String, dynamic>>> lineup(String matchId) async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id, team, assignment_basis')
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows);
    }

    test('a reorder that keeps the starting community set keeps the lineup',
        () async {
      final matchId = await matchWithGuest();
      await storeLineup(matchId, [owner, admin, player, player2]);
      final ids = [
        for (final r in await roster(matchId)) r['registration_id'] as String
      ];

      await arrange(owner, matchId, [ids[1], ids[0], ids[2], ids[3], ids[4]]);

      expect((await lineup(matchId)).where((a) => a['user_id'] != null),
          hasLength(4));
    });

    test('a swap that changes it clears the lineup for regeneration', () async {
      final matchId = await matchWithGuest();
      await register(player3, matchId);
      await storeLineup(matchId, [owner, admin, player, player2]);
      final rows = await roster(matchId);

      // player3 is on the reserve; swapping them in changes the starting
      // community set, which the approved rule says invalidates the lineup.
      await swap(
        owner,
        matchId,
        await registrationOfUser(matchId, player3.id),
        rows[3]['registration_id'] as String,
      );

      expect(await lineup(matchId), isEmpty,
          reason: 'a stale lineup never survives a change to the starting '
              'community players');
    });

    test('a guest never enters team generation', () async {
      final matchId = await matchWithGuest();
      final guestId = (await roster(matchId)).last['professional_guest_id']
          as String;
      await storeLineup(matchId, [owner, admin, player, player2]);

      await swap(
        owner,
        matchId,
        await registrationOfGuest(matchId, guestId),
        (await roster(matchId))[3]['registration_id'] as String,
      );

      final assignments = await lineup(matchId);
      // Whatever survives, no row names both identities and no guest is ever
      // credited with an engine basis: a guest is placed by the database, after
      // the engine, or not at all.
      expect(
        assignments.where(
            (a) => a['user_id'] != null && a['professional_guest_id'] != null),
        isEmpty,
      );
      expect(
        assignments.where((a) =>
            a['professional_guest_id'] != null &&
            a['assignment_basis'] != 'GUEST'),
        isEmpty,
      );
    });
  });
}
