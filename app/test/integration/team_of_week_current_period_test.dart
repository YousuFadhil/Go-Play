@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/infrastructure/supabase/supabase_statistics_adapter.dart';

import 'support.dart';

/// Migration `0077` — Team of the Week is the week now running.
///
/// What only the database can answer: that the weekly window is the ISO week
/// containing the database's own clock, in Muscat; that an empty week is still
/// that week; that inside it the award follows completed matches and
/// corrections as they happen; that Team of the Month is still the last
/// completed month; and that who may read any of it has not moved.
///
/// The expected week is computed here from this machine's clock. A run that
/// straddles Monday 00:00 in Muscat could disagree with itself, which is a
/// window of seconds once a week.
void main() {
  if (!integrationConfigured) {
    test('team of the week: current period', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Team of the Week');
    for (final user in [admin, player, player2, player3]) {
      await addMember(owner, communityId, user);
    }
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  const muscat = Duration(hours: 4);

  /// The ISO week containing [instant], Monday 00:00 in Muscat, half-open.
  ({DateTime start, DateTime end, String key}) weekOf(DateTime instant) {
    final wall = instant.toUtc().add(muscat);
    final monday = DateTime.utc(wall.year, wall.month, wall.day)
        .subtract(Duration(days: wall.weekday - DateTime.monday));
    final thursday = monday.add(const Duration(days: 3));
    final dayOfYear =
        thursday.difference(DateTime.utc(thursday.year)).inDays + 1;
    final isoWeek = (dayOfYear - 1) ~/ 7 + 1;
    final start = monday.subtract(muscat);
    return (
      start: start,
      end: start.add(const Duration(days: 7)),
      key: '${thursday.year}-W${isoWeek.toString().padLeft(2, '0')}',
    );
  }

  /// The last fully completed calendar month before [instant], in Muscat.
  ({DateTime start, DateTime end, String key}) lastMonthOf(DateTime instant) {
    final wall = instant.toUtc().add(muscat);
    final thisMonth = DateTime.utc(wall.year, wall.month);
    final lastMonth = DateTime.utc(wall.year, wall.month - 1);
    return (
      start: lastMonth.subtract(muscat),
      end: thisMonth.subtract(muscat),
      key: '${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}',
    );
  }

  List<TestUser> squadOf() => [owner, admin, player, player2];

  /// A completed match with a stored lineup, played at [start].
  ///
  /// Built as a future fixture and then moved, because registration is closed
  /// to a match that has already ended — the same approach the statistics
  /// recency suite takes. Moving it before the next one is built keeps two
  /// fixtures from overlapping for the same players.
  Future<String> playedMatch({
    required DateTime start,
    required Duration duration,
  }) async {
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
    await owner.client.from('matches').update({
      'start_at': start.toUtc().toIso8601String(),
      'end_at': start.toUtc().add(duration).toIso8601String(),
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

  /// A start inside the current week that has already finished by now: slot
  /// [slot] of [slots] evenly spaced through the part of the week that has
  /// elapsed, each lasting a third of its share so no two overlap.
  ({DateTime start, Duration duration})? thisWeekSlot(int slot,
      {int slots = 3}) {
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(weekOf(now).start);
    // In the first minutes of a Monday there is no finished football to place.
    if (elapsed < const Duration(minutes: 10)) return null;
    final share = elapsed ~/ (slots + 1);
    final start = weekOf(now).start.add(share * (slot + 1));
    return (start: start, duration: share ~/ 3);
  }

  Future<Map<String, dynamic>> windowOf(TestUser reader, String type) async {
    final rows = await reader.client.rpc('community_period_xi_window', params: {
      'p_community_id': communityId,
      'p_period_type': type,
    }) as List<dynamic>;
    expect(rows, hasLength(1), reason: 'exactly one window, always');
    return Map<String, dynamic>.from(rows.single as Map);
  }

  Future<Map<String, Map<String, dynamic>>> candidatesOf(
      TestUser reader, String type) async {
    final rows =
        await reader.client.rpc('community_period_xi_evidence', params: {
      'p_community_id': communityId,
      'p_period_type': type,
    }) as List<dynamic>;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['user_id'] as String: row,
    };
  }

  DateTime instant(Object? value) => DateTime.parse(value as String).toUtc();

  group('the week is the one being played', () {
    test('an empty week is still this week, and never last week', () async {
      final expected = weekOf(DateTime.now());

      var window = await windowOf(player, 'weekly');
      expect(window['period_type'], 'weekly');
      expect(window['period_key'], expected.key);
      expect(instant(window['period_start']), expected.start);
      expect(instant(window['period_end']), expected.end);
      expect(window['qualifying_match_count'], 0);
      expect(window['required_matches'], 0);
      expect(window['evidence_last_changed_at'], isNull);
      expect(await candidatesOf(player, 'weekly'), isEmpty);

      // Last week had football. The award does not reach back for it.
      final lastWeek = await playedMatch(
        start: expected.start.subtract(const Duration(days: 2)),
        duration: const Duration(hours: 1),
      );
      await recordResult(lastWeek, teamA: 1, teamB: 0, goals: [
        {'user_id': owner.id, 'goals': 1},
      ]);

      window = await windowOf(player, 'weekly');
      expect(window['period_key'], expected.key,
          reason: 'still the current week, with no fallback');
      expect(window['qualifying_match_count'], 0);
      expect(await candidatesOf(player, 'weekly'), isEmpty);
    });

    test('the week begins at Monday 00:00 in Muscat, by start_at', () async {
      final now = DateTime.now().toUtc();
      final week = weekOf(now);
      if (now.difference(week.start) < const Duration(minutes: 10)) return;

      // One minute before the week, ending on its first instant: last week's.
      final before = await playedMatch(
        start: week.start.subtract(const Duration(minutes: 1)),
        duration: const Duration(minutes: 1),
      );
      await recordResult(before, teamA: 0, teamB: 0);
      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 0);

      // On the first instant of the week: this week's.
      final onTheLine = await playedMatch(
        start: week.start,
        duration: const Duration(minutes: 2),
      );
      await recordResult(onTheLine, teamA: 0, teamB: 0);
      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 1);
    });
  });

  group('inside the week, the award follows its evidence', () {
    test('a match completed this week joins it, and only with a result',
        () async {
      final first = thisWeekSlot(0);
      if (first == null) return;

      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 0);

      final matchId =
          await playedMatch(start: first.start, duration: first.duration);
      // Completed, lineup stored, no result yet: not evidence.
      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 0);

      await recordResult(matchId, teamA: 1, teamB: 0, goals: [
        {'user_id': owner.id, 'goals': 1},
      ]);
      var window = await windowOf(owner, 'weekly');
      expect(window['qualifying_match_count'], 1);
      expect(window['required_matches'], 1);
      expect(window['evidence_last_changed_at'], isNotNull);
      var candidates = await candidatesOf(owner, 'weekly');
      expect(candidates.keys.toSet(), {for (final u in squadOf()) u.id});
      expect(candidates[owner.id]!['matches_played'], 1);
      expect(candidates[owner.id]!['eligible'], isTrue);

      // A second match, entered today for a time already played this week.
      final second = thisWeekSlot(1)!;
      final secondId =
          await playedMatch(start: second.start, duration: second.duration);
      await recordResult(secondId, teamA: 0, teamB: 0);

      window = await windowOf(owner, 'weekly');
      expect(window['qualifying_match_count'], 2);
      candidates = await candidatesOf(owner, 'weekly');
      expect(candidates[owner.id]!['matches_played'], 2);
      expect(candidates[player2.id]!['participation_rate'], 1);
    });

    test('a corrected result, goal or MVP moves it', () async {
      final slot = thisWeekSlot(0);
      if (slot == null) return;
      final matchId =
          await playedMatch(start: slot.start, duration: slot.duration);

      // Team A (owner, admin) wins; the owner scores and is best player.
      await recordResult(matchId,
          teamA: 1,
          teamB: 0,
          mvpUserId: owner.id,
          goals: [
            {'user_id': owner.id, 'goals': 1},
          ]);
      var candidates = await candidatesOf(owner, 'weekly');
      expect(candidates[owner.id]!['wins'], 1);
      expect(candidates[owner.id]!['goals'], 1);
      expect(candidates[owner.id]!['mvp_count'], 1);
      expect(candidates[player.id]!['losses'], 1);
      final before = instant(
          (await windowOf(owner, 'weekly'))['evidence_last_changed_at']);

      // Corrected: team B (player, player2) won 2-0, player scored both and was
      // the best player.
      await recordResult(matchId,
          teamA: 0,
          teamB: 2,
          mvpUserId: player.id,
          goals: [
            {'user_id': player.id, 'goals': 2},
          ]);
      candidates = await candidatesOf(owner, 'weekly');
      expect(candidates[owner.id]!['wins'], 0);
      expect(candidates[owner.id]!['losses'], 1);
      expect(candidates[owner.id]!['goals'], 0);
      expect(candidates[owner.id]!['mvp_count'], 0);
      expect(candidates[player.id]!['wins'], 1);
      expect(candidates[player.id]!['goals'], 2);
      expect(candidates[player.id]!['mvp_count'], 1);

      final after = instant(
          (await windowOf(owner, 'weekly'))['evidence_last_changed_at']);
      expect(after.isBefore(before), isFalse,
          reason: 'the correction is newer evidence');
    });

    test('a corrected lineup and position moves it', () async {
      final slot = thisWeekSlot(0);
      if (slot == null) return;
      final matchId =
          await playedMatch(start: slot.start, duration: slot.duration);
      await recordResult(matchId, teamA: 0, teamB: 0);

      var candidates = await candidatesOf(owner, 'weekly');
      expect(candidates.keys, isNot(contains(player3.id)));
      expect(candidates[player.id]!['period_primary_position'], 'FWD');

      await owner.client.rpc('correct_completed_match_players', params: {
        'p_match_id': matchId,
        'p_changes': [
          {
            'user_id': player3.id,
            'action': 'UPSERT',
            'team': 'A',
            'assigned_position': 'MID',
          },
          {'user_id': admin.id, 'action': 'REMOVE'},
          {
            'user_id': player.id,
            'action': 'UPSERT',
            'team': 'B',
            'assigned_position': 'DEF',
          },
        ],
      });

      candidates = await candidatesOf(owner, 'weekly');
      expect(candidates.keys.toSet(),
          {owner.id, player.id, player2.id, player3.id});
      expect(candidates[player3.id]!['matches_played'], 1);
      expect(candidates[player.id]!['period_primary_position'], 'DEF');
    });
  });

  group('Team of the Month is unchanged', () {
    test('it is the last completed month, and this week is not in it',
        () async {
      final now = DateTime.now().toUtc();
      final expected = lastMonthOf(now);

      var window = await windowOf(owner, 'monthly');
      expect(window['period_type'], 'monthly');
      expect(window['period_key'], expected.key);
      expect(instant(window['period_start']), expected.start);
      expect(instant(window['period_end']), expected.end);
      expect(window['qualifying_match_count'], 0);

      // Eight days before this month began: always last month, and always
      // before the current week.
      final lastMonth = await playedMatch(
        start: expected.end.subtract(const Duration(days: 8)),
        duration: const Duration(hours: 1),
      );
      await recordResult(lastMonth, teamA: 1, teamB: 0, goals: [
        {'user_id': owner.id, 'goals': 1},
      ]);

      window = await windowOf(owner, 'monthly');
      expect(window['qualifying_match_count'], 1);
      expect(window['period_key'], expected.key);
      expect((await candidatesOf(owner, 'monthly')).keys.toSet(),
          {for (final u in squadOf()) u.id});
      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 0);

      // A match this week is the week's; the month only counts it if this
      // week happens to begin inside last month.
      final slot = thisWeekSlot(0);
      if (slot == null) return;
      final thisWeek =
          await playedMatch(start: slot.start, duration: slot.duration);
      await recordResult(thisWeek, teamA: 0, teamB: 0);
      expect((await windowOf(owner, 'weekly'))['qualifying_match_count'], 1);
      if (!slot.start.isBefore(expected.end)) {
        expect((await windowOf(owner, 'monthly'))['qualifying_match_count'], 1,
            reason: 'the running month is not the award month');
      }
    });
  });

  group('who may read it is unchanged', () {
    Future<String> call(Object client, String fn, Map<String, Object?> params) =>
        outcomeOf(() async {
          await (client as dynamic).rpc(fn, params: params);
        });

    test('a member reads both kinds; an outsider and a visitor read neither',
        () async {
      for (final type in ['weekly', 'monthly']) {
        final params = {'p_community_id': communityId, 'p_period_type': type};
        for (final fn in [
          'community_period_xi_window',
          'community_period_xi_evidence',
        ]) {
          expect(await call(player3.client, fn, params), 'ALLOW');
          expect(await call(outsider.client, fn, params), 'NOT_AUTHORIZED');
          expect(await call(anonClient(), fn, params), isNot('ALLOW'));
        }
      }
    });

    test('the period helpers are callable by no client', () async {
      for (final (fn, params) in [
        ('team_of_period_statistics_period', {'p_period_type': 'weekly'}),
        (
          'current_statistics_week_at',
          {'p_at': DateTime.now().toUtc().toIso8601String()}
        ),
        ('last_completed_statistics_period', {'p_period_type': 'monthly'}),
        (
          'community_period_xi_matches',
          {'p_community_id': communityId, 'p_period_type': 'weekly'}
        ),
      ]) {
        expect(await call(owner.client, fn, params), isNot('ALLOW'),
            reason: fn);
        expect(await call(anonClient(), fn, params), isNot('ALLOW'),
            reason: fn);
      }
    });
  });

  group('the award is still selected the same way', () {
    test('the repository selects this week\'s team from this week\'s football',
        () async {
      final repository =
          StatisticsRepository(SupabaseStatisticsAdapter(owner.client));
      final expected = weekOf(DateTime.now());

      var award =
          await repository.fetchTeamOfPeriod(communityId, TeamOfPeriodKind.weekly);
      expect(award.window.periodKey, expected.key);
      expect(award.state, TeamOfPeriodState.noQualifyingMatches);

      final slot = thisWeekSlot(0);
      if (slot == null) return;
      final matchId =
          await playedMatch(start: slot.start, duration: slot.duration);
      await recordResult(matchId,
          teamA: 2,
          teamB: 0,
          mvpUserId: owner.id,
          goals: [
            {'user_id': owner.id, 'goals': 2},
          ]);

      award =
          await repository.fetchTeamOfPeriod(communityId, TeamOfPeriodKind.weekly);
      expect(award.window.periodKey, expected.key);
      expect(award.window.qualifyingMatchCount, 1);
      expect(award.state, TeamOfPeriodState.selected);
      expect(award.selected, isNotEmpty);
      final squad = {for (final u in squadOf()) u.id};
      for (final pick in award.selected) {
        expect(squad, contains(pick.candidate.userId));
      }
    });
  });
}
