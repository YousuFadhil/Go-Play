import '../../infrastructure/supabase/supabase_account_deletion_adapter.dart';
import 'account_deletion_adapter.dart';
import 'account_deletion_models.dart';

/// Data access for the signed-in user deleting their own account.
///
/// A straight pass-through: the database decides who may delete and what blocks
/// it, and this layer adds no product reasoning of its own.
class AccountDeletionRepository {
  AccountDeletionRepository([AccountDeletionAdapter? adapter])
      : _adapter = adapter ?? SupabaseAccountDeletionAdapter();

  final AccountDeletionAdapter _adapter;

  Future<MyAccountDeletionPreview> previewMyDeletion() =>
      _adapter.previewMyDeletion();

  /// **Not a read: a failure is a failure to report, never to swallow, and a
  /// success is irreversible.**
  Future<void> deleteMyAccount() => _adapter.deleteMyAccount();
}
