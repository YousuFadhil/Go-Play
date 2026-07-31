import 'admin_models.dart';

/// The administration screens' port into the data provider.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). [isSystemAdmin] reports what the database says
/// and nothing more: what to do when the answer cannot be obtained is a
/// permission decision, and an adapter does not make those (OP-2).
abstract interface class AdminAdapter {
  Future<bool> isSystemAdmin();

  Future<List<AdminUserSummary>> listUsers(String? search);

  Future<List<AdminCommunitySummary>> listCommunities(String? search);

  Future<List<AdminMatchSummary>> listMatches(String? search);

  Future<void> deleteUser(String id);

  Future<void> deleteCommunity(String id);

  Future<void> deleteMatch(String id);
}
