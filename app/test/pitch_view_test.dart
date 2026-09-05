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
      // The approved depth, and the approved range it has to stay inside. The
      // share raster's 1.675 is outside it, which is the point.
      expect(PitchView.phoneAspectRatio, inInclusiveRange(1.38, 1.45));

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
      expect((phone.decoration! as BoxDecoration).color, MatchStage.phoneBadge);
      expect(
        tester
            .widget<Icon>(find.descendant(
              of: find.byKey(PitchView.goalKey('m1')),
              matching: find.byIcon(Icons.sports_soccer),
            ))
            .color,
        MatchStage.ink,
        reason: 'white on near-black, not the orange the share card uses',
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
}
