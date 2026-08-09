@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/infrastructure/supabase/supabase_match_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

/// Match creation against a real project, through `create_match`.
///
/// Creation used to be a direct insert into `matches`, guarded by
/// `matches_insert_community_admins`. The policy was correct, but a policy can
/// only refuse a row — it cannot say which field was wrong, and it had nothing
/// to say about a match scheduled into the past. `create_match` (migration
/// `0026`) validates first and names what it refused.
///
/// Every case below goes through `SupabaseMatchAdapter` rather than calling the
/// RPC directly, so what is proven is the whole path the create screen takes:
/// the parameters the adapter sends, the refusal the function raises, and the
/// `Failure` the mapper turns it into. A test that called `rpc()` itself would
/// prove the database works and leave the application untested.
///
/// Day 40 is this file's match window, kept clear of the other integration
/// files for the reason `profile_test.dart` records: the suite runs in
/// parallel over six shared accounts.
void main() {
  if (!integrationConfigured) {
    test('match creation', () {}, skip: skipReason);
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
    communityId = await createCommunity(owner, 'ITest Match Creation');
    await addMember(owner, communityId, player);
  });

  tearDown(() async {
    await disposeCommunity(owner, communityId);
  });

  /// The adapter as [actor] holds it — the production path, over that account's
  /// session.
  SupabaseMatchAdapter matchesOf(TestUser actor) =>
      SupabaseMatchAdapter(actor.client);

  /// A schedule [startsIn] from now, lasting two hours.
  (DateTime, DateTime) window(Duration startsIn) {
    final start = DateTime.now().add(startsIn);
    return (start, start.add(const Duration(hours: 2)));
  }

  /// Creates a match as [actor], defaulting every field to something valid so
  /// each test varies only the one it is about.
  Future<void> create(
    TestUser actor, {
    String? inCommunity,
    String title = 'ITest created match',
    String location = 'ITest pitch',
    Duration startsIn = const Duration(days: 40),
    int startingPlayers = 10,
  }) async {
    final (start, end) = window(startsIn);
    await matchesOf(actor).createMatch(
      communityId: inCommunity ?? communityId,
      title: title,
      location: location,
      startAt: start,
      endAt: end,
      startingPlayers: startingPlayers,
    );
  }

  group('a match is created', () {
    test('an owner creates one, and the database fills in the rest', () async {
      await create(owner, startingPlayers: 10);

      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, hasLength(1));
      final match = matches.single;

      expect(match.title, 'ITest created match');
      expect(match.location, 'ITest pitch');
      expect(match.startingPlayers, 10);

      // `created_by` is no longer sent by the client. The function takes it
      // from `auth.uid()`, which is what the old insert policy checked the
      // client's value against anyway.
      expect(match.createdBy, owner.id,
          reason: 'created_by comes from the session, not from the request');

      // Capacity stays the trigger's to derive. The function does not compute
      // it and neither does the adapter, so the stored value must be the
      // trigger's arithmetic over the project's own reserve setting.
      final reserve = await matchesOf(owner).fetchReservePlayers();
      expect(match.maxRegistration, 10 + (reserve ?? 0),
          reason: 'matches_set_capacity derives max_registration');
    });

    test('an admin creates one too', () async {
      await addMember(owner, communityId, await signInTestUser('admin'),
          role: 'admin');
      final admin = await signInTestUser('admin');

      await create(admin, startsIn: const Duration(days: 41));

      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, hasLength(1));
      expect(matches.single.createdBy, admin.id);
    });
  });

  group('the refusals', () {
    test('START_IN_PAST — a match cannot be created already begun', () async {
      // The rule is not new: `update_match` refuses a match whose start has
      // passed, so one created that way could never be edited or cancelled.
      // The insert path allowed exactly that; this is what closed it.
      await expectLater(
        create(owner, startsIn: const Duration(hours: -2)),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.startInPast)),
      );

      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, isEmpty, reason: 'a refused creation writes nothing');
    });

    test('INVALID_TITLE — one character is not a name', () async {
      // The screen only asks that the field is non-empty; the database asks for
      // two characters after trimming. This is the gap between them.
      await expectLater(
        create(owner, title: 'x'),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.invalidTitle)),
      );
      await expectLater(
        create(owner, title: '   '),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.invalidTitle)),
      );
    });

    test('INVALID_LOCATION — the same rule, on the other field', () async {
      await expectLater(
        create(owner, location: 'x'),
        throwsA(isA<ValidationFailure>()
            .having((f) => f.reason, 'reason', FailureReason.invalidLocation)),
      );
    });

    test('NOT_AUTHORIZED — a player may not create a match', () async {
      // `player` is an ordinary member of this community. Creation is an
      // owner-or-admin operation (PD-07), and the function asks the same
      // `has_community_role` predicate the insert policy asked.
      await expectLater(
        create(player),
        throwsA(isA<AuthorizationFailure>()),
      );

      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, isEmpty);
    });

    test('COMMUNITY_INACTIVE cannot be reached from a client', () async {
      // The guard in `create_match` is real and was verified directly against
      // the function. What no client can do is produce the state it guards.
      //
      // `communities_select_visible` is `using (is_active)`, so clearing the
      // flag would leave the owner holding a row they could no longer see, and
      // PostgreSQL refuses an update whose result fails the select policy —
      // 42501, even though `communities_update_owner` permits the owner every
      // other edit to the same row. Nothing in migrations 0001-0026 sets
      // `communities.is_active = false` either, so no RPC produces it.
      //
      // What is testable from here is therefore the reachable half: that the
      // deactivation itself is refused. If that ever stops being true, a
      // community can be closed and this test should be replaced by one that
      // drives `create_match` into COMMUNITY_INACTIVE for real.
      await expectLater(
        owner.client
            .from('communities')
            .update({'is_active': false}).eq('id', communityId),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', '42501')),
      );

      // The community is untouched, so creation still works.
      await create(owner);
      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, hasLength(1));
    });

    test('a caller with no session is refused', () async {
      // `create_match` raises NOT_AUTHENTICATED when `auth.uid()` is null, but
      // a real client never gets that far: EXECUTE is revoked from `anon`, so
      // the grant refuses the call before the body runs. Both are refusals and
      // the app treats them the same; this records which one actually happens,
      // because the in-function guard is the backstop, not the gate.
      final anonymous = SupabaseClient(supabaseUrl, supabaseAnonKey);
      final (start, end) = window(const Duration(days: 40));

      await expectLater(
        SupabaseMatchAdapter(anonymous).createMatch(
          communityId: communityId,
          title: 'ITest created match',
          location: 'ITest pitch',
          startAt: start,
          endAt: end,
          startingPlayers: 10,
        ),
        throwsA(isA<Failure>()),
      );

      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, isEmpty, reason: 'a refused call writes nothing');
    });

    test('the guards run before anything is written', () async {
      // Four refusals in a row, then a valid creation. If any refusal had
      // written a partial row, the count at the end would not be one.
      await expectLater(create(owner, title: 'x'), throwsA(isA<Failure>()));
      await expectLater(create(owner, location: 'x'), throwsA(isA<Failure>()));
      await expectLater(create(owner, startsIn: const Duration(hours: -1)),
          throwsA(isA<Failure>()));
      await expectLater(create(player), throwsA(isA<Failure>()));

      await create(owner);
      final matches = await matchesOf(owner).fetchCommunityMatches(communityId);
      expect(matches, hasLength(1));
    });
  });
}
