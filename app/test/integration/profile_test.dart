@Timeout(Duration(minutes: 5))
library;

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_profile_adapter.dart';
import 'package:go_play/infrastructure/supabase/supabase_team_adapter.dart';

import 'support.dart';

/// The profile path against a real project.
///
/// This is the half of the fix the registration change cannot reach: the
/// accounts that already exist have no date of birth, the engine refuses to
/// invent one (§4.3), and this is how they supply it. Every write below goes
/// through `ProfileRepository` and `SupabaseProfileAdapter` — the path the
/// screen takes — rather than a raw table update, so what is proven is that the
/// application's own route works and not merely that the column is writable.
///
/// The profile columns this file writes belong to `player2` and `player3`.
/// `team_generation_test.dart` writes `owner` and `admin`, `btge_schema_test`
/// writes `player` and reads `outsider`, and the files run in parallel — so no
/// two of them may share a profile. Day 24 is this file's match window for the
/// same reason: a player cannot hold two overlapping matches.
void main() {
  if (!integrationConfigured) {
    test('profile', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player2;
  late TestUser player3;
  late String communityId;
  late String matchId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player2 = await signInTestUser('player2');
    player3 = await signInTestUser('player3');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Profile');
    await addMember(owner, communityId, player2);
    await addMember(owner, communityId, player3);
    matchId = await createMatch(owner, communityId,
        startsIn: const Duration(days: 24), startingPlayers: 4);
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    // The six accounts are permanent fixtures: leave their profiles as found.
    for (final user in [player2, player3]) {
      await user.client.from('users').update({
        'date_of_birth': null,
        'secondary_position': null,
        'primary_position': 'MID',
      }).eq('id', user.id);
    }
  });

  /// The repository as [actor] holds it — the production path, over that
  /// account's session.
  ProfileRepository profilesOf(TestUser actor) =>
      ProfileRepository(SupabaseProfileAdapter(actor.client));

  /// The rating, read straight from the row. It is not part of the profile
  /// model, so this is the only way to see what the database holds.
  Future<double> ratingOf(TestUser user) async {
    final row = await user.client
        .from('users')
        .select('overall_rating')
        .eq('id', user.id)
        .single();
    return double.parse('${row['overall_rating']}');
  }

  Future<void> register(TestUser user) async {
    await user.client.rpc('register_for_match', params: {'p_match_id': matchId});
  }

  /// The domain model the team repository reads a match's community and
  /// kick-off from.
  Future<Match> matchModel() async {
    final row = await owner.client
        .from('matches')
        .select('id, community_id, start_at, end_at')
        .eq('id', matchId)
        .single();
    return Match(
      id: row['id'] as String,
      communityId: row['community_id'] as String,
      createdBy: owner.id,
      location: 'ITest pitch',
      startAt: DateTime.parse(row['start_at'] as String).toLocal(),
      endAt: DateTime.parse(row['end_at'] as String).toLocal(),
      startingPlayers: 4,
      maxRegistration: 10,
      status: MatchStatus.open,
    );
  }

  group('completing an existing profile', () {
    test('the three inputs are stored and read back', () async {
      final profiles = profilesOf(player2);

      final before = await profiles.fetchMyProfile();
      expect(before.dateOfBirth, isNull,
          reason: 'this is what the existing accounts look like, and nothing '
              'filled it in for them');
      expect(before.isComplete, isFalse);

      await profiles.saveMyProfile(
        dateOfBirth: DateTime(1995, 4, 17),
        primaryPosition: PlayerPosition.gk,
        secondaryPosition: PlayerPosition.def,
      );

      final after = await profiles.fetchMyProfile();
      expect(after.dateOfBirth, DateTime(1995, 4, 17));
      expect(after.primaryPosition, PlayerPosition.gk);
      expect(after.secondaryPosition, PlayerPosition.def);
      expect(after.isComplete, isTrue);
    });

    test('a secondary position can be removed once set', () async {
      final profiles = profilesOf(player2);
      await profiles.saveMyProfile(
        dateOfBirth: DateTime(1990, 1, 2),
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: PlayerPosition.fwd,
      );
      expect((await profiles.fetchMyProfile()).secondaryPosition,
          PlayerPosition.fwd);

      await profiles.saveMyProfile(
        dateOfBirth: DateTime(1990, 1, 2),
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: null,
      );

      expect((await profiles.fetchMyProfile()).secondaryPosition, isNull,
          reason: 'removing one stores the absence, not a NONE value');
    });

    test('the date of birth is stored as a date, with no time of day',
        () async {
      await profilesOf(player2).saveMyProfile(
        dateOfBirth: DateTime(1995, 4, 17, 23, 30),
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: null,
      );

      final row = await player2.client
          .from('users')
          .select('date_of_birth')
          .eq('id', player2.id)
          .single();
      expect(row['date_of_birth'], '1995-04-17',
          reason: 'a birthday sent as an instant lands on the wrong day from '
              'east of Greenwich');
    });

    test('the rating is left to the database, at the approved 5.0 (OP-1)',
        () async {
      expect(await ratingOf(player2), 5.0);

      await profilesOf(player2).saveMyProfile(
        dateOfBirth: DateTime(1995, 4, 17),
        primaryPosition: PlayerPosition.fwd,
        secondaryPosition: PlayerPosition.mid,
      );

      expect(await ratingOf(player2), 5.0,
          reason: 'the profile path carries no rating, so a save cannot move '
              'it');
    });

    test('a player writes their own profile and nobody else\'s', () async {
      // The boundary is `users_update_own_profile`, unchanged since migration
      // 0001. A write aimed at another row matches nothing under RLS.
      final before = await profilesOf(player3).fetchMyProfile();

      await player2.client
          .from('users')
          .update({'date_of_birth': '1980-01-01'}).eq('id', player3.id);

      final after = await profilesOf(player3).fetchMyProfile();
      expect(after.dateOfBirth, before.dateOfBirth);
      expect(after.dateOfBirth, isNull);
    });
  });

  group('what team generation then reads', () {
    test('an incomplete profile is refused, and completing it is enough',
        () async {
      await register(player2);
      await register(player3);
      final match = await matchModel();
      final teams = TeamRepository(SupabaseTeamAdapter(player2.client));

      // Neither has a date of birth yet: §4.3 rejects the missing input rather
      // than substituting one.
      await expectLater(
        teams.fetchGenerationInputs(match, historyLookback: null),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.missingPlayerInputs)),
      );
      expect(
        [for (final p in await teams.fetchPlayersMissingInputs(matchId)) p.userId],
        unorderedEquals([player2.id, player3.id]),
      );

      // The same completion the screen performs, through the same repository.
      await profilesOf(player2).saveMyProfile(
        dateOfBirth: DateTime(1995, 4, 17),
        primaryPosition: PlayerPosition.gk,
        secondaryPosition: PlayerPosition.def,
      );
      await profilesOf(player3).saveMyProfile(
        dateOfBirth: DateTime(1990, 1, 2),
        primaryPosition: PlayerPosition.fwd,
        secondaryPosition: null,
      );

      expect(await teams.fetchPlayersMissingInputs(matchId), isEmpty);

      final inputs =
          await teams.fetchGenerationInputs(match, historyLookback: null);
      final byId = {for (final p in inputs.players) p.id: p};

      expect(byId.keys, unorderedEquals([player2.id, player3.id]));
      expect(byId[player2.id]!.dateOfBirth, DateTime(1995, 4, 17));
      expect(byId[player2.id]!.primaryPosition, Position.gk);
      expect(byId[player2.id]!.secondaryPosition, Position.def);
      expect(byId[player2.id]!.overallRating, 5.0);
      expect(byId[player3.id]!.dateOfBirth, DateTime(1990, 1, 2));
      expect(byId[player3.id]!.primaryPosition, Position.fwd);
      expect(byId[player3.id]!.secondaryPosition, isNull,
          reason: 'a missing secondary is ordinary input (BTGE-SC-6)');
      expect(inputs.settings.matchDate, match.startAt);
    });

    test('a profile saved through the application is visible to generation '
        'immediately', () async {
      await register(player2);
      await profilesOf(player2).saveMyProfile(
        dateOfBirth: DateTime(2000, 6, 30),
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: PlayerPosition.def,
      );

      final roster = await SupabaseTeamAdapter(player2.client)
          .fetchConfirmedPlayerInputs(matchId);

      expect(roster.single.userId, player2.id);
      expect(roster.single.dateOfBirth, DateTime(2000, 6, 30));
      expect(roster.single.primaryPosition, Position.mid);
      expect(roster.single.secondaryPosition, Position.def);
      expect(roster.single.hasEveryRequiredInput, isTrue);
    });
  });
}
