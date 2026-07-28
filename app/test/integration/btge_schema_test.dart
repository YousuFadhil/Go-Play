@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0018_btge_schema.sql` — the KB-D3 schema.
///
/// The engine is not wired to any of this yet, so what is exercised here is the
/// schema itself: the new profile columns, the constraints the Engineering
/// Specification requires of a stored lineup, and who may read or write one.
void main() {
  if (!integrationConfigured) {
    test('btge schema', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late TestUser outsider;
  late String communityId;
  late String matchId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest BTGE Schema');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 3));
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  Future<Map<String, dynamic>> profileOf(TestUser user) async {
    final row = await user.client
        .from('users')
        .select('overall_rating, date_of_birth, secondary_position')
        .eq('id', user.id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<String> assign(
    TestUser actor, {
    required String userId,
    required String team,
    required String position,
    String basis = 'PRIMARY',
    String? onMatch,
  }) =>
      outcomeOf(() async {
        await actor.client.from('match_team_assignments').insert({
          'match_id': onMatch ?? matchId,
          'user_id': userId,
          'team': team,
          'assigned_position': position,
          'assignment_basis': basis,
        });
      });

  group('Core Player Inputs on the profile (§4.1)', () {
    test('overall_rating exists and carries the approved OP-1 default', () async {
      final profile = await profileOf(player);
      // NUMERIC comes back as a string or a num depending on the driver; the
      // value is what matters, not the wire type.
      expect(double.parse('${profile['overall_rating']}'), 5.0);
    });

    test('date_of_birth and secondary_position start empty, not invented',
        () async {
      // Existing players have neither. §4.3 forbids the engine substituting a
      // default, and the schema must not do it on the engine's behalf either.
      final profile = await profileOf(outsider);
      expect(profile['date_of_birth'], isNull);
      expect(profile['secondary_position'], isNull);
    });

    test('a player may set their own date of birth and secondary position',
        () async {
      await player.client.from('users').update({
        'date_of_birth': '1995-04-17',
        'secondary_position': 'DEF',
      }).eq('id', player.id);

      final profile = await profileOf(player);
      expect(profile['date_of_birth'], '1995-04-17');
      expect(profile['secondary_position'], 'DEF');

      await player.client.from('users').update({
        'date_of_birth': null,
        'secondary_position': null,
      }).eq('id', player.id);
    });

    test('secondary_position is held to the position vocabulary (BTGE-HC-5)',
        () async {
      final result = await outcomeOf(() async {
        await player.client
            .from('users')
            .update({'secondary_position': 'SWEEPER'}).eq('id', player.id);
      });
      expect(result, isNot('ALLOW'));
    });

    test('a player cannot set their own rating', () async {
      // Rating adjustment is a separate business rule. Until it exists the
      // column is withheld from clients, or the balance the engine computes
      // would mean nothing.
      final result = await outcomeOf(() async {
        await player.client
            .from('users')
            .update({'overall_rating': 10.0}).eq('id', player.id);
      });
      expect(result, isNot('ALLOW'));
      expect(double.parse('${(await profileOf(player))['overall_rating']}'), 5.0);
    });
  });

  group('The played lineup (§4.2.1)', () {
    test('an admin records a lineup and a member can read it', () async {
      expect(
        await assign(admin, userId: player.id, team: 'A', position: 'MID'),
        'ALLOW',
      );
      expect(
        await assign(owner,
            userId: admin.id, team: 'B', position: 'DEF', basis: 'SECONDARY'),
        'ALLOW',
      );

      final rows = await player.client
          .from('match_team_assignments')
          .select('user_id, team, assigned_position, assignment_basis')
          .eq('match_id', matchId);
      expect(rows.length, 2);
    });

    test('a player cannot record a lineup, and an outsider cannot read one',
        () async {
      expect(
        await assign(player, userId: player.id, team: 'A', position: 'MID'),
        isNot('ALLOW'),
      );

      await assign(owner, userId: player.id, team: 'A', position: 'MID');
      final rows = await outsider.client
          .from('match_team_assignments')
          .select('user_id')
          .eq('match_id', matchId);
      expect(rows, isEmpty);
    });

    test('a player is assigned exactly once (BTGE-HC-1, BTGE-HC-2)', () async {
      expect(
        await assign(owner, userId: player.id, team: 'A', position: 'MID'),
        'ALLOW',
      );
      expect(
        await assign(owner, userId: player.id, team: 'B', position: 'DEF'),
        isNot('ALLOW'),
      );
    });

    test('no team holds two goalkeepers (BTGE-HC-6)', () async {
      expect(
        await assign(owner, userId: player.id, team: 'A', position: 'GK'),
        'ALLOW',
      );
      expect(
        await assign(owner, userId: admin.id, team: 'A', position: 'GK'),
        isNot('ALLOW'),
      );
      // One per team is the even distribution the specification asks for.
      expect(
        await assign(owner, userId: admin.id, team: 'B', position: 'GK'),
        'ALLOW',
      );
    });

    test('team, position and basis are held to their vocabularies', () async {
      expect(
        await assign(owner, userId: player.id, team: 'C', position: 'MID'),
        isNot('ALLOW'),
      );
      expect(
        await assign(owner, userId: player.id, team: 'A', position: 'STRIKER'),
        isNot('ALLOW'),
      );
      expect(
        await assign(owner,
            userId: player.id, team: 'A', position: 'MID', basis: 'GUESS'),
        isNot('ALLOW'),
      );
    });

    test('deleting the match takes its lineup with it', () async {
      await assign(owner, userId: player.id, team: 'A', position: 'MID');
      await owner.client.rpc('delete_match', params: {'p_match_id': matchId});

      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id')
          .eq('match_id', matchId);
      expect(rows, isEmpty);
    });
  });
}
