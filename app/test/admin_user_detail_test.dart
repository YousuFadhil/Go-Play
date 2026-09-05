import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

import 'admin_fakes.dart';

/// An account that has been seen, on both platforms, and has played.
final _seen = AdminUserActivitySummary(
  userId: 'u1',
  fullName: 'Ali Al Amri',
  email: 'ali@example.com',
  createdAt: DateTime.utc(2026, 1, 15, 9),
  isActive: true,
  lastSeenAt: DateTime.utc(2026, 9, 3, 18, 30),
  activeDays7d: 4,
  activeDays30d: 17,
  sessionsTotal: 63,
  platforms: const ['android', 'web'],
  latestAppVersion: '0.4.1-public-beta+2',
  communityCount: 3,
  trackedRegistrations: 22,
  matchesPlayed: 41,
  trackedWithdrawals: 5,
);

/// An account the product has never observed, which is the ordinary state of
/// one that has not been back since analytics was deployed.
final _unseen = AdminUserActivitySummary(
  userId: 'u2',
  fullName: 'Sara Al Balushi',
  email: 'sara@example.com',
  createdAt: DateTime.utc(2025, 6, 2, 12),
  isActive: false,
  suspendedAt: DateTime.utc(2026, 8, 1),
  suspensionReason: 'Repeated no-shows',
  activeDays7d: 0,
  activeDays30d: 0,
  sessionsTotal: 0,
  platforms: const [],
  communityCount: 1,
  trackedRegistrations: 0,
  matchesPlayed: 12,
  trackedWithdrawals: 0,
);

String _day(DateTime value) => DateFormat.yMMMEd('en').format(value);

void main() {
  Future<void> pumpDetail(
    WidgetTester tester,
    FakeAdminAdapter adapter, {
    String userId = 'u1',
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminUserDetailScreen(
        userId: userId,
        repository: AdminRepository(adapter),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the mapper keeps what the database did not say', () {
    test('a null Last Seen stays null', () {
      final summary = adminUserActivityFromRow(const {
        'user_id': 'u1',
        'full_name': 'Ali',
        'email': 'a@b.c',
        'created_at': '2026-01-15T09:00:00Z',
        'is_active': true,
        'last_seen_at': null,
        'platforms': <String>[],
        'latest_app_version': null,
      });

      // Substituting the join date would state something the database did not.
      expect(summary.lastSeenAt, isNull);
      expect(summary.latestAppVersion, isNull);
      expect(summary.platforms, isEmpty);
    });

    test('an empty version string is an absence, not an empty version', () {
      final summary = adminUserActivityFromRow(const {
        'user_id': 'u1',
        'created_at': '2026-01-15T09:00:00Z',
        'latest_app_version': '   ',
      });
      expect(summary.latestAppVersion, isNull);
    });

    test('platforms are read in the order the database sent them', () {
      final summary = adminUserActivityFromRow(const {
        'user_id': 'u1',
        'created_at': '2026-01-15T09:00:00Z',
        'platforms': ['android', 'web'],
      });
      expect(summary.platforms, ['android', 'web']);
    });

    test('counts are read as numbers, and a missing one is zero', () {
      final summary = adminUserActivityFromRow(const {
        'user_id': 'u1',
        'created_at': '2026-01-15T09:00:00Z',
        'active_days_7d': 4,
        'active_days_30d': 17,
        'sessions_total': 63,
        'community_count': 3,
        'tracked_registrations': 22,
        'matches_played': 41,
      });

      expect(summary.activeDays7d, 4);
      expect(summary.activeDays30d, 17);
      expect(summary.sessionsTotal, 63);
      expect(summary.communityCount, 3);
      expect(summary.trackedRegistrations, 22);
      expect(summary.matchesPlayed, 41);
      // Absent from the row entirely.
      expect(summary.trackedWithdrawals, 0);
    });

    test('an activity row keeps a context id whose label is gone', () {
      final event = adminActivityEventFromRow(const {
        'event_name': 'match_viewed',
        'created_at': '2026-09-03T18:30:00Z',
        'community_id': 'c1',
        'community_name': null,
        'match_id': 'm1',
        'match_title': null,
      });

      // The LEFT joins are what let the event survive its target's deletion;
      // the mapper must not then discard the evidence that there was one.
      expect(event.communityId, 'c1');
      expect(event.communityName, isNull);
      expect(event.matchId, 'm1');
      expect(event.matchTitle, isNull);
    });

    test('an audit entry keeps its optional fields', () {
      final entry = adminAuditEntryFromRow(const {
        'id': 'a1',
        'action': 'USER_SUSPENDED',
        'target_type': 'USER',
        'created_at': '2026-09-04T10:00:00Z',
        'actor_email_snapshot': '  admin@example.com  ',
        'target_label_snapshot': null,
        'reason': '  spam  ',
      });

      expect(entry.actorEmailSnapshot, 'admin@example.com');
      expect(entry.targetLabelSnapshot, isNull);
      expect(entry.reason, 'spam');
    });

    test('an action this build has never heard of maps without crashing', () {
      final entry = adminAuditEntryFromRow(const {
        'id': 'a2',
        'action': 'SOMETHING_LATER',
        'target_type': 'USER',
        'created_at': '2026-09-04T10:00:00Z',
      });
      expect(entry.action, 'SOMETHING_LATER');
    });
  });

  group('opening a user', () {
    testWidgets('tapping a Users row opens the detail screen', (tester) async {
      final adapter = FakeAdminAdapter(
        users: [adminUser()],
        activitySummary: _seen,
      );
      await pumpAdmin(tester, adapter);
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
      expect(adapter.calls, contains('userActivitySummary:u1'));
    });

    testWidgets('pressing Suspend suspends, and does not open the detail',
        (tester) async {
      final adapter = FakeAdminAdapter(
        users: [adminUser()],
        activitySummary: _seen,
      );
      await pumpAdmin(tester, adapter);
      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();

      // The suspension flow, on the list, exactly as before.
      expect(find.text('Reason'), findsOneWidget);
      expect(find.byType(AdminUserDetailScreen), findsNothing);
      expect(adapter.calls, isNot(contains('userActivitySummary:u1')));
    });
  });

  group('an account the product has watched', () {
    testWidgets('says who it is and that it is active', (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(find.text('Ali Al Amri'), findsOneWidget);
      expect(find.text('ali@example.com'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows when they joined and when they were last seen',
        (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(find.text('Joined'), findsOneWidget);
      expect(find.text(_day(_seen.createdAt)), findsOneWidget);
      expect(find.text('Last seen'), findsOneWidget);
      expect(
        find.textContaining(_day(_seen.lastSeenAt!)),
        findsOneWidget,
      );
    });

    testWidgets('shows active days, sessions, platforms and version',
        (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(find.text('Active days · 7 days'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Active days · 30 days'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('63'), findsOneWidget);
      expect(find.text('Platforms'), findsOneWidget);
      expect(find.text('Android · Web'), findsOneWidget);
      expect(find.text('App version'), findsOneWidget);
      expect(find.text('0.4.1-public-beta+2'), findsOneWidget);
    });

    testWidgets('shows the football figures', (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(find.text('Communities'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Registrations'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('Matches played'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Withdrawals'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('says where the behavioural figures begin', (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(
        find.textContaining('Activity metrics start from this release'),
        findsOneWidget,
      );
    });
  });

  group('an account the product has never observed', () {
    testWidgets('shows a dash for last seen, platforms and version',
        (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _unseen),
        userId: 'u2',
      );

      // Three unknowns, three dashes. None of them is a zero and none of them
      // is a guess.
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('shows the suspension and its reason', (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _unseen),
        userId: 'u2',
      );

      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('Repeated no-shows'), findsOneWidget);
      // The detail screen does not offer a second way to change that state.
      expect(find.text('Reactivate'), findsNothing);
      expect(find.text('Suspend'), findsNothing);
    });

    testWidgets('still shows the matches they played', (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _unseen),
        userId: 'u2',
      );

      // The reason 0068 reads player_statistics rather than
      // v_player_statistics: the view filters on users.is_active, and this is
      // the suspended account the screen exists to inspect.
      expect(find.text('Matches played'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });
  });

  group('recent activity', () {
    final timeline = [
      AdminUserActivityEvent(
        eventName: ProductEvent.matchRegistered.wireName,
        createdAt: DateTime.utc(2026, 9, 3, 18, 30),
        matchId: 'm1',
        matchTitle: 'Friday Night',
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        platform: 'android',
      ),
      AdminUserActivityEvent(
        eventName: ProductEvent.sessionStarted.wireName,
        createdAt: DateTime.utc(2026, 9, 1, 8),
        platform: 'web',
      ),
    ];

    testWidgets('reads the ten event names in the reader\'s language',
        (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _seen, timeline: timeline),
      );

      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Match registered'), findsOneWidget);
      expect(find.text('Session started'), findsOneWidget);
    });

    testWidgets('shows the context it has, and never a raw id', (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _seen, timeline: timeline),
      );

      expect(find.textContaining('Al Amerat FC'), findsOneWidget);
      expect(find.textContaining('Friday Night'), findsOneWidget);
      expect(find.textContaining('m1'), findsNothing);
      expect(find.textContaining('c1'), findsNothing);
    });

    testWidgets('newest is first', (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(activitySummary: _seen, timeline: timeline),
      );

      final newest = tester.getTopLeft(find.text('Match registered')).dy;
      final older = tester.getTopLeft(find.text('Session started')).dy;
      expect(newest, lessThan(older));
    });

    testWidgets('a deleted community is named as gone, not as a uuid',
        (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(
          activitySummary: _seen,
          timeline: [
            AdminUserActivityEvent(
              eventName: ProductEvent.communityViewed.wireName,
              createdAt: DateTime.utc(2026, 9, 3, 18, 30),
              // The id outlived the row: product_events holds no foreign keys.
              communityId: 'deadbeef-0000-0000-0000-000000000000',
            ),
          ],
        ),
      );

      expect(find.textContaining('No longer available'), findsOneWidget);
      expect(find.textContaining('deadbeef'), findsNothing);
    });

    testWidgets('an event this build does not know is shown as recorded',
        (tester) async {
      await pumpDetail(
        tester,
        FakeAdminAdapter(
          activitySummary: _seen,
          timeline: [
            AdminUserActivityEvent(
              eventName: 'something_a_later_release_records',
              createdAt: DateTime.utc(2026, 9, 3, 18, 30),
            ),
          ],
        ),
      );

      // Shown rather than dropped or crashed on.
      expect(find.text('something_a_later_release_records'), findsOneWidget);
    });

    testWidgets('an account with no activity says so', (tester) async {
      await pumpDetail(tester, FakeAdminAdapter(activitySummary: _seen));

      expect(
        find.text('Nothing has been recorded for this account yet.'),
        findsOneWidget,
      );
    });
  });

  group('a failed read', () {
    testWidgets('offers a retry rather than a half-filled record',
        (tester) async {
      final adapter = FakeAdminAdapter(
        activitySummary: _seen,
        activityFailure: const NetworkFailure(),
      );
      await pumpDetail(tester, adapter);

      expect(find.text('Ali Al Amri'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('and the retry reads again', (tester) async {
      final adapter = FakeAdminAdapter(
        activitySummary: _seen,
        activityFailure: const NetworkFailure(),
      );
      await pumpDetail(tester, adapter);

      adapter.activityFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Ali Al Amri'), findsOneWidget);
    });
  });

  group('the analytics contract is unchanged', () {
    test('there are still exactly ten events', () {
      expect(ProductEvent.values.length, 10);
    });

    test('an unknown wire name resolves to null rather than throwing', () {
      expect(ProductEvent.fromWireName('session_started'),
          ProductEvent.sessionStarted);
      expect(ProductEvent.fromWireName('nothing_like_it'), isNull);
    });
  });
}
