/// The application's error language (OP-5).
///
/// Every error the application sees is one of the eight types below. The
/// Adapter Layer converts provider exceptions into them, and nothing outside
/// that layer knows what a data provider is: no PostgreSQL code, Supabase
/// code, SDK exception type, provider message and no stack trace is carried
/// here. Those stay in the adapter, where they are logged.
///
/// A failure may also carry a [FailureReason] — the business outcome behind
/// it. Per the approved clarification to OP-5, a reason exists **only** to
/// select the right localized sentence. Application behaviour — offer a retry,
/// ask the user to correct their input, block the operation — branches on the
/// failure *type*, never on the reason.
sealed class Failure implements Exception {
  const Failure([this.reason]);

  /// The business outcome behind the failure, when the operation reported one.
  /// Message selection only; never a basis for behaviour.
  final FailureReason? reason;

  @override
  String toString() =>
      reason == null ? '$runtimeType' : '$runtimeType(${reason!.name})';
}

/// Sign-in was refused, or the session has expired.
final class AuthenticationFailure extends Failure {
  const AuthenticationFailure([super.reason]);
}

/// The user lacks the permission the operation requires.
final class AuthorizationFailure extends Failure {
  const AuthorizationFailure([super.reason]);
}

/// The data sent was invalid or incomplete.
final class ValidationFailure extends Failure {
  const ValidationFailure([super.reason]);
}

/// The requested resource does not exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.reason]);
}

/// A state conflict: a registration clash, or data that changed underneath.
final class ConflictFailure extends Failure {
  const ConflictFailure([super.reason]);
}

/// A connectivity interruption: the request never reached the server.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.reason]);
}

/// The database or a supporting service failed.
final class InfrastructureFailure extends Failure {
  const InfrastructureFailure([super.reason]);
}

/// Anything that could not be classified.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.reason]);
}

/// A business outcome the product recognises, independent of any provider.
///
/// These are the product's own refusals — the same list would survive a move
/// to a different backend, because they describe what the rule decided, not
/// how the failure was reported. They never reach the UI as behaviour, only as
/// wording.
enum FailureReason {
  // Registration
  overlappingMatch,
  matchClosed,
  matchCompleted,
  matchLocked,
  registrationClosed,
  alreadyRegistered,
  notRegistered,
  notCommunityMember,

  // Match management
  maxBelowRegistered,
  invalidStartingPlayers,
  invalidTimeRange,

  // Membership
  cannotChangeOwnRole,
  cannotRemoveSelf,
  cannotRemoveOwner,
  alreadyOwner,
  memberNotFound,
  invalidRole,

  // Joining a community
  joinCodeRequired,
  communityNotFound,
  alreadyMember,

  // Team generation
  missingPlayerInputs,

  // Identity
  emailAlreadyUsed,
}
