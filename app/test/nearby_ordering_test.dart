import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';

/// The rule Discover orders by, asserted as a rule.
///
/// Both functions are pure -- no clock, no adapter -- so nothing here needs a
/// widget or a fake port. What is pinned: the local group comes first, the rest
/// follows, each group has its own order, a community with no Wilayat is simply
/// non-local, and the order is total.
void main() {
  const sohar = 7;
  const salalah = 51;
  const muscat = 1;

  final base = DateTime(2027, 3, 6, 18);

  PublicMatch match(
    String id, {
    int? wilayat,
    Duration start = Duration.zero,
    Duration length = const Duration(hours: 2),
  }) =>
      PublicMatch(
        id: id,
        communityId: 'c-$id',
        communityName: 'Community $id',
        location: 'Pitch',
        startAt: base.add(start),
        endAt: base.add(start + length),
        startingPlayers: 10,
        openSlots: 4,
        wilayatCode: wilayat,
      );

  PublicCommunity community(
    String id, {
    int? wilayat,
    DateTime? activity,
  }) =>
      PublicCommunity(
        id: id,
        name: 'Community $id',
        memberCount: 5,
        upcomingMatchCount: 1,
        wilayatCode: wilayat,
        lastActivityAt: activity,
      );

  List<String> ids(Iterable<PublicMatch> matches) =>
      [for (final m in matches) m.id];
  List<String> cids(Iterable<PublicCommunity> cs) => [for (final c in cs) c.id];

  group('Upcoming Matches', () {
    test('the local group comes first, then everything else', () {
      final ordered = DiscoverRepository.orderUpcomingMatches(
        [
          match('far-early', wilayat: salalah),
          match('near-late', wilayat: sohar, start: const Duration(days: 3)),
          match('far-later', wilayat: muscat, start: const Duration(days: 1)),
          match('near-early', wilayat: sohar, start: const Duration(days: 1)),
        ],
        nearWilayatCode: sohar,
      );

      expect(
          ids(ordered), ['near-early', 'near-late', 'far-early', 'far-later']);
    });

    test('each group is ordered by start, ascending', () {
      final ordered = DiscoverRepository.orderUpcomingMatches(
        [
          match('c', wilayat: sohar, start: const Duration(days: 5)),
          match('a', wilayat: sohar, start: const Duration(days: 1)),
          match('b', wilayat: sohar, start: const Duration(days: 2)),
          match('z', wilayat: salalah, start: const Duration(days: 4)),
          match('y', wilayat: salalah, start: const Duration(days: 3)),
        ],
        nearWilayatCode: sohar,
      );

      expect(ids(ordered), ['a', 'b', 'c', 'y', 'z']);
    });

    test('a match in play leads its group without being sorted specially', () {
      // LIVE is a state. The order is start ascending, and a match that has
      // begun starts earlier than one that has not.
      final now = base.add(const Duration(hours: 1));
      final live = match('live', wilayat: sohar); // base .. base+2h
      final soon =
          match('soon', wilayat: sohar, start: const Duration(hours: 3));
      final later =
          match('later', wilayat: sohar, start: const Duration(days: 2));
      final farLive = match('far-live', wilayat: salalah);

      final ordered = DiscoverRepository.orderUpcomingMatches(
        [later, soon, farLive, live],
        nearWilayatCode: sohar,
      );

      expect(ids(ordered), ['live', 'soon', 'later', 'far-live']);
      expect(live.isLiveAt(now), isTrue);
      expect(soon.isLiveAt(now), isFalse);
      expect(farLive.isLiveAt(now), isTrue,
          reason: 'live is judged the same way wherever the match is');
    });

    test('live is start <= now < end, at both edges', () {
      final m = match('edge'); // base .. base+2h
      expect(m.isLiveAt(base.subtract(const Duration(seconds: 1))), isFalse);
      expect(m.isLiveAt(base), isTrue, reason: 'start_at <= now');
      expect(m.isLiveAt(base.add(const Duration(hours: 2))), isFalse,
          reason: 'now < end_at, so the end instant is not live');
      expect(
        m.isLiveAt(base.add(const Duration(hours: 2, seconds: -1))),
        isTrue,
      );
    });

    test('with nothing local the non-local results are simply shown', () {
      final ordered = DiscoverRepository.orderUpcomingMatches(
        [
          match('b', wilayat: salalah, start: const Duration(days: 2)),
          match('a', wilayat: muscat, start: const Duration(days: 1)),
        ],
        nearWilayatCode: sohar,
      );

      expect(ids(ordered), ['a', 'b']);
    });

    test('no Near means everything is non-local, by start', () {
      final ordered = DiscoverRepository.orderUpcomingMatches([
        match('b', wilayat: sohar, start: const Duration(days: 2)),
        match('a', wilayat: salalah, start: const Duration(days: 1)),
      ]);

      expect(ids(ordered), ['a', 'b']);
    });

    test('a match whose community has no Wilayat is non-local', () {
      final ordered = DiscoverRepository.orderUpcomingMatches(
        [
          match('none-early'),
          match('near-late', wilayat: sohar, start: const Duration(days: 9)),
        ],
        nearWilayatCode: sohar,
      );

      expect(ids(ordered), ['near-late', 'none-early']);
    });

    test('equal starts are ordered by id, so the order is total', () {
      final shuffled = [
        match('m3', wilayat: sohar),
        match('m1', wilayat: sohar),
        match('m2', wilayat: sohar),
      ];

      final once = DiscoverRepository.orderUpcomingMatches(
        shuffled,
        nearWilayatCode: sohar,
      );
      final again = DiscoverRepository.orderUpcomingMatches(
        shuffled.reversed.toList(),
        nearWilayatCode: sohar,
      );

      expect(ids(once), ['m1', 'm2', 'm3']);
      expect(ids(again), ids(once));
    });

    test('the input is not modified', () {
      final input = [
        match('b', wilayat: salalah, start: const Duration(days: 2)),
        match('a', wilayat: sohar, start: const Duration(days: 1)),
      ];
      DiscoverRepository.orderUpcomingMatches(input, nearWilayatCode: sohar);

      expect(ids(input), ['b', 'a']);
    });

    test('changing Near re-derives the order from the same rows', () {
      final rows = [
        match('sohar', wilayat: sohar, start: const Duration(days: 2)),
        match('salalah', wilayat: salalah, start: const Duration(days: 1)),
      ];

      expect(
        ids(DiscoverRepository.orderUpcomingMatches(rows,
            nearWilayatCode: sohar)),
        ['sohar', 'salalah'],
      );
      expect(
        ids(DiscoverRepository.orderUpcomingMatches(rows,
            nearWilayatCode: salalah)),
        ['salalah', 'sohar'],
      );
    });

    test('a community that moves takes its matches with it', () {
      // A match holds no Wilayat of its own: it reads its community's current
      // one. The same fixture, before and after the owner moves the community,
      // therefore changes group without a single match being edited.
      PublicMatch fixture(int wilayat) =>
          match('fixture', wilayat: wilayat, start: Duration.zero);
      final other =
          match('other', wilayat: sohar, start: const Duration(days: 1));

      expect(
        ids(DiscoverRepository.orderUpcomingMatches(
          [fixture(sohar), other],
          nearWilayatCode: sohar,
        )),
        ['fixture', 'other'],
      );
      expect(
        ids(DiscoverRepository.orderUpcomingMatches(
          [fixture(salalah), other],
          nearWilayatCode: sohar,
        )),
        ['other', 'fixture'],
        reason: 'moved away: now after the local group, though it starts first',
      );
      expect(
        ids(DiscoverRepository.orderUpcomingMatches(
          [fixture(salalah), other],
          nearWilayatCode: salalah,
        )),
        ['fixture', 'other'],
        reason: 'and it leads for a reader near where it moved to',
      );
    });
  });

  group('Communities', () {
    final jan = DateTime.utc(2027, 1, 1);
    final feb = DateTime.utc(2027, 2, 1);
    final mar = DateTime.utc(2027, 3, 1);

    test('the local group comes first, then everything else', () {
      final ordered = DiscoverRepository.orderCommunities(
        [
          community('far-new', wilayat: salalah, activity: mar),
          community('near-old', wilayat: sohar, activity: jan),
        ],
        nearWilayatCode: sohar,
      );

      expect(cids(ordered), ['near-old', 'far-new']);
    });

    test('each group is ordered by latest activity, newest first', () {
      final ordered = DiscoverRepository.orderCommunities(
        [
          community('n-old', wilayat: sohar, activity: jan),
          community('f-new', wilayat: salalah, activity: mar),
          community('n-new', wilayat: sohar, activity: feb),
          community('f-old', wilayat: salalah, activity: jan),
        ],
        nearWilayatCode: sohar,
      );

      expect(cids(ordered), ['n-new', 'n-old', 'f-new', 'f-old']);
    });

    test('a community with no Wilayat is non-local and ordered like the rest',
        () {
      final ordered = DiscoverRepository.orderCommunities(
        [
          community('far-old', wilayat: salalah, activity: jan),
          community('none-new', activity: mar),
          community('none-mid', activity: feb),
          community('near', wilayat: sohar, activity: jan),
        ],
        nearWilayatCode: sohar,
      );

      // No third group and no forced last place: the two without a Wilayat
      // interleave with the other non-local community purely by activity.
      expect(cids(ordered), ['near', 'none-new', 'none-mid', 'far-old']);
    });

    test('with nothing local the non-local results are simply shown', () {
      final ordered = DiscoverRepository.orderCommunities(
        [
          community('old', wilayat: salalah, activity: jan),
          community('new', wilayat: muscat, activity: mar),
        ],
        nearWilayatCode: sohar,
      );

      expect(cids(ordered), ['new', 'old']);
    });

    test('no Near means every community is non-local', () {
      final ordered = DiscoverRepository.orderCommunities([
        community('old', wilayat: sohar, activity: jan),
        community('new', wilayat: salalah, activity: mar),
      ]);

      expect(cids(ordered), ['new', 'old']);
    });

    test('equal activity is broken by id, deterministically', () {
      final shuffled = [
        community('b', wilayat: sohar, activity: feb),
        community('c', wilayat: sohar, activity: feb),
        community('a', wilayat: sohar, activity: feb),
      ];

      expect(
        cids(DiscoverRepository.orderCommunities(shuffled,
            nearWilayatCode: sohar)),
        ['a', 'b', 'c'],
      );
      expect(
        cids(DiscoverRepository.orderCommunities(shuffled.reversed.toList(),
            nearWilayatCode: sohar)),
        ['a', 'b', 'c'],
      );
    });

    test('a row that carries no activity sorts as the oldest', () {
      final ordered = DiscoverRepository.orderCommunities(
        [
          community('unknown', wilayat: sohar),
          community('known', wilayat: sohar, activity: jan),
        ],
        nearWilayatCode: sohar,
      );

      expect(cids(ordered), ['known', 'unknown']);
    });

    test('moving a community changes its group and nothing else', () {
      PublicCommunity moved(int wilayat) =>
          community('mover', wilayat: wilayat, activity: mar);
      final resident = community('resident', wilayat: sohar, activity: jan);

      expect(
        cids(DiscoverRepository.orderCommunities([moved(sohar), resident],
            nearWilayatCode: sohar)),
        ['mover', 'resident'],
      );
      expect(
        cids(DiscoverRepository.orderCommunities([moved(salalah), resident],
            nearWilayatCode: sohar)),
        ['resident', 'mover'],
      );
    });

    test('the input is not modified', () {
      final input = [
        community('b', wilayat: salalah, activity: jan),
        community('a', wilayat: sohar, activity: feb),
      ];
      DiscoverRepository.orderCommunities(input, nearWilayatCode: sohar);

      expect(cids(input), ['b', 'a']);
    });
  });
}
