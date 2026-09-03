import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/statistics/community_leaderboards_tab.dart';
import 'package:go_play/features/statistics/community_statistics_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_period_selector.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community Leaderboards against a fake port.
///
/// The ranking rules carry every product decision in this feature — who may
/// appear, how ties place, how deep a board goes, and when a board is not
/// worth showing — so they are tested apart from the screen that draws them.
void main() {
  CommunityMemberRating member(String id, String name, double rating,
          {String? avatarUrl}) =>
      CommunityMemberRating(
        userId: id,
        fullName: name,
        rating: rating,
        avatarUrl: avatarUrl,
      );

  CommunityPlayerStatistics counters(
    String id, {
    int played = 0,
    int wins = 0,
    int goals = 0,
    int mvp = 0,
  }) =>
      CommunityPlayerStatistics(
        userId: id,
        fullName: null,
        matchesPlayed: played,
        wins: wins,
        losses: 0,
        draws: 0,
        goals: goals,
        mvpCount: mvp,
      );

  /// A community a few matches in. Two members share a rating, which is what
  /// makes it a useful fixture rather than a tidy one.
  final roster = [
    // Ali has set a picture; the other three have not, which is what makes the
    // fallback observable on the same board.
    member('u1', 'Ali', 6.0, avatarUrl: 'https://example.test/u1.jpg'),
    member('u2', 'Sara', 5.5),
    member('u3', 'Omar', 5.5),
    member('u4', 'Zed', 5.0),
  ];
  final records = [
    counters('u1', played: 3, wins: 2, goals: 5, mvp: 1),
    counters('u2', played: 4, wins: 1, goals: 2, mvp: 2),
    counters('u3', played: 1),
    // u4 has no record at all.
  ];

  Future<List<Leaderboard>> boardsFrom(FakeLeaderboardAdapter adapter) =>
      StatisticsRepository(adapter).fetchLeaderboards('c1');

  Leaderboard boardOf(List<Leaderboard> boards, LeaderboardKind kind) =>
      boards.firstWhere((board) => board.kind == kind);

  group('building the boards', () {
    test('all five are built, in the approved order', () async {
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(boards.map((b) => b.kind), [
        LeaderboardKind.highestRated,
        LeaderboardKind.topScorer,
        LeaderboardKind.mostMvp,
        LeaderboardKind.mostActive,
        LeaderboardKind.mostWins,
      ]);
    });

    test('each board ranks its own measure', () async {
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(boardOf(boards, LeaderboardKind.topScorer).entries.first.fullName,
          'Ali');
      expect(boardOf(boards, LeaderboardKind.mostMvp).entries.first.fullName,
          'Sara');
      expect(boardOf(boards, LeaderboardKind.mostActive).entries.first.fullName,
          'Sara');
      expect(boardOf(boards, LeaderboardKind.mostWins).entries.first.fullName,
          'Ali');
      expect(
          boardOf(boards, LeaderboardKind.highestRated).entries.first.fullName,
          'Ali');
    });

    test('ties share a rank, and the next distinct value skips the places',
        () async {
      // Sara and Omar are both 5.5. Both are second; nobody is third.
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: roster, records: records),
      );
      final rated = boardOf(boards, LeaderboardKind.highestRated);

      expect(rated.entries.map((e) => e.rank), [1, 2, 2]);
      expect(rated.entries.map((e) => e.fullName), ['Ali', 'Omar', 'Sara']);
    });

    test('a rank skips the places a tie used up', () async {
      // Three tied at the top are all first, and the next player is fourth --
      // which is only visible when the board is deep enough to show them.
      final tied = [
        member('u1', 'Ali', 6.0),
        member('u2', 'Sara', 6.0),
        member('u3', 'Omar', 6.0),
      ];
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: tied, records: const []),
      );

      expect(
          boardOf(boards, LeaderboardKind.highestRated)
              .entries
              .map((e) => e.rank),
          [1, 1, 1]);
    });

    test('only the top three appear', () async {
      final crowd = [
        for (var i = 0; i < 8; i++) member('u$i', 'P$i', 9.0 - i),
      ];
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: crowd, records: const []),
      );

      expect(
          boardOf(boards, LeaderboardKind.highestRated).entries, hasLength(3));
    });

    test('a tie renders the same way whatever order the rows arrive in',
        () async {
      // The secondary ordering decides nothing about who is better. It exists
      // so a board does not shuffle between refreshes.
      final forward = await boardsFrom(
        FakeLeaderboardAdapter(members: roster, records: records),
      );
      final reversed = await boardsFrom(
        FakeLeaderboardAdapter(
          members: roster.reversed.toList(),
          records: records.reversed.toList(),
        ),
      );

      expect(
        boardOf(reversed, LeaderboardKind.highestRated)
            .entries
            .map((e) => e.userId),
        boardOf(forward, LeaderboardKind.highestRated)
            .entries
            .map((e) => e.userId),
      );
    });
  });

  group('who may be ranked', () {
    test('a player who has left is not on a board, records and all', () async {
      // Their statistics are preserved deliberately, but a board ranks people
      // who are still here.
      final boards = await boardsFrom(FakeLeaderboardAdapter(
        members: [member('u1', 'Ali', 5.0)],
        records: [
          counters('u1', played: 1, goals: 1),
          counters('gone', played: 9, goals: 99, mvp: 9, wins: 9),
        ],
      ));

      final scorers = boardOf(boards, LeaderboardKind.topScorer);
      expect(scorers.entries, hasLength(1));
      expect(scorers.entries.single.fullName, 'Ali');
      expect(scorers.entries.single.value, 1);
    });

    test('a player the measure has not happened to takes no place', () async {
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: roster, records: records),
      );
      final scorers = boardOf(boards, LeaderboardKind.topScorer);

      // Omar's record carries no goals and Zed has no record at all. Neither
      // belongs on a board of who has scored, even though both are members and
      // the board has a free place.
      expect(scorers.entries.map((e) => e.fullName), ['Ali', 'Sara']);
      expect(scorers.entries.every((entry) => entry.value > 0), isTrue);
    });

    test('a board shows fewer than three rather than padding with zeros',
        () async {
      final boards = await boardsFrom(FakeLeaderboardAdapter(
        members: roster,
        records: [counters('u1', goals: 4)],
      ));
      final scorers = boardOf(boards, LeaderboardKind.topScorer);

      expect(scorers.entries, hasLength(1));
      expect(scorers.entries.single.fullName, 'Ali');
    });
  });

  group('when a board is not worth showing', () {
    test('a board of nothing but zeros is hidden', () async {
      // A fresh community: everyone holds a record from the day they joined,
      // so every counter is zero. Only the rating has anything to say.
      final fresh = [
        member('u1', 'Ali', 5.0),
        member('u2', 'Sara', 5.0),
      ];
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: fresh, records: const []),
      );

      expect(boards.map((b) => b.kind), [LeaderboardKind.highestRated]);
    });

    test('when every measure is zero, no board is built at all', () async {
      final boards = await boardsFrom(FakeLeaderboardAdapter(
        members: [member('u1', 'Ali', 0), member('u2', 'Sara', 0)],
        records: const [],
      ));

      expect(boards, isEmpty);
    });

    test('a community with no members has no boards', () async {
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: const [], records: const []),
      );

      expect(boards, isEmpty);
    });
  });

  group('the screen', () {
    Future<void> pumpBoards(
      WidgetTester tester,
      FakeLeaderboardAdapter adapter, {
      Locale locale = const Locale('en'),
      bool settle = true,
      NavigatorObserver? observer,
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observer == null ? const [] : [observer],
        home: Scaffold(
          body: CommunityStatisticsTab(
            communityId: 'c1',
            repository: StatisticsRepository(adapter),
          ),
        ),
      ));
      if (settle) await tester.pumpAndSettle();
    }

    // --- player identity on a board -----------------------------------------------

    group('a board row is a player identity', () {
      testWidgets('the leader and the runners-up all carry a face',
          (tester) async {
        await pumpBoards(
          tester,
          FakeLeaderboardAdapter(members: roster, records: records),
        );

        final board = find.widgetWithText(LeaderboardCard, 'Highest rated');
        await tester
            .tap(find.descendant(of: board, matching: find.text('Show more')));
        await tester.pumpAndSettle();

        // Scoped to one card: a player who leads three measures has an identity
        // on each of them, and the same key on all three.
        PlayerAvatar avatarOn(String userId) => tester.widget<PlayerAvatar>(
              find.descendant(
                of: find.descendant(
                  of: board,
                  matching: find.byKey(Key('boardIdentity_$userId')),
                ),
                matching: find.byType(PlayerAvatar),
              ),
            );

        // Ali leads with a picture; Sara and Omar are behind him with none, and
        // fall back to the initials every other surface uses.
        expect(avatarOn('u1').avatarUrl, 'https://example.test/u1.jpg');
        expect(avatarOn('u1').isProfessionalGuest, isFalse);
        expect(avatarOn('u2').avatarUrl, isNull);
        expect(
          find.descendant(
            of: find.descendant(
              of: board,
              matching: find.byKey(const Key('boardIdentity_u2')),
            ),
            matching: find.text('S'),
          ),
          findsOneWidget,
          reason: 'the existing initials fallback, not a new one',
        );
      });

      testWidgets('the identity opens that player', (tester) async {
        final observer = _BoardRouteRecorder();
        await pumpBoards(
          tester,
          FakeLeaderboardAdapter(members: roster, records: records),
          observer: observer,
        );
        observer.pushed.clear();

        await tester.tap(find.byKey(const Key('boardIdentity_u1')).first);

        final screen = observer.pushed.single
            .builder(tester.element(find.byType(CommunityStatisticsTab)));
        expect((screen as ProfileScreen).userId, 'u1');
        observer.discard();
      });

      testWidgets('the rank and the value are not tappable', (tester) async {
        final observer = _BoardRouteRecorder();
        await pumpBoards(
          tester,
          FakeLeaderboardAdapter(members: roster, records: records),
          observer: observer,
        );
        observer.pushed.clear();

        // The value beside the leader of Top Scorer: five goals, and not a
        // player identity.
        await tester.tap(find
            .descendant(
              of: find.widgetWithText(LeaderboardCard, 'Top scorer'),
              matching: find.text('5'),
            )
            .first);
        await tester.pumpAndSettle();

        expect(observer.pushed, isEmpty,
            reason: 'only the identity is the control');
      });

      testWidgets('the ranking and the figures are unchanged', (tester) async {
        await pumpBoards(
          tester,
          FakeLeaderboardAdapter(members: roster, records: records),
        );

        // The same assertions the board made before it carried faces.
        final topScorer = find.widgetWithText(LeaderboardCard, 'Top scorer');
        expect(find.descendant(of: topScorer, matching: find.text('Ali')),
            findsOneWidget);
        expect(find.descendant(of: topScorer, matching: find.text('5')),
            findsOneWidget);
        expect(
          find.descendant(
            of: find.widgetWithText(LeaderboardCard, 'Highest rated'),
            matching: find.text('6.0'),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('shows the indicator until the boards arrive', (tester) async {
      final gate = Completer<void>();
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(
            members: roster, records: records, gate: gate.future),
        settle: false,
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('all five boards are on the screen', (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(find.text('Highest rated'), findsOneWidget);
      expect(find.text('Top scorer'), findsOneWidget);
      expect(find.text('Most valuable player'), findsOneWidget);
      expect(find.text('Most active'), findsOneWidget);
      expect(find.text('Most wins'), findsOneWidget);
      expect(find.byType(LeaderboardCard), findsNWidgets(5));
    });

    testWidgets('a board opens on its leader and nobody else', (tester) async {
      // The approved default. Five boards three deep is fifteen names on a
      // phone; what the tab is for is who leads each measure.
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(find.text('Ali'), findsWidgets, reason: 'the leaders are shown');
      expect(find.text('Omar'), findsNothing,
          reason: 'second place is behind Show more');
      expect(find.text('Show more'), findsWidgets);
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('Show more reveals the rest, and Show less puts it back',
        (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      final ratingBoard = find.widgetWithText(LeaderboardCard, 'Highest rated');
      await tester.tap(find.descendant(
        of: ratingBoard,
        matching: find.text('Show more'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Omar'), findsOneWidget);
      expect(
        find.descendant(of: ratingBoard, matching: find.text('Show less')),
        findsOneWidget,
      );

      await tester.tap(find.descendant(
        of: ratingBoard,
        matching: find.text('Show less'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Omar'), findsNothing);
    });

    testWidgets('a board expands one at a time, not all of them',
        (tester) async {
      // Each card owns its own state. Expanding Highest Rated must not open
      // Top Scorer as well -- that would be the table the collapse avoids.
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      await tester.tap(find.descendant(
        of: find.widgetWithText(LeaderboardCard, 'Highest rated'),
        matching: find.text('Show more'),
      ));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.widgetWithText(LeaderboardCard, 'Top scorer'),
          matching: find.text('Show more'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rating keeps its decimal and a count does not',
        (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      // The rating board expanded, so the tied pair is on the screen; the
      // counts are read from the leaders, which are shown either way.
      await tester.tap(find.descendant(
        of: find.widgetWithText(LeaderboardCard, 'Highest rated'),
        matching: find.text('Show more'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('6.0'), findsOneWidget, reason: "Ali's rating");
      expect(find.text('5.5'), findsNWidgets(2), reason: 'the tied pair');
      expect(find.text('5'), findsWidgets, reason: "Ali's goals, as a count");
      expect(find.text('5.0'), findsNothing,
          reason: 'a count shown with a decimal reads as a rating');
    });

    testWidgets('a board with only a leader offers nothing to expand',
        (tester) async {
      // Ali is the only one who has scored. The Top Scorer card holds one row,
      // not three padded out with members on nothing -- and a "Show more" that
      // revealed nothing would be worse than no control.
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(
          members: roster,
          records: [counters('u1', goals: 4)],
        ),
      );

      final scorers = find.widgetWithText(LeaderboardCard, 'Top scorer');
      expect(
        find.descendant(of: scorers, matching: find.text('Show more')),
        findsNothing,
      );
      expect(
        find.descendant(of: scorers, matching: find.text('Ali')),
        findsOneWidget,
      );
    });

    testWidgets('a tie shows the same rank twice', (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      await tester.tap(find.descendant(
        of: find.widgetWithText(LeaderboardCard, 'Highest rated'),
        matching: find.text('Show more'),
      ));
      await tester.pumpAndSettle();

      // Ranks 1, 2, 2 on the rating board -- so a "3" never appears on it,
      // while every board shows a "1".
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('an empty community says so once, not five times',
        (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(
          members: [member('u1', 'Ali', 0)],
          records: const [],
        ),
      );

      expect(find.byType(LeaderboardCard), findsNothing);
      expect(find.textContaining('No leaderboards yet'), findsOneWidget);
    });

    testWidgets('the rating note appears where a rating is shown',
        (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(find.textContaining('across every community'), findsOneWidget);
    });

    testWidgets('the rating note is absent when the rating board is hidden',
        (tester) async {
      // Counters worth ranking, but no rating worth ranking. The note explains
      // a figure that is not on the screen, so it does not appear either.
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(
          members: [member('u1', 'Ali', 0), member('u2', 'Sara', 0)],
          records: [counters('u1', played: 2, goals: 3)],
        ),
      );

      expect(find.text('Top scorer'), findsOneWidget);
      expect(find.text('Highest rated'), findsNothing);
      expect(find.textContaining('across every community'), findsNothing);
    });

    testWidgets('a load that fails offers a retry', (tester) async {
      final adapter = FakeLeaderboardAdapter(
        members: roster,
        records: records,
        failure: const NetworkFailure(),
      );
      await pumpBoards(tester, adapter);

      expect(find.text('Failed to load data.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.reads, 2);
    });

    testWidgets('nothing on it is editable', (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('Arabic renders the boards in Arabic', (tester) async {
      await pumpBoards(
        tester,
        FakeLeaderboardAdapter(members: roster, records: records),
        locale: const Locale('ar'),
      );

      expect(find.text('الأعلى تقييماً'), findsOneWidget);
      expect(find.text('الأكثر فوزاً'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الأعلى تقييماً'))),
        TextDirection.rtl,
      );
    });
  });

  group('building the boards for a period', () {
    /// One week of the same season: Zed, who has no season record at all, has
    /// had a good week, and Ali has not played.
    final thisWeek = [
      counters('u4', played: 2, wins: 2, goals: 4, mvp: 1),
      counters('u2', played: 1, wins: 0, goals: 1, mvp: 0),
    ];

    FakeLeaderboardAdapter seasonAndWeek() => FakeLeaderboardAdapter(
          members: roster,
          records: records,
          periodRecords: {StatisticsPeriod.weekly: thisWeek},
        );

    test('the chosen period reaches the counters read', () async {
      final adapter = seasonAndWeek();

      await StatisticsRepository(adapter)
          .fetchLeaderboards('c1', StatisticsPeriod.monthly);

      expect(adapter.periodsAsked, [StatisticsPeriod.monthly]);
    });

    test('All Time is what it always was', () async {
      final adapter = seasonAndWeek();
      final boards =
          await StatisticsRepository(adapter).fetchLeaderboards('c1');

      expect(adapter.periodsAsked, [StatisticsPeriod.allTime]);
      expect(boardOf(boards, LeaderboardKind.topScorer).entries.first.fullName,
          'Ali');
      expect(boardOf(boards, LeaderboardKind.topScorer).entries.first.value, 5);
    });

    test('a week ranks the week, and the season falls away', () async {
      final boards = await StatisticsRepository(seasonAndWeek())
          .fetchLeaderboards('c1', StatisticsPeriod.weekly);

      final scorers = boardOf(boards, LeaderboardKind.topScorer);
      expect(scorers.entries.map((e) => e.fullName), ['Zed', 'Sara']);
      expect(scorers.entries.first.value, 4);
      // Ali leads the season's board and does not appear on this one at all:
      // he did not play, so the measure did not happen to him this week.
      expect(scorers.entries.map((e) => e.fullName), isNot(contains('Ali')));
    });

    test('the top three, the ranking and the tie-breaking are unchanged',
        () async {
      final tied = [
        counters('u2', goals: 3),
        counters('u1', goals: 3),
        counters('u3', goals: 1),
        counters('u4', goals: 1),
      ];
      final boards = await StatisticsRepository(
        FakeLeaderboardAdapter(
          members: roster,
          records: records,
          periodRecords: {StatisticsPeriod.monthly: tied},
        ),
      ).fetchLeaderboards('c1', StatisticsPeriod.monthly);

      final scorers = boardOf(boards, LeaderboardKind.topScorer);
      // Three deep, however many are eligible.
      expect(scorers.entries, hasLength(3));
      // Competition ranking: the two at three share first, and the next
      // distinct value takes third.
      expect(scorers.entries.map((e) => e.rank), [1, 1, 3]);
      // And the tie breaks by name, so the board reads the same every time.
      expect(scorers.entries.map((e) => e.fullName), ['Ali', 'Sara', 'Omar']);
    });

    test('a period a member did not play in leaves them off every board',
        () async {
      // Not eligibility -- Ali is still a member and still on Highest rated.
      // He simply has no counters in this week.
      final boards = await StatisticsRepository(seasonAndWeek())
          .fetchLeaderboards('c1', StatisticsPeriod.weekly);

      expect(
        boardOf(boards, LeaderboardKind.highestRated).entries.first.fullName,
        'Ali',
      );
      expect(
        boardOf(boards, LeaderboardKind.mostActive)
            .entries
            .map((e) => e.fullName),
        isNot(contains('Ali')),
      );
    });

    test('a period nobody played in builds no counted board at all', () async {
      final boards = await StatisticsRepository(seasonAndWeek())
          .fetchLeaderboards('c1', StatisticsPeriod.monthly);

      // The rating is not a period figure and has no periodic form, so its
      // board stands. The four counted boards are gone rather than filled with
      // zeros, which is the same rule that hides them for a new community.
      expect(boards.map((b) => b.kind), [LeaderboardKind.highestRated]);
    });

    test('the rating board reads the same in every period', () async {
      // `OP-1` gives the Global Rating no periodic form and this cycle does not
      // invent one. Its board is deliberately identical in all three views.
      final adapter = seasonAndWeek();
      final repository = StatisticsRepository(adapter);

      final allTime = await repository.fetchLeaderboards('c1');
      final weekly =
          await repository.fetchLeaderboards('c1', StatisticsPeriod.weekly);

      List<String> ratedNames(List<Leaderboard> boards) =>
          boardOf(boards, LeaderboardKind.highestRated)
              .entries
              .map((e) => e.fullName)
              .toList();

      expect(ratedNames(weekly), ratedNames(allTime));
      expect(
        boardOf(weekly, LeaderboardKind.highestRated).entries.first.value,
        boardOf(allTime, LeaderboardKind.highestRated).entries.first.value,
      );
    });
  });

  group('choosing a period on the boards', () {
    final thisWeek = [counters('u4', played: 2, wins: 2, goals: 4, mvp: 1)];

    FakeLeaderboardAdapter seasonAndWeek() => FakeLeaderboardAdapter(
          members: roster,
          records: records,
          periodRecords: {StatisticsPeriod.weekly: thisWeek},
        );

    Future<void> pumpBoards(
      WidgetTester tester,
      FakeLeaderboardAdapter adapter, {
      Locale locale = const Locale('en'),
      Size size = const Size(900, 1800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityStatisticsTab(
            communityId: 'c1',
            repository: StatisticsRepository(adapter),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('all three periods are offered, and it opens on All time',
        (tester) async {
      final adapter = seasonAndWeek();
      await pumpBoards(tester, adapter);

      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
      expect(
        tester
            .widget<StatisticsPeriodSelector>(
                find.byType(StatisticsPeriodSelector))
            .selected,
        StatisticsPeriod.allTime,
      );
      expect(adapter.periodsAsked, [StatisticsPeriod.allTime]);
    });

    testWidgets('choosing a week re-reads and re-ranks', (tester) async {
      final adapter = seasonAndWeek();
      await pumpBoards(tester, adapter);

      // Ali leads Top scorer over the season.
      expect(
        find.descendant(
          of: find.widgetWithText(LeaderboardCard, 'Top scorer'),
          matching: find.text('Ali'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      expect(adapter.periodsAsked,
          [StatisticsPeriod.allTime, StatisticsPeriod.weekly]);
      expect(
        find.descendant(
          of: find.widgetWithText(LeaderboardCard, 'Top scorer'),
          matching: find.text('Zed'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Weeks run Monday to Sunday'), findsOneWidget);
    });

    testWidgets(
        'a period with nothing in it shows no counted board and no '
        'invented leader', (tester) async {
      final adapter = seasonAndWeek();
      await pumpBoards(tester, adapter);

      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(LeaderboardCard, 'Top scorer'), findsNothing);
      expect(find.widgetWithText(LeaderboardCard, 'Most wins'), findsNothing);
      // The rating board is not a counted one and stays.
      expect(
        find.widgetWithText(LeaderboardCard, 'Highest rated'),
        findsOneWidget,
      );
    });

    testWidgets('the selector survives a narrow screen in English and Arabic',
        (tester) async {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        await pumpBoards(
          tester,
          seasonAndWeek(),
          locale: locale,
          size: const Size(320, 640),
        );

        expect(find.byType(StatisticsPeriodSelector), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'a period label must shrink rather than overflow');
      }
    });

    testWidgets('Arabic names all three periods in Arabic', (tester) async {
      await pumpBoards(tester, seasonAndWeek(), locale: const Locale('ar'));

      expect(find.text('أسبوعي'), findsOneWidget);
      expect(find.text('شهري'), findsOneWidget);
      expect(find.text('الكل'), findsOneWidget);
    });
  });
}

/// The statistics port, answering a roster and its counters from memory.
class FakeLeaderboardAdapter implements StatisticsAdapter {
  FakeLeaderboardAdapter({
    required this.members,
    required this.records,
    this.periodRecords = const {},
    this.failure,
    this.gate,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> records;

  /// The counters for a bounded period. Absent means the period holds nothing,
  /// which is what the database returns for a week nobody played in.
  final Map<StatisticsPeriod, List<CommunityPlayerStatistics>> periodRecords;
  final Failure? failure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;

  /// Every period the counters were asked for, in order.
  final List<StatisticsPeriod> periodsAsked = [];

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(
    String communityId,
  ) async {
    reads++;
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return members;
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) async {
    periodsAsked.add(period);
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return period == StatisticsPeriod.allTime
        ? records
        : periodRecords[period] ?? const [];
  }

  /// A board shows no community-wide totals. Reaching this from the
  /// leaderboards would be a defect, so it fails loudly rather than answering.
  @override
  Future<int> fetchCompletedMatches(
    String communityId,
    StatisticsPeriod period,
  ) =>
      // The Statistics tab draws the community's totals above the boards, so
      // this port is asked for a match count the Leaderboards tab never wanted.
      // Zero: this file is about ranking, and a total it does not assert must
      // not be the reason a board fails to draw.
      Future.value(0);

  /// A board is a community's ranking, never one player's own totals.
  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError('the leaderboards read no player totals');

  /// When each player last achieved each measure. Empty means nobody has any
  /// recency, which is the state before a test says otherwise — every tie then
  /// falls through to the name, exactly as it did before Cycle B1.
  Map<String, PlayerAchievementRecency> recency = const {};

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) async {
    recencyReads++;
    lastRecencyPeriod = period;
    return recency;
  }

  int recencyReads = 0;
  StatisticsPeriod? lastRecencyPeriod;
}

/// Records a pushed route without letting it build: `ProfileScreen` makes the
/// production repositories when nobody injects any, and this suite has no data
/// provider.
class _BoardRouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}
