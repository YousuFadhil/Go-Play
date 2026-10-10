import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_admin_adapter.dart';
import '../auth/auth_models.dart' show PlayerPosition;
import '../profile/profile_models.dart' show ProfileVisibility;
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

  /// The drill-down and inspection reads added by `0069`.
  ///
  /// None of them swallows a failure, for the reason the three above do not:
  /// these are reads, and a screen handed an empty list where the truth was
  /// "the request failed" would show an administrator a clean, wrong answer
  /// instead of a retry. Only [isSystemAdmin] answers a failure with a
  /// decision, because a permission question that cannot be answered has to
  /// mean no.
  Future<List<AdminDrilldownUser>> drilldownUsers(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      _adapter.drilldownUsers(metric, offset: offset);

  Future<List<AdminDrilldownCommunity>> drilldownCommunities(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      _adapter.drilldownCommunities(metric, offset: offset);

  Future<List<AdminDrilldownMatch>> drilldownMatches(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      _adapter.drilldownMatches(metric, offset: offset);

  Future<List<AdminDrilldownRegistration>> drilldownRegistrations(
    AdminDrilldownMetric metric, {
    int offset = 0,
  }) =>
      _adapter.drilldownRegistrations(metric, offset: offset);

  Future<AdminCommunityInspection> communityInspection(String communityId) =>
      _adapter.communityInspection(communityId);

  Future<AdminMatchInspection> matchInspection(String matchId) =>
      _adapter.matchInspection(matchId);

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

  /// The signed-in account's id, for the one question the console asks of it:
  /// is this account me.
  String? get currentUserId => _adapter.currentUserId;

  /// One account's data and settings (migration `0095`). A failure is not
  /// swallowed, for the reason the other reads do not: a section that received
  /// a blank where the truth was "the request failed" would show an
  /// administrator a clean, wrong answer instead of a retry.
  Future<AdminUserAccount> userAccount(String userId) =>
      _adapter.userAccount(userId);

  /// The five account edits. The reason is optional: it is trimmed here and a
  /// blank one is sent as no reason, so the database stores an absence rather
  /// than whitespace. Everything else is passed through; what a valid value is
  /// stays a database rule, and the edit screen has already checked it.
  Future<void> updateUserAccount(
    String userId, {
    required String fullName,
    required String phone,
    String? reason,
  }) =>
      _adapter.updateUserAccount(
        userId,
        fullName: fullName,
        phone: phone,
        reason: _reason(reason),
      );

  Future<void> updateUserPlayerProfile(
    String userId, {
    required DateTime? dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
    String? reason,
  }) =>
      _adapter.updateUserPlayerProfile(
        userId,
        dateOfBirth: dateOfBirth,
        primaryPosition: primaryPosition,
        secondaryPosition: secondaryPosition,
        reason: _reason(reason),
      );

  Future<void> updateUserPrivacy(
    String userId, {
    required ProfileVisibility visibility,
    required bool ageVisible,
    String? reason,
  }) =>
      _adapter.updateUserPrivacy(
        userId,
        visibility: visibility,
        ageVisible: ageVisible,
        reason: _reason(reason),
      );

  Future<void> updateUserDefaultWilayat(
    String userId, {
    required int? wilayatCode,
    String? reason,
  }) =>
      _adapter.updateUserDefaultWilayat(
        userId,
        wilayatCode: wilayatCode,
        reason: _reason(reason),
      );

  Future<void> updateUserPushPreferences(
    String userId, {
    required bool matchPush,
    required bool communityPush,
    required bool muteAll,
    String? reason,
  }) =>
      _adapter.updateUserPushPreferences(
        userId,
        matchPush: matchPush,
        communityPush: communityPush,
        muteAll: muteAll,
        reason: _reason(reason),
      );

  /// The read-only previews (migration `0096`). Reads, so a failure is not
  /// swallowed: a preview that failed must show as failed, never as "nothing in
  /// the way".
  ///
  /// The same account twice is not a merge. It is refused here, as a rejected
  /// Future like every other failure in this layer, so the database is not asked.
  Future<AdminMergePreview> previewAccountMerge({
    required String retainedUserId,
    required String sourceUserId,
  }) async {
    if (retainedUserId == sourceUserId) throw const ValidationFailure();
    return _adapter.previewAccountMerge(
      retainedUserId: retainedUserId,
      sourceUserId: sourceUserId,
    );
  }

  Future<AdminDeletionPreview> previewAccountDeletion(String userId) =>
      _adapter.previewAccountDeletion(userId);

  /// The permanent merge (migration `0101`). **Not a read: a failure is a failure
  /// to report, never to swallow, and a success is irreversible.** The same
  /// account twice is refused here, as a rejected Future, so the database is not
  /// asked; everything else is the database's to refuse, inside its transaction.
  Future<AdminMergeResult> mergeAccounts({
    required String retainedUserId,
    required String sourceUserId,
    required List<AdminMergeResolution> resolutions,
  }) async {
    if (retainedUserId == sourceUserId) throw const ValidationFailure();
    return _adapter.mergeAccounts(
      retainedUserId: retainedUserId,
      sourceUserId: sourceUserId,
      resolutions: resolutions,
    );
  }

  /// The permanent deletion (migration `0102`). **Not a read: a failure is a failure to
  /// report, never to swallow, and a success is irreversible.** Who may do it, and
  /// whether anything stands in the way, is the server's to decide.
  Future<AdminDeletionResult> deleteAccount(String userId) =>
      _adapter.deleteAccount(userId: userId);

  static String? _reason(String? reason) {
    final trimmed = reason?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
