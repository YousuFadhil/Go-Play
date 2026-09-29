/// Player field positions.
enum PlayerPosition { gk, def, mid, fwd }

/// What the signed-in account is, as the database reports it.
///
/// Three answers, because the application has to do three different things: let
/// an active player in, tell a suspended one they are suspended, and ask an
/// account that has no player profile yet for the one it has not given. The
/// older two-way `isCurrentUserActive` cannot tell the last two apart, and
/// treating "no profile yet" as "suspended" would show a new Google account a
/// suspension notice it has done nothing to earn.
enum AccountState { active, suspended, profileRequired }

/// What a sign-up produced.
///
/// Whether the provider signs a new account in straight away is its own project
/// setting -- email confirmation on or off -- and the application has to work
/// under both, so the answer is data rather than an assumption.
enum SignUpOutcome {
  /// A session exists. The account is usable now.
  signedIn,

  /// The account exists but has no session: the provider is waiting for the
  /// owner of the address to confirm it. Nothing is signed in.
  confirmationRequired,
}

/// An application-level authentication event.
///
/// A provider-independent restatement of what the session just did. A boolean
/// "is there a session" cannot carry the one distinction that matters most
/// here: a password-recovery link produces a session too, and one that looks
/// exactly like an ordinary sign-in until something says otherwise.
enum AuthEvent {
  /// A session began: a sign-in, a sign-up that was not held for confirmation,
  /// a confirmation link, or a completed OAuth redirect.
  signedIn,

  /// The session ended, by choice or because the provider could no longer keep
  /// it.
  signedOut,

  /// The session was created by a password-recovery link. It exists so the
  /// person can choose a new password and for nothing else, and the gate must
  /// not treat it as a way into the product.
  passwordRecovery,

  /// The session stayed in place and something about it changed: a refreshed
  /// token, an updated user, the initial restore from storage.
  sessionUpdated,
}
