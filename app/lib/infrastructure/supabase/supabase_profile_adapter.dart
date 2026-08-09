import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';
import '../../features/auth/auth_models.dart';
import '../../features/profile/profile_adapter.dart';
import '../../features/profile/profile_models.dart';
import 'mappers/profile_mapper.dart';
import 'supabase_avatars.dart';
import 'supabase_bootstrap.dart';
import 'supabase_failure_mapper.dart';

/// Supabase implementation of the profile port.
///
/// The read goes through `v_user_profile` (migration `0025`, extended by `0031`)
/// and the writes go to `users` directly. That split is the point of the read
/// model: a view is read-only, and the write still belongs to the table whose
/// policy governs it.
///
/// Authorization is unchanged by the move. `v_user_profile` is
/// `security_invoker = on`, so the caller's own policies decide what it
/// returns — `authenticated_select_active_users` on `users` exactly as before,
/// and the view restates none of it. `users_update_own_profile` still allows a
/// write only where `auth.uid() = id`, and migration `0022`'s column grant is
/// what decides *which* columns that write may touch. The `eq` below says which
/// row is meant, not who may have it.
class SupabaseProfileAdapter implements ProfileAdapter {
  SupabaseProfileAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// The profile columns this aggregate deals in. `overall_rating` is not among
  /// them: it is neither shown nor written, so it is not read either — the view
  /// carries it, and leaving it out of the projection keeps that true.
  static const _columns = 'full_name, phone, date_of_birth, primary_position, '
      'secondary_position, avatar_path';

  /// Reads the profile from the read model.
  ///
  /// The view names the key `user_id` where the table calls it `id`; the other
  /// columns keep their names.
  @override
  Future<PlayerProfile> fetchMyProfile() => guarded(() async {
        final row = await _client
            .from('v_user_profile')
            .select(_columns)
            .eq('user_id', _currentUserId)
            .maybeSingle();
        if (row == null) throw const NotFoundFailure();
        return playerProfileFromRow(
          row,
          // Versioned: this is the player looking at their own profile, which
          // is exactly where a picture they have just changed must not be the
          // one the cache still holds.
          avatarUrl: SupabaseAvatars.publicUrl(
            _client,
            row['avatar_path'] as String?,
            version: true,
          ),
        );
      });

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) =>
      guarded(() async {
        await _client
            .from('users')
            .update(profileUpdateToRow(
              dateOfBirth: dateOfBirth,
              primaryPosition: primaryPosition,
              secondaryPosition: secondaryPosition,
            ))
            .eq('id', _currentUserId);
      });

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) =>
      guarded(() async {
        await _client
            .from('users')
            .update(accountUpdateToRow(fullName: fullName, phone: phone))
            .eq('id', _currentUserId);
      });

  /// Uploads the picture and points the profile row at it.
  ///
  /// The object name is `<user id>/avatar.<ext>`, which is two things at once:
  /// the folder is what the storage policy checks ownership against, and the
  /// fixed file name means a player has one picture rather than an accumulating
  /// pile of them. `upsert` is therefore required — the second upload replaces
  /// the first rather than colliding with it.
  ///
  /// A cache-busting query is appended to the returned URL. The path does not
  /// change between uploads, so without it every client that already fetched the
  /// old picture would keep showing it.
  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      guarded(() async {
        final path = SupabaseAvatars.pathFor(_currentUserId, fileExtension);
        await _client.storage.from(SupabaseAvatars.bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: SupabaseAvatars.contentTypeFor(fileExtension),
              ),
            );
        await _client
            .from('users')
            .update(avatarUpdateToRow(path))
            .eq('id', _currentUserId);
        return SupabaseAvatars.publicUrl(_client, path, version: true)!;
      });

  /// Clears the column first, then removes the object.
  ///
  /// That order is deliberate. A cleared column with the object still in the
  /// bucket is a player with no picture and a stray file; the reverse is a
  /// profile pointing at something that is not there, which every screen showing
  /// an avatar would render as a broken image.
  @override
  Future<void> removeMyAvatar() => guarded(() async {
        final id = _currentUserId;
        final row = await _client
            .from('v_user_profile')
            .select('avatar_path')
            .eq('user_id', id)
            .maybeSingle();
        final path = row?['avatar_path'] as String?;
        if (path == null) return;

        await _client
            .from('users')
            .update(avatarUpdateToRow(null))
            .eq('id', id);
        await _client.storage.from(SupabaseAvatars.bucket).remove([path]);
      });

  /// The signed-in user's id, or a refusal.
  ///
  /// A profile is somebody's, so without a session there is no row to name.
  /// [guarded] passes this through unchanged (OP-5).
  String get _currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthenticationFailure();
    return id;
  }
}
