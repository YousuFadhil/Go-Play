import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider exception -> Failure (OP-5). This is the whole classification
/// contract: if a rule is not asserted here, it is not enforced anywhere.
void main() {
  Failure map(Object error) => SupabaseFailureMapper.from(error);

  /// A refusal raised by one of the project's own RPCs, which arrives as
  /// `raise exception` — SQLSTATE P0001 with the token in the message.
  PostgrestException raised(String token) =>
      PostgrestException(message: 'error: $token', code: 'P0001');

  group('business outcomes the database raised', () {
    test('registration refusals keep their reason', () {
      expect(map(raised('OVERLAPPING_MATCH')),
          isA<ConflictFailure>().having((f) => f.reason, 'reason',
              FailureReason.overlappingMatch));
      expect(map(raised('ALREADY_REGISTERED')).reason,
          FailureReason.alreadyRegistered);
      expect(map(raised('NOT_REGISTERED')).reason, FailureReason.notRegistered);
      expect(map(raised('REGISTRATION_CLOSED')).reason,
          FailureReason.registrationClosed);
      expect(map(raised('MATCH_CLOSED')).reason, FailureReason.matchClosed);
      expect(map(raised('MATCH_COMPLETED')).reason,
          FailureReason.matchCompleted);
      expect(map(raised('MATCH_LOCKED')).reason, FailureReason.matchLocked);
    });

    test('a non-member is refused as an authorization failure', () {
      expect(map(raised('NOT_COMMUNITY_MEMBER')),
          isA<AuthorizationFailure>().having((f) => f.reason, 'reason',
              FailureReason.notCommunityMember));
    });

    test('match-management refusals are validation failures', () {
      expect(map(raised('MAX_BELOW_REGISTERED')),
          isA<ValidationFailure>().having((f) => f.reason, 'reason',
              FailureReason.maxBelowRegistered));
      expect(map(raised('INVALID_STARTING_PLAYERS')).reason,
          FailureReason.invalidStartingPlayers);
      expect(map(raised('INVALID_TIME_RANGE')).reason,
          FailureReason.invalidTimeRange);
    });

    test('membership refusals keep their reason', () {
      expect(map(raised('CANNOT_CHANGE_OWN_ROLE')).reason,
          FailureReason.cannotChangeOwnRole);
      expect(map(raised('CANNOT_REMOVE_SELF')).reason,
          FailureReason.cannotRemoveSelf);
      expect(map(raised('CANNOT_REMOVE_OWNER')).reason,
          FailureReason.cannotRemoveOwner);
      expect(map(raised('INVALID_ROLE')).reason, FailureReason.invalidRole);
      expect(map(raised('ALREADY_OWNER')),
          isA<ConflictFailure>()
              .having((f) => f.reason, 'reason', FailureReason.alreadyOwner));
      expect(map(raised('MEMBER_NOT_FOUND')),
          isA<NotFoundFailure>()
              .having((f) => f.reason, 'reason', FailureReason.memberNotFound));
    });

    test('joining refusals keep their reason', () {
      expect(map(raised('JOIN_CODE_REQUIRED')).reason,
          FailureReason.joinCodeRequired);
      expect(map(raised('ALREADY_MEMBER')),
          isA<ConflictFailure>()
              .having((f) => f.reason, 'reason', FailureReason.alreadyMember));
      expect(map(raised('COMMUNITY_NOT_FOUND')),
          isA<NotFoundFailure>().having(
              (f) => f.reason, 'reason', FailureReason.communityNotFound));
    });

    test('a permission refusal is the type alone, with no reason', () {
      final failure = map(raised('NOT_AUTHORIZED'));
      expect(failure, isA<AuthorizationFailure>());
      expect(failure.reason, isNull,
          reason: 'the type already says it; a reason would only repeat it');
    });

    test('a token wins over the SQLSTATE code that carried it', () {
      expect(
        map(const PostgrestException(message: 'ALREADY_MEMBER', code: '42501')),
        isA<ConflictFailure>(),
      );
    });
  });

  group('database errors nobody raised deliberately', () {
    test('insufficient privilege is an authorization failure', () {
      expect(map(const PostgrestException(message: 'denied', code: '42501')),
          isA<AuthorizationFailure>());
    });

    test('a rejected token is an authentication failure', () {
      expect(map(const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
          isA<AuthenticationFailure>());
    });

    test('a single-row request that matched nothing is not found', () {
      expect(map(const PostgrestException(message: '0 rows', code: 'PGRST116')),
          isA<NotFoundFailure>());
    });

    test('unique violations and lost races are conflicts', () {
      expect(map(const PostgrestException(message: 'dup', code: '23505')),
          isA<ConflictFailure>());
      expect(map(const PostgrestException(message: 'retry', code: '40001')),
          isA<ConflictFailure>());
      expect(map(const PostgrestException(message: 'deadlock', code: '40P01')),
          isA<ConflictFailure>());
    });

    test('constraint violations are validation failures', () {
      for (final code in ['23502', '23503', '23514', '22P02']) {
        expect(map(PostgrestException(message: 'bad', code: code)),
            isA<ValidationFailure>(),
            reason: 'SQLSTATE $code describes data the database refused');
      }
    });

    test('anything else from the database is an infrastructure failure', () {
      expect(map(const PostgrestException(message: 'boom', code: '53300')),
          isA<InfrastructureFailure>());
      expect(map(const PostgrestException(message: 'read-only', code: '25006')),
          isA<InfrastructureFailure>(),
          reason: 'a full Free-plan project goes read-only; that is not a bug '
              'in the request');
      expect(map(const PostgrestException(message: 'no code')),
          isA<InfrastructureFailure>());
    });
  });

  group('identity', () {
    test('a retryable fetch failure is a network failure', () {
      expect(map(AuthRetryableFetchException()), isA<NetworkFailure>());
    });

    test('an address already registered is a conflict, with its reason', () {
      expect(
        map(const AuthException('User already registered', statusCode: '422')),
        isA<ConflictFailure>().having(
            (f) => f.reason, 'reason', FailureReason.emailAlreadyUsed),
      );
      expect(map(const AuthException('Email already in use')).reason,
          FailureReason.emailAlreadyUsed,
          reason: 'the wording carries it when the status code does not');
    });

    test('any other auth refusal is an authentication failure', () {
      expect(map(const AuthException('Invalid login credentials', statusCode: '400')),
          isA<AuthenticationFailure>());
    });
  });

  group('transport and the unclassified', () {
    test('a socket failure is a network failure', () {
      expect(map(const SocketException('no route to host')),
          isA<NetworkFailure>());
    });

    test('a timeout is a network failure', () {
      expect(map(TimeoutException('too slow')), isA<NetworkFailure>());
    });

    test('anything unrecognised is an unknown failure', () {
      expect(map(StateError('bad state')), isA<UnknownFailure>());
      expect(map('a bare string'), isA<UnknownFailure>());
    });
  });

  group('failures the adapter raised itself', () {
    test('pass through untouched rather than being wrapped again', () {
      const original = ConflictFailure(FailureReason.alreadyMember);
      expect(identical(map(original), original), isTrue);
      expect(map(const InfrastructureFailure()), isA<InfrastructureFailure>());
    });
  });

  group('guarded', () {
    test('returns the value when the call succeeds', () async {
      expect(await guarded(() async => 42), 42);
    });

    test('converts whatever the call throws', () async {
      expect(
        guarded<void>(() async => throw const SocketException('down')),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('lets a Failure through unchanged', () async {
      expect(
        guarded<void>(
            () async => throw const AuthorizationFailure()),
        throwsA(isA<AuthorizationFailure>()),
      );
    });
  });
}
