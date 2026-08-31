import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_task.dart';
import 'package:go_play/core/football_components.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_management_screen.dart';
import 'package:go_play/features/members/member_repository.dart';

void main() {
  const owner = CommunityMember(
    userId: 'u1',
    fullName: 'Yousuf Al Amri',
    position: 'MID',
    role: CommunityRole.owner,
  );
  const player = CommunityMember(
    userId: 'u2',
    fullName: 'Noor Al Kindi',
    position: 'FWD',
    role: CommunityRole.player,
  );
  const admin = CommunityMember(
    userId: 'u3',
    fullName: 'Salim Al Harthy',
    position: 'DEF',
    role: CommunityRole.admin,
  );

  Future<void> pumpMembers(
    WidgetTester tester, {
    required FakeMemberAdapter members,
    required CommunityRole myRole,
    String currentUserId = 'u1',
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
  }) async {
    assert(members.myRole == myRole);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MemberManagementScreen(
          communityId: 'c1',
          communityName: 'Al Amerat FC',
          memberRepository: MemberRepository(members),
          authService: AuthService(FakeAuthAdapter(currentUserId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the Club task bar and bounded role markers',
      (tester) async {
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(myRole: CommunityRole.owner, members: [
        owner,
        player,
        admin,
      ]),
      myRole: CommunityRole.owner,
    );

    expect(find.byType(ClubTaskBar), findsOneWidget);
    expect(find.byType(ClubTaskBody), findsOneWidget);
    expect(find.byType(GoRoleChip), findsNWidgets(2));
  });

  testWidgets('the owner retains promotion, transfer, and removal actions',
      (tester) async {
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(myRole: CommunityRole.owner, members: [
        owner,
        player,
        admin,
      ]),
      myRole: CommunityRole.owner,
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('Make admin'), findsOneWidget);
    expect(find.text('Transfer ownership'), findsOneWidget);
    expect(find.text('Remove from community'), findsOneWidget);
  });

  testWidgets('an admin can only remove a player', (tester) async {
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(myRole: CommunityRole.admin, members: [
        owner,
        player,
        admin,
      ]),
      myRole: CommunityRole.admin,
      currentUserId: 'u3',
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('Make admin'), findsNothing);
    expect(find.text('Transfer ownership'), findsNothing);
    expect(find.text('Remove from community'), findsOneWidget);
  });

  testWidgets('a player has no management actions', (tester) async {
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(myRole: CommunityRole.player, members: [
        owner,
        player,
        admin,
      ]),
      myRole: CommunityRole.player,
      currentUserId: 'u2',
    );

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(
      find.text('Only the owner and admins can do this.'),
      findsOneWidget,
    );
  });

  testWidgets('long English and Arabic names stay on one line at 320px',
      (tester) async {
    const english =
        'Christopher Alexander Montgomery-Williams the Third Junior';
    const arabic = 'يوسف بن عبدالله الفاضل الحارثي لاعب خط الوسط المحترف';
    final longMembers = [
      const CommunityMember(
        userId: 'u2',
        fullName: english,
        position: 'FWD',
        role: CommunityRole.player,
      ),
      const CommunityMember(
        userId: 'u3',
        fullName: arabic,
        position: 'DEF',
        role: CommunityRole.admin,
      ),
    ];
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(
        myRole: CommunityRole.owner,
        members: longMembers,
      ),
      myRole: CommunityRole.owner,
      size: const Size(320, 700),
    );

    final englishText = tester.widget<Text>(find.text(english));
    final arabicText = tester.widget<Text>(find.text(arabic));
    expect(englishText.maxLines, 1);
    expect(englishText.overflow, TextOverflow.ellipsis);
    expect(arabicText.maxLines, 1);
    expect(arabicText.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    await pumpMembers(
      tester,
      members: FakeMemberAdapter(
        myRole: CommunityRole.owner,
        members: longMembers,
      ),
      myRole: CommunityRole.owner,
      locale: const Locale('ar'),
      size: const Size(320, 700),
    );
    final arabicRtlText = tester.widget<Text>(find.text(arabic));
    expect(arabicRtlText.maxLines, 1);
    expect(arabicRtlText.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role and removal callbacks still refresh the member list',
      (tester) async {
    final members = FakeMemberAdapter(
      myRole: CommunityRole.owner,
      members: [owner, player],
    );
    await pumpMembers(
      tester,
      members: members,
      myRole: CommunityRole.owner,
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();

    expect(members.roleChanges, [('u2', CommunityRole.admin)]);
    expect(members.memberReads, greaterThanOrEqualTo(2));

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from community'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from community').last);
    await tester.pumpAndSettle();

    expect(members.removals, ['u2']);
    expect(members.memberReads, greaterThanOrEqualTo(3));
    expect(find.text('Noor Al Kindi'), findsNothing);
  });

  testWidgets('the task body builds at 480px', (tester) async {
    await pumpMembers(
      tester,
      members: FakeMemberAdapter(myRole: CommunityRole.player, members: [
        owner,
        player,
      ]),
      myRole: CommunityRole.player,
      size: const Size(480, 900),
    );

    expect(find.byType(ClubTaskBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class FakeMemberAdapter implements MemberAdapter {
  FakeMemberAdapter({required this.myRole, required List<CommunityMember> members})
      : _members = members;

  final CommunityRole myRole;
  List<CommunityMember> _members;
  int memberReads = 0;
  final List<(String, CommunityRole)> roleChanges = [];
  final List<String> removals = [];

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => myRole;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async {
    memberReads++;
    return _members;
  }

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) async {
    roleChanges.add((userId, role));
    _members = [
      for (final member in _members)
        if (member.userId == userId)
          CommunityMember(
            userId: member.userId,
            fullName: member.fullName,
            position: member.position,
            role: role,
            avatarUrl: member.avatarUrl,
          )
        else
          member,
    ];
  }

  @override
  Future<void> removeMember(String communityId, String userId) async {
    removals.add(userId);
    _members = _members.where((member) => member.userId != userId).toList();
  }

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();
}

class FakeAuthAdapter implements AuthAdapter {
  FakeAuthAdapter(this.id);

  final String id;

  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => id;

  @override
  String? get currentUserEmail => null;

  @override
  Stream<bool> get signedInChanges => const Stream<bool>.empty();

  @override
  Future<String?> fetchCurrentUserFullName() async => null;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}
