@Timeout(Duration(minutes: 8))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0074_all_state_match_management.sql` against a real database.
///
/// Three rules, and each of them is about what the database does rather than
/// about which row moved:
///
///   A1. A batch correction of a completed match is ONE transaction. The whole
///       payload is validated first, the ratings and counters are recalculated
///       once from the lineup the batch adds up to, and a refusal leaves
///       nothing behind at all.
///   A2. A match's lifecycle moves forward only. Future may become anything,
///       active may end, completed stays completed.
///   A3. A final result belongs to a match that has been played, and a result
///       offered before that mutates nothing.
///
/// The rating assertions are written against *relationships* rather than against
/// literal values -- a corrected player is compared to a teammate whose match
/// was identical, and a removed player to their own baseline. That is
/// deliberate: it holds under the rating values in `0073` and under the ones
/// before it, so this suite tests the correction's behaviour rather than
/// restating the rating engine's constants, which `rating_engine_v2_test.dart`
/// already pins.
///
/// Day 74 is this file's match window. Ratings and counters belong to the
/// permanent accounts, and teardown deletes the community, whose cascade gives
/// every change back.
void main() {
  if (!integrationConfigured) {
    test('all-state match management', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser player2;
  late TestUser player3;
  late String communityId;
  late String matchId;

  late List<TestUser> squad;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    player2 = await signInTestUser('player2');
    player3 = await signInTestUser('player3');
    squad = [owner, admin, player, player2];
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest AllState');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    // In the past: a correction is to the record of a match that was played.
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: -74), startingPlayers: 4);
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  Map<String, dynamic> seat(TestUser user, String team, String position) => {
        'user_id': user.id,
        'team': team,
        'assigned_position': position,
        'assignment_basis': 'PRIMARY',
      };

  /// Two a side: owner and admin on A, player and player2 on B.
  Future<void> storeLineup() async {
    await owner.client.rpc('replace_match_lineup', params: {
      'p_match_id': matchId,
      'p_assignments': [
        seat(owner, 'A', 'GK'),
        seat(admin, 'A', 'MID'),
        seat(player, 'B', 'GK'),
        seat(player2, 'B', 'FWD'),
      ],
      'p_from_generation': false,
      'p_completed_correction': true,
    });
  }

  /// Team A wins 2-0, the owner scoring both and taking the MVP.
  Future<void> recordResult({
    int teamA = 2,
    int teamB = 0,
    TestUser? mvp,
    List<Map<String, dynamic>>? goals,
  }) async {
    await owner.client.rpc('record_match_result', params: {
      'p_match_id': matchId,
      'p_team_a_score': teamA,
      'p_team_b_score': teamB,
      'p_mvp_user_id': (mvp ?? owner).id,
      'p_goals': goals ??
          [
            if (teamA > 0) {'user_id': owner.id, 'goals': teamA},
            if (teamB > 0) {'user_id': player.id, 'goals': teamB},
          ],
    });
  }

  Future<String> correct(
    TestUser actor,
    Object changes, {
    String? onMatch,
  }) =>
      outcomeOf(() async {
        await actor.client.rpc('correct_completed_match_players', params: {
          'p_match_id': onMatch ?? matchId,
          'p_changes': changes,
        });
      });

  Map<String, dynamic> upsert(TestUser user, String team, String position) => {
        'user_id': user.id,
        'action': 'UPSERT',
        'team': team,
        'assigned_position': position,
      };

  Map<String, dynamic> remove(TestUser user) =>
      {'user_id': user.id, 'action': 'REMOVE'};

  Future<double> ratingOf(TestUser user) async {
    final row = await owner.client
        .from('users')
        .select('overall_rating')
        .eq('id', user.id)
        .single();
    return (row['overall_rating'] as num).toDouble();
  }

  Future<Map<String, int>> countersOf(TestUser user) async {
    final row = await owner.client
        .from('player_statistics')
        .select('matches_played, wins, losses, draws, goals, mvp_count')
        .eq('user_id', user.id)
        .maybeSingle();
    return {
      for (final key in const [
        'matches_played',
        'wins',
        'losses',
        'draws',
        'goals',
        'mvp_count',
      ])
        key: (row?[key] as int?) ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> assignments() async {
    final rows = await owner.client
        .from('match_team_assignments')
        .select('user_id, professional_guest_id, team, assigned_position, '
            'assignment_basis')
        .eq('match_id', matchId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<Map<String, dynamic>?> assignmentOf(TestUser user) async {
    final all = await assignments();
    for (final row in all) {
      if (row['user_id'] == user.id) return row;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> registrations() async {
    final rows = await owner.client
        .from('match_registrations')
        .select('user_id, status, registration_order')
        .eq('match_id', matchId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<Map<String, dynamic>?> registrationOf(TestUser user) async {
    final all = await registrations();
    for (final row in all) {
      if (row['user_id'] == user.id) return row;
    }
    return null;
  }

  Future<Map<String, dynamic>> snapshot() async => {
        'assignments': await assignments(),
        'registrations': await registrations(),
        for (final user in [...squad, player3]) ...{
          '${user.label}.rating': await ratingOf(user),
          '${user.label}.counters': await countersOf(user),
        },
      };

  // ---------------------------------------------------------------------------
  group('A1: a batch is validated whole, or refused whole', () {
    setUp(storeLineup);

    test('three players are corrected in one call', () async {
      final outcome = await correct(owner, [
        upsert(player3, 'A', 'FWD'),
        upsert(player2, 'A', 'DEF'),
        upsert(player, 'B', 'MID'),
      ]);

      expect(outcome, 'ALLOW');
      expect((await assignmentOf(player3))?['team'], 'A');
      expect((await assignmentOf(player2))?['team'], 'A',
          reason: 'moved across in the same batch');
      expect((await assignmentOf(player))?['assigned_position'], 'MID');
    });

    test('the same player twice is refused as a malformed batch', () async {
      final before = await snapshot();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          upsert(player3, 'B', 'GK'),
        ]),
        'INVALID_CHANGES',
      );

      expect(await snapshot(), before,
          reason: 'two answers to one question change nothing');
    });

    test('an empty batch is refused, and recalculates nothing', () async {
      await recordResult();
      final before = await snapshot();
      final audit = await owner.client
          .from('rating_history')
          .select('id')
          .eq('match_id', matchId)
          .count();

      expect(await correct(owner, const []), 'INVALID_CHANGES');

      expect(await snapshot(), before);
      final after = await owner.client
          .from('rating_history')
          .select('id')
          .eq('match_id', matchId)
          .count();
      expect(after.count, audit.count,
          reason: 'nothing was detached and reattached for an empty batch');
    });

    test('the same uuid in two cases is one player, and refuses the batch',
        () async {
      // PostgreSQL reads both spellings as the same uuid, so this is a doubled
      // entry however it is written.
      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          {
            'user_id': player3.id.toUpperCase(),
            'action': 'UPSERT',
            'team': 'B',
            'assigned_position': 'GK',
          },
        ]),
        'INVALID_CHANGES',
      );
      expect(await assignmentOf(player3), isNull,
          reason: 'neither entry was applied');
    });

    test('a payload that is not an array is refused the same way', () async {
      expect(await correct(owner, {'user_id': player3.id, 'action': 'REMOVE'}),
          'INVALID_CHANGES');
      expect(await correct(owner, 'REMOVE'), 'INVALID_CHANGES');
    });

    test('one non-member refuses the whole batch', () async {
      // The third entry is the bad one, so this also proves the first two were
      // not applied on the way past.
      final outsider = await signInTestUser('outsider');
      final before = await snapshot();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          upsert(player2, 'A', 'DEF'),
          upsert(outsider, 'B', 'MID'),
        ]),
        'NOT_COMMUNITY_MEMBER',
      );

      expect(await snapshot(), before);
      expect(await assignmentOf(player3), isNull,
          reason: 'no partial assignment survived the refusal');
      expect(await registrationOf(player3), isNull,
          reason: 'and no partial registration either');
    });

    test('an invalid team refuses the whole batch', () async {
      final before = await snapshot();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          {
            'user_id': player2.id,
            'action': 'UPSERT',
            'team': 'C',
            'assigned_position': 'MID',
          },
        ]),
        'INVALID_TEAM',
      );

      expect(await snapshot(), before);
    });

    test('an invalid position refuses the whole batch', () async {
      final before = await snapshot();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          {
            'user_id': player2.id,
            'action': 'UPSERT',
            'team': 'A',
            'assigned_position': 'SWEEPER',
          },
        ]),
        'INVALID_POSITION',
      );

      expect(await snapshot(), before);
    });

    test('only an owner or admin may correct, and only a played match',
        () async {
      expect(await correct(player, [upsert(player3, 'A', 'FWD')]),
          'NOT_AUTHORIZED');
      expect(await correct(admin, [upsert(player3, 'A', 'FWD')]), 'ALLOW',
          reason: 'an admin may');

      final future = await createMatch(owner, communityId,
          startsIn: const Duration(days: 7), startingPlayers: 4);
      expect(
        await correct(owner, [upsert(player3, 'A', 'FWD')], onMatch: future),
        'MATCH_NOT_COMPLETED',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('A1: the roster follows the lineup', () {
    setUp(storeLineup);

    test('a player who never registered is confirmed and placed', () async {
      expect(await registrationOf(player3), isNull);

      expect(await correct(owner, [upsert(player3, 'A', 'FWD')]), 'ALLOW');

      final registration = await registrationOf(player3);
      expect(registration?['status'], 'confirmed');
      expect(registration?['registration_order'], isNotNull);
      final assignment = await assignmentOf(player3);
      expect(assignment?['team'], 'A');
      expect(assignment?['assigned_position'], 'FWD');
    });

    test('a reserve is confirmed rather than left waiting', () async {
      // A completed match has no queue to wait in: somebody who played is
      // confirmed, whatever their seat said before.
      await owner.client.rpc('register_player_in_match', params: {
        'p_match_id': matchId,
        'p_user_id': player3.id,
      });
      await owner.client
          .from('match_registrations')
          .update({'status': 'reserve'})
          .eq('match_id', matchId)
          .eq('user_id', player3.id);

      expect(await correct(owner, [upsert(player3, 'B', 'DEF')]), 'ALLOW');

      expect((await registrationOf(player3))?['status'], 'confirmed');
      expect((await assignmentOf(player3))?['team'], 'B');
    });

    test('correcting somebody already registered does not duplicate the seat',
        () async {
      final before = await registrations();

      expect(await correct(owner, [upsert(admin, 'B', 'MID')]), 'ALLOW');

      final after = await registrations();
      expect(after.length, before.length);
      expect(after.where((row) => row['user_id'] == admin.id), hasLength(1));
      expect((await assignmentOf(admin))?['team'], 'B');
      expect((await assignmentOf(admin))?['assigned_position'], 'MID');
    });

    test('the basis is derived from the profile, not from the payload',
        () async {
      // The payload cannot claim a basis, and what is stored follows the
      // player's own primary and secondary positions.
      expect(await correct(owner, [upsert(player3, 'A', 'GK')]), 'ALLOW');

      final stored = (await assignmentOf(player3))?['assignment_basis'];
      expect(stored, isIn(const ['PRIMARY', 'SECONDARY', 'TRANSITION']));
    });

    test('a removal takes the lineup row and the seat together', () async {
      expect(await correct(owner, [remove(player2)]), 'ALLOW');

      expect(await assignmentOf(player2), isNull);
      expect(await registrationOf(player2), isNull);
    });

    test('adding and removing in one batch is one edit', () async {
      expect(
        await correct(owner, [upsert(player3, 'B', 'FWD'), remove(player2)]),
        'ALLOW',
      );

      expect((await assignmentOf(player3))?['team'], 'B');
      expect(await assignmentOf(player2), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('A1: Professional Guests are left alone', () {
    late String guestId;

    setUp(() async {
      await storeLineup();
      guestId = await owner.client.rpc('add_professional_guest', params: {
        'p_match_id': matchId,
        'p_full_name': 'ITest Guest',
      }) as String;
      await owner.client.rpc('set_professional_guest_team', params: {
        'p_match_id': matchId,
        'p_professional_guest_id': guestId,
        'p_team': 'A',
        'p_assigned_position': 'DEF',
      });
    });

    test('a batch correction does not disturb a guest lineup row', () async {
      final before = (await assignments())
          .where((row) => row['professional_guest_id'] == guestId)
          .toList();
      expect(before, hasLength(1));

      expect(
        await correct(owner, [upsert(player3, 'B', 'MID'), remove(player2)]),
        'ALLOW',
      );

      final after = (await assignments())
          .where((row) => row['professional_guest_id'] == guestId)
          .toList();
      expect(after, before, reason: 'side, position and basis all unchanged');
    });
  });

  // ---------------------------------------------------------------------------
  group('A1: the recorded result survives, or the batch does not', () {
    setUp(() async {
      await storeLineup();
      // Owner scores both goals and takes the MVP; player scores nothing.
      await recordResult();
    });

    test('a batch that would remove the scorer is refused atomically',
        () async {
      final before = await snapshot();

      expect(
        await correct(owner, [upsert(player3, 'A', 'FWD'), remove(owner)]),
        'RESULT_PARTICIPANT_REMOVED',
      );

      expect(await snapshot(), before,
          reason: 'the other entry in the batch did not apply either');
    });

    test('a batch that would remove the MVP is refused atomically', () async {
      await recordResult(teamA: 2, teamB: 0, mvp: admin);
      final before = await snapshot();

      expect(
        await correct(owner, [remove(admin), upsert(player3, 'B', 'MID')]),
        'RESULT_PARTICIPANT_REMOVED',
      );

      expect(await snapshot(), before);
    });

    test('adding players leaves the score, the goals and the MVP alone',
        () async {
      final result = await owner.client
          .from('match_results')
          .select('team_a_score, team_b_score, mvp_user_id')
          .eq('match_id', matchId)
          .single();
      final goals = await owner.client
          .from('match_goals')
          .select('user_id, goals')
          .eq('match_id', matchId);

      expect(await correct(owner, [upsert(player3, 'B', 'MID')]), 'ALLOW');

      expect(
        await owner.client
            .from('match_results')
            .select('team_a_score, team_b_score, mvp_user_id')
            .eq('match_id', matchId)
            .single(),
        result,
      );
      expect(
        await owner.client
            .from('match_goals')
            .select('user_id, goals')
            .eq('match_id', matchId),
        goals,
      );
    });

    test('a scorer may be moved between sides, just not out of the lineup',
        () async {
      // The guard is about disappearing from the lineup, not about staying put.
      expect(await correct(owner, [upsert(owner, 'B', 'FWD')]), 'ALLOW');
      expect((await assignmentOf(owner))?['team'], 'B');
    });
  });

  // ---------------------------------------------------------------------------
  group('A1: ratings and counters are recalculated once, from the final lineup',
      () {
    setUp(() async {
      await storeLineup();
      await recordResult();
    });

    test('a player added to the winning side gains what their side gained',
        () async {
      // admin is already on A with no goal and no MVP. player3 is corrected onto
      // A with no goal and no MVP, so whatever one match on the winning side is
      // worth under the current rules, both must have it -- which is what
      // catches a correction that forgets participation or the win.
      final adminGain = await ratingOf(admin);
      final adminCounters = await countersOf(admin);
      final baseline = await ratingOf(player3);

      expect(await correct(owner, [upsert(player3, 'A', 'FWD')]), 'ALLOW');

      final after = await countersOf(player3);
      expect(after['matches_played'], 1);
      expect(after['wins'], 1);
      expect(after['losses'], 0);
      expect(adminCounters['wins'], 1,
          reason: 'the comparison is like for like');
      // Both accounts start from the same configured default, so the gain is the
      // difference from each one's own baseline.
      expect(await ratingOf(player3) - baseline,
          closeTo(adminGain - baseline, 0.0005),
          reason: 'one match on the winning side is worth one thing');
    });

    test('a removed player gives back everything the match gave them',
        () async {
      final baseline = await ratingOf(player2);
      final counters = await countersOf(player2);
      expect(counters['matches_played'], 1);

      expect(await correct(owner, [remove(player2)]), 'ALLOW');

      final after = await countersOf(player2);
      expect(after['matches_played'], 0);
      expect(after['losses'], 0);
      expect(await ratingOf(player2), lessThan(baseline + 0.0005),
          reason: 'the loss came back off');
      expect(await ratingOf(player2), greaterThan(baseline - 0.0005),
          reason: 'and nothing else was taken');
    });

    test('a side change moves the effects from one side to the other',
        () async {
      final before = await countersOf(player2);
      expect(before['losses'], 1);

      expect(await correct(owner, [upsert(player2, 'A', 'DEF')]), 'ALLOW');

      final after = await countersOf(player2);
      expect(after['wins'], before['wins']! + 1);
      expect(after['losses'], before['losses']! - 1);
      expect(after['matches_played'], before['matches_played'],
          reason: 'they played the same one match either way');
    });

    test('correcting twice does not accumulate twice', () async {
      expect(await correct(owner, [upsert(player3, 'A', 'FWD')]), 'ALLOW');
      final once = await snapshot();

      // The same statement made again says nothing new.
      expect(await correct(owner, [upsert(player3, 'A', 'FWD')]), 'ALLOW');

      expect(await snapshot(), once);
      expect((await countersOf(player3))['matches_played'], 1,
          reason: 'one match, however many times it is corrected');
    });

    test('a refused batch moves no rating and no counter', () async {
      final before = await snapshot();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          upsert(player3, 'B', 'GK'),
        ]),
        'INVALID_CHANGES',
      );

      expect(await snapshot(), before);
    });

    test('a batch of three is one recalculation, not three', () async {
      // Observable in the audit: a correction detaches and reattaches the
      // match's effects once, so one batch writes one reversal per existing
      // entry and one fresh set -- not one cycle per player in the batch.
      final before = await owner.client
          .from('rating_history')
          .select('id')
          .eq('match_id', matchId)
          .count();

      expect(
        await correct(owner, [
          upsert(player3, 'A', 'FWD'),
          upsert(player2, 'A', 'DEF'),
          upsert(player, 'B', 'MID'),
        ]),
        'ALLOW',
      );

      final after = await owner.client
          .from('rating_history')
          .select('id')
          .eq('match_id', matchId)
          .count();
      // One detach writes one reversal for each entry that stood, and one attach
      // writes the new set. Three separate corrections would have written three
      // such cycles.
      expect(after.count, lessThan(before.count * 3),
          reason: 'not one detach/attach cycle per player');
    });
  });

  // ---------------------------------------------------------------------------
  group('A2: the lifecycle moves forward only', () {
    Future<String> edit(
      String id, {
      required Duration startsIn,
      Duration duration = const Duration(hours: 2),
      int startingPlayers = 4,
      String title = 'ITest edited',
    }) {
      final start = DateTime.now().toUtc().add(startsIn);
      return outcomeOf(() async {
        await owner.client.rpc('update_match', params: {
          'p_match_id': id,
          'p_title': title,
          'p_location': 'ITest pitch',
          'p_start_at': start.toIso8601String(),
          'p_end_at': start.add(duration).toIso8601String(),
          'p_starting_players': startingPlayers,
          'p_description': null,
        });
      });
    }

    Future<String> futureMatch() => createMatch(owner, communityId,
        startsIn: const Duration(days: 7), startingPlayers: 4);

    /// Started an hour ago and still running.
    Future<String> activeMatch() => createMatch(owner, communityId,
        startsIn: const Duration(hours: -1),
        duration: const Duration(hours: 3),
        startingPlayers: 4);

    Future<String> completedMatch() => createMatch(owner, communityId,
        startsIn: const Duration(days: -74), startingPlayers: 4);

    test('future may stay future', () async {
      expect(
          await edit(await futureMatch(), startsIn: const Duration(days: 14)),
          'ALLOW');
    });

    test('future may be corrected into active', () async {
      expect(
        await edit(await futureMatch(),
            startsIn: const Duration(minutes: -30),
            duration: const Duration(hours: 2)),
        'ALLOW',
      );
    });

    test('future may be corrected into completed', () async {
      // Recording a fixture that has already happened.
      expect(
        await edit(await futureMatch(),
            startsIn: const Duration(days: -3),
            duration: const Duration(hours: 2)),
        'ALLOW',
      );
    });

    test('active may stay active', () async {
      expect(
        await edit(await activeMatch(),
            startsIn: const Duration(hours: -1),
            duration: const Duration(hours: 4)),
        'ALLOW',
      );
    });

    test('active may be ended', () async {
      expect(
        await edit(await activeMatch(),
            startsIn: const Duration(hours: -3),
            duration: const Duration(hours: 1)),
        'ALLOW',
      );
    });

    test('active may not be returned to the schedule', () async {
      final id = await activeMatch();

      expect(await edit(id, startsIn: const Duration(days: 2)), 'MATCH_LOCKED');

      final row = await owner.client
          .from('matches')
          .select('start_at')
          .eq('id', id)
          .single();
      expect(DateTime.parse(row['start_at'] as String).isBefore(DateTime.now()),
          isTrue,
          reason: 'the refused edit changed nothing');
    });

    test('completed may stay completed, any number of times', () async {
      final id = await completedMatch();

      for (final days in const [70, 60, 50]) {
        expect(await edit(id, startsIn: Duration(days: -days)), 'ALLOW',
            reason: 'edit $days');
      }
    });

    test('completed may not be reopened as active', () async {
      expect(
        await edit(await completedMatch(),
            startsIn: const Duration(hours: -1),
            duration: const Duration(hours: 3)),
        'MATCH_COMPLETED',
      );
    });

    test('completed may not be pushed into the future', () async {
      expect(
        await edit(await completedMatch(), startsIn: const Duration(days: 7)),
        'MATCH_COMPLETED',
      );
    });

    /// Five registrations on a four-a-side match, so the fifth holds a reserve
    /// seat. Promoting that seat is what `rebalance_roster` does, which makes it
    /// the observable difference between the branches below.
    Future<String> crowdedFutureMatch() async {
      final id = await createMatch(owner, communityId,
          startsIn: const Duration(days: 7), startingPlayers: 4);
      for (final user in [owner, admin, player, player2, player3]) {
        await owner.client.rpc('register_player_in_match', params: {
          'p_match_id': id,
          'p_user_id': user.id,
        });
      }
      return id;
    }

    Future<Map<String, String>> statuses(String id) async {
      final rows = await owner.client
          .from('match_registrations')
          .select('user_id, status')
          .eq('match_id', id);
      return {
        for (final row in rows) row['user_id'] as String: row['status'] as String,
      };
    }

    Future<String> reserveOf(String id) async {
      final all = await statuses(id);
      return all.entries
          .firstWhere((entry) => entry.value == 'reserve',
              orElse: () => throw StateError('the fixture holds no reserve'))
          .key;
    }

    test('future to future re-cuts the roster, as it always did', () async {
      final id = await crowdedFutureMatch();
      final reserve = await reserveOf(id);

      // Room for five now, and the match is still a plan: the reserve is
      // promoted, which is the ordinary behaviour this cycle preserves.
      expect(
        await edit(id, startsIn: const Duration(days: 14), startingPlayers: 5),
        'ALLOW',
      );

      expect((await statuses(id))[reserve], 'confirmed');
    });

    test('future to active does not promote anybody', () async {
      final id = await crowdedFutureMatch();
      final reserve = await reserveOf(id);

      expect(
        await edit(id,
            startsIn: const Duration(minutes: -30),
            duration: const Duration(hours: 2),
            startingPlayers: 5),
        'ALLOW',
      );

      expect((await statuses(id))[reserve], 'reserve',
          reason: 'the match is being played; its roster is participation');
    });

    test('future to completed does not promote anybody', () async {
      final id = await crowdedFutureMatch();
      final reserve = await reserveOf(id);

      expect(
        await edit(id,
            startsIn: const Duration(days: -3),
            duration: const Duration(hours: 2),
            startingPlayers: 5),
        'ALLOW',
      );

      expect((await statuses(id))[reserve], 'reserve',
          reason: 'a match entered as a record of itself rebalances nothing');
      final row = await owner.client
          .from('matches')
          .select('status')
          .eq('id', id)
          .single();
      expect(row['status'], 'completed');
    });

    test('active to active does not promote anybody', () async {
      final id = await crowdedFutureMatch();
      final reserve = await reserveOf(id);
      // Into progress first, which is itself a future -> active edit.
      await edit(id,
          startsIn: const Duration(minutes: -30),
          duration: const Duration(hours: 3),
          startingPlayers: 4);

      expect(
        await edit(id,
            startsIn: const Duration(minutes: -30),
            duration: const Duration(hours: 4),
            startingPlayers: 5),
        'ALLOW',
      );

      expect((await statuses(id))[reserve], 'reserve');
    });

    test('active to completed does not promote anybody', () async {
      final id = await crowdedFutureMatch();
      final reserve = await reserveOf(id);
      await edit(id,
          startsIn: const Duration(hours: -1),
          duration: const Duration(hours: 3),
          startingPlayers: 4);

      // Ended early, with room for five.
      expect(
        await edit(id,
            startsIn: const Duration(hours: -3),
            duration: const Duration(hours: 1),
            startingPlayers: 5),
        'ALLOW',
      );

      expect((await statuses(id))[reserve], 'reserve');
      final row = await owner.client
          .from('matches')
          .select('status')
          .eq('id', id)
          .single();
      expect(row['status'], 'completed');
    });

    test('an active match keeps a non-completed status through an edit',
        () async {
      final id = await crowdedFutureMatch();
      await edit(id,
          startsIn: const Duration(minutes: -30),
          duration: const Duration(hours: 3),
          startingPlayers: 5);

      final row = await owner.client
          .from('matches')
          .select('status')
          .eq('id', id)
          .single();
      expect(row['status'], isNot('completed'),
          reason: 'it is being played, not over');
    });

    test('starting_players is editable in every state', () async {
      expect(
          await edit(await futureMatch(),
              startsIn: const Duration(days: 7), startingPlayers: 8),
          'ALLOW');
      expect(
          await edit(await activeMatch(),
              startsIn: const Duration(hours: -1),
              duration: const Duration(hours: 3),
              startingPlayers: 9),
          'ALLOW');
      expect(
          await edit(await completedMatch(),
              startsIn: const Duration(days: -74), startingPlayers: 10),
          'ALLOW');
    });

    test('changing it on a played match rewrites no lineup and no roster',
        () async {
      await storeLineup();
      await recordResult();
      final before = await snapshot();

      expect(
        await edit(matchId,
            startsIn: const Duration(days: -74), startingPlayers: 30),
        'ALLOW',
      );

      final after = await snapshot();
      expect(after['assignments'], before['assignments'],
          reason: 'the played lineup is history, not a plan');
      expect(after['registrations'], before['registrations'],
          reason: 'nobody was promoted or demoted');
      for (final user in squad) {
        expect(after['${user.label}.rating'], before['${user.label}.rating'],
            reason: user.label);
        expect(
            after['${user.label}.counters'], before['${user.label}.counters'],
            reason: user.label);
      }
    });

    test('a completed match keeps its stored status through an edit', () async {
      final id = await completedMatch();
      await owner.client.rpc('update_match', params: {
        'p_match_id': id,
        'p_title': 'ITest settled',
        'p_location': 'ITest pitch',
        'p_start_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 70))
            .toIso8601String(),
        'p_end_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 70))
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'p_starting_players': 4,
        'p_description': null,
      });

      final row = await owner.client
          .from('matches')
          .select('status, end_at')
          .eq('id', id)
          .single();
      expect(row['status'], 'completed');
      expect(DateTime.parse(row['end_at'] as String).isBefore(DateTime.now()),
          isTrue,
          reason: 'a completed match never claims an end it has not reached');
    });
  });

  // ---------------------------------------------------------------------------
  group('A3: a result belongs to a played match', () {
    Future<String> resultOn(String id, {int teamA = 1, int teamB = 0}) =>
        outcomeOf(() async {
          await owner.client.rpc('record_match_result', params: {
            'p_match_id': id,
            'p_team_a_score': teamA,
            'p_team_b_score': teamB,
            'p_mvp_user_id': owner.id,
            'p_goals': [
              if (teamA > 0) {'user_id': owner.id, 'goals': teamA},
            ],
          });
        });

    /// A lineup on a match of any age, written as a correction so that the
    /// completed-match guard of 0071 is satisfied where it applies.
    Future<void> lineupOn(String id) async {
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': id,
        'p_assignments': [
          seat(owner, 'A', 'GK'),
          seat(admin, 'A', 'MID'),
          seat(player, 'B', 'GK'),
          seat(player2, 'B', 'FWD'),
        ],
        'p_from_generation': false,
        'p_completed_correction': false,
      });
    }

    test('a future match refuses a result, and nothing moves', () async {
      final id = await createMatch(owner, communityId,
          startsIn: const Duration(days: 7), startingPlayers: 4);
      await lineupOn(id);
      final ratings = {
        for (final user in squad) user.label: await ratingOf(user),
      };

      expect(await resultOn(id), 'MATCH_NOT_COMPLETED');

      expect(
        await owner.client
            .from('match_results')
            .select('match_id')
            .eq('match_id', id)
            .maybeSingle(),
        isNull,
      );
      for (final user in squad) {
        expect(await ratingOf(user), ratings[user.label], reason: user.label);
        expect((await countersOf(user))['matches_played'], 0,
            reason: user.label);
      }
    });

    test('a match in progress refuses one too', () async {
      final id = await createMatch(owner, communityId,
          startsIn: const Duration(hours: -1),
          duration: const Duration(hours: 3),
          startingPlayers: 4);
      await lineupOn(id);

      expect(await resultOn(id), 'MATCH_NOT_COMPLETED');
      expect(
        await owner.client
            .from('match_goals')
            .select('match_id')
            .eq('match_id', id),
        isEmpty,
        reason: 'no goal was written by the attempt',
      );
    });

    test('a completed match takes one, and takes corrections after it',
        () async {
      await storeLineup();

      expect(await resultOn(matchId, teamA: 1), 'ALLOW');
      expect(await resultOn(matchId, teamA: 3), 'ALLOW');
      expect(await resultOn(matchId, teamA: 2), 'ALLOW');

      final row = await owner.client
          .from('match_results')
          .select('team_a_score')
          .eq('match_id', matchId)
          .single();
      expect(row['team_a_score'], 2, reason: 'the last correction stands');
      expect((await countersOf(owner))['matches_played'], 1,
          reason: 'three saves, one match');
    });

    test('a match whose end has passed counts as played, stored status or not',
        () async {
      // The authoritative rule is the stored status OR the passed end, so a
      // match nothing has settled yet still takes its result.
      final id = await createMatch(owner, communityId,
          startsIn: const Duration(days: -2), startingPlayers: 4);
      await lineupOn(id);

      expect(await resultOn(id), 'ALLOW');
    });
  });
}
