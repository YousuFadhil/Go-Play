import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_adapter.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_screen.dart';

/// A full set of figures, so a test can change the one it cares about.
const _figures = AdminAnalyticsOverview(
  totalUsers: 412,
  newUsersToday: 3,
  newUsers7d: 19,
  newUsers30d: 64,
  dau: 27,
  wau: 88,
  mau: 205,
  weeklyActiveCommunities: 11,
  matches7d: 14,
  matches30d: 51,
  registrations7d: 132,
  registrations30d: 470,
  results7d: 9,
  results30d: 38,
  retentionPreviousWeekUsers: 80,
  retentionReturningUsers: 60,
  weeklyRetentionPercent: 75,
);

class _FakeAdminAdapter implements AdminAdapter {
  _FakeAdminAdapter({this.overview = _figures, this.overviewFailure});

  AdminAnalyticsOverview overview;
  Failure? overviewFailure;

  int overviewCalls = 0;

  @override
  Future<AdminAnalyticsOverview> analyticsOverview() async {
    overviewCalls++;
    if (overviewFailure != null) throw overviewFailure!;
    return overview;
  }

  @override
  Future<bool> isSystemAdmin() async => true;

  @override
  Future<List<AdminAuditEntry>> listAuditLog() async => const [];

  // The drill-downs (0069) are not what this suite is about; a call from an
  // unexpected place should fail loudly rather than answer.
  @override
  Future<List<AdminDrilldownUser>> drilldownUsers(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AdminDrilldownCommunity>> drilldownCommunities(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AdminDrilldownMatch>> drilldownMatches(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AdminDrilldownRegistration>> drilldownRegistrations(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<AdminCommunityInspection> communityInspection(String communityId) =>
      throw UnimplementedError();

  @override
  Future<AdminMatchInspection> matchInspection(String matchId) =>
      throw UnimplementedError();

  @override
  Future<AdminUserActivitySummary> userActivitySummary(String userId) =>
      throw UnimplementedError();

  @override
  Future<List<AdminUserActivityEvent>> userActivityTimeline(String userId) =>
      throw UnimplementedError();

  @override
  Future<List<AdminUserSummary>> listUsers(String? search) async => const [
        AdminUserSummary(
          id: 'u1',
          fullName: 'Ali',
          email: 'ali@example.com',
          isSystemAdmin: false,
          isActive: true,
        ),
      ];

  @override
  Future<List<AdminCommunitySummary>> listCommunities(String? search) async =>
      const [
        AdminCommunitySummary(
          id: 'c1',
          name: 'Al Amerat FC',
          memberCount: 12,
          matchCount: 4,
          isActive: true,
        ),
      ];

  @override
  Future<List<AdminMatchSummary>> listMatches(String? search) async => const [
        AdminMatchSummary(
          id: 'm1',
          location: 'Al Amerat Pitch',
          registrationCount: 10,
          title: 'Friday Night',
        ),
      ];

  @override
  Future<void> suspendUser(String id, String reason) async {}

  @override
  Future<void> reactivateUser(String id) async {}

  @override
  Future<void> suspendCommunity(String id, String reason) async {}

  @override
  Future<void> reactivateCommunity(String id) async {}
}

void main() {
  Future<void> pumpAdmin(
    WidgetTester tester,
    _FakeAdminAdapter adapter, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminScreen(repository: AdminRepository(adapter)),
    ));
    await tester.pumpAndSettle();
  }

  group('the Overview is what the console opens on', () {
    testWidgets('it is the first of five tabs, in the approved order',
        (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
      expect(
        [for (final tab in tabs) tab.text],
        ['Overview', 'Users', 'Communities', 'Matches', 'Audit Log'],
      );
    });

    testWidgets('and it is the tab actually showing', (tester) async {
      final adapter = _FakeAdminAdapter();
      await pumpAdmin(tester, adapter);

      expect(adapter.overviewCalls, 1);
      expect(find.text('Product health'), findsOneWidget);
    });

    testWidgets('the two Product Health signals lead', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      // Weekly Active Users appears twice -- once as a headline, once in
      // Engagement -- and Weekly Active Communities once.
      expect(find.text('Weekly active users'), findsNWidgets(2));
      expect(find.text('Weekly active communities'), findsOneWidget);
      expect(find.text('88'), findsNWidgets(2));
      expect(find.text('11'), findsOneWidget);
    });
  });

  group('the figures are the ones the database sent', () {
    testWidgets('user growth', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      expect(find.text('Total users'), findsOneWidget);
      expect(find.text('412'), findsOneWidget);
      expect(find.text('New today'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('64'), findsOneWidget);
    });

    testWidgets('engagement', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      expect(find.text('Daily active users'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('Monthly active users'), findsOneWidget);
      expect(find.text('205'), findsOneWidget);
      expect(find.text('Weekly retention'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      // What the percentage is made of, so a figure from four people is not
      // read as the same evidence as one from four hundred.
      expect(find.text('60 of 80 from last week'), findsOneWidget);
    });

    testWidgets('football activity', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      expect(find.text('Matches · 7 days'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('Matches · 30 days'), findsOneWidget);
      expect(find.text('51'), findsOneWidget);
      expect(find.text('Registrations · 7 days'), findsOneWidget);
      expect(find.text('132'), findsOneWidget);
      expect(find.text('Registrations · 30 days'), findsOneWidget);
      expect(find.text('470'), findsOneWidget);
      expect(find.text('Results · 7 days'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Results · 30 days'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
    });
  });

  group('retention that cannot be computed', () {
    testWidgets('renders an em dash, never 0%', (tester) async {
      await pumpAdmin(
        tester,
        _FakeAdminAdapter(
          overview: const AdminAnalyticsOverview(
            totalUsers: 5,
            newUsersToday: 0,
            newUsers7d: 5,
            newUsers30d: 5,
            dau: 0,
            wau: 0,
            mau: 0,
            weeklyActiveCommunities: 0,
            matches7d: 0,
            matches30d: 0,
            registrations7d: 0,
            registrations30d: 0,
            results7d: 0,
            results30d: 0,
            retentionPreviousWeekUsers: 0,
            retentionReturningUsers: 0,
          ),
        ),
      );

      // Nobody to come back is not nobody coming back.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });
  });

  group('a failed read', () {
    testWidgets('offers a retry rather than a dashboard of zeroes',
        (tester) async {
      final adapter =
          _FakeAdminAdapter(overviewFailure: const NetworkFailure());
      await pumpAdmin(tester, adapter);

      expect(find.text('Product health'), findsNothing);
      expect(find.text('412'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(adapter.overviewCalls, 1);
    });

    testWidgets('and the retry makes exactly one new call', (tester) async {
      final adapter =
          _FakeAdminAdapter(overviewFailure: const NetworkFailure());
      await pumpAdmin(tester, adapter);

      adapter.overviewFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.overviewCalls, 2);
      expect(find.text('Product health'), findsOneWidget);
      expect(find.text('412'), findsOneWidget);
    });
  });

  group('the tracking notice', () {
    testWidgets('says where the behavioural figures begin, quietly',
        (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());

      expect(
        find.textContaining('Activity metrics start from this release'),
        findsOneWidget,
      );
      // A note, not a warning: no dialog, no banner.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('and is translated', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter(), locale: const Locale('ar'));

      expect(find.text('نظرة عامة'), findsOneWidget);
      expect(find.text('صحة المنتج'), findsOneWidget);
      expect(
        find.textContaining('تبدأ مؤشرات النشاط من هذا الإصدار'),
        findsOneWidget,
      );
    });
  });

  group('the rest of the console is unchanged', () {
    testWidgets('Users still shows state and offers Suspend', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspend'), findsOneWidget);
    });

    testWidgets('Communities still shows state and offers Suspend',
        (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();

      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspend'), findsOneWidget);
    });

    testWidgets('Matches remains inspection only', (tester) async {
      await pumpAdmin(tester, _FakeAdminAdapter());
      await tester.tap(find.text('Matches').last);
      await tester.pumpAndSettle();

      expect(find.text('Friday Night'), findsOneWidget);
      // No action of any kind on a match row, and no delete anywhere.
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });
  });
}
