import '../../core/failures.dart';
import '../auth/auth_models.dart';
import '../results/result_models.dart';

/// A player's own profile: who they are, how to reach them, and the inputs the
/// Balanced Team Generation Engine reads (§4.1).
///
/// `overall_rating` is deliberately absent: `OP-1` makes it system-managed, the
/// database initialises it to 5.0, and a model that carried it would invite a
/// screen to write it. So is every administrative field — a role belongs to a
/// membership, not to a person.
///
/// The email is absent for a different reason. It is an Auth credential, not a
/// column of the profile row, and it is read and written through the identity
/// port; putting it here would be a second copy of it, free to disagree.
///
/// [dateOfBirth] is nullable because the schema allows it to be and the
/// accounts that predate this feature have none. §4.3 forbids inventing one, so
/// this reports what is stored and the player supplies the rest.
/// Who may open a player's profile.
///
/// **Retired by migration `0055`.** A football profile is football data and is
/// readable by every signed-in player, so `player_profile` no longer consults
/// this. The type and its column survive because dropping a column is
/// irreversible and because removing the type would churn every fake that
/// implements the port; nothing reads either to decide anything.
enum ProfileVisibility {
  /// Any signed-in player may read the non-sensitive profile.
  everyone,

  /// Only players who share an active community with the owner.
  communityMembersOnly,
}

/// What a player had decided about who sees what.
///
/// **Retired by migration `0055`**, along with the Settings controls that wrote
/// it. Both preferences described disclosures that no longer happen: a football
/// profile is readable by every signed-in player, and no date of birth leaves
/// through it for an age setting to withhold. Kept as plumbing so the stored
/// columns can still be read back, and read by nothing that decides anything.
class ProfilePrivacy {
  const ProfilePrivacy({
    required this.visibility,
    required this.ageVisible,
  });

  /// What a profile that has never been configured means: visible to everyone,
  /// with an age on it. The same defaults the column carries.
  const ProfilePrivacy.defaults()
      : visibility = ProfileVisibility.everyone,
        ageVisible = true;

  final ProfileVisibility visibility;

  /// Whether other players receive the date of birth the age is derived from.
  /// The owner always does.
  final bool ageVisible;

  ProfilePrivacy copyWith({
    ProfileVisibility? visibility,
    bool? ageVisible,
  }) =>
      ProfilePrivacy(
        visibility: visibility ?? this.visibility,
        ageVisible: ageVisible ?? this.ageVisible,
      );
}

class PlayerProfile {
  const PlayerProfile({
    required this.fullName,
    required this.phone,
    required this.primaryPosition,
    this.dateOfBirth,
    this.secondaryPosition,
    this.avatarUrl,
    this.privacy = const ProfilePrivacy.defaults(),
  });

  final String fullName;

  /// Stored in E.164 (`+968XXXXXXXX`). How an Oman number is composed is a
  /// product rule that lives in `AuthService`; this carries the result.
  final String phone;

  final PlayerPosition primaryPosition;

  /// A date, never an instant: age is derived from it as of the match date
  /// (§15, `DD-11`), and a birthday has no time of day.
  final DateTime? dateOfBirth;

  /// A missing secondary position is ordinary input, never an error
  /// (`BTGE-SC-6`).
  final PlayerPosition? secondaryPosition;

  /// Where the player's picture can be fetched, or null when they have none.
  ///
  /// A URL rather than a storage path: composing one is provider knowledge, and
  /// the adapter that knows the bucket is where it belongs. Null is the ordinary
  /// state of a new account, never an error.
  final String? avatarUrl;

  /// What this player has decided about who sees their profile and their age.
  /// Read here because this is the player's own row; it decides nothing on the
  /// client, and the server refuses a profile the viewer may not open.
  final ProfilePrivacy privacy;

  /// Whether the engine would accept this player (§4.1). Only the date of birth
  /// can be absent: the rating and the primary position are `NOT NULL`.
  bool get isComplete => dateOfBirth != null;

  /// Completed years as of [asOf], or null when no date of birth is stored.
  ///
  /// Derived, never stored (`KB-C7`): a stored number is wrong from the next
  /// birthday onwards, and the engine already derives age the same way from the
  /// same date.
  int? ageOn(DateTime asOf) {
    final birth = dateOfBirth;
    if (birth == null) return null;
    var age = asOf.year - birth.year;
    final hadBirthday = asOf.month > birth.month ||
        (asOf.month == birth.month && asOf.day >= birth.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  /// Completed years today, in the device's local time (`DD-11`).
  int? get age => ageOn(DateTime.now());
}

/// Another player's **football** profile.
///
/// A separate model from [PlayerProfile], and deliberately so. What keeps a
/// phone number, an email address, an authentication identifier and a date of
/// birth off somebody else's profile is not a screen remembering not to draw
/// them — it is that there is nowhere here to put one. The server sends a fixed
/// short list (`player_profile`, migrations `0043` and `0055`) and this is its
/// shape.
///
/// There is no date of birth and therefore no age. That is migration `0055`'s
/// boundary: a birth date is account data, and account data belongs to the
/// account's owner. A player's own age is still on their own record, which is
/// [PlayerProfile].
class PlayerProfileView {
  const PlayerProfileView({
    required this.userId,
    required this.fullName,
    required this.primaryPosition,
    required this.statistics,
    required this.isSelf,
    this.secondaryPosition,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final PlayerPosition primaryPosition;
  final PlayerPosition? secondaryPosition;

  /// The career record: the same counters the player's own profile shows.
  final PlayerStatistics statistics;

  /// Whether this is the viewer looking at themselves, which the server decides
  /// from the session rather than the client from an id it was handed.
  final bool isSelf;

  final String? avatarUrl;
}

/// [value] with its time of day dropped, in local time.
///
/// `date_of_birth` is a `date` column. Carrying a time towards it would let the
/// same birthday land on two different days depending on the device's zone.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// The rules a written profile is held to, stated once.
///
/// Registration and the profile screen write the same three fields, so they ask
/// the same question rather than each answering it. Both refusals are a
/// [ValidationFailure] — the data handed in was inconsistent (OP-5).
///
/// Age is not among the rules. §4.3 asks for a date of birth and derives age
/// from it; no approved document sets a minimum or a maximum, and inventing one
/// here would be a Product Decision this layer does not hold (OP-2). The only
/// thing said about the date is that it has already happened.
void validateProfileInputs({
  required DateTime dateOfBirth,
  required PlayerPosition primaryPosition,
  required PlayerPosition? secondaryPosition,
  DateTime? today,
}) {
  if (dateOnly(dateOfBirth).isAfter(dateOnly(today ?? DateTime.now()))) {
    throw const ValidationFailure();
  }
  // A second position is a *different* position. §4.1 reads the two as
  // distinct, and one repeated would say nothing the primary does not.
  if (secondaryPosition != null && secondaryPosition == primaryPosition) {
    throw const ValidationFailure();
  }
}

/// The rules the two account fields a player may edit are held to.
///
/// The name is the one every roster, lineup and leaderboard shows, so an empty
/// one is refused rather than stored — a blank row is not an anonymous player,
/// it is a row nobody can identify. Two characters is the same floor a match
/// title has; no approved document sets a different one.
///
/// The phone is not checked here. What a valid Oman number looks like is a
/// product rule stated once in `AuthService`, and restating it would be a second
/// answer to the same question.
void validateAccountInputs({required String fullName}) {
  if (fullName.trim().length < 2) throw const ValidationFailure();
}
