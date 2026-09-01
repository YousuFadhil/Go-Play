@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_profile_adapter.dart';

import 'support.dart';

/// The football-profile boundary, against a real project.
///
/// This file used to prove the `COMMUNITY_MEMBERS` visibility rule and the age
/// setting. Migration `0055` retired both: a football profile is football data
/// and is readable by every signed-in player, and a date of birth no longer
/// leaves the database for anybody but its owner — so there is no age
/// disclosure left for a setting to govern. What replaces those tests is the
/// rule that took their place, proved the same way: on the server.
///
/// A widget test can show that the application asks through the authorized
/// path; only a live call can show what the database actually sends.
///
/// **`outsider` is the subject of every test below**, and deliberately: it is
/// the one permanent account that shares no community with anybody unless a
/// test puts it in one, which is the condition requirement 8 is about.
void main() {
  if (!integrationConfigured) {
    test('football profile boundary', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player;
  late TestUser outsider;
  String? communityId;

  /// The profile port, driven through the caller's own session — the path the
  /// screen takes, not a raw table read.
  ProfileRepository repositoryFor(TestUser user) =>
      ProfileRepository(SupabaseProfileAdapter(user.client));

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');

    // A date of birth to withhold. Without one stored, "no date of birth comes
    // back" would be true for an uninteresting reason.
    await repositoryFor(outsider).saveMyProfile(
      dateOfBirth: DateTime(1994, 6, 15),
      primaryPosition:
          (await repositoryFor(outsider).fetchMyProfile()).primaryPosition,
      secondaryPosition: null,
    );
  });

  setUp(() => communityId = null);
  tearDown(() => disposeCommunity(owner, communityId));

  /// Puts `owner` and `outsider` in one community.
  Future<void> shareACommunity() async {
    communityId = await createCommunity(owner, 'ITest Visibility');
    await addMember(owner, communityId!, outsider);
  }

  group('any signed-in player may open any active football profile', () {
    // Requirement 8: no shared community, no refusal.
    test('a player who shares no community may open it', () async {
      final view = await repositoryFor(player).fetchPlayerProfile(outsider.id);

      expect(view.userId, outsider.id);
      expect(view.fullName, outsider.name);
      expect(view.isSelf, isFalse);
    });

    test('a player who shares a community may open it too', () async {
      await shareACommunity();

      final view = await repositoryFor(owner).fetchPlayerProfile(outsider.id);

      expect(view.fullName, outsider.name);
    });

    test('the owner of the profile opens their own', () async {
      final view =
          await repositoryFor(outsider).fetchPlayerProfile(outsider.id);

      expect(view.isSelf, isTrue);
      expect(view.fullName, outsider.name);
    });

    // The setting is retired, not merely ignored by the client: whatever the
    // column says, the function no longer reads it. Written straight to the
    // column, because the application no longer has a path that writes it.
    test('a profile marked COMMUNITY_MEMBERS still opens', () async {
      await outsider.client
          .from('users')
          .update({'profile_visibility': 'COMMUNITY_MEMBERS'}).eq(
              'id', outsider.id);
      addTearDown(() async {
        await outsider.client
            .from('users')
            .update({'profile_visibility': 'EVERYONE'}).eq('id', outsider.id);
      });

      final view = await repositoryFor(player).fetchPlayerProfile(outsider.id);

      expect(view.fullName, outsider.name,
          reason: 'the retired setting grants and refuses nothing');
    });
  });

  group('what a football profile never carries', () {
    /// The function's own answer, asked directly. The assertion is about what
    /// the *database* sends, not about what the model has room for.
    Future<Map<String, dynamic>> rowFor(TestUser viewer, String userId) async {
      final rows = await viewer.client.rpc(
        'player_profile',
        params: {'p_user_id': userId},
      ) as List<dynamic>;
      expect(rows, hasLength(1));
      return rows.first as Map<String, dynamic>;
    }

    // Requirements 9, 10 and 11 in one read, because they are one column list.
    test('no phone, email, auth identifier or date of birth', () async {
      final row = await rowFor(player, outsider.id);

      expect(row.containsKey('phone'), isFalse);
      expect(row.containsKey('email'), isFalse);
      expect(row.keys, isNot(contains('id')),
          reason: 'the key is user_id; there is no auth identifier column');
      expect(row.containsKey('date_of_birth'), isFalse,
          reason: 'a birth date is account data (migration 0055)');
      expect(row.containsKey('age'), isFalse);
    });

    test('and carries exactly the approved football columns', () async {
      final row = await rowFor(player, outsider.id);

      expect(
        row.keys.toSet(),
        {
          'user_id',
          'full_name',
          'primary_position',
          'secondary_position',
          'avatar_path',
          'overall_rating',
          'matches_played',
          'wins',
          'losses',
          'draws',
          'goals',
          'mvp_count',
          'is_self',
        },
        reason: 'the column list is fixed by the function, not by the caller',
      );
    });

    test('not even for the profile owner, who reads their own elsewhere',
        () async {
      final row = await rowFor(outsider, outsider.id);

      expect(row['is_self'], isTrue);
      expect(row.containsKey('phone'), isFalse);
      expect(row.containsKey('date_of_birth'), isFalse,
          reason: 'my_profile() is the owner path, not this one');
    });
  });

  group('an id that names nobody', () {
    test('is a not-found, not a refusal', () async {
      await expectLater(
        repositoryFor(player)
            .fetchPlayerProfile('00000000-0000-0000-0000-000000000000'),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('a session is still required', () {
    test('anon cannot call player_profile at all', () async {
      expect(
        await outcomeOf(() async {
          await anonClient().rpc(
            'player_profile',
            params: {'p_user_id': outsider.id},
          );
        }),
        isNot('ALLOW'),
        reason: 'execute is revoked from anon (migration 0055)',
      );
    });
  });
}
