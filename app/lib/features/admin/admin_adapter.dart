import '../auth/auth_models.dart' show PlayerPosition;
import '../profile/profile_models.dart' show ProfileVisibility;
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

  /// The signed-in account's id, or null without a session. Reads the session
  /// and asks the database nothing: it only lets the console leave out an edit
  /// the database would refuse with `CANNOT_MODIFY_SELF` anyway.
  String? get currentUserId;

  /// One account's data and settings (migration `0095`). Raises
  /// `USER_NOT_FOUND` rather than returning nothing.
  Future<AdminUserAccount> userAccount(String userId);

  /// The five account edits (migration `0095`), one per owner operation. Each
  /// sets its whole group; there is deliberately no patch call. [reason] is
  /// optional and arrives already trimmed, or null.
  ///
  /// A null [dateOfBirth], [secondaryPosition] or [wilayatCode] clears the
  /// value; nothing else in any of them may be null.
  Future<void> updateUserAccount(
    String userId, {
    required String fullName,
    required String phone,
    String? reason,
  });

  Future<void> updateUserPlayerProfile(
    String userId, {
    required DateTime? dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
    String? reason,
  });

  Future<void> updateUserPrivacy(
    String userId, {
    required ProfileVisibility visibility,
    required bool ageVisible,
    String? reason,
  });

  Future<void> updateUserDefaultWilayat(
    String userId, {
    required int? wilayatCode,
    String? reason,
  });

  Future<void> updateUserPushPreferences(
    String userId, {
    required bool matchPush,
    required bool communityPush,
    required bool muteAll,
    String? reason,
  });

  /// The read-only previews of merging two accounts and of deleting one
  /// (migration `0096`). They describe what each would collide with and write
  /// nothing, not even an audit event. Neither has an execute counterpart here
  /// or in the database.
  Future<AdminMergePreview> previewAccountMerge({
    required String retainedUserId,
    required String sourceUserId,
  });

  Future<AdminDeletionPreview> previewAccountDeletion(String userId);

  /// Merges the source account into the retained one and removes the source for
  /// good -- its profile, its sign-in identities and its sessions -- in one
  /// database transaction (migration `0101`). **Permanent and irreversible.**
  ///
  /// [resolutions] is the administrator's explicit choice for every match both
  /// accounts took part in. The database refuses, and changes nothing, when a
  /// choice is missing, when a blocker has appeared since the preview, or when the
  /// choice would discard goals, an MVP award, a result or a confirmed lineup.
  Future<AdminMergeResult> mergeAccounts({
    required String retainedUserId,
    required String sourceUserId,
    required List<AdminMergeResolution> resolutions,
  });
}

// Permanent delete is deliberately absent from this port. The `admin_delete_*`
// RPCs still exist in the database and are untouched, but the normal Admin
// console no longer offers them: suspension is the reversible action the
// product asks for, and a client method nothing calls is a door left open.
//
// `mergeAccounts` above is the one permanent action the console offers, and only
// because the Product Owner approved it: one account into another, with the source
// removed in the same transaction, behind a typed confirmation.
