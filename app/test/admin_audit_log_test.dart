import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/admin/admin_models.dart';

import 'admin_fakes.dart';

/// The administrative record, as an administrator reads it.
///
/// Read only throughout: what these assert as strongly as anything they assert
/// about content is that there is nothing on this screen to press.
void main() {
  final suspended = AdminAuditEntry(
    id: 'a1',
    action: 'USER_SUSPENDED',
    targetType: 'USER',
    createdAt: DateTime.utc(2026, 9, 4, 10),
    actorUserId: 'admin1',
    actorEmailSnapshot: 'admin@example.com',
    targetId: 'u1',
    targetLabelSnapshot: 'Ali Al Amri',
    reason: 'Repeated no-shows',
  );

  final reactivated = AdminAuditEntry(
    id: 'a2',
    action: 'USER_REACTIVATED',
    targetType: 'USER',
    createdAt: DateTime.utc(2026, 9, 3, 9),
    actorEmailSnapshot: 'admin@example.com',
    targetLabelSnapshot: 'Ali Al Amri',
  );

  final communitySuspended = AdminAuditEntry(
    id: 'a3',
    action: 'COMMUNITY_SUSPENDED',
    targetType: 'COMMUNITY',
    createdAt: DateTime.utc(2026, 9, 2, 9),
    actorEmailSnapshot: 'admin@example.com',
    targetLabelSnapshot: 'Al Amerat FC',
    reason: 'Under review',
  );

  final communityReactivated = AdminAuditEntry(
    id: 'a4',
    action: 'COMMUNITY_REACTIVATED',
    targetType: 'COMMUNITY',
    createdAt: DateTime.utc(2026, 9, 1, 9),
    actorEmailSnapshot: 'admin@example.com',
    targetLabelSnapshot: 'Al Amerat FC',
  );

  Future<void> openAudit(WidgetTester tester, FakeAdminAdapter adapter) async {
    await pumpAdmin(tester, adapter);
    await tester.tap(find.text('Audit Log'));
    await tester.pumpAndSettle();
  }

  group('the Audit Log is the fifth tab', () {
    testWidgets('and the four before it keep their order', (tester) async {
      await pumpAdmin(tester, FakeAdminAdapter());

      final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
      expect(
        [for (final tab in tabs) tab.text],
        ['Overview', 'Users', 'Communities', 'Matches', 'Audit Log'],
      );
    });

    testWidgets('and Overview is still what the console opens on',
        (tester) async {
      await pumpAdmin(tester, FakeAdminAdapter());
      expect(find.text('Product health'), findsOneWidget);
    });

    testWidgets('opening it reads the log', (tester) async {
      final adapter = FakeAdminAdapter(audit: [suspended]);
      await openAudit(tester, adapter);

      expect(adapter.auditCalls, greaterThanOrEqualTo(1));
      expect(find.text('User suspended'), findsOneWidget);
    });
  });

  group('an entry says what was done, to what, by whom and why', () {
    testWidgets('all four recorded actions read in the reader\'s language',
        (tester) async {
      await openAudit(
        tester,
        FakeAdminAdapter(audit: [
          suspended,
          reactivated,
          communitySuspended,
          communityReactivated,
        ]),
      );

      expect(find.text('User suspended'), findsOneWidget);
      expect(find.text('User reactivated'), findsOneWidget);
      expect(find.text('Community suspended'), findsOneWidget);
      expect(find.text('Community reactivated'), findsOneWidget);
    });

    testWidgets('the target, the actor, the reason and the time', (tester) async {
      await openAudit(tester, FakeAdminAdapter(audit: [suspended]));

      expect(find.text('Ali Al Amri'), findsOneWidget);
      expect(find.textContaining('admin@example.com'), findsOneWidget);
      expect(find.text('Repeated no-shows'), findsOneWidget);
      // The date rides on the same line as the actor.
      expect(find.textContaining('2026'), findsOneWidget);
    });

    testWidgets('a reactivation carries no reason, and none is shown',
        (tester) async {
      await openAudit(tester, FakeAdminAdapter(audit: [reactivated]));

      expect(find.text('User reactivated'), findsOneWidget);
      expect(find.text('Repeated no-shows'), findsNothing);
    });

    testWidgets('a snapshot that was never captured reads as gone, not as a id',
        (tester) async {
      await openAudit(
        tester,
        FakeAdminAdapter(audit: [
          AdminAuditEntry(
            id: 'a9',
            action: 'USER_SUSPENDED',
            targetType: 'USER',
            createdAt: DateTime.utc(2026, 9, 4, 10),
            actorUserId: 'deadbeef-0000-0000-0000-000000000000',
            targetId: 'cafebabe-0000-0000-0000-000000000000',
          ),
        ]),
      );

      // The target stands alone; the actor rides on the date line, so it is
      // matched as a substring rather than as its own Text.
      expect(find.text('No longer available'), findsOneWidget);
      expect(find.textContaining('No longer available'), findsNWidgets(2));
      // Neither uuid is anywhere on screen. One names nothing an
      // administrator can act on, and reads as noise.
      expect(find.textContaining('deadbeef'), findsNothing);
      expect(find.textContaining('cafebabe'), findsNothing);
    });

    testWidgets('an action a later cycle records is shown as recorded',
        (tester) async {
      await openAudit(
        tester,
        FakeAdminAdapter(audit: [
          AdminAuditEntry(
            id: 'a8',
            action: 'SOMETHING_LATER',
            targetType: 'USER',
            createdAt: DateTime.utc(2026, 9, 4, 10),
            targetLabelSnapshot: 'Ali Al Amri',
          ),
        ]),
      );

      // The log is append-only. A reader that dropped what it did not
      // recognise would hide exactly the entries most worth seeing.
      expect(find.text('SOMETHING_LATER'), findsOneWidget);
    });
  });

  group('it is read only, structurally', () {
    testWidgets('there is nothing to press on an entry', (tester) async {
      await openAudit(
        tester,
        FakeAdminAdapter(audit: [suspended, communitySuspended]),
      );

      for (final label in ['Delete', 'Undo', 'Edit', 'Reactivate', 'Suspend']) {
        expect(find.text(label), findsNothing, reason: '$label is not offered');
      }
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('and no raw metadata is anywhere on screen', (tester) async {
      await openAudit(tester, FakeAdminAdapter(audit: [suspended]));

      expect(find.textContaining('{'), findsNothing);
      expect(find.textContaining('metadata'), findsNothing);
    });
  });

  group('the empty and failed states', () {
    testWidgets('an empty log says so rather than looking broken',
        (tester) async {
      await openAudit(tester, FakeAdminAdapter());

      expect(find.text('Nothing has been recorded yet.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failed read offers a retry', (tester) async {
      final adapter = FakeAdminAdapter(auditFailure: const NetworkFailure());
      await openAudit(tester, adapter);

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Nothing has been recorded yet.'), findsNothing);
    });

    testWidgets('and the retry reads again', (tester) async {
      final adapter = FakeAdminAdapter(
        audit: [suspended],
        auditFailure: const NetworkFailure(),
      );
      await openAudit(tester, adapter);
      final before = adapter.auditCalls;

      adapter.auditFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.auditCalls, before + 1);
      expect(find.text('User suspended'), findsOneWidget);
    });
  });

  group('the rest of the console still works', () {
    testWidgets('Users still offers Suspend', (tester) async {
      await pumpAdmin(tester, FakeAdminAdapter(users: [adminUser()]));
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspend'), findsOneWidget);
    });

    testWidgets('a System Admin is still protected', (tester) async {
      await pumpAdmin(
        tester,
        FakeAdminAdapter(users: [adminUser(systemAdmin: true)]),
      );
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      expect(find.text('System Admin'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
    });

    testWidgets('Communities still offers Suspend', (tester) async {
      await pumpAdmin(
        tester,
        FakeAdminAdapter(communities: [
          const AdminCommunitySummary(
            id: 'c1',
            name: 'Al Amerat FC',
            memberCount: 12,
            matchCount: 4,
            isActive: true,
          ),
        ]),
      );
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();

      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Suspend'), findsOneWidget);
    });

    testWidgets('Matches remains inspection only', (tester) async {
      await pumpAdmin(
        tester,
        FakeAdminAdapter(matches: [
          const AdminMatchSummary(
            id: 'm1',
            location: 'Al Amerat Pitch',
            registrationCount: 10,
            title: 'Friday Night',
          ),
        ]),
      );
      await tester.tap(find.text('Matches').last);
      await tester.pumpAndSettle();

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });
  });

  group('Arabic', () {
    testWidgets('the tab and the actions are translated', (tester) async {
      await pumpAdmin(
        tester,
        FakeAdminAdapter(audit: [suspended]),
        locale: const Locale('ar'),
      );
      await tester.tap(find.text('سجل الإدارة'));
      await tester.pumpAndSettle();

      expect(find.text('إيقاف مستخدم'), findsOneWidget);
    });
  });
}
