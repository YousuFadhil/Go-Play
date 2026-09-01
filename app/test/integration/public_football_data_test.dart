@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_football_adapter.dart';

import 'support.dart';

/// The Cycle 2 football boundary, proved where it is enforced.
///
/// **Requires `0057_public_football_data.sql` to be applied.** Every assertion
/// below is a live call, and it has to be: a widget test can show that the
/// client asks the right relation, but only the server can show that a caller
/// in *no* community gets an answer — and that a caller with no session gets
/// none. Cycle 2's whole claim is about who the database answers.
///
/// `outsider` is the subject throughout. It is the one permanent account that
/// belongs to no community unless a test puts it in one, which is exactly the
/// condition "no membership required" is about. Nothing here creates, deletes or
/// modifies a community, a match, a registration or a result: the suite reads
/// football history that other tests have already produced, and skips rather
/// than fabricating it.
void main() {
  if (!integrationConfigured) {
    test('public football data', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player;
  late TestUser outsider;

  FootballRepository footballFor(TestUser user) =>
      FootballRepository(SupabaseFootballAdapter(user.client));

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  /// The Cycle 2 relations, named once. Every "anon sees nothing" and
  /// "SELECT-only" assertion iterates this list, so a view added later without
  /// its privileges is caught by the same tests.
  const cycle2Views = [
    'v_football_completed_matches',
    'v_football_match_participants',
    'v_football_match_lineup',
    'v_football_community_stats',
    'v_football_community_player_stats',
  ];

  // ==========================================================================
  // Access: authenticated only, membership never required
  // ==========================================================================
  group('anon gets none of it', () {
    for (final view in cycle2Views) {
      test('anon cannot read $view', () async {
        expect(
          await outcomeOf(() async {
            await anonClient().from(view).select('*').limit(1);
          }),
          isNot('ALLOW'),
          reason: 'Cycle 2 publishes football history to accounts only',
        );
      });
    }
  });

  group('a signed-in caller reads football history without membership', () {
    test('a non-member reads completed matches across communities', () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();

      expect(matches, isNotEmpty,
          reason: 'the outsider is in no community and must still see '
              'football that has been played');
      expect(matches.map((m) => m.communityId).toSet(), isNotEmpty);
    });

    test('an ordinary Player reads the same set', () async {
      final asOutsider = await footballFor(outsider).fetchCompletedMatches();
      final asPlayer = await footballFor(player).fetchCompletedMatches();

      expect(asPlayer.map((m) => m.matchId).toSet(),
          asOutsider.map((m) => m.matchId).toSet(),
          reason: 'reading football activity does not depend on membership');
    });

    test('an owner sees no more football history than an outsider', () async {
      final asOwner = await footballFor(owner).fetchCompletedMatches();
      final asOutsider = await footballFor(outsider).fetchCompletedMatches();

      expect(asOwner.map((m) => m.matchId).toSet(),
          asOutsider.map((m) => m.matchId).toSet(),
          reason: 'a role grants management, not extra football visibility');
    });

    test('reading football confers no participation or administration',
        () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final communityId = matches.first.communityId;

      // The member-only paths must still refuse the same caller.
      expect(
        await outcomeOf(() async {
          await outsider.client.rpc('community_join_code',
              params: {'p_community_id': communityId});
        }),
        isNot('ALLOW'),
        reason: 'Cycle 1 join-code administration is untouched by Cycle 2',
      );
      expect(
        await outsider.client
            .from('match_registrations')
            .select('id')
            .eq('match_id', matches.first.matchId),
        isEmpty,
        reason: 'the base tables are still membership-gated',
      );
    });
  });

  // ==========================================================================
  // Privacy: the column lists are the whole of what is sent
  // ==========================================================================
  group('no private or administrative column is ever sent', () {
    const forbidden = [
      'join_code',
      'phone',
      'email',
      'date_of_birth',
      'age_visible',
      'profile_visibility',
      'created_by',
      'recorded_by',
      'owner_id',
      'password',
    ];

    for (final view in cycle2Views) {
      test('$view carries none of them', () async {
        final rows = await outsider.client.from(view).select('*').limit(1);
        if (rows.isEmpty) return; // nothing recorded yet; nothing to leak
        final keys = (rows.first as Map<String, dynamic>).keys.toSet();
        for (final f in forbidden) {
          expect(keys, isNot(contains(f)), reason: '$view exposes $f');
        }
      });
    }

    test('a football profile is still the hardened 13-column contract',
        () async {
      final rows = await outsider.client.rpc(
        'player_profile',
        params: {'p_user_id': owner.id},
      ) as List<dynamic>;

      expect(rows, hasLength(1));
      final row = rows.first as Map<String, dynamic>;
      expect(row.keys.toSet(), {
        'user_id', 'full_name', 'primary_position', 'secondary_position',
        'avatar_path', 'overall_rating', 'matches_played', 'wins', 'losses',
        'draws', 'goals', 'mvp_count', 'is_self',
      }, reason: 'Cycle 2 reuses this contract rather than competing with it');
    });
  });

  // ==========================================================================
  // Football content
  // ==========================================================================
  group('what a completed match carries', () {
    test('a recorded match has a score; an unrecorded one has none', () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();

      for (final m in matches) {
        if (m.hasResult) {
          expect(m.teamAScore, isNotNull, reason: m.matchId);
          expect(m.teamBScore, isNotNull, reason: m.matchId);
        } else {
          expect(m.teamAScore, isNull, reason: m.matchId);
        }
      }
      expect(matches.where((m) => m.hasResult), isNotEmpty,
          reason: 'at least one recorded result is expected in the fixture set');
    });

    test('an MVP is optional and, where present, names a participant',
        () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final withMvp = matches.where((m) => m.mvp != null);

      for (final m in withMvp) {
        final detail = await footballFor(outsider).fetchMatchDetail(m.matchId);
        final ids = {
          for (final s in detail.lineup)
            s.participant.userId ?? s.participant.guestId,
        };
        expect(ids, contains(m.mvp!.userId ?? m.mvp!.guestId),
            reason: 'the MVP of ${m.matchId} must have played in it');
      }
    });

    test('a saved lineup reconstructs into two sides with goals', () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final withLineup = <CompletedMatchDetail>[];
      for (final m in matches.take(5)) {
        final d = await footballFor(outsider).fetchMatchDetail(m.matchId);
        if (d.lineup.isNotEmpty) withLineup.add(d);
      }

      expect(withLineup, isNotEmpty,
          reason: 'at least one completed match should have a stored lineup');

      final d = withLineup.first;
      expect(d.teamA, isNotEmpty);
      expect(d.teamB, isNotEmpty);
      expect(d.teamA.length + d.teamB.length, d.lineup.length,
          reason: 'every slot belongs to exactly one side');

      if (d.match.hasResult) {
        final goals = d.lineup.fold<int>(0, (sum, s) => sum + s.goals);
        expect(goals, d.match.teamAScore! + d.match.teamBScore!,
            reason: 'recorded goals add up to the recorded score');
      }
    });

    test('a roster comes back in the order it was saved', () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      for (final m in matches.take(3)) {
        final d = await footballFor(outsider).fetchMatchDetail(m.matchId);
        if (d.roster.isEmpty) continue;
        final positions = [for (final e in d.roster) e.rosterPosition];
        final sorted = [...positions]..sort();
        expect(positions, sorted, reason: 'roster order is not recomputed');
      }
    });
  });

  // ==========================================================================
  // Professional Guests stay match-scoped
  // ==========================================================================
  group('a professional guest is football, not a player', () {
    test('a guest may appear in a lineup, with no account behind them',
        () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final guests = <FootballParticipant>[];
      for (final m in matches) {
        final d = await footballFor(outsider).fetchMatchDetail(m.matchId);
        guests.addAll([
          for (final s in d.lineup)
            if (s.participant.type == ParticipantType.professionalGuest)
              s.participant,
        ]);
      }

      if (guests.isEmpty) {
        markTestSkipped('no professional guest in the fixture data');
        return;
      }
      for (final g in guests) {
        expect(g.guestId, isNotNull);
        expect(g.userId, isNull, reason: 'a guest has no account');
        expect(g.displayName, isNotEmpty);
        expect(g.opensProfile, isFalse);
        expect(g.overallRating, isNull,
            reason: 'no Core Player Input exists for somebody with no profile');
      }
    });

    test('a guest never enters persistent player statistics', () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final guestIds = <String>{};
      for (final m in matches) {
        final d = await footballFor(outsider).fetchMatchDetail(m.matchId);
        for (final s in d.lineup) {
          if (s.participant.guestId != null) guestIds.add(s.participant.guestId!);
        }
      }
      if (guestIds.isEmpty) {
        markTestSkipped('no professional guest in the fixture data');
        return;
      }

      // The statistics relations are keyed by user. A guest id can never be one.
      final rows = await outsider.client
          .from('v_football_community_player_stats')
          .select('user_id');
      final statUserIds = {
        for (final r in rows) (r as Map<String, dynamic>)['user_id'] as String,
      };
      expect(statUserIds.intersection(guestIds), isEmpty,
          reason: 'a guest must not rank as if they were a registered player');
    });
  });

  // ==========================================================================
  // Community aggregates
  // ==========================================================================
  group('community football statistics', () {
    test('a non-member reads them, and they count completed matches',
        () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final communityId = matches.first.communityId;

      final stats = await footballFor(outsider).fetchCommunityStats(communityId);
      final counted =
          matches.where((m) => m.communityId == communityId).length;

      expect(stats.communityId, communityId);
      expect(stats.completedMatches, counted,
          reason: 'the aggregate uses the same completed rule as the list');
      expect(stats.players, greaterThanOrEqualTo(0));
    });

    test('a non-member reads the per-player records a leaderboard ranks on',
        () async {
      final matches = await footballFor(outsider).fetchCompletedMatches();
      final players = await footballFor(outsider)
          .fetchCommunityPlayerStats(matches.first.communityId);

      expect(players, isNotEmpty);
      for (final p in players) {
        expect(p.userId, isNotEmpty);
        expect(p.displayName, isNotEmpty);
        expect(p.overallRating, greaterThan(0));
        expect(p.matchesPlayed, greaterThanOrEqualTo(0));
      }
    });
  });

  // ==========================================================================
  // Nothing that already worked stopped working
  // ==========================================================================
  group('the existing surfaces are untouched', () {
    test('anon still reads the two public discovery views', () async {
      final client = anonClient();
      expect(
        await outcomeOf(() async {
          await client.from('v_public_communities').select('id, name').limit(1);
        }),
        'ALLOW',
      );
      expect(
        await outcomeOf(() async {
          await client
              .from('v_public_upcoming_matches')
              .select('id, community_name')
              .limit(1);
        }),
        'ALLOW',
      );
    });

    test('the Cycle 1 boundary still refuses join_code and phone', () async {
      expect(
        await outcomeOf(() async {
          await player.client.from('communities').select('id, join_code');
        }),
        isNot('ALLOW'),
      );
      expect(
        await outcomeOf(() async {
          await player.client.from('users').select('id, phone');
        }),
        isNot('ALLOW'),
      );
    });

    test('a player still reads their own phone through my_profile', () async {
      final rows = await player.client.rpc('my_profile') as List<dynamic>;
      expect((rows.first as Map<String, dynamic>)['phone'], isNotNull);
    });
  });

  // ==========================================================================
  // The views are read-only
  // ==========================================================================
  group('every Cycle 2 view is SELECT-only', () {
    for (final view in cycle2Views) {
      test('$view refuses a delete from authenticated', () async {
        expect(
          await outcomeOf(() async {
            await player.client
                .from(view)
                .delete()
                .eq('community_id', '00000000-0000-0000-0000-000000000000');
          }),
          isNot('ALLOW'),
        );
      });

      test('$view refuses an insert from authenticated', () async {
        expect(
          await outcomeOf(() async {
            await player.client.from(view).insert({'community_id': 'x'});
          }),
          isNot('ALLOW'),
        );
      });
    }
  });
}
