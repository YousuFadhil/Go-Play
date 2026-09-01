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
/// The reads go through functions and the writes go to `users` directly.
///
/// That split follows the privileges. Migration `0056` revoked SELECT on
/// `users.phone`, so a caller — including the column's owner — can no longer
/// read it through the table or through a `security_invoker` view over it. Both
/// reads here are therefore `security definer` functions with fixed column
/// lists: `my_profile` for the owner's own row, `player_profile` for anybody's
/// football profile.
///
/// The writes are unchanged and stay on the table. `users_update_own_profile`
/// allows a write only where `auth.uid() = id`, and migration `0022`'s column
/// grant is what decides *which* columns it may touch — `phone` among them.
/// Writing a column is not reading it, so `0056` did not touch that path.
class SupabaseProfileAdapter implements ProfileAdapter {
  SupabaseProfileAdapter([SupabaseClient? client])
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  /// Reads the signed-in player's own profile, through `my_profile`
  /// (migration `0055`).
  ///
  /// This was a projection of `v_user_profile`, and it stopped being one when
  /// the phone number stopped being a column any caller may select. The view is
  /// `security_invoker = on`, so it can only return what the caller is allowed
  /// to read — and since `0056` that no longer includes `phone` or
  /// `date_of_birth` for anybody, the owner included.
  ///
  /// The function takes no user id. That is the whole of the authorization
  /// story: there is no argument to point at somebody else, so this call cannot
  /// express the request the boundary is there to refuse.
  @override
  Future<PlayerProfile> fetchMyProfile() => guarded(
        () async {
          final rows =
              await _client.rpc('my_profile') as List<dynamic>;
          if (rows.isEmpty) throw const NotFoundFailure();
          final row = rows.first as Map<String, dynamic>;
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
        },
        operation: 'rpc my_profile',
      );

  /// Another player's football profile, through `player_profile`
  /// (migrations `0043`, `0056`).
  ///
  /// An RPC rather than a table read, because the columns it returns are a
  /// fixed list decided by the server rather than a projection chosen here.
  /// That is what makes the boundary hold: there is no phone, no email, no
  /// authentication identifier and — since `0056` — no date of birth in the
  /// answer, whatever this layer asks for.
  ///
  /// It no longer asks whether the two players share a community. A football
  /// profile is football data, and every active player's is readable by every
  /// signed-in player.
  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) => guarded(
        () async {
          final rows = await _client.rpc(
            'player_profile',
            params: {'p_user_id': userId},
          ) as List<dynamic>;
          if (rows.isEmpty) throw const NotFoundFailure();
          final row = rows.first as Map<String, dynamic>;
          return playerProfileViewFromRow(
            row,
            avatarUrl: SupabaseAvatars.publicUrl(
              _client,
              row['avatar_path'] as String?,
            ),
          );
        },
        operation: 'rpc player_profile',
      );

  /// Writes the two privacy columns, and only those two.
  ///
  /// The same shape as every other write on this row: migration `0043` grants
  /// the two columns and `users_update_own_profile` confines the statement to
  /// the caller's own row, so the `eq` below says which row is meant rather than
  /// who may have it.
  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) => guarded(() async {
        await _client
            .from('users')
            .update(privacyUpdateToRow(privacy))
            .eq('id', _currentUserId);
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
