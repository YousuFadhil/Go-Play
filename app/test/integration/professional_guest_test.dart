@Timeout(Duration(minutes: 8))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

/// Migrations `0044`-`0047` — the Professional Guest.
///
/// A Professional Guest is a match-scoped temporary participant with no
/// account, no membership, no profile and no career. Three claims are worth
/// testing and the rest follows from them:
///
///   1. **Ordering.** `(user_id is null), registration_order` is meant to
///      deliver community priority, FIFO promotion and LIFO displacement at
///      once. Each is asserted separately, because one clause doing three jobs
///      is exactly the kind of thing that quietly does two.
///   2. **Isolation.** A guest may play, score and be named best player, and
///      none of it may reach `player_statistics`, `rating_history` or
///      `community_statistics`. Asserted by recording a real result with a
///      guest in the lineup and reading the career tables afterwards.
///   3. **Authorization in every state.** Owner and admin manage guests in
///      open, full, in-progress, finished and completed matches; an ordinary
///      player and a non-member cannot, in any of them.
///
/// Everything created here lives under one community per test and is removed by
/// `disposeCommunity`, whose cascade also gives back any rating the result
/// tests moved on the permanent accounts.
void main() {
  if (!integrationConfigured) {
    test('professional guests', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Guests');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  // --- helpers ---------------------------------------------------------------

  Future<String> addGuest(TestUser actor, String matchId, String name) async {
    final id = await actor.client.rpc('add_professional_guest', params: {
      'p_match_id': matchId,
      'p_name': name,
    });
    return id as String;
  }

  /// The whole roster in the order the approved rules put it in, so a test can
  /// assert placement without restating the sort.
  Future<List<Map<String, dynamic>>> roster(String matchId) async {
    final rows = await owner.client
        .from('match_registrations')
        .select('user_id, professional_guest_id, status, registration_order')
        .eq('match_id', matchId)
        .order('registration_order', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> guests(String matchId) async {
    final rows = await owner.client
        .from('match_professional_guests')
        .select('id, display_name, created_at')
        .eq('match_id', matchId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  String? statusOfGuest(List<Map<String, dynamic>> rows, String guestId) {
    for (final row in rows) {
      if (row['professional_guest_id'] == guestId) return row['status'] as String;
    }
    return null;
  }

  String? statusOfUser(List<Map<String, dynamic>> rows, String userId) {
    for (final row in rows) {
      if (row['user_id'] == userId) return row['status'] as String;
    }
    return null;
  }

  // --- 1-3: the three operations ---------------------------------------------

  group('the three operations', () {
    test('1. an owner creates a guest, and it is match-scoped', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      final guestId = await addGuest(owner, matchId, 'Zico');

      final rows = await guests(matchId);
      expect(rows, hasLength(1));
      expect(rows.single['id'], guestId);
      expect(rows.single['display_name'], 'Zico');

      // The seat exists and belongs to the guest, not to a user.
      final seat = (await roster(matchId)).single;
      expect(seat['professional_guest_id'], guestId);
      expect(seat['user_id'], isNull);
      expect(seat['registration_order'], 1);
    });

    test('2. deleting a guest takes its seat with it', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final guestId = await addGuest(owner, matchId, 'Zico');

      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
      });

      expect(await guests(matchId), isEmpty);
      expect(await roster(matchId), isEmpty,
          reason: 'the registration cascades from the guest');
    });

    test('3. renaming changes the name and nothing else', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final guestId = await addGuest(owner, matchId, 'Zico');
      final before = (await roster(matchId)).single;

      await owner.client.rpc('rename_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
        'p_name': 'Zico Junior',
      });

      expect((await guests(matchId)).single['display_name'], 'Zico Junior');
      final after = (await roster(matchId)).single;
      expect(after['status'], before['status']);
      expect(after['registration_order'], before['registration_order']);
    });

    test('a guest of another match cannot be named', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final otherId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 18), startingPlayers: 4);
      final guestId = await addGuest(owner, otherId, 'Zico');

      expect(
        await outcomeOf(() async {
          await owner.client.rpc('remove_professional_guest', params: {
            'p_match_id': matchId,
            'p_guest_id': guestId,
          });
        }),
        'GUEST_NOT_FOUND',
      );
    });

    test('a name outside the approved bounds is refused by name', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      expect(await outcomeOf(() => addGuest(owner, matchId, 'A')),
          'INVALID_GUEST_NAME');
      expect(await outcomeOf(() => addGuest(owner, matchId, '   ')),
          'INVALID_GUEST_NAME');
      expect(await outcomeOf(() => addGuest(owner, matchId, 'x' * 61)),
          'INVALID_GUEST_NAME');
      expect(await guests(matchId), isEmpty,
          reason: 'a rejected name leaves no orphan guest row');
    });
  });

  // --- 4-7: authorization ------------------------------------------------------

  group('authorization', () {
    late String matchId;

    setUp(() async {
      matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
    });

    test('4. the owner may manage guests', () async {
      final guestId = await addGuest(owner, matchId, 'Owner Guest');
      expect(guestId, isNotEmpty);
    });

    test('5. an admin may manage guests', () async {
      final guestId = await addGuest(admin, matchId, 'Admin Guest');
      await admin.client.rpc('rename_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
        'p_name': 'Admin Guest II',
      });
      await admin.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
      });
      expect(await guests(matchId), isEmpty);
    });

    test('6. an ordinary player may not', () async {
      expect(await outcomeOf(() => addGuest(player, matchId, 'Nope')),
          'NOT_AUTHORIZED');

      final guestId = await addGuest(owner, matchId, 'Zico');
      expect(
        await outcomeOf(() async {
          await player.client.rpc('remove_professional_guest', params: {
            'p_match_id': matchId,
            'p_guest_id': guestId,
          });
        }),
        'NOT_AUTHORIZED',
      );
      expect(
        await outcomeOf(() async {
          await player.client.rpc('rename_professional_guest', params: {
            'p_match_id': matchId,
            'p_guest_id': guestId,
            'p_name': 'Hacked',
          });
        }),
        'NOT_AUTHORIZED',
      );
    });

    test('7. a non-member may not, and cannot even see the match', () async {
      // `matches_select_community_members` hides the row, so the role check
      // never gets the chance to refuse: MATCH_NOT_FOUND is the correct answer
      // and is the same one a mistyped id gives.
      final outcome = await outcomeOf(() => addGuest(outsider, matchId, 'Nope'));
      expect(outcome, anyOf('MATCH_NOT_FOUND', 'NOT_AUTHORIZED'));
      expect(await guests(matchId), isEmpty);

      // And the guest list itself is not readable by an outsider.
      await addGuest(owner, matchId, 'Zico');
      final visible = await outsider.client
          .from('match_professional_guests')
          .select('id')
          .eq('match_id', matchId);
      expect(visible, isEmpty, reason: 'RLS hides guests from non-members');
    });
  });

  // --- 8-12: every match state -------------------------------------------------

  group('owner/admin management is allowed in every match state', () {
    /// The five approved states, as the schedule that produces each one.
    /// `startingPlayers: 4` is the approved minimum (OP-2).
    Future<String> matchInState(String state) async {
      switch (state) {
        case 'open':
          return createMatch(owner, communityId,
              startsIn: const Duration(days: 17), startingPlayers: 4);
        case 'in progress':
          return createMatch(owner, communityId,
              startsIn: const Duration(hours: -1),
              duration: const Duration(hours: 3),
              startingPlayers: 4);
        case 'after the scheduled time':
        case 'completed':
          return createMatch(owner, communityId,
              startsIn: const Duration(days: -17),
              duration: const Duration(hours: 2),
              startingPlayers: 4);
      }
      throw ArgumentError(state);
    }

    for (final state in const [
      '8. open',
      '10. in progress',
      '11. after the scheduled time',
      '12. completed',
    ]) {
      test('a guest can be added, renamed and removed — $state', () async {
        // '8. open' -> 'open', '12. completed' -> 'completed', and so on.
        final key = state.substring(state.indexOf(' ') + 1);
        final matchId = await matchInState(key);

        if (key == 'completed') {
          // `recompute_match_status` stores `completed` the first time anything
          // touches the match; the row is already past its end time either way.
          await owner.client
              .from('matches')
              .update({'status': 'completed'}).eq('id', matchId);
        }

        final guestId = await addGuest(owner, matchId, 'State Guest');
        await owner.client.rpc('rename_professional_guest', params: {
          'p_match_id': matchId,
          'p_guest_id': guestId,
          'p_name': 'State Guest II',
        });
        expect((await guests(matchId)).single['display_name'],
            'State Guest II');

        await owner.client.rpc('remove_professional_guest', params: {
          'p_match_id': matchId,
          'p_guest_id': guestId,
        });
        expect(await guests(matchId), isEmpty);
      });
    }

    test('9. full — a guest can still be managed once registration closed',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final capacity = (await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single())['max_registration'] as int;

      // Fill the match to the cap with guests, which is the cheapest way to
      // reach `full` without needing more permanent accounts than exist.
      final ids = <String>[];
      for (var i = 0; i < capacity; i++) {
        ids.add(await addGuest(owner, matchId, 'Filler $i'));
      }
      final status = (await owner.client
          .from('matches')
          .select('status')
          .eq('id', matchId)
          .single())['status'] as String;
      expect(status, 'full', reason: 'guests count towards max_registration');

      // Management still works in `full`: removing one and adding one back.
      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': ids.last,
      });
      final replacement = await addGuest(owner, matchId, 'Replacement');
      expect(replacement, isNotEmpty);
    });

    test('self-service is NOT unlocked by any of this', () async {
      // The approved decision unlocks administration only. A player still
      // cannot join or leave a match that has started.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(hours: -1),
          duration: const Duration(hours: 3),
          startingPlayers: 4);

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

    test('an admin may add and remove a community player in a locked match',
        () async {
      // The other half of the same approved decision: the administrative
      // entry points stop asking about the clock.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(hours: -1),
          duration: const Duration(hours: 3),
          startingPlayers: 4);

      final seat = await owner.client.rpc('admin_add_player_to_match', params: {
        'p_match_id': matchId,
        'p_user_id': player.id,
      });
      expect(seat, 'confirmed');

      await owner.client.rpc('remove_player', params: {
        'p_match_id': matchId,
        'p_user_id': player.id,
      });
      expect(await roster(matchId), isEmpty);
    });
  });

  // --- 13-17: capacity and ordering --------------------------------------------

  group('capacity and ordering', () {
    test('13. guests consume the shared capacity and cannot exceed it',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final capacity = (await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single())['max_registration'] as int;

      for (var i = 0; i < capacity; i++) {
        await addGuest(owner, matchId, 'Filler $i');
      }
      expect(await outcomeOf(() => addGuest(owner, matchId, 'One too many')),
          'REGISTRATION_CLOSED');
      expect(await roster(matchId), hasLength(capacity));

      // And a community player is refused by the same cap, not a separate one.
      expect(
        await outcomeOf(() async {
          await player.client
              .rpc('register_for_match', params: {'p_match_id': matchId});
        }),
        'REGISTRATION_CLOSED',
      );
    });

    test('14. a community reserve is promoted before any guest', () async {
      // Two starting slots' worth of community players plus a reserve, then a
      // guest. When a starting player leaves, the community reserve goes up.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      for (final user in [owner, admin, player, player2]) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      // player3 is the fifth community body: reserve.
      await player3.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      final guestId = await addGuest(owner, matchId, 'Waiting Guest');

      expect(statusOfUser(await roster(matchId), player3.id), 'reserve');
      expect(statusOfGuest(await roster(matchId), guestId), 'reserve');

      await player2.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});

      final after = await roster(matchId);
      expect(statusOfUser(after, player3.id), 'confirmed',
          reason: 'the community reserve outranks the guest');
      expect(statusOfGuest(after, guestId), 'reserve');
    });

    test('15. with no community reserve, the earliest guest is promoted (FIFO)',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      for (final user in [owner, admin, player, player2]) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      final first = await addGuest(owner, matchId, 'First Guest');
      final second = await addGuest(owner, matchId, 'Second Guest');

      expect(statusOfGuest(await roster(matchId), first), 'reserve');

      await player2.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});

      final after = await roster(matchId);
      expect(statusOfGuest(after, first), 'confirmed',
          reason: 'FIFO: the guest added first is promoted first');
      expect(statusOfGuest(after, second), 'reserve');
    });

    test('16. a joining community player displaces the latest guest (LIFO)',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      // Two community players and two guests fill the four starting slots.
      for (final user in [owner, admin]) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      final first = await addGuest(owner, matchId, 'First Guest');
      final second = await addGuest(owner, matchId, 'Second Guest');

      var rows = await roster(matchId);
      expect(statusOfGuest(rows, first), 'confirmed');
      expect(statusOfGuest(rows, second), 'confirmed',
          reason: 'guests take starting slots before reserve capacity');

      final seat = await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      expect(seat, 'confirmed',
          reason: 'a community player takes a starting slot from a guest');

      rows = await roster(matchId);
      expect(statusOfGuest(rows, first), 'confirmed');
      expect(statusOfGuest(rows, second), 'reserve',
          reason: 'LIFO: the guest added last is displaced first');
    });

    test('17. multiple guests keep their insertion order', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        ids.add(await addGuest(owner, matchId, 'Guest $i'));
      }

      final rows = await roster(matchId);
      expect(
        [for (final row in rows) row['professional_guest_id']],
        ids,
        reason: 'registration_order is one sequence, shared and in arrival '
            'order',
      );
    });

    test('a community player always sorts ahead of an earlier guest', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      // The guest arrives FIRST, and still loses the starting slot to a
      // community player who arrives later. This is the whole of the priority
      // rule and is the one case a naive `order by registration_order` fails.
      final guestIds = <String>[];
      for (var i = 0; i < 4; i++) {
        guestIds.add(await addGuest(owner, matchId, 'Early Guest $i'));
      }
      for (final user in [owner, admin, player, player2]) {
        final seat = await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
        expect(seat, 'confirmed');
      }

      final rows = await roster(matchId);
      for (final id in guestIds) {
        expect(statusOfGuest(rows, id), 'reserve',
            reason: 'four community players hold all four starting slots');
      }
    });
  });

  // --- 18-20, 25: the schema's own rules ----------------------------------------

  group('the schema', () {
    test('18. two guests with the same name are independent records', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      final a = await addGuest(owner, matchId, 'Ahmed');
      final b = await addGuest(owner, matchId, 'Ahmed');
      expect(a, isNot(b));
      expect(await guests(matchId), hasLength(2));

      // Removing one leaves the other untouched.
      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': a,
      });
      final left = await guests(matchId);
      expect(left, hasLength(1));
      expect(left.single['id'], b);
    });

    test('the same name in another match is an unrelated record', () async {
      final first = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final second = await createMatch(owner, communityId,
          startsIn: const Duration(days: 18), startingPlayers: 4);

      final a = await addGuest(owner, first, 'Ahmed');
      final b = await addGuest(owner, second, 'Ahmed');
      expect(a, isNot(b));
      expect((await guests(first)).single['id'], a);
      expect((await guests(second)).single['id'], b);
    });

    test('19. a guest seat names a guest and no user', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final guestId = await addGuest(owner, matchId, 'Zico');

      final seat = (await roster(matchId)).single;
      expect(seat['professional_guest_id'], guestId);
      expect(seat['user_id'], isNull);
    });

    test('20. a community seat names a user and no guest', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});

      final seat = (await roster(matchId)).single;
      expect(seat['user_id'], player.id);
      expect(seat['professional_guest_id'], isNull);
    });

    test('25. one goalkeeper per team, guests included', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -17),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      final first = await addGuest(owner, matchId, 'Keeper One');
      final second = await addGuest(owner, matchId, 'Keeper Two');

      Future<void> assign(String guestId) => owner.client
              .from('match_team_assignments')
              .insert({
            'match_id': matchId,
            'professional_guest_id': guestId,
            'team': 'A',
            'assigned_position': 'GK',
            'assignment_basis': 'GUEST',
          });

      await assign(first);
      // The partial unique index constrains (match_id, team) where the position
      // is GK, and says nothing about who the participant is.
      await expectLater(assign(second), throwsA(isA<PostgrestException>()));
    });
  });

  // --- 21-24: isolation from the career record ------------------------------------

  group('a guest earns nothing that outlives the match', () {
    late String matchId;
    late String guestId;

    setUp(() async {
      // A match in the past, so a result can be recorded against it.
      matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -18),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      for (final user in [owner, admin, player]) {
        await owner.client.rpc('admin_add_player_to_match', params: {
          'p_match_id': matchId,
          'p_user_id': user.id,
        });
      }
      guestId = await addGuest(owner, matchId, 'Ringer');

      // Two a side: three members and the guest.
      Future<void> assign(String? userId, String? gid, String team,
              String position, String basis) =>
          owner.client.from('match_team_assignments').insert({
            'match_id': matchId,
            if (userId != null) 'user_id': userId,
            if (gid != null) 'professional_guest_id': gid,
            'team': team,
            'assigned_position': position,
            'assignment_basis': basis,
          });

      await assign(owner.id, null, 'A', 'DEF', 'TRANSITION');
      await assign(admin.id, null, 'A', 'MID', 'TRANSITION');
      await assign(player.id, null, 'B', 'MID', 'TRANSITION');
      await assign(null, guestId, 'B', 'FWD', 'GUEST');
    });

    test('21-23. a guest in a recorded result touches no career table',
        () async {
      Future<Map<String, dynamic>?> careerOf(String userId) async =>
          await owner.client
              .from('player_statistics')
              .select('matches_played, wins, losses, goals, mvp_count')
              .eq('user_id', userId)
              .maybeSingle();

      final before = await careerOf(player.id);

      // 2-1 to A. The goals have to add up to the score, so both are credited
      // to community players: `record_match_result` has no guest-scorer
      // parameter yet, and Phase 1 does not give it one. The guest is on the
      // losing side, which is what makes the rating assertions below
      // meaningful — a guest who lost must still lose nothing.
      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 2,
        'p_team_b_score': 1,
        'p_mvp_user_id': player.id,
        'p_goals': [
          {'user_id': owner.id, 'goals': 2},
          {'user_id': player.id, 'goals': 1},
        ],
      });

      // The community player's career moved, so the engine did run and this is
      // not a test that passes because nothing happened.
      final after = await careerOf(player.id);
      expect(after, isNotNull);
      expect(after!['matches_played'],
          ((before?['matches_played'] as int?) ?? 0) + 1);

      // 21. The lineup held four participants; exactly three of them have a
      // career record from this match.
      final lineup = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id')
          .eq('match_id', matchId);
      expect(lineup, hasLength(4), reason: 'the guest did play');
      expect(
        lineup.where((r) => r['professional_guest_id'] != null),
        hasLength(1),
      );

      // 22. No rating_history entry belongs to this match without a user.
      final audit = await owner.client
          .from('rating_history')
          .select('user_id, change_reason')
          .eq('match_id', matchId);
      expect(audit, isNotEmpty, reason: 'the community players were rated');
      for (final row in audit) {
        expect(row['user_id'], isNotNull,
            reason: 'every rating entry names a real account');
      }

      // 23. The guest played, and the count of rated participants is three —
      // the community players — not four.
      final rated = {for (final row in audit) row['user_id'] as String};
      expect(rated, {owner.id, admin.id, player.id});
    });

    test('24. a guest can be stored as the match MVP and can score', () async {
      // Migration `0049`: the score is 1-1 and the guest scored one of them,
      // which is why a guest goal has to be recordable at all — the tallies
      // must add up to the score.
      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 1,
        'p_team_b_score': 1,
        'p_mvp_user_id': null,
        'p_mvp_professional_guest_id': guestId,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'professional_guest_id': guestId, 'goals': 1},
        ],
      });

      final result = await owner.client
          .from('match_results')
          .select('mvp_user_id, mvp_professional_guest_id')
          .eq('match_id', matchId)
          .single();
      expect(result['mvp_professional_guest_id'], guestId);
      expect(result['mvp_user_id'], isNull);

      final tally = await owner.client
          .from('match_goals')
          .select('user_id, professional_guest_id, goals')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId)
          .single();
      expect(tally['goals'], 1);
      expect(tally['user_id'], isNull);

      // And none of it reached a career record.
      final audit = await owner.client
          .from('rating_history')
          .select('user_id')
          .eq('match_id', matchId);
      for (final row in audit) {
        expect(row['user_id'], isNotNull);
      }
    });

    test('naming two best players is refused', () async {
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('record_match_result', params: {
            'p_match_id': matchId,
            'p_team_a_score': 1,
            'p_team_b_score': 1,
            'p_mvp_user_id': player.id,
            'p_mvp_professional_guest_id': guestId,
            'p_goals': [
              {'user_id': owner.id, 'goals': 1},
              {'user_id': player.id, 'goals': 1},
            ],
          });
        }),
        'INVALID_MVP',
      );
    });

    test('correcting a guest MVP to a user MVP clears the guest', () async {
      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 1,
        'p_team_b_score': 1,
        'p_mvp_user_id': null,
        'p_mvp_professional_guest_id': guestId,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'professional_guest_id': guestId, 'goals': 1},
        ],
      });

      // The mutual-exclusion constraint would refuse a correction that set the
      // user column without clearing the guest one, so this is the assertion
      // that both are written as a pair.
      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 1,
        'p_team_b_score': 1,
        'p_mvp_user_id': player.id,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'user_id': player.id, 'goals': 1},
        ],
      });

      final row = await owner.client
          .from('match_results')
          .select('mvp_user_id, mvp_professional_guest_id')
          .eq('match_id', matchId)
          .single();
      expect(row['mvp_user_id'], player.id);
      expect(row['mvp_professional_guest_id'], isNull);
    });
  });

  // --- concurrency ----------------------------------------------------------------

  group('concurrency', () {
    test('concurrent guest additions cannot exceed capacity', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final capacity = (await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single())['max_registration'] as int;

      // Fill to one below the cap, then race two administrators for the last
      // place. The match row lock is what has to make this one and one.
      for (var i = 0; i < capacity - 1; i++) {
        await addGuest(owner, matchId, 'Filler $i');
      }

      final outcomes = await Future.wait([
        outcomeOf(() => addGuest(owner, matchId, 'Race A')),
        outcomeOf(() => addGuest(admin, matchId, 'Race B')),
      ]);

      expect(outcomes..sort(), ['ALLOW', 'REGISTRATION_CLOSED']);
      expect(await roster(matchId), hasLength(capacity));
      expect(await guests(matchId), hasLength(capacity),
          reason: 'the refused addition left no orphan guest row');
    });

    test('a community registration and a guest addition cannot both take the '
        'last place', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final capacity = (await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', matchId)
          .single())['max_registration'] as int;

      for (var i = 0; i < capacity - 1; i++) {
        await addGuest(owner, matchId, 'Filler $i');
      }

      final outcomes = await Future.wait([
        outcomeOf(() => addGuest(admin, matchId, 'Race Guest')),
        outcomeOf(() async {
          await player.client
              .rpc('register_for_match', params: {'p_match_id': matchId});
        }),
      ]);

      expect(outcomes..sort(), ['ALLOW', 'REGISTRATION_CLOSED']);
      expect(await roster(matchId), hasLength(capacity));
    });

    test('concurrent displacement preserves the ordering rules', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      // Four guests hold every starting slot.
      final guestIds = <String>[];
      for (var i = 0; i < 4; i++) {
        guestIds.add(await addGuest(owner, matchId, 'Guest $i'));
      }

      // Two community players arrive at once. Both must start, and the two
      // guests displaced must be the last two — whichever order the races
      // resolve in.
      final seats = await Future.wait([
        player.client.rpc('register_for_match', params: {'p_match_id': matchId}),
        player2.client
            .rpc('register_for_match', params: {'p_match_id': matchId}),
      ]);
      expect(seats.map((s) => s as String).toList(), ['confirmed', 'confirmed']);

      final rows = await roster(matchId);
      expect(statusOfGuest(rows, guestIds[0]), 'confirmed');
      expect(statusOfGuest(rows, guestIds[1]), 'confirmed');
      expect(statusOfGuest(rows, guestIds[2]), 'reserve');
      expect(statusOfGuest(rows, guestIds[3]), 'reserve');

      final confirmed =
          rows.where((r) => r['status'] == 'confirmed').length;
      expect(confirmed, 4, reason: 'never more starters than starting_players');
    });
  });

  // --- the correction cycle ---------------------------------------------------
  //
  // Administration in every state, and the line between the **current roster**
  // and **historical performance**. Removing somebody from the first must never
  // touch the second: the match has been played, and the record of it is not the
  // roster's to edit.

  group('completed-match administration preserves what was played', () {
    late String matchId;
    late String guestId;

    setUp(() async {
      matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      for (final user in [owner, admin, player]) {
        await owner.client.rpc('admin_add_player_to_match', params: {
          'p_match_id': matchId,
          'p_user_id': user.id,
        });
      }
      guestId = await addGuest(owner, matchId, 'Ringer');

      Future<void> assign(String? userId, String? gid, String team,
              String position, String basis) =>
          owner.client.from('match_team_assignments').insert({
            'match_id': matchId,
            if (userId != null) 'user_id': userId,
            if (gid != null) 'professional_guest_id': gid,
            'team': team,
            'assigned_position': position,
            'assignment_basis': basis,
          });

      await assign(owner.id, null, 'A', 'DEF', 'TRANSITION');
      await assign(admin.id, null, 'A', 'MID', 'TRANSITION');
      await assign(player.id, null, 'B', 'MID', 'TRANSITION');
      await assign(null, guestId, 'B', 'FWD', 'GUEST');

      // 1-1, and the guest scored one of them, so the guest has a goal, an MVP
      // award and a side — all three of the things that must survive removal.
      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 1,
        'p_team_b_score': 1,
        'p_mvp_user_id': null,
        'p_mvp_professional_guest_id': guestId,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'professional_guest_id': guestId, 'goals': 1},
        ],
      });
    });

    Future<String> editBy(TestUser actor, String title) => outcomeOf(() async {
          // The same past window, so the edit does not reschedule the match out
          // of the completed state it is being edited in.
          final start =
              DateTime.now().toUtc().subtract(const Duration(days: 19));
          await actor.client.rpc('update_match', params: {
            'p_match_id': matchId,
            'p_title': title,
            'p_location': 'Corrected pitch',
            'p_start_at': start.toIso8601String(),
            'p_end_at':
                start.add(const Duration(hours: 2)).toIso8601String(),
            'p_starting_players': 4,
            'p_description': null,
          });
        });

    Future<List<Map<String, dynamic>>> lineup() async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id, team, assigned_position, '
              'assignment_basis')
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows);
    }

    test('an owner can update a completed match', () async {
      expect(await editBy(owner, 'ITest owner corrected'), 'ALLOW');
      final row = await owner.client
          .from('matches')
          .select('title')
          .eq('id', matchId)
          .single();
      expect(row['title'], 'ITest owner corrected');
    });

    test('an admin can update a completed match', () async {
      expect(await editBy(admin, 'ITest admin corrected'), 'ALLOW');
      final row = await owner.client
          .from('matches')
          .select('title')
          .eq('id', matchId)
          .single();
      expect(row['title'], 'ITest admin corrected');
    });

    test('an ordinary player still cannot update it', () async {
      expect(await editBy(player, 'ITest not allowed'), 'NOT_AUTHORIZED');
    });

    test('editing a completed match demotes nobody', () async {
      final before = await roster(matchId);
      expect(await editBy(owner, 'ITest corrected'), 'ALLOW');
      final after = await roster(matchId);
      expect(
        [for (final r in after) r['status']],
        [for (final r in before) r['status']],
        reason: 'a played match keeps the roster it played with',
      );
      expect(await lineup(), hasLength(4));
    });

    test('removing a community player keeps their historical performance',
        () async {
      Future<int?> playedBy(String userId) async {
        final row = await owner.client
            .from('player_statistics')
            .select('matches_played')
            .eq('user_id', userId)
            .maybeSingle();
        return row?['matches_played'] as int?;
      }

      final playedBefore = await playedBy(player.id);

      await owner.client.rpc('remove_player', params: {
        'p_match_id': matchId,
        'p_user_id': player.id,
      });

      // Off the current roster...
      expect(statusOfUser(await roster(matchId), player.id), isNull);

      // ...and still in the record of what happened.
      final rows = await lineup();
      expect(rows.where((r) => r['user_id'] == player.id), hasLength(1),
          reason: 'the side they played on is historical performance');
      expect(await playedBy(player.id), playedBefore,
          reason: 'no statistic is reversed by a roster change');
    });

    test('removing a guest keeps identity, side, goal and MVP', () async {
      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
      });

      // Off the current roster.
      expect(statusOfGuest(await roster(matchId), guestId), isNull);

      // The identity survives, so the completed match can still name them.
      final identities = await guests(matchId);
      expect(identities, hasLength(1));
      expect(identities.single['id'], guestId);

      // The side they played on survives, with its GUEST basis.
      final guestRow = (await lineup())
          .firstWhere((r) => r['professional_guest_id'] == guestId);
      expect(guestRow['team'], 'B');
      expect(guestRow['assigned_position'], 'FWD');
      expect(guestRow['assignment_basis'], 'GUEST');

      // The goal survives.
      final tally = await owner.client
          .from('match_goals')
          .select('goals')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId)
          .single();
      expect(tally['goals'], 1);

      // The MVP reference survives and still names them.
      final result = await owner.client
          .from('match_results')
          .select('mvp_professional_guest_id, team_a_score, team_b_score')
          .eq('match_id', matchId)
          .single();
      expect(result['mvp_professional_guest_id'], guestId);
      expect(result['team_a_score'], 1);
      expect(result['team_b_score'], 1);
    });

    test('a removed guest is still shown by v_match_teams', () async {
      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
      });

      final rows = await owner.client
          .from('v_match_teams')
          .select('participant_type, display_name, goals, is_mvp, '
              'professional_guest_id')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId);
      expect(rows, hasLength(1));
      expect(rows.first['participant_type'], 'PROFESSIONAL');
      expect(rows.first['display_name'], 'Ringer');
      expect(rows.first['goals'], 1);
      expect(rows.first['is_mvp'], isTrue);
    });

    test('replace_match_lineup leaves guest assignments alone', () async {
      // The community half only, which is exactly what the team-generation
      // screen sends: it knows nothing about guests.
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          {
            'user_id': owner.id,
            'team': 'A',
            'assigned_position': 'DEF',
            'assignment_basis': 'TRANSITION',
          },
          {
            'user_id': admin.id,
            'team': 'B',
            'assigned_position': 'MID',
            'assignment_basis': 'TRANSITION',
          },
          {
            'user_id': player.id,
            'team': 'B',
            'assigned_position': 'MID',
            'assignment_basis': 'TRANSITION',
          },
        ],
      });

      final rows = await lineup();
      expect(rows, hasLength(4), reason: 'the guest was not swept away');
      final guestRow =
          rows.firstWhere((r) => r['professional_guest_id'] == guestId);
      expect(guestRow['team'], 'B');
      expect(guestRow['assigned_position'], 'FWD');
      expect(guestRow['assignment_basis'], 'GUEST');

      // The community half was replaced: admin moved from A to B.
      final adminRow = rows.firstWhere((r) => r['user_id'] == admin.id);
      expect(adminRow['team'], 'B');
    });

    test('replace_match_lineup moves a guest when the payload names one',
        () async {
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          {
            'user_id': owner.id,
            'team': 'A',
            'assigned_position': 'DEF',
            'assignment_basis': 'TRANSITION',
          },
          {
            'user_id': admin.id,
            'team': 'A',
            'assigned_position': 'MID',
            'assignment_basis': 'TRANSITION',
          },
          {
            'user_id': player.id,
            'team': 'B',
            'assigned_position': 'MID',
            'assignment_basis': 'TRANSITION',
          },
          {
            'professional_guest_id': guestId,
            'team': 'A',
            'assigned_position': 'FWD',
            // Deliberately wrong: a guest has no profile, so the basis is
            // forced to GUEST rather than taken from the caller.
            'assignment_basis': 'PRIMARY',
          },
        ],
      });

      final guestRow = (await lineup())
          .firstWhere((r) => r['professional_guest_id'] == guestId);
      expect(guestRow['team'], 'A');
      expect(guestRow['assignment_basis'], 'GUEST');
    });

    test('a lineup that drops the guest MVP is still refused', () async {
      // The guest half is only replaced where the payload names it, so dropping
      // the MVP means naming them and putting them nowhere — which is what a
      // future guest-removal UI would do, and what the result forbids.
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('replace_match_lineup', params: {
            'p_match_id': matchId,
            'p_assignments': [
              {
                'user_id': owner.id,
                'team': 'A',
                'assigned_position': 'DEF',
                'assignment_basis': 'TRANSITION',
              },
            ],
          });
        }),
        'RESULT_PARTICIPANT_REMOVED',
        reason: 'owner scored, and dropping him orphans his goal',
      );
    });
  });

  group('the read models represent both kinds of participant', () {
    test('v_match_registrations includes Professional Guests', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      await player.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      final guestId = await addGuest(owner, matchId, 'Zico');

      final rows = await owner.client
          .from('v_match_registrations')
          .select('user_id, professional_guest_id, participant_type, '
              'display_name, full_name, status')
          .eq('match_id', matchId)
          .order('registration_order', ascending: true);
      expect(rows, hasLength(2),
          reason: 'the guest is a row, not a silently dropped one');

      final user = rows.firstWhere((r) => r['participant_type'] == 'USER');
      expect(user['user_id'], player.id);
      expect(user['professional_guest_id'], isNull);
      expect(user['display_name'], player.name);

      final guest =
          rows.firstWhere((r) => r['participant_type'] == 'PROFESSIONAL');
      expect(guest['professional_guest_id'], guestId);
      expect(guest['user_id'], isNull);
      expect(guest['display_name'], 'Zico');
      expect(guest['full_name'], isNull,
          reason: 'full_name is a profile fact, and a guest has no profile');
    });

    test('v_match_teams includes Professional Guests', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      final guestId = await addGuest(owner, matchId, 'Zico');
      await owner.client.from('match_team_assignments').insert([
        {
          'match_id': matchId,
          'user_id': owner.id,
          'team': 'A',
          'assigned_position': 'MID',
          'assignment_basis': 'TRANSITION',
        },
        {
          'match_id': matchId,
          'professional_guest_id': guestId,
          'team': 'B',
          'assigned_position': 'FWD',
          'assignment_basis': 'GUEST',
        },
      ]);

      final rows = await owner.client
          .from('v_match_teams')
          .select('user_id, professional_guest_id, participant_type, '
              'display_name, is_out_of_position, is_mvp')
          .eq('match_id', matchId);
      expect(rows, hasLength(2));

      final guest =
          rows.firstWhere((r) => r['participant_type'] == 'PROFESSIONAL');
      expect(guest['display_name'], 'Zico');
      expect(guest['user_id'], isNull);
      expect(guest['is_out_of_position'], isFalse,
          reason: 'a GUEST basis is not TRANSITION');
      expect(guest['is_mvp'], isFalse,
          reason: 'no result, so nobody is the MVP — false, not null');
    });
  });

  group('the XOR still holds', () {
    late String matchId;
    late String guestId;

    setUp(() async {
      matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      guestId = await addGuest(owner, matchId, 'Zico');
    });

    test('a lineup row naming both a user and a guest is refused', () async {
      await expectLater(
        owner.client.from('match_team_assignments').insert({
          'match_id': matchId,
          'user_id': owner.id,
          'professional_guest_id': guestId,
          'team': 'A',
          'assigned_position': 'MID',
          'assignment_basis': 'GUEST',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a lineup row naming neither is refused', () async {
      await expectLater(
        owner.client.from('match_team_assignments').insert({
          'match_id': matchId,
          'team': 'A',
          'assigned_position': 'MID',
          'assignment_basis': 'GUEST',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    // Migration 0051. A position is required of a registered player and
    // optional for a Professional Guest, who has no profile for one to be
    // derived against.
    test('9. a registered player with no position is refused', () async {
      await expectLater(
        owner.client.from('match_team_assignments').insert({
          'match_id': matchId,
          'user_id': owner.id,
          'team': 'A',
          'assigned_position': null,
          'assignment_basis': 'TRANSITION',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('10. a guest with no position is accepted', () async {
      await owner.client.from('match_team_assignments').insert({
        'match_id': matchId,
        'professional_guest_id': guestId,
        'team': 'A',
        'assigned_position': null,
        'assignment_basis': 'GUEST',
      });

      final row = await owner.client
          .from('match_team_assignments')
          .select('assigned_position, assignment_basis, user_id')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId)
          .single();
      expect(row['assigned_position'], isNull);
      expect(row['assignment_basis'], 'GUEST');
      expect(row['user_id'], isNull);
    });

    test('5. one goalkeeper per team is unaffected by a positionless guest',
        () async {
      // The index is `where assigned_position = 'GK'`, so a null row is not in
      // it — and a real GK still cannot be doubled up on a side.
      await owner.client.from('match_team_assignments').insert({
        'match_id': matchId,
        'professional_guest_id': guestId,
        'team': 'A',
        'assigned_position': null,
        'assignment_basis': 'GUEST',
      });
      await owner.client.from('match_team_assignments').insert({
        'match_id': matchId,
        'user_id': owner.id,
        'team': 'A',
        'assigned_position': 'GK',
        'assignment_basis': 'PRIMARY',
      });

      await expectLater(
        owner.client.from('match_team_assignments').insert({
          'match_id': matchId,
          'user_id': admin.id,
          'team': 'A',
          'assigned_position': 'GK',
          'assignment_basis': 'PRIMARY',
        }),
        throwsA(isA<PostgrestException>()),
        reason: 'one goalkeeper per team, exactly as before',
      );
    });

    test('a position outside the four codes is still refused', () async {
      await expectLater(
        owner.client.from('match_team_assignments').insert({
          'match_id': matchId,
          'professional_guest_id': guestId,
          'team': 'A',
          'assigned_position': 'SWEEPER',
          'assignment_basis': 'GUEST',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a goal naming both is refused by record_match_result', () async {
      await owner.client.from('match_team_assignments').insert({
        'match_id': matchId,
        'user_id': owner.id,
        'team': 'A',
        'assigned_position': 'MID',
        'assignment_basis': 'TRANSITION',
      });

      expect(
        await outcomeOf(() async {
          await owner.client.rpc('record_match_result', params: {
            'p_match_id': matchId,
            'p_team_a_score': 1,
            'p_team_b_score': 0,
            'p_mvp_user_id': null,
            'p_goals': [
              {
                'user_id': owner.id,
                'professional_guest_id': guestId,
                'goals': 1,
              },
            ],
          });
        }),
        'INVALID_GOALS',
      );
    });
  });

  group('ordinary player behaviour is unchanged', () {
    test('a guest-free match registers, fills and promotes exactly as before',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);

      for (final user in [owner, admin, player, player2]) {
        expect(
          await user.client
              .rpc('register_for_match', params: {'p_match_id': matchId}),
          'confirmed',
        );
      }
      expect(
        await player3.client
            .rpc('register_for_match', params: {'p_match_id': matchId}),
        'reserve',
        reason: 'the fifth body waits, exactly as it always did',
      );

      await player2.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});
      expect(statusOfUser(await roster(matchId), player3.id), 'confirmed');

      // And every seat still names a user and no guest.
      for (final row in await roster(matchId)) {
        expect(row['user_id'], isNotNull);
        expect(row['professional_guest_id'], isNull);
      }
    });

    test('self-service still refuses a started match', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(hours: -1),
          duration: const Duration(hours: 3),
          startingPlayers: 4);
      expect(
        await outcomeOf(() async {
          await player.client
              .rpc('register_for_match', params: {'p_match_id': matchId});
        }),
        'MATCH_LOCKED',
      );
    });
  });

  // --- a completed match stays completed ----------------------------------------
  //
  // `update_match` recomputes the status from the stored `end_at`, so moving a
  // completed match's schedule forward used to reopen it for registration — with
  // its lineup, result, goals and MVP still recorded against it. The status of a
  // played match is now preserved from the row as it was *before* the edit.
  //
  // None of this restricts the edit. An owner or admin moves the times of a
  // completed match freely; it simply stays completed.

  group('a completed match stays completed', () {
    late String matchId;

    Future<String?> statusOf(String id) async {
      final row = await owner.client
          .from('matches')
          .select('status')
          .eq('id', id)
          .maybeSingle();
      return row?['status'] as String?;
    }

    /// [startsIn] and [duration] are the *new* schedule the edit writes.
    Future<String> editBy(
      TestUser actor,
      String id, {
      required String title,
      Duration startsIn = const Duration(days: -19),
      Duration duration = const Duration(hours: 2),
      int startingPlayers = 4,
    }) =>
        outcomeOf(() async {
          final start = DateTime.now().toUtc().add(startsIn);
          await actor.client.rpc('update_match', params: {
            'p_match_id': id,
            'p_title': title,
            'p_location': 'Corrected pitch',
            'p_start_at': start.toIso8601String(),
            'p_end_at': start.add(duration).toIso8601String(),
            'p_starting_players': startingPlayers,
            'p_description': null,
          });
        });

    setUp(() async {
      matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      // Stored as completed, which is the state a real finished match reaches
      // the first time anything touches it.
      await owner.client
          .from('matches')
          .update({'status': 'completed'}).eq('id', matchId);
    });

    test('1. moving end_at into the future leaves it completed', () async {
      // The schedule now ends four days from now, and the match is still a
      // match that was played.
      expect(
        await editBy(owner, matchId,
            title: 'ITest end moved',
            startsIn: const Duration(days: 3),
            duration: const Duration(days: 1)),
        'ALLOW',
      );
      expect(await statusOf(matchId), 'completed');
    });

    test('2. moving start_at into the future leaves it completed', () async {
      expect(
        await editBy(owner, matchId,
            title: 'ITest start moved',
            startsIn: const Duration(days: 5),
            duration: const Duration(hours: 2)),
        'ALLOW',
      );
      expect(await statusOf(matchId), 'completed');
    });

    test('3. an ordinary field edit leaves it completed', () async {
      expect(await editBy(owner, matchId, title: 'ITest renamed'), 'ALLOW');
      expect(await statusOf(matchId), 'completed');
      final row = await owner.client
          .from('matches')
          .select('title, location')
          .eq('id', matchId)
          .single();
      expect(row['title'], 'ITest renamed');
      expect(row['location'], 'Corrected pitch');
    });

    test('4. an owner may make the edit', () async {
      expect(
        await editBy(owner, matchId,
            title: 'ITest owner edit', startsIn: const Duration(days: 4)),
        'ALLOW',
      );
      expect(await statusOf(matchId), 'completed');
    });

    test('5. an admin may make the edit', () async {
      expect(
        await editBy(admin, matchId,
            title: 'ITest admin edit', startsIn: const Duration(days: 4)),
        'ALLOW',
      );
      expect(await statusOf(matchId), 'completed');
    });

    test('7. a completed time edit rebalances nobody', () async {
      // Five confirmed players in a match with four starting slots.
      // `set_completed_match_player` confirms without regard to
      // `starting_players`, which is the state a rebalance would demote out of.
      const positions = ['DEF', 'MID', 'FWD', 'MID', 'DEF'];
      const teams = ['A', 'A', 'A', 'B', 'B'];
      final squad = [owner, admin, player, player2, player3];
      for (var i = 0; i < squad.length; i++) {
        await owner.client.rpc('set_completed_match_player', params: {
          'p_match_id': matchId,
          'p_user_id': squad[i].id,
          'p_team': teams[i],
          'p_assigned_position': positions[i],
        });
      }

      final before = await roster(matchId);
      expect(before, hasLength(5));
      expect(before.where((r) => r['status'] == 'confirmed'), hasLength(5));

      expect(
        await editBy(owner, matchId,
            title: 'ITest rebalance probe',
            startsIn: const Duration(days: 6)),
        'ALLOW',
      );

      final after = await roster(matchId);
      expect(after.where((r) => r['status'] == 'confirmed'), hasLength(5),
          reason: 'a played match is not re-cut to starting_players');
      expect(
        [for (final r in after) r['status']],
        [for (final r in before) r['status']],
      );
      expect(await statusOf(matchId), 'completed');

      // And nobody was told they had been moved.
      for (final user in squad) {
        final moved = await user.client
            .from('notifications')
            .select('id')
            .eq('match_id', matchId)
            .eq('type', 'moved_to_reserve');
        expect(moved, isEmpty,
            reason: 'no demotion notice for a match already played');
      }
    });

    test('a match past its end time but not yet stored completed is settled',
        () async {
      // The status is written lazily, so a finished match can still read `open`.
      // The edit must settle it rather than leave it there.
      final lazy = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      expect(await statusOf(lazy), 'open');

      expect(
        await editBy(owner, lazy,
            title: 'ITest lazy', startsIn: const Duration(days: 6)),
        'ALLOW',
      );
      expect(await statusOf(lazy), 'completed');
    });

    test('6. an Open match still recomputes its status exactly as before',
        () async {
      final open = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      expect(await statusOf(open), 'open');

      // An edit that keeps it in the future leaves it open.
      expect(
        await editBy(owner, open,
            title: 'ITest still open', startsIn: const Duration(days: 18)),
        'ALLOW',
      );
      expect(await statusOf(open), 'open');

      // And an edit that moves it into the past still completes it — the
      // recomputation is untouched for a match that had not been played.
      expect(
        await editBy(owner, open,
            title: 'ITest now past', startsIn: const Duration(days: -18)),
        'ALLOW',
      );
      expect(await statusOf(open), 'completed',
          reason: 'Open/Full recomputation is unchanged in both directions');
    });

    test('6b. a Full match still recomputes to Open when capacity grows',
        () async {
      // Four starting slots plus the global reserve of six is ten places;
      // guests are the cheapest way to reach the cap with five accounts.
      final full = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final capacity = (await owner.client
          .from('matches')
          .select('max_registration')
          .eq('id', full)
          .single())['max_registration'] as int;
      for (var i = 0; i < capacity; i++) {
        await addGuest(owner, full, 'Filler $i');
      }
      expect(await statusOf(full), 'full');

      // A larger starting count derives a larger maximum, so the match reopens
      // — which is the existing recomputation, and it must still happen.
      expect(
        await editBy(owner, full,
            title: 'ITest reopened by capacity',
            startsIn: const Duration(days: 18),
            startingPlayers: 5),
        'ALLOW',
      );
      expect(await statusOf(full), 'open');
    });
  });

  // --- alternating guest teams, and lineup regeneration -------------------------
  //
  // Migration `0050`. Two rules the client cannot own: which side a Professional
  // Guest plays on, and when a stored lineup has stopped describing the roster.
  //
  // Neither is a change to the engine. The community teams below are written the
  // way the application writes them — `replace_match_lineup` with the confirmed
  // community players and nothing else — and the database places the guests
  // around that result afterwards.

  group('guests take alternating sides', () {
    Future<List<Map<String, dynamic>>> lineup(String matchId) async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id, team, assigned_position, '
              'assignment_basis')
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows);
    }

    String? teamOfGuest(List<Map<String, dynamic>> rows, String guestId) {
      for (final row in rows) {
        if (row['professional_guest_id'] == guestId) {
          return row['team'] as String;
        }
      }
      return null;
    }

    /// The community half of a lineup, written exactly as the application
    /// writes it: engine output for the confirmed community players only.
    Future<void> saveCommunityLineup(String matchId, List<TestUser> squad) =>
        owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            for (final (index, user) in squad.indexed)
              {
                'user_id': user.id,
                'team': index.isEven ? 'A' : 'B',
                'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
                'assignment_basis': 'TRANSITION',
              },
          ],
        });

    /// Eight starting slots so four guests can be *starting*: community players
    /// always fill the first seats, so a guest only starts when the count
    /// exceeds the community roster.
    Future<String> matchWithSlots(int startingPlayers) => createMatch(
          owner,
          communityId,
          startsIn: const Duration(days: 17),
          startingPlayers: startingPlayers,
        );

    test('1-4. four guests are placed A, B, A, B in addition order', () async {
      final matchId = await matchWithSlots(8);
      final squad = [owner, admin, player, player2];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveCommunityLineup(matchId, squad);

      final ids = <String>[];
      for (var i = 1; i <= 4; i++) {
        ids.add(await addGuest(owner, matchId, 'Guest $i'));
      }

      final rows = await lineup(matchId);
      expect(teamOfGuest(rows, ids[0]), 'A');
      expect(teamOfGuest(rows, ids[1]), 'B');
      expect(teamOfGuest(rows, ids[2]), 'A');
      expect(teamOfGuest(rows, ids[3]), 'B');

      for (final id in ids) {
        final row = rows.firstWhere((r) => r['professional_guest_id'] == id);
        expect(row['assignment_basis'], 'GUEST');
        expect(row['user_id'], isNull);
        // Migration 0051: a side is decided for them, a position is not
        // invented for them.
        expect(row['assigned_position'], isNull);
      }
    });

    test('the alternation holds when the guests precede the lineup', () async {
      // The other order: guests added first, teams generated afterwards. The
      // placement is a property of the current state, not of the sequence.
      final matchId = await matchWithSlots(8);
      final squad = [owner, admin, player, player2];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }

      final ids = <String>[];
      for (var i = 1; i <= 4; i++) {
        ids.add(await addGuest(owner, matchId, 'Guest $i'));
      }
      expect(await lineup(matchId), isEmpty,
          reason: 'no guest stands on a pitch that has not been picked');

      await saveCommunityLineup(matchId, squad);

      final rows = await lineup(matchId);
      expect(teamOfGuest(rows, ids[0]), 'A');
      expect(teamOfGuest(rows, ids[1]), 'B');
      expect(teamOfGuest(rows, ids[2]), 'A');
      expect(teamOfGuest(rows, ids[3]), 'B');
    });

    test('removing a guest re-alternates the rest', () async {
      final matchId = await matchWithSlots(8);
      final squad = [owner, admin, player, player2];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveCommunityLineup(matchId, squad);

      final ids = <String>[];
      for (var i = 1; i <= 4; i++) {
        ids.add(await addGuest(owner, matchId, 'Guest $i'));
      }

      await owner.client.rpc('remove_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': ids[0],
      });

      final rows = await lineup(matchId);
      expect(teamOfGuest(rows, ids[0]), isNull);
      expect(teamOfGuest(rows, ids[1]), 'A');
      expect(teamOfGuest(rows, ids[2]), 'B');
      expect(teamOfGuest(rows, ids[3]), 'A');
    });

    // --- a side an organizer chose (migration 0058) --------------------------
    //
    // The alternation re-runs at the end of every lineup write, and its upsert
    // used to set the team unconditionally: a guest moved to the other side was
    // moved back by the very call that saved the move. These prove the column
    // that stops it, and the one operation that still clears it.

    /// A move, as `TeamRepository.movePlayer` sends it: the whole lineup back
    /// with one guest row on the other side, marked as chosen.
    Future<void> moveGuest(
      String matchId,
      List<TestUser> squad,
      String guestId,
      String toTeam,
    ) =>
        owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            for (final (index, user) in squad.indexed)
              {
                'user_id': user.id,
                'team': index.isEven ? 'A' : 'B',
                'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
                'assignment_basis': 'TRANSITION',
              },
            {
              'professional_guest_id': guestId,
              'team': toTeam,
              'assigned_position': null,
              'assignment_basis': 'GUEST',
              'team_manually_overridden': true,
            },
          ],
        });

    Future<String> startedMatchWithSquad(List<TestUser> squad) async {
      final matchId = await matchWithSlots(8);
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveCommunityLineup(matchId, squad);
      return matchId;
    }

    test('a chosen side survives the write that saves it', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');

      // First guest added, so the alternation put them on A.
      expect(teamOfGuest(await lineup(matchId), guestId), 'A');

      await moveGuest(matchId, squad, guestId, 'B');

      expect(teamOfGuest(await lineup(matchId), guestId), 'B',
          reason: 'the alternation that runs at the end of this same call must '
              'leave a chosen side alone');
    });

    test('and survives an ordinary later save', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      await moveGuest(matchId, squad, guestId, 'B');

      // Another manual save saying nothing about the guest — a community player
      // rearranged, which is the common case.
      await saveCommunityLineup(matchId, squad);

      expect(teamOfGuest(await lineup(matchId), guestId), 'B');
    });

    test('and is given up by a generation', () async {
      // `BTGE-MO-2`: a fresh search discards what was adjusted around the teams
      // it replaces, and a guest's chosen side is such an adjustment.
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      await moveGuest(matchId, squad, guestId, 'B');
      expect(teamOfGuest(await lineup(matchId), guestId), 'B');

      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          for (final (index, user) in squad.indexed)
            {
              'user_id': user.id,
              'team': index.isEven ? 'A' : 'B',
              'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
              'assignment_basis': 'TRANSITION',
            },
        ],
        'p_from_generation': true,
      });

      expect(teamOfGuest(await lineup(matchId), guestId), 'A',
          reason: 'the automatic A, B, A, B policy applies again');
    });

    test('the two-argument call still works and keeps a chosen side', () async {
      // A client older than 0058 calls this function with two arguments. The
      // default resolves it to the same body with `p_from_generation => false`,
      // so nothing is cleared by a client that never asked to clear it.
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      await moveGuest(matchId, squad, guestId, 'B');

      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          for (final (index, user) in squad.indexed)
            {
              'user_id': user.id,
              'team': index.isEven ? 'A' : 'B',
              'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
              'assignment_basis': 'TRANSITION',
            },
        ],
      });

      expect(teamOfGuest(await lineup(matchId), guestId), 'B');
    });

    test('a pinned guest still holds its place in the alternation', () async {
      // The sequence decides everybody else's side. A pinned guest is counted
      // by it rather than skipped, so the guests added after them keep the
      // seats they had.
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);

      final ids = <String>[];
      for (var i = 1; i <= 3; i++) {
        ids.add(await addGuest(owner, matchId, 'Guest $i'));
      }
      // A, B, A by addition order.
      expect(teamOfGuest(await lineup(matchId), ids[1]), 'B');

      // Pin the second guest onto A, where the alternation would not put them.
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          for (final (index, user) in squad.indexed)
            {
              'user_id': user.id,
              'team': index.isEven ? 'A' : 'B',
              'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
              'assignment_basis': 'TRANSITION',
            },
          {
            'professional_guest_id': ids[1],
            'team': 'A',
            'assigned_position': null,
            'assignment_basis': 'GUEST',
            'team_manually_overridden': true,
          },
        ],
      });

      final rows = await lineup(matchId);
      expect(teamOfGuest(rows, ids[0]), 'A');
      expect(teamOfGuest(rows, ids[1]), 'A', reason: 'chosen, and kept');
      expect(teamOfGuest(rows, ids[2]), 'A',
          reason: 'still the third seat in the order, so still A');
    });

    // --- a position, and not playing after all (migration 0059) --------------

    /// Writes the lineup with one guest carrying [position].
    Future<void> saveGuestPosition(
      String matchId,
      List<TestUser> squad,
      String guestId,
      String? position,
    ) =>
        owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            for (final (index, user) in squad.indexed)
              {
                'user_id': user.id,
                'team': index.isEven ? 'A' : 'B',
                'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
                'assignment_basis': 'TRANSITION',
              },
            {
              'professional_guest_id': guestId,
              'team': 'A',
              'assigned_position': position,
              'assignment_basis': 'GUEST',
            },
          ],
        });

    Future<Map<String, dynamic>?> guestRow(
        String matchId, String guestId) async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('professional_guest_id, user_id, team, assigned_position, '
              'assignment_basis, team_manually_overridden')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId);
      final list = List<Map<String, dynamic>>.from(rows);
      return list.isEmpty ? null : list.single;
    }

    test('a guest carries any of the four positions, or none', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');

      for (final position in ['GK', 'DEF', 'MID', 'FWD']) {
        await saveGuestPosition(matchId, squad, guestId, position);
        final row = await guestRow(matchId, guestId);
        expect(row!['assigned_position'], position);
        expect(row['assignment_basis'], 'GUEST',
            reason: 'a position for this match implies no profile');
        expect(row['user_id'], isNull);
        expect(row['professional_guest_id'], guestId);
      }

      // And back to none, which is what `0051` calls the normal guest row.
      await saveGuestPosition(matchId, squad, guestId, null);
      expect((await guestRow(matchId, guestId))!['assigned_position'], isNull);
    });

    test('a community player still may not be left without one', () async {
      // The other half of `0051`'s pair of checks, unchanged: `user_id is null
      // or assigned_position is not null`.
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);

      await expectLater(
        owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            {
              'user_id': owner.id,
              'team': 'A',
              'assigned_position': null,
              'assignment_basis': 'TRANSITION',
            },
          ],
        }),
        throwsA(anything),
      );
    });

    test('a chosen position survives an ordinary later save', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      await saveGuestPosition(matchId, squad, guestId, 'GK');

      // A save that says nothing about the guest.
      await saveCommunityLineup(matchId, squad);

      expect((await guestRow(matchId, guestId))!['assigned_position'], 'GK');
    });

    test('and is given up by a generation', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      await saveGuestPosition(matchId, squad, guestId, 'GK');

      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          for (final (index, user) in squad.indexed)
            {
              'user_id': user.id,
              'team': index.isEven ? 'A' : 'B',
              'assigned_position': const ['DEF', 'MID', 'FWD'][index % 3],
              'assignment_basis': 'TRANSITION',
            },
        ],
        'p_from_generation': true,
      });

      expect((await guestRow(matchId, guestId))!['assigned_position'], isNull,
          reason: 'a fresh search discards the adjustments around the old one');
    });

    test('a guest who did not play is taken out of the record', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');
      expect(await guestRow(matchId, guestId), isNotNull);

      await owner.client.rpc('remove_played_professional_guest', params: {
        'p_match_id': matchId,
        'p_guest_id': guestId,
      });

      // Neither on the pitch nor on the roster: no dangling reference either
      // way, which is what `remove_professional_guest` deliberately does not do.
      expect(await guestRow(matchId, guestId), isNull);
      expect(
        (await roster(matchId))
            .where((r) => r['professional_guest_id'] == guestId),
        isEmpty,
      );
    });

    test('a guest who scored is refused, and nothing is edited', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await startedMatchWithSquad(squad);
      final guestId = await addGuest(owner, matchId, 'Guest 1');

      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 2,
        'p_team_b_score': 0,
        'p_mvp_user_id': null,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'professional_guest_id': guestId, 'goals': 1},
        ],
      });

      await expectLater(
        owner.client.rpc('remove_played_professional_guest', params: {
          'p_match_id': matchId,
          'p_guest_id': guestId,
        }),
        throwsA(predicate(
          (e) => e.toString().contains('RESULT_PARTICIPANT_REMOVED'),
          'RESULT_PARTICIPANT_REMOVED',
        )),
      );

      // The refusal changed nothing: the goal stands, the score stands, and the
      // guest is still on the pitch. The organizer corrects the result first.
      final goals = List<Map<String, dynamic>>.from(await owner.client
          .from('match_goals')
          .select('user_id, professional_guest_id, goals')
          .eq('match_id', matchId));
      expect(
        goals.where((g) => g['professional_guest_id'] == guestId),
        hasLength(1),
        reason: 'no goal is deleted to make a removal possible',
      );
      final result = await owner.client
          .from('match_results')
          .select('team_a_score, team_b_score')
          .eq('match_id', matchId)
          .single();
      expect(result['team_a_score'], 2);
      expect(result['team_b_score'], 0);
      expect(
        goals.fold<int>(0, (sum, g) => sum + (g['goals'] as int)),
        2,
        reason: 'the goals still equal the score',
      );
      expect(await guestRow(matchId, guestId), isNotNull);
    });

    test('a reserve guest is not on the pitch', () async {
      final matchId = await matchWithSlots(4);
      final squad = [owner, admin, player, player2];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveCommunityLineup(matchId, squad);
      final guestId = await addGuest(owner, matchId, 'Waiting');

      expect(statusOfGuest(await roster(matchId), guestId), 'reserve');
      final rows = await lineup(matchId);
      expect(teamOfGuest(rows, guestId), isNull);
      expect(rows, hasLength(4), reason: 'only the community players played');
    });

    test('5. the community half of the lineup is untouched', () async {
      final matchId = await matchWithSlots(8);
      final squad = [owner, admin, player, player2];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveCommunityLineup(matchId, squad);

      List<Map<String, dynamic>> communityRows(
        List<Map<String, dynamic>> rows,
      ) =>
          rows.where((r) => r['user_id'] != null).toList()
            ..sort((a, b) =>
                (a['user_id'] as String).compareTo(b['user_id'] as String));

      final before = communityRows(await lineup(matchId));
      for (var i = 1; i <= 3; i++) {
        await addGuest(owner, matchId, 'Guest $i');
      }

      expect(communityRows(await lineup(matchId)), before,
          reason: 'placing guests moves no community player and changes no '
              'side, position or basis');
    });

    test('6. a guest is not in the set the engine is given', () async {
      final matchId = await matchWithSlots(8);
      await owner.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
      final guestId = await addGuest(owner, matchId, 'Ringer');

      // The query the application builds the generation set from: confirmed
      // registrations that name a user. A guest names none, and there is no
      // profile row for one to join to.
      final inputs = await owner.client
          .from('match_registrations')
          .select('user_id, user:users(id)')
          .eq('match_id', matchId)
          .eq('status', 'confirmed')
          .not('user_id', 'is', null);
      expect(inputs, hasLength(1));
      expect(inputs.single['user_id'], owner.id);

      expect(statusOfGuest(await roster(matchId), guestId), 'confirmed',
          reason: 'excluded from the engine, present on the roster');
    });
  });

  // Regression for the production failure fixed by migration `0052`.
  //
  // `assign_professional_guest_teams` used `r` as a table alias in the DELETE
  // above its `for r in ...` loop. PL/pgSQL resolves `r.match_id` against the
  // declared record rather than the alias, so the statement raised
  // `55000 record "r" is not assigned yet` at runtime — a fault no `create
  // function` could catch, because the function parses fine and only fails when
  // that statement is reached.
  //
  // It was reachable only once a **community lineup existed**, which is why
  // adding a guest always worked and "Create Teams" always failed. These tests
  // walk that exact order.
  group('creating teams for a match that holds guests (0052 regression)', () {
    Future<List<Map<String, dynamic>>> lineup(String matchId) async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id, team, assigned_position')
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows);
    }

    /// The save at the end of "Create Teams": engine output for the confirmed
    /// community players, and nothing else in the payload.
    Future<String> createTeams(String matchId, List<TestUser> squad) =>
        outcomeOf(() async {
          await owner.client.rpc('replace_match_lineup', params: {
            'p_match_id': matchId,
            'p_assignments': [
              for (final (index, user) in squad.indexed)
                {
                  'user_id': user.id,
                  'team': index.isEven ? 'A' : 'B',
                  'assigned_position': 'MID',
                  'assignment_basis': 'TRANSITION',
                },
            ],
          });
        });

    Future<String> matchWith(List<TestUser> squad, int guests) async {
      // Slots for everybody, so the guests are starting rather than reserve —
      // the state the production match was in.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17),
          startingPlayers: squad.length + guests);
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      for (var i = 1; i <= guests; i++) {
        await addGuest(owner, matchId, 'Guest $i');
      }
      return matchId;
    }

    test('1. a match with no guests still generates', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await matchWith(squad, 0);

      expect(await createTeams(matchId, squad), 'ALLOW');
      expect(await lineup(matchId), hasLength(4));
    });

    test('2. a match with one Professional Guest generates', () async {
      final squad = [owner, admin, player, player2];
      final matchId = await matchWith(squad, 1);

      expect(await createTeams(matchId, squad), 'ALLOW',
          reason: 'this raised 55000 before migration 0052');

      final rows = await lineup(matchId);
      expect(rows.where((r) => r['user_id'] != null), hasLength(4));
      final guestRows =
          rows.where((r) => r['professional_guest_id'] != null).toList();
      expect(guestRows, hasLength(1));
      expect(guestRows.single['team'], 'A');
      expect(guestRows.single['assigned_position'], isNull);
    });

    test('3. a match with several Professional Guests generates', () async {
      final squad = [owner, admin, player];
      final matchId = await matchWith(squad, 3);

      expect(await createTeams(matchId, squad), 'ALLOW');

      final rows = await lineup(matchId);
      expect(rows.where((r) => r['user_id'] != null), hasLength(3),
          reason: '5. the community half is exactly what was sent');
      expect(rows.where((r) => r['professional_guest_id'] != null),
          hasLength(3));
      for (final row in rows.where((r) => r['professional_guest_id'] != null)) {
        expect(row['assigned_position'], isNull,
            reason: '7. a guest carries no position');
      }
    });

    test('regenerating over an existing guest lineup also works', () async {
      // The second pass is the one that reaches the DELETE with guest rows
      // already present, which is the statement that used to fail.
      final squad = [owner, admin, player, player2];
      final matchId = await matchWith(squad, 2);

      expect(await createTeams(matchId, squad), 'ALLOW');
      expect(await createTeams(matchId, squad.reversed.toList()), 'ALLOW');

      final rows = await lineup(matchId);
      expect(rows, hasLength(6));
      expect(rows.where((r) => r['professional_guest_id'] != null),
          hasLength(2), reason: '6. the guests are still placed, and only once');
    });

    test('a withdrawal from a match with a lineup and a guest works', () async {
      // Same function, reached through `recompute_match_status` instead of
      // through the lineup save — it failed here too before 0052.
      final squad = [owner, admin, player, player2];
      final matchId = await matchWith(squad, 1);
      expect(await createTeams(matchId, squad), 'ALLOW');

      expect(
        await outcomeOf(() async {
          await player2.client
              .rpc('withdraw_from_match', params: {'p_match_id': matchId});
        }),
        'ALLOW',
      );
    });
  });

  group('a lineup that no longer describes the roster is regenerated', () {
    Future<List<Map<String, dynamic>>> lineup(String matchId) async {
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id, professional_guest_id, team')
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows);
    }

    Future<void> saveLineupFor(String matchId, List<TestUser> squad) =>
        owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            for (final (index, user) in squad.indexed)
              {
                'user_id': user.id,
                'team': index.isEven ? 'A' : 'B',
                'assigned_position': 'MID',
                'assignment_basis': 'TRANSITION',
              },
          ],
        });

    Future<String> editStartingPlayers(TestUser actor, String matchId, int n) =>
        outcomeOf(() async {
          final start = DateTime.now().toUtc().add(const Duration(days: 17));
          await actor.client.rpc('update_match', params: {
            'p_match_id': matchId,
            'p_title': 'ITest regeneration',
            'p_location': 'ITest pitch',
            'p_start_at': start.toIso8601String(),
            'p_end_at': start.add(const Duration(hours: 2)).toIso8601String(),
            'p_starting_players': n,
            'p_description': null,
          });
        });

    test('7/12. promoting a reserve clears the whole stale lineup', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final starting = [owner, admin, player, player2];
      for (final user in [...starting, player3]) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      expect(statusOfUser(await roster(matchId), player3.id), 'reserve');
      await saveLineupFor(matchId, starting);
      expect(await lineup(matchId), hasLength(4));

      // Five starting slots promotes the reserve, so the stored lineup now
      // describes four of the five confirmed players.
      expect(await editStartingPlayers(owner, matchId, 5), 'ALLOW');
      expect(statusOfUser(await roster(matchId), player3.id), 'confirmed');

      expect(await lineup(matchId), isEmpty,
          reason: 'regenerated completely — no stale row survives');
    });

    test('a withdrawal clears the lineup too', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final starting = [owner, admin, player, player2];
      for (final user in starting) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveLineupFor(matchId, starting);

      await player2.client
          .rpc('withdraw_from_match', params: {'p_match_id': matchId});

      expect(await lineup(matchId), isEmpty);
    });

    test('9. a guest moving between starting and reserve does NOT regenerate',
        () async {
      // The approved exception: only a change to the confirmed *community*
      // players re-runs the engine.
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final squad = [owner, admin, player];
      for (final user in squad) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveLineupFor(matchId, squad);
      final guestId = await addGuest(owner, matchId, 'Ringer');

      expect((await lineup(matchId)).where((r) => r['user_id'] != null),
          hasLength(3));
      expect(
        (await lineup(matchId))
            .where((r) => r['professional_guest_id'] == guestId),
        hasLength(1),
      );

      // A larger starting count changes nothing about who is confirmed among
      // the community players, so the lineup stands.
      expect(await editStartingPlayers(owner, matchId, 6), 'ALLOW');

      final after = await lineup(matchId);
      expect(after.where((r) => r['user_id'] != null), hasLength(3),
          reason: 'the engine is not re-run for a guest-only change');
      expect(after.where((r) => r['professional_guest_id'] == guestId),
          hasLength(1));
    });

    test('10. an admin can make the change as well as the owner', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      final starting = [owner, admin, player, player2];
      for (final user in [...starting, player3]) {
        await user.client
            .rpc('register_for_match', params: {'p_match_id': matchId});
      }
      await saveLineupFor(matchId, starting);

      expect(await editStartingPlayers(admin, matchId, 5), 'ALLOW');
      expect(await lineup(matchId), isEmpty);
    });

    test('an ordinary player cannot', () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: 17), startingPlayers: 4);
      expect(await editStartingPlayers(player, matchId, 5), 'NOT_AUTHORIZED');
    });

    test('8/11. a played match keeps its lineup, its result and its status',
        () async {
      final matchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -19),
          duration: const Duration(hours: 2),
          startingPlayers: 4);
      for (final user in [owner, admin, player]) {
        await owner.client.rpc('admin_add_player_to_match', params: {
          'p_match_id': matchId,
          'p_user_id': user.id,
        });
      }
      final guestId = await addGuest(owner, matchId, 'Ringer');

      Future<void> assign(String? userId, String? gid, String team) =>
          owner.client.from('match_team_assignments').insert({
            'match_id': matchId,
            if (userId != null) 'user_id': userId,
            if (gid != null) 'professional_guest_id': gid,
            'team': team,
            'assigned_position': 'MID',
            'assignment_basis': gid == null ? 'TRANSITION' : 'GUEST',
          });
      await assign(owner.id, null, 'A');
      await assign(admin.id, null, 'A');
      await assign(player.id, null, 'B');
      await assign(null, guestId, 'B');

      await owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': 1,
        'p_team_b_score': 1,
        'p_mvp_user_id': null,
        'p_mvp_professional_guest_id': guestId,
        'p_goals': [
          {'user_id': owner.id, 'goals': 1},
          {'professional_guest_id': guestId, 'goals': 1},
        ],
      });

      // The administrative edit is allowed in every state, including this one.
      final start = DateTime.now().toUtc().subtract(const Duration(days: 19));
      expect(
        await outcomeOf(() async {
          await owner.client.rpc('update_match', params: {
            'p_match_id': matchId,
            'p_title': 'ITest played edit',
            'p_location': 'ITest pitch',
            'p_start_at': start.toIso8601String(),
            'p_end_at': start.add(const Duration(hours: 2)).toIso8601String(),
            'p_starting_players': 6,
            'p_description': null,
          });
        }),
        'ALLOW',
      );

      // Nothing historical moved.
      expect(await lineup(matchId), hasLength(4),
          reason: 'a played lineup is a record, not a plan');
      final result = await owner.client
          .from('match_results')
          .select('mvp_professional_guest_id')
          .eq('match_id', matchId)
          .single();
      expect(result['mvp_professional_guest_id'], guestId);
      final tally = await owner.client
          .from('match_goals')
          .select('goals')
          .eq('match_id', matchId)
          .eq('professional_guest_id', guestId)
          .single();
      expect(tally['goals'], 1);

      final status = await owner.client
          .from('matches')
          .select('status')
          .eq('id', matchId)
          .single();
      expect(status['status'], 'completed');
    });
  });
}
