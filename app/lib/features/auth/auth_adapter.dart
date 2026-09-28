import 'auth_models.dart';

/// Identity's port into the data provider.
///
/// The provider's session object never crosses this line — the application
/// asks whether it is signed in, not what the session contains (OP-3).
/// Implementations raise a `Failure` rather than an SDK exception (OP-5).
///
/// [signUp] takes the phone already in its stored form: how an Oman number is
/// composed is a product rule and stays above this layer (OP-2). The profile it
/// carries is the one §4.1 asks for — a date of birth, a primary position and
/// an optional secondary — because the account and its profile are created
/// together, by the trigger, from what sign-up was given.
abstract interface class AuthAdapter {
  /// Id of the signed-in user, or null when there is no session.
  String? get currentUserId;

  /// Email the account signs in with, or null when there is no session.
  ///
  /// It is read from the session rather than from the profile row: the email is
  /// a credential, and the account is the only thing that knows what it is.
  String? get currentUserEmail;

  /// Whether a session exists right now.
  bool get isSignedIn;

  /// Emits true while a session exists, so the auth gate never subscribes to
  /// the provider itself.
  Stream<bool> get signedInChanges;

  /// What the session did, in the application's own terms.
  ///
  /// [signedInChanges] says only whether a session exists, and a recovery link
  /// produces one that is indistinguishable from an ordinary sign-in. This is
  /// the stream that keeps the difference: it is how the gate learns that the
  /// session it is looking at exists to reset a password and nothing else.
  ///
  /// May replay the most recent event to a late listener, as the provider's own
  /// stream does, so a recovery link that was handled before the gate existed is
  /// still seen. Provider errors never surface on it.
  Stream<AuthEvent> get authEvents;

  /// The full name the sign-in provider supplied for the signed-in account, or
  /// null when there is none or it is blank.
  ///
  /// Only ever a suggestion for a form the person can edit. It is never stored
  /// from here and never trusted as a profile.
  String? get suggestedFullName;

  /// The signed-in user's stored full name, or null when there is no session
  /// or no profile row yet.
  Future<String?> fetchCurrentUserFullName();

  /// Creates the account and, with it, the profile row.
  ///
  /// [dateOfBirth] is a date; any time of day it carries is not part of what is
  /// stored. A null [secondaryPosition] means the player named none, which is
  /// ordinary input (`BTGE-SC-6`) and is stored as the absence itself.
  ///
  /// There is no rating parameter. `OP-1` makes the initial rating the
  /// database's to set, and an implementation that sent one would be handing a
  /// system-managed value to whoever fills in the form.
  ///
  /// The result says whether the provider signed the new account in. It is
  /// [SignUpOutcome.confirmationRequired] when the project asks the owner of the
  /// address to confirm it first, and the caller must not then behave as though
  /// there were a session.
  ///
  /// [redirectTo] is where the confirmation link, when there is one, sends the
  /// player. See [changeEmail] for why it cannot be left to the provider.
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
    required String redirectTo,
  });

  /// Sends the sign-up confirmation email again.
  ///
  /// The provider rate-limits this and says so; an implementation reports that
  /// as a `Failure` and does not retry.
  Future<void> resendSignupConfirmation({
    required String email,
    required String redirectTo,
  });

  /// Starts signing in with Google through the provider's own redirect flow.
  ///
  /// Returns once the browser has been handed the request, not once anybody is
  /// signed in: the result arrives later, through [authEvents] and
  /// [signedInChanges], when the redirect returns to [redirectTo]. On the web
  /// the page itself navigates away.
  ///
  /// An account whose email matches an existing one is linked to it by the
  /// provider, under the provider's own rules. Nothing here decides that.
  Future<void> signInWithGoogle({required String redirectTo});

  /// Asks the provider to email a password-recovery link to [email].
  ///
  /// The provider answers the same whether or not the address belongs to an
  /// account, and an implementation must not add a difference of its own: this
  /// is a question anybody can ask, so its answer cannot say who is registered.
  Future<void> requestPasswordReset(String email, {required String redirectTo});

  Future<void> signIn({required String email, required String password});

  /// Changes the email the account signs in with.
  ///
  /// The provider may require the new address to be confirmed before it takes
  /// effect; that is its rule, not this port's, and an implementation reports
  /// what it was told rather than promising the change has already landed.
  ///
  /// [redirectTo] is where the confirmation link should send the player when
  /// they tap it. Without one the provider falls back to its own configured Site
  /// URL, which is a web address this app does not serve — the player confirms
  /// the change and lands somewhere that is not Go Play.
  Future<void> changeEmail(String email, {required String redirectTo});

  /// Changes the account password. There is no old-password parameter: the
  /// caller already holds a session, which is what proves the account is theirs.
  Future<void> changePassword(String password);

  /// Whether the signed-in account is still active, straight from the
  /// database's own `is_current_user_active()`.
  ///
  /// It reports what the database says and nothing more. What to do when the
  /// answer cannot be obtained is a permission decision, and an adapter does
  /// not make those (OP-2) -- an implementation raises a `Failure` and the
  /// caller decides.
  Future<bool> isCurrentUserActive();

  /// What the signed-in account is: active, suspended, or without a player
  /// profile yet -- straight from the database's own `get_my_account_state()`.
  ///
  /// Like [isCurrentUserActive] it reports what the database says and nothing
  /// more; an unanswerable question is a `Failure`, and the caller decides.
  Future<AccountState> fetchAccountState();

  /// Creates the signed-in account's player profile, for an account that has
  /// none.
  ///
  /// Takes what the profile needs and nothing else -- no rating, role, active
  /// state or user id -- because the database acts for the session's own user
  /// and sets the rest itself. [phone] is already in its stored form.
  Future<void> completePlayerProfile({
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition position,
    required PlayerPosition? secondaryPosition,
  });

  Future<void> signOut();
}
