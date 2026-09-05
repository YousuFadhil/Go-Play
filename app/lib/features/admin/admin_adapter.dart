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
