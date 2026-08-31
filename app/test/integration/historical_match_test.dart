@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/infrastructure/supabase/supabase_match_adapter.dart';

import 'support.dart';

/// Recording a match that has already been played, against a real project
/// (migration `0054`).
///
/// The widget suite proves the screen sends the flag. This proves what the
/// database does with it, which is the half that cannot be faked: that the two
/// temporal rules are genuinely exclusive, that the marker is stored, and that
/// a recorded match refuses a registration from every direction — the player's
/// own and an organizer's on their behalf.
///
/// Everything goes through `SupabaseMatchAdapter` rather than calling the RPC
/// directly, so what is proven is the whole path the create screen takes: the
/// parameters the adapter sends, the refusal the function raises, and the
/// `Failure` the mapper turns it into.
///
/// Day 44 is this file's forward match window, kept clear of the other
/// integration files: the suite runs in parallel over six shared accounts.
void main() {
  if (!integrationConfigured) {
    test('historical match entry', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player;
  late String communityId;

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Historical Match');
    await addMember(owner, communityId, player);
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
  });

  SupabaseMatchAdapter matchesOf(TestUser actor) =>
      SupabaseMatchAdapter(actor.client);

  /// Records a played match [ago] before now, lasting two hours.
  Future<void> record(
    TestUser actor, {
    Duration ago = const Duration(days: 7),
    String title = 'ITest recorded match',
    int startingPlayers = 4,
    bool isHistorical = true,
  }) async {
    final start = DateTime.now().subtract(ago);
    await matchesOf(actor).createMatch(
      communityId: communityId,
      title: title,
      location: 'ITest pitch',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      startingPlayers: startingPlayers,
      isHistorical: isHistorical,
    );
  }

  Future<Match> theMatch() async {
    final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
    expect(matches, hasLength(1));
    return matches.single;
  }

  group('the two temporal rules are exclusive', () {
    test('a past match is accepted on the historical path', () async {
      await record(owner);

      final match = await theMatch();
      expect(match.isHistorical, isTrue,
          reason: 'the marker is stored, not inferred');
      expect(match.startAt.isBefore(DateTime.now()), isTrue);
      expect(match.endAt.isBefore(DateTime.now()), isTrue);
      // Completed by the same rule `v_completed_matches` applies, without any
      // new status and without anything having touched the row.
      expect(match.isCompleted, isTrue);
    });

    test('START_IN_PAST — and refused on the ordinary one', () async {
      // The identical schedule, with the flag off. Nothing about an accidental
      // past date is weakened by the historical path existing.
      await expectLater(
        record(owner, isHistorical: false),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.startInPast)),
      );
    });

    test('HISTORICAL_NOT_PAST — a fixture still to come is not a record',
        () async {
      final start = DateTime.now().add(const Duration(days: 44));
      await expectLater(
        matchesOf(owner).createMatch(
          communityId: communityId,
          title: 'ITest not yet played',
          location: 'ITest pitch',
          startAt: start,
          endAt: start.add(const Duration(hours: 2)),
          startingPlayers: 4,
          isHistorical: true,
        ),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.historicalNotPast)),
      );
    });

    test('INVALID_TIME_RANGE — the end still comes after the start', () async {
      final start = DateTime.now().subtract(const Duration(days: 7));
      await expectLater(
        matchesOf(owner).createMatch(
          communityId: communityId,
          title: 'ITest inverted',
          location: 'ITest pitch',
          startAt: start,
          endAt: start.subtract(const Duration(hours: 2)),
          startingPlayers: 4,
          isHistorical: true,
        ),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.invalidTimeRange)),
      );
    });

    test('every other validation is untouched', () async {
      await expectLater(
        record(owner, title: 'x'),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.invalidTitle)),
      );
      await expectLater(
        record(owner, startingPlayers: 2),
        throwsA(isA<ValidationFailure>().having(
            (f) => f.reason, 'reason', FailureReason.invalidStartingPlayers)),
      );
    });

    test('NOT_AUTHORIZED — a player may not record one either', () async {
      await expectLater(record(player), throwsA(isA<AuthorizationFailure>()));
    });
  });

  group('a recorded match takes no registration', () {
    setUp(() async => record(owner));

    test('MATCH_HISTORICAL — not from the player themselves', () async {
      final match = await theMatch();
      await expectLater(
        matchesOf(player).registerForMatch(match.id),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.matchHistorical)),
      );
    });

    test('nor from an organizer adding them', () async {
      // `admin_add_player_to_match` goes through the same helper, so the one
      // guard closes both doors. This is what makes the rule the server's
      // rather than the create screen's.
      final match = await theMatch();
      await expectLater(
        matchesOf(owner).addPlayerToMatch(match.id, player.id),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.matchHistorical)),
      );
    });

    test('so there is no reserve queue on it at all', () async {
      // Nothing can be registered, so nothing can be queued, so nothing can be
      // promoted. The roster is empty until an organizer records who played.
      final match = await theMatch();
      final roster = await matchesOf(owner).fetchRegistrations(match.id);
      expect(roster, isEmpty);
    });
  });

  group('an ordinary match is unaffected', () {
    test('it is not historical, and it still takes registrations', () async {
      final start = DateTime.now().add(const Duration(days: 44));
      await matchesOf(owner).createMatch(
        communityId: communityId,
        title: 'ITest ordinary match',
        location: 'ITest pitch',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 4,
      );

      final match = await theMatch();
      expect(match.isHistorical, isFalse);

      final status = await matchesOf(player).registerForMatch(match.id);
      expect(status, RegistrationStatus.confirmed);
    });
  });
}
