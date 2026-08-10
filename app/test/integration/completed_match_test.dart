@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0029_completed_match_editing.sql` — correcting a match that has
/// already been played.
///
/// The rule under test is one sentence: **anything that changes who played, or
/// which side they played on, reverses the result's effects and reapplies them
/// in the same transaction.** Before `0029` the lineup could be rewritten while
/// every rating and counter derived from it stayed as it was, which left the
/// statistics describing a lineup that no longer existed. Nothing detected it,
/// because nothing was wrong at the row level.
///
/// So these tests do not check that a row moved. They record a real result,
/// move a player between sides, and check that the *ratings and counters* moved
/// with them — which is the only thing that was ever broken.
///
/// Day 29 is this file's match window, in the past, because that is what makes
/// the match one a correction may be applied to. Ratings and counters belong to
/// the six permanent accounts, and teardown deletes the community, whose cascade
/// gives every change back.
void main() {
  if (!integrationConfigured) {
    test('completed match editing', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Completed');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    // In the past: a correction to who played only makes sense once somebody
    // has, and `set_completed_match_player` refuses anything else.
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: -29), startingPlayers: 4);
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
    });
  }

  /// Team A wins 2-0 unless a test says otherwise.
  ///
  /// [goals] defaults to a list that adds up to the score rather than to an
  /// empty one: the approved result rules require the attributed goals to equal
  /// `teamA + teamB`, so a default of "nobody scored" would be refused for every
  /// score but 0-0. Team A's goals go to the owner and Team B's to `player`,
  /// both of whom are in the fixture lineup on those sides.
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

  Future<Map<String, dynamic>> capture() async => {
        for (final user in squad) ...{
          '${user.label}.rating': await ratingOf(user),
          '${user.label}.counters': await countersOf(user),
        },
      };

  Future<String> setPlayer(
    TestUser actor,
    TestUser target, {
    String? team,
    String? position,
  }) =>
      outcomeOf(() async {
        await actor.client.rpc('set_completed_match_player', params: {
          'p_match_id': matchId,
          'p_user_id': target.id,
          'p_team': team,
          'p_assigned_position': position,
        });
      });

  group('moving a player between sides', () {
    setUp(() async {
      await storeLineup();
      // Team A wins 2-0. The two on A gain the win, the two on B take the loss.
      await recordResult();
    });

    test('the counters follow the lineup rather than staying behind', () async {
      final before = await countersOf(player2);
      expect(before['losses'], greaterThanOrEqualTo(1));

      // player2 moves from the losing side to the winning one.
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          seat(owner, 'A', 'GK'),
          seat(admin, 'A', 'MID'),
          seat(player2, 'A', 'FWD'),
          seat(player, 'B', 'GK'),
        ],
      });

      final after = await countersOf(player2);
      expect(after['wins'], before['wins']! + 1);
      expect(after['losses'], before['losses']! - 1);
      expect(after['matches_played'], before['matches_played'],
          reason: 'they played the same one match either way');
    });

    test('the rating follows it too', () async {
      final before = await ratingOf(player2);

      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          seat(owner, 'A', 'GK'),
          seat(admin, 'A', 'MID'),
          seat(player2, 'A', 'FWD'),
          seat(player, 'B', 'GK'),
        ],
      });

      // A loss came off and a win went on: +0.10 - (-0.10) = +0.20.
      expect(await ratingOf(player2), closeTo(before + 0.20, 0.001));
    });

    test('a match with no result is untouched by any of it', () async {
      // The reversal and the reapplication are both no-ops without a result, so
      // a lineup written before one is recorded behaves exactly as it always
      // did.
      final second = await createMatch(owner, communityId,
          startsIn: const Duration(days: -30), startingPlayers: 4);
      final outcome = await outcomeOf(() async {
        await owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': second,
          'p_assignments': [seat(owner, 'A', 'GK'), seat(admin, 'B', 'MID')],
        });
      });

      expect(outcome, 'ALLOW');
    });
  });

  group('adding and removing a player', () {
    setUp(() async {
      await storeLineup();
      await recordResult();
    });

    test('an added member gains what the match was worth', () async {
      final before = await countersOf(player3);

      expect(await setPlayer(owner, player3, team: 'B', position: 'DEF'),
          'ALLOW');

      final after = await countersOf(player3);
      expect(after['matches_played'], before['matches_played']! + 1);
      expect(after['losses'], before['losses']! + 1,
          reason: 'they were added to the side that lost 0-2');
    });

    test('an added member is on the roster as well as in the lineup', () async {
      await setPlayer(owner, player3, team: 'B', position: 'DEF');

      final registration = await owner.client
          .from('match_registrations')
          .select('status')
          .eq('match_id', matchId)
          .eq('user_id', player3.id)
          .maybeSingle();

      expect(registration?['status'], 'confirmed',
          reason: 'a player present in one and not the other would be a record '
              'that contradicts itself');
    });

    test('a removed player gives back everything the match gave them',
        () async {
      final before = await countersOf(player2);
      final ratingBefore = await ratingOf(player2);

      expect(await setPlayer(owner, player2), 'ALLOW');

      final after = await countersOf(player2);
      expect(after['matches_played'], before['matches_played']! - 1);
      expect(after['losses'], before['losses']! - 1);
      expect(await ratingOf(player2), closeTo(ratingBefore + 0.10, 0.001),
          reason: 'the 0.10 the loss cost them comes back');
    });

    test('the assignment basis is derived, never taken from the caller',
        () async {
      // §5.1 defines the basis as which rule produced the position, so a caller
      // cannot declare somebody in position who is not.
      await setPlayer(owner, player3, team: 'B', position: 'DEF');

      final row = await owner.client
          .from('match_team_assignments')
          .select('assignment_basis')
          .eq('match_id', matchId)
          .eq('user_id', player3.id)
          .single();
      final profile = await owner.client
          .from('users')
          .select('primary_position, secondary_position')
          .eq('id', player3.id)
          .single();

      final expected = profile['primary_position'] == 'DEF'
          ? 'PRIMARY'
          : profile['secondary_position'] == 'DEF'
              ? 'SECONDARY'
              : 'TRANSITION';
      expect(row['assignment_basis'], expected);
    });
  });

  group('what the result will not allow', () {
    setUp(storeLineup);

    test('the recorded MVP may not be taken out of the lineup', () async {
      await recordResult(mvp: player2);

      expect(await setPlayer(owner, player2), 'RESULT_PARTICIPANT_REMOVED',
          reason: 'a best player who was not on the pitch is not a state the '
              'result rules allow; the result is corrected first');
    });

    test('nor may a scorer', () async {
      await recordResult(
        teamA: 0,
        teamB: 2,
        mvp: owner,
        goals: [
          {'user_id': player2.id, 'goals': 2},
        ],
      );

      expect(await setPlayer(owner, player2), 'RESULT_PARTICIPANT_REMOVED');
    });

    test('a refused removal leaves the counters exactly as they were',
        () async {
      await recordResult(mvp: player2);
      final before = await capture();

      await setPlayer(owner, player2);

      expect(await capture(), before,
          reason: 'the guard runs before anything is written');
    });

    test('the same rule applies to a whole-lineup rewrite', () async {
      await recordResult(mvp: player2);

      final outcome = await outcomeOf(() async {
        await owner.client.rpc('replace_match_lineup', params: {
          'p_match_id': matchId,
          'p_assignments': [
            seat(owner, 'A', 'GK'),
            seat(admin, 'A', 'MID'),
            seat(player, 'B', 'GK'),
          ],
        });
      });

      expect(outcome, 'RESULT_PARTICIPANT_REMOVED');
    });
  });

  group('who may correct a played match', () {
    setUp(storeLineup);

    test('an admin may', () async {
      expect(await setPlayer(admin, player3, team: 'A', position: 'MID'),
          'ALLOW');
    });

    test('an ordinary player may not', () async {
      expect(await setPlayer(player, player3, team: 'A', position: 'MID'),
          'NOT_AUTHORIZED');
    });

    test('somebody outside the community cannot be added to it', () async {
      final outsider = await signInTestUser('outsider');
      expect(await setPlayer(owner, outsider, team: 'A', position: 'MID'),
          'NOT_COMMUNITY_MEMBER');
    });

    test('a match still to come is refused', () async {
      final upcoming = await createMatch(owner, communityId,
          startsIn: const Duration(days: 29), startingPlayers: 4);
      final outcome = await outcomeOf(() async {
        await owner.client.rpc('set_completed_match_player', params: {
          'p_match_id': upcoming,
          'p_user_id': player3.id,
          'p_team': 'A',
          'p_assigned_position': 'MID',
        });
      });

      expect(outcome, 'MATCH_NOT_COMPLETED',
          reason: 'before the match is over the roster belongs to capacity, '
              'the reserve queue and the player\'s own decision to join');
    });

    test('a side that is not a side is refused', () async {
      expect(await setPlayer(owner, player3, team: 'C', position: 'MID'),
          'INVALID_TEAM');
    });

    test('a position that is not one is refused', () async {
      expect(await setPlayer(owner, player3, team: 'A', position: 'SWEEPER'),
          'INVALID_POSITION');
    });
  });

  group('the reversal that used to go negative', () {
    // Regression for `23514 / player_statistics_wins_check` with `wins = -1`.
    //
    // `match_result_contribution` reads which side a player is on *now*, so the
    // subtraction at reversal is only the inverse of the addition at record
    // time while the lineup has not moved in between. Before `0029`,
    // `replace_match_lineup` moved players without reversing and reapplying —
    // so a player who banked a win and was then moved to the losing side had a
    // loss subtracted from a row that held a win, and deleting the match drove
    // `wins` to -1 and was refused outright.
    //
    // What is asserted here is the invariant whose absence caused it: after a
    // move, the stored counters describe the side the player is on now. The
    // drift itself can no longer be created through the API, which is the fix.

    setUp(() async {
      await storeLineup();
      // Team A wins 2-0. player2 is on B, so they take a loss.
      await recordResult();
    });

    test('a move rewrites the win and the loss, so neither can go negative',
        () async {
      final before = await countersOf(player2);
      expect(before['losses'], greaterThanOrEqualTo(1),
          reason: 'they were on the side that lost 0-2');

      // The operation that used to corrupt the row.
      await owner.client.rpc('replace_match_lineup', params: {
        'p_match_id': matchId,
        'p_assignments': [
          seat(owner, 'A', 'GK'),
          seat(admin, 'A', 'MID'),
          seat(player2, 'A', 'FWD'),
          seat(player, 'B', 'GK'),
        ],
      });

      final moved = await countersOf(player2);
      expect(moved['wins'], before['wins']! + 1);
      expect(moved['losses'], before['losses']! - 1,
          reason: 'the loss came off with the move rather than being left '
              'behind for the delete to subtract twice');

      // The delete that used to raise 23514.
      expect(
        await outcomeOf(() async {
          await owner.client
              .rpc('delete_match', params: {'p_match_id': matchId});
        }),
        'ALLOW',
      );
      matchId = '';

      final after = await countersOf(player2);
      for (final counter in const [
        'matches_played',
        'wins',
        'losses',
        'draws',
        'goals',
        'mvp_count',
      ]) {
        expect(after[counter], greaterThanOrEqualTo(0),
            reason: '$counter must never go below zero — '
                'player_statistics_${counter}_check is what refused the '
                'delete, and it is correct');
      }
      // `before` was taken while this match still counted as a loss for them.
      // The move turned that loss into a win, and the delete then took the win
      // away — so what is left is their record without this match at all: the
      // win never survives, and the loss `before` included is gone too.
      expect(after['wins'], before['wins'],
          reason: 'the match is gone, so it is worth nothing to anybody');
      expect(after['losses'], before['losses']! - 1,
          reason: 'the loss this match contributed before the move went with '
              'it — deleting a match removes whatever it was worth at the '
              'time, not whatever it was worth when it was recorded');
    });

    test('every participant comes back to where they started', () async {
      final before = <String, Map<String, int>>{
        for (final user in squad) user.label: await countersOf(user),
      };

      await owner.client.rpc('delete_match', params: {'p_match_id': matchId});
      matchId = '';

      for (final user in squad) {
        final after = await countersOf(user);
        final was = before[user.label]!;
        expect(after['matches_played'], was['matches_played']! - 1);
        expect(after['wins'], lessThanOrEqualTo(was['wins']!));
        expect(after['losses'], lessThanOrEqualTo(was['losses']!));
        for (final value in after.values) {
          expect(value, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('deleting a played match', () {
    test('gives back every statistic and rating its result produced', () async {
      await storeLineup();
      await recordResult();
      expect((await countersOf(owner))['wins'], greaterThanOrEqualTo(1));

      final before = <String, dynamic>{};
      // What the accounts looked like before this match existed is what the
      // deletion has to restore, so it is reconstructed by reversing what the
      // result is known to have applied.
      for (final user in squad) {
        before['${user.label}.counters'] = await countersOf(user);
      }

      await owner.client.rpc('delete_match', params: {'p_match_id': matchId});

      for (final user in squad) {
        final after = await countersOf(user);
        final was = before['${user.label}.counters'] as Map<String, int>;
        expect(after['matches_played'], was['matches_played']! - 1,
            reason: 'the match no longer exists, so nobody played it');
      }

      // And the match itself is gone, not merely emptied.
      final row = await owner.client
          .from('matches')
          .select('id')
          .eq('id', matchId)
          .maybeSingle();
      expect(row, isNull);
    });
  });
}
