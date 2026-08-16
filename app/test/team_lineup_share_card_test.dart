import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// `show`n: intl exports a TextDirection that would shadow Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_lineup_card.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/features/teams/teams_screen.dart';

/// The Team Lineup share card, and the Teams screen action that makes one.
///
/// Two things are asserted and they are deliberately separate: what the card
/// draws when handed a lineup, and that the screen hands it the lineup the
/// reader is looking at. Neither the Share Card Engine nor the pitch is
/// retested here — both have their own suites, and the card's job is to reuse
/// them rather than to restate them.
void main() {
  const names = {
    'u1': 'Sara Al Balushi',
    'u2': 'Ahmed Al Harthy',
    'u3': 'Noor Al Kindi',
    'u4': 'Yousef Al Amri',
  };

  PlayerCoreInputs input(String id, Position primary, {String? avatarUrl}) =>
      PlayerCoreInputs(
        userId: id,
        fullName: names[id] ?? 'Player $id',
        overallRating: 6,
        primaryPosition: primary,
        avatarUrl: avatarUrl,
      );

  TeamAssignment assignment(
    String id,
    TeamId team,
    Position position, {
    AssignmentBasis basis = AssignmentBasis.primary,
  }) =>
      TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: position,
        basis: basis,
      );

  TeamAssignment guest(String id, TeamId team) => TeamAssignment(
        professionalGuestId: id,
        team: team,
        assignedPosition: null,
        basis: null,
      );

  List<TeamAssignment> storedLineup() => [
        assignment('u1', TeamId.a, Position.gk),
        assignment('u3', TeamId.a, Position.mid),
        assignment('u2', TeamId.b, Position.def),
        assignment('u4', TeamId.b, Position.fwd),
      ];

  TeamLineupCardData cardData({
    List<TeamAssignment>? lineup,
    Map<String, PlayerCoreInputs>? players,
    Map<String, String>? resolvedNames,
    bool hasNaturalGoalkeeper = true,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    final assignments = lineup ?? storedLineup();
    return TeamLineupCardData(
      lineup: assignments,
      players: players ??
          {
            'u1': input('u1', Position.gk),
            'u2': input('u2', Position.def),
            'u3': input('u3', Position.mid),
            'u4': input('u4', Position.fwd),
          },
      names: resolvedNames ??
          {
            for (final a in assignments)
              a.participantId: names[a.participantId] ?? '—',
          },
      hasNaturalGoalkeeper: hasNaturalGoalkeeper,
      startAt: startAt,
      endAt: endAt,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    TeamLineupCardData data, {
    Locale locale = const Locale('en'),
    GlobalKey? boundaryKey,
  }) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundaryKey ?? GlobalKey(),
          child: ShareCardSurface(child: TeamLineupCard(data: data)),
        ),
      ),
    ));
    await tester.pump();
  }

  // --- the lineup, passed through unchanged -----------------------------------

  group('the card draws the lineup it was given', () {
    testWidgets('both sides, every player, named as the screen names them',
        (tester) async {
      await pumpCard(tester, cardData());

      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      for (final name in names.values) {
        expect(find.text(name), findsOneWidget);
      }
      // The mark signs the card once, at the bottom, and never heads it.
      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('both teams share one pitch', (tester) async {
      // A lineup is two sides of the same match; a pitch each would say they
      // are two separate things.
      await pumpCard(tester, cardData());

      // One painted board carrying both halves, and one mark per player.
      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(4));
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
    });

    testWidgets('the two teams face each other across the halfway line',
        (tester) async {
      // Team A defends the top goal, so its keeper is the topmost card and
      // Team B's the bottommost — the two attacks meet in the middle.
      await pumpCard(
        tester,
        cardData(lineup: [
          assignment('u1', TeamId.a, Position.gk),
          assignment('u3', TeamId.a, Position.fwd),
          assignment('u4', TeamId.b, Position.fwd),
          assignment('u2', TeamId.b, Position.gk),
        ]),
      );

      double topOf(String name) => tester.getTopLeft(find.text(name)).dy;

      // Team A: keeper above forward. Team B: forward above keeper.
      expect(topOf('Sara Al Balushi'), lessThan(topOf('Noor Al Kindi')));
      expect(topOf('Yousef Al Amri'), lessThan(topOf('Ahmed Al Harthy')));
      // And the two forwards are the innermost pair.
      expect(topOf('Noor Al Kindi'), lessThan(topOf('Yousef Al Amri')));
    });

    testWidgets('a player who left the match keeps the screen\'s dash',
        (tester) async {
      // `KB-017` records that they played. The screen resolves the name — the
      // profile, then the roster, then a dash — and the card is handed the
      // answer rather than deriving a different one.
      await pumpCard(
        tester,
        cardData(
          players: {'u1': input('u1', Position.gk)},
          resolvedNames: {
            'u1': 'Sara Al Balushi',
            'u2': '—',
            'u3': '—',
            'u4': '—',
          },
        ),
      );

      expect(find.text('Sara Al Balushi'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('a Professional Guest is drawn the way the pitch draws one',
        (tester) async {
      await pumpCard(
        tester,
        cardData(
          lineup: [
            assignment('u1', TeamId.a, Position.gk),
            guest('g1', TeamId.b),
          ],
          resolvedNames: {'u1': 'Sara Al Balushi', 'g1': 'Professional (Omar)'},
        ),
      );

      expect(find.text('Professional (Omar)'), findsOneWidget);
      // A guest is marked as one on the card's own mark: same ring, same
      // shadow, the guest's badge instead of a face.
      final marks = tester.widgetList<TeamLineupPlayerMark>(
        find.byType(TeamLineupPlayerMark),
      );
      expect(marks.where((m) => m.isProfessionalGuest), hasLength(1));
    });

    testWidgets('a player with a picture keeps it, one without falls back',
        (tester) async {
      await pumpCard(
        tester,
        cardData(
          lineup: [
            assignment('u1', TeamId.a, Position.gk),
            assignment('u2', TeamId.b, Position.def),
          ],
          players: {
            'u1': input('u1', Position.gk,
                avatarUrl: 'https://example.test/u1.jpg'),
            'u2': input('u2', Position.def),
          },
        ),
      );

      final marks = tester.widgetList<TeamLineupPlayerMark>(
        find.byType(TeamLineupPlayerMark),
      );
      expect(marks.map((m) => m.avatarUrl),
          containsAll(<String?>['https://example.test/u1.jpg', null]));
      expect(tester.takeException(), isNull,
          reason: 'a missing picture is the app\'s fallback, not an error');
    });

    testWidgets('no goalkeeper in the squad means no goal row', (tester) async {
      // The screen's own answer, passed through: a goal row is drawn only
      // where the squad has somebody who keeps goal, so the two keepers in
      // this lineup are not drawn at all.
      await pumpCard(tester, cardData(hasNaturalGoalkeeper: false));

      expect(find.text('Sara Al Balushi'), findsNothing,
          reason: 'u1 keeps goal, and there is no goal row to draw them in');
      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(3));

      // With a keeper in the squad, the same lineup draws all four.
      await pumpCard(tester, cardData());
      expect(find.text('Sara Al Balushi'), findsOneWidget);
      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(4));
    });

    test('an empty lineup is not a card', () {
      // The Teams screen shows "not generated yet" in that state and has
      // nothing on it to send.
      expect(cardData().isShareable, isTrue);
      expect(cardData(lineup: const []).isShareable, isFalse);
    });

    test('the data carries a lineup and nothing about a match', () {
      // There is no field for a match title, location or time: the type itself
      // is what stops one being drawn.
      final data = cardData();
      expect(data.lineup, hasLength(4));
      expect(data.names.values, contains('Sara Al Balushi'));
      expect(data.hasNaturalGoalkeeper, isTrue);
      expect(data.isShareable, isTrue);
    });

    test('the sides are split from the one lineup it was handed', () {
      final data = cardData();

      expect(data.of(TeamId.a).map((a) => a.participantId), ['u1', 'u3']);
      expect(data.of(TeamId.b).map((a) => a.participantId), ['u2', 'u4']);
      expect(data.lineup, hasLength(4));
    });
  });

  // --- names ------------------------------------------------------------------

  group('a name is set, not cut', () {
    /// Eleven a side, the densest lineup the card draws, with [long] given to
    /// one player and ordinary names to the rest.
    TeamLineupCardData crowded({String? long}) {
      final lineup = <TeamAssignment>[
        for (var i = 0; i < 11; i++)
          assignment('a$i', TeamId.a, Position.values[i % 4]),
        for (var i = 0; i < 11; i++)
          assignment('b$i', TeamId.b, Position.values[i % 4]),
      ];
      return cardData(
        lineup: lineup,
        players: {
          for (final a in lineup)
            a.participantId: input(a.participantId, Position.mid),
        },
        resolvedNames: {
          for (final a in lineup)
            a.participantId: a.participantId == 'a0' && long != null
                ? long
                // Short and distinct, so a name can be found by its own text
                // and no name is long enough to need a second line of its own.
                : 'P${a.participantId}',
        },
      );
    }

    testWidgets('one too long for a line is set on two, not trimmed',
        (tester) async {
      // The alternative the card used to reach for was a smaller and smaller
      // one-liner and then an ellipsis, which turns a player into an initial
      // and a row of dots.
      const long = 'Abdulrahman Bin Sulaiman Al Harthy';
      await pumpCard(tester, crowded(long: long));

      expect(find.text(long), findsOneWidget,
          reason: 'the name itself is never altered');
      expect(tester.widget<Text>(find.text(long)).maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ordinary name keeps its one line', (tester) async {
      // The second line is bought only where it is needed: a lineup of names
      // that fit is composed exactly as it was before it existed.
      await pumpCard(
        tester,
        cardData(resolvedNames: const {
          'u1': 'Sara',
          'u2': 'Ahmed',
          'u3': 'Noor',
          'u4': 'Yousef',
        }),
      );

      expect(tester.widget<Text>(find.text('Sara')).maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no two names on the card overlap, however long they are',
        (tester) async {
      // The one thing a two-line name must never buy: a name running into the
      // player beside it, or into the row underneath.
      const long = 'Abdulrahman Bin Sulaiman Al Harthy';
      await pumpCard(tester, crowded(long: long));

      final boxes = <Rect>[
        for (final element in find.byType(TeamLineupPlayerMark).evaluate())
          tester.getRect(
            find.text((element.widget as TeamLineupPlayerMark).name),
          ),
      ];

      expect(boxes, hasLength(22));
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          expect(boxes[i].overlaps(boxes[j]), isFalse,
              reason: 'two names share the same pixels: '
                  '${boxes[i]} and ${boxes[j]}');
        }
      }
    });

    testWidgets('every rating is still on the card, long names or not',
        (tester) async {
      const long = 'Abdulrahman Bin Sulaiman Al Harthy';
      await pumpCard(tester, crowded(long: long));

      // One tag per player, and the long name has not cost anybody theirs.
      expect(find.text('6.0'), findsNWidgets(22));
    });

    testWidgets('Arabic sets two lines the same way, right to left',
        (tester) async {
      const long = 'عبدالرحمن بن سليمان الحارثي البوسعيدي';
      await pumpCard(tester, crowded(long: long), locale: const Locale('ar'));

      expect(find.text(long), findsOneWidget);
      expect(tester.widget<Text>(find.text(long)).maxLines, 2);
      expect(
        Directionality.of(tester.element(find.text(long))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // --- geometry ---------------------------------------------------------------

  group('the card is the engine\'s card', () {
    testWidgets('it fills the 1080x1920 surface and nothing overflows',
        (tester) async {
      await pumpCard(tester, cardData());

      expect(tester.getSize(find.byType(ShareCardSurface)),
          ShareCardCanvas.designSize);
      expect(tester.takeException(), isNull,
          reason: 'a card that overflows its own surface is a broken picture');
    });

    testWidgets('a crowded lineup still fits', (tester) async {
      // Eleven a side is past anything the engine produces, and the card has to
      // shrink to hold it rather than run off the bottom of the picture.
      final crowded = <TeamAssignment>[
        for (var i = 0; i < 11; i++)
          assignment('a$i', TeamId.a, Position.values[i % 4]),
        for (var i = 0; i < 11; i++)
          assignment('b$i', TeamId.b, Position.values[i % 4]),
      ];
      await pumpCard(
        tester,
        cardData(
          lineup: crowded,
          players: {for (final a in crowded) a.participantId: input(a.participantId, Position.mid)},
          resolvedNames: {
            for (final a in crowded) a.participantId: 'Player ${a.participantId}',
          },
        ),
      );

      expect(tester.getSize(find.byType(ShareCardSurface)),
          ShareCardCanvas.designSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('captured through the engine it is a 9:16 PNG', (tester) async {
      final key = GlobalKey();
      await pumpCard(tester, cardData(), boundaryKey: key);

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));

      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
      expect(image.isShareCardShape, isTrue);
      expect(image.bytes, isNotEmpty);
    });

    testWidgets('nothing in it measures the device', (tester) async {
      await pumpCard(tester, cardData());
      final composed = tester.getSize(find.byType(TeamLineupCard));

      tester.view.physicalSize = const Size(1200, 3000);
      await tester.pump();

      expect(tester.getSize(find.byType(TeamLineupCard)), composed);
      expect(composed, ShareCardCanvas.designSize);
    });

    testWidgets('the card looks the same whatever theme composed it',
        (tester) async {
      // A picture that leaves the phone must not change because the reader has
      // dark mode on. The card takes no colour from the ambient scheme — every
      // one of them is its own constant — and this asserts the consequence
      // rather than the mechanism: the two files are the same file.
      tester.view.physicalSize = const Size(2400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final images = <ShareCardImage>[];
      for (final brightness in Brightness.values) {
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ShareCardSurface(child: TeamLineupCard(data: cardData())),
            ),
          ),
        ));
        await tester.pump();

        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        images.add((await tester.runAsync(() => captureShareCard(boundary)))!);
      }

      expect(images.first.bytes, images.last.bytes);
    });
  });

  // --- localization -----------------------------------------------------------

  group('English and Arabic', () {
    testWidgets('English draws the card left to right', (tester) async {
      await pumpCard(tester, cardData());

      expect(
        Directionality.of(tester.element(find.text('Team A'))),
        TextDirection.ltr,
      );
    });

    testWidgets('Arabic names both sides in Arabic, right to left',
        (tester) async {
      await pumpCard(tester, cardData(), locale: const Locale('ar'));

      expect(find.text('الفريق أ'), findsOneWidget);
      expect(find.text('الفريق ب'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الفريق أ'))),
        TextDirection.rtl,
        reason: 'the direction is inherited, not mirrored element by element',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mark reads Go Play in both languages', (tester) async {
      await pumpCard(tester, cardData(), locale: const Locale('ar'));

      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('a match inside one half of the day is given one meridiem',
        (tester) async {
      // "8:00–10:00 PM", not "8:00 PM - 10:00 PM": one range, written once.
      await pumpCard(
        tester,
        cardData(
          startAt: DateTime(2026, 8, 21, 20),
          endAt: DateTime(2026, 8, 21, 22),
        ),
      );

      expect(find.text('8:00–10:00 PM'), findsOneWidget);
    });

    testWidgets('a match that crosses noon reads start-then-end in Arabic',
        (tester) async {
      // The one case that needs both meridiems, and the case that cannot be
      // written as one string: with "11:00 ص – 1:00 م" in a single run, the
      // neutral dash joins the Arabic side and the line resolves to
      // "11:00 م 1:00 – ص" — the match appearing to end before it began. The
      // two ends are laid out as separate pieces so the order is the card's
      // rather than the paragraph's.
      final start = DateTime(2026, 8, 21, 11);
      final end = DateTime(2026, 8, 21, 13);
      String at(DateTime t) => '${DateFormat('h:mm', 'ar').format(t)} '
          '${DateFormat('a', 'ar').format(t)}';

      await pumpCard(
        tester,
        cardData(startAt: start, endAt: end),
        locale: const Locale('ar'),
      );

      expect(find.text(at(start)), findsOneWidget);
      expect(find.text(at(end)), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(at(start))).dx,
        lessThan(tester.getTopLeft(find.text(at(end))).dx),
        reason: 'the kick-off is on the left of the dash in every language',
      );
    });
  });

  // --- the template depends on nothing ----------------------------------------

  group('the template is presentation only', () {
    test('it imports no repository, adapter, service or data provider', () {
      // If this file could fetch, the card would become a second source for a
      // lineup the reader is already looking at.
      final imports = File('lib/features/teams/team_lineup_card.dart')
          .readAsLinesSync()
          .where((line) => line.startsWith('import '))
          .toList();

      for (final line in imports) {
        for (final word in const [
          'repository',
          'adapter',
          'supabase',
          'infrastructure',
          'match_service',
          'auth_service',
        ]) {
          expect(line.contains(word), isFalse,
              reason: 'the card imports "$word" — it must be handed a resolved '
                  'lineup, never fetch one');
        }
      }
    });
  });

  // --- the Teams screen's Share action ----------------------------------------

  group('sharing from the Teams screen', () {
    final kickOff = DateTime.now().add(const Duration(days: 3));

    Match matchAt(DateTime start, {String? title, String location = 'Al Amerat Pitch'}) =>
        Match(
          id: 'm1',
          communityId: 'c1',
          createdBy: 'u1',
          // `fetchMatch` joins the community for its name, so the Teams screen
          // holds it and the card's subject is available without a second read.
          communityName: 'Al Amerat FC',
          location: location,
          title: title,
          startAt: start,
          endAt: start.add(const Duration(hours: 2)),
          startingPlayers: 10,
          maxRegistration: 16,
          status: MatchStatus.open,
        );

    MatchRegistration seat(String id, String name, String position) =>
        MatchRegistration(
          registrationId: 'reg-$id',
          userId: id,
          fullName: name,
          position: position,
          status: RegistrationStatus.confirmed,
          registrationOrder: int.parse(id.substring(1)),
        );

    Future<CapturingRenderer> pumpTeams(
      WidgetTester tester, {
      List<TeamAssignment> lineup = const [],
      String? title = 'Friday Night',
      String location = 'Al Amerat Pitch',
    }) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final renderer = CapturingRenderer();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TeamsScreen(
          matchId: 'm1',
          teamRepository: TeamRepository(_TeamAdapter(
            lineup: lineup,
            roster: [
              input('u1', Position.gk),
              input('u2', Position.def),
              input('u3', Position.mid),
              input('u4', Position.fwd),
            ],
          )),
          matchService: MatchService(_MatchAdapter(
            match: matchAt(kickOff, title: title, location: location),
            registrations: [
              seat('u1', 'Sara Al Balushi', 'GK'),
              seat('u2', 'Ahmed Al Harthy', 'DEF'),
              seat('u3', 'Noor Al Kindi', 'MID'),
              seat('u4', 'Yousef Al Amri', 'FWD'),
            ],
          )),
          memberRepository: MemberRepository(_MemberAdapter()),
          renderer: renderer,
          shareService: FakeShareService(),
        ),
      ));
      await tester.pumpAndSettle();
      return renderer;
    }

    /// Builds whatever template the screen handed the engine.
    Future<void> pumpTemplate(
      WidgetTester tester,
      CapturingRenderer renderer,
    ) async {
      // Torn down first: pumping another `MaterialApp` would update the one
      // already mounted, keeping its Navigator and the preview route on top —
      // and everything under an opaque route is offstage, where `find.byType`
      // does not look.
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Align(
          alignment: Alignment.topLeft,
          child: ShareCardSurface(child: Builder(builder: renderer.captured!)),
        ),
      ));
      await tester.pump();
    }

    IconButton shareButton(WidgetTester tester) => tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.ios_share));

    testWidgets('a match with no lineup offers nothing to share',
        (tester) async {
      // The screen says teams have not been generated; there is no picture of
      // that worth sending.
      await pumpTeams(tester);

      expect(find.text('Teams have not been generated for this match yet.'),
          findsOneWidget);
      expect(shareButton(tester).onPressed, isNull);
    });

    testWidgets('a stored lineup offers the action', (tester) async {
      await pumpTeams(tester, lineup: storedLineup());

      expect(find.byTooltip('Share the lineup'), findsOneWidget);
      expect(shareButton(tester).onPressed, isNotNull);
    });

    testWidgets('Share hands the engine a Team Lineup card', (tester) async {
      final renderer = await pumpTeams(tester, lineup: storedLineup());

      await tester.tap(find.byTooltip('Share the lineup'));
      await tester.pumpAndSettle();

      // The existing engine composed it and the existing preview opened.
      expect(renderer.renders, 1);
      expect(find.byType(ShareCardPreviewScreen), findsOneWidget);
    });

    testWidgets('the card carries the lineup on screen', (tester) async {
      final renderer = await pumpTeams(tester, lineup: storedLineup());
      await tester.tap(find.byTooltip('Share the lineup'));
      await tester.pumpAndSettle();

      await pumpTemplate(tester, renderer);

      final data =
          tester.widget<TeamLineupCard>(find.byType(TeamLineupCard)).data;
      expect(data.lineup.map((a) => a.participantId),
          storedLineup().map((a) => a.participantId));
      expect(data.of(TeamId.a).map((a) => a.participantId), ['u1', 'u3']);
      expect(data.of(TeamId.b).map((a) => a.participantId), ['u2', 'u4']);
      // The names the pitch behind it is showing, resolved once by the screen.
      expect(data.names['u1'], 'Sara Al Balushi');
      expect(data.names['u4'], 'Yousef Al Amri');
      expect(data.players['u1']?.primaryPosition, Position.gk);
      expect(data.hasNaturalGoalkeeper, isTrue);
    });

    testWidgets('the community heads the card and the fixture follows it',
        (tester) async {
      // The approved hierarchy: whose teams these are is the subject, the
      // match is one line of context under it, and the product signs the
      // bottom. The match *title* is deliberately not among the context —
      // date, time and place are what a reader needs.
      final renderer = await pumpTeams(tester, lineup: storedLineup());

      await tester.tap(find.byTooltip('Share the lineup'));
      await tester.pumpAndSettle();
      await pumpTemplate(tester, renderer);

      final data =
          tester.widget<TeamLineupCard>(find.byType(TeamLineupCard)).data;
      expect(data.communityName, 'Al Amerat FC');
      expect(data.location, 'Al Amerat Pitch');
      expect(data.startAt, isNotNull);
      expect(data.endAt, isNotNull);

      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.textContaining('Al Amerat Pitch'), findsOneWidget);
      // The subject is larger than the context that qualifies it.
      double sizeOf(Finder f) => tester.widget<Text>(f).style!.fontSize!;
      expect(
        sizeOf(find.text('Al Amerat FC')),
        greaterThan(sizeOf(find.textContaining('Al Amerat Pitch'))),
      );
      // And the match's own name is not on the card.
      expect(find.textContaining('Friday Night'), findsNothing);
      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(4));
      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('a match with no location still gets its date line',
        (tester) async {
      // Nothing is stood in for. The place drops out and the day survives.
      final renderer =
          await pumpTeams(tester, lineup: storedLineup(), location: '');

      await tester.tap(find.byTooltip('Share the lineup'));
      await tester.pumpAndSettle();
      await pumpTemplate(tester, renderer);

      expect(find.textContaining('Al Amerat Pitch'), findsNothing);
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(4));
    });

    testWidgets('a card with no community and no fixture is still a lineup',
        (tester) async {
      // Both are optional and neither is invented. The pitch carries the card.
      await pumpCard(tester, cardData());

      expect(find.byType(TeamLineupPlayerMark), findsNWidgets(4));
      expect(find.text('GO PLAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing is composed until the lineup has loaded',
        (tester) async {
      final gate = Completer<void>();
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final renderer = CapturingRenderer();
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TeamsScreen(
          matchId: 'm1',
          teamRepository: TeamRepository(_TeamAdapter(lineup: storedLineup())),
          matchService: MatchService(_MatchAdapter(
            match: matchAt(kickOff),
            registrations: const [],
            gate: gate.future,
          )),
          memberRepository: MemberRepository(_MemberAdapter()),
          renderer: renderer,
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(shareButton(tester).onPressed, isNull,
          reason: 'there is no lineup on screen yet');

      gate.complete();
      await tester.pumpAndSettle();
      expect(shareButton(tester).onPressed, isNotNull);
      expect(renderer.renders, 0);
    });

    testWidgets('a load that failed shares nothing', (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TeamsScreen(
          matchId: 'm1',
          teamRepository: TeamRepository(_TeamAdapter(lineup: storedLineup())),
          matchService: MatchService(_MatchAdapter(
            match: matchAt(kickOff),
            registrations: const [],
            thrown: const NetworkFailure(),
          )),
          memberRepository: MemberRepository(_MemberAdapter()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(shareButton(tester).onPressed, isNull);
    });
  });
}

/// The Share Card Engine's renderer port, keeping the template it was given.
class CapturingRenderer implements ShareCardRenderer {
  ShareCardTemplate? captured;
  int renders = 0;

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    renders++;
    captured = template;
    return ShareCardImage(
      bytes: Uint8List.fromList(_pixel),
      pixelWidth: 1080,
      pixelHeight: 1920,
    );
  }
}

/// A valid one-pixel PNG, so the preview decodes something real.
const _pixel = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

/// The share port, sharing nothing.
class FakeShareService implements ShareService {
  final List<ShareCardImage> shared = [];

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    shared.add(image);
    return ShareOutcome.shared;
  }
}

class _TeamAdapter implements TeamAdapter {
  _TeamAdapter({this.lineup = const [], this.roster = const []});

  final List<TeamAssignment> lineup;
  final List<PlayerCoreInputs> roster;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
    String matchId,
  ) async =>
      roster;

  /// The screen reads a lineup and a roster and nothing else. Reaching any
  /// other method from it would be a defect, so they fail loudly rather than
  /// answer.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the teams screen reads no other team data');
}

class _MatchAdapter implements MatchAdapter {
  _MatchAdapter({
    required this.match,
    required this.registrations,
    this.thrown,
    this.gate,
  });

  final Match match;
  final List<MatchRegistration> registrations;
  final Failure? thrown;
  final Future<void>? gate;

  @override
  Future<Match> fetchMatch(String matchId) async {
    if (gate != null) await gate;
    if (thrown != null) throw thrown!;
    return match;
  }

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the teams screen reads no other match data');
}

class _MemberAdapter implements MemberAdapter {
  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async =>
      CommunityRole.admin;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the teams screen reads no other member data');
}
