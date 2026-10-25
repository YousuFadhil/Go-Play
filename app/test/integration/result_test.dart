@Timeout(Duration(minutes: 5))
library;

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/results/weighted_rating.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/infrastructure/supabase/supabase_result_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

/// Migration `0022_match_results.sql` — recording a result, and everything that
/// follows from it.
///
/// Migration 0108: SQL is checked against the weighted arithmetic mirror.
/// Run this file alone against an isolated project whose fixture accounts have
/// no recorded matches; it refuses a dirty baseline instead of assuming one.
/// Day 26 is this file's match window; nothing else uses it. Ratings and
/// counters belong to the six permanent accounts, so teardown puts both back.
void main() {
  if (!integrationConfigured) {
    test('match results', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser player2;
  late TestUser outsider;
  late String communityId;
  late String matchId;

  /// The four who played the fixture match, team A first.
  late List<TestUser> squad;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    player2 = await signInTestUser('player2');
    outsider = await signInTestUser('outsider');
    squad = [owner, admin, player, player2];
  });

  /// Where each squad member's rating stood before the test recorded anything.
  ///
  /// Captured rather than assumed: the rating is system-managed, so no test may
  /// set one, and asserting a change against what was there is the only honest
  /// way to check the arithmetic. Teardown deletes the match, which gives every
  /// change back, so each test starts from the same place it left.
  late Map<String, double> baseline;
  Map<String, double> expectedRatings = {};

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Results');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    await addMember(owner, communityId, player2);
    // In the past, because a final result belongs to a match that has been
    // played: migration 0074 refuses one with MATCH_NOT_COMPLETED while the
    // match is still to come or is under way, and every test below records a
    // result. Day 26 stays this file's window; it is simply behind us now.
    // The refusal itself is covered by all_state_match_management_test.dart.
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: -26), startingPlayers: 4);
  });

  /// Deleting the community deletes its matches, and the `before delete` trigger
  /// on `matches` gives back every rating and counter the results produced. The
  /// six accounts are permanent fixtures and are left exactly as found.
  tearDown(() async => disposeCommunity(owner, communityId));

  ResultRepository repositoryFor(TestUser actor) =>
      ResultRepository(SupabaseResultAdapter(actor.client));

  Future<void> storeLineup() async {
    await owner.client.rpc('replace_match_lineup', params: {
      'p_match_id': matchId,
      // The match is played, so this is an explicit correction to the record of
      // who played rather than a generation: migration 0071 refuses a
      // generation on a completed match, and the flag is how the caller says
      // which of the two it means.
      'p_from_generation': false,
      'p_completed_correction': true,
      'p_assignments': [
        {
          'user_id': owner.id,
          'team': 'A',
          'assigned_position': 'GK',
          'assignment_basis': 'PRIMARY',
        },
        {
          'user_id': admin.id,
          'team': 'A',
          'assigned_position': 'MID',
          'assignment_basis': 'PRIMARY',
        },
        {
          'user_id': player.id,
          'team': 'B',
          'assigned_position': 'GK',
          'assignment_basis': 'PRIMARY',
        },
        {
          'user_id': player2.id,
          'team': 'B',
          'assigned_position': 'FWD',
          'assignment_basis': 'PRIMARY',
        },
      ],
    });
  }

  /// The stored lineup, as the repository is handed it. Only the player and the
  /// side matter to a result; the position is read back as it is stored.
  Future<List<TeamAssignment>> lineup() async {
    final rows = await owner.client
        .from('match_team_assignments')
        .select('user_id, team, assigned_position, assignment_basis')
        .eq('match_id', matchId);
    return [
      for (final row in rows)
        TeamAssignment(
          userId: row['user_id'] as String,
          team: row['team'] == 'A' ? TeamId.a : TeamId.b,
          assignedPosition: Position.mid,
          basis: AssignmentBasis.primary,
        ),
    ];
  }

  Future<double> ratingOf(TestUser user) async {
    final row = await owner.client
        .from('users')
        .select('overall_rating')
        .eq('id', user.id)
        .single();
    return (row['overall_rating'] as num).toDouble();
  }

  Future<void> captureBaseline() async {
    baseline = {for (final user in squad) user.id: await ratingOf(user)};
    for (final user in squad) {
      expect((await repositoryFor(owner).fetchStatistics(user.id)).matchesPlayed, 0,
          reason:
              'Weighted result tests require isolated clean fixture accounts');
      expect(baseline[user.id], 5);
    }
  }

  /// How far [user]'s rating has moved since the baseline was taken. Asserting
  /// the change rather than the number is what lets these tests run against
  /// accounts whose rating is whatever previous runs left it.
  Future<double> gainOf(TestUser user) async =>
      await ratingOf(user) - baseline[user.id]!;

  Future<PlayerStatistics> statisticsOf(TestUser user) =>
      repositoryFor(owner).fetchStatistics(user.id);

  Future<void> record(
    TestUser actor, {
    required int teamA,
    required int teamB,
    required TestUser mvp,
    Map<TestUser, int> goals = const {},
  }) async {
    await repositoryFor(actor).recordResult(
      matchId: matchId,
      teamAScore: teamA,
      teamBScore: teamB,
      mvpUserId: mvp.id,
      goals: [
        for (final entry in goals.entries)
          GoalTally(userId: entry.key.id, goals: entry.value),
      ],
      lineup: await lineup(),
    );
    expectedRatings = {
      for (final user in squad)
        user.id: storedWeightedRating(weightedRating([
          RatedMatch(
              teamA == teamB
                  ? MatchOutcome.draw
                  : ((squad.indexOf(user) < 2) == (teamA > teamB))
                      ? MatchOutcome.win
                      : MatchOutcome.loss,
              goals: goals[user] ?? 0,
              mvp: user.id == mvp.id),
        ])),
    };
  }

  /// Sends the numbers straight to the RPC, past the repository's checks, so
  /// that the database's own refusal is what is being tested.
  Future<String> recordRaw(
    TestUser actor, {
    required int teamA,
    required int teamB,
    required String mvpUserId,
    List<Map<String, dynamic>> goals = const [],
  }) =>
      outcomeOf(() async {
        await actor.client.rpc('record_match_result', params: {
          'p_match_id': matchId,
          'p_team_a_score': teamA,
          'p_team_b_score': teamB,
          'p_mvp_user_id': mvpUserId,
          'p_goals': goals,
        });
      });

  group('who may record a result', () {
    setUp(storeLineup);

    test('the owner may', () async {
      expect(
        await recordRaw(owner, teamA: 0, teamB: 0, mvpUserId: owner.id),
        'ALLOW',
      );
    });

    test('an admin may', () async {
      expect(
        await recordRaw(admin, teamA: 0, teamB: 0, mvpUserId: owner.id),
        'ALLOW',
      );
    });

    test('an ordinary player may not', () async {
      // Management is a community role (PD-07), and recording a result is
      // management. Playing in the match is not a permission.
      expect(
        await recordRaw(player, teamA: 0, teamB: 0, mvpUserId: owner.id),
        'NOT_AUTHORIZED',
      );
    });

    test('an outsider may not', () async {
      expect(
        await recordRaw(outsider, teamA: 0, teamB: 0, mvpUserId: owner.id),
        'NOT_AUTHORIZED',
      );
    });

    test('nobody may write a rating directly', () async {
      // OP-1: the rating is system-managed. Without this the whole engine is
      // decoration — a player could simply award themselves a 10.
      //
      // The refusal is a privilege error, not a policy one: RLS cannot restrict
      // which columns an update touches, so migration `0022` narrowed the column
      // grant instead. That is why this raises rather than quietly matching no
      // rows, which is what an RLS refusal would do.
      final before = await ratingOf(owner);

      await expectLater(
        owner.client
            .from('users')
            .update({'overall_rating': 9.9}).eq('id', owner.id),
        throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );
      expect(await ratingOf(owner), closeTo(before, 0.001));
    });

    test('a player may still write the profile fields they own', () async {
      // The narrowed grant took the rating and nothing else: what the profile
      // screen sends still goes through.
      await expectLater(
        player.client
            .from('users')
            .update({'secondary_position': 'DEF'}).eq('id', player.id),
        completes,
      );
      await player.client
          .from('users')
          .update({'secondary_position': null}).eq('id', player.id);
    });

    test('nobody may write the audit or the counters', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});

      final history = await owner.client
          .from('rating_history')
          .update({'delta': 9.9})
          .eq('match_id', matchId)
          .select();
      expect(history, isEmpty, reason: 'no update policy exists');

      final counters = await owner.client
          .from('player_statistics')
          .update({'wins': 99})
          .eq('user_id', owner.id)
          .select();
      expect(counters, isEmpty);
    });
  });

  group('the rules the database enforces', () {
    setUp(storeLineup);

    test('goals that do not add up to the score are refused', () async {
      expect(
        await recordRaw(owner, teamA: 3, teamB: 0, mvpUserId: owner.id, goals: [
          {'user_id': owner.id, 'goals': 1},
        ]),
        'GOALS_DO_NOT_MATCH_SCORE',
      );
    });

    test('a negative score is refused', () async {
      expect(
        await recordRaw(owner, teamA: -1, teamB: 0, mvpUserId: owner.id),
        'INVALID_SCORE',
      );
    });

    test('a negative goal tally is refused', () async {
      expect(
        await recordRaw(owner, teamA: 0, teamB: 0, mvpUserId: owner.id, goals: [
          {'user_id': owner.id, 'goals': -1},
        ]),
        'INVALID_GOALS',
      );
    });

    test('the same scorer twice is refused', () async {
      expect(
        await recordRaw(owner, teamA: 3, teamB: 0, mvpUserId: owner.id, goals: [
          {'user_id': owner.id, 'goals': 1},
          {'user_id': owner.id, 'goals': 2},
        ]),
        'INVALID_GOALS',
      );
    });

    test('a best player who did not play is refused', () async {
      expect(
        await recordRaw(owner, teamA: 0, teamB: 0, mvpUserId: outsider.id),
        'MVP_NOT_PARTICIPANT',
      );
    });

    test('a scorer who did not play is refused', () async {
      expect(
        await recordRaw(owner, teamA: 1, teamB: 0, mvpUserId: owner.id, goals: [
          {'user_id': outsider.id, 'goals': 1},
        ]),
        'SCORER_NOT_PARTICIPANT',
      );
    });

    test('a refused result leaves no trace', () async {
      final before = await ratingOf(owner);
      final played = (await statisticsOf(owner)).matchesPlayed;

      await recordRaw(owner, teamA: 5, teamB: 0, mvpUserId: owner.id);

      expect(await repositoryFor(owner).fetchResult(matchId), isNull);
      expect(await ratingOf(owner), closeTo(before, 0.001));
      expect((await statisticsOf(owner)).matchesPlayed, played);
    });
  });

  group('a match with no lineup', () {
    test('cannot have a result recorded', () async {
      // Without sides there is no winner to reward and no loser to charge.
      expect(
        await recordRaw(owner, teamA: 0, teamB: 0, mvpUserId: owner.id),
        'LINEUP_REQUIRED',
      );
    });
  });

  group('recording a result', () {
    setUp(storeLineup);

    test('the result and its goals come back as they went in', () async {
      await record(owner,
          teamA: 2, teamB: 1, mvp: admin, goals: {admin: 2, player2: 1});

      final result = await repositoryFor(player).fetchResult(matchId);
      expect(result, isNotNull);
      expect(result!.teamAScore, 2);
      expect(result.teamBScore, 1);
      expect(result.mvpUserId, admin.id);
      expect(result.recordedGoals, 3);
      expect(result.goalsBy(admin.id), 2);
    });

    test('a member may read a result they did not record', () async {
      await record(owner, teamA: 0, teamB: 0, mvp: player);

      expect(await repositoryFor(player).fetchResult(matchId), isNotNull);
    });

    test('an outsider sees nothing', () async {
      await record(owner, teamA: 0, teamB: 0, mvp: player);

      expect(await repositoryFor(outsider).fetchResult(matchId), isNull);
    });
  });

  group('the rating engine, as the database applies it', () {
    setUp(() async {
      await storeLineup();
      await captureBaseline();
    });

    test('wins and losses contribute their weighted match scores', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: player, goals: {owner: 1});

      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
      expect(await ratingOf(admin), closeTo(expectedRatings[admin.id]!, 0.001));
      expect(
          await ratingOf(player), closeTo(expectedRatings[player.id]!, 0.001));
      expect(await ratingOf(player2),
          closeTo(expectedRatings[player2.id]!, 0.001));
    });

    test('a draw contributes 4.4 plus individual quality', () async {
      await record(owner,
          teamA: 1, teamB: 1, mvp: owner, goals: {owner: 1, player: 1});
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
      expect(await ratingOf(admin), closeTo(expectedRatings[admin.id]!, 0.001));
      expect(
          await ratingOf(player), closeTo(expectedRatings[player.id]!, 0.001));
      expect(await ratingOf(player2),
          closeTo(expectedRatings[player2.id]!, 0.001));
    });

    test('a goalless match still moves the outcome and the best player',
        () async {
      await record(owner, teamA: 0, teamB: 0, mvp: player2);

      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
      expect(await ratingOf(player2),
          closeTo(expectedRatings[player2.id]!, 0.001));
    });

    test('goals improve the weighted match score', () async {
      await record(owner, teamA: 3, teamB: 0, mvp: player, goals: {owner: 3});
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
    });

    test('goals above seven still improve the score', () async {
      await record(owner, teamA: 9, teamB: 0, mvp: player, goals: {owner: 9});
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
    });

    test('the losing top scorer with the MVP stays below a plain winner',
        () async {
      // The rule the values exist to serve, as the database applies it: player
      // loses, scores five and is named best on the pitch; admin only won.
      await record(owner,
          teamA: 6, teamB: 5, mvp: player, goals: {owner: 6, player: 5});
      expect(
          await ratingOf(player), closeTo(expectedRatings[player.id]!, 0.001));
      expect(await ratingOf(admin), closeTo(expectedRatings[admin.id]!, 0.001));
      expect(await gainOf(player), lessThan(await gainOf(admin)));
    });

    test('the database agrees with the weighted Dart mirror', () async {
      await record(owner,
          teamA: 2, teamB: 1, mvp: admin, goals: {admin: 2, player: 1});
      for (final user in squad) {
        expect(await ratingOf(user), closeTo(expectedRatings[user.id]!, 0.001));
      }
    });

    test('a rating cannot pass the top of the range', () async {
      // The stored mean and every audit movement must respect the scale.
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});
      final history = await repositoryFor(owner).fetchRatingHistory(matchId);

      for (final change in history) {
        expect(change.ratingAfter, lessThan(10.0));
        expect(change.ratingAfter, greaterThanOrEqualTo(0.0));
        expect(change.delta,
            closeTo(change.ratingAfter - change.ratingBefore, 0.001),
            reason: 'the recorded delta is the one that was applied');
      }
    });
  });

  group('the rating audit', () {
    setUp(() async {
      await storeLineup();
      await captureBaseline();
    });

    test('one weighted match movement is recorded per player', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});

      final history = await repositoryFor(owner).fetchRatingHistory(matchId);
      final mine = [
        for (final c in history)
          if (c.userId == owner.id) c
      ];

      expect(mine.map((c) => c.reason), [
        RatingChangeReason.win,
      ]);
      expect(history.where((c) => c.reason == RatingChangeReason.loss),
          hasLength(2));
    });

    test('each entry says what the rating moved between', () async {
      await record(owner, teamA: 0, teamB: 0, mvp: owner);

      final history = await repositoryFor(owner).fetchRatingHistory(matchId);
      final mvp = history.singleWhere((c) => c.userId == owner.id);
      expect(mvp.ratingBefore, 5);
      expect(mvp.ratingAfter, expectedRatings[owner.id]);
      expect(mvp.delta, closeTo(mvp.ratingAfter - 5, 0.001));
      expect(mvp.reversesId, isNull);
    });
  });

  group('the counters', () {
    setUp(() async {
      await storeLineup();
      await captureBaseline();
    });

    test('a win, a loss and the goals behind them', () async {
      await record(owner,
          teamA: 2, teamB: 0, mvp: owner, goals: {owner: 1, admin: 1});

      final mine = await statisticsOf(owner);
      expect(mine.matchesPlayed, 1);
      expect(mine.wins, 1);
      expect(mine.losses, 0);
      expect(mine.draws, 0);
      expect(mine.goals, 1);
      expect(mine.mvpCount, 1);
      expect(mine.currentRating, expectedRatings[owner.id]);

      final theirs = await statisticsOf(player);
      expect(theirs.matchesPlayed, 1);
      expect(theirs.losses, 1);
      expect(theirs.wins, 0);
      expect(theirs.goals, 0);
      expect(theirs.mvpCount, 0);
    });

    test('a draw counts for both sides', () async {
      await record(owner, teamA: 0, teamB: 0, mvp: owner);

      for (final user in squad) {
        final counters = await statisticsOf(user);
        expect(counters.draws, 1, reason: user.label);
        expect(counters.wins, 0, reason: user.label);
        expect(counters.losses, 0, reason: user.label);
        expect(counters.matchesPlayed, 1, reason: user.label);
      }
    });

    test('somebody who did not play is counted in nothing', () async {
      await record(owner, teamA: 0, teamB: 0, mvp: owner);

      expect((await statisticsOf(outsider)).matchesPlayed, 0);
    });
  });

  group('correcting a recorded result', () {
    setUp(() async {
      await storeLineup();
      await captureBaseline();
    });

    test('the ratings end where the new result alone would put them', () async {
      await record(owner, teamA: 3, teamB: 0, mvp: owner, goals: {owner: 3});
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));

      await record(owner, teamA: 0, teamB: 1, mvp: player, goals: {player: 1});
      // Every change the 3-0 made is given back, and the 0-1 applied in its
      // place: the owner is left with a loss and nothing else, and the player —
      // now on the winning side, having scored it and taken the MVP — collects
      // all three. Neither carries anything over from the result that was
      // replaced.
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
      expect(
          await ratingOf(player), closeTo(expectedRatings[player.id]!, 0.001));
    });

    test('the counters end where the new result alone would put them',
        () async {
      await record(owner, teamA: 3, teamB: 0, mvp: owner, goals: {owner: 3});
      await record(owner, teamA: 0, teamB: 1, mvp: player, goals: {player: 1});

      final mine = await statisticsOf(owner);
      expect(mine.matchesPlayed, 1, reason: 'one match, corrected once');
      expect(mine.wins, 0);
      expect(mine.losses, 1);
      expect(mine.goals, 0);
      expect(mine.mvpCount, 0);

      final theirs = await statisticsOf(player);
      expect(theirs.wins, 1);
      expect(theirs.goals, 1);
      expect(theirs.mvpCount, 1);
    });

    test('the stored result is the new one, goals and all', () async {
      await record(owner, teamA: 3, teamB: 0, mvp: owner, goals: {owner: 3});
      await record(owner, teamA: 0, teamB: 1, mvp: player, goals: {player: 1});

      final result = await repositoryFor(owner).fetchResult(matchId);
      expect(result!.teamAScore, 0);
      expect(result.teamBScore, 1);
      expect(result.mvpUserId, player.id);
      expect(result.goals, hasLength(1));
      expect(result.goalsBy(owner.id), 0,
          reason: 'the previous scorer is gone, not kept alongside');
    });

    test('the audit keeps every entry, and adds the reversals', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});
      final first = await repositoryFor(owner).fetchRatingHistory(matchId);
      await record(owner, teamA: 0, teamB: 1, mvp: player, goals: {player: 1});
      final after = await repositoryFor(owner).fetchRatingHistory(matchId);

      // Nothing was rewritten: every entry of the first recording is still
      // there, unchanged.
      for (final original in first) {
        final kept = after.singleWhere((c) => c.id == original.id);
        expect(kept.delta, original.delta);
        expect(kept.ratingAfter, original.ratingAfter);
        expect(kept.reason, original.reason);
      }

      final reversals = [
        for (final c in after)
          if (c.isReversal) c
      ];
      expect(reversals, hasLength(first.length),
          reason: 'every change the first result made was given back');
      expect(
        {for (final r in reversals) r.reversesId},
        {for (final c in first) c.id},
      );
    });

    test('a correction reverses once, however many times it is corrected',
        () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});
      await record(owner, teamA: 2, teamB: 0, mvp: owner, goals: {owner: 2});
      await record(owner, teamA: 0, teamB: 0, mvp: admin);

      // Only the last result stands: a draw, with admin as best player.
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));
      expect(await ratingOf(admin), closeTo(expectedRatings[admin.id]!, 0.001));

      final mine = await statisticsOf(owner);
      expect(mine.matchesPlayed, 1);
      expect(mine.draws, 1);
      expect(mine.goals, 0);
    });

    test('a correction that is refused changes nothing', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});
      final before = await ratingOf(owner);

      expect(
        await recordRaw(owner, teamA: 9, teamB: 0, mvpUserId: owner.id),
        'GOALS_DO_NOT_MATCH_SCORE',
      );

      expect(await ratingOf(owner), closeTo(before, 0.001));
      final result = await repositoryFor(owner).fetchResult(matchId);
      expect(result!.teamAScore, 1, reason: 'the first result still stands');
      expect((await statisticsOf(owner)).wins, 1);
    });

    test('the repository refuses a correction the same way', () async {
      await record(owner, teamA: 1, teamB: 0, mvp: owner, goals: {owner: 1});

      await expectLater(
        record(owner, teamA: 4, teamB: 0, mvp: owner, goals: {owner: 1}),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.goalsDoNotMatchScore)),
      );
    });
  });

  group('a deleted match gives back what it did', () {
    setUp(() async {
      await storeLineup();
      await captureBaseline();
    });

    test('the ratings and counters go back to where they started', () async {
      // Without this a deleted match would leave the ratings it produced
      // standing, credited to something that no longer exists.
      await record(owner, teamA: 2, teamB: 0, mvp: owner, goals: {owner: 2});
      expect(await ratingOf(owner), closeTo(expectedRatings[owner.id]!, 0.001));

      await owner.client.rpc('delete_match', params: {'p_match_id': matchId});

      for (final user in squad) {
        expect(await gainOf(user), closeTo(0.0, 0.001), reason: user.label);
        expect((await statisticsOf(user)).matchesPlayed, 0, reason: user.label);
      }
    });
  });
}
