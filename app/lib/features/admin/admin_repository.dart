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

  Future<List<AdminUserSummary>> listUsers(String? search) =>
      _adapter.listUsers(search);

  Future<List<AdminCommunitySummary>> listCommunities(String? search) =>
      _adapter.listCommunities(search);

  Future<List<AdminMatchSummary>> listMatches(String? search) =>
      _adapter.listMatches(search);

  Future<void> deleteUser(String id) => _adapter.deleteUser(id);

  Future<void> deleteCommunity(String id) => _adapter.deleteCommunity(id);

  Future<void> deleteMatch(String id) => _adapter.deleteMatch(id);
}
