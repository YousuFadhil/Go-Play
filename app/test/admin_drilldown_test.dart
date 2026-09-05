import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_analytics_drilldown_screen.dart';
import 'package:go_play/features/admin/admin_community_inspection_screen.dart';
import 'package:go_play/features/admin/admin_match_inspection_screen.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';

import 'admin_fakes.dart';

/// A live account, with somewhere to go.
AdminDrilldownUser _user({
  String id = 'u1',
  String name = 'Ali Al Amri',
  bool active = true,
  bool? returned,
}) =>
    AdminDrilldownUser(
      userId: id,
      fullName: name,
      email: '$id@example.com',
      createdAt: DateTime.utc(2026, 1, 15),
      isActive: active,
      isSystemAdmin: false,
      lastSeenAt: DateTime.utc(2026, 9, 3),
      returnedInCurrentWeek: returned,
    );

/// An account a session event named and that has since been deleted. The
/// Overview counted it, so the list must contain it.
const _deletedUser = AdminDrilldownUser(
  userId: 'deadbeef-0000-0000-0000-000000000000',
);

final _community = AdminDrilldownCommunity(
  communityId: 'c1',
  name: 'Al Amerat FC',
  ownerName: 'Owner',
  memberCount: 12,
  matchCount: 4,
  isActive: true,
  lastActivityAt: DateTime.utc(2026, 9, 3),
);

final _match = AdminDrilldownMatch(
  matchId: 'm1',
  title: 'Friday Night',
  communityId: 'c1',
  communityName: 'Al Amerat FC',
  location: 'Al Amerat Pitch',
  startAt: DateTime.utc(2026, 9, 3, 18),
  status: 'completed',
  matchCreatedAt: DateTime.utc(2026, 8, 30),
  resultCreatedAt: DateTime.utc(2026, 9, 4),
  scoreA: 3,
  scoreB: 2,
);

final _registration = AdminDrilldownRegistration(
  eventId: 'e1',
  createdAt: DateTime.utc(2026, 9, 3, 18, 30),
  userId: 'u1',
  fullName: 'Ali Al Amri',
  email: 'u1@example.com',
  matchId: 'm1',
  matchTitle: 'Friday Night',
  communityId: 'c1',
  communityName: 'Al Amerat FC',
);

final _communityInspection = AdminCommunityInspection(
  communityId: 'c1',
  name: 'Al Amerat FC',
  description: 'Friday football',
  joinPolicy: 'OPEN',
  createdAt: DateTime.utc(2025, 3, 1),
  ownerName: 'Owner',
  memberCount: 12,
  matchCount: 4,
  isActive: true,
);

final _matchInspection = AdminMatchInspection(
  matchId: 'm1',
  title: 'Friday Night',
  location: 'Al Amerat Pitch',
  startAt: DateTime.utc(2026, 9, 3, 18),
  status: 'completed',
  communityId: 'c1',
  communityName: 'Al Amerat FC',
  createdAt: DateTime.utc(2026, 8, 30),
  creatorName: 'Organizer',
  registrationCount: 14,
  startingPlayers: 10,
  scoreA: 3,
  scoreB: 2,
  resultCreatedAt: DateTime.utc(2026, 9, 4),
  mvpName: 'Ali Al Amri',
);

void main() {
  Future<void> pumpDrilldown(
    WidgetTester tester,
    FakeAdminAdapter adapter,
    AdminDrilldownMetric metric, {
    String title = 'Metric',
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminAnalyticsDrilldownScreen(
        metric: metric,
        title: title,
        repository: AdminRepository(adapter),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the mapper keeps what the database did not say', () {
    test('a deleted account keeps its id and loses only its labels', () {
      final user = adminDrilldownUserFromRow(const {
        'user_id': 'u9',
        'full_name': null,
        'email': null,
        'is_active': null,
        'returned_in_current_week': null,
      });

      expect(user.userId, 'u9');
      expect(user.fullName, isNull);
      expect(user.email, isNull);
      expect(user.isActive, isNull);
      // Null means the metric does not ask; false would mean "did not return".
      expect(user.returnedInCurrentWeek, isNull);
      expect(user.exists, isFalse);
    });

    test('the retention flag is read as the boolean it is', () {
      expect(
        adminDrilldownUserFromRow(const {
          'user_id': 'u1',
          'full_name': 'Ali',
          'returned_in_current_week': true,
        }).returnedInCurrentWeek,
        isTrue,
      );
      expect(
        adminDrilldownUserFromRow(const {
          'user_id': 'u2',
          'full_name': 'Sara',
          'returned_in_current_week': false,
        }).returnedInCurrentWeek,
        isFalse,
      );
    });

    test('a match with no result has no score, and one with a result does', () {
      final unplayed = adminDrilldownMatchFromRow(const {
        'match_id': 'm1',
        'community_id': 'c1',
        'location': 'Pitch',
        'start_at': '2026-09-03T18:00:00Z',
        'status': 'open',
        'match_created_at': '2026-08-30T00:00:00Z',
        'result_created_at': null,
        'score_a': null,
        'score_b': null,
      });
      expect(unplayed.hasScore, isFalse);
      expect(unplayed.resultCreatedAt, isNull);

      final played = adminDrilldownMatchFromRow(const {
        'match_id': 'm2',
        'community_id': 'c1',
        'location': 'Pitch',
        'start_at': '2026-09-03T18:00:00Z',
        'status': 'completed',
        'match_created_at': '2026-08-30T00:00:00Z',
        'result_created_at': '2026-09-04T00:00:00Z',
        'score_a': 0,
        'score_b': 0,
      });
      // Nil-nil is a real score, not a missing one.
      expect(played.hasScore, isTrue);
      expect(played.scoreA, 0);
    });

    test('a registration survives its match and user being deleted', () {
      final registration = adminDrilldownRegistrationFromRow(const {
        'event_id': 'e1',
        'created_at': '2026-09-03T18:30:00Z',
        'user_id': 'u9',
        'full_name': null,
        'match_id': 'm9',
        'match_title': null,
        'community_id': null,
        'community_name': null,
      });

      expect(registration.eventId, 'e1');
      expect(registration.userExists, isFalse);
      expect(registration.matchExists, isFalse);
    });

    test('the inspection models map safely with their optional fields absent',
        () {
      final community = adminCommunityInspectionFromRow(const {
        'community_id': 'c1',
        'name': 'Al Amerat FC',
        'join_policy': 'OPEN',
        'created_at': '2025-03-01T00:00:00Z',
      });
      expect(community.description, isNull);
      expect(community.ownerName, isNull);
      expect(community.memberCount, 0);
      expect(community.isActive, isTrue);

      final match = adminMatchInspectionFromRow(const {
        'match_id': 'm1',
        'location': 'Pitch',
        'start_at': '2026-09-03T18:00:00Z',
        'status': 'open',
        'community_id': 'c1',
        'created_at': '2026-08-30T00:00:00Z',
      });
      expect(match.title, isNull);
      expect(match.creatorName, isNull);
      expect(match.startingPlayers, isNull);
      expect(match.hasScore, isFalse);
    });
  });

  group('every Overview card opens its own records', () {
    /// Card label -> the metric it must ask for.
    const cards = {
      'Total users': AdminDrilldownMetric.totalUsers,
      'New today': AdminDrilldownMetric.newUsersToday,
      'Daily active users': AdminDrilldownMetric.dau,
      'Monthly active users': AdminDrilldownMetric.mau,
      'Weekly retention': AdminDrilldownMetric.weeklyRetention,
      'Weekly active communities': AdminDrilldownMetric.weeklyActiveCommunities,
      'Matches · 7 days': AdminDrilldownMetric.matches7d,
      'Matches · 30 days': AdminDrilldownMetric.matches30d,
      'Registrations · 7 days': AdminDrilldownMetric.registrations7d,
      'Registrations · 30 days': AdminDrilldownMetric.registrations30d,
      'Results · 7 days': AdminDrilldownMetric.results7d,
      'Results · 30 days': AdminDrilldownMetric.results30d,
    };

    for (final entry in cards.entries) {
      testWidgets('${entry.key} opens ${entry.value.name}', (tester) async {
        final adapter = FakeAdminAdapter();
        await pumpAdmin(tester, adapter);

        await tester.tap(find.text(entry.key).first);
        await tester.pumpAndSettle();

        expect(find.byType(AdminAnalyticsDrilldownScreen), findsOneWidget);
        expect(adapter.calls, contains('drilldown:${entry.value.name}:0'));
      });
    }

    testWidgets('the two headline cards open too', (tester) async {
      // Weekly Active Users appears twice -- as a headline and in Engagement --
      // and both lead to the same records.
      final adapter = FakeAdminAdapter();
      await pumpAdmin(tester, adapter);

      await tester.tap(find.text('Weekly active users').first);
      await tester.pumpAndSettle();

      expect(find.byType(AdminAnalyticsDrilldownScreen), findsOneWidget);
      expect(adapter.calls, contains('drilldown:wau:0'));
    });

    testWidgets('the figures and labels on the Overview are unchanged',
        (tester) async {
      await pumpAdmin(tester, FakeAdminAdapter());

      // Making the cards pressable must not move anything on them.
      expect(find.text('Product health'), findsOneWidget);
      expect(find.text('User growth'), findsOneWidget);
      expect(find.text('Engagement'), findsOneWidget);
      expect(find.text('Football activity'), findsOneWidget);
      expect(
        find.textContaining('Activity metrics start from this release'),
        findsOneWidget,
      );
    });

    testWidgets('a card showing zero still opens, and shows an empty list',
        (tester) async {
      // `emptyOverview` is all zeroes, which is the state of a freshly
      // deployed platform -- and exactly when an administrator most wants to
      // check whether the number is real.
      final adapter = FakeAdminAdapter();
      await pumpAdmin(tester, adapter);

      await tester.tap(find.text('Total users'));
      await tester.pumpAndSettle();

      expect(find.text('No records for this metric.'), findsOneWidget);
    });

    testWidgets('retention opens even when the percentage is unavailable',
        (tester) async {
      // No previous cohort means no percentage -- and the drill-down correctly
      // has an empty cohort to show, which is an answer rather than a fault.
      final adapter = FakeAdminAdapter();
      await pumpAdmin(tester, adapter);
      expect(find.text('—'), findsOneWidget);

      await tester.tap(find.text('Weekly retention'));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('drilldown:weeklyRetention:0'));
      expect(find.text('No records for this metric.'), findsOneWidget);
    });
  });

  group('the user drill-down', () {
    testWidgets('opens the account it names', (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.wau: [
            [_user()]
          ]
        },
        activitySummary: seenActivitySummary,
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.wau);

      expect(find.text('Ali Al Amri'), findsOneWidget);
      await tester.tap(find.text('Ali Al Amri'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
    });

    testWidgets('lists a deleted account and refuses to navigate to it',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.wau: [
            [_deletedUser]
          ]
        },
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.wau);

      // The row is present -- the Overview counted this session -- and named
      // as gone rather than by its uuid.
      expect(find.text('No longer available'), findsOneWidget);
      expect(find.textContaining('deadbeef'), findsNothing);

      await tester.tap(find.text('No longer available'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminUserDetailScreen), findsNothing);
    });

    testWidgets('a suspended account is listed with its state', (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.totalUsers: [
            [_user(active: false)]
          ]
        },
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.totalUsers);

      // No is_active filter is applied anywhere: the Overview counts every
      // account, so the list shows every account.
      expect(find.text('Suspended'), findsOneWidget);
    });
  });

  group('the retention drill-down', () {
    testWidgets('says who came back and who did not', (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.weeklyRetention: [
            [
              _user(id: 'u1', name: 'Came Back', returned: true),
              _user(id: 'u2', name: 'Stayed Away', returned: false),
            ]
          ]
        },
      );
      await pumpDrilldown(
        tester,
        adapter,
        AdminDrilldownMetric.weeklyRetention,
      );

      expect(find.text('Came Back'), findsOneWidget);
      expect(find.text('Returned'), findsOneWidget);
      expect(find.text('Stayed Away'), findsOneWidget);
      expect(find.text('Did not return'), findsOneWidget);
    });

    testWidgets('the flag is shown for no other metric', (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.wau: [
            [_user(returned: true)]
          ]
        },
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.wau);

      expect(find.text('Returned'), findsNothing);
    });
  });

  group('the community drill-down', () {
    testWidgets('opens the inspection screen, not the member screen',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.weeklyActiveCommunities: [
            [_community]
          ]
        },
        communityInspectionResult: _communityInspection,
      );
      await pumpDrilldown(
        tester,
        adapter,
        AdminDrilldownMetric.weeklyActiveCommunities,
      );

      await tester.tap(find.text('Al Amerat FC'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCommunityInspectionScreen), findsOneWidget);
      expect(adapter.calls, contains('communityInspection:c1'));
    });
  });

  group('the match and result drill-downs', () {
    testWidgets('a match opens the match inspection screen', (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.matches7d: [
            [_match]
          ]
        },
        matchInspectionResult: _matchInspection,
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.matches7d);

      await tester.tap(find.text('Friday Night'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminMatchInspectionScreen), findsOneWidget);
      expect(adapter.calls, contains('matchInspection:m1'));
    });

    testWidgets('a results metric shows the score, a matches metric does not',
        (tester) async {
      final withScore = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.results7d: [
            [_match]
          ]
        },
      );
      await pumpDrilldown(tester, withScore, AdminDrilldownMetric.results7d);
      expect(find.textContaining('3 - 2'), findsOneWidget);

      final withoutScore = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.matches7d: [
            [_match]
          ]
        },
      );
      await pumpDrilldown(
        tester,
        withoutScore,
        AdminDrilldownMetric.matches7d,
      );
      expect(find.textContaining('3 - 2'), findsNothing);
    });
  });

  group('the registration drill-down', () {
    testWidgets('one event is one row, however often the same person appears',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.registrations7d: [
            [
              _registration,
              AdminDrilldownRegistration(
                eventId: 'e2',
                createdAt: DateTime.utc(2026, 9, 2, 18),
                userId: 'u1',
                fullName: 'Ali Al Amri',
                matchId: 'm2',
                matchTitle: 'Sunday Game',
              ),
            ]
          ]
        },
      );
      await pumpDrilldown(
        tester,
        adapter,
        AdminDrilldownMetric.registrations7d,
      );

      // The Overview counts events, so the same player twice is two rows.
      expect(find.text('Ali Al Amri'), findsNWidgets(2));
    });

    testWidgets('the row opens the person and the button opens the match',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.registrations7d: [
            [_registration]
          ]
        },
        activitySummary: seenActivitySummary,
        matchInspectionResult: _matchInspection,
      );
      await pumpDrilldown(
        tester,
        adapter,
        AdminDrilldownMetric.registrations7d,
      );

      await tester.tap(find.text('Open match'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminMatchInspectionScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ali Al Amri'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
    });

    testWidgets('an event whose match is gone offers no way into it',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.registrations7d: [
            [
              AdminDrilldownRegistration(
                eventId: 'e3',
                createdAt: DateTime.utc(2026, 9, 3),
                userId: 'u1',
                fullName: 'Ali Al Amri',
                matchId: 'gone',
              ),
            ]
          ]
        },
      );
      await pumpDrilldown(
        tester,
        adapter,
        AdminDrilldownMetric.registrations7d,
      );

      // The event still counts and still lists.
      expect(find.text('Ali Al Amri'), findsOneWidget);
      expect(find.text('Open match'), findsNothing);
      expect(find.textContaining('gone'), findsNothing);
    });
  });

  group('paging', () {
    testWidgets('a full page offers more, and a short page ends the list',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.totalUsers: [
            [for (var i = 0; i < 50; i++) _user(id: 'u$i', name: 'User $i')],
            [_user(id: 'last', name: 'Last One')],
          ]
        },
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.totalUsers);

      expect(adapter.calls, ['drilldown:totalUsers:0']);

      // The list is lazy, so the footer is not built until it is scrolled to.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Load more'),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      // The second page was asked for at the offset the first page ended at.
      expect(adapter.calls, contains('drilldown:totalUsers:50'));

      await tester.scrollUntilVisible(
        find.text('Last One'),
        300,
        scrollable: scrollable,
      );
      expect(find.text('Last One'), findsOneWidget);
      // A short page means there is no more, so the button is gone -- and the
      // list is scrolled to its end, where it would be if it were there.
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('a first page shorter than a full one never offers more',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.totalUsers: [
            [_user()]
          ]
        },
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.totalUsers);

      expect(find.text('Load more'), findsNothing);
    });
  });

  group('the empty and failed states', () {
    testWidgets('an empty metric says so', (tester) async {
      await pumpDrilldown(
        tester,
        FakeAdminAdapter(),
        AdminDrilldownMetric.dau,
      );

      expect(find.text('No records for this metric.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failed first page offers a retry, and the retry reads again',
        (tester) async {
      final adapter = FakeAdminAdapter(
        pages: {
          AdminDrilldownMetric.dau: [
            [_user()]
          ]
        },
        drilldownFailure: const NetworkFailure(),
      );
      await pumpDrilldown(tester, adapter, AdminDrilldownMetric.dau);

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No records for this metric.'), findsNothing);

      adapter.drilldownFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Ali Al Amri'), findsOneWidget);
    });
  });

  group('the two inspection screens are read only', () {
    testWidgets('the community screen shows facts and offers no action',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminCommunityInspectionScreen(
          communityId: 'c1',
          repository: AdminRepository(
            FakeAdminAdapter(communityInspectionResult: _communityInspection),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Owner'), findsNWidgets(2));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);

      // Nothing a member could do, and nothing an administrator could do
      // twice: suspension stays on the lists.
      for (final action in [
        'Join',
        'Join community',
        'Suspend',
        'Reactivate',
        'Delete',
        'Edit',
      ]) {
        expect(find.text(action), findsNothing, reason: '$action is offered');
      }
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the match screen shows facts and offers no action',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AdminMatchInspectionScreen(
          matchId: 'm1',
          repository: AdminRepository(
            FakeAdminAdapter(
              matchInspectionResult: _matchInspection,
              communityInspectionResult: _communityInspection,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Al Amerat Pitch'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.textContaining('3 - 2'), findsOneWidget);

      for (final action in [
        'Join match',
        'Withdraw',
        'Generate teams',
        'Record result',
        'Delete',
        'Edit',
      ]) {
        expect(find.text(action), findsNothing, reason: '$action is offered');
      }
      expect(find.byType(FilledButton), findsNothing);

      // The community leads to inspection, never to the member screen.
      await tester.tap(find.text('Al Amerat FC'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminCommunityInspectionScreen), findsOneWidget);
    });
  });

  group('the rest of the console is unchanged', () {
    testWidgets('the five tabs keep their order', (tester) async {
      await pumpAdmin(tester, FakeAdminAdapter());

      final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
      expect(
        [for (final tab in tabs) tab.text],
        ['Overview', 'Users', 'Communities', 'Matches', 'Audit Log'],
      );
    });

    testWidgets('Users still suspends and Matches is still read only',
        (tester) async {
      await pumpAdmin(
        tester,
        FakeAdminAdapter(
          users: [adminUser()],
          matches: [
            const AdminMatchSummary(
              id: 'm1',
              location: 'Al Amerat Pitch',
              registrationCount: 10,
              title: 'Friday Night',
            ),
          ],
        ),
      );

      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(find.text('Suspend'), findsOneWidget);

      await tester.tap(find.text('Matches').last);
      await tester.pumpAndSettle();
      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });
  });
}
