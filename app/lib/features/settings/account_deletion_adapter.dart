import 'account_deletion_models.dart';

/// The port for the signed-in user deleting their own account (migration `0102`).
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Nothing here decides anything (OP-2): who may delete,
/// and whether anything blocks it, is answered by the database, twice.
abstract interface class AccountDeletionAdapter {
  /// Whether anything blocks deleting the signed-in user's own account, and which
  /// communities they own and must hand over first.
  Future<MyAccountDeletionPreview> previewMyDeletion();

  /// Deletes the signed-in user's own account for good -- the sign-in, the profile
  /// data, the picture and the personal records -- in one database transaction, and
  /// keeps the football history under "Deleted Player". **Permanent and
  /// irreversible.** There is no argument: the account is the caller's, and the
  /// server knows who that is.
  ///
  /// A returned future is a deletion that happened. A failure the database
  /// confirms rolled back is a failure to report; one that may have reached it is
  /// worded as "may or may not have been performed".
  Future<void> deleteMyAccount();
}
