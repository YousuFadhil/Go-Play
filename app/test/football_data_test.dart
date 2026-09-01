import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/football_mapper.dart';

/// The Cycle 2 football data layer, above the database.
///
/// What the *server* gives a caller is proved in
/// `test/integration/public_football_data_test.dart`, against a real project.
/// What is asserted here is everything on this side of the wire: that the models
/// have nowhere to put a private field, that a Professional Guest stays
/// match-scoped, that an optional MVP is genuinely optional, and that a stored
/// lineup can be put back together from what the port returns.
///
/// The last group is different in kind: it reads migration `0057` as text and
/// holds it to the privilege rule migration `0034` exists to enforce. That is a
/// guard rather than a behaviour test, and it is here because the behaviour it
/// guards cannot be executed without a database.
void main() {
  Map<String, dynamic> participantRow({
    String type = 'USER',
    String? userId = 'u1',
    String? guestId,
    String name = 'Salim Al Harthy',
  }) =>
      {
        'participant_type': type,
        'user_id': userId,
        'professional_guest_id': guestId,
        'display_name': name,
        'avatar_path': userId == null ? null : 'u1/avatar.jpg',
        'primary_position': userId == null ? null : 'MID',
        'secondary_position': userId == null ? null : 'FWD',
        'overall_rating': userId == null ? null : 6.4,
      };

  String? fakeAvatar(String? path) => path == null ? null : 'https://cdn/$path';

  group('a participant is one of two kinds, and says which', () {
    test('a registered player carries a profile and opens one', () {
      final p = footballParticipantFromRow(participantRow(),
          avatarUrl: fakeAvatar);

      expect(p.type, ParticipantType.user);
      expect(p.userId, 'u1');
      expect(p.guestId, isNull);
      expect(p.avatarUrl, 'https://cdn/u1/avatar.jpg');
      expect(p.primaryPosition, 'MID');
      expect(p.overallRating, 6.4);
      expect(p.opensProfile, isTrue);
    });

    test('a professional guest carries none, and opens nothing', () {
      final p = footballParticipantFromRow(
        participantRow(
            type: 'PROFESSIONAL', userId: null, guestId: 'g1', name: 'Guest'),
        avatarUrl: fakeAvatar,
      );

      expect(p.type, ParticipantType.professionalGuest);
      expect(p.userId, isNull);
      expect(p.guestId, 'g1');
      expect(p.displayName, 'Guest');
      expect(p.avatarUrl, isNull, reason: 'a guest has no picture to have');
      expect(p.primaryPosition, isNull);
      expect(p.overallRating, isNull);
      expect(p.opensProfile, isFalse,
          reason: 'a guest has no profile to open — the rule every screen '
              'showing a participant has to honour');
    });

    test('an unrecognised kind falls back to the one that grants least', () {
      final p = footballParticipantFromRow(participantRow(type: 'SOMETHING'));

      expect(p.type, ParticipantType.professionalGuest);
      expect(p.opensProfile, isFalse);
    });
  });

  group('a completed match', () {
    Map<String, dynamic> matchRow({
      bool hasResult = true,
      int? a = 3,
      int? b = 2,
      String? mvpType = 'USER',
      bool historical = false,
      String? title = 'Friday night',
    }) =>
        {
          'match_id': 'm1',
          'community_id': 'c1',
          'community_name': 'Al Shamal',
          'title': title,
          'location': 'Muscat pitch',
          'start_at': '2026-08-20T18:00:00Z',
          'end_at': '2026-08-20T20:00:00Z',
          'is_historical': historical,
          'has_result': hasResult,
          'team_a_score': a,
          'team_b_score': b,
          'mvp_participant_type': mvpType,
          'mvp_user_id': mvpType == 'USER' ? 'u1' : null,
          'mvp_professional_guest_id': mvpType == 'PROFESSIONAL' ? 'g1' : null,
          'mvp_display_name': mvpType == null ? null : 'Best Player',
          'mvp_avatar_path': mvpType == 'USER' ? 'u1/avatar.jpg' : null,
        };

    test('carries its score', () {
      final m = completedMatchFromRow(matchRow(), avatarUrl: fakeAvatar);

      expect(m.hasResult, isTrue);
      expect(m.teamAScore, 3);
      expect(m.teamBScore, 2);
    });

    test('a match played but not yet written up has no score, not a zero one',
        () {
      final m = completedMatchFromRow(
          matchRow(hasResult: false, a: null, b: null, mvpType: null));

      expect(m.hasResult, isFalse);
      expect(m.teamAScore, isNull,
          reason: '0-0 is a result somebody recorded; this is not');
      expect(m.mvp, isNull);
    });

    test('an MVP is optional and absent when none was named', () {
      final m = completedMatchFromRow(matchRow(mvpType: null));
      expect(m.mvp, isNull);
    });

    test('an MVP may be a registered player', () {
      final m = completedMatchFromRow(matchRow(), avatarUrl: fakeAvatar);

      expect(m.mvp!.type, ParticipantType.user);
      expect(m.mvp!.userId, 'u1');
      expect(m.mvp!.opensProfile, isTrue);
    });

    test('an MVP may be a professional guest, who still opens nothing', () {
      final m = completedMatchFromRow(matchRow(mvpType: 'PROFESSIONAL'));

      expect(m.mvp!.type, ParticipantType.professionalGuest);
      expect(m.mvp!.guestId, 'g1');
      expect(m.mvp!.opensProfile, isFalse);
    });

    test('a historical match is football like any other', () {
      final m = completedMatchFromRow(matchRow(historical: true));
      expect(m.isHistorical, isTrue);
      expect(m.hasResult, isTrue);
    });

    test('the headline is the title, or the location when there is none', () {
      expect(completedMatchFromRow(matchRow()).displayName, 'Friday night');
      expect(completedMatchFromRow(matchRow(title: null)).displayName,
          'Muscat pitch');
    });

    test('carries nothing private, even when the row does', () {
      // The row below is wider than anything `v_football_completed_matches` can
      // send: none of these five columns is on it. The point is that the model
      // has nowhere to put them, which is a compile-time fact rather than a
      // value this test could read back.
      final m = completedMatchFromRow({
        ...matchRow(),
        'join_code': '4213',
        'phone': '+96890123456',
        'email': 'someone@example.com',
        'date_of_birth': '1994-06-15',
        'created_by': 'u9',
        'recorded_by': 'u9',
      });

      expect(m.matchId, 'm1');
      expect(m.communityName, 'Al Shamal');
    });
  });

  group('the stored lineup can be put back together', () {
    List<LineupSlot> lineup() => [
          lineupSlotFromRow({
            ...participantRow(),
            'match_id': 'm1',
            'team': 'A',
            'assigned_position': 'MID',
            'is_out_of_position': false,
            'goals': 2,
            'is_mvp': true,
          }),
          lineupSlotFromRow({
            ...participantRow(
                type: 'PROFESSIONAL',
                userId: null,
                guestId: 'g1',
                name: 'Guest Striker'),
            'match_id': 'm1',
            'team': 'B',
            'assigned_position': null,
            'is_out_of_position': false,
            'goals': 1,
            'is_mvp': false,
          }),
        ];

    test('each slot knows its side, position, goals and MVP flag', () {
      final slots = lineup();

      expect(slots.first.team, FootballTeam.a);
      expect(slots.first.assignedPosition, 'MID');
      expect(slots.first.goals, 2);
      expect(slots.first.isMvp, isTrue);
      expect(slots.last.team, FootballTeam.b);
      expect(slots.last.assignedPosition, isNull,
          reason: 'a guest position is nullable — migration 0051');
    });

    test('goals resolve to the identity that scored them', () {
      final slots = lineup();

      final scorers = {
        for (final s in slots)
          if (s.goals > 0) s.participant.displayName: s.goals,
      };
      expect(scorers, {'Salim Al Harthy': 2, 'Guest Striker': 1});
      expect(scorers.values.reduce((a, b) => a + b), 3,
          reason: 'the goals add up to a score the match could have had');
    });

    test('the repository splits it into two sides without a second source', () {
      final detail = CompletedMatchDetail(
        match: completedMatchFromRow({
          'match_id': 'm1',
          'community_id': 'c1',
          'community_name': 'Al Shamal',
          'title': 't',
          'location': 'l',
          'start_at': '2026-08-20T18:00:00Z',
          'end_at': '2026-08-20T20:00:00Z',
          'is_historical': false,
          'has_result': true,
          'team_a_score': 2,
          'team_b_score': 1,
          'mvp_participant_type': null,
        }),
        roster: const [],
        lineup: lineup(),
      );

      expect(detail.teamA, hasLength(1));
      expect(detail.teamB, hasLength(1));
      expect(detail.teamA.single.participant.userId, 'u1');
      expect(detail.teamB.single.participant.guestId, 'g1');
    });
  });

  group('a roster keeps the order it was saved in', () {
    test('status and position are read as stored', () {
      final entry = matchRosterEntryFromRow({
        ...participantRow(),
        'match_id': 'm1',
        'status': 'reserve',
        'roster_position': 7,
      });

      expect(entry.status, ParticipationStatus.reserve);
      expect(entry.rosterPosition, 7);
    });

    test('an unrecognised status reads as the reserve queue', () {
      final entry = matchRosterEntryFromRow({
        ...participantRow(),
        'match_id': 'm1',
        'status': 'something',
        'roster_position': 1,
      });

      expect(entry.status, ParticipationStatus.reserve);
    });
  });

  group('statistics are the approved football measures and no more', () {
    test('a community record reports what the dashboard already counts', () {
      final s = communityFootballStatsFromRow(const {
        'community_id': 'c1',
        'community_name': 'Al Shamal',
        'completed_matches': 14,
        'players': 33,
        'goals': 91,
        'mvp_count': 12,
      });

      expect(s.completedMatches, 14);
      expect(s.players, 33);
      expect(s.goals, 91);
      expect(s.mvpCount, 12);
    });

    test('a community player row carries the hardened football contract', () {
      final p = communityPlayerStatsFromRow({
        'community_id': 'c1',
        'user_id': 'u1',
        'display_name': 'Salim Al Harthy',
        'avatar_path': 'u1/avatar.jpg',
        'primary_position': 'MID',
        'secondary_position': 'FWD',
        'overall_rating': '6.40',
        'matches_played': 12,
        'wins': 7,
        'draws': 2,
        'losses': 3,
        'goals': 9,
        'mvp_count': 2,
      }, avatarUrl: fakeAvatar);

      // Exactly the columns `player_profile` was hardened to, minus is_self:
      // identity, positions, picture, rating and the six counters.
      expect(p.userId, 'u1');
      expect(p.displayName, 'Salim Al Harthy');
      expect(p.avatarUrl, 'https://cdn/u1/avatar.jpg');
      expect(p.primaryPosition, 'MID');
      expect(p.secondaryPosition, 'FWD');
      expect(p.overallRating, 6.4,
          reason: 'numeric(4,2) may arrive as a string');
      expect(p.matchesPlayed, 12);
      expect(p.wins, 7);
      expect(p.draws, 2);
      expect(p.losses, 3);
      expect(p.goals, 9);
      expect(p.mvpCount, 2);
    });

    test('a rating that arrives as a number reads the same as a string', () {
      final asNum = communityPlayerStatsFromRow({
        'community_id': 'c1',
        'user_id': 'u1',
        'display_name': 'x',
        'overall_rating': 7,
        'matches_played': 0,
        'wins': 0,
        'draws': 0,
        'losses': 0,
        'goals': 0,
        'mvp_count': 0,
      });
      expect(asNum.overallRating, 7.0);
    });

    // A guest has no `user_id`, and both statistics tables are keyed by one.
    // There is therefore no row a guest could occupy — and, decisively, no
    // field on the model that could hold a guest id.
    test('a community player row has nowhere to put a guest', () {
      final p = communityPlayerStatsFromRow({
        'community_id': 'c1',
        'user_id': 'u1',
        'display_name': 'Salim Al Harthy',
        'professional_guest_id': 'g1',
        'participant_type': 'PROFESSIONAL',
        'overall_rating': 6.4,
        'matches_played': 1,
        'wins': 1,
        'draws': 0,
        'losses': 0,
        'goals': 1,
        'mvp_count': 0,
      });

      expect(p.userId, 'u1',
          reason: 'the row is keyed by user; a guest id is not read');
    });
  });

  group('the repository adds no rule of its own', () {
    test('a match detail is three reads that fail together', () async {
      final adapter = _FakeFootballAdapter();
      final detail = await FootballRepository(adapter).fetchMatchDetail('m1');

      expect(adapter.calls,
          containsAll(['match:m1', 'roster:m1', 'lineup:m1']));
      expect(detail.match.matchId, 'm1');
      expect(detail.roster, hasLength(1));
      expect(detail.lineup, hasLength(1));
    });

    test('a refusal travels untouched', () async {
      final adapter = _FakeFootballAdapter(fail: true);
      await expectLater(
        FootballRepository(adapter).fetchMatchDetail('m1'),
        throwsA(isA<StateError>()),
      );
    });

    test('the completed-match read passes its scope through unchanged',
        () async {
      final adapter = _FakeFootballAdapter();
      await FootballRepository(adapter)
          .fetchCompletedMatches(communityId: 'c1', limit: 10);

      expect(adapter.calls, contains('completed:c1:10'));
    });
  });

  // ==========================================================================
  // Migration 0057 read as text: the privilege rule migration 0034 exists for.
  // ==========================================================================
  group('every view migration 0057 adds is SELECT-only to authenticated', () {
    late String sql;

    setUpAll(() {
      final file = File('../supabase/migrations/0057_public_football_data.sql');
      expect(file.existsSync(), isTrue,
          reason: 'the Cycle 2 migration must travel with the client that '
              'reads it');
      sql = file.readAsStringSync();
    });

    const views = [
      'v_football_completed_matches',
      'v_football_match_participants',
      'v_football_match_lineup',
      'v_football_community_stats',
      'v_football_community_player_stats',
    ];

    test('each view is created', () {
      for (final v in views) {
        expect(sql, contains('create or replace view public.$v'), reason: v);
      }
    });

    test('the six extra privileges are revoked by name', () {
      // Supabase grants ALL on a newly created object in `public` before a
      // migration's own grant is reached (migration 0034). These views are not
      // security_invoker, so they would inherit exactly the hole 0034 found.
      expect(sql, contains('revoke all on public.%I from anon, authenticated, public'));
      expect(
        sql,
        contains('revoke insert, update, delete, truncate, references, trigger'),
      );
      expect(sql, contains('grant select on public.%I to authenticated'));
    });

    test('no new view is granted to anon', () {
      // Cycle 2 is authenticated-only. The signed-out surface stays exactly
      // v_public_communities and v_public_upcoming_matches.
      for (final v in views) {
        expect(sql, isNot(contains('grant select on public.$v to anon')),
            reason: v);
        expect(sql, isNot(contains('to anon, authenticated;\n')),
            reason: 'no blanket anon grant belongs in this migration');
      }
    });

    test('no private column is ever selected', () {
      // The migration must not name a private column anywhere in a projection.
      // `join_code`, `phone` and the auth identifiers appear only in prose.
      for (final line in sql.split('\n')) {
        final code = line.trim();
        if (code.startsWith('--') || code.isEmpty) continue;
        for (final forbidden in [
          'join_code',
          'u.phone',
          'phone,',
          'date_of_birth',
          'recorded_by',
          'created_by',
          'owner_id',
        ]) {
          expect(code, isNot(contains(forbidden)),
              reason: 'private/administrative column in SQL: $code');
        }
      }
    });

    test('it touches no policy and revokes nothing that exists', () {
      // Additive only: Cycle 2 must not alter a Cycle 1 guarantee.
      expect(sql, isNot(contains('create policy')));
      expect(sql, isNot(contains('drop policy')));
      expect(sql, isNot(contains('alter table')));
      expect(sql, isNot(contains('revoke select on public.communities')));
      expect(sql, isNot(contains('revoke select on public.users')));
      expect(sql, isNot(contains('drop view')));
      expect(sql, isNot(contains('drop function')));
    });

    test('the two anonymous discovery views are not touched', () {
      expect(sql, isNot(contains('create or replace view public.v_public_')));
    });
  });
}

class _FakeFootballAdapter implements FootballAdapter {
  _FakeFootballAdapter({this.fail = false});

  final bool fail;
  final calls = <String>[];

  CompletedMatch _match(String id) => CompletedMatch(
        matchId: id,
        communityId: 'c1',
        communityName: 'Al Shamal',
        location: 'Muscat pitch',
        startAt: DateTime(2026, 8, 20, 18),
        endAt: DateTime(2026, 8, 20, 20),
        isHistorical: false,
        hasResult: true,
        teamAScore: 2,
        teamBScore: 1,
      );

  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) async {
    calls.add('completed:$communityId:$limit');
    return [_match('m1')];
  }

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) async {
    calls.add('match:$matchId');
    if (fail) throw StateError('refused');
    return _match(matchId);
  }

  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) async {
    calls.add('roster:$matchId');
    return [
      MatchRosterEntry(
        matchId: matchId,
        participant: const FootballParticipant(
          type: ParticipantType.user,
          displayName: 'Salim Al Harthy',
          userId: 'u1',
        ),
        status: ParticipationStatus.confirmed,
        rosterPosition: 1,
      ),
    ];
  }

  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) async {
    calls.add('lineup:$matchId');
    return [
      LineupSlot(
        matchId: matchId,
        participant: const FootballParticipant(
          type: ParticipantType.user,
          displayName: 'Salim Al Harthy',
          userId: 'u1',
        ),
        team: FootballTeam.a,
        goals: 1,
        isMvp: false,
        isOutOfPosition: false,
      ),
    ];
  }

  @override
  Future<CommunityFootballStats> fetchCommunityStats(String communityId) async {
    calls.add('stats:$communityId');
    return CommunityFootballStats(
      communityId: communityId,
      communityName: 'Al Shamal',
      completedMatches: 14,
      players: 33,
      goals: 91,
      mvpCount: 12,
    );
  }

  @override
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
    String communityId,
  ) async {
    calls.add('playerStats:$communityId');
    return const [];
  }
}
