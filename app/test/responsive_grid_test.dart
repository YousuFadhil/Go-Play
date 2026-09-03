import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/design.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/responsive_grid.dart';
import 'package:go_play/core/skeleton.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/communities/member_card.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/matches/compact_match_card.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/profile/profile_screen.dart';

/// The approved grid contract, and the three cards laid out under it.
///
/// The contract is one sentence: **a card states the narrowest it may be drawn,
/// and the grid gives up a column rather than draw it narrower.** Two for a
/// match, two for a community, three for a member — and never a horizontal
/// scroll, never a smaller typeface, and never an overflow.
///
/// Widths here are the width the *cards* are offered, after whatever padding
/// surrounds them, because that is the number the decision is actually made on.
/// The boundaries are stated rather than approximated so that a change to a
/// minimum shows up as a failing arithmetic test before it shows up as a
/// cramped card somebody has to notice.
void main() {
  /// How many cards share the topmost row.
  ///
  /// Position rather than tree structure: what is being asserted is that two
  /// cards ended up beside each other, and a card's top edge is the stable fact
  /// that says so however the rows are built.
  int columnsOf(WidgetTester tester, Finder cards) {
    final count = tester.widgetList(cards).length;
    expect(count, greaterThan(0), reason: 'no cards were rendered');

    var top = double.infinity;
    for (var i = 0; i < count; i++) {
      final dy = tester.getTopLeft(cards.at(i)).dy;
      if (dy < top) top = dy;
    }
    var inFirstRow = 0;
    for (var i = 0; i < count; i++) {
      if ((tester.getTopLeft(cards.at(i)).dy - top).abs() < 0.5) inFirstRow++;
    }
    return inFirstRow;
  }

  /// The grid at an exact content width, with nothing else claiming space.
  Future<void> pumpGrid(
    WidgetTester tester, {
    required double width,
    required int maxColumns,
    required double minCardWidth,
    required List<Widget> children,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: ResponsiveCardGrid(
              maxColumns: maxColumns,
              minCardWidth: minCardWidth,
              children: children,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // --- the arithmetic ------------------------------------------------------

  group('how many columns a width supports', () {
    test('a match grid takes two, and gives the second up below 310', () {
      // Two 150s and the 10 between them. A 360-wide phone offers 332 to its
      // cards and keeps both columns; a 320-wide one offers 292 and does not.
      int columns(double width) => ResponsiveCardGrid.columnsFor(
            availableWidth: width,
            maxColumns: 2,
            minCardWidth: GridCard.matchMinWidth,
          );

      expect(columns(310), 2);
      expect(columns(309.9), 1);
      expect(columns(332), 2, reason: 'a 360-wide phone');
      expect(columns(292), 1, reason: 'a 320-wide phone');
      expect(columns(1200), 2,
          reason: 'a wide window gets wider cards, '
              'not a third column');
    });

    test('a community grid uses the same boundary', () {
      // Deliberately identical: the two sit in one scroll on Discover, and a
      // different fallback point between them would be visible as one section
      // collapsing to a column while the other did not.
      int columns(double width) => ResponsiveCardGrid.columnsFor(
            availableWidth: width,
            maxColumns: 2,
            minCardWidth: GridCard.communityMinWidth,
          );

      expect(columns(310), 2);
      expect(columns(309.9), 1);
    });

    test('a member grid steps three, two, one', () {
      int columns(double width) => ResponsiveCardGrid.columnsFor(
            availableWidth: width,
            maxColumns: 3,
            minCardWidth: GridCard.memberMinWidth,
          );

      // Three 96s and the two 10s between them.
      expect(columns(308), 3);
      expect(columns(307.9), 2, reason: 'three would be too narrow');
      // Two 96s and the one 10.
      expect(columns(202), 2);
      expect(columns(201.9), 1, reason: 'two would be too narrow');
      expect(columns(40), 1,
          reason: 'one card too narrow to read still beats two');
    });
  });

  // --- the layout ----------------------------------------------------------

  group('what the grid actually draws', () {
    List<Widget> boxes(int n) => [
          for (var i = 0; i < n; i++)
            Card(
              key: ValueKey('box$i'),
              margin: EdgeInsets.zero,
              child: const SizedBox(height: 40),
            ),
        ];

    testWidgets('lays cards side by side when the width allows',
        (tester) async {
      await pumpGrid(
        tester,
        width: 340,
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        children: boxes(4),
      );

      expect(columnsOf(tester, find.byType(Card)), 2);
      // Equal widths, and the gap between them accounted for.
      final first = tester.getSize(find.byKey(const ValueKey('box0')));
      final second = tester.getSize(find.byKey(const ValueKey('box1')));
      expect(first.width, closeTo(second.width, 0.01));
      expect(first.width * 2 + 10, closeTo(340, 0.01));
    });

    testWidgets('falls back to one column rather than shrinking a card',
        (tester) async {
      await pumpGrid(
        tester,
        width: 292,
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        children: boxes(4),
      );

      expect(columnsOf(tester, find.byType(Card)), 1);
      // The fallback is fewer columns, not a narrower card: the one card now
      // has the whole width.
      expect(
        tester.getSize(find.byKey(const ValueKey('box0'))).width,
        closeTo(292, 0.01),
      );
    });

    testWidgets('a short last row keeps its cards at column width',
        (tester) async {
      // Three cards in a two-column grid. The odd one must not stretch across
      // the row, which would read as a different kind of card.
      await pumpGrid(
        tester,
        width: 340,
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        children: boxes(3),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('box2'))).width,
        closeTo(tester.getSize(find.byKey(const ValueKey('box0'))).width, 0.01),
      );
    });

    testWidgets('cards on a row are the same height', (tester) async {
      await pumpGrid(
        tester,
        width: 340,
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        children: [
          const Card(
            key: ValueKey('short'),
            margin: EdgeInsets.zero,
            child: SizedBox(height: 30),
          ),
          const Card(
            key: ValueKey('tall'),
            margin: EdgeInsets.zero,
            child: SizedBox(height: 90),
          ),
        ],
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('short'))).height,
        tester.getSize(find.byKey(const ValueKey('tall'))).height,
      );
    });

    testWidgets('an empty grid draws nothing at all', (tester) async {
      await pumpGrid(
        tester,
        width: 340,
        maxColumns: 2,
        minCardWidth: GridCard.matchMinWidth,
        children: const [],
      );

      expect(find.byType(Card), findsNothing);
    });
  });

  // --- the match card ------------------------------------------------------

  group('the compact match card', () {
    Match match(
      String id, {
      String? title = 'Friday night five-a-side',
      String location = 'Al Amerat Pitch 2',
      String? communityName,
      MatchStatus status = MatchStatus.open,
    }) =>
        Match(
          id: id,
          communityId: 'c1',
          createdBy: 'u1',
          location: location,
          startAt: DateTime(2027, 3, 6, 19),
          endAt: DateTime(2027, 3, 6, 20, 30),
          startingPlayers: 10,
          maxRegistration: 14,
          status: status,
          title: title,
          communityName: communityName,
        );

    Future<void> pumpMatches(
      WidgetTester tester, {
      required double width,
      required List<Match> matches,
      Locale locale = const Locale('en'),
    }) =>
        pumpGrid(
          tester,
          width: width,
          locale: locale,
          maxColumns: 2,
          minCardWidth: GridCard.matchMinWidth,
          children: [
            for (final m in matches)
              CompactMatchCard(match: m, showCommunityName: true),
          ],
        );

    testWidgets('two across on a phone, one on a narrow one', (tester) async {
      await pumpMatches(
        tester,
        width: 332,
        matches: [match('m1'), match('m2'), match('m3'), match('m4')],
      );
      expect(columnsOf(tester, find.byType(CompactMatchCard)), 2);

      await pumpMatches(
        tester,
        width: 292,
        matches: [match('m1'), match('m2')],
      );
      expect(columnsOf(tester, find.byType(CompactMatchCard)), 1);
    });

    testWidgets('carries the facts the list card carried', (tester) async {
      await pumpMatches(
        tester,
        width: 332,
        matches: [match('m1', communityName: 'Muscat United')],
      );

      expect(find.text('Friday night five-a-side'), findsOneWidget);
      expect(find.text('Muscat United'), findsOneWidget);
      expect(find.text('Al Amerat Pitch 2'), findsOneWidget);
      expect(find.text('Sat 6 Mar'), findsOneWidget);
      expect(find.textContaining('7:00'), findsOneWidget);
    });

    testWidgets('a state worth noticing is still reported', (tester) async {
      // Open says nothing — it is the ordinary case. The other two are the
      // reason a reader looks twice, exactly as on the row card.
      await pumpMatches(tester, width: 332, matches: [match('m1')]);
      expect(find.text('Full'), findsNothing);

      await pumpMatches(
        tester,
        width: 332,
        matches: [match('m1', status: MatchStatus.full)],
      );
      expect(find.text('Full'), findsOneWidget);
    });

    testWidgets('a long title and location stay inside a narrow card',
        (tester) async {
      await pumpMatches(
        tester,
        width: 310,
        matches: [
          match(
            'm1',
            title: 'The Thursday Evening Seven-a-Side Championship Fixture',
            location: 'Al Amerat Sports Complex Auxiliary Training Pitch 2',
            communityName: 'The Muscat United Football and Social Club',
          ),
          match('m2'),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactMatchCard)), 2);
    });

    testWidgets('and in Arabic, right to left', (tester) async {
      await pumpMatches(
        tester,
        width: 310,
        locale: const Locale('ar'),
        matches: [
          match(
            'm1',
            title: 'بطولة مساء الخميس لكرة القدم سباعية اللاعبين',
            location: 'مجمع العامرات الرياضي ملعب التدريب الإضافي رقم اثنان',
            communityName: 'نادي مسقط المتحد لكرة القدم والأنشطة الاجتماعية',
          ),
          match('m2'),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactMatchCard)), 2);

      // The card reads the way the rest of the screen does. Its first card
      // starts at the right-hand edge of the grid.
      final first = tester.getTopLeft(find.byType(CompactMatchCard).at(0));
      final second = tester.getTopLeft(find.byType(CompactMatchCard).at(1));
      expect(first.dx, greaterThan(second.dx),
          reason: 'the first card of a row sits on the right under Arabic');
    });

    testWidgets('is still a way into the match', (tester) async {
      final observer = _RouteRecorder();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: [observer],
        home: Scaffold(
          body: SizedBox(
            width: 332,
            child: ResponsiveCardGrid(
              maxColumns: 2,
              minCardWidth: GridCard.matchMinWidth,
              children: [CompactMatchCard(match: match('m1'))],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      observer.ignoreInitialRoute();

      // Not pumped afterwards on purpose: the assertion is about the route that
      // was pushed, and building it would construct the services the match
      // screen makes when nobody injects any.
      await tester.tap(find.byType(CompactMatchCard));

      expect(observer.pushed, hasLength(1),
          reason: 'a compact card is still a way into the match');
      observer.discard();
    });
  });

  // --- the community card --------------------------------------------------

  group('the compact community card', () {
    PublicCommunity community(String id, String name, {String? description}) =>
        PublicCommunity(
          id: id,
          name: name,
          memberCount: 24,
          upcomingMatchCount: 3,
          description: description,
        );

    Future<void> pumpCommunities(
      WidgetTester tester, {
      required double width,
      required List<PublicCommunity> communities,
      Locale locale = const Locale('en'),
      VoidCallback? onOpen,
      VoidCallback? onJoin,
    }) =>
        pumpGrid(
          tester,
          width: width,
          locale: locale,
          maxColumns: 2,
          minCardWidth: GridCard.communityMinWidth,
          children: [
            for (final c in communities)
              CompactPublicCommunityCard(
                community: c,
                onOpen: onOpen ?? () {},
                onJoin: onJoin ?? () {},
              ),
          ],
        );

    testWidgets('two across, and one when two will not fit', (tester) async {
      await pumpCommunities(
        tester,
        width: 332,
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Al Amerat FC'),
        ],
      );
      expect(columnsOf(tester, find.byType(CompactPublicCommunityCard)), 2);

      await pumpCommunities(
        tester,
        width: 292,
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Al Amerat FC'),
        ],
      );
      expect(columnsOf(tester, find.byType(CompactPublicCommunityCard)), 1);
    });

    testWidgets('a long name is contained, in both languages', (tester) async {
      await pumpCommunities(
        tester,
        width: 310,
        communities: [
          community(
            'c1',
            'The Muscat United Football and Social Club of Al Amerat',
            description: 'A long-standing club playing every Thursday evening '
                'at the Al Amerat complex, open to newcomers.',
          ),
          community('c2', 'Al Amerat FC'),
        ],
      );
      expect(tester.takeException(), isNull);

      await pumpCommunities(
        tester,
        width: 310,
        locale: const Locale('ar'),
        communities: [
          community(
            'c1',
            'نادي مسقط المتحد لكرة القدم والأنشطة الاجتماعية بالعامرات',
            description: 'نادٍ عريق يلعب كل مساء خميس في مجمع العامرات '
                'الرياضي، ويرحب بالأعضاء الجدد.',
          ),
          community('c2', 'نادي العامرات'),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactPublicCommunityCard)), 2);
    });

    testWidgets('keeps both ways in — opening it and joining it',
        (tester) async {
      var opened = 0;
      var joined = 0;
      await pumpCommunities(
        tester,
        width: 332,
        communities: [community('c1', 'Muscat United')],
        onOpen: () => opened++,
        onJoin: () => joined++,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Join'));
      await tester.pump();
      expect(joined, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'View community'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('shows the crest, which is what a community identity is',
        (tester) async {
      // Not a placeholder for a picture. The schema has no logo column, this
      // phase adds none, and nothing on this card is holding space for one.
      await pumpCommunities(
        tester,
        width: 332,
        communities: [community('c1', 'Muscat United')],
      );

      expect(find.text('MU'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  // --- the member card -----------------------------------------------------

  group('the member grid', () {
    Widget memberCard(
      String id,
      String name, {
      String position = 'Midfielder',
      String? role,
    }) =>
        CommunityMemberCard(
          userId: id,
          fullName: name,
          positionLabel: position,
          roleLabel: role,
        );

    Future<void> pumpMembers(
      WidgetTester tester, {
      required double width,
      required List<Widget> members,
      Locale locale = const Locale('en'),
      NavigatorObserver? observer,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observer == null ? const [] : [observer],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: ResponsiveCardGrid(
                maxColumns: 3,
                minCardWidth: GridCard.memberMinWidth,
                children: members,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    List<Widget> squad(int n) => [
          for (var i = 0; i < n; i++) memberCard('u$i', 'Player Number $i'),
        ];

    testWidgets('three across where three fit', (tester) async {
      await pumpMembers(tester, width: 332, members: squad(6));
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 3);
    });

    testWidgets('two when three would be too constrained', (tester) async {
      await pumpMembers(tester, width: 280, members: squad(6));
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 2);
    });

    testWidgets('one only when two would be unsuitable too', (tester) async {
      await pumpMembers(tester, width: 190, members: squad(4));
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 1);
    });

    testWidgets(
        'a long Arabic name wraps inside the card rather than out of it',
        (tester) async {
      await pumpMembers(
        tester,
        width: 332,
        locale: const Locale('ar'),
        members: [
          memberCard('u1', 'عبدالرحمن بن سليمان الحارثي', position: 'وسط'),
          memberCard('u2', 'أحمد البلوشي', position: 'دفاع'),
          memberCard('u3', 'يوسف العامري', position: 'هجوم'),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CommunityMemberCard)), 3);

      // Two lines, and the second is where it stops. The card must not have
      // grown to fit the name, nor the name escaped the card.
      final card = tester.getSize(find.byType(CommunityMemberCard).first);
      final name = tester.getSize(
        find.text('عبدالرحمن بن سليمان الحارثي'),
      );
      expect(name.width, lessThanOrEqualTo(card.width));
    });

    testWidgets('a role is shown where there is one, and nowhere else',
        (tester) async {
      await pumpMembers(
        tester,
        width: 332,
        members: [
          memberCard('u1', 'Yousuf Al Amri', role: 'Owner'),
          memberCard('u2', 'Ahmed Al Balushi'),
          memberCard('u3', 'Salim Al Harthy', role: 'Admin'),
        ],
      );

      expect(find.text('OWNER'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('a badge does not make one card taller than its row',
        (tester) async {
      await pumpMembers(
        tester,
        width: 332,
        members: [
          memberCard('u1', 'Yousuf Al Amri', role: 'Owner'),
          memberCard('u2', 'Ahmed Al Balushi'),
          memberCard('u3', 'Salim Al Harthy'),
        ],
      );

      final heights = [
        for (var i = 0; i < 3; i++)
          tester.getSize(find.byType(CommunityMemberCard).at(i)).height,
      ];
      expect(heights[1], heights[0]);
      expect(heights[2], heights[0]);
    });

    testWidgets('carries the four things it is allowed to carry',
        (tester) async {
      await pumpMembers(
        tester,
        width: 332,
        members: [memberCard('u1', 'Yousuf Al Amri', role: 'Owner')],
      );

      expect(find.text('Yousuf Al Amri'), findsOneWidget);
      expect(find.text('Midfielder'), findsOneWidget);
      expect(find.text('OWNER'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);

      // And nothing that acts on the member: management stays where it was.
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
    });

    testWidgets('the whole card opens the player', (tester) async {
      final observer = _RouteRecorder();
      await pumpMembers(
        tester,
        width: 332,
        members: [memberCard('u1', 'Yousuf Al Amri')],
        observer: observer,
      );
      observer.ignoreInitialRoute();

      await tester.tap(find.byType(CommunityMemberCard));

      final screen =
          observer.pushed.single.builder(tester.element(find.byType(Scaffold)));
      expect(screen, isA<ProfileScreen>());
      expect((screen as ProfileScreen).userId, 'u1',
          reason: 'the same one Player Profile the list tile opened');
      observer.discard();
    });
  });

  // --- the loading state ---------------------------------------------------

  group('the placeholders take the shape of what is coming', () {
    /// A skeleton grid at an exact *screen* width.
    ///
    /// The grid carries its own gutters, exactly as it does on the screens, so
    /// what is set here is the width the page gets rather than the width the
    /// cards get. That is the point of these tests: the two states have to make
    /// the same decision from the same starting number.
    Future<void> pumpSkeleton(
      WidgetTester tester, {
      required double screenWidth,
      required Widget skeleton,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: screenWidth, child: skeleton),
          ),
        ),
      ));
      await tester.pump();
    }

    /// The loaded grid at the same exact screen width, with its own gutters —
    /// the arrangement the real screens build.
    Future<void> pumpLoaded(
      WidgetTester tester, {
      required double screenWidth,
      required List<Widget> children,
      required double minCardWidth,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: screenWidth,
              child: ResponsiveCardGrid(
                maxColumns: 2,
                minCardWidth: minCardWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: Layout.sheetGutter,
                  vertical: Gap.xs,
                ),
                children: children,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Match match(String id) => Match(
          id: id,
          communityId: 'c1',
          createdBy: 'u1',
          location: 'Al Amerat Pitch 2',
          startAt: DateTime(2027, 3, 6, 19),
          endAt: DateTime(2027, 3, 6, 20, 30),
          startingPlayers: 10,
          maxRegistration: 14,
          status: MatchStatus.open,
          title: 'Friday night five-a-side',
        );

    testWidgets('a match skeleton sits two across on a phone', (tester) async {
      // 360 wide leaves 332 after the sheet's gutters, which is over the 310
      // two columns of match card need.
      await pumpSkeleton(
        tester,
        screenWidth: 360,
        skeleton: const CompactMatchGridSkeleton(),
      );

      expect(columnsOf(tester, find.byType(CompactMatchCardSkeleton)), 2);
    });

    testWidgets('and gives the column up on a narrow one', (tester) async {
      await pumpSkeleton(
        tester,
        screenWidth: 320,
        skeleton: const CompactMatchGridSkeleton(),
      );

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactMatchCardSkeleton)), 1);
    });

    testWidgets('the community skeleton follows the same contract',
        (tester) async {
      await pumpSkeleton(
        tester,
        screenWidth: 360,
        skeleton: const CompactCommunityGridSkeleton(),
      );
      expect(columnsOf(tester, find.byType(CompactCommunityCardSkeleton)), 2);

      await pumpSkeleton(
        tester,
        screenWidth: 320,
        skeleton: const CompactCommunityGridSkeleton(),
      );
      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactCommunityCardSkeleton)), 1);
    });

    testWidgets('loading and loaded agree on the columns, at both widths',
        (tester) async {
      // The defect this pass corrects: the page was drawn one shape while the
      // read was in flight and another the moment it landed. Same screen width
      // in, same number of columns out — asserted rather than assumed, because
      // the two states are built by different widgets.
      for (final width in [360.0, 320.0]) {
        await pumpSkeleton(
          tester,
          screenWidth: width,
          skeleton: const CompactMatchGridSkeleton(),
        );
        final loading =
            columnsOf(tester, find.byType(CompactMatchCardSkeleton));

        await pumpLoaded(
          tester,
          screenWidth: width,
          minCardWidth: GridCard.matchMinWidth,
          children: [
            for (var i = 0; i < 4; i++) CompactMatchCard(match: match('m$i')),
          ],
        );
        final loaded = columnsOf(tester, find.byType(CompactMatchCard));

        expect(loading, loaded,
            reason: 'the placeholder and the card must not disagree about the '
                'layout at ${width}px');
      }
    });

    testWidgets('and on how wide a card is', (tester) async {
      // Not only the count. A placeholder that is the right number of columns
      // but the wrong width still moves the page when it is replaced.
      await pumpSkeleton(
        tester,
        screenWidth: 360,
        skeleton: const CompactMatchGridSkeleton(),
      );
      final placeholder =
          tester.getSize(find.byType(CompactMatchCardSkeleton).first).width;

      await pumpLoaded(
        tester,
        screenWidth: 360,
        minCardWidth: GridCard.matchMinWidth,
        children: [
          for (var i = 0; i < 4; i++) CompactMatchCard(match: match('m$i')),
        ],
      );
      final card = tester.getSize(find.byType(CompactMatchCard).first).width;

      expect(placeholder, closeTo(card, 0.01));
    });

    testWidgets('neither skeleton overflows, in either direction',
        (tester) async {
      for (final width in [320.0, 360.0, 800.0]) {
        await pumpSkeleton(
          tester,
          screenWidth: width,
          skeleton: const CompactMatchGridSkeleton(),
        );
        expect(tester.takeException(), isNull, reason: 'matches at ${width}px');

        await pumpSkeleton(
          tester,
          screenWidth: width,
          skeleton: const CompactCommunityGridSkeleton(),
        );
        expect(tester.takeException(), isNull,
            reason: 'communities at ${width}px');
      }
    });
  });
}

/// Records what was pushed without letting it build.
///
/// The same recorder `test/player_identity_test.dart` uses, and for the same
/// reason: the screens behind these taps build the production repositories when
/// nobody injects any, and what is being asserted is where a tap goes rather
/// than what it finds when it arrives.
class _RouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  /// Forgets the route `MaterialApp` pushes for its own home.
  void ignoreInitialRoute() => pushed.clear();

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}
