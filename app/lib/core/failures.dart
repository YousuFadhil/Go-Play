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
  invalidTitle,
  invalidLocation,
  matchNotFound,

  // A match may not be scheduled to start in the past. `update_match` refuses
  // any match whose start has passed (matchLocked), so one created that way
  // could never be edited or cancelled by its organizer — this is that rule
  // seen from the creating end, not a new one.
  startInPast,

  // Membership
  cannotChangeOwnRole,
  cannotRemoveSelf,
  cannotRemoveOwner,
  alreadyOwner,
  memberNotFound,
  invalidRole,

  // The community named in a request
  joinCodeRequired,
  communityNotFound,
  alreadyMember,

  // The community exists but is not active, so nothing new may be created
  // inside it. A state the operation ran into, not input the caller got wrong.
  communityInactive,

  // Team generation.
  //
  // Raised by the team repository when a Core Player Input is absent (§4.1,
  // §4.3). **Reserved for the upcoming Team Generation UI**: no screen selects
  // a sentence from it yet, and until one does the failure reaches the user
  // through the generic fallback for its type. Nothing branches on it —
  // behaviour follows the failure type, as OP-5 requires.
  missingPlayerInputs,

  // Recording a match result.
  //
  // Each one is a rule the approved result rules state, and each selects its own
  // sentence because the organizer has to know which number to correct. As
  // everywhere else, behaviour follows the failure type — every one of these is
  // a ValidationFailure, and nothing branches on the reason.
  invalidScore,
  invalidGoals,
  goalsDoNotMatchScore,
  mvpNotParticipant,
  scorerNotParticipant,
  lineupRequired,

  // Correcting a match that has already been played.
  //
  // The record of who was on the pitch may only be corrected once the match is
  // over; before that the roster belongs to capacity, the reserve queue and the
  // player's own decision to join.
  matchNotCompleted,

  // The player being taken out of the lineup is the recorded MVP or a scorer.
  // Removing them would leave goals credited to somebody who did not play, or a
  // best player who was not on the pitch, so the result is corrected first.
  resultParticipantRemoved,

  // The side or the position asked for is not one of the values the lineup
  // recognises.
  invalidTeam,
  invalidPosition,

  // Identity
  emailAlreadyUsed,

  // Opening another player's profile.
  //
  // The player set their profile to community members only and the viewer
  // shares no active community with them. An authorization outcome, worded on
  // its own because "you do not have permission" would describe a rule the
  // reader has no way of knowing exists; nothing branches on it.
  profileNotVisible,

  // The id does not name an active player.
  profileNotFound,
}
