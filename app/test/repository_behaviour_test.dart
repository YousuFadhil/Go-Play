import 'dart:typed_data';

import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/admin/admin_adapter.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';

/// What the repositories decide once the provider is out of the way (OP-6).
///
/// Each test drives a repository through a fake port, so what is asserted is
/// the product's own reasoning: which communities are offered, what a join
/// attempt means, what is normalised before it is stored, and what happens
/// when the answer cannot be obtained.
void main() {
  Community community(String id) => Community(
        id: id,
        ownerId: 'owner',
        name: 'Community $id',
        joinPolicy: JoinPolicy.open,
        joinCode: 'CODE$id',
      );

  group('CommunityRepository.joinCommunity', () {
    test('a completed join reports the community it joined', () async {
      final adapter = FakeCommunityAdapter(joinResult: 'c7');
      final outcome = await CommunityRepository(adapter).joinCommunity('c7');

      expect(outcome, isA<JoinedCommunity>());
      expect((outcome as JoinedCommunity).communityId, 'c7');
    });

    test('a community that wants its code is an outcome, not a failure',
        () async {
      final adapter = FakeCommunityAdapter(
        thrown: const ValidationFailure(FailureReason.joinCodeRequired),
      );

      expect(await CommunityRepository(adapter).joinCommunity('c1'),
          isA<NeedsJoinCode>());
    });

    test('being a member already is an outcome, not a failure', () async {
      final adapter = FakeCommunityAdapter(
        thrown: const ConflictFailure(FailureReason.alreadyMember),
      );

      expect(await CommunityRepository(adapter).joinCommunity('c1'),
          isA<AlreadyMember>());
    });

    test('a community that is gone is still a failure', () async {
      final adapter = FakeCommunityAdapter(
        thrown: const NotFoundFailure(FailureReason.communityNotFound),
      );

      expect(CommunityRepository(adapter).joinCommunity('c1'),
          throwsA(isA<NotFoundFailure>()));
    });

    test('a failure of the same type but another reason travels on', () async {
      // The reason is read to recognise an outcome, not to swallow a type.
      final repository = CommunityRepository(FakeCommunityAdapter(
        thrown: const ValidationFailure(FailureReason.invalidRole),
      ));
      expect(repository.joinCommunity('c1'), throwsA(isA<ValidationFailure>()));

      final conflicting = CommunityRepository(FakeCommunityAdapter(
        thrown: const ConflictFailure(FailureReason.alreadyOwner),
      ));
      expect(conflicting.joinCommunity('c1'), throwsA(isA<ConflictFailure>()));
    });

    test('an infrastructure failure is not turned into an outcome', () async {
      final adapter =
          FakeCommunityAdapter(thrown: const InfrastructureFailure());

      expect(CommunityRepository(adapter).joinCommunity('c1'),
          throwsA(isA<InfrastructureFailure>()));
    });
  });

  group('CommunityRepository.joinCommunityByCode', () {
    test('sends the code as stored, however it was typed', () async {
      final adapter = FakeCommunityAdapter();
      await CommunityRepository(adapter).joinCommunityByCode('  ab12cd  ');

      expect(adapter.lastCode, 'AB12CD',
          reason: 'a code read aloud and retyped must still work');
    });

    test('shares the outcomes of the other join path', () async {
      final adapter = FakeCommunityAdapter(
        thrown: const ConflictFailure(FailureReason.alreadyMember),
      );

      expect(await CommunityRepository(adapter).joinCommunityByCode('AB12CD'),
          isA<AlreadyMember>());
    });
  });

  group('CommunityRepository.fetchCommunitiesOverview', () {
    test('discover excludes what the user has already joined', () async {
      final adapter = FakeCommunityAdapter(
        mine: [community('a'), community('b')],
        all: [community('a'), community('b'), community('c')],
      );

      final overview =
          await CommunityRepository(adapter).fetchCommunitiesOverview();

      expect([for (final c in overview.mine) c.id], ['a', 'b']);
      expect([for (final c in overview.discover) c.id], ['c']);
    });

    test('a user in nothing is offered everything', () async {
      final adapter =
          FakeCommunityAdapter(all: [community('a'), community('b')]);

      final overview =
          await CommunityRepository(adapter).fetchCommunitiesOverview();

      expect(overview.mine, isEmpty);
      expect(overview.discover, hasLength(2));
    });
  });

  group('CommunityRepository.createCommunity', () {
    test('trims the name', () async {
      final adapter = FakeCommunityAdapter();
      await CommunityRepository(adapter).createCommunity(
        name: '  Friday Football  ',
        joinPolicy: JoinPolicy.open,
      );

      expect(adapter.lastName, 'Friday Football');
      expect(adapter.lastJoinPolicy, JoinPolicy.open);
    });

    test('a description of nothing is stored as no description', () async {
      final adapter = FakeCommunityAdapter();
      final repository = CommunityRepository(adapter);

      await repository.createCommunity(
          name: 'A', description: '   ', joinPolicy: JoinPolicy.open);
      expect(adapter.lastDescription, isNull);

      await repository.createCommunity(
          name: 'A', description: null, joinPolicy: JoinPolicy.open);
      expect(adapter.lastDescription, isNull);
    });

    test('a real description is kept, trimmed', () async {
      final adapter = FakeCommunityAdapter();
      await CommunityRepository(adapter).createCommunity(
        name: 'A',
        description: '  Weekly game  ',
        joinPolicy: JoinPolicy.codeRequired,
      );

      expect(adapter.lastDescription, 'Weekly game');
    });
  });

  group('AdminRepository.isSystemAdmin', () {
    test('reports what the database said', () async {
      expect(await AdminRepository(FakeAdminAdapter(isAdmin: true))
          .isSystemAdmin(), isTrue);
      expect(await AdminRepository(FakeAdminAdapter(isAdmin: false))
          .isSystemAdmin(), isFalse);
    });

    test('a question that could not be answered is answered no', () async {
      for (final failure in const <Failure>[
        AuthenticationFailure(),
        AuthorizationFailure(),
        NetworkFailure(),
        InfrastructureFailure(),
        UnknownFailure(),
      ]) {
        expect(
          await AdminRepository(FakeAdminAdapter(thrown: failure))
              .isSystemAdmin(),
          isFalse,
          reason: 'a failure must not open the door ($failure)',
        );
      }
    });
  });

  group('AuthService.fetchCurrentUserFirstName', () {
    Future<String> firstNameOf(String? fullName) =>
        AuthService(FakeAuthAdapter(fullName: fullName))
            .fetchCurrentUserFirstName();

    test('takes the first word of the stored name', () async {
      expect(await firstNameOf('Sara Al Balushi'), 'Sara');
      expect(await firstNameOf('Sara'), 'Sara');
      expect(await firstNameOf('  Sara   Al Balushi '), 'Sara');
    });

    test('has nothing to greet when there is no name', () async {
      expect(await firstNameOf(null), '');
      expect(await firstNameOf('   '), '');
    });
  });

  group('AuthService.register', () {
    final birthday = DateTime(1995, 4, 17);

    Future<void> register(
      FakeAuthAdapter adapter, {
      String email = 'player@example.com',
      String localPhone = '90123456',
      String fullName = 'Sara',
      PlayerPosition position = PlayerPosition.mid,
      DateTime? dateOfBirth,
      PlayerPosition? secondaryPosition,
    }) =>
        AuthService(adapter).register(
          email: email,
          localPhone: localPhone,
          password: 'secret',
          fullName: fullName,
          position: position,
          dateOfBirth: dateOfBirth ?? birthday,
          secondaryPosition: secondaryPosition,
        );

    test('stores the phone in its full international form', () async {
      final adapter = FakeAuthAdapter();
      await register(adapter, localPhone: '9012 3456');

      expect(adapter.lastPhone, '+96890123456');
      expect(adapter.lastPosition, PlayerPosition.mid);
    });

    test('trims the email and the name', () async {
      final adapter = FakeAuthAdapter();
      await register(adapter,
          email: '  player@example.com ',
          fullName: '  Sara  ',
          position: PlayerPosition.gk);

      expect(adapter.lastEmail, 'player@example.com');
      expect(adapter.lastFullName, 'Sara');
    });

    test('the profile §4.1 asks for reaches the adapter as it was given',
        () async {
      final adapter = FakeAuthAdapter();
      await register(adapter,
          position: PlayerPosition.gk, secondaryPosition: PlayerPosition.def);

      expect(adapter.lastDateOfBirth, birthday);
      expect(adapter.lastPosition, PlayerPosition.gk);
      expect(adapter.lastSecondaryPosition, PlayerPosition.def);
    });

    test('a player who named no secondary position registers without one',
        () async {
      final adapter = FakeAuthAdapter();
      await register(adapter);

      expect(adapter.signUpCount, 1);
      expect(adapter.lastSecondaryPosition, isNull,
          reason: 'a missing secondary is ordinary input (BTGE-SC-6), and no '
              'value stands in for it');
    });

    test('the date of birth is stored as a date, with no time of day',
        () async {
      final adapter = FakeAuthAdapter();
      await register(adapter, dateOfBirth: DateTime(1995, 4, 17, 23, 30));

      expect(adapter.lastDateOfBirth, DateTime(1995, 4, 17));
    });

    test('a secondary position that repeats the primary is refused before the '
        'adapter is reached', () async {
      final adapter = FakeAuthAdapter();

      await expectLater(
        register(adapter,
            position: PlayerPosition.mid,
            secondaryPosition: PlayerPosition.mid),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.signUpCount, 0);
    });

    test('a date of birth that has not happened yet is refused before the '
        'adapter is reached', () async {
      final adapter = FakeAuthAdapter();

      await expectLater(
        register(adapter,
            dateOfBirth: DateTime.now().add(const Duration(days: 1))),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.signUpCount, 0);
    });

    test('today is a date of birth, not a future one', () async {
      // The boundary the rule is stated at: born today is behind us.
      final adapter = FakeAuthAdapter();
      await register(adapter, dateOfBirth: DateTime.now());

      expect(adapter.signUpCount, 1);
    });

    test('sign-in trims the email too', () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter)
          .login(email: '  player@example.com ', password: 'secret');

      expect(adapter.lastEmail, 'player@example.com');
    });
  });

  group('ProfileRepository', () {
    final birthday = DateTime(1995, 4, 17);

    Future<void> save(
      FakeProfileAdapter adapter, {
      DateTime? dateOfBirth,
      PlayerPosition primary = PlayerPosition.mid,
      PlayerPosition? secondary,
    }) =>
        ProfileRepository(adapter).saveMyProfile(
          dateOfBirth: dateOfBirth ?? birthday,
          primaryPosition: primary,
          secondaryPosition: secondary,
        );

    test('reads back what is stored, missing date of birth and all', () async {
      // The nine accounts that predate the date-of-birth field look like this,
      // and §4.3 forbids the layer below inventing one for them.
      final profile = await ProfileRepository(
        FakeProfileAdapter(
          profile: const PlayerProfile(
            fullName: 'Salim Al Harthy',
            phone: '+96890123456',
            primaryPosition: PlayerPosition.fwd,
          ),
        ),
      ).fetchMyProfile();

      expect(profile.dateOfBirth, isNull);
      expect(profile.secondaryPosition, isNull);
      expect(profile.primaryPosition, PlayerPosition.fwd);
      expect(profile.isComplete, isFalse);
    });

    test('a completed profile reports itself complete', () async {
      final profile = await ProfileRepository(
        FakeProfileAdapter(
          profile: PlayerProfile(
            fullName: 'Salim Al Harthy',
            phone: '+96890123456',
            primaryPosition: PlayerPosition.gk,
            dateOfBirth: birthday,
            secondaryPosition: PlayerPosition.def,
          ),
        ),
      ).fetchMyProfile();

      expect(profile.isComplete, isTrue);
    });

    test('the three inputs reach the adapter as they were given', () async {
      final adapter = FakeProfileAdapter();
      await save(adapter,
          primary: PlayerPosition.gk, secondary: PlayerPosition.def);

      expect(adapter.writes, 1);
      expect(adapter.lastDateOfBirth, birthday);
      expect(adapter.lastPrimaryPosition, PlayerPosition.gk);
      expect(adapter.lastSecondaryPosition, PlayerPosition.def);
    });

    test('removing the secondary position writes its absence', () async {
      final adapter = FakeProfileAdapter();
      await save(adapter);

      expect(adapter.writes, 1);
      expect(adapter.lastSecondaryPosition, isNull);
    });

    test('the date of birth is stored as a date, with no time of day',
        () async {
      final adapter = FakeProfileAdapter();
      await save(adapter, dateOfBirth: DateTime(1995, 4, 17, 23, 30));

      expect(adapter.lastDateOfBirth, DateTime(1995, 4, 17));
    });

    test('a secondary position that repeats the primary is refused before the '
        'adapter is reached', () async {
      final adapter = FakeProfileAdapter();

      await expectLater(
        save(adapter, primary: PlayerPosition.mid, secondary: PlayerPosition.mid),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.writes, 0);
    });

    test('a date of birth that has not happened yet is refused before the '
        'adapter is reached', () async {
      final adapter = FakeProfileAdapter();

      await expectLater(
        save(adapter, dateOfBirth: DateTime.now().add(const Duration(days: 1))),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.writes, 0);
    });

    test('the account is written by its own call, trimmed', () async {
      final adapter = FakeProfileAdapter();
      await ProfileRepository(adapter).saveMyAccount(
        fullName: '  Salim Al Harthy  ',
        phone: '+96890123456',
      );

      expect(adapter.accountWrites, 1);
      expect(adapter.lastFullName, 'Salim Al Harthy');
      expect(adapter.lastPhone, '+96890123456');
      expect(adapter.writes, 0,
          reason: 'correcting a name never rewrites the playing inputs');
    });

    test('a name too short to identify anybody is refused before the adapter',
        () async {
      final adapter = FakeProfileAdapter();

      await expectLater(
        ProfileRepository(adapter)
            .saveMyAccount(fullName: '  a ', phone: '+96890123456'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.accountWrites, 0);
    });

    test('a picture is stored and its address handed back', () async {
      final adapter = FakeProfileAdapter();
      final url = await ProfileRepository(adapter).uploadMyAvatar(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        fileExtension: 'png',
      );

      expect(adapter.avatarUploads, 1);
      expect(adapter.lastFileExtension, 'png');
      expect(url, 'https://example.test/avatar.png');
    });

    test('removing a picture is a pass-through', () async {
      final adapter = FakeProfileAdapter();
      await ProfileRepository(adapter).removeMyAvatar();

      expect(adapter.avatarRemovals, 1);
    });
  });

  group('AuthService credentials', () {
    test('the address is trimmed and checked before the port is reached',
        () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter).changeEmail('  new@example.com ');

      expect(adapter.changedEmail, 'new@example.com');
    });

    test('the confirmation link is told to come back to the app', () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter).changeEmail('new@example.com');

      // Without a redirect the provider falls back to its configured Site URL,
      // which is a web address this project does not serve — the player
      // confirms the change and never returns to Go Play. The scheme has to
      // match the Android manifest's intent filter and the Supabase project's
      // Redirect URLs allow-list; neither is checkable from here, which is why
      // the value is stated once and asserted rather than inlined at the call.
      expect(adapter.changedRedirect, AuthService.emailChangeRedirect);
      expect(AuthService.emailChangeRedirect, 'goplay://login-callback');
    });

    test('an address that is not one is refused here', () async {
      final adapter = FakeAuthAdapter();

      await expectLater(
        AuthService(adapter).changeEmail('not-an-email'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.changedEmail, isNull);
    });

    test('changing an email to the one already held is not a change', () async {
      final adapter = FakeAuthAdapter()..email = 'player@example.com';

      await expectLater(
        AuthService(adapter).changeEmail('PLAYER@example.com'),
        throwsA(isA<ValidationFailure>()),
        // Case-insensitively: it is the same address, and the provider would
        // send a confirmation for nothing.
      );
      expect(adapter.changedEmail, isNull);
    });

    test('a password shorter than the product accepts never leaves', () async {
      final adapter = FakeAuthAdapter();

      await expectLater(
        AuthService(adapter).changePassword('short'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.changedPassword, isNull);

      await AuthService(adapter).changePassword('longenough');
      expect(adapter.changedPassword, 'longenough');
    });
  });

  group('MatchService', () {
    final start = DateTime(2026, 8, 1, 20);
    final end = DateTime(2026, 8, 1, 22);

    test('trims what the organizer typed when creating', () async {
      final adapter = FakeMatchAdapter();
      await MatchService(adapter).createMatch(
        communityId: 'c1',
        title: '  Friday Game  ',
        location: '  Al Amerat Pitch  ',
        startAt: start,
        endAt: end,
        startingPlayers: 10,
      );

      expect(adapter.lastTitle, 'Friday Game');
      expect(adapter.lastLocation, 'Al Amerat Pitch');
    });

    test('trims the location when editing', () async {
      final adapter = FakeMatchAdapter();
      await MatchService(adapter).updateMatch(
        matchId: 'm1',
        title: 'Friday Game',
        location: '  Al Amerat Pitch  ',
        startAt: start,
        endAt: end,
        startingPlayers: 10,
      );

      expect(adapter.lastLocation, 'Al Amerat Pitch');
    });
  });

  group('MemberRepository', () {
    test('forwards the role it was asked to set', () async {
      final adapter = FakeMemberAdapter();
      await MemberRepository(adapter)
          .setMemberRole('c1', 'u2', CommunityRole.admin);

      expect(adapter.lastCommunityId, 'c1');
      expect(adapter.lastUserId, 'u2');
      expect(adapter.lastRole, CommunityRole.admin);
    });
  });

  group('TeamRepository.fetchGenerationInputs', () {
    final kickOff = DateTime(2026, 8, 7, 20);
    final match = Match(
      id: 'm1',
      communityId: 'c1',
      createdBy: 'u1',
      location: 'Al Amerat Pitch',
      startAt: kickOff,
      endAt: kickOff.add(const Duration(hours: 2)),
      startingPlayers: 10,
      maxRegistration: 16,
      status: MatchStatus.open,
    );

    PlayerCoreInputs player(String id, {DateTime? dateOfBirth}) =>
        PlayerCoreInputs(
          userId: id,
          fullName: 'Player $id',
          overallRating: 6,
          primaryPosition: Position.mid,
          dateOfBirth: dateOfBirth ?? DateTime(1995, 4, 17),
        );

    test('the confirmed roster becomes the generation set', () async {
      final adapter = FakeTeamAdapter(roster: [player('u1'), player('u2')]);

      final inputs = await TeamRepository(adapter)
          .fetchGenerationInputs(match, historyLookback: null);

      expect([for (final p in inputs.players) p.id], ['u1', 'u2']);
      expect(adapter.lastMatchId, 'm1');
    });

    test('age is computed as of the match date (§4.2)', () async {
      final inputs = await TeamRepository(FakeTeamAdapter(roster: [player('u1')]))
          .fetchGenerationInputs(match, historyLookback: null);

      expect(inputs.settings.matchDate, kickOff);
      expect(inputs.players.single.ageAt(inputs.settings.matchDate), 31);
    });

    test('a player with no date of birth stops the request (§4.3)', () async {
      final adapter = FakeTeamAdapter(roster: [
        player('u1'),
        const PlayerCoreInputs(
          userId: 'u2',
          fullName: 'Ahmed',
          overallRating: 5,
          primaryPosition: Position.gk,
        ),
      ]);

      await expectLater(
        TeamRepository(adapter)
            .fetchGenerationInputs(match, historyLookback: null),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.missingPlayerInputs)),
        reason: 'the engine is never handed an invented input',
      );
    });

    test('an unset window reads no history at all (BTGE-DV-5)', () async {
      final adapter = FakeTeamAdapter(roster: [player('u1')]);

      final inputs = await TeamRepository(adapter)
          .fetchGenerationInputs(match, historyLookback: null);

      expect(inputs.history.isEmpty, isTrue);
      expect(adapter.lastLimit, isNull,
          reason: 'no window means nothing to look back over, not an error');
    });

    test('a window is passed to the port exactly as given (OP-6)', () async {
      final adapter = FakeTeamAdapter(
        roster: [player('u1')],
        played: [
          PastMatch(playedAt: DateTime(2026, 7, 31), teams: const [
            {'u1', 'u2'},
            {'u3'},
          ]),
        ],
      );

      final inputs = await TeamRepository(adapter)
          .fetchGenerationInputs(match, historyLookback: 5);

      expect(adapter.lastLimit, 5);
      expect(adapter.lastCommunityId, 'c1');
      expect(adapter.lastExcludedMatchId, 'm1',
          reason: 'the match being generated is not its own history');
      expect(inputs.history.isEmpty, isFalse);
    });

    test('a window of nothing reads nothing', () async {
      final adapter = FakeTeamAdapter(roster: [player('u1')]);

      final inputs = await TeamRepository(adapter)
          .fetchGenerationInputs(match, historyLookback: 0);

      expect(inputs.history.isEmpty, isTrue);
      expect(adapter.lastLimit, isNull);
    });
  });

  group('TeamRepository lineups', () {
    test('names the players whose profile is unfinished', () async {
      final adapter = FakeTeamAdapter(roster: [
        PlayerCoreInputs(
          userId: 'u1',
          fullName: 'Sara',
          overallRating: 6,
          primaryPosition: Position.mid,
          dateOfBirth: DateTime(1995, 4, 17),
        ),
        const PlayerCoreInputs(
          userId: 'u2',
          fullName: 'Ahmed',
          overallRating: 5,
          primaryPosition: Position.gk,
        ),
      ]);

      final missing =
          await TeamRepository(adapter).fetchPlayersMissingInputs('m1');

      expect([for (final p in missing) p.fullName], ['Ahmed']);
    });

    test('a generated result and an adjusted one take the same path', () async {
      // KB-017 and BTGE-MO-5: what is stored is what actually played, however
      // it came to be.
      final adapter = FakeTeamAdapter();
      final generated = [
        TeamAssignment.fromAssignment(const PlayerAssignment(
          playerId: 'u1',
          team: TeamId.a,
          assignedPosition: Position.gk,
          basis: AssignmentBasis.primary,
        )),
      ];

      await TeamRepository(adapter).saveLineup('m1', generated);

      expect(adapter.lastMatchId, 'm1');
      expect(adapter.savedLineup, hasLength(1));
      expect(adapter.savedLineup!.single.userId, 'u1');
      expect(adapter.savedLineup!.single.team, TeamId.a);
    });

    test('an empty lineup is stored as an empty lineup', () async {
      final adapter = FakeTeamAdapter();
      await TeamRepository(adapter).saveLineup('m1', const []);

      expect(adapter.savedLineup, isEmpty,
          reason: 'clearing a lineup is a lineup of nobody, not a no-op');
    });
  });
}

// --- Fake ports -------------------------------------------------------------
//
// Each answers from memory and records what it was handed. `thrown` stands in
// for a failure arriving from the adapter, which is how the outcome
// translation and the fail-closed rule are exercised without a database.
// Methods a test never reaches are left unimplemented on purpose: adding one
// to a port should break these fakes loudly rather than pass silently.

class FakeCommunityAdapter implements CommunityAdapter {
  FakeCommunityAdapter({
    this.mine = const [],
    this.all = const [],
    this.joinResult = 'c1',
    this.thrown,
  });

  final List<Community> mine;
  final List<Community> all;
  final String joinResult;
  final Object? thrown;

  String? lastCode;
  String? lastName;
  String? lastDescription;
  JoinPolicy? lastJoinPolicy;

  @override
  Future<List<Community>> fetchMyCommunities() async => mine;

  @override
  Future<List<Community>> fetchAllCommunities() async => all;

  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) async {
    lastName = name;
    lastDescription = description;
    lastJoinPolicy = joinPolicy;
    return 'created';
  }

  @override
  Future<String> joinCommunity(String communityId) async {
    if (thrown != null) throw thrown!;
    return joinResult;
  }

  @override
  Future<String> joinCommunityByCode(String code) async {
    lastCode = code;
    if (thrown != null) throw thrown!;
    return joinResult;
  }

  @override
  Future<Community> fetchCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> setJoinPolicy(String communityId,
          {required JoinPolicy joinPolicy}) =>
      throw UnimplementedError();

  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      throw UnimplementedError();

  @override
  Future<String> regenerateJoinCode(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunity(String communityId) =>
      throw UnimplementedError();
}

class FakeAdminAdapter implements AdminAdapter {
  FakeAdminAdapter({this.isAdmin = false, this.thrown});

  final bool isAdmin;
  final Object? thrown;

  @override
  Future<bool> isSystemAdmin() async {
    if (thrown != null) throw thrown!;
    return isAdmin;
  }

  @override
  Future<List<AdminUserSummary>> listUsers(String? search) =>
      throw UnimplementedError();

  @override
  Future<List<AdminCommunitySummary>> listCommunities(String? search) =>
      throw UnimplementedError();

  @override
  Future<List<AdminMatchSummary>> listMatches(String? search) =>
      throw UnimplementedError();

  @override
  Future<void> deleteUser(String id) => throw UnimplementedError();

  @override
  Future<void> deleteCommunity(String id) => throw UnimplementedError();

  @override
  Future<void> deleteMatch(String id) => throw UnimplementedError();
}

class FakeProfileAdapter implements ProfileAdapter {
  FakeProfileAdapter({
    this.profile = const PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    ),
  });

  final PlayerProfile profile;

  int writes = 0;
  DateTime? lastDateOfBirth;
  PlayerPosition? lastPrimaryPosition;
  PlayerPosition? lastSecondaryPosition;

  int accountWrites = 0;
  String? lastFullName;
  String? lastPhone;

  int avatarUploads = 0;
  int avatarRemovals = 0;
  String? lastFileExtension;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile;

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) async {
    writes++;
    lastDateOfBirth = dateOfBirth;
    lastPrimaryPosition = primaryPosition;
    lastSecondaryPosition = secondaryPosition;
  }

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) async {
    accountWrites++;
    lastFullName = fullName;
    lastPhone = phone;
  }

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    avatarUploads++;
    lastFileExtension = fileExtension;
    return 'https://example.test/avatar.$fileExtension';
  }

  @override
  Future<void> removeMyAvatar() async => avatarRemovals++;
}

class FakeAuthAdapter implements AuthAdapter {
  FakeAuthAdapter({this.fullName});

  final String? fullName;

  String? lastEmail;
  String? lastFullName;
  String? lastPhone;
  PlayerPosition? lastPosition;
  DateTime? lastDateOfBirth;
  PlayerPosition? lastSecondaryPosition;
  int signUpCount = 0;

  @override
  Future<String?> fetchCurrentUserFullName() async => fullName;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) async {
    signUpCount++;
    lastEmail = email;
    lastFullName = fullName;
    lastPhone = phone;
    lastPosition = position;
    lastDateOfBirth = dateOfBirth;
    lastSecondaryPosition = secondaryPosition;
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
  }

  @override
  String? get currentUserId => 'u1';

  @override
  String? get currentUserEmail => email;

  String email = 'player@example.com';

  String? changedEmail;
  String? changedPassword;

  String? changedRedirect;

  @override
  Future<void> changeEmail(String value, {required String redirectTo}) async {
    changedEmail = value;
    changedRedirect = redirectTo;
  }

  @override
  Future<void> changePassword(String value) async => changedPassword = value;

  @override
  bool get isSignedIn => true;

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  Future<void> signOut() => throw UnimplementedError();
}

class FakeMatchAdapter implements MatchAdapter {
  String? lastTitle;
  String? lastLocation;

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) async {
    lastTitle = title;
    lastLocation = location;
  }

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) async {
    lastTitle = title;
    lastLocation = location;
  }

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchUpcomingMatches() => throw UnimplementedError();

  @override
  Future<Match> fetchMatch(String matchId) => throw UnimplementedError();

  @override
  Future<void> deleteMatch(String matchId) => throw UnimplementedError();

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      throw UnimplementedError();

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      throw UnimplementedError();

  @override
  Future<void> withdrawFromMatch(String matchId) => throw UnimplementedError();

  @override
  Future<void> removePlayer(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<int?> fetchReservePlayers() => throw UnimplementedError();
}

class FakeTeamAdapter implements TeamAdapter {
  FakeTeamAdapter({this.roster = const [], this.played = const []});

  final List<PlayerCoreInputs> roster;
  final List<PastMatch> played;

  String? lastMatchId;
  String? lastCommunityId;
  String? lastExcludedMatchId;
  int? lastLimit;
  List<TeamAssignment>? savedLineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
      String matchId) async {
    lastMatchId = matchId;
    return roster;
  }

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) async {
    lastCommunityId = communityId;
    lastExcludedMatchId = excludeMatchId;
    lastLimit = limit;
    return played;
  }

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) async {
    lastMatchId = matchId;
    savedLineup = lineup;
  }

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) =>
      throw UnimplementedError();

  String? addedUserId;
  TeamId? addedTeam;
  Position? addedPosition;
  String? removedUserId;

  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) async {
    lastMatchId = matchId;
    addedUserId = userId;
    addedTeam = team;
    addedPosition = position;
  }

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) async {
    lastMatchId = matchId;
    removedUserId = userId;
  }
}

class FakeMemberAdapter implements MemberAdapter {
  String? lastCommunityId;
  String? lastUserId;
  CommunityRole? lastRole;

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) async {
    lastCommunityId = communityId;
    lastUserId = userId;
    lastRole = role;
  }

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) =>
      throw UnimplementedError();

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();

  @override
  Future<void> removeMember(String communityId, String userId) =>
      throw UnimplementedError();
}
