import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_admin_adapter.dart';
import 'admin_adapter.dart';
import 'admin_models.dart';

/// Data access for the internal administration screens.
///
/// Every operation goes through an `admin_*` RPC that checks
/// `is_system_admin()` server-side. Nothing here is authorization: hiding the
/// screens is a convenience, and the database refuses regardless.
class AdminRepository {
  AdminRepository([AdminAdapter? adapter])
      : _adapter = adapter ?? SupabaseAdminAdapter();

  final AdminAdapter _adapter;

  /// Whether the signed-in account may see the administration screens at all.
  /// A question that could not be answered is answered no: a failure here must
  /// not open the door.
  Future<bool> isSystemAdmin() async {
    try {
      return await _adapter.isSystemAdmin();
    } on Failure {
      return false;
    }
  }

  /// The Overview dashboard's figures.
  ///
  /// A failure is **not** swallowed the way [isSystemAdmin]'s is. That one is a
  /// permission question, where an unanswered question has to mean no; this is
  /// a read, and a read that failed must reach the screen so it can offer a
  /// retry rather than draw a dashboard of zeroes.
  Future<AdminAnalyticsOverview> analyticsOverview() =>
      _adapter.analyticsOverview();

  Future<List<AdminUserSummary>> listUsers(String? search) =>
      _adapter.listUsers(search);

  Future<List<AdminCommunitySummary>> listCommunities(String? search) =>
      _adapter.listCommunities(search);

  Future<List<AdminMatchSummary>> listMatches(String? search) =>
      _adapter.listMatches(search);

  /// The three read paths added by `0068`.
  ///
  /// None of them swallows a failure. Like [analyticsOverview] and unlike
  /// [isSystemAdmin], these are reads rather than permission questions: a
  /// screen that received an empty list where the truth was "the request
  /// failed" would show an administrator a clean, wrong answer instead of a
  /// retry.
  Future<AdminUserActivitySummary> userActivitySummary(String userId) =>
      _adapter.userActivitySummary(userId);

  Future<List<AdminUserActivityEvent>> userActivityTimeline(String userId) =>
      _adapter.userActivityTimeline(userId);

  Future<List<AdminAuditEntry>> listAuditLog() => _adapter.listAuditLog();

  /// Suspends an account. The reason is trimmed here and refused when empty,
  /// so `REASON_REQUIRED` is a server guarantee rather than something an
  /// ordinary screen can provoke.
  /// `async` so an empty reason arrives as a rejected Future like every other
  /// failure in this layer, rather than as a synchronous throw the caller has
  /// to guard differently.
  Future<void> suspendUser(String id, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw const ValidationFailure();
    await _adapter.suspendUser(id, trimmed);
  }

  Future<void> reactivateUser(String id) => _adapter.reactivateUser(id);

  Future<void> suspendCommunity(String id, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw const ValidationFailure();
    await _adapter.suspendCommunity(id, trimmed);
  }

  Future<void> reactivateCommunity(String id) =>
      _adapter.reactivateCommunity(id);
}
