import 'dart:typed_data';

import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_profile_adapter.dart';
import '../auth/auth_models.dart';
import 'profile_adapter.dart';
import 'profile_models.dart';

/// Data access for the signed-in player's own profile.
///
/// Two kinds of thing live here and are deliberately written separately. The
/// playing inputs (§4.1) are what the engine reads and what a refusal to
/// generate teams points at; the account fields are who the player is to
/// everybody else. Saving one has never been a reason to rewrite the other, and
/// a single call that wrote both would make every name change a rewrite of the
/// date of birth the engine depends on.
class ProfileRepository {
  ProfileRepository([ProfileAdapter? adapter])
      : _adapter = adapter ?? SupabaseProfileAdapter();

  final ProfileAdapter _adapter;

  /// The player's stored profile, missing date of birth and all.
  Future<PlayerProfile> fetchMyProfile() => _adapter.fetchMyProfile();

  /// Another player's profile, as this viewer is allowed to see it.
  ///
  /// A straight pass-through, and deliberately: whether the viewer may open the
  /// profile is the server's decision (`player_profile`, migration `0043`), and
  /// a second answer here would be a rule the database does not know about. A
  /// refusal arrives as an [AuthorizationFailure] carrying
  /// [FailureReason.profileNotVisible].
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      _adapter.fetchPlayerProfile(userId);

  /// Stores the player's privacy preferences: who may open their profile, and
  /// whether other players are given the date their age is derived from.
  Future<void> saveMyPrivacy(ProfilePrivacy privacy) =>
      _adapter.updateMyPrivacy(privacy);

  /// Stores the player's playing inputs.
  ///
  /// A date of birth is required — the engine refuses to invent one (§4.3) and
  /// completing it is what the accounts predating the field are here for. A
  /// secondary position is optional, and null clears it (`BTGE-SC-6`).
  ///
  /// The rating is not a parameter. `OP-1` makes it system-managed, so there is
  /// nothing here for a caller to pass and nothing for this to write.
  ///
  /// Throws [ValidationFailure] when the date of birth has not happened yet or
  /// the secondary position repeats the primary.
  Future<void> saveMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) async {
    validateProfileInputs(
      dateOfBirth: dateOfBirth,
      primaryPosition: primaryPosition,
      secondaryPosition: secondaryPosition,
    );
    await _adapter.updateMyProfile(
      dateOfBirth: dateOnly(dateOfBirth),
      primaryPosition: primaryPosition,
      secondaryPosition: secondaryPosition,
    );
  }

  /// Stores the player's name and contact number.
  ///
  /// [phone] is already in its stored form: the screen composes it from the
  /// eight-digit local number through `AuthService`, which is where the rule
  /// lives.
  ///
  /// Throws [ValidationFailure] when the name is too short to identify anybody.
  Future<void> saveMyAccount({
    required String fullName,
    required String phone,
  }) async {
    validateAccountInputs(fullName: fullName);
    await _adapter.updateMyAccount(fullName: fullName.trim(), phone: phone);
  }

  /// Stores [bytes] as the player's picture, returning where it can be fetched.
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      _adapter.uploadMyAvatar(bytes: bytes, fileExtension: fileExtension);

  /// Removes the player's picture.
  Future<void> removeMyAvatar() => _adapter.removeMyAvatar();
}
