import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failures.dart';

/// Runs [call] and converts anything it throws into a [Failure].
///
/// Every adapter method goes through this. An adapter therefore never names a
/// provider exception, never reads an error code, and cannot leak one: the
/// classification rules live in [SupabaseFailureMapper] and nowhere else.
Future<T> guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (error, stackTrace) {
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
    if (error is IOException || error is TimeoutException) {
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

    // Match management
    'MAX_BELOW_REGISTERED': ValidationFailure(
      FailureReason.maxBelowRegistered,
    ),
    'INVALID_STARTING_PLAYERS': ValidationFailure(
      FailureReason.invalidStartingPlayers,
    ),
    'INVALID_TIME_RANGE': ValidationFailure(FailureReason.invalidTimeRange),

    // Membership
    'CANNOT_CHANGE_OWN_ROLE': ValidationFailure(
      FailureReason.cannotChangeOwnRole,
    ),
    'CANNOT_REMOVE_SELF': ValidationFailure(FailureReason.cannotRemoveSelf),
    'CANNOT_REMOVE_OWNER': ValidationFailure(FailureReason.cannotRemoveOwner),
    'INVALID_ROLE': ValidationFailure(FailureReason.invalidRole),
    'ALREADY_OWNER': ConflictFailure(FailureReason.alreadyOwner),
    'MEMBER_NOT_FOUND': NotFoundFailure(FailureReason.memberNotFound),

    // Joining a community
    'JOIN_CODE_REQUIRED': ValidationFailure(FailureReason.joinCodeRequired),
    'ALREADY_MEMBER': ConflictFailure(FailureReason.alreadyMember),
    'COMMUNITY_NOT_FOUND': NotFoundFailure(FailureReason.communityNotFound),

    // The permission refusal every guarded RPC shares. The type says it;
    // a reason would only repeat it.
    'NOT_AUTHORIZED': AuthorizationFailure(),
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
  static void _log(Object error, StackTrace? stackTrace) {
    debugPrint('[GoPlay] adapter failure: $error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}
