import '../../core/failures.dart';
import '../auth/auth_models.dart';

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
class PlayerProfile {
  const PlayerProfile({
    required this.fullName,
    required this.phone,
    required this.primaryPosition,
    this.dateOfBirth,
    this.secondaryPosition,
    this.avatarUrl,
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
