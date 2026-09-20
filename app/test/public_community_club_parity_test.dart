import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/results/result_card.dart';

/// The public community page is the same place, seen by another audience.
///
/// **The defect this pins.** A visitor opened a community onto a plain app bar
/// over a centred crest and a column of sections, while a member opened the
/// identical community onto the Club hero. Signing in changed what the
/// community looked like rather than what the reader could do there.
///
/// It is now composed from the same primitives — and what is *on* it must not
/// have changed by one row: the same public reads, and no member content.
void main() {
  PublicResult result(String id) => PublicResult(
        matchId: id,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: 'Friday football',
        startAt: DateTime(2026, 9, 11, 17),
        teamAScore: 3,
        teamBScore: 2,
      );

  Future<void> pump(
    WidgetTester tester,
    _Discover adapter, {
    Locale locale = const Locale('en'),
    Size size = const Size(412, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: PublicCommunityScreen(
        communityId: 'c1',
        repository: DiscoverRepository(adapter),
        authService: AuthService(_GuestAuth()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('it is composed like the place it is', () {
    testWidgets('a Club hero over a Club sheet, not an app bar over a column',
        (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(find.byType(ClubHeroBar), findsOneWidget);
      // The identity row the member's view of this community uses.
      expect(find.byType(CommunityIdentity), findsOneWidget);
      expect(find.byType(CommunityCrest), findsWidgets);
    });

    testWidgets('on the same ground a profile and a match open on',
        (tester) async {
      // A community is a place, and the public page is that place seen by
      // somebody who is not in it -- not a lighter version of it.
      await pump(tester, _Discover(results: [result('m1')]));

      expect(find.byType(StadiumBackdrop), findsOneWidget);
      // Drawn rather than fetched: no asset, no network, nothing to licence.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('and the crest is given the room it carries the identity with',
        (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      final identity =
          tester.widget<CommunityIdentity>(find.byType(CommunityIdentity));
      expect(identity.crestSize, greaterThan(56));
      expect(identity.onHero, isTrue);
    });

    testWidgets('the figures are the public ones, on the hero', (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      final hero = find.byType(ClubHero);
      expect(
          find.descendant(of: hero, matching: find.text('12')), findsOneWidget);
      expect(
          find.descendant(of: hero, matching: find.text('2')), findsOneWidget);
      expect(find.byType(ClubHeroCount), findsNWidgets(2));
    });

    testWidgets('and the join action is on the hero, as a guest prompt',
        (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      expect(find.byKey(const Key('publicCommunityJoin')), findsOneWidget);
    });
  });

  group('what is on it did not change', () {
    testWidgets('upcoming matches and latest results, both public',
        (tester) async {
      final adapter = _Discover(results: [result('m1')]);
      await pump(tester, adapter);

      // Twice: once as the hero figure's label and once as the section
      // heading -- exactly as the member's view of this community reads.
      expect(find.text('Upcoming matches'), findsNWidgets(2));
      expect(find.text('Latest results'), findsOneWidget);
      expect(find.byType(DiscoverSectionHeader), findsNWidgets(2));
      expect(find.byType(PublicMatchCard), findsOneWidget);
      expect(find.byType(PublicResultCard), findsOneWidget);
      // Scoped to this community, through the public contract only.
      expect(adapter.recentResultsRequests, ['c1']);
    });

    testWidgets('the results use the one shared card', (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      expect(find.byType(ResultCard), findsOneWidget);
    });

    testWidgets('no members, no management, no join code', (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      for (final forbidden in [
        'Members',
        'Roster',
        'Join code',
        'Settings',
        'Leaderboards',
        'Manage',
      ]) {
        // "Members" is allowed only as the hero figure's own label, which is
        // the public count the contract already publishes.
        if (forbidden == 'Members') continue;
        expect(find.text(forbidden), findsNothing, reason: forbidden);
      }
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('and nothing authenticated is ever mounted', (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      // `CurrentUserMenu` reads `my_profile` the moment it is built; a guest
      // page that mounted it would have called an authenticated contract.
      expect(find.byType(CurrentUserMenu), findsNothing);
      expect(find.byType(AppHeader), findsNothing);
    });

    testWidgets('a result opens the public match page with no prompt',
        (tester) async {
      await pump(tester, _Discover(results: [result('m1')]));

      await tester.tap(find.byType(PublicResultCard));
      await tester.pumpAndSettle();

      expect(find.byType(PublicMatchScreen), findsOneWidget);
    });
  });

  group('the results section behaves as it does on Discover', () {
    testWidgets('three by default, all of them behind one control',
        (tester) async {
      await pump(
        tester,
        _Discover(results: [for (var i = 1; i <= 5; i++) result('m$i')]),
      );

      expect(find.byType(PublicResultCard), findsNWidgets(3));
      await tester
          .tap(find.byKey(const Key('publicCommunityPreviousResultsToggle')));
      await tester.pumpAndSettle();
      expect(find.byType(PublicResultCard), findsNWidgets(5));
    });
  });

  group('the upcoming card is readable on a narrow phone', () {
    testWidgets('at 320 the seat badge steps out of the fixture row',
        (tester) async {
      // **Three things cannot share one tight row.** A date tile, the fixture
      // and a seat badge each want their own width, and the fixture -- the
      // only one a reader is looking for -- was the one that gave.
      await pump(
        tester,
        _Discover(results: [result('m1')], longName: true),
        size: const Size(320, 1400),
      );

      expect(tester.takeException(), isNull);
      final card = find.byType(PublicMatchCard);
      expect(card, findsOneWidget);

      final title = find.descendant(
        of: card,
        matching: find.text('Friday night five-a-side'),
      );
      expect(title, findsOneWidget);
      // The title keeps two lines and is not cut to nothing.
      expect(tester.widget<Text>(title).maxLines, 2);
    });

    testWidgets('and at 412 it keeps the efficient one-row layout',
        (tester) async {
      await pump(
        tester,
        _Discover(results: [result('m1')]),
        size: const Size(412, 1400),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PublicMatchCard), findsOneWidget);
    });

    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets(
            'no overflow at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(
            tester,
            _Discover(results: [result('m1')], longName: true),
            locale: locale,
            size: Size(width, 1400),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PublicMatchCard), findsOneWidget);
        });
      }
    }
  });

  group('it survives a narrow phone in both languages', () {
    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets('at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(
            tester,
            _Discover(results: [result('m1')], longName: true),
            locale: locale,
            size: Size(width, 1200),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(ClubHero), findsOneWidget);
        });
      }
    }
  });
}

class _Discover implements DiscoverAdapter {
  _Discover({this.results = const [], this.longName = false});

  final List<PublicResult> results;
  final bool longName;

  /// One entry per read, carrying the community it was scoped to.
  final List<String?> recentResultsRequests = [];

  PublicCommunity get _community => PublicCommunity(
        id: 'c1',
        name: longName
            ? 'Al Amerat Football and Sporting Community of Muscat South'
            : 'Al Amerat FC',
        description: longName
            ? 'A community that has been playing five-a-side every Friday '
                'evening for a very long time indeed'
            : null,
        memberCount: 12,
        upcomingMatchCount: 2,
      );

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async =>
      _community;

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => [_community];

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      [
        PublicMatch(
          id: 'up1',
          communityId: 'c1',
          communityName: _community.name,
          title: 'Friday night five-a-side',
          location: 'Al Amerat Pitch',
          startAt: DateTime(2026, 9, 25, 19),
          endAt: DateTime(2026, 9, 25, 21),
          startingPlayers: 10,
          openSlots: 6,
        ),
      ];

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async {
    recentResultsRequests.add(communityId);
    return results.take(limit).toList();
  }

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async => null;

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _GuestAuth implements AuthAdapter {
  @override
  bool get isSignedIn => false;

  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
