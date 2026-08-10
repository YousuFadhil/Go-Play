@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Migration `0020_atomic_lineup_write.sql` — `replace_match_lineup`.
///
/// Replacing a stored lineup used to be a delete and then an insert, sent
/// separately. Manual Override rewrites the whole lineup on every edit, so that
/// window sat under routine adjustments: a failure between the two left the
/// match with no lineup, having destroyed one nobody asked to destroy.
///
/// What is exercised here is the function, not the operations above it. Who may
/// call it, that it replaces rather than accumulates, and — the reason it
/// exists — that a replacement the database refuses leaves the previous lineup
/// exactly as it was.
void main() {
  if (!integrationConfigured) {
    test('manual override', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Manual Override');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 3));
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  Map<String, dynamic> assignment(
    TestUser user, {
    required String team,
    required String position,
    String basis = 'PRIMARY',
  }) =>
      {
        'user_id': user.id,
        'team': team,
        'assigned_position': position,
        'assignment_basis': basis,
      };

  Future<String> replace(
    TestUser actor,
    List<Map<String, dynamic>> assignments, {
    String? onMatch,
  }) =>
      outcomeOf(() async {
        await actor.client.rpc('replace_match_lineup', params: {
          'p_match_id': onMatch ?? matchId,
          'p_assignments': assignments,
        });
      });

  Future<List<Map<String, dynamic>>> storedLineup() async {
    final rows = await owner.client
        .from('match_team_assignments')
        .select('user_id, team, assigned_position, assignment_basis')
        .eq('match_id', matchId)
        .order('user_id', ascending: true);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  group('who may replace a lineup', () {
    test('an owner may', () async {
      expect(
        await replace(owner, [
          assignment(owner, team: 'A', position: 'GK'),
          assignment(player, team: 'B', position: 'MID'),
        ]),
        'ALLOW',
      );
      expect(await storedLineup(), hasLength(2));
    });

    test('an admin may', () async {
      expect(
        await replace(admin, [assignment(player, team: 'A', position: 'MID')]),
        'ALLOW',
      );
    });

    test('a player may not', () async {
      expect(
        await replace(player, [assignment(player, team: 'A', position: 'MID')]),
        'NOT_AUTHORIZED',
      );
      expect(await storedLineup(), isEmpty);
    });

    test('an outsider may not', () async {
      expect(
        await replace(
            outsider, [assignment(outsider, team: 'A', position: 'MID')]),
        'NOT_AUTHORIZED',
      );
    });

    test('a player cannot destroy a lineup either', () async {
      await replace(owner, [assignment(player, team: 'A', position: 'MID')]);

      expect(await replace(player, const []), 'NOT_AUTHORIZED');
      expect(await storedLineup(), hasLength(1),
          reason: 'a refused clear must refuse, not quietly succeed');
    });
  });

  group('replacing rather than accumulating', () {
    test('the previous lineup is gone, not added to', () async {
      await replace(owner, [
        assignment(owner, team: 'A', position: 'GK'),
        assignment(player, team: 'B', position: 'MID'),
      ]);

      expect(
        await replace(owner, [assignment(admin, team: 'A', position: 'DEF')]),
        'ALLOW',
      );

      final stored = await storedLineup();
      expect(stored, hasLength(1));
      expect(stored.single['user_id'], admin.id);
    });

    test('an empty lineup clears it', () async {
      await replace(owner, [assignment(player, team: 'A', position: 'MID')]);

      expect(await replace(owner, const []), 'ALLOW');
      expect(await storedLineup(), isEmpty,
          reason: 'a lineup of nobody is a lineup, not a no-op');
    });

    test('the same player may move side without tripping the unique rule',
        () async {
      // The whole point of one transaction: the old row is gone before the new
      // one lands, so unique (match_id, user_id) never sees both.
      await replace(owner, [assignment(player, team: 'A', position: 'MID')]);

      expect(
        await replace(owner, [assignment(player, team: 'B', position: 'MID')]),
        'ALLOW',
      );
      expect((await storedLineup()).single['team'], 'B');
    });

    test('two players may exchange sides in one call', () async {
      await replace(owner, [
        assignment(owner, team: 'A', position: 'GK'),
        assignment(player, team: 'B', position: 'GK'),
      ]);

      // Both goalkeepers swap. Row by row this is impossible without briefly
      // putting two keepers on one side; as one replacement it is ordinary.
      expect(
        await replace(owner, [
          assignment(owner, team: 'B', position: 'GK'),
          assignment(player, team: 'A', position: 'GK'),
        ]),
        'ALLOW',
      );

      final stored = await storedLineup();
      expect(
        {for (final row in stored) row['user_id']: row['team']},
        {owner.id: 'B', player.id: 'A'},
      );
    });
  });

  group('a refused replacement changes nothing', () {
    /// The lineup every test below starts from and must still find afterwards.
    Future<void> givenALineup() async {
      await replace(owner, [
        assignment(owner, team: 'A', position: 'GK'),
        assignment(player, team: 'B', position: 'MID'),
      ]);
    }

    test('two goalkeepers on one side rolls the whole call back (BTGE-HC-6)',
        () async {
      await givenALineup();

      final result = await replace(owner, [
        assignment(owner, team: 'A', position: 'GK'),
        assignment(player, team: 'A', position: 'GK'),
      ]);

      expect(result, isNot('ALLOW'));
      final stored = await storedLineup();
      expect(stored, hasLength(2),
          reason: 'the delete must not survive the failed insert');
      expect(
        {for (final row in stored) row['user_id']: row['team']},
        {owner.id: 'A', player.id: 'B'},
      );
    });

    test('the same player twice rolls the whole call back (BTGE-HC-2)',
        () async {
      await givenALineup();

      final result = await replace(owner, [
        assignment(player, team: 'A', position: 'MID'),
        assignment(player, team: 'B', position: 'DEF'),
      ]);

      expect(result, isNot('ALLOW'));
      expect(await storedLineup(), hasLength(2));
    });

    test('a position outside the vocabulary rolls it back (BTGE-HC-5)',
        () async {
      await givenALineup();

      final result = await replace(
          owner, [assignment(player, team: 'A', position: 'SWEEPER')]);

      expect(result, isNot('ALLOW'));
      expect(await storedLineup(), hasLength(2));
    });

    test('an unauthorized call leaves the lineup intact', () async {
      await givenALineup();

      expect(await replace(player, const []), 'NOT_AUTHORIZED');
      expect(await storedLineup(), hasLength(2));
    });
  });

  group('the match is the one that was authorized', () {
    test('a lineup lands on the match named in the argument', () async {
      final other = await createMatch(owner, communityId,
          startsIn: const Duration(days: 4));

      // The payload carries no match: the function takes it from p_match_id, so
      // a row cannot be aimed somewhere else.
      expect(
        await replace(owner, [assignment(player, team: 'A', position: 'MID')],
            onMatch: other),
        'ALLOW',
      );

      expect(await storedLineup(), isEmpty,
          reason: 'the match under test was not touched');
      final rows = await owner.client
          .from('match_team_assignments')
          .select('user_id')
          .eq('match_id', other);
      expect(rows, hasLength(1));
    });
  });
}
