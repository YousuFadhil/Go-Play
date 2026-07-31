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
    test('stores the phone in its full international form', () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter).register(
        email: 'player@example.com',
        localPhone: '9012 3456',
        password: 'secret',
        fullName: 'Sara',
        position: PlayerPosition.mid,
      );

      expect(adapter.lastPhone, '+96890123456');
      expect(adapter.lastPosition, PlayerPosition.mid);
    });

    test('trims the email and the name', () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter).register(
        email: '  player@example.com ',
        localPhone: '90123456',
        password: 'secret',
        fullName: '  Sara  ',
        position: PlayerPosition.gk,
      );

      expect(adapter.lastEmail, 'player@example.com');
      expect(adapter.lastFullName, 'Sara');
    });

    test('sign-in trims the email too', () async {
      final adapter = FakeAuthAdapter();
      await AuthService(adapter)
          .login(email: '  player@example.com ', password: 'secret');

      expect(adapter.lastEmail, 'player@example.com');
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

class FakeAuthAdapter implements AuthAdapter {
  FakeAuthAdapter({this.fullName});

  final String? fullName;

  String? lastEmail;
  String? lastFullName;
  String? lastPhone;
  PlayerPosition? lastPosition;

  @override
  Future<String?> fetchCurrentUserFullName() async => fullName;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
  }) async {
    lastEmail = email;
    lastFullName = fullName;
    lastPhone = phone;
    lastPosition = position;
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
