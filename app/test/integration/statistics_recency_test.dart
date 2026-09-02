@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0060` — `community_statistics_recency`.
///
/// The read model behind unified tie-breaking. What is exercised here is what
/// only the database can answer: that every timestamp is `matches.start_at`,
/// that the period buckets are the counters' own, that a correction moves the
/// evidence rather than leaving a stale "latest", and that the function is
/// `security invoker` — a non-member reads nothing.
///
/// The ordering built on top of these timestamps is the repository's and is
/// covered by `statistics_tie_break_test.dart`; nothing here re-asserts it.
void main() {
  if (!integrationConfigured) {
    test('statistics recency', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser player2;
  late TestUser outsider;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    player2 = await signInTestUser('player2');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Statistics Recency');
    for (final user in [admin, player, player2]) {
      await addMember(owner, communityId, user);
    }
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  List<TestUser> squadOf() => [owner, admin, player, player2];

  /// A played match with a stored lineup, started [daysAgo] days ago.
  ///
  /// The start is moved after the roster is built: registration is closed to a
  /// match that has already ended, so the fixture is assembled first and the
  /// clock set afterwards.
  Future<String> playedMatch({required int daysAgo}) async {
    final matchId = await createMatch(
      owner,
      communityId,
      startsIn: const Duration(days: 9),
      startingPlayers: 4,
    );
    final squad = squadOf();
    for (final user in squad) {
      await user.client
          .rpc('register_for_match', params: {'p_match_id': matchId});
    }
    await owner.client.rpc('replace_match_lineup', params: {
      'p_match_id': matchId,
      'p_assignments': [
        for (final (index, user) in squad.indexed)
          {
            'user_id': user.id,
            'team': index < 2 ? 'A' : 'B',
            'assigned_position': const ['DEF', 'MID', 'FWD', 'GK'][index],
            'assignment_basis': 'TRANSITION',
          },
      ],
    });
    final start = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
    await owner.client.from('matches').update({
      'start_at': start.toIso8601String(),
      'end_at': start.add(const Duration(hours: 2)).toIso8601String(),
    }).eq('id', matchId);
    return matchId;
  }

  Future<void> recordResult(
    String matchId, {
    required int teamA,
    required int teamB,
    String? mvpUserId,
    List<Map<String, Object?>> goals = const [],
  }) =>
      owner.client.rpc('record_match_result', params: {
        'p_match_id': matchId,
        'p_team_a_score': teamA,
        'p_team_b_score': teamB,
        'p_mvp_user_id': mvpUserId,
        'p_goals': goals,
      });

  /// The read model, as the client calls it.
  Future<Map<String, Map<String, dynamic>>> recency(
    TestUser reader, {
    String periodType = 'overall',
    String periodKey = 'overall',
  }) async {
    final rows = await reader.client.rpc(
      'community_statistics_recency',
      params: {
        'p_community_id': communityId,
        'p_period_type': periodType,
        'p_period_key': periodKey,
      },
    ) as List<dynamic>;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['user_id'] as String: row,
    };
  }

  DateTime? stamp(Map<String, dynamic>? row, String field) {
    final value = row?[field];
    return value == null ? null : DateTime.parse(value as String).toUtc();
  }

  /// The start the database stored for a match, to compare a timestamp against.
  Future<DateTime> startOf(String matchId) async {
    final row = await owner.client
        .from('matches')
        .select('start_at')
        .eq('id', matchId)
        .single();
    return DateTime.parse(row['start_at'] as String).toUtc();
  }

  group('the timestamps are the football, not the bookkeeping', () {
    test('each measure reports the start of the match it happened in',
        () async {
      final older = await playedMatch(daysAgo: 30);
      await recordResult(older,
          teamA: 1,
          teamB: 0,
          mvpUserId: owner.id,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);

      final newer = await playedMatch(daysAgo: 3);
      await recordResult(newer,
          teamA: 0,
          teamB: 2,
          mvpUserId: player.id,
          goals: [
            {'user_id': player.id, 'goals': 2}
          ]);

      final rows = await recency(owner);
      final ownerRow = rows[owner.id];

      // The owner scored, was MVP and won in the older match; they played in
      // both, and lost the newer one.
      expect(stamp(ownerRow, 'last_goal_at'), await startOf(older));
      expect(stamp(ownerRow, 'last_mvp_at'), await startOf(older));
      expect(stamp(ownerRow, 'last_win_at'), await startOf(older));
      expect(stamp(ownerRow, 'last_played_at'), await startOf(newer),
          reason: 'played is the newest participation, win is the newest win');
    });

    test('a match recorded today but played long ago stays old', () async {
      // The whole reason the comparison is `start_at`. This match is entered
      // now and played a month ago; it must not outrank a match from last week.
      final lastWeek = await playedMatch(daysAgo: 7);
      await recordResult(lastWeek,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);

      final longAgo = await playedMatch(daysAgo: 60);
      await recordResult(longAgo,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);

      expect(stamp((await recency(owner))[owner.id], 'last_goal_at'),
          await startOf(lastWeek),
          reason: 'entered last, played first — and played is what counts');
    });

    test('a measure that never happened is null, not an old date', () async {
      final matchId = await playedMatch(daysAgo: 5);
      // A draw: nobody wins, nobody scores, nobody is named MVP.
      await recordResult(matchId, teamA: 0, teamB: 0);

      final row = (await recency(owner))[owner.id];
      expect(stamp(row, 'last_played_at'), isNotNull);
      expect(stamp(row, 'last_goal_at'), isNull);
      expect(stamp(row, 'last_win_at'), isNull);
      expect(stamp(row, 'last_mvp_at'), isNull);
    });

    test('a Professional Guest is not a player with recency', () async {
      final matchId = await playedMatch(daysAgo: 5);
      final guestId = await owner.client.rpc('add_professional_guest',
          params: {'p_match_id': matchId, 'p_name': 'Faisal'});
      await recordResult(matchId, teamA: 1, teamB: 0);

      expect((await recency(owner)).keys, isNot(contains(guestId)));
    });
  });

  group('the period is the counters own', () {
    test('an overall read sees a match a weekly read does not', () async {
      final longAgo = await playedMatch(daysAgo: 90);
      await recordResult(longAgo,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);

      expect(stamp((await recency(owner))[owner.id], 'last_goal_at'),
          isNotNull);

      // The week that match fell in, asked of the database rather than
      // recomputed here, so the boundary is the one migration 0028 froze.
      final key = await owner.client.rpc('statistics_period_key', params: {
        'p_start_at': (await startOf(longAgo)).toIso8601String(),
        'p_period_type': 'weekly',
      }) as String;

      final inThatWeek =
          await recency(owner, periodType: 'weekly', periodKey: key);
      expect(stamp(inThatWeek[owner.id], 'last_goal_at'), isNotNull);

      final thisWeekKey = await owner.client.rpc('statistics_period_key',
          params: {
            'p_start_at': DateTime.now().toUtc().toIso8601String(),
            'p_period_type': 'weekly',
          }) as String;
      if (thisWeekKey != key) {
        final thisWeek = await recency(owner,
            periodType: 'weekly', periodKey: thisWeekKey);
        expect(stamp(thisWeek[owner.id], 'last_goal_at'), isNull,
            reason: 'a goal outside the week is not evidence inside it');
      }
    });

    test('the rating recency ignores the period entirely', () async {
      // Highest Rated shows the Global Rating in every period, so its
      // tie-break is the same answer in all three.
      final matchId = await playedMatch(daysAgo: 40);
      await recordResult(matchId, teamA: 1, teamB: 0);

      final overall = stamp((await recency(owner))[owner.id], 'last_rating_at');
      final weekly = stamp(
        (await recency(owner, periodType: 'weekly', periodKey: '2026-W01'))[
            owner.id],
        'last_rating_at',
      );

      expect(overall, isNotNull);
      expect(weekly, overall,
          reason: 'global means global, whichever window is asked for');
    });
  });

  group('corrections move the evidence', () {
    test('a goal that no longer counts stops being the latest goal', () async {
      final older = await playedMatch(daysAgo: 30);
      await recordResult(older,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);
      final newer = await playedMatch(daysAgo: 3);
      await recordResult(newer,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': owner.id, 'goals': 1}
          ]);

      expect(stamp((await recency(owner))[owner.id], 'last_goal_at'),
          await startOf(newer));

      // The newer result is corrected: the owner did not score in it after all.
      await recordResult(newer,
          teamA: 1,
          teamB: 0,
          goals: [
            {'user_id': admin.id, 'goals': 1}
          ]);

      expect(stamp((await recency(owner))[owner.id], 'last_goal_at'),
          await startOf(older),
          reason: 'the corrected goal is not evidence any more');
    });

    test('a replaced MVP is no longer the MVP timestamp', () async {
      final matchId = await playedMatch(daysAgo: 5);
      await recordResult(matchId, teamA: 1, teamB: 0, mvpUserId: owner.id);
      expect(stamp((await recency(owner))[owner.id], 'last_mvp_at'), isNotNull);

      await recordResult(matchId, teamA: 1, teamB: 0, mvpUserId: admin.id);

      final rows = await recency(owner);
      expect(stamp(rows[owner.id], 'last_mvp_at'), isNull);
      expect(stamp(rows[admin.id], 'last_mvp_at'), isNotNull);
    });

    test('a corrected score moves the win to the side that won', () async {
      final matchId = await playedMatch(daysAgo: 5);
      // Team A wins: owner and admin are on A.
      await recordResult(matchId, teamA: 2, teamB: 1);

      var rows = await recency(owner);
      expect(stamp(rows[owner.id], 'last_win_at'), isNotNull);
      expect(stamp(rows[player.id], 'last_win_at'), isNull);

      // The score was entered the wrong way round.
      await recordResult(matchId, teamA: 1, teamB: 2);

      rows = await recency(owner);
      expect(stamp(rows[owner.id], 'last_win_at'), isNull);
      expect(stamp(rows[player.id], 'last_win_at'), isNotNull,
          reason: 'the current winning side, not the one first recorded');
    });

    test('participation taken out of the lineup stops being participation',
        () async {
      final matchId = await playedMatch(daysAgo: 5);
      await recordResult(matchId, teamA: 1, teamB: 0);
      expect(stamp((await recency(owner))[player2.id], 'last_played_at'),
          isNotNull);

      // The correction that says they did not play after all.
      await owner.client.rpc('set_completed_match_player', params: {
        'p_match_id': matchId,
        'p_user_id': player2.id,
        'p_team': null,
        'p_assigned_position': null,
      });

      expect((await recency(owner))[player2.id]?['last_played_at'], isNull,
          reason: 'no lineup row, no participation recency');
    });

    test('a reversed rating entry is not rating recency', () async {
      final older = await playedMatch(daysAgo: 30);
      await recordResult(older, teamA: 1, teamB: 0);
      final newer = await playedMatch(daysAgo: 3);
      await recordResult(newer, teamA: 1, teamB: 0);

      expect(stamp((await recency(owner))[player2.id], 'last_rating_at'),
          await startOf(newer));

      // Taking them out of the newer lineup reverses the rating entries that
      // match gave them — `set_completed_match_player` detaches the effects,
      // removes the row and reattaches, so nothing reapplies them.
      await owner.client.rpc('set_completed_match_player', params: {
        'p_match_id': newer,
        'p_user_id': player2.id,
        'p_team': null,
        'p_assigned_position': null,
      });

      expect(stamp((await recency(owner))[player2.id], 'last_rating_at'),
          await startOf(older),
          reason: 'a reversed entry is not part of the rating held now');
    });
  });

  group('authorization is the databases', () {
    test('a non-member reads nothing', () async {
      // `security invoker`: the policies on matches, results and rating history
      // decide, exactly as they do for `community_statistics`. An outsider gets
      // an empty result rather than a refusal — the same shape a community with
      // no football has.
      final matchId = await playedMatch(daysAgo: 5);
      await recordResult(matchId, teamA: 1, teamB: 0);

      expect(await recency(owner), isNotEmpty);
      expect(await recency(outsider), isEmpty);
    });

    test('a member reads the community they belong to', () async {
      final matchId = await playedMatch(daysAgo: 5);
      await recordResult(matchId, teamA: 1, teamB: 0);

      expect(await recency(player), isNotEmpty);
    });
  });
}
