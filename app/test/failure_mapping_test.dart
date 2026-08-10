import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stands in for the private `_ClientSocketException` that `IOClient` throws on
/// Android when the socket fails.
///
/// The real one cannot be constructed from here and naming its `SocketException`
/// half would put `dart:io` back in this file, which is what stopped the suite
/// compiling for the web. What matters to the mapper is the shape rather than
/// the identity: the native type is a [ClientException] *subclass*, so this
/// asserts the classification follows the subtype and not just the exact class.
class _SocketClientException extends ClientException {
  _SocketClientException(super.message);
}

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

    test('create_match refusals keep their reason', () {
      expect(map(raised('INVALID_TITLE')),
          isA<ValidationFailure>()
              .having((f) => f.reason, 'reason', FailureReason.invalidTitle));
      expect(map(raised('INVALID_LOCATION')),
          isA<ValidationFailure>()
              .having((f) => f.reason, 'reason', FailureReason.invalidLocation));
      expect(map(raised('START_IN_PAST')),
          isA<ValidationFailure>()
              .having((f) => f.reason, 'reason', FailureReason.startInPast));
    });

    test('an inactive community is a conflict, not bad input', () {
      // The id sent is the one meant; the community's state is what refuses.
      // Same shape as MATCH_COMPLETED and MATCH_LOCKED, same classification.
      expect(map(raised('COMMUNITY_INACTIVE')),
          isA<ConflictFailure>().having(
              (f) => f.reason, 'reason', FailureReason.communityInactive));
    });

    test('a missing match is not found, with its reason', () {
      expect(map(raised('MATCH_NOT_FOUND')),
          isA<NotFoundFailure>()
              .having((f) => f.reason, 'reason', FailureReason.matchNotFound));
    });

    test('a call with no session is an authentication failure, no reason', () {
      final failure = map(raised('NOT_AUTHENTICATED'));
      expect(failure, isA<AuthenticationFailure>());
      expect(failure.reason, isNull,
          reason: 'the type already says it, exactly as with NOT_AUTHORIZED');
    });

    test('NOT_AUTHENTICATED and NOT_AUTHORIZED are not confused', () {
      // The scan matches by substring and these two share a prefix. Neither
      // contains the other, and the classification differs, so a mix-up would
      // report a signed-out caller as forbidden or a forbidden one as
      // signed out.
      expect(map(raised('NOT_AUTHENTICATED')), isA<AuthenticationFailure>());
      expect(map(raised('NOT_AUTHORIZED')), isA<AuthorizationFailure>());
    });

    test('no create_match token is mistaken for a match-management one', () {
      // INVALID_TITLE and INVALID_TIME_RANGE share a prefix; MATCH_NOT_FOUND
      // and COMMUNITY_NOT_FOUND share a suffix.
      expect(map(raised('INVALID_TITLE')).reason,
          isNot(FailureReason.invalidTimeRange));
      expect(map(raised('INVALID_TIME_RANGE')).reason,
          isNot(FailureReason.invalidTitle));
      expect(map(raised('MATCH_NOT_FOUND')).reason,
          isNot(FailureReason.communityNotFound));
      expect(map(raised('COMMUNITY_NOT_FOUND')).reason,
          isNot(FailureReason.matchNotFound));
      expect(map(raised('COMMUNITY_INACTIVE')).reason,
          isNot(FailureReason.communityNotFound));
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

    test('result refusals are validation failures with their reason', () {
      expect(map(raised('INVALID_SCORE')),
          isA<ValidationFailure>()
              .having((f) => f.reason, 'reason', FailureReason.invalidScore));
      expect(map(raised('INVALID_GOALS')).reason, FailureReason.invalidGoals);
      expect(map(raised('GOALS_DO_NOT_MATCH_SCORE')).reason,
          FailureReason.goalsDoNotMatchScore);
      expect(map(raised('MVP_NOT_PARTICIPANT')).reason,
          FailureReason.mvpNotParticipant);
      expect(map(raised('SCORER_NOT_PARTICIPANT')).reason,
          FailureReason.scorerNotParticipant);
      expect(map(raised('LINEUP_REQUIRED')).reason,
          FailureReason.lineupRequired);
    });

    test('correcting a played match has its own refusals', () {
      // Both are states the operation ran into rather than input the caller got
      // wrong, so both are conflicts — the same shape as MATCH_COMPLETED.
      expect(
          map(raised('RESULT_PARTICIPANT_REMOVED')),
          isA<ConflictFailure>().having((f) => f.reason, 'reason',
              FailureReason.resultParticipantRemoved));
      expect(
          map(raised('MATCH_NOT_COMPLETED')),
          isA<ConflictFailure>().having(
              (f) => f.reason, 'reason', FailureReason.matchNotCompleted));

      expect(map(raised('INVALID_TEAM')),
          isA<ValidationFailure>()
              .having((f) => f.reason, 'reason', FailureReason.invalidTeam));
      expect(map(raised('INVALID_POSITION')).reason,
          FailureReason.invalidPosition);
    });

    test('MATCH_NOT_COMPLETED is not read as MATCH_COMPLETED', () {
      // The scan matches by substring and the two tokens are one word apart, so
      // this is the pair most likely to be confused.
      expect(map(raised('MATCH_NOT_COMPLETED')).reason,
          FailureReason.matchNotCompleted);
      expect(map(raised('MATCH_COMPLETED')).reason,
          FailureReason.matchCompleted);
    });

    test('no result token is mistaken for another', () {
      // The scan matches by substring, so the tokens have to stay distinct —
      // `MVP_NOT_PARTICIPANT` and `SCORER_NOT_PARTICIPANT` in particular.
      expect(map(raised('MVP_NOT_PARTICIPANT')).reason,
          isNot(FailureReason.scorerNotParticipant));
      expect(map(raised('INVALID_SCORE')).reason,
          isNot(FailureReason.goalsDoNotMatchScore));
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
    test('a dropped connection is a network failure', () {
      // What `BrowserClient` throws for a network or CORS failure on the web,
      // and what `IOClient` throws for a DNS or refused-connection failure on
      // Android.
      expect(map(ClientException('no route to host')), isA<NetworkFailure>());
    });

    test('a native socket failure is still a network failure', () {
      // Android does not deliver the bare exception: `IOClient` rethrows it as
      // a subclass. Asserted separately because a mapper written against the
      // exact class rather than the subtype would pass the test above and then
      // report every real dropped connection on a phone as UnknownFailure.
      expect(map(_SocketClientException('connection refused')),
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
        guarded<void>(() async => throw ClientException('down')),
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
