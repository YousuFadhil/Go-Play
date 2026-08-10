import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/statistics/community_leaderboards_tab.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';

/// The Community Leaderboards against a fake port.
///
/// The ranking rules carry every product decision in this feature — who may
/// appear, how ties place, how deep a board goes, and when a board is not
/// worth showing — so they are tested apart from the screen that draws them.
void main() {
  CommunityMemberRating member(String id, String name, double rating) =>
      CommunityMemberRating(userId: id, fullName: name, rating: rating);

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
    member('u1', 'Ali', 6.0),
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

      expect(boardOf(boards, LeaderboardKind.highestRated).entries
          .map((e) => e.rank), [1, 1, 1]);
    });

    test('only the top three appear', () async {
      final crowd = [
        for (var i = 0; i < 8; i++)
          member('u$i', 'P$i', 9.0 - i),
      ];
      final boards = await boardsFrom(
        FakeLeaderboardAdapter(members: crowd, records: const []),
      );

      expect(boardOf(boards, LeaderboardKind.highestRated).entries, hasLength(3));
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
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CommunityLeaderboardsTab(
            communityId: 'c1',
            repository: StatisticsRepository(adapter),
          ),
        ),
      ));
      if (settle) await tester.pumpAndSettle();
    }

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
}

/// The statistics port, answering a roster and its counters from memory.
class FakeLeaderboardAdapter implements StatisticsAdapter {
  FakeLeaderboardAdapter({
    required this.members,
    required this.records,
    this.failure,
    this.gate,
  });

  final List<CommunityMemberRating> members;
  final List<CommunityPlayerStatistics> records;
  final Failure? failure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;

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
  ) async {
    if (gate != null) await gate;
    if (failure != null) throw failure!;
    return records;
  }

  /// A board shows no community-wide totals. Reaching this from the
  /// leaderboards would be a defect, so it fails loudly rather than answering.
  @override
  Future<int> fetchCompletedMatches(String communityId) =>
      throw UnimplementedError('the leaderboards read no match totals');
}
