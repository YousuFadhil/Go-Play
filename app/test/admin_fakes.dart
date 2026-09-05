import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_adapter.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_screen.dart';

/// Shared Admin test fixtures.
///
/// Not a test file — the runner only collects `*_test.dart`, so nothing here
/// runs on its own. It exists because the User Detail and Audit Log suites
/// drive the same console through the same port, and two hand-copied fakes of a
/// twelve-method interface would drift the first time the interface moved.

/// An empty set of figures, for the tabs a test is not looking at.
const emptyOverview = AdminAnalyticsOverview(
  totalUsers: 0,
  newUsersToday: 0,
  newUsers7d: 0,
  newUsers30d: 0,
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
);

/// An account the product has watched, for tests that only need the User
/// Detail screen to render something when they arrive on it.
final seenActivitySummary = AdminUserActivitySummary(
  userId: 'u1',
  fullName: 'Ali Al Amri',
  email: 'u1@example.com',
  createdAt: DateTime.utc(2026, 1, 15),
  isActive: true,
  lastSeenAt: DateTime.utc(2026, 9, 3),
  activeDays7d: 4,
  activeDays30d: 17,
  sessionsTotal: 63,
  platforms: const ['android'],
  latestAppVersion: '0.4.1-public-beta+2',
  communityCount: 3,
  trackedRegistrations: 22,
  matchesPlayed: 41,
  trackedWithdrawals: 5,
);

AdminUserSummary adminUser({
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

/// Answers whatever a test needs, and remembers what it was asked.
class FakeAdminAdapter implements AdminAdapter {
  FakeAdminAdapter({
    this.users = const [],
    this.communities = const [],
    this.matches = const [],
    this.audit = const [],
    this.timeline = const [],
    this.activitySummary,
    this.activityFailure,
    this.auditFailure,
    this.pages = const {},
    this.drilldownFailure,
    this.communityInspectionResult,
    this.matchInspectionResult,
    this.inspectionFailure,
  });

  List<AdminUserSummary> users;
  List<AdminCommunitySummary> communities;
  List<AdminMatchSummary> matches;
  List<AdminAuditEntry> audit;
  List<AdminUserActivityEvent> timeline;

  /// What the detail screen is given. Null means no test asked for one, and a
  /// call is then a mistake worth failing loudly on.
  AdminUserActivitySummary? activitySummary;

  /// Set to make the detail reads fail; cleared to let a retry succeed.
  Failure? activityFailure;
  Failure? auditFailure;

  /// Drill-down pages, keyed by the metric that asks for them.
  ///
  /// A `List<List<…>>` rather than a flat list, because paging is the thing
  /// most worth testing here: entry `n` is what the `n`th call returns, so a
  /// test can hand out a full page followed by a short one and watch the
  /// screen stop asking.
  Map<AdminDrilldownMetric, List<List<Object>>> pages = const {};

  /// What every drill-down read should throw instead of answering. Cleared to
  /// let a retry succeed.
  Failure? drilldownFailure;

  AdminCommunityInspection? communityInspectionResult;
  AdminMatchInspection? matchInspectionResult;
  Failure? inspectionFailure;

  final List<String> calls = [];

  int auditCalls = 0;

  /// One page for [metric], or an empty list once the fixture runs out.
  List<T> _page<T>(AdminDrilldownMetric metric, int offset) {
    calls.add('drilldown:${metric.name}:$offset');
    if (drilldownFailure != null) throw drilldownFailure!;
    final configured = pages[metric] ?? const [];
    // Which page this offset is asking for, at the screen's own page size.
    final index = offset ~/ 50;
    if (index >= configured.length) return const [];
    return configured[index].cast<T>();
  }

  @override
  Future<bool> isSystemAdmin() async => true;

  @override
  Future<AdminAnalyticsOverview> analyticsOverview() async {
    calls.add('analyticsOverview');
    return emptyOverview;
  }

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
  Future<AdminUserActivitySummary> userActivitySummary(String userId) async {
    calls.add('userActivitySummary:$userId');
    if (activityFailure != null) throw activityFailure!;
    return activitySummary!;
  }

  @override
  Future<List<AdminUserActivityEvent>> userActivityTimeline(
    String userId,
  ) async {
    calls.add('userActivityTimeline:$userId');
    if (activityFailure != null) throw activityFailure!;
    return timeline;
  }

  @override
  Future<List<AdminAuditEntry>> listAuditLog() async {
    calls.add('listAuditLog');
    auditCalls++;
    if (auditFailure != null) throw auditFailure!;
    return audit;
  }

  @override
  Future<List<AdminDrilldownUser>> drilldownUsers(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) async =>
      _page<AdminDrilldownUser>(metric, offset);

  @override
  Future<List<AdminDrilldownCommunity>> drilldownCommunities(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) async =>
      _page<AdminDrilldownCommunity>(metric, offset);

  @override
  Future<List<AdminDrilldownMatch>> drilldownMatches(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) async =>
      _page<AdminDrilldownMatch>(metric, offset);

  @override
  Future<List<AdminDrilldownRegistration>> drilldownRegistrations(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) async =>
      _page<AdminDrilldownRegistration>(metric, offset);

  @override
  Future<AdminCommunityInspection> communityInspection(
    String communityId,
  ) async {
    calls.add('communityInspection:$communityId');
    if (inspectionFailure != null) throw inspectionFailure!;
    return communityInspectionResult!;
  }

  @override
  Future<AdminMatchInspection> matchInspection(String matchId) async {
    calls.add('matchInspection:$matchId');
    if (inspectionFailure != null) throw inspectionFailure!;
    return matchInspectionResult!;
  }

  @override
  Future<void> suspendUser(String id, String reason) async {
    calls.add('suspendUser:$id:$reason');
  }

  @override
  Future<void> reactivateUser(String id) async =>
      calls.add('reactivateUser:$id');

  @override
  Future<void> suspendCommunity(String id, String reason) async {
    calls.add('suspendCommunity:$id:$reason');
  }

  @override
  Future<void> reactivateCommunity(String id) async =>
      calls.add('reactivateCommunity:$id');
}

/// The whole console, on a surface tall enough that nothing under test is
/// scrolled out of reach.
Future<void> pumpAdmin(
  WidgetTester tester,
  FakeAdminAdapter adapter, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
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
