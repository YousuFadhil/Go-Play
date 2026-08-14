@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/infrastructure/supabase/supabase_profile_adapter.dart';

import 'support.dart';

/// Profile visibility and age visibility, against a real project.
///
/// These are server rules, so this is where they are actually proved. A widget
/// test can show that the application asks through the authorized path and words
/// a refusal; only a live `player_profile` call can show that the refusal
/// happens at all, and that a hidden date of birth never leaves the database.
///
/// **`outsider` is the subject of every test below**, and deliberately: it is
/// the one permanent account whose profile columns no other file writes, so the
/// visibility settings this file changes cannot collide with a parallel run. The
/// viewers are `owner` (who shares a community with it, when a test says so) and
/// `player` (who never does). Teardown puts the two columns back to the defaults
/// the column carries, so a run leaves the account as it found it.
void main() {
  if (!integrationConfigured) {
    test('profile visibility', () {}, skip: skipReason);
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

  Future<void> setPrivacy(
    TestUser user, {
    required ProfileVisibility visibility,
    required bool ageVisible,
  }) =>
      repositoryFor(user).saveMyPrivacy(
        ProfilePrivacy(visibility: visibility, ageVisible: ageVisible),
      );

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');

    // A date of birth to derive an age from. `outsider` may or may not have one
    // depending on what has run before, so this file supplies its own.
    await repositoryFor(outsider).saveMyProfile(
      dateOfBirth: DateTime(1994, 6, 15),
      primaryPosition:
          (await repositoryFor(outsider).fetchMyProfile()).primaryPosition,
      secondaryPosition: null,
    );
  });

  setUp(() async {
    communityId = null;
    await setPrivacy(
      outsider,
      visibility: ProfileVisibility.everyone,
      ageVisible: true,
    );
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
    await setPrivacy(
      outsider,
      visibility: ProfileVisibility.everyone,
      ageVisible: true,
    );
  });

  /// Puts `owner` and `outsider` in one community, which is what
  /// `shares_active_community` looks for.
  Future<void> shareACommunity() async {
    communityId = await createCommunity(owner, 'ITest Visibility');
    await addMember(owner, communityId!, outsider);
  }

  group('what the column defaults are', () {
    test('a profile is visible to everyone, with an age on it', () async {
      // Read back through the owner's own profile, which is where the two
      // preferences live. This is the state `setUp` restores, and it is the
      // state migration 0043 gives every account that predates it.
      final profile = await repositoryFor(outsider).fetchMyProfile();

      expect(profile.privacy.visibility, ProfileVisibility.everyone);
      expect(profile.privacy.ageVisible, isTrue);
    });
  });

  group('visibility EVERYONE', () {
    test('a player who shares no community may open the profile', () async {
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
  });

  group('visibility COMMUNITY_MEMBERS', () {
    test('a player who shares no community is refused', () async {
      await setPrivacy(
        outsider,
        visibility: ProfileVisibility.communityMembersOnly,
        ageVisible: true,
      );

      await expectLater(
        repositoryFor(player).fetchPlayerProfile(outsider.id),
        throwsA(isA<AuthorizationFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.profileNotVisible,
        )),
      );
    });

    test('a player who shares an active community may still open it', () async {
      await shareACommunity();
      await setPrivacy(
        outsider,
        visibility: ProfileVisibility.communityMembersOnly,
        ageVisible: true,
      );

      final view = await repositoryFor(owner).fetchPlayerProfile(outsider.id);

      expect(view.fullName, outsider.name);
    });

    test('the owner always opens their own', () async {
      await setPrivacy(
        outsider,
        visibility: ProfileVisibility.communityMembersOnly,
        ageVisible: true,
      );

      final view =
          await repositoryFor(outsider).fetchPlayerProfile(outsider.id);

      expect(view.isSelf, isTrue);
      expect(view.fullName, outsider.name);
    });
  });

  group('age visibility', () {
    test('a visible age arrives as the date it is derived from', () async {
      final view = await repositoryFor(player).fetchPlayerProfile(outsider.id);

      expect(view.dateOfBirth, isNotNull);
      expect(view.age, isNotNull);
    });

    test('a hidden age does not leave the database', () async {
      await setPrivacy(
        outsider,
        visibility: ProfileVisibility.everyone,
        ageVisible: false,
      );

      final view = await repositoryFor(player).fetchPlayerProfile(outsider.id);

      // The rest of the profile is unaffected: hiding an age is not hiding a
      // profile.
      expect(view.fullName, outsider.name);
      expect(view.dateOfBirth, isNull,
          reason: 'the value is withheld at the source, not by the client');
      expect(view.age, isNull);
    });

    test('the owner still receives their own hidden age', () async {
      await setPrivacy(
        outsider,
        visibility: ProfileVisibility.everyone,
        ageVisible: false,
      );

      final view =
          await repositoryFor(outsider).fetchPlayerProfile(outsider.id);

      expect(view.dateOfBirth, isNotNull);
      expect(view.age, isNotNull);
    });
  });

  group('what a profile never carries', () {
    test('no phone number, email or auth identifier is returned', () async {
      // The function returns a fixed column list. Asked directly, so the
      // assertion is about what the *database* sends and not about what the
      // model happens to have room for.
      final rows = await player.client.rpc(
        'player_profile',
        params: {'p_user_id': outsider.id},
      ) as List<dynamic>;

      expect(rows, hasLength(1));
      final row = rows.first as Map<String, dynamic>;
      expect(row.containsKey('phone'), isFalse);
      expect(row.containsKey('email'), isFalse);
      expect(row.keys, isNot(contains('id')));
      expect(row['user_id'], outsider.id);
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
}
