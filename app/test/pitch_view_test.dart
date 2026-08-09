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
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final byId = {for (final p in squad) p.userId: p};
    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PitchView(
            assignments: assignments,
            players: byId,
            hasNaturalGoalkeeper: hasNaturalGoalkeeper ??
                squad.any((p) => p.isNaturalGoalkeeper),
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
