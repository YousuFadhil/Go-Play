import 'package:flutter/foundation.dart'
    show ValueListenable, kIsWeb, visibleForTesting;

import '../../core/failures.dart';
import '../../infrastructure/supabase/supabase_auth_adapter.dart';
import '../profile/profile_models.dart';
import 'auth_adapter.dart';
import 'auth_models.dart';
import 'password_recovery_state.dart';

/// Identity: sign-up, sign-in, the session stream, and the profile name.
///
/// Everything provider-specific is behind [AuthAdapter]. What stays here is
/// the product's own rules — what a valid Oman number looks like, how it is
/// stored, and what counts as a first name.
class AuthService {
  AuthService([AuthAdapter? adapter, PasswordRecoveryState? recovery])
      : _adapter = adapter ?? SupabaseAuthAdapter(),
        _recovery = recovery ?? PasswordRecoveryState.instance;

  final AuthAdapter _adapter;

  /// The durable memory of an unfinished password recovery. Shared with the
  /// launch and route handling in `main.dart` and `GoPlayApp` through
  /// [PasswordRecoveryState.instance]; a test supplies its own.
  final PasswordRecoveryState _recovery;

  /// Whether a session exists. The auth gate reads this so the widget layer
  /// never sees a provider's session object.
  bool get isSignedIn => _adapter.isSignedIn;

  /// Emits true while a session exists.
  Stream<bool> get signedInChanges => _adapter.signedInChanges;

  /// What the session did, as it happens. A listener sees only what is emitted
  /// after it starts listening; **it is not a record of what happened before**,
  /// so nothing that must not be missed may depend on it alone — see
  /// [recoveryInProgress].
  Stream<AuthEvent> get authEvents => _adapter.authEvents;

  /// Whether a password recovery is in progress on this device, durably: it is
  /// still true after the app is killed and reopened, which the provider's own
  /// event cannot be. The gate consults it before anything else about a
  /// signed-in account.
  ValueListenable<bool> get recoveryInProgress => _recovery.inProgress;

  /// Records that a recovery began. Called when the provider reports one, as a
  /// backup to the launch or route that came from the recovery callback.
  Future<void> beginPasswordRecovery() => _recovery.begin();

  /// Forgets a recovery that has nothing behind it: a flag with no session, or
  /// an armed link that an ordinary sign-in has since taken over from.
  Future<void> discardPasswordRecovery() => _recovery.clear();

  /// The name the sign-in provider supplied, to offer as a starting point for a
  /// form the person edits. Null when there is none.
  String? get suggestedFullName => _adapter.suggestedFullName;

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
  ///
  /// Returns whether the new account is signed in. It is not always: when the
  /// project asks for the address to be confirmed first, the account exists and
  /// nothing is signed in, and the caller shows "check your email" rather than
  /// waiting for a session that is not coming.
  Future<SignUpOutcome> register({
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
    return _adapter.signUp(
      email: email.trim(),
      password: password,
      fullName: fullName.trim(),
      position: position,
      phone: toOmanE164(localPhone),
      dateOfBirth: dateOnly(dateOfBirth),
      secondaryPosition: secondaryPosition,
      redirectTo: authCallbackRedirect,
    );
  }

  /// Sends the sign-up confirmation email again.
  ///
  /// The provider allows one email per address a minute or so and refuses the
  /// rest; that surfaces as a failure the screen words, and nothing here
  /// retries. Throws [ValidationFailure] for something that is not an address.
  Future<void> resendConfirmation(String email) async {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed)) throw const ValidationFailure();
    await _adapter.resendSignupConfirmation(
      email: trimmed,
      redirectTo: authCallbackRedirect,
    );
  }

  /// Starts signing in with Google. See [AuthAdapter.signInWithGoogle]: this
  /// returns when the browser has the request, and the outcome arrives as a
  /// session change, not as this call's result.
  Future<void> signInWithGoogle() =>
      _adapter.signInWithGoogle(redirectTo: authCallbackRedirect);

  /// Asks for a password-recovery email.
  ///
  /// Throws [ValidationFailure] for something that is not an address. Nothing
  /// else about the address is checked or reported: the provider answers the
  /// same for a registered address and an unregistered one, and this must not
  /// add a difference the caller could show.
  ///
  /// The link goes to [recoveryRedirect], not the ordinary callback: what the
  /// person arrives on is what tells the application it was a recovery.
  Future<void> requestPasswordReset(String email) async {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed)) throw const ValidationFailure();
    await _adapter.requestPasswordReset(
      trimmed,
      redirectTo: recoveryRedirect,
    );
  }

  /// How many digits an emailed code has.
  static const int emailCodeLength = 6;

  /// [input] as the digits the provider expects.
  ///
  /// Arabic-Indic and Eastern Arabic-Indic digits, which an Arabic keyboard
  /// types, become ASCII ones; anything else that is not a digit -- the space in
  /// "123 456" pasted from an email -- is dropped. It is a normalisation, not a
  /// validation: see [isValidEmailCode].
  static String normalizeEmailCode(String input) {
    final digits = StringBuffer();
    for (final unit in input.runes) {
      if (unit >= 0x30 && unit <= 0x39) {
        digits.writeCharCode(unit);
      } else if (unit >= 0x660 && unit <= 0x669) {
        digits.writeCharCode(unit - 0x660 + 0x30);
      } else if (unit >= 0x6F0 && unit <= 0x6F9) {
        digits.writeCharCode(unit - 0x6F0 + 0x30);
      }
    }
    return digits.toString();
  }

  /// Whether [input] is, once normalised, exactly [emailCodeLength] digits.
  static bool isValidEmailCode(String input) =>
      normalizeEmailCode(input).length == emailCodeLength;

  /// Verifies the code from a password-recovery email and, if it is right, puts
  /// the application **into the protected recovery state**: the durable record
  /// is set, so the auth gate shows `ResetPasswordScreen` and nothing else, and
  /// the session that results never becomes a product session.
  ///
  /// **The record is written before the provider is asked, not after.** The
  /// provider stores the session the moment the code is accepted; a record
  /// written afterwards leaves a window -- however short -- in which the app can
  /// be killed holding a recovery session that nothing says is one, and it would
  /// come back as an ordinary sign-in. Written first, there is no moment at which
  /// the session exists and the record does not. If the code is refused the
  /// record is taken back out, because nothing is being protected: with no
  /// session a record is stale by definition, and the gate drops it anyway.
  ///
  /// The provider's own recovery event is not what this relies on. It is a
  /// backup to the record, as it is for a recovery link, and the record is
  /// written again once the session is known to exist.
  ///
  /// The code itself is used and forgotten: it is passed to the provider and
  /// nowhere else -- not stored, not logged, not kept in this object.
  ///
  /// Throws [ValidationFailure] for something that is not an address or not six
  /// digits, before anything reaches the provider. A code the provider refuses
  /// -- wrong, expired, used, or for an address with no account -- is one
  /// failure, [FailureReason.invalidEmailCode].
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed) || !isValidEmailCode(code)) {
      throw const ValidationFailure();
    }
    // With somebody already signed in, a record set now would describe *their*
    // ordinary session as a recovery. That cannot arise from the screens -- the
    // gate leaves them when a session appears -- but it is cheap to be certain
    // of, and the record is set below once the recovery session exists.
    final armedFirst = !_adapter.isSignedIn;
    if (armedFirst) await _recovery.begin();
    try {
      await _adapter.verifyRecoveryCode(
        email: trimmed,
        code: normalizeEmailCode(code),
      );
    } catch (_) {
      // Only a record this call set is taken back, and only if no session came of
      // it. A session that exists is a recovery session and keeps its record.
      if (armedFirst && !_adapter.isSignedIn) await _recovery.clear();
      rethrow;
    }
    await _recovery.begin();
  }

  /// Verifies the code that completes a sign-up. On success the person has an
  /// ordinary session, and what happens next -- Home, or the player-profile form
  /// -- is the gate's account-state check like any other sign-in, not something
  /// decided here.
  ///
  /// Nothing about recovery is touched: this session is not one.
  ///
  /// Throws [ValidationFailure] for something that is not an address or not six
  /// digits; a refused code is [FailureReason.invalidEmailCode]. The code is used
  /// and forgotten, as in [verifyRecoveryCode].
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    final trimmed = email.trim();
    if (!isValidEmail(trimmed) || !isValidEmailCode(code)) {
      throw const ValidationFailure();
    }
    await _adapter.verifySignupCode(
      email: trimmed,
      code: normalizeEmailCode(code),
    );
  }

  /// Chooses the new password for a password-recovery session, then ends that
  /// session and the durable record of it.
  ///
  /// The sign-out is the point. A recovery link proves control of an inbox, not
  /// knowledge of the old password, and the session it produces exists to make
  /// this one change; leaving it in place would turn "I clicked a link" into a
  /// signed-in product session nobody asked for. After this the person signs in
  /// in the ordinary way, with the password they just chose.
  ///
  /// The order is fixed: change the password, end the session, *then* clear the
  /// flag. Interrupted anywhere before the last step the flag is still set, so a
  /// session that outlived the interruption is met by the reset screen again
  /// rather than becoming an ordinary one; interrupted after the sign-out the
  /// flag is merely stale, and the gate finds it with no session and drops it.
  ///
  /// Throws [ValidationFailure] when the password is too short. A failure from
  /// the provider — an expired link, no connection — leaves the session and the
  /// flag alone so the person can try again or cancel.
  Future<void> completePasswordRecovery(String password) async {
    if (!isValidPassword(password)) throw const ValidationFailure();
    await _adapter.changePassword(password);
    await _endRecovery();
  }

  /// Leaves a password recovery without changing anything: ends the session and
  /// clears the durable record of it.
  ///
  /// If the session cannot be ended the flag is **kept** and the failure is
  /// thrown. Clearing it over a session that is still there would be exactly
  /// what the flag exists to prevent.
  Future<void> cancelPasswordRecovery() => _endRecovery();

  Future<void> _endRecovery() async {
    try {
      await _adapter.signOut();
    } catch (_) {
      // A provider clears its own copy of the session before it tells the
      // server, so a failed call usually still leaves nobody signed in, and that
      // is what matters. Only when a session is somehow still there is the
      // failure real.
      if (_adapter.isSignedIn) rethrow;
    }
    await _recovery.clear();
  }

  /// What the signed-in account is: active, suspended, or waiting for a player
  /// profile. The gate fails closed on a failure here exactly as it does on
  /// [isCurrentUserActive].
  Future<AccountState> fetchAccountState() => _adapter.fetchAccountState();

  /// Creates the signed-in account's player profile.
  ///
  /// This is the Google onboarding path, and it is held to the same rules as
  /// registration and the profile screen, asked in the same places: the name is
  /// the one every roster shows, so a blank one is refused; the phone is an
  /// 8-digit Oman number and is stored as `+968XXXXXXXX`; the date of birth
  /// cannot be in the future; and a secondary position is a different position.
  ///
  /// Throws [ValidationFailure] - before anything reaches the provider - for any
  /// of those. There is no email or password here: the account already has its
  /// credentials.
  Future<void> completePlayerProfile({
    required String fullName,
    required String localPhone,
    required DateTime dateOfBirth,
    required PlayerPosition position,
    PlayerPosition? secondaryPosition,
  }) async {
    validateAccountInputs(fullName: fullName);
    if (!isValidOmanLocalPhone(localPhone)) throw const ValidationFailure();
    validateProfileInputs(
      dateOfBirth: dateOfBirth,
      primaryPosition: position,
      secondaryPosition: secondaryPosition,
    );
    await _adapter.completePlayerProfile(
      fullName: fullName.trim(),
      phone: toOmanE164(localPhone),
      dateOfBirth: dateOnly(dateOfBirth),
      position: position,
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

  /// Where the ordinary emailed or redirected authentication links send the
  /// player: the sign-up confirmation and the return from Google. It is the same
  /// address as [emailChangeRedirect] on purpose - one callback, one manifest
  /// filter, one allow-list entry per form - and this name exists so those
  /// callers do not read as though they were changing an email. Everything said
  /// above about what has to agree outside Dart applies to it unchanged.
  ///
  /// Password recovery does **not** use it; see [recoveryRedirect].
  static String get authCallbackRedirect => emailChangeRedirect;

  /// Where a password-recovery link sends the player: the ordinary callback with
  /// `/recovery` after it.
  ///
  /// The extra segment is what lets the application recognise a recovery from
  /// the address it was opened on, without having to have seen the provider's
  /// event (`RecoveryLink`). It adds two things outside Dart that have to agree:
  /// the Redirect URLs allow-list needs the `/recovery` form of **each** ordinary
  /// entry, or Auth ignores the parameter and falls back to the Site URL; and
  /// the Android intent filter must accept it — which it does, because it names
  /// the host `login-callback` and restricts no path.
  static String get recoveryRedirect =>
      kIsWeb ? webRecoveryRedirect(Uri.base) : nativeRecoveryRedirect;

  /// What reopens the app on Android and iOS for a recovery.
  static const String nativeRecoveryRedirect = 'goplay://login-callback/recovery';

  /// The web form, for a page served from [base]. Derived the same way as
  /// [webEmailChangeRedirect], and for the same reasons.
  @visibleForTesting
  static String webRecoveryRedirect(Uri base) =>
      '${base.origin}/login-callback/recovery';

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
