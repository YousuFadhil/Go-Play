import 'admin_models.dart';

/// The administration screens' port into the data provider.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). [isSystemAdmin] reports what the database says
/// and nothing more: what to do when the answer cannot be obtained is a
/// permission decision, and an adapter does not make those (OP-2).
abstract interface class AdminAdapter {
  Future<bool> isSystemAdmin();

  /// Every figure on the Overview dashboard, from one call. The RPC beneath it
  /// returns counts only -- there is no way to ask it what one person did.
  Future<AdminAnalyticsOverview> analyticsOverview();

  Future<List<AdminUserSummary>> listUsers(String? search);

  Future<List<AdminCommunitySummary>> listCommunities(String? search);

  Future<List<AdminMatchSummary>> listMatches(String? search);

  /// One account in figures, for the detail screen.
  Future<AdminUserActivitySummary> userActivitySummary(String userId);

  /// That account's recent activity, newest first. The row count is the
  /// database's decision, not a page the caller assembles.
  Future<List<AdminUserActivityEvent>> userActivityTimeline(String userId);

  /// The administrative audit trail, newest first. Read-only: there is no
  /// write, edit or undo counterpart, here or in the database.
  Future<List<AdminAuditEntry>> listAuditLog();

  /// The records behind one Overview figure (migration `0069`).
  ///
  /// [offset] pages a list the database orders; the page size is the
  /// database's own clamp, not something a caller negotiates. Each returns
  /// exactly the population its metric counted, deleted records included.
  Future<List<AdminDrilldownUser>> drilldownUsers(
    AdminDrilldownMetric metric, {
    int offset,
  });

  Future<List<AdminDrilldownCommunity>> drilldownCommunities(
    AdminDrilldownMetric metric, {
    int offset,
  });

  Future<List<AdminDrilldownMatch>> drilldownMatches(
    AdminDrilldownMetric metric, {
    int offset,
  });

  Future<List<AdminDrilldownRegistration>> drilldownRegistrations(
    AdminDrilldownMetric metric, {
    int offset,
  });

  /// One community or one match, read only. Neither grants the caller a
  /// community role, and neither has a mutation counterpart.
  Future<AdminCommunityInspection> communityInspection(String communityId);

  Future<AdminMatchInspection> matchInspection(String matchId);

  /// Suspends an account. [reason] is required by the database and is passed
  /// through already trimmed -- what counts as a reason is a product rule and
  /// stays above this layer (OP-2).
  Future<void> suspendUser(String id, String reason);

  Future<void> reactivateUser(String id);

  Future<void> suspendCommunity(String id, String reason);

  Future<void> reactivateCommunity(String id);
}

// Permanent delete is deliberately absent from this port. The `admin_delete_*`
// RPCs still exist in the database and are untouched, but the normal Admin
// console no longer offers them: suspension is the reversible action the
// product asks for, and a client method nothing calls is a door left open.
