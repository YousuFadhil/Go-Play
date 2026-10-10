import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/settings/account_deletion_adapter.dart';
import '../../features/settings/account_deletion_models.dart';
import 'mappers/account_deletion_mapper.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the account-deletion port.
///
/// The preview is an RPC that answers about `auth.uid()`. The deletion goes through the
/// `delete-account` Edge Function, which first removes the profile picture from Storage
/// (which no SQL can do) and then calls `delete_my_account`: one database transaction
/// that deletes the Auth user itself. The function is called with the signed-in user's own
/// token and the request names no account -- the server knows who is asking.
class SupabaseAccountDeletionAdapter implements AccountDeletionAdapter {
  SupabaseAccountDeletionAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  @override
  Future<MyAccountDeletionPreview> previewMyDeletion() => guarded(
        () async {
          final result = await _client.rpc('preview_my_account_deletion');
          if (result is! Map) throw const InfrastructureFailure();
          return myAccountDeletionPreviewFromJson(result.cast<String, dynamic>());
        },
        operation: 'rpc preview_my_account_deletion',
      );

  /// **If the function answered 2xx, the account is deleted.** The answer is not read
  /// beyond that: a shape this build does not recognise must never be mistaken for a
  /// deletion that failed.
  @override
  Future<void> deleteMyAccount() => guarded(
        () async {
          await _client.functions.invoke(
            'delete-account',
            body: const <String, dynamic>{},
          );
        },
        operation: 'function delete-account',
      );
}
