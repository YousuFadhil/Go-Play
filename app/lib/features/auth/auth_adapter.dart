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
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  });

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

  Future<void> signOut();
}
