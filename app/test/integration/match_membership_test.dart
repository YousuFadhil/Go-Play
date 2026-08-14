@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/infrastructure/supabase/supabase_match_adapter.dart';

import 'support.dart';

/// Why a match did not load, against a real project.
///
/// The policy itself is not on trial here — `authorization_test.dart` already
/// proves that a non-member reads no match — and nothing in migration `0042`
/// changes it. What is proved here is the follow-up question: that a non-member
/// still gets nothing of the match, and that the context call tells them which
/// community to join without telling them anything about the match.
void main() {
  if (!integrationConfigured) {
    test('match membership context', () {}, skip: skipReason);
    return;
  }

  late TestUser owner;
  late TestUser player;
  late TestUser outsider;
  late String communityId;
  late String matchId;

  MatchService serviceFor(TestUser user) =>
      MatchService(SupabaseMatchAdapter(user.client));

  setUpAll(() async {
    owner = await signInTestUser('owner');
    player = await signInTestUser('player');
    outsider = await signInTestUser('outsider');
  });

  setUp(() async {
    communityId = await createCommunity(owner, 'ITest Membership');
    await addMember(owner, communityId, player);
    matchId = await createMatch(
      owner,
      communityId,
      startsIn: const Duration(days: 26),
    );
  });

  tearDown(() async => disposeCommunity(owner, communityId));

  test('a non-member still reads no match at all', () async {
    // The rule this feature must not weaken, restated where the feature lives.
    await expectLater(
      serviceFor(outsider).fetchMatch(matchId),
      throwsA(isA<Failure>()),
    );
  });

  test('a non-member is told which community to join, and nothing more',
      () async {
    final context = await serviceFor(outsider).fetchAccessContext(matchId);

    expect(context.matchExists, isTrue);
    expect(context.isMember, isFalse);
    expect(context.membershipRequired, isTrue);
    expect(context.communityId, communityId);
    expect(context.communityName, 'ITest Membership');
    expect(context.joinPolicy, isNotNull);
  });

  test('the context carries no match data', () async {
    // Asked directly, so what is checked is the column list the database sends
    // rather than what the model has room for.
    final rows = await outsider.client.rpc(
      'match_membership_context',
      params: {'p_match_id': matchId},
    ) as List<dynamic>;

    final row = (rows.first as Map<String, dynamic>).keys.toSet();
    expect(row, {
      'match_exists',
      'community_id',
      'community_name',
      'join_policy',
      'is_member',
    });
  });

  test('a member is told they are one', () async {
    final context = await serviceFor(player).fetchAccessContext(matchId);

    expect(context.isMember, isTrue);
    expect(context.membershipRequired, isFalse);
  });

  test('an id that names no match says so, and names no community', () async {
    final context = await serviceFor(outsider)
        .fetchAccessContext('00000000-0000-0000-0000-000000000000');

    expect(context.matchExists, isFalse);
    expect(context.membershipRequired, isFalse);
    expect(context.communityId, isNull);
    expect(context.communityName, isNull);
  });

  test('joining the community makes the match readable', () async {
    await addMember(owner, communityId, outsider);

    final match = await serviceFor(outsider).fetchMatch(matchId);
    expect(match.id, matchId);

    final context = await serviceFor(outsider).fetchAccessContext(matchId);
    expect(context.isMember, isTrue);
  });
}
