import 'auth_models.dart';

/// Identity's port into the data provider.
///
/// The provider's session object never crosses this line — the application
/// asks whether it is signed in, not what the session contains (OP-3).
/// Implementations raise a `Failure` rather than an SDK exception (OP-5).
///
/// [signUp] takes the phone already in its stored form: how an Oman number is
/// composed is a product rule and stays above this layer (OP-2).
abstract interface class AuthAdapter {
  /// Id of the signed-in user, or null when there is no session.
  String? get currentUserId;

  /// Whether a session exists right now.
  bool get isSignedIn;

  /// Emits true while a session exists, so the auth gate never subscribes to
  /// the provider itself.
  Stream<bool> get signedInChanges;

  /// The signed-in user's stored full name, or null when there is no session
  /// or no profile row yet.
  Future<String?> fetchCurrentUserFullName();

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
  });

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}
