import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/diagnostics.dart';
import '../../core/failures.dart';

/// Runs [call] and converts anything it throws into a [Failure].
///
/// Every adapter method goes through this. An adapter therefore never names a
/// provider exception, never reads an error code, and cannot leak one: the
/// classification rules live in [SupabaseFailureMapper] and nowhere else.
///
/// [operation] labels the call for instrumentation — the RPC or table it goes
/// to. It is never read to decide anything and never reaches the user: it
/// exists so that a traced flow says *which* call failed, which a failure type
/// on its own cannot. Under `Diagnostics.verboseErrors` it is recorded with the
/// original exception; otherwise it is discarded with it.
Future<T> guarded<T>(Future<T> Function() call, {String? operation}) async {
  if (operation != null) Diagnostics.trace('adapter', 'begin $operation');
  try {
    final result = await call();
    if (operation != null) Diagnostics.trace('adapter', 'ok $operation');
    return result;
  } catch (error, stackTrace) {
    // Recorded before it is converted: this is the last point at which the
    // provider's own message exists.
    Diagnostics.recordAdapterFailure(operation, error);
    Diagnostics.trace('adapter', 'failed $operation: $error');
    throw SupabaseFailureMapper.from(error, stackTrace);
  }
}

/// The single point where a provider exception becomes a [Failure] (OP-5).
///
/// Everything technical stops here: PostgreSQL codes, Supabase codes, SDK
/// exception types, messages and stack traces are read to classify, logged for
/// diagnosis, and then discarded. What leaves is a failure type and, when the
/// database named a business outcome, the reason that selects its wording.
class SupabaseFailureMapper {
  const SupabaseFailureMapper._();

  static Failure from(Object error, [StackTrace? stackTrace]) {
    // Already ours — a mapped failure passed back up through another guard, or
    // one an adapter raised from the data itself.
    if (error is Failure) return error;

    _log(error, stackTrace);

    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is AuthException) return _fromAuth(error);
    // The transport never completed the round trip.
    //
    // [ClientException] is the one type that says this on every platform the
    // app builds for, which is why `dart:io` is not named here — importing it
    // would be a compile error on the web target, and this file is in the
    // compile graph of every adapter through [guarded].
    //
    // It covers both sides because `package:http` normalises to it:
    //
    //   * on Android, `IOClient` catches the `SocketException` its underlying
    //     `HttpClient` throws and rethrows it as a `ClientException` subclass
    //     that still implements `SocketException` — so a dropped connection is
    //     caught here exactly as it was when this read `IOException`;
    //   * on the web, `BrowserClient` converts every failure it sees, CORS and
    //     network alike, into a plain `ClientException`.
    //
    // Everything the Supabase SDK sends goes through `package:http`, so there
    // is no route by which a bare `SocketException` reaches this mapper.
    // PostgREST and Storage rethrow it untouched; GoTrue is the exception, and
    // it wraps its own transport failures into the [AuthRetryableFetchException]
    // handled in [_fromAuth].
    if (error is ClientException || error is TimeoutException) {
      return const NetworkFailure();
    }
    return const UnknownFailure();
  }

  /// Outcomes the project's own RPCs raise, by the token they carry.
  ///
  /// These are business results, not provider detail: the same list would
  /// survive a move to another backend. No token is a substring of another, so
  /// the scan below cannot match the wrong one.
  static const _domainOutcomes = <String, Failure>{
    // Registration
    'OVERLAPPING_MATCH': ConflictFailure(FailureReason.overlappingMatch),
    'ALREADY_REGISTERED': ConflictFailure(FailureReason.alreadyRegistered),
    'NOT_REGISTERED': ConflictFailure(FailureReason.notRegistered),
    'REGISTRATION_CLOSED': ConflictFailure(FailureReason.registrationClosed),
    'MATCH_CLOSED': ConflictFailure(FailureReason.matchClosed),
    'MATCH_COMPLETED': ConflictFailure(FailureReason.matchCompleted),
    'MATCH_LOCKED': ConflictFailure(FailureReason.matchLocked),
    'NOT_COMMUNITY_MEMBER': AuthorizationFailure(
      FailureReason.notCommunityMember,
    ),

    // Professional Guests (migration 0047). The name is input the caller got
    // wrong; the missing guest is a state the operation ran into — the same two
    // shapes every other pair here takes.
    'INVALID_GUEST_NAME': ValidationFailure(FailureReason.invalidGuestName),
    'GUEST_NOT_FOUND': NotFoundFailure(FailureReason.guestNotFound),

    // Arranging a roster (migration 0053). The first is the roster having moved
    // between the arranger reading it and sending the order back, which is a
    // state the operation ran into — the same shape as ALREADY_REGISTERED. The
    // second is a pair of seats that cannot be exchanged, which is input.
    'ROSTER_MISMATCH': ConflictFailure(FailureReason.rosterChanged),
    'INVALID_SWAP': ValidationFailure(FailureReason.invalidSwap),

    // Match management
    'MAX_BELOW_REGISTERED': ValidationFailure(
      FailureReason.maxBelowRegistered,
    ),
    'INVALID_STARTING_PLAYERS': ValidationFailure(
      FailureReason.invalidStartingPlayers,
    ),
    'INVALID_TIME_RANGE': ValidationFailure(FailureReason.invalidTimeRange),
    'INVALID_TITLE': ValidationFailure(FailureReason.invalidTitle),
    'INVALID_LOCATION': ValidationFailure(FailureReason.invalidLocation),
    // The schedule the caller asked for, refused. `create_match` raises this so
    // a match cannot be created into the state `update_match` then treats as
    // locked forever.
    'START_IN_PAST': ValidationFailure(FailureReason.startInPast),
    'MATCH_NOT_FOUND': NotFoundFailure(FailureReason.matchNotFound),

    // Membership
    'CANNOT_CHANGE_OWN_ROLE': ValidationFailure(
      FailureReason.cannotChangeOwnRole,
    ),
    'CANNOT_REMOVE_SELF': ValidationFailure(FailureReason.cannotRemoveSelf),
    'CANNOT_REMOVE_OWNER': ValidationFailure(FailureReason.cannotRemoveOwner),
    'INVALID_ROLE': ValidationFailure(FailureReason.invalidRole),
    'ALREADY_OWNER': ConflictFailure(FailureReason.alreadyOwner),
    'MEMBER_NOT_FOUND': NotFoundFailure(FailureReason.memberNotFound),

    // Recording a match result
    'INVALID_SCORE': ValidationFailure(FailureReason.invalidScore),
    'INVALID_GOALS': ValidationFailure(FailureReason.invalidGoals),
    'GOALS_DO_NOT_MATCH_SCORE': ValidationFailure(
      FailureReason.goalsDoNotMatchScore,
    ),
    'MVP_NOT_PARTICIPANT': ValidationFailure(
      FailureReason.mvpNotParticipant,
    ),
    'SCORER_NOT_PARTICIPANT': ValidationFailure(
      FailureReason.scorerNotParticipant,
    ),
    'LINEUP_REQUIRED': ValidationFailure(FailureReason.lineupRequired),

    // Correcting a played match. The first two are states the operation ran
    // into rather than input the caller got wrong, so they are conflicts — the
    // same shape as MATCH_COMPLETED. The last two are input.
    'MATCH_NOT_COMPLETED': ConflictFailure(FailureReason.matchNotCompleted),
    'RESULT_PARTICIPANT_REMOVED': ConflictFailure(
      FailureReason.resultParticipantRemoved,
    ),
    'INVALID_TEAM': ValidationFailure(FailureReason.invalidTeam),
    'INVALID_POSITION': ValidationFailure(FailureReason.invalidPosition),

    // The community named in a request
    'JOIN_CODE_REQUIRED': ValidationFailure(FailureReason.joinCodeRequired),
    'ALREADY_MEMBER': ConflictFailure(FailureReason.alreadyMember),
    'COMMUNITY_NOT_FOUND': NotFoundFailure(FailureReason.communityNotFound),
    // Not bad input: the community named is the one meant, and its state is
    // what refuses. That is the same shape as MATCH_COMPLETED and MATCH_LOCKED,
    // and it is classified the same way.
    'COMMUNITY_INACTIVE': ConflictFailure(FailureReason.communityInactive),

    // Opening another player's profile. Both are outcomes `player_profile`
    // raises (migration `0043`). The first is an authorization refusal that
    // words itself, because "you do not have permission" would name a rule the
    // reader cannot see; the second is an id that names nobody.
    'PROFILE_NOT_VISIBLE': AuthorizationFailure(
      FailureReason.profileNotVisible,
    ),
    'USER_NOT_FOUND': NotFoundFailure(FailureReason.profileNotFound),

    // The permission refusal every guarded RPC shares. The type says it;
    // a reason would only repeat it.
    'NOT_AUTHORIZED': AuthorizationFailure(),

    // Raised by every guarded RPC when the call arrives without a session.
    // A reason would only repeat what the type already says, exactly as with
    // NOT_AUTHORIZED above. Note this is a *refusal the database raised*, not
    // the SDK reporting a rejected token — PGRST301 covers that case below and
    // reaches the same failure type by a different route.
    'NOT_AUTHENTICATED': AuthenticationFailure(),
  };

  static Failure _fromPostgrest(PostgrestException error) {
    final outcome = _domainOutcome(error.message);
    if (outcome != null) return outcome;

    // Nothing the product raised, so read what Postgres said.
    return switch (error.code) {
      // insufficient_privilege — RLS refused the statement.
      '42501' => const AuthorizationFailure(),
      // PostgREST rejected or could not verify the JWT.
      'PGRST301' || '401' => const AuthenticationFailure(),
      // A single-row request matched nothing.
      'PGRST116' || '404' => const NotFoundFailure(),
      // unique_violation, serialization_failure, deadlock_detected.
      '23505' || '40001' || '40P01' => const ConflictFailure(),
      // not_null, foreign_key, check violations and unparseable input: the
      // statement was built from data the database would not accept.
      '23502' || '23503' || '23514' || '22P02' => const ValidationFailure(),
      // Everything else that reached us from the database is the database
      // failing, including the read-only mode a full Free-plan project enters.
      _ => const InfrastructureFailure(),
    };
  }

  static Failure _fromAuth(AuthException error) {
    // The SDK's own signal that the request never reached the server.
    if (error is AuthRetryableFetchException) return const NetworkFailure();

    final alreadyUsed = error.statusCode == '422' ||
        error.message.toLowerCase().contains('already');
    if (alreadyUsed) {
      return const ConflictFailure(FailureReason.emailAlreadyUsed);
    }
    return const AuthenticationFailure();
  }

  static Failure? _domainOutcome(String message) {
    for (final entry in _domainOutcomes.entries) {
      if (message.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Diagnostics stay here. This is the last point at which the original error
  /// exists, and the only layer allowed to know what it said.
  ///
  /// Debug builds only. A release build reaches logcat through
  /// `Diagnostics.trace`, which is off unless it is switched on deliberately —
  /// an unconditional print here would put the provider's own message and a
  /// stack trace on every user's device for every failure, whether or not
  /// anybody asked to be shown them.
  static void _log(Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    debugPrint('[GoPlay] adapter failure: $error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}
