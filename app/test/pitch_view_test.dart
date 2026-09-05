import 'dart:math' as math;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/teams/match_stage.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The pitch, on its own.
///
/// What is asserted is the layout rule and nothing above it: which rows exist,
/// what order they are in, and what a card carries. Who may tap one and what
/// happens then belong to the Teams screen and are covered there.
void main() {
  PlayerCoreInputs player(
    String id,
    Position primary, {
    Position? secondary,
    double rating = 6,
    String? avatarUrl,
    String? name,
  }) =>
      PlayerCoreInputs(
        userId: id,
        fullName: name ?? 'Player $id',
        overallRating: rating,
        primaryPosition: primary,
        secondaryPosition: secondary,
        dateOfBirth: DateTime(1995, 4, 17),
        avatarUrl: avatarUrl,
      );

  TeamAssignment at(String id, Position position,
          {AssignmentBasis basis = AssignmentBasis.primary}) =>
      TeamAssignment(
        userId: id,
        team: TeamId.a,
        assignedPosition: position,
        basis: basis,
      );

  Future<void> pumpPitch(
    WidgetTester tester, {
    required List<TeamAssignment> assignments,
    required List<PlayerCoreInputs> squad,
    bool? hasNaturalGoalkeeper,
    Locale locale = const Locale('en'),
    int Function(String participantId)? goalsOf,
    bool Function(String participantId)? isMvpOf,
    PitchPresentation presentation = PitchPresentation.phone,
    double? width,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final byId = {for (final p in squad) p.userId: p};
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width ?? PitchView.phonePitchWidth,
            child: PitchView(
              assignments: assignments,
              players: byId,
              hasNaturalGoalkeeper: hasNaturalGoalkeeper ??
                  squad.any((p) => p.isNaturalGoalkeeper),
              nameOf: (id) => byId[id]?.fullName ?? '—',
              goalsOf: goalsOf,
              isMvpOf: isMvpOf,
              presentation: presentation,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double yOf(WidgetTester tester, String name) =>
      tester.getCenter(find.text(name)).dy;

  group('the order of the rows', () {
    testWidgets('goal at the top, then defence, midfield, and attack',
        (tester) async {
      // A squad big enough to fill every line. A smaller one would not: the
      // approved rules fill defence to three before attack gets anybody, so a
      // one-per-line squad is drawn as one defensive line and says nothing
      // about row order. `formation_test.dart` covers that case directly.
      final squad = [
        player('gk', Position.gk),
        for (var i = 0; i < 4; i++) player('d$i', Position.def),
        for (var i = 0; i < 4; i++) player('m$i', Position.mid),
        for (var i = 0; i < 3; i++) player('f$i', Position.fwd),
      ];
      await pumpPitch(
        tester,
        assignments: [
          at('gk', Position.gk),
          for (var i = 0; i < 4; i++) at('d$i', Position.def),
          for (var i = 0; i < 4; i++) at('m$i', Position.mid),
          for (var i = 0; i < 3; i++) at('f$i', Position.fwd),
        ],
        squad: squad,
      );

      expect(yOf(tester, 'Player gk'), lessThan(yOf(tester, 'Player d0')));
      expect(yOf(tester, 'Player d0'), lessThan(yOf(tester, 'Player m0')));
      expect(yOf(tester, 'Player m0'), lessThan(yOf(tester, 'Player f0')));
    });

    testWidgets('a line nobody plays in is not drawn', (tester) async {
      // `BTGE-PD-1` forbids fixed formations, so a shape with no midfield is an
      // ordinary outcome rather than a special case to handle.
      final squad = [
        player('gk', Position.gk),
        player('d1', Position.def),
        player('d2', Position.def),
      ];
      await pumpPitch(
        tester,
        assignments: [
          at('gk', Position.gk),
          at('d1', Position.def),
          at('d2', Position.def),
        ],
        squad: squad,
      );

      expect(find.byType(PlayerCard), findsNWidgets(3));
    });
  });

  group('the attack is never drawn as large as the midfield', () {
    /// The players drawn on each y, which is how a row is identified on a pitch:
    /// everyone on one line shares a centre.
    Map<double, int> rowSizes(WidgetTester tester, List<String> names) {
      final rows = <double, int>{};
      for (final name in names) {
        final y = yOf(tester, name);
        rows[y] = (rows[y] ?? 0) + 1;
      }
      return rows;
    }

    testWidgets('a squad of five forwards and two midfielders is rearranged',
        (tester) async {
      // The engine put five forwards and two midfielders on this side. Drawn
      // literally that is three up front over two in the middle, which is the
      // shape the rule forbids. Nobody is dropped to fix it.
      final squad = [
        for (var i = 0; i < 4; i++) player('d$i', Position.def),
        for (var i = 0; i < 2; i++) player('m$i', Position.mid),
        for (var i = 0; i < 5; i++) player('f$i', Position.fwd),
      ];
      final names = [
        for (final p in squad) p.fullName,
      ];
      await pumpPitch(
        tester,
        assignments: [
          for (var i = 0; i < 4; i++) at('d$i', Position.def),
          for (var i = 0; i < 2; i++) at('m$i', Position.mid),
          for (var i = 0; i < 5; i++) at('f$i', Position.fwd),
        ],
        squad: squad,
        hasNaturalGoalkeeper: false,
      );

      // Every player is still on the pitch.
      expect(find.byType(PlayerCard), findsNWidgets(11));

      final rows = rowSizes(tester, names);
      final ys = rows.keys.toList()..sort();
      // Top row is the back line; the rows between it and the attack are the
      // midfield.
      final defence = rows[ys.first]!;
      final attack = rows[ys.last]!;
      final midfield = names.length - attack - defence;

      expect(attack, lessThan(midfield));
      expect(defence, 4, reason: 'the back line is untouched by the rule');
    });

    testWidgets('nothing moves when the drawing already satisfies the rule',
        (tester) async {
      final squad = [
        for (var i = 0; i < 4; i++) player('d$i', Position.def),
        for (var i = 0; i < 4; i++) player('m$i', Position.mid),
        for (var i = 0; i < 3; i++) player('f$i', Position.fwd),
      ];
      await pumpPitch(
        tester,
        assignments: [
          for (var i = 0; i < 4; i++) at('d$i', Position.def),
          for (var i = 0; i < 4; i++) at('m$i', Position.mid),
          for (var i = 0; i < 3; i++) at('f$i', Position.fwd),
        ],
        squad: squad,
        hasNaturalGoalkeeper: false,
      );

      // The three forwards share the bottom outfield line, which is where the
      // approved visual composition places the attack.
      final attack = yOf(tester, 'Player f0');
      expect(yOf(tester, 'Player f1'), attack);
      expect(yOf(tester, 'Player f2'), attack);
      expect(yOf(tester, 'Player m0'), lessThan(attack));
    });

    testWidgets('a forward drawn in midfield keeps its data without a badge',
        (tester) async {
      // The drawing moved a card between rows. It did not change what the
      // assignment says, which is what the out-of-position marker reports.
      final squad = [
        for (var i = 0; i < 3; i++) player('d$i', Position.def),
        for (var i = 0; i < 3; i++) player('f$i', Position.mid),
      ];
      await pumpPitch(
        tester,
        assignments: [
          for (var i = 0; i < 3; i++) at('d$i', Position.def),
          for (var i = 0; i < 3; i++)
            at('f$i', Position.fwd, basis: AssignmentBasis.transition),
        ],
        squad: squad,
        hasNaturalGoalkeeper: false,
      );

      expect(find.byType(PlayerCard), findsNWidgets(6));
      expect(find.text('Out of position'), findsNothing);
    });
  });

  group('the marker on a card the drawing moved', () {
    /// The live shape: three at the back, two in midfield, two up front. The
    /// rule brings one forward down, so exactly one card is marked.
    List<TeamAssignment> liveShape() => [
          for (var i = 0; i < 3; i++) at('d$i', Position.def),
          for (var i = 0; i < 2; i++) at('m$i', Position.mid),
          for (var i = 0; i < 2; i++) at('f$i', Position.fwd),
        ];

    List<PlayerCoreInputs> liveSquad() => [
          for (var i = 0; i < 3; i++) player('d$i', Position.def),
          for (var i = 0; i < 2; i++) player('m$i', Position.mid),
          for (var i = 0; i < 2; i++) player('f$i', Position.fwd),
        ];

    testWidgets('a forward drawn in midfield shows no transition badge',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Forward'), findsNothing);
      expect(find.byIcon(Icons.north), findsNothing);
      // Everybody is still on the pitch.
      expect(find.byType(PlayerCard), findsNWidgets(7));
    });

    testWidgets('the badge is on the moved card and on no other',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      final marked = tester
          .widgetList<PlayerCard>(find.byType(PlayerCard))
          .where((card) => card.movedFrom != null)
          .toList();

      expect(marked, hasLength(1));
      expect(marked.single.movedFrom, Position.fwd);
      expect(marked.single.assignment.assignedPosition, Position.fwd,
          reason: 'the card is marked, not rewritten');
      expect(marked.single.assignment.userId, startsWith('f'));
    });

    testWidgets('a real midfielder carries no badge', (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      final midfielders = tester
          .widgetList<PlayerCard>(find.byType(PlayerCard))
          .where((card) => card.assignment.participantId.startsWith('m'));

      expect(midfielders, hasLength(2));
      for (final card in midfielders) {
        expect(card.movedFrom, isNull);
      }
      // The midfield row holds three cards and only one of them is badged.
      expect(find.text('Midfielder'), findsNothing,
          reason: 'a card in the row its position names says nothing');
    });

    testWidgets('a pitch that moved nobody draws no badge', (tester) async {
      final squad = [
        for (var i = 0; i < 4; i++) player('d$i', Position.def),
        for (var i = 0; i < 4; i++) player('m$i', Position.mid),
        for (var i = 0; i < 3; i++) player('f$i', Position.fwd),
      ];
      await pumpPitch(
        tester,
        assignments: [
          for (var i = 0; i < 4; i++) at('d$i', Position.def),
          for (var i = 0; i < 4; i++) at('m$i', Position.mid),
          for (var i = 0; i < 3; i++) at('f$i', Position.fwd),
        ],
        squad: squad,
        hasNaturalGoalkeeper: false,
      );

      expect(find.byIcon(Icons.north), findsNothing);
      expect(find.text('Forward'), findsNothing);
    });

    testWidgets('neither transition marker is presentation chrome',
        (tester) async {
      // The two mean different things and are drawn separately. Here the engine
      // played every player in their own position, so the §5.1 marker stays
      // silent while the drawing's own marker speaks.
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Out of position'), findsNothing);
      expect(find.byIcon(Icons.north), findsNothing);
    });

    testWidgets('a transition keeps no visible position marker',
        (tester) async {
      // A forward the engine placed out of their own position, then moved down
      // a line by the drawing: both markers apply and both are shown, because
      // they answer different questions.
      final assignments = [
        for (var i = 0; i < 3; i++) at('d$i', Position.def),
        for (var i = 0; i < 2; i++) at('m$i', Position.mid),
        at('f0', Position.fwd, basis: AssignmentBasis.transition),
        at('f1', Position.fwd, basis: AssignmentBasis.transition),
      ];
      await pumpPitch(
        tester,
        assignments: assignments,
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Out of position'), findsNothing);
      expect(find.byIcon(Icons.north), findsNothing);
    });

    testWidgets('the badge is absent in Arabic too', (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
        locale: const Locale('ar'),
      );

      expect(find.text('مهاجم'), findsNothing);
      expect(find.byIcon(Icons.north), findsNothing);
    });

    testWidgets('the removed badge adds no screen-reader sentence',
        (tester) async {
      // The pill itself is an arrow and a word, which is all a card 82 pixels
      // wide has room for. Anybody not reading it by eye gets the sentence.
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label)
          .whereType<String>()
          .toList();

      expect(
          labels, isNot(contains('Drawn in another line. Position: Forward.')));
    });

    testWidgets('a crowded corrected row still fits without badges',
        (tester) async {
      // The badge sits inside the card's 82-pixel constraint. A midfield row of
      // four badged forwards is the widest this gets, and it must not overflow.
      final squad = [
        for (var i = 0; i < 4; i++) player('d$i', Position.def),
        for (var i = 0; i < 7; i++) player('f$i', Position.fwd),
      ];
      await pumpPitch(
        tester,
        assignments: [
          for (var i = 0; i < 4; i++) at('d$i', Position.def),
          for (var i = 0; i < 7; i++) at('f$i', Position.fwd),
        ],
        squad: squad,
        hasNaturalGoalkeeper: false,
      );

      expect(find.byType(PlayerCard), findsNWidgets(11));
      expect(find.text('Forward'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the displayed rule still holds with the badge on',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      final ys = <double, int>{};
      for (var i = 0; i < 3; i++) {
        ys.update(yOf(tester, 'Player d$i'), (n) => n + 1, ifAbsent: () => 1);
      }
      for (var i = 0; i < 2; i++) {
        ys.update(yOf(tester, 'Player m$i'), (n) => n + 1, ifAbsent: () => 1);
        ys.update(yOf(tester, 'Player f$i'), (n) => n + 1, ifAbsent: () => 1);
      }
      final rows = ys.keys.toList()..sort();

      expect(ys[rows.first], 3, reason: 'three at the back, untouched');
      expect(ys[rows[1]], 3, reason: 'three in midfield');
      expect(ys[rows.last], 1, reason: 'one attacker on the bottom row');
    });
  });

  group('the goalkeeper row', () {
    testWidgets('is drawn when somebody keeps goal by primary', (tester) async {
      final squad = [player('gk', Position.gk), player('df', Position.def)];
      await pumpPitch(
        tester,
        assignments: [at('gk', Position.gk), at('df', Position.def)],
        squad: squad,
      );

      expect(find.text('Player gk'), findsOneWidget);
    });

    testWidgets('a GK secondary counts as a natural goalkeeper (§10.1)',
        (tester) async {
      final squad = [
        player('util', Position.def, secondary: Position.gk),
        player('df', Position.def),
      ];
      expect(squad.first.isNaturalGoalkeeper, isTrue);

      await pumpPitch(
        tester,
        assignments: [at('util', Position.gk), at('df', Position.def)],
        squad: squad,
      );

      expect(find.text('Player util'), findsOneWidget);
    });

    testWidgets('is absent when nobody in the squad keeps goal',
        (tester) async {
      // The engine will not create a goalkeeper slot for a squad with no
      // natural goalkeeper, so this is what its output looks like — and the
      // pitch must not draw a position the match did not have.
      final squad = [
        player('d1', Position.def),
        player('m1', Position.mid),
      ];
      await pumpPitch(
        tester,
        assignments: [at('d1', Position.def), at('m1', Position.mid)],
        squad: squad,
      );

      expect(find.byType(PlayerCard), findsNWidgets(2));
      expect(find.text('Player d1'), findsOneWidget);
    });

    testWidgets('a keeper assigned to a squad with none is not drawn',
        (tester) async {
      // Belt and braces for the manual-override path: if somebody were put in
      // goal for a squad that has no natural goalkeeper, the row is still the
      // one the rule says exists, and it does not.
      await pumpPitch(
        tester,
        assignments: [at('d1', Position.gk), at('m1', Position.mid)],
        squad: [player('d1', Position.def), player('m1', Position.mid)],
      );

      expect(find.text('Player d1'), findsNothing);
      expect(find.text('Player m1'), findsOneWidget);
    });
  });

  group('what a card carries', () {
    testWidgets('the name and the rating, to one decimal', (tester) async {
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid, rating: 7.25)],
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Player m1'), findsOneWidget);
      // `OP-1`'s presentation scale is one decimal.
      expect(find.text('7.3'), findsOneWidget);
    });

    testWidgets('a figure standing in for a picture nobody set',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('the out-of-position marker is omitted in presentation mode',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [
          at('m1', Position.def, basis: AssignmentBasis.transition),
        ],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Out of position'), findsNothing);
    });

    testWidgets('a secondary placement is not marked (BTGE-PT-2)',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [
          at('m1', Position.def, basis: AssignmentBasis.secondary),
        ],
        squad: [player('m1', Position.mid, secondary: Position.def)],
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Out of position'), findsNothing);
    });
  });

  group('the approved projected field plane', () {
    const size = Size(
      PitchView.shareBeforePitchWidth,
      PitchView.shareBeforePitchHeight,
    );

    test('penalty areas project to quadrilaterals, not screen rectangles', () {
      final points = PitchView.projectFieldRect(
        size,
        const Rect.fromLTWH(.32, .018, .36, .152),
      );

      final topWidth = (points[1] - points[0]).distance;
      final bottomWidth = (points[2] - points[3]).distance;
      expect(bottomWidth, greaterThan(topWidth));
      expect(points[0].dx, isNot(closeTo(points[3].dx, .01)));
      expect(points[1].dx, isNot(closeTo(points[2].dx, .01)));
    });

    test('center-circle samples are individually projected from field space',
        () {
      const segments = 16;
      final samples = PitchView.projectCenterCircle(
        size,
        segments: segments,
      );
      const fieldSample = Offset(.5, .65);
      final projected = PitchView.projectFieldPoint(size, fieldSample);

      expect(samples, hasLength(segments + 1));
      expect(samples[4].dx, closeTo(projected.dx, .001));
      expect(samples[4].dy, closeTo(projected.dy, .001));
      expect(samples.first, samples.last);
    });
  });

  group('the approved seven-player presentation', () {
    final fixtureNames = <String>[
      'ماجد أبو حافظ',
      'قيس البلوشي',
      'علي الرواحي',
      'عبدالله الغنيوي',
      'سالم فاضل',
      'خالد البلوشي',
      'بو عدول',
    ];

    List<PlayerCoreInputs> sevenSquad() => [
          player('p0', Position.gk, name: fixtureNames[0]),
          for (var index = 1; index <= 3; index++)
            player('p$index', Position.def, name: fixtureNames[index]),
          for (var index = 4; index <= 6; index++)
            player('p$index', Position.mid, name: fixtureNames[index]),
        ];

    List<TeamAssignment> sevenAssignments() => [
          at('p0', Position.gk),
          for (var index = 1; index <= 3; index++) at('p$index', Position.def),
          for (var index = 4; index <= 6; index++) at('p$index', Position.mid),
        ];

    testWidgets('the share card uses every exact approved source diameter',
        (tester) async {
      // The traced diameters are the share raster's, and stay the share
      // raster's. The phone reads them as placement and decides its own size
      // (below), which is the one thing this contract lets it decide.
      await pumpPitch(
        tester,
        assignments: sevenAssignments(),
        squad: sevenSquad(),
        locale: const Locale('ar'),
        presentation: PitchPresentation.shareResult,
        width: PitchView.shareBeforePitchWidth,
      );

      final actual = [
        for (var index = 0; index < 7; index++)
          tester.getSize(find.byKey(PitchView.avatarKey('p$index'))).width,
      ]..sort();
      final expected = <double>[83.46, 79.18, 81.32, 74.90, 77.04, 74.90, 74.90]
        ..sort();

      for (var index = 0; index < expected.length; index++) {
        expect(actual[index], closeTo(expected[index], .01));
      }
    });

    testWidgets('the phone draws one face, at the size a phone reads',
        (tester) async {
      // Seven a side is the approved small squad, and it is the one that gets
      // the largest faces: 54-56 points at the reference width, the same for
      // everybody, because the variation in the traced masters is an artefact
      // of the tracing and not a rule about who is standing where.
      await pumpPitch(
        tester,
        assignments: sevenAssignments(),
        squad: sevenSquad(),
        locale: const Locale('ar'),
      );

      final diameters = {
        for (var index = 0; index < 7; index++)
          tester.getSize(find.byKey(PitchView.avatarKey('p$index'))).width,
      };
      expect(diameters, hasLength(1));
      expect(diameters.single, inInclusiveRange(54, 56));
    });

    testWidgets('keeps only the name below and places metadata around avatar',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: sevenAssignments(),
        squad: sevenSquad(),
        locale: const Locale('ar'),
        goalsOf: (id) => id == 'p2' ? 2 : 0,
        isMvpOf: (id) => id == 'p2',
      );

      final avatar = tester.getRect(find.byKey(PitchView.avatarKey('p2')));
      final name = tester.getRect(find.byKey(PitchView.nameKey('p2')));
      final rating = tester.getRect(find.byKey(PitchView.ratingKey('p2')));
      final goal = tester.getRect(find.byKey(PitchView.goalKey('p2')));
      final mvp = tester.getRect(find.byKey(PitchView.mvpKey('p2')));

      expect(name.top, greaterThanOrEqualTo(avatar.bottom));
      expect(rating.bottom, lessThan(name.top));
      expect(rating.center.dx, lessThan(avatar.center.dx));
      expect(goal.center.dx, greaterThan(avatar.center.dx));
      expect(mvp.center.dx, greaterThan(avatar.center.dx));
      expect(goal.overlaps(mvp), isFalse);
      expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('player-number-');
        }),
        findsNothing,
      );
    });

    testWidgets('one goal is icon-only and multiple goals include the count',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: sevenAssignments(),
        squad: sevenSquad(),
        goalsOf: (id) => id == 'p1'
            ? 1
            : id == 'p2'
                ? 2
                : 0,
      );

      final one = find.byKey(PitchView.goalKey('p1'));
      final multiple = find.byKey(PitchView.goalKey('p2'));
      expect(
          find.descendant(of: one, matching: find.byIcon(Icons.sports_soccer)),
          findsOneWidget);
      expect(find.descendant(of: one, matching: find.text('1')), findsNothing);
      expect(
        find.descendant(of: multiple, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('every name gets the same envelope, marked or not',
        (tester) async {
      // **The envelope, not the fit.** This used to assert that ordinary
      // fixture names never reached their ellipsis, and that assertion no
      // longer says what it looks like it says: the widget tester draws with a
      // fixed-width placeholder font, so a name's measured width here is its
      // glyph count times its point size and nothing to do with Arabic. It held
      // only because the phone drew names at about six points — which is the
      // size this presentation was approved to stop drawing them at.
      //
      // What survives is the guarantee that was always about the layout: every
      // player is given exactly the same room for their name, so carrying a
      // goal or a star never costs a player a legible one. Genuinely long names
      // ellipsizing is the approved behaviour and is covered below.
      await pumpPitch(
        tester,
        assignments: sevenAssignments(),
        squad: sevenSquad(),
        locale: const Locale('ar'),
        goalsOf: (id) => id == 'p2' ? 2 : 0,
        isMvpOf: (id) => id == 'p2',
      );

      final widths = {
        for (var index = 0; index < fixtureNames.length; index++)
          tester.getSize(find.byKey(PitchView.nameKey('p$index'))).width,
      };
      expect(widths, hasLength(1),
          reason: 'Goal and MVP lanes never reduce the name envelope.');

      for (var index = 0; index < fixtureNames.length; index++) {
        final text =
            tester.widget<Text>(find.byKey(PitchView.nameKey('p$index')));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        // One line and an ellipsis, at a size a phone reads — never a name
        // shrunk until it fits.
        expect(text.style!.fontSize, inInclusiveRange(12, 13));
      }
    });

    testWidgets('dense layouts still ellipsize genuinely long names',
        (tester) async {
      const longName = 'عبدالرحمن بن سليمان الحارثي الطويل جداً';
      final squad = [
        player('gk', Position.gk, name: longName),
        for (var index = 0; index < 4; index++)
          player('d$index', Position.def, name: longName),
        for (var index = 0; index < 3; index++)
          player('m$index', Position.mid, name: longName),
        for (var index = 0; index < 3; index++)
          player('f$index', Position.fwd, name: longName),
      ];
      await pumpPitch(
        tester,
        assignments: [
          at('gk', Position.gk),
          for (var index = 0; index < 4; index++) at('d$index', Position.def),
          for (var index = 0; index < 3; index++) at('m$index', Position.mid),
          for (var index = 0; index < 3; index++) at('f$index', Position.fwd),
        ],
        squad: squad,
        locale: const Locale('ar'),
      );

      final finder = find.byKey(PitchView.nameKey('gk'));
      final text = tester.widget<Text>(finder);
      final painter = TextPainter(
        text: TextSpan(text: longName, style: text.style),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: tester.getSize(finder).width);
      expect(painter.didExceedMaxLines, isTrue);
    });
  });

  group('the sizes the engine supports', () {
    testWidgets('the phone pitch and player unit use the approved geometry',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
      );

      final pitch = tester.getSize(find.byKey(const ValueKey('match-pitch')));
      expect(pitch.width, PitchView.phonePitchWidth);
      expect(pitch.height, PitchView.phonePitchHeight);
      expect(
        pitch.width / pitch.height,
        closeTo(PitchView.phoneAspectRatio, 0.001),
      );
      // The approved phone depth, and the share raster's own. Deeper than the
      // share band of grass, and pinned, because it is the shape the whole
      // phone pitch was approved at.
      expect(PitchView.phoneAspectRatio, 1.38);
      expect(PitchView.phoneAspectRatio,
          isNot(closeTo(PitchView.shareBeforeAspectRatio, .2)));

      final avatar = tester.getSize(find.byKey(PitchView.avatarKey('m1')));
      expect(avatar.width, inInclusiveRange(54, 56));
      expect(avatar.height, avatar.width);

      final name = tester.widget<Text>(find.text('Player m1'));
      final rating = tester.widget<Text>(find.text('6.0'));
      expect(name.style!.fontSize, inInclusiveRange(12, 13));
      expect(name.style!.fontWeight, FontWeight.w700);
      expect(name.style!.color, MatchStage.ink);
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(rating.style!.fontSize, inInclusiveRange(11, 12));
      expect(rating.style!.fontWeight, FontWeight.w700);
      expect(rating.style!.color, MatchStage.ink);
      expect(
        tester.getSize(find.byKey(PitchView.ratingKey('m1'))).height,
        inInclusiveRange(20, 22),
      );
    });

    testWidgets('the phone rating pill is black, not a green pill on green',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
      );

      final pill = tester.widget<Container>(
        find.byKey(PitchView.ratingKey('m1')),
      );
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, MatchStage.phoneBadge);
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow, isNotNull);
      // A pill this tall with this radius is a full pill and nothing else.
      final radius = decoration.borderRadius! as BorderRadius;
      final height =
          tester.getSize(find.byKey(PitchView.ratingKey('m1'))).height;
      expect(radius.topLeft.x * 2, closeTo(height, .01));
    });

    testWidgets('a share pitch keeps the share pill, at the share size',
        (tester) async {
      // The same widget, the other answer. Nothing above may reach this.
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
        presentation: PitchPresentation.shareResult,
        width: PitchView.shareBeforePitchWidth,
      );

      final pill = tester.widget<Container>(
        find.byKey(PitchView.ratingKey('m1')),
      );
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, MatchStage.rating.withValues(alpha: .90));
      expect(decoration.boxShadow, isNull);
      expect(
        tester.getSize(find.byKey(PitchView.ratingKey('m1'))).height,
        closeTo(22, .01),
      );
      expect(
        tester.widget<Text>(find.text('6.0')).style!.fontSize,
        closeTo(14, .01),
      );
      expect(
        tester.getSize(find.byKey(PitchView.avatarKey('m1'))).width,
        closeTo(50, .01),
      );
    });

    testWidgets('a 2 v 2 side draws without a goalkeeper row', (tester) async {
      // `OP-2`'s minimum, from one side's point of view.
      await pumpPitch(
        tester,
        assignments: [at('d1', Position.def), at('m1', Position.mid)],
        squad: [player('d1', Position.def), player('m1', Position.mid)],
      );

      expect(find.byType(PlayerCard), findsNWidgets(2));
    });

    testWidgets('a 15-a-side line wraps rather than running off the screen',
        (tester) async {
      // `BTGE-PF-1`'s ceiling is 30 players, so one side can be 15. Nothing in
      // the layout is per-formation, so the only thing to check is that a wide
      // line stays on the pitch.
      final squad = [
        player('gk', Position.gk),
        for (var i = 0; i < 14; i++) player('m$i', Position.mid),
      ];
      await pumpPitch(
        tester,
        assignments: [
          at('gk', Position.gk),
          for (var i = 0; i < 14; i++) at('m$i', Position.mid),
        ],
        squad: squad,
      );

      expect(find.byType(PlayerCard), findsNWidgets(15));
      expect(tester.takeException(), isNull);
    });
  });

  group('the phone presentation, and the line it stops at', () {
    /// Every rectangle one player occupies on the pitch.
    ({Rect avatar, Rect name, Rect? rating, Rect? goal, Rect? mvp}) marksOf(
      WidgetTester tester,
      String id,
    ) {
      Rect? rectOf(Finder finder) =>
          finder.evaluate().isEmpty ? null : tester.getRect(finder);
      return (
        avatar: tester.getRect(find.byKey(PitchView.avatarKey(id))),
        name: tester.getRect(find.byKey(PitchView.nameKey(id))),
        rating: rectOf(find.byKey(PitchView.ratingKey(id))),
        goal: rectOf(find.byKey(PitchView.goalKey(id))),
        mvp: rectOf(find.byKey(PitchView.mvpKey(id))),
      );
    }

    /// Nothing any player is drawn as touches anything another player is drawn
    /// as. The rule the phone sizes faces by, read back off the drawing.
    void expectNothingCollides(WidgetTester tester, List<String> ids) {
      final boxes = <(String, String, Rect)>[];
      for (final id in ids) {
        final marks = marksOf(tester, id);
        boxes.add((id, 'face', marks.avatar));
        boxes.add((id, 'name', marks.name));
        if (marks.rating != null) boxes.add((id, 'rating', marks.rating!));
        if (marks.goal != null) boxes.add((id, 'goal', marks.goal!));
        if (marks.mvp != null) boxes.add((id, 'star', marks.mvp!));
      }
      for (var first = 0; first < boxes.length; first++) {
        for (var second = first + 1; second < boxes.length; second++) {
          final a = boxes[first];
          final b = boxes[second];
          if (a.$1 == b.$1) continue;
          expect(
            a.$3.intersect(b.$3).isEmpty,
            isTrue,
            reason: '${a.$1}.${a.$2} collides with ${b.$1}.${b.$2}',
          );
        }
      }
      expect(tester.takeException(), isNull);
    }

    List<PlayerCoreInputs> denseSquad() => [
          player('gk', Position.gk),
          for (var index = 0; index < 4; index++)
            player('d$index', Position.def),
          for (var index = 0; index < 3; index++)
            player('m$index', Position.mid),
          for (var index = 0; index < 3; index++)
            player('f$index', Position.fwd),
        ];

    List<TeamAssignment> denseAssignments() => [
          at('gk', Position.gk),
          for (var index = 0; index < 4; index++) at('d$index', Position.def),
          for (var index = 0; index < 3; index++) at('m$index', Position.mid),
          for (var index = 0; index < 3; index++) at('f$index', Position.fwd),
        ];

    const denseIds = [
      'gk',
      'd0',
      'd1',
      'd2',
      'd3',
      'm0',
      'm1',
      'm2',
      'f0',
      'f1',
      'f2',
    ];

    testWidgets('seven a side: nothing drawn touches anything else',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [
          at('p0', Position.gk),
          for (var index = 1; index <= 3; index++) at('p$index', Position.def),
          for (var index = 4; index <= 6; index++) at('p$index', Position.mid),
        ],
        squad: [
          player('p0', Position.gk),
          for (var index = 1; index <= 3; index++)
            player('p$index', Position.def),
          for (var index = 4; index <= 6; index++)
            player('p$index', Position.mid),
        ],
        locale: const Locale('ar'),
        goalsOf: (id) => id == 'p2' ? 3 : 0,
        isMvpOf: (id) => id == 'p2',
      );

      expectNothingCollides(tester, [
        for (var index = 0; index < 7; index++) 'p$index',
      ]);
    });

    testWidgets('eleven a side keeps the approved dense shape, and its room',
        (tester) async {
      // The 4-3-3 contract, on a phone. The rows are the solver's and are not
      // touched; what is asserted is that the phone still fits a readable face
      // into them and that nothing lands on anything.
      await pumpPitch(
        tester,
        assignments: denseAssignments(),
        squad: denseSquad(),
        locale: const Locale('ar'),
        goalsOf: (id) => id == 'f0' ? 2 : 0,
        isMvpOf: (id) => id == 'f0',
      );

      expect(find.byType(PlayerCard), findsNWidgets(11));
      // Four lines, in the order the pitch draws them, still.
      final keeper = tester.getCenter(find.byKey(PitchView.avatarKey('gk'))).dy;
      final back = tester.getCenter(find.byKey(PitchView.avatarKey('d0'))).dy;
      final middle = tester.getCenter(find.byKey(PitchView.avatarKey('m0'))).dy;
      final front = tester.getCenter(find.byKey(PitchView.avatarKey('f0'))).dy;
      expect(keeper, lessThan(back));
      expect(back, lessThan(middle));
      expect(middle, lessThan(front));

      // A crowded side still reads: every face the same size, and far larger
      // than the raster scaling this presentation replaced.
      final diameters = {
        for (final id in denseIds)
          tester.getSize(find.byKey(PitchView.avatarKey(id))).width,
      };
      expect(diameters, hasLength(1));
      expect(
        diameters.single,
        greaterThan(
          PitchView.phoneAvatarFloor(PitchView.phonePitchWidth) * 1.8,
        ),
      );
      expectNothingCollides(tester, denseIds);
    });

    testWidgets('a scorer who was also best on the pitch carries two badges',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: denseAssignments(),
        squad: denseSquad(),
        goalsOf: (id) => id == 'f0' ? 4 : 0,
        isMvpOf: (id) => id == 'f0',
      );

      final marks = marksOf(tester, 'f0');
      // Two badges, and they stay two: a single combined pill would read as
      // one thing done, and they were two.
      expect(marks.goal, isNotNull);
      expect(marks.mvp, isNotNull);
      expect(marks.goal!.overlaps(marks.mvp!), isFalse);
      expect(
        find.descendant(
          of: find.byKey(PitchView.goalKey('f0')),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsNothing,
        reason: 'the star does not move into the goal badge',
      );
      expect(
        find.descendant(
          of: find.byKey(PitchView.mvpKey('f0')),
          matching: find.byIcon(Icons.sports_soccer),
        ),
        findsNothing,
        reason: 'and the ball does not move into the star',
      );

      // Stacked, in that order, tight against each other.
      expect(marks.goal!.bottom, lessThanOrEqualTo(marks.mvp!.top));
      expect(marks.mvp!.top - marks.goal!.bottom, lessThan(6));

      // And all three stay attached to the face rather than floating off it:
      // each overlaps the face's own horizontal span, and none reaches the
      // name below.
      for (final badge in [marks.goal!, marks.mvp!, marks.rating!]) {
        expect(badge.left, lessThan(marks.avatar.right));
        expect(badge.right, greaterThan(marks.avatar.left));
        expect(badge.bottom, lessThan(marks.name.top));
      }
      expect(marks.rating!.left, lessThan(marks.avatar.left));
      expect(marks.goal!.right, greaterThan(marks.avatar.right));
      expect(marks.mvp!.right, greaterThan(marks.avatar.right));
    });

    testWidgets('the best player wears the gold, and nobody else does',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: denseAssignments(),
        squad: denseSquad(),
        isMvpOf: (id) => id == 'f0',
      );

      Color? ringOf(String id) {
        final box = tester.widget<DecoratedBox>(find.descendant(
          of: find.byKey(PitchView.avatarKey(id)),
          matching: find.byType(DecoratedBox),
        ));
        return (box.decoration as BoxDecoration).border?.top.color;
      }

      expect(ringOf('f0'), MatchStage.star);
      expect(ringOf('d0'), MatchStage.accent.withValues(alpha: .78));
    });

    testWidgets('the goal badge is restrained, and the share one is not',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
        goalsOf: (_) => 2,
      );

      final phone =
          tester.widget<Container>(find.byKey(PitchView.goalKey('m1')));
      // A goal wears its own colour, and it is neither the rating's black nor
      // the MVP's gold.
      expect((phone.decoration! as BoxDecoration).color, MatchStage.phoneGoal);
      expect((phone.decoration! as BoxDecoration).color,
          isNot(MatchStage.phoneBadge));
      expect(
          (phone.decoration! as BoxDecoration).color, isNot(MatchStage.star));
      expect(
        tester
            .widget<Icon>(find.descendant(
              of: find.byKey(PitchView.goalKey('m1')),
              matching: find.byIcon(Icons.sports_soccer),
            ))
            .color,
        MatchStage.ink,
        reason: 'white on deep orange, not the orange-on-dark the share uses',
      );
      expect(
        find.descendant(
          of: find.byKey(PitchView.goalKey('m1')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      await pumpPitch(
        tester,
        assignments: [at('m1', Position.mid)],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
        goalsOf: (_) => 2,
        presentation: PitchPresentation.shareResult,
        width: PitchView.shareBeforePitchWidth,
      );

      expect(
        tester
            .widget<Icon>(find.descendant(
              of: find.byKey(PitchView.goalKey('m1')),
              matching: find.byIcon(Icons.sports_soccer),
            ))
            .color,
        MatchStage.goal,
        reason: 'the share card keeps every value it was approved with',
      );
    });

    test('the phone values are its own, and the share raster is untouched', () {
      // The regression boundary, stated as the constants themselves. A phone
      // value that started reading a share value, or a share value edited to
      // suit the phone, fails here before it reaches a picture anybody sent.
      expect(MatchStage.pitchDark, const Color(0xFF237A3A));
      expect(MatchStage.pitchLight, const Color(0xFF3B9B43));
      expect(MatchStage.pitchLine, const Color(0xB3F5F8F6));
      expect(MatchStage.rating, const Color(0xFF082D22));
      expect(MatchStage.goal, const Color(0xFFFF6B57));
      expect(MatchStage.star, const Color(0xFFF5C451));
      expect(PitchView.shareBeforePitchWidth, 842.09);
      expect(PitchView.shareBeforePitchHeight, 502.90);
      expect(PitchView.shareBeforeAvatarDiameter, 83.46);
      expect(PitchView.shareResultAvatarDiameter, 83.46);
      expect(MatchStage.canonicalWidth, 1080.0);
      expect(MatchStage.canonicalHeight, 1920.0);

      expect(MatchStage.phonePitchLight, isNot(MatchStage.pitchLight));
      expect(MatchStage.phonePitchDark, isNot(MatchStage.pitchDark));
      expect(MatchStage.phoneBadge, isNot(MatchStage.rating));
      expect(
        PitchView.phoneAspectRatio,
        isNot(closeTo(PitchView.shareBeforeAspectRatio, .05)),
      );
    });
  });

  group('two whole pitches, with Team B standing the other way up', () {
    List<PlayerCoreInputs> squad11() => [
          player('gk', Position.gk),
          for (var i = 0; i < 4; i++) player('d$i', Position.def),
          for (var i = 0; i < 3; i++) player('m$i', Position.mid),
          for (var i = 0; i < 3; i++) player('f$i', Position.fwd),
        ];

    List<TeamAssignment> lineup11(TeamId team) => [
          TeamAssignment(
              userId: 'gk',
              team: team,
              assignedPosition: Position.gk,
              basis: AssignmentBasis.primary),
          for (var i = 0; i < 4; i++)
            TeamAssignment(
                userId: 'd$i',
                team: team,
                assignedPosition: Position.def,
                basis: AssignmentBasis.primary),
          for (var i = 0; i < 3; i++)
            TeamAssignment(
                userId: 'm$i',
                team: team,
                assignedPosition: Position.mid,
                basis: AssignmentBasis.primary),
          for (var i = 0; i < 3; i++)
            TeamAssignment(
                userId: 'f$i',
                team: team,
                assignedPosition: Position.fwd,
                basis: AssignmentBasis.primary),
        ];

    Future<void> pumpTeam(WidgetTester tester, TeamId team) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final byId = {for (final p in squad11()) p.userId: p};
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: PitchView.phonePitchWidth,
              child: PitchView(
                assignments: lineup11(team),
                players: byId,
                hasNaturalGoalkeeper: true,
                nameOf: (id) => byId[id]?.fullName ?? '—',
                goalsOf: (id) => id == 'f0' ? 2 : 0,
                isMvpOf: (id) => id == 'f0',
                team: team,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    double depthOf(WidgetTester tester, String id) {
      final pitch = tester.getRect(find.byKey(const ValueKey('match-pitch')));
      return (tester.getCenter(find.byKey(PitchView.avatarKey(id))).dy -
              pitch.top) /
          pitch.height;
    }

    testWidgets('Team A runs from its own goal towards the halfway line',
        (tester) async {
      await pumpTeam(tester, TeamId.a);

      // The keeper is nearest the top, which is Team A's goal end, and the
      // attack is nearest the bottom, which is the edge it shares with Team B.
      final keeper = depthOf(tester, 'gk');
      final back = depthOf(tester, 'd0');
      final middle = depthOf(tester, 'm0');
      final front = depthOf(tester, 'f0');
      expect(keeper, lessThan(back));
      expect(back, lessThan(middle));
      expect(middle, lessThan(front));

      // And they use the half rather than huddling in a part of it.
      expect(keeper, closeTo(PitchView.phoneRowNear, .02));
      expect(front, closeTo(PitchView.phoneRowFar, .02));
    });

    testWidgets('Team B runs from the halfway line back towards its own goal',
        (tester) async {
      await pumpTeam(tester, TeamId.b);

      // The mirror, stated as the thing a reader sees: Team B's attack is at
      // the top of its half, against the edge Team A's attack is against, and
      // its keeper is at the bottom with its own goal behind.
      final keeper = depthOf(tester, 'gk');
      final back = depthOf(tester, 'd0');
      final middle = depthOf(tester, 'm0');
      final front = depthOf(tester, 'f0');
      expect(front, lessThan(middle));
      expect(middle, lessThan(back));
      expect(back, lessThan(keeper));

      expect(keeper, closeTo(1 - PitchView.phoneRowNear, .02));
      expect(front, closeTo(1 - PitchView.phoneRowFar, .02));
    });

    testWidgets('the two attacks face each other across the gap',
        (tester) async {
      await pumpTeam(tester, TeamId.a);
      final aFront = depthOf(tester, 'f0');
      final aKeeper = depthOf(tester, 'gk');

      await pumpTeam(tester, TeamId.b);
      final bFront = depthOf(tester, 'f0');
      final bKeeper = depthOf(tester, 'gk');

      // Team A sits above Team B on the page. Its attack is at the bottom of
      // its own half and Team B's is at the top of its own, so the two are the
      // closest things to the space between the sections; the two keepers are
      // the furthest apart.
      expect(aFront, greaterThan(.5));
      expect(bFront, lessThan(.5));
      expect(aKeeper, lessThan(.5));
      expect(bKeeper, greaterThan(.5));
      expect(aFront - aKeeper, closeTo(bKeeper - bFront, .01),
          reason: 'the two halves are the same drawing, one stood over');
    });

    testWidgets('nothing a reader reads is mirrored', (tester) async {
      await pumpTeam(tester, TeamId.b);

      // A flipped widget would have flipped these. The mirror is in the field
      // plane, so a face is a face, a name reads left to right off its own
      // baseline, and the badges keep the corners they were put in.
      //
      // Asserted as "nothing inside the pitch scales negatively in y", which
      // is what a vertical flip actually is; the framework puts transforms of
      // its own in any subtree and none of them turn anything over.
      for (final transform in tester.widgetList<Transform>(find.descendant(
        of: find.byType(PitchView),
        matching: find.byType(Transform),
      ))) {
        expect(transform.transform.storage[5], greaterThan(0),
            reason: 'a vertical flip would have reached the players');
      }
      for (final id in const ['gk', 'd0', 'f0']) {
        final avatar = tester.getRect(find.byKey(PitchView.avatarKey(id)));
        final name = tester.getRect(find.byKey(PitchView.nameKey(id)));
        expect(name.top, greaterThanOrEqualTo(avatar.bottom),
            reason: '$id: the name stays under the face, never over it');
      }
      final marked = tester.getRect(find.byKey(PitchView.avatarKey('f0')));
      final goal = tester.getRect(find.byKey(PitchView.goalKey('f0')));
      final mvp = tester.getRect(find.byKey(PitchView.mvpKey('f0')));
      final rating = tester.getRect(find.byKey(PitchView.ratingKey('f0')));
      expect(goal.center.dx, greaterThan(marked.center.dx));
      expect(mvp.center.dx, greaterThan(marked.center.dx));
      expect(rating.center.dx, lessThan(marked.center.dx));
      expect(goal.bottom, lessThanOrEqualTo(mvp.top),
          reason: 'goal over star, the same way up as Team A draws them');
      expect(goal.overlaps(mvp), isFalse);
    });

    testWidgets('the row a player stands in keeps its order across',
        (tester) async {
      // Mirroring depth must not disturb who stands where along a line.
      final order = <TeamId, List<double>>{};
      final centres = <TeamId, double>{};
      for (final team in TeamId.values) {
        await pumpTeam(tester, team);
        order[team] = [
          for (var i = 0; i < 4; i++)
            tester.getCenter(find.byKey(PitchView.avatarKey('d$i'))).dx,
        ];
        centres[team] =
            tester.getRect(find.byKey(const ValueKey('match-pitch'))).center.dx;
      }

      for (final team in TeamId.values) {
        final xs = order[team]!;
        expect(xs, orderedEquals([...xs]..sort()),
            reason: '$team: d0..d3 run left to right');
        expect((xs.first + xs.last) / 2, closeTo(centres[team]!, 1),
            reason: '$team: the line is centred on its own half');
      }

      // The two lines are the same line, not the same numbers. Both sides are
      // drawn on the same trapezoid, and Team B's back four stands nearer the
      // reader on it — the wide end — so it is drawn wider than Team A's,
      // which stands at the narrow end. That is the shared perspective doing
      // its job, not a different formation: the gaps within each line stay in
      // the proportion the solver set.
      final a = order[TeamId.a]!;
      final b = order[TeamId.b]!;
      expect(b.last - b.first, greaterThan(a.last - a.first),
          reason: 'Team B defends the near end, where the pitch is widest');
      for (final xs in [a, b]) {
        final gaps = [
          for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1],
        ];
        expect(gaps.reduce(math.min) / gaps.reduce(math.max), greaterThan(.85),
            reason: 'evenly spaced, never squeezed into a central column');
      }
    });

    testWidgets('the two sides are the same object, marked the other way',
        (tester) async {
      const size = Size(360, 360 / 1.38);

      // A. The outer shape is one shape. Not "a mirror of the other" — the
      //    same corners, in the same places, for both sides. This is what a
      //    canvas-space mirror used to break: Team B's trapezoid stood upside
      //    down and the two stopped looking like the same kind of object.
      final outline =
          PitchView.projectFieldRect(size, const Rect.fromLTWH(0, 0, 1, 1));
      double widthAt(double depth) =>
          (PitchView.projectFieldPoint(size, Offset(1, depth)) -
                  PitchView.projectFieldPoint(size, Offset(0, depth)))
              .dx;
      expect(widthAt(0), lessThan(widthAt(1)),
          reason: 'the shared outline narrows away from the reader');
      // The mirror cannot reach the outline: it takes a depth, and the outline
      // is not drawn through it.
      for (final corner in outline) {
        expect(corner.dy, isNot(isNaN));
      }
      expect(PitchView.phoneDepth(.25, mirror: false), .25);
      expect(PitchView.phoneDepth(.25, mirror: true), closeTo(.75, 1e-9));

      // B/C. The goal is at the outer end of each side and nowhere else:
      //      shallow depth for Team A, deep for Team B, never at the facing
      //      edge, so no goal can ever sit behind either set of attackers.
      const goal = Rect.fromLTWH(.446, -.028, .108, .028);
      final goalA = PitchView.phoneRect(goal, mirror: false);
      final goalB = PitchView.phoneRect(goal, mirror: true);
      expect(goalA.bottom, lessThan(.05), reason: 'Team A defends the top');
      expect(goalB.top, greaterThan(.95), reason: 'Team B defends the bottom');
      // And so are the areas in front of them.
      const penalty = Rect.fromLTWH(.32, .036, .36, .304);
      expect(PitchView.phoneRect(penalty, mirror: false).bottom, lessThan(.5));
      expect(PitchView.phoneRect(penalty, mirror: true).top, greaterThan(.5));

      // The centre cue sits at each side's facing edge, curving inward. It is
      // a local cue only: nothing asserts that the two arcs align.
      for (final mirror in const [false, true]) {
        final arc = PitchView.projectHalfCenterArc(size, mirror: mirror);
        final depths = arc.map((point) => point.dy);
        if (mirror) {
          expect(depths.reduce(math.min), lessThan(size.height * .05),
              reason: 'Team B: the cue is at the top, its facing edge');
        } else {
          expect(depths.reduce(math.max), greaterThan(size.height * .95),
              reason: 'Team A: the cue is at the bottom, its facing edge');
        }
      }

      // K. The share card keeps the whole pitch, with its closed centre ring.
      final ring = PitchView.projectCenterCircle(size);
      expect(ring.first.dx, closeTo(ring.last.dx, .01));
      expect(ring.first.dy, closeTo(ring.last.dy, .01));
      expect(ring.map((point) => point.dy).reduce(math.min),
          greaterThan(size.height * .2));
      expect(ring.map((point) => point.dy).reduce(math.max),
          lessThan(size.height * .8));
    });

    testWidgets('both pitches are drawn at exactly the same size',
        (tester) async {
      // Contract: one phone half-pitch aspect, and both sides get it.
      await pumpTeam(tester, TeamId.a);
      final a = tester.getRect(find.byKey(const ValueKey('match-pitch')));
      await pumpTeam(tester, TeamId.b);
      final b = tester.getRect(find.byKey(const ValueKey('match-pitch')));
      expect(a.width, b.width);
      expect(a.height, b.height);
      expect(a.width / a.height, closeTo(PitchView.phoneAspectRatio, .001));
    });

    testWidgets('an eleven-a-side stays safe on both sides', (tester) async {
      const ids = [
        'gk',
        'd0',
        'd1',
        'd2',
        'd3',
        'm0',
        'm1',
        'm2',
        'f0',
        'f1',
        'f2',
      ];
      for (final team in TeamId.values) {
        await pumpTeam(tester, team);
        final pitch = tester.getRect(find.byKey(const ValueKey('match-pitch')));
        final boxes = <(String, Rect)>[];
        for (final id in ids) {
          for (final key in [
            PitchView.avatarKey(id),
            PitchView.nameKey(id),
            PitchView.ratingKey(id),
            PitchView.goalKey(id),
            PitchView.mvpKey(id),
          ]) {
            final finder = find.byKey(key);
            if (finder.evaluate().isEmpty) continue;
            final rect = tester.getRect(finder);
            boxes.add((id, rect));
            // Inside the touchlines at that depth, on either side.
            final dy = rect.center.dy - pitch.top;
            for (final right in const [false, true]) {
              final top = PitchView.projectFieldPoint(
                pitch.size,
                Offset(right ? 1 : 0, 0),
              );
              final foot = PitchView.projectFieldPoint(
                pitch.size,
                Offset(right ? 1 : 0, 1),
              );
              final t = ((dy - top.dy) / (foot.dy - top.dy)).clamp(0.0, 1.0);
              final edge = pitch.left + top.dx + (foot.dx - top.dx) * t;
              if (right) {
                expect(rect.right, lessThanOrEqualTo(edge + .5),
                    reason: '$team $id past the right touchline');
              } else {
                expect(rect.left, greaterThanOrEqualTo(edge - .5),
                    reason: '$team $id past the left touchline');
              }
            }
          }
        }
        for (var a = 0; a < boxes.length; a++) {
          for (var b = a + 1; b < boxes.length; b++) {
            if (boxes[a].$1 == boxes[b].$1) continue;
            expect(boxes[a].$2.intersect(boxes[b].$2).isEmpty, isTrue,
                reason: '$team ${boxes[a].$1} collides with ${boxes[b].$1}');
          }
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the share pitch is not mirrored', (tester) async {
      // The regression boundary for this cycle, stated in the one place the
      // two could have been confused.
      for (final team in TeamId.values) {
        final byId = {for (final p in squad11()) p.userId: p};
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: PitchView.shareBeforePitchWidth,
                child: PitchView(
                  assignments: lineup11(team),
                  players: byId,
                  hasNaturalGoalkeeper: true,
                  nameOf: (id) => byId[id]?.fullName ?? '—',
                  presentation: PitchPresentation.shareResult,
                  team: team,
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        final pitch = tester.getRect(find.byKey(const ValueKey('match-pitch')));
        expect(pitch.width / pitch.height,
            closeTo(PitchView.shareBeforeAspectRatio, .001),
            reason: '$team keeps the share raster');
        double depth(String id) =>
            (tester.getCenter(find.byKey(PitchView.avatarKey(id))).dy -
                pitch.top) /
            pitch.height;
        // Both share sides still run keeper-at-the-top, exactly as approved.
        expect(depth('gk'), lessThan(depth('d0')), reason: '$team');
        expect(depth('d0'), lessThan(depth('f0')), reason: '$team');
        expect(depth('gk'), closeTo(.13, .01), reason: '$team');
        expect(depth('f0'), closeTo(.82, .01), reason: '$team');
      }
    });
  });
}
