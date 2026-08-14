import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
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
  }) =>
      PlayerCoreInputs(
        userId: id,
        fullName: 'Player $id',
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
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final byId = {for (final p in squad) p.userId: p};
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PitchView(
            assignments: assignments,
            players: byId,
            hasNaturalGoalkeeper:
                hasNaturalGoalkeeper ?? squad.any((p) => p.isNaturalGoalkeeper),
            nameOf: (id) => byId[id]?.fullName ?? '—',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double yOf(WidgetTester tester, String name) =>
      tester.getCenter(find.text(name)).dy;

  group('the order of the rows', () {
    testWidgets('attack at the top, then midfield, defence, and goal',
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

      expect(yOf(tester, 'Player f0'), lessThan(yOf(tester, 'Player m0')));
      expect(yOf(tester, 'Player m0'), lessThan(yOf(tester, 'Player d0')));
      expect(yOf(tester, 'Player d0'), lessThan(yOf(tester, 'Player gk')));
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
      // Top row is the attack; the rows between it and the back line are the
      // midfield.
      final attack = rows[ys.first]!;
      final defence = rows[ys.last]!;
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

      // The three forwards share the top line, which is where they started.
      final top = yOf(tester, 'Player f0');
      expect(yOf(tester, 'Player f1'), top);
      expect(yOf(tester, 'Player f2'), top);
      expect(yOf(tester, 'Player m0'), greaterThan(top));
    });

    testWidgets('a forward drawn in midfield is still marked as it was',
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
      expect(find.text('Out of position'), findsNWidgets(3));
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

    testWidgets('a forward drawn in midfield says what it actually is',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
      );

      // One badge, naming the position the stored lineup holds.
      expect(find.text('Forward'), findsOneWidget);
      expect(find.byIcon(Icons.north), findsOneWidget);
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
          .where((card) => card.assignment.userId.startsWith('m'));

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

    testWidgets('the badge is not the out-of-position marker', (tester) async {
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
      expect(find.byIcon(Icons.north), findsOneWidget);
    });

    testWidgets('a transition keeps its own marker alongside', (tester) async {
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

      expect(find.text('Out of position'), findsNWidgets(2));
      expect(find.byIcon(Icons.north), findsOneWidget,
          reason: 'only one of the two forwards was moved by the drawing');
    });

    testWidgets('the badge reads the same way in Arabic', (tester) async {
      await pumpPitch(
        tester,
        assignments: liveShape(),
        squad: liveSquad(),
        hasNaturalGoalkeeper: false,
        locale: const Locale('ar'),
      );

      expect(find.text('مهاجم'), findsOneWidget);
      expect(find.byIcon(Icons.north), findsOneWidget);
    });

    testWidgets('the whole sentence is there for a screen reader',
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

      expect(labels, contains('Drawn in another line. Position: Forward.'));
    });

    testWidgets('a row full of badged cards still fits', (tester) async {
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
      expect(find.text('Forward'), findsNWidgets(4),
          reason: 'the four forwards drawn in midfield each say so');
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

      expect(ys[rows.first], 1, reason: 'one attacker on the top row');
      expect(ys[rows[1]], 3, reason: 'three in midfield');
      expect(ys[rows.last], 3, reason: 'three at the back, untouched');
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

    testWidgets('the out-of-position marker, which the row cannot show',
        (tester) async {
      await pumpPitch(
        tester,
        assignments: [
          at('m1', Position.def, basis: AssignmentBasis.transition),
        ],
        squad: [player('m1', Position.mid)],
        hasNaturalGoalkeeper: false,
      );

      expect(find.text('Out of position'), findsOneWidget);
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

  group('the sizes the engine supports', () {
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
}
