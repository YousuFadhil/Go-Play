import '../../../features/auth/auth_models.dart';
import '../../../features/profile/profile_models.dart';
import 'auth_mapper.dart';

// Conversion between the `users` row and the player's own profile model.
//
// Every column this aggregate reads or writes appears here and nowhere else
// (OP-3). The position vocabulary and the date encoding are shared with
// registration, which writes the same fields through Auth metadata, so both
// come from `auth_mapper.dart` rather than being restated.

/// Reads the signed-in player's own profile row.
///
/// A null date of birth or secondary position stays null. Migration `0018` left
/// both nullable on purpose and §4.3 forbids filling either in, so nothing here
/// closes a gap the player has not closed themselves.
///
/// [avatarUrl] is composed by the adapter from `avatar_path`, because the bucket
/// and the host are provider knowledge and a row does not carry them. A player
/// with no picture gets null, which is what migration `0031` stores for one.
PlayerProfile playerProfileFromRow(
  Map<String, dynamic> row, {
  String? avatarUrl,
}) {
  final dateOfBirth = row['date_of_birth'] as String?;
  final secondary = row['secondary_position'] as String?;
  return PlayerProfile(
    fullName: row['full_name'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    primaryPosition: playerPositionFromDb(row['primary_position'] as String),
    dateOfBirth: dateOfBirth == null ? null : DateTime.parse(dateOfBirth),
    secondaryPosition:
        secondary == null ? null : playerPositionFromDb(secondary),
    avatarUrl: avatarUrl,
  );
}

/// The columns a player writes on their own account.
///
/// Two, and neither of them is a playing input: the name and the number are who
/// the player is to everyone else, and are written by their own call so that
/// correcting a typo in a name never rewrites the date of birth the engine
/// depends on.
Map<String, dynamic> accountUpdateToRow({
  required String fullName,
  required String phone,
}) =>
    {'full_name': fullName, 'phone': phone};

/// The one column an uploaded picture writes. Null clears it, which is how "no
/// picture" is stored — migration `0031` chose the absence itself over a
/// placeholder path.
Map<String, dynamic> avatarUpdateToRow(String? path) => {'avatar_path': path};

/// The columns a player writes on their own profile — these three and no
/// others.
///
/// `overall_rating` is absent by construction rather than by convention: a
/// payload built here cannot carry it, so no screen above can send one. `OP-1`
/// makes it system-managed and the column default sets it to 5.0.
Map<String, dynamic> profileUpdateToRow({
  required DateTime dateOfBirth,
  required PlayerPosition primaryPosition,
  required PlayerPosition? secondaryPosition,
}) =>
    {
      'date_of_birth': dateOnlyToDb(dateOfBirth),
      'primary_position': playerPositionToDb(primaryPosition),
      // Null is how "no secondary position" is stored. Migration `0018` chose
      // that over a `NONE` value, so clearing writes the absence itself.
      'secondary_position': secondaryPosition == null
          ? null
          : playerPositionToDb(secondaryPosition),
    };
