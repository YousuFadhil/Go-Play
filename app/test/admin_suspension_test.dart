import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_adapter.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_screen.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

/// Records what the Admin screens ask of the data layer, and answers with
/// whatever the test needs to see.
class _FakeAdminAdapter implements AdminAdapter {
  _FakeAdminAdapter({
    this.users = const [],
    this.communities = const [],
    this.matches = const [],
  });

  List<AdminUserSummary> users;
  List<AdminCommunitySummary> communities;
  List<AdminMatchSummary> matches;

  final List<String> calls = [];

  @override
  Future<bool> isSystemAdmin() async => true;

  @override
  Future<List<AdminUserSummary>> listUsers(String? search) async {
    calls.add('listUsers');
    return users;
  }

  @override
  Future<List<AdminCommunitySummary>> listCommunities(String? search) async {
    calls.add('listCommunities');
    return communities;
  }

  @override
  Future<List<AdminMatchSummary>> listMatches(String? search) async {
    calls.add('listMatches');
    return matches;
  }

  @override
  Future<void> suspendUser(String id, String reason) async {
    calls.add('suspendUser:$id:$reason');
  }

  @override
  Future<void> reactivateUser(String id) async => calls.add('reactivateUser:$id');

  @override
  Future<void> suspendCommunity(String id, String reason) async {
    calls.add('suspendCommunity:$id:$reason');
  }

  @override
  Future<void> reactivateCommunity(String id) async =>
      calls.add('reactivateCommunity:$id');
}

AdminUserSummary _user({
  String id = 'u1',
  String name = 'Ali',
  bool active = true,
  bool systemAdmin = false,
}) =>
    AdminUserSummary(
      id: id,
      fullName: name,
      email: '$id@example.com',
      isSystemAdmin: systemAdmin,
      isActive: active,
    );

AdminCommunitySummary _community({
  String id = 'c1',
  String name = 'Falcons',
  bool active = true,
}) =>
    AdminCommunitySummary(
      id: id,
      name: name,
      memberCount: 3,
      matchCount: 2,
      isActive: active,
      ownerName: 'Owner',
    );

Widget _app(AdminRepository repository) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminScreen(repository: repository),
    );

void main() {
  group('admin mapper reads the suspension read model (0066)', () {
    test('an active user carries no suspension metadata', () {
      final user = adminUserFromRow(const {
        'id': 'u1',
        'full_name': 'Ali',
        'email': 'a@b.c',
        'is_system_admin': false,
        'is_active': true,
        'suspended_at': null,
        'suspension_reason': null,
      });

      expect(user.isActive, isTrue);
      expect(user.suspendedAt, isNull);
      expect(user.suspensionReason, isNull);
    });

    test('a suspended user carries when and why', () {
      final user = adminUserFromRow(const {
        'id': 'u1',
        'full_name': 'Ali',
        'email': 'a@b.c',
        'is_system_admin': false,
        'is_active': false,
        'suspended_at': '2026-09-04T10:00:00Z',
        'suspension_reason': '  spam  ',
      });

      expect(user.isActive, isFalse);
      expect(user.suspendedAt, DateTime.parse('2026-09-04T10:00:00Z'));
      // Trimmed, so the screen has one thing to test rather than two.
      expect(user.suspensionReason, 'spam');
    });

    test('a missing is_active reads as active, never as suspended', () {
      // Inventing a suspension is the worse of the two mistakes.
      final user = adminUserFromRow(const {'id': 'u1'});
      expect(user.isActive, isTrue);
    });

    test('an empty reason is an absence', () {
      final community = adminCommunityFromRow(const {
        'id': 'c1',
        'name': 'Falcons',
        'is_active': false,
        'suspension_reason': '   ',
      });
      expect(community.isActive, isFalse);
      expect(community.suspensionReason, isNull);
    });

    test('an unparseable timestamp does not lose the row', () {
      final community = adminCommunityFromRow(const {
        'id': 'c1',
        'name': 'Falcons',
        'is_active': false,
        'suspended_at': 'not-a-date',
      });
      expect(community.suspendedAt, isNull);
      expect(community.isActive, isFalse);
    });
  });

  group('AdminRepository refuses a blank reason before the adapter', () {
    test('suspendUser', () async {
      final adapter = _FakeAdminAdapter();
      final repository = AdminRepository(adapter);

      await expectLater(
        repository.suspendUser('u1', '   '),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.calls, isEmpty);
    });

    test('suspendCommunity', () async {
      final adapter = _FakeAdminAdapter();
      final repository = AdminRepository(adapter);

      await expectLater(
        repository.suspendCommunity('c1', ''),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.calls, isEmpty);
    });

    test('a reason reaches the adapter trimmed', () async {
      final adapter = _FakeAdminAdapter();
      await AdminRepository(adapter).suspendUser('u1', '  spam  ');
      expect(adapter.calls, ['suspendUser:u1:spam']);
    });
  });

  group('Users tab', () {
    testWidgets('an active user offers Suspend', (tester) async {
      final adapter = _FakeAdminAdapter(users: [_user()]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('Suspend'), findsOneWidget);
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('a suspended user offers Reactivate', (tester) async {
      final adapter = _FakeAdminAdapter(users: [_user(active: false)]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Suspended'), findsOneWidget);
    });

    testWidgets('a System Admin offers neither action', (tester) async {
      final adapter =
          _FakeAdminAdapter(users: [_user(systemAdmin: true)]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('System Admin'), findsOneWidget);
    });

    testWidgets('a blank reason never reaches the repository', (tester) async {
      final adapter = _FakeAdminAdapter(users: [_user()]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();

      // Confirm without typing anything.
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(adapter.calls.where((c) => c.startsWith('suspendUser')), isEmpty);
      expect(find.text('Please give a reason.'), findsOneWidget);
      // The dialog stays open rather than pretending anything happened.
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('a real suspension calls the RPC and refreshes',
        (tester) async {
      final adapter = _FakeAdminAdapter(users: [_user()]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      adapter.calls.clear();

      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '  spam  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('suspendUser:u1:spam'));
      // Refreshed, so the row shows its new state rather than a stale one.
      expect(adapter.calls, contains('listUsers'));
      expect(find.text('Suspended.'), findsOneWidget);
    });

    testWidgets('reactivation confirms, calls and refreshes', (tester) async {
      final adapter = _FakeAdminAdapter(users: [_user(active: false)]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      adapter.calls.clear();

      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // No reason field on this path.
      expect(find.text('Reason'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('reactivateUser:u1'));
      expect(adapter.calls, contains('listUsers'));
      expect(find.text('Reactivated.'), findsOneWidget);
    });
  });

  group('Communities tab', () {
    Future<void> openCommunities(WidgetTester tester) async {
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();
    }

    testWidgets('an active community offers Suspend', (tester) async {
      final adapter = _FakeAdminAdapter(communities: [_community()]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      await openCommunities(tester);

      expect(find.text('Suspend'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('a suspended community offers Reactivate', (tester) async {
      final adapter =
          _FakeAdminAdapter(communities: [_community(active: false)]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      await openCommunities(tester);

      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);
    });

    testWidgets('suspension requires a reason and then calls the RPC',
        (tester) async {
      final adapter = _FakeAdminAdapter(communities: [_community()]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      await openCommunities(tester);
      adapter.calls.clear();

      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      expect(adapter.calls.where((c) => c.startsWith('suspendCommunity')),
          isEmpty);

      await tester.enterText(find.byType(TextField).last, 'abuse');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('suspendCommunity:c1:abuse'));
      expect(adapter.calls, contains('listCommunities'));
    });
  });

  group('Matches tab', () {
    testWidgets('is read-only: no delete, suspend or reactivate',
        (tester) async {
      final adapter = _FakeAdminAdapter(matches: const [
        AdminMatchSummary(
          id: 'm1',
          location: 'Pitch 3',
          registrationCount: 8,
          title: 'Friday',
          communityName: 'Falcons',
        ),
      ]);
      await tester.pumpWidget(_app(AdminRepository(adapter)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Matches'));
      await tester.pumpAndSettle();

      expect(find.text('Friday'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });
}
