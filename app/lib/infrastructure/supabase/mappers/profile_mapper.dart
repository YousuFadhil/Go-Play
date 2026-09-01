import '../../../features/auth/auth_models.dart';
import '../../../features/profile/profile_models.dart';
import 'auth_mapper.dart';
import 'result_mapper.dart';

// Conversion between the `users` row and the player's own profile model.
//
// Every column this aggregate reads or writes appears here and nowhere else
// (OP-3). The position vocabulary and the date encoding are shared with
// registration, which writes the same fields through Auth metadata, so both
// come from `auth_mapper.dart` rather than being restated.

/// Reads the signed-in player's own profile row (`my_profile`, migration
/// `0055`).
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
    privacy: profilePrivacyFromRow(row),
  );
}

/// The two privacy columns migration `0043` added, read off the same row.
///
/// An older row — or a projection that did not ask for them — reads as the
/// column defaults rather than as an error: `EVERYONE` with the age shown is
/// what the database stores for an account that has never been configured.
ProfilePrivacy profilePrivacyFromRow(Map<String, dynamic> row) =>
    ProfilePrivacy(
      visibility: profileVisibilityFromDb(row['profile_visibility'] as String?),
      ageVisible: row['age_visible'] as bool? ?? true,
    );

/// An unrecognised value reads as [ProfileVisibility.everyone]: that is the
/// column default and what every row carried before the setting existed.
ProfileVisibility profileVisibilityFromDb(String? value) =>
    value == 'COMMUNITY_MEMBERS'
        ? ProfileVisibility.communityMembersOnly
        : ProfileVisibility.everyone;

String profileVisibilityToDb(ProfileVisibility visibility) =>
    switch (visibility) {
      ProfileVisibility.everyone => 'EVERYONE',
      ProfileVisibility.communityMembersOnly => 'COMMUNITY_MEMBERS',
    };

/// The two columns the privacy settings write, and no others.
Map<String, dynamic> privacyUpdateToRow(ProfilePrivacy privacy) => {
      'profile_visibility': profileVisibilityToDb(privacy.visibility),
      'age_visible': privacy.ageVisible,
    };

/// Reads one row of `player_profile` (migrations `0043`, `0055`).
///
/// The function decides what the row contains, so nothing is filtered here —
/// and since `0055` there is nothing to filter: no phone, no email, no
/// authentication identifier and no date of birth is returned, so none can be
/// read out even by mistake. A column named here that the function does not
/// send would simply be absent.
PlayerProfileView playerProfileViewFromRow(
  Map<String, dynamic> row, {
  String? avatarUrl,
}) {
  final secondary = row['secondary_position'] as String?;
  return PlayerProfileView(
    userId: row['user_id'] as String,
    fullName: row['full_name'] as String? ?? '',
    primaryPosition: playerPositionFromDb(row['primary_position'] as String),
    secondaryPosition:
        secondary == null ? null : playerPositionFromDb(secondary),
    avatarUrl: avatarUrl,
    isSelf: row['is_self'] as bool? ?? false,
    statistics: playerStatisticsFromRow(row),
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
