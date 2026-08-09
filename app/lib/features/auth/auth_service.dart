import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_auth_adapter.dart';
import '../profile/profile_models.dart';
import 'auth_adapter.dart';
import 'auth_models.dart';

/// Identity: sign-up, sign-in, the session stream, and the profile name.
///
/// Everything provider-specific is behind [AuthAdapter]. What stays here is
/// the product's own rules — what a valid Oman number looks like, how it is
/// stored, and what counts as a first name.
class AuthService {
  AuthService([AuthAdapter? adapter])
      : _adapter = adapter ?? SupabaseAuthAdapter();

  final AuthAdapter _adapter;

  /// Whether a session exists. The auth gate reads this so the widget layer
  /// never sees a provider's session object.
  bool get isSignedIn => _adapter.isSignedIn;

  /// Emits true while a session exists.
  Stream<bool> get signedInChanges => _adapter.signedInChanges;

  /// Id of the signed-in user, or null when there is no session.
  String? get currentUserId => _adapter.currentUserId;

  /// Email the account signs in with, or null when there is no session.
  String? get currentUserEmail => _adapter.currentUserEmail;

  /// First name of the signed-in user, for greetings. Empty when there is no
  /// session or the profile has no name yet.
  Future<String> fetchCurrentUserFirstName() async {
    final fullName = (await _adapter.fetchCurrentUserFullName())?.trim() ?? '';
    return fullName.isEmpty ? '' : fullName.split(RegExp(r'\s+')).first;
  }

  /// Oman country calling code. The MVP is Oman-only, so the code is fixed
  /// and the user enters just the 8-digit local number.
  static const String omanCallingCode = '+968';

  /// Keeps digits only from user input, e.g. "9012 3456" -> "90123456".
  static String digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// An Oman local mobile number is exactly 8 digits.
  static bool isValidOmanLocalPhone(String input) {
    return RegExp(r'^[0-9]{8}$').hasMatch(digitsOnly(input));
  }

  /// Builds the stored E.164 phone from an 8-digit local number,
  /// e.g. "90123456" -> "+96890123456".
  static String toOmanE164(String localPhone) {
    return '$omanCallingCode${digitsOnly(localPhone)}';
  }

  /// Basic sanity check for an email address.
  static bool isValidEmail(String input) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input.trim());
  }

  /// Identity is email+password; phone is stored as profile contact info
  /// (see Docs/10-Design-Decisions.md DD-02). [localPhone] is the 8-digit
  /// Oman number; it is stored as +968XXXXXXXX.
  ///
  /// The profile §4.1 requires is collected here rather than afterwards: an
  /// account that arrives without a date of birth is one the engine will refuse
  /// to generate teams around, and asking once at sign-up is what stops that
  /// happening again.
  ///
  /// [dateOfBirth] is required and [secondaryPosition] is optional
  /// (`BTGE-SC-6`). The rating is neither: `OP-1` makes it system-managed, so
  /// registration has nothing to say about it.
  ///
  /// Throws [ValidationFailure] — before anything reaches the provider — when
  /// the date of birth has not happened yet or the secondary position repeats
  /// the primary. It is the same rule the profile screen writes under, asked in
  /// the same place.
  Future<void> register({
    required String email,
    required String localPhone,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required DateTime dateOfBirth,
    PlayerPosition? secondaryPosition,
  }) async {
    validateProfileInputs(
      dateOfBirth: dateOfBirth,
      primaryPosition: position,
      secondaryPosition: secondaryPosition,
    );
    await _adapter.signUp(
      email: email.trim(),
      password: password,
      fullName: fullName.trim(),
      position: position,
      phone: toOmanE164(localPhone),
      dateOfBirth: dateOnly(dateOfBirth),
      secondaryPosition: secondaryPosition,
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) =>
      _adapter.signIn(email: email.trim(), password: password);

  /// Changes the email the account signs in with.
  ///
  /// The address is checked here rather than being sent and refused a round trip
  /// later — it is the same question [isValidEmail] answers for registration and
  /// for sign-in, asked in the same place.
  ///
  /// Throws [ValidationFailure] when the address is not one, or when it is the
  /// address the account already has: changing an email to itself is not a
  /// change, and the provider would send a confirmation for nothing.
  Future<void> changeEmail(String email) async {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed)) throw const ValidationFailure();
    if (trimmed.toLowerCase() == currentUserEmail?.toLowerCase()) {
      throw const ValidationFailure();
    }
    await _adapter.changeEmail(trimmed, redirectTo: emailChangeRedirect);
  }

  /// Where the confirmation link for an email change sends the player.
  ///
  /// The app's own scheme, so tapping the link in the mail app reopens Go Play
  /// rather than a browser. Without this the provider uses its configured Site
  /// URL — a web address this project does not serve — and the player confirms
  /// the change and is left staring at a page that is not the app.
  ///
  /// Two things outside this file have to agree with it, and neither is
  /// something Dart can enforce:
  ///
  ///   * the Android manifest must carry an intent filter for
  ///     `goplay://login-callback`, or the link opens nothing;
  ///   * the Supabase project's **Redirect URLs** allow-list must contain it,
  ///     or Auth ignores the parameter and falls back to the Site URL again.
  ///
  /// Both are recorded in `Docs/engineering/SUPABASE_OPERATIONAL_GUIDELINES.md`
  /// alongside the rest of the project configuration.
  static const String emailChangeRedirect = 'goplay://login-callback';

  /// The shortest password the product accepts.
  ///
  /// Eight, which is what the registration screen has always asked for and what
  /// `passwordTooShort` tells the player. It is stated here so that changing a
  /// password and choosing one are held to the same rule rather than to two
  /// copies of it that can drift.
  static const int minimumPasswordLength = 8;

  static bool isValidPassword(String input) =>
      input.length >= minimumPasswordLength;

  /// Changes the account password.
  ///
  /// Throws [ValidationFailure] when the password is shorter than the provider
  /// will accept.
  Future<void> changePassword(String password) async {
    if (!isValidPassword(password)) throw const ValidationFailure();
    await _adapter.changePassword(password);
  }

  Future<void> logout() => _adapter.signOut();
}
