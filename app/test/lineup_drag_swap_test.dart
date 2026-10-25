import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/teams/lineup_swap.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/teams/pitch_drag.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/infrastructure/supabase/mappers/discover_mapper.dart';
import 'package:go_play/infrastructure/supabase/mappers/team_mapper.dart';

/// Drag-to-swap and the stored order inside a line (migration `0107`).
///
/// The pure half -- which operation a drop is, and which order each line is
/// stored in afterwards -- is asserted here directly. The screen half (who may
/// drag, the confirmation on a played match, the sheet) is in
/// `teams_screen_test.dart`.
void main() {
  TeamAssignment row(
    String id,
    TeamId team,
    Position? position, {
    int? order,
    bool guest = false,
  }) =>
      TeamAssignment(
        userId: guest ? null : id,
        professionalGuestId: guest ? id : null,
        team: team,
        assignedPosition: position,
        basis: guest ? null : AssignmentBasis.primary,
        lineOrder: order,
      );

  const names = {
    'ali': 'Ali',
    'badr': 'Badr',
    'zaid': 'Zaid',
    'hamad': 'Hamad',
    'omar': 'Omar',
    'gk': 'Keeper',
  };
  String nameOf(String id) => names[id] ?? id;
  final order = lineOrderThenName(nameOf);

  group('resolvePitchSwap -- the outcome table', () {
    final defA = row('ali', TeamId.a, Position.def);
    final defA2 = row('badr', TeamId.a, Position.def);
    final midA = row('zaid', TeamId.a, Position.mid);
    final defB = row('omar', TeamId.b, Position.def);
    final guestA = row('g1', TeamId.a, null, guest: true);
    final guestB = row('g2', TeamId.b, null, guest: true);

    test('same team, same position: a side swap', () {
      expect(resolvePitchSwap(defA, defA2), PitchSwapKind.sideSwap);
    });
    test('same team, different position: a position swap', () {
      expect(resolvePitchSwap(defA, midA), PitchSwapKind.positionSwap);
    });
    test('other team: a team swap, whatever the positions', () {
      expect(resolvePitchSwap(defA, defB), PitchSwapKind.teamSwap);
      expect(resolvePitchSwap(midA, defB), PitchSwapKind.teamSwap);
    });
    test('a guest without a position swaps across the teams', () {
      expect(resolvePitchSwap(guestA, defB), PitchSwapKind.teamSwap);
      expect(resolvePitchSwap(guestA, guestB), PitchSwapKind.teamSwap);
      expect(resolvePitchSwap(defB, guestA), PitchSwapKind.teamSwap);
    });
    test('the same player is no target', () {
      expect(resolvePitchSwap(defA, defA), isNull);
      expect(
          resolvePitchSwap(defA, row('ali', TeamId.a, Position.def)), isNull);
    });
    test('same team with a guest that has no position is no target', () {
      expect(resolvePitchSwap(defA, guestA), isNull);
      expect(resolvePitchSwap(guestA, defA), isNull);
      expect(resolvePitchSwap(guestA, row('g3', TeamId.a, null, guest: true)),
          isNull);
    });
  });

  group('lineOrderThenName', () {
    List<String> sorted(List<TeamAssignment> line) => [
          for (final a in [...line]..sort(order)) a.participantId
        ];

    test('no stored order reads by name, exactly as before', () {
      expect(
        sorted([
          row('zaid', TeamId.a, Position.def),
          row('ali', TeamId.a, Position.def),
          row('badr', TeamId.a, Position.def),
        ]),
        ['ali', 'badr', 'zaid'],
      );
    });
    test('a stored order wins over the name', () {
      expect(
        sorted([
          row('ali', TeamId.a, Position.def, order: 3),
          row('badr', TeamId.a, Position.def, order: 1),
          row('zaid', TeamId.a, Position.def, order: 2),
        ]),
        ['badr', 'zaid', 'ali'],
      );
    });
    test('mixed: ordered first, the rest after them by name', () {
      expect(
        sorted([
          row('ali', TeamId.a, Position.def),
          row('zaid', TeamId.a, Position.def, order: 1),
          row('badr', TeamId.a, Position.def),
        ]),
        ['zaid', 'ali', 'badr'],
      );
    });
  });

  group('lineOrdersAfterSwap -- each takes the other\'s exact place', () {
    test('a side swap exchanges the two and materialises the line', () {
      final before = [
        row('ali', TeamId.a, Position.def),
        row('badr', TeamId.a, Position.def),
        row('zaid', TeamId.a, Position.def),
      ];
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: before,
          firstId: 'ali',
          secondId: 'zaid',
          order: order,
        ),
        {
          (team: TeamId.a, position: Position.def): ['zaid', 'badr', 'ali'],
        },
      );
    });

    test('a side swap respects an order already stored', () {
      final before = [
        row('ali', TeamId.a, Position.def, order: 2),
        row('badr', TeamId.a, Position.def, order: 3),
        row('zaid', TeamId.a, Position.def, order: 1),
      ];
      // Drawn: zaid, ali, badr. Ali and Badr exchange.
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: before,
          firstId: 'badr',
          secondId: 'ali',
          order: order,
        ).values.single,
        ['zaid', 'badr', 'ali'],
      );
    });

    test('a position swap puts each in the other\'s slot of the other line',
        () {
      final before = [
        row('ali', TeamId.a, Position.def),
        row('badr', TeamId.a, Position.def),
        row('hamad', TeamId.a, Position.mid),
        row('omar', TeamId.a, Position.mid),
        row('zaid', TeamId.a, Position.mid),
      ];
      // Ali (DEF, first) and Omar (MID, second of hamad/omar/zaid).
      final after = [
        row('ali', TeamId.a, Position.mid),
        row('badr', TeamId.a, Position.def),
        row('hamad', TeamId.a, Position.mid),
        row('omar', TeamId.a, Position.def),
        row('zaid', TeamId.a, Position.mid),
      ];
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: after,
          firstId: 'ali',
          secondId: 'omar',
          order: order,
        ),
        {
          (team: TeamId.a, position: Position.mid): ['hamad', 'ali', 'zaid'],
          (team: TeamId.a, position: Position.def): ['omar', 'badr'],
        },
      );
    });

    test('a team swap of two at one position: each in the other\'s slot', () {
      final before = [
        row('ali', TeamId.a, Position.def),
        row('badr', TeamId.a, Position.def),
        row('hamad', TeamId.b, Position.def),
        row('omar', TeamId.b, Position.def),
        row('zaid', TeamId.b, Position.def),
      ];
      // Badr (A, second) and Zaid (B, third).
      final after = [
        row('ali', TeamId.a, Position.def),
        row('badr', TeamId.b, Position.def),
        row('hamad', TeamId.b, Position.def),
        row('omar', TeamId.b, Position.def),
        row('zaid', TeamId.a, Position.def),
      ];
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: after,
          firstId: 'badr',
          secondId: 'zaid',
          order: order,
        ),
        {
          (team: TeamId.b, position: Position.def): ['hamad', 'omar', 'badr'],
          (team: TeamId.a, position: Position.def): ['ali', 'zaid'],
        },
      );
    });

    test('a team swap at different positions keeps the index, clamped', () {
      final before = [
        row('ali', TeamId.a, Position.fwd),
        row('zaid', TeamId.b, Position.def),
        row('hamad', TeamId.b, Position.fwd),
      ];
      // Ali (A FWD, index 0) and Zaid (B DEF, index 0). Positions stay.
      final after = [
        row('ali', TeamId.b, Position.fwd),
        row('zaid', TeamId.a, Position.def),
        row('hamad', TeamId.b, Position.fwd),
      ];
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: after,
          firstId: 'ali',
          secondId: 'zaid',
          order: order,
        ),
        {
          (team: TeamId.b, position: Position.fwd): ['ali', 'hamad'],
          (team: TeamId.a, position: Position.def): ['zaid'],
        },
      );
    });

    test('a guest without a position stands in no line and writes none', () {
      final before = [
        row('g1', TeamId.a, null, guest: true),
        row('zaid', TeamId.b, Position.def),
      ];
      final after = [
        row('g1', TeamId.b, null, guest: true),
        row('zaid', TeamId.a, Position.def),
      ];
      expect(
        lineOrdersAfterSwap(
          before: before,
          after: after,
          firstId: 'g1',
          secondId: 'zaid',
          order: order,
        ),
        {
          (team: TeamId.a, position: Position.def): ['zaid'],
        },
      );
    });
  });

  group('the stored order is read from every lineup source', () {
    test('the lineup table', () {
      final read = teamAssignmentFromRow({
        'user_id': 'u1',
        'team': 'A',
        'assigned_position': 'DEF',
        'assignment_basis': 'PRIMARY',
        'line_order': 2,
      });
      expect(read.lineOrder, 2);
      expect(
        teamAssignmentFromRow({
          'user_id': 'u1',
          'team': 'A',
          'assigned_position': 'DEF',
          'assignment_basis': 'PRIMARY',
        }).lineOrder,
        isNull,
        reason: 'absent is the ordinary case: by name',
      );
    });
    test('the public match lineup', () {
      final entry = publicLineupEntryFromRow(
        {
          'team': 'B',
          'assigned_position': 'MID',
          'display_name': 'Ali',
          'participant_type': 'USER',
          'goals': 0,
          'is_mvp': false,
          'line_order': 1,
        },
        avatarUrl: (_) => null,
      );
      expect(entry.lineOrder, 1);
    });
    test('a move or a position change leaves the order behind', () {
      final placed = row('ali', TeamId.a, Position.def, order: 2);
      expect(placed.movedToOtherTeam().lineOrder, isNull);
      expect(placed.withPosition(Position.mid, null).lineOrder, isNull);
    });
  });

  group('the pitch', () {
    PlayerCoreInputs inputs(String id, Position position) => PlayerCoreInputs(
          userId: id,
          fullName: nameOf(id),
          overallRating: 6,
          primaryPosition: position,
          dateOfBirth: DateTime(1995, 4, 17),
        );

    /// A seven: a keeper, three defenders, two midfielders, a forward.
    List<TeamAssignment> seven({Map<String, int> orders = const {}}) => [
          row('gk', TeamId.a, Position.gk),
          for (final id in ['zaid', 'ali', 'badr'])
            row(id, TeamId.a, Position.def, order: orders[id]),
          row('hamad', TeamId.a, Position.mid),
          row('omar', TeamId.a, Position.mid),
          row('f1', TeamId.a, Position.fwd),
        ];

    Future<void> pumpPitch(
      WidgetTester tester,
      List<TeamAssignment> lineup, {
      bool Function(TeamAssignment, TeamAssignment)? canSwap,
      void Function(TeamAssignment, TeamAssignment)? onSwap,
    }) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final players = {
        for (final a in lineup)
          a.participantId: inputs(a.participantId, a.assignedPosition!),
      };
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: PitchView.phonePitchWidth,
              child: PitchView(
                assignments: lineup,
                players: players,
                nameOf: nameOf,
                canSwapPlayers: canSwap,
                onSwapPlayers: onSwap,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// The three defenders, left to right as drawn.
    List<String> drawnDefence(WidgetTester tester) {
      final ids = ['zaid', 'ali', 'badr'];
      double x(String id) =>
          tester.getCenter(find.byKey(PitchView.nameKey(id))).dx;
      return ids..sort((a, b) => x(a).compareTo(x(b)));
    }

    testWidgets(
        'no stored order: by name, unchanged; a stored order is '
        'respected, and so is a mixed one', (tester) async {
      await pumpPitch(tester, seven());
      final byName = drawnDefence(tester);
      // Left-to-right or right-to-left, the name decides: whichever direction
      // the first slot is drawn in, the rest follow it.
      final ltr = byName.first == 'ali';
      List<String> asDrawn(List<String> slots) =>
          ltr ? slots : slots.reversed.toList();
      expect(byName, asDrawn(['ali', 'badr', 'zaid']));

      await pumpPitch(tester, seven(orders: {'zaid': 1, 'ali': 2, 'badr': 3}));
      expect(drawnDefence(tester), asDrawn(['zaid', 'ali', 'badr']));

      await pumpPitch(tester, seven(orders: {'badr': 1}));
      expect(drawnDefence(tester), asDrawn(['badr', 'ali', 'zaid']));
    });

    testWidgets('without the swap callback nothing can be dragged',
        (tester) async {
      await pumpPitch(tester, seven());
      expect(find.byType(LongPressDraggable<TeamAssignment>), findsNothing);
      expect(find.byType(SwappablePlayer), findsNothing);
    });

    testWidgets('with it every card can be picked up and dropped on another',
        (tester) async {
      TeamAssignment? dragged;
      TeamAssignment? target;
      await pumpPitch(
        tester,
        seven(),
        canSwap: (a, b) => resolvePitchSwap(a, b) != null,
        onSwap: (a, b) {
          dragged = a;
          target = b;
        },
      );
      expect(find.byType(LongPressDraggable<TeamAssignment>), findsNWidgets(7));

      final from = tester.getCenter(find.byKey(PitchView.nameKey('ali')));
      final to = tester.getCenter(find.byKey(PitchView.nameKey('zaid')));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(Offset.lerp(from, to, .5)!);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dragged?.participantId, 'ali');
      expect(target?.participantId, 'zaid');
    });

    testWidgets('a board without the swap callback adds no drag scope',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchStageBoard(
              lineup: seven(),
              players: const {},
              nameOf: nameOf,
              hasNaturalGoalkeeper: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(PitchDragScope), findsNothing);
      expect(find.byType(LongPressDraggable<TeamAssignment>), findsNothing);
    });
  });
}
