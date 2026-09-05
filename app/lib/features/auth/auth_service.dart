import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

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
  /// The answer differs by platform because what can open the link differs. A
  /// phone can be handed a custom scheme and will reopen the app with it; a
  /// browser cannot — `goplay://` is not a thing a browser knows how to follow,
  /// so on the web the same constant would confirm the change and then strand
  /// the reader on a link their browser refuses. Without either, the provider
  /// falls back to its configured Site URL.
  ///
  /// Three things outside this file have to agree with it, and none is
  /// something Dart can enforce:
  ///
  ///   * the Android manifest must carry an intent filter for
  ///     `goplay://login-callback`, or the link opens nothing;
  ///   * the Supabase project's **Redirect URLs** allow-list must contain both
  ///     forms, or Auth ignores the parameter and falls back to the Site URL
  ///     again. The web form cannot be added until the origin the app is served
  ///     from is decided — see [webEmailChangeRedirect];
  ///   * whatever serves the web build must answer `/login-callback`. It does
  ///     not need its own page: the app is a single page and any path reaches
  ///     it, so the host's SPA rewrite is what makes this true.
  ///
  /// The first two are recorded in
  /// `Docs/engineering/SUPABASE_OPERATIONAL_GUIDELINES.md` alongside the rest of
  /// the project configuration.
  static String get emailChangeRedirect =>
      kIsWeb ? webEmailChangeRedirect(Uri.base) : nativeEmailChangeRedirect;

  /// What reopens the app on Android and iOS. Registered in the manifest.
  static const String nativeEmailChangeRedirect = 'goplay://login-callback';

  /// The web form, for a page served from [base].
  ///
  /// Derived at runtime rather than written down, because this project has no
  /// web origin yet: `goplay.app` appears in the invitation link but is not a
  /// registered domain, and naming it here would send confirmations to a host
  /// that does not answer.
  /// Reading the origin off the running page is also what keeps one build
  /// correct on localhost, on a staging host and in production at once.
  ///
  /// [Uri.origin] is scheme, host and non-default port only — the path is
  /// dropped on purpose, so this stays right wherever in the app the reader
  /// happened to be. It does assume the build is served from the root of its
  /// origin; a deployment under a sub-path would need the base href instead.
  @visibleForTesting
  static String webEmailChangeRedirect(Uri base) =>
      '${base.origin}/login-callback';

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

  /// Whether the signed-in account is still active.
  ///
  /// Suspension is enforced by the database whatever this returns; this is what
  /// lets the app stop showing a suspended player a product they cannot use.
  /// The failure is deliberately *not* swallowed here: the auth gate fails
  /// closed on it, and turning an unanswered question into `true` at this layer
  /// would be the one mistake that opens the door.
  Future<bool> isCurrentUserActive() => _adapter.isCurrentUserActive();

  Future<void> logout() => _adapter.signOut();
}
