@Timeout(Duration(minutes: 5))
library;

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_team_adapter.dart';

import 'support.dart';

/// The team-generation adapter against a real project.
///
/// `btge_schema_test.dart` covers migration `0018` itself. What is exercised
/// here is the layer above it: that the schema really does yield the engine's
/// input contract (§4), that a lineup survives a round trip (§5.1), and that
/// the permissions the migration placed in RLS are what the application sees.
///
/// The profile columns this file writes belong to the `owner` and `admin`
/// accounts. `btge_schema_test.dart` writes the `player` account's and reads
/// the `outsider` account's, and the two files run in parallel — so they must
/// not share a profile.
void main() {
  if (!integrationConfigured) {
    test('team generation adapter', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser admin;
  late TestUser player;
  late String communityId;
  late String matchId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    admin = await signInTestUser('admin');
    player = await signInTestUser('player');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Team Generation');
    await addMember(owner, communityId, admin, role: 'admin');
    await addMember(owner, communityId, player);
    // Days 20 and 21 are this file's window; nothing else uses them.
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 20), startingPlayers: 2);
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    // The four accounts are permanent fixtures: leave their profiles as found.
    for (final user in [owner, admin]) {
      await user.client.from('users').update({
        'date_of_birth': null,
        'secondary_position': null,
      }).eq('id', user.id);
    }
  });

  /// The adapter as [actor] sees it — the port under test, holding that
  /// account's session.
  SupabaseTeamAdapter adapterFor(TestUser actor) =>
      SupabaseTeamAdapter(actor.client);

  Future<void> setDateOfBirth(TestUser user, String? value) => user.client
      .from('users')
      .update({'date_of_birth': value}).eq('id', user.id);

  Future<void> register(TestUser user, String id) async {
    await user.client.rpc('register_for_match', params: {'p_match_id': id});
  }

  /// The domain model the repository reads a match's community and kick-off
  /// from. Only those two fields are consulted, but the row is read back so
  /// the times are the ones the database holds.
  Future<Match> matchModel(String id) async {
    final row = await owner.client
        .from('matches')
        .select('id, community_id, start_at, end_at')
        .eq('id', id)
        .single();
    return Match(
      id: row['id'] as String,
      communityId: row['community_id'] as String,
      createdBy: owner.id,
      location: 'ITest pitch',
      startAt: DateTime.parse(row['start_at'] as String).toLocal(),
      endAt: DateTime.parse(row['end_at'] as String).toLocal(),
      startingPlayers: 2,
      maxRegistration: 8,
      status: MatchStatus.open,
    );
  }

  group('the generation set (§4.1)', () {
    test('a confirmed seat is in it and a reserve one is not', () async {
      await register(owner, matchId);
      await register(admin, matchId);
      // The third registration exceeds the two starting places.
      await register(player, matchId);

      final roster = await adapterFor(owner).fetchConfirmedPlayerInputs(matchId);

      expect([for (final p in roster) p.userId], [owner.id, admin.id],
          reason: 'a reserve holds no seat, so it is not part of the set');
    });

    test('the Core Player Inputs come from the profile, unaltered', () async {
      await owner.client.from('users').update({
        'date_of_birth': '1990-01-02',
        'secondary_position': 'DEF',
      }).eq('id', owner.id);
      await register(owner, matchId);

      final entry =
          (await adapterFor(owner).fetchConfirmedPlayerInputs(matchId)).single;

      expect(entry.userId, owner.id);
      expect(entry.dateOfBirth, DateTime(1990, 1, 2));
      expect(entry.secondaryPosition, Position.def);
      expect(entry.overallRating, 5.0,
          reason: 'the approved OP-1 default, read as a number');
      expect(entry.hasEveryRequiredInput, isTrue);
    });

    test('a profile with no date of birth reports one missing, not a made-up '
        'one (§4.3)', () async {
      await setDateOfBirth(owner, null);
      await register(owner, matchId);
      final match = await matchModel(matchId);
      final repository = TeamRepository(adapterFor(owner));

      expect(
        (await adapterFor(owner).fetchConfirmedPlayerInputs(matchId))
            .single
            .dateOfBirth,
        isNull,
      );
      await expectLater(
        repository.fetchGenerationInputs(match, historyLookback: null),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.missingPlayerInputs)),
      );
      expect([for (final p in await repository.fetchPlayersMissingInputs(matchId)) p.userId],
          [owner.id]);

      // Finish the profile and the same request goes through.
      await setDateOfBirth(owner, '1990-01-02');
      final inputs =
          await repository.fetchGenerationInputs(match, historyLookback: null);
      expect(inputs.players.single.id, owner.id);
      expect(inputs.settings.matchDate, match.startAt);
      expect(inputs.history.isEmpty, isTrue);
    });
  });

  group('the stored lineup (§5.1)', () {
    List<TeamAssignment> lineup() => [
          TeamAssignment(
            userId: owner.id,
            team: TeamId.a,
            assignedPosition: Position.gk,
            basis: AssignmentBasis.primary,
          ),
          TeamAssignment(
            userId: admin.id,
            team: TeamId.b,
            assignedPosition: Position.def,
            basis: AssignmentBasis.transition,
          ),
        ];

    test('an admin writes a lineup and it reads back as it was written',
        () async {
      await adapterFor(admin).saveLineup(matchId, lineup());

      final stored = await adapterFor(player).fetchLineup(matchId);

      expect(stored, hasLength(2));
      final byId = {for (final a in stored) a.userId: a};
      expect(byId[owner.id]!.team, TeamId.a);
      expect(byId[owner.id]!.assignedPosition, Position.gk);
      expect(byId[owner.id]!.basis, AssignmentBasis.primary);
      expect(byId[owner.id]!.outOfPosition, isFalse);
      expect(byId[admin.id]!.team, TeamId.b);
      expect(byId[admin.id]!.outOfPosition, isTrue,
          reason: 'a transition is out of position, derived not stored');
    });

    test('saving again replaces the lineup rather than adding to it', () async {
      await adapterFor(owner).saveLineup(matchId, lineup());
      await adapterFor(owner).saveLineup(matchId, [
        TeamAssignment(
          userId: player.id,
          team: TeamId.a,
          assignedPosition: Position.mid,
          basis: AssignmentBasis.primary,
        ),
      ]);

      final stored = await adapterFor(owner).fetchLineup(matchId);

      expect([for (final a in stored) a.userId], [player.id],
          reason: 'a shrunken roster must not leave a stale row behind');
    });

    test('an empty lineup clears what was stored', () async {
      await adapterFor(owner).saveLineup(matchId, lineup());
      await adapterFor(owner).saveLineup(matchId, const []);

      expect(await adapterFor(owner).fetchLineup(matchId), isEmpty);
    });

    test('a player cannot write a lineup, and cannot destroy one either',
        () async {
      await adapterFor(owner).saveLineup(matchId, lineup());

      await expectLater(
        adapterFor(player).saveLineup(matchId, const []),
        throwsA(isA<AuthorizationFailure>()),
      );
      expect(await adapterFor(owner).fetchLineup(matchId), hasLength(2),
          reason: 'the refused delete must not have taken the lineup with it');
    });
  });

  group('the played lineups Diversity may read (§4.2.1)', () {
    late String pastMatchId;

    setUp(() async {
      pastMatchId = await createMatch(owner, communityId,
          startsIn: const Duration(days: -21));
      await adapterFor(owner).saveLineup(pastMatchId, [
        TeamAssignment(
          userId: owner.id,
          team: TeamId.a,
          assignedPosition: Position.mid,
          basis: AssignmentBasis.primary,
        ),
        TeamAssignment(
          userId: admin.id,
          team: TeamId.a,
          assignedPosition: Position.def,
          basis: AssignmentBasis.primary,
        ),
        TeamAssignment(
          userId: player.id,
          team: TeamId.b,
          assignedPosition: Position.fwd,
          basis: AssignmentBasis.primary,
        ),
      ]);
    });

    test('a played match yields who played with whom, and nothing else',
        () async {
      final played = await adapterFor(owner).fetchPlayedLineups(
        communityId: communityId,
        excludeMatchId: matchId,
        limit: 10,
      );

      expect(played, hasLength(1));
      expect(played.single.teammatePairs().length, 1,
          reason: 'two teammates make one pair; the opponent makes none');
      expect(
        MatchHistory(played).pairsInWindow(asOf: DateTime.now(), lastNMatches: 10),
        hasLength(1),
      );
    });

    test('the match being generated is not part of its own history', () async {
      await adapterFor(owner).saveLineup(matchId, [
        TeamAssignment(
          userId: owner.id,
          team: TeamId.a,
          assignedPosition: Position.mid,
          basis: AssignmentBasis.primary,
        ),
      ]);

      final played = await adapterFor(owner).fetchPlayedLineups(
        communityId: communityId,
        excludeMatchId: pastMatchId,
        limit: 10,
      );

      expect(played, isEmpty,
          reason: 'the only other match has not been played yet');
    });

    test('a match with no stored lineup takes up none of the window',
        () async {
      // A more recent match that nobody generated teams for. A window of one
      // must still reach the match that has a lineup, or the window would
      // count matches instead of lineups.
      await createMatch(owner, communityId,
          startsIn: const Duration(days: -20, hours: -12));

      final played = await adapterFor(owner).fetchPlayedLineups(
        communityId: communityId,
        excludeMatchId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        limit: 1,
      );

      expect(played, hasLength(1));
      expect(played.single.teams.length, 2);
    });
  });
}
