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

  final List<String> calls = [];

  int auditCalls = 0;

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
