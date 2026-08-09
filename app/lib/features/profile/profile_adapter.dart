import 'dart:typed_data';

import '../auth/auth_models.dart';
import 'profile_models.dart';

/// The profile aggregate's port into the data provider: the signed-in player's
/// own profile, and the writes that keep it current.
///
/// Domain Models only (OP-3); implementations raise a `Failure` rather than a
/// provider exception (OP-5). Nothing here decides anything (OP-2): whether a
/// date is acceptable, whether a secondary position may repeat the primary and
/// what a valid phone number looks like are answered above this layer, and who
/// may write the row is answered by RLS below it.
///
/// The email and the password are **not** here. They are Auth credentials, and
/// `AuthAdapter` is the port that owns identity; a second path to them would be
/// a second answer to who the account belongs to.
abstract interface class ProfileAdapter {
  /// The signed-in player's profile.
  Future<PlayerProfile> fetchMyProfile();

  /// Replaces the signed-in player's playing inputs.
  ///
  /// The three fields §4.1 leaves to the player and no others: `overall_rating`
  /// is system-managed (`OP-1`) and is never written from here. A null
  /// [secondaryPosition] clears the column — that is what "no secondary
  /// position" is stored as, and no invented value stands in for it.
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  });

  /// Replaces the signed-in player's name and contact number.
  ///
  /// [phone] arrives in its stored form; composing it from what the player typed
  /// is a product rule and stays above this layer (OP-2).
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  });

  /// Stores [bytes] as the signed-in player's picture and returns where it can
  /// be fetched from.
  ///
  /// [fileExtension] is the encoding the bytes are in (`jpg`, `png`, `webp`),
  /// which the store needs to serve them back with the right content type. The
  /// returned URL is what [PlayerProfile.avatarUrl] then reports.
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  });

  /// Removes the signed-in player's picture. A player with none is already in
  /// the state this asks for, so it is not an error.
  Future<void> removeMyAvatar();
}
