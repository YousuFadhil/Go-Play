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

    test('a profile the viewer may not open is an authorization refusal', () {
      // It words itself rather than falling back on the generic permission
      // sentence, because "you do not have permission" would name a rule the
      // reader has no way of knowing exists. The *type* is still what
      // behaviour follows.
      expect(map(raised('PROFILE_NOT_VISIBLE')),
          isA<AuthorizationFailure>().having(
              (f) => f.reason, 'reason', FailureReason.profileNotVisible));
      expect(map(raised('USER_NOT_FOUND')),
          isA<NotFoundFailure>().having(
              (f) => f.reason, 'reason', FailureReason.profileNotFound));
    });

    test('editing an account: who may be edited is a permission refusal', () {
      // The console words it once, because it already knows whether the account
      // is the administrator's own or a System Admin's.
      expect(map(raised('CANNOT_MODIFY_SELF')), isA<AuthorizationFailure>());
      expect(map(raised('CANNOT_MODIFY_SYSTEM_ADMIN')),
          isA<AuthorizationFailure>());
      // And neither is mistaken for the membership refusals they resemble.
      expect(map(raised('CANNOT_MODIFY_SELF')).reason,
          isNot(FailureReason.cannotRemoveSelf));
      expect(map(raised('CANNOT_MODIFY_SYSTEM_ADMIN')).reason, isNull);
    });

    test('editing an account: every value the database refuses is input', () {
      for (final token in [
        'INVALID_FULL_NAME',
        'INVALID_PHONE',
        'INVALID_DATE_OF_BIRTH',
        'INVALID_POSITION',
        'INVALID_WILAYAT',
        'INVALID_SETTINGS',
      ]) {
        expect(map(raised(token)), isA<ValidationFailure>(), reason: token);
      }
      // The new token carries no reason: the console words it for the group.
      expect(map(raised('INVALID_SETTINGS')).reason, isNull);
    });

    test('editing an account: an unknown id is not found', () {
      expect(map(raised('USER_NOT_FOUND')), isA<NotFoundFailure>());
    });

    test('previewing a merge: the same account twice is input, not a fault', () {
      // Migration 0096. The screen never offers the same account twice, so
      // reaching this means the request was built some other way.
      expect(map(raised('SAME_ACCOUNT')), isA<ValidationFailure>());
      expect(map(raised('SAME_ACCOUNT')).reason, isNull);
    });

    test('merging accounts: the administrator cannot be either account', () {
      // Migration 0101. A permission refusal, as with editing their own.
      expect(map(raised('CANNOT_MERGE_SELF')), isA<AuthorizationFailure>());
      expect(map(raised('CANNOT_MERGE_SELF')).reason, isNull);
    });

    test('merging accounts: what stands in the way is a state to look at again',
        () {
      // A blocker that appeared since the preview, a choice that is missing, or
      // one that would discard goals, an MVP award, a result or a confirmed
      // lineup: not bad input, so the screen asks for the preview again.
      for (final token in [
        'MERGE_BLOCKED',
        'RESOLUTION_REQUIRED',
        'RESOLUTION_BLOCKED',
        'RESOLUTION_UNKNOWN_MATCH',
      ]) {
        expect(map(raised(token)), isA<ConflictFailure>(), reason: token);
        expect(map(raised(token)).reason, isNull, reason: token);
      }
      expect(map(raised('RESOLUTIONS_INVALID')), isA<ValidationFailure>());
    });

    test('merging accounts: what the Edge Function adds to the database\'s own',
        () {
      expect(map(raised('SOURCE_FILES_REMAIN')), isA<ConflictFailure>());
      expect(map(raised('MERGE_OUTCOME_UNKNOWN')), isA<InfrastructureFailure>());
      expect(map(raised('PREFLIGHT_FAILED')), isA<InfrastructureFailure>());
      expect(map(raised('REQUEST_FAILED')), isA<InfrastructureFailure>());
      expect(map(raised('BAD_REQUEST')), isA<ValidationFailure>());
      // The merge was never attempted: the picture could not be removed.
      expect(
        map(raised('AVATAR_CLEANUP_FAILED')),
        isA<InfrastructureFailure>().having(
            (f) => f.reason, 'reason', FailureReason.mergeAvatarCleanupFailed),
      );
    });

    test('merging accounts: the merge checking its own work is a fault', () {
      // Each rolled the transaction back, and none is something the
      // administrator did.
      for (final token in [
        'MERGE_UNHANDLED_REFERENCE',
        'MERGE_RESIDUAL_REFERENCE',
        'MERGE_INVARIANT_BROKEN',
        'RATING_BASELINE_MISMATCH',
        'RATING_CHAIN_BROKEN',
        'AUTH_DELETE_INCOMPLETE',
      ]) {
        expect(map(raised(token)), isA<InfrastructureFailure>(), reason: token);
      }
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

      // Migration 0074's batch correction: a payload that is not an array, or
      // one naming the same player twice. Input the caller got wrong, so a
      // validation failure rather than a conflict.
      expect(
          map(raised('INVALID_CHANGES')),
          isA<ValidationFailure>().having(
              (f) => f.reason, 'reason', FailureReason.invalidChanges));
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

  group('an Edge Function answered', () {
    // The merge is requested through `admin-merge-accounts`, which answers a refusal as
    // {"error": TOKEN, "avatar_removed": bool} under an HTTP status.
    Failure answered(int status, Object? details) =>
        map(FunctionException(status: status, details: details));

    test('the database\'s own token is classified as it is for an RPC', () {
      expect(answered(403, {'error': 'NOT_AUTHORIZED'}),
          isA<AuthorizationFailure>());
      expect(answered(409, {'error': 'MERGE_BLOCKED', 'detail': 'X'}),
          isA<ConflictFailure>());
      expect(answered(404, {'error': 'USER_NOT_FOUND'}), isA<NotFoundFailure>());
      expect(answered(400, {'error': 'RESOLUTIONS_INVALID'}),
          isA<ValidationFailure>());
      expect(answered(401, {'error': 'NOT_AUTHENTICATED'}),
          isA<AuthenticationFailure>());
      expect(answered(502, {'error': 'MERGE_OUTCOME_UNKNOWN'}),
          isA<InfrastructureFailure>());
    });

    test('a picture already removed is said on top of whatever else failed', () {
      for (final entry in <(Map<String, Object?>, Type)>[
        ({'error': 'MERGE_BLOCKED', 'avatar_removed': true}, ConflictFailure),
        (
          {'error': 'MERGE_OUTCOME_UNKNOWN', 'avatar_removed': true},
          InfrastructureFailure
        ),
        (
          {'error': 'MERGE_INVARIANT_BROKEN', 'avatar_removed': true},
          InfrastructureFailure
        ),
      ]) {
        final failure = answered(500, entry.$1);
        expect(failure.runtimeType, entry.$2);
        expect(failure.reason, FailureReason.mergeAvatarRemoved);
      }
      expect(
        answered(409, {'error': 'MERGE_BLOCKED', 'avatar_removed': false})
            .reason,
        isNull,
      );
    });

    test('a failed cleanup keeps its own reason, whether or not part of the '
        'picture went', () {
      for (final removed in [true, false]) {
        final failure = answered(
            502, {'error': 'AVATAR_CLEANUP_FAILED', 'avatar_removed': removed});
        expect(failure, isA<InfrastructureFailure>());
        expect(failure.reason, FailureReason.mergeAvatarCleanupFailed);
      }
    });

    test('an answer from the platform, not the function, is read by status only',
        () {
      expect(answered(401, 'Invalid JWT'), isA<AuthenticationFailure>());
      expect(answered(403, null), isA<AuthorizationFailure>());
      // Not deployed, timed out, crashed: the service failed; it is not "the
      // account is gone".
      expect(answered(404, 'Requested function was not found'),
          isA<InfrastructureFailure>());
      expect(answered(500, {'message': 'boom'}), isA<InfrastructureFailure>());
      expect(answered(546, null), isA<InfrastructureFailure>());
    });

    test('a token this build does not know falls back to the status', () {
      expect(answered(409, {'error': 'SOMETHING_NEW'}),
          isA<InfrastructureFailure>());
      expect(answered(403, {'error': 'SOMETHING_NEW'}),
          isA<AuthorizationFailure>());
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
