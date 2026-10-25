import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/public_match_stage.dart';
import 'package:go_play/features/teams/match_stage.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_models.dart';

/// Every match pitch draws the recorded position (DD-29).
///
/// The row a player stands in is their `assignedPosition`, with no minimum and
/// no maximum on any line, and the side order stored for the line places them
/// in it. What the organizer drags is therefore what is stored. The screens
/// that mount these pitches are covered in their own tests; this asserts the
/// drawing.
void main() {
  TeamAssignment at(
    String id,
    Position? position, {
    TeamId team = TeamId.a,
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

  String nameOf(String id) => 'Player $id';

  Widget app(Widget child) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      );

  Future<void> pumpPitch(
    WidgetTester tester,
    List<TeamAssignment> lineup, {
    Comparator<TeamAssignment>? order,
    PitchPresentation presentation = PitchPresentation.phone,
    TeamId team = TeamId.a,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(SizedBox(
      width: presentation == PitchPresentation.phone
          ? PitchView.phonePitchWidth
          : MatchStage.sharePitchWidth,
      child: PitchView(
        assignments: lineup,
        nameOf: nameOf,
        layout: PitchLayoutMode.exactAssignedPositions,
        order: order,
        presentation: presentation,
        team: team,
      ),
    )));
    await tester.pumpAndSettle();
  }

  Rect avatar(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(PitchView.avatarKey(id)));

  group('the order inside a line', () {
    // Handed over as zaid, ali, badr: neither by name nor by any stored order.
    List<TeamAssignment> defence({Map<String, int> orders = const {}}) => [
          at('gk', Position.gk),
          for (final id in ['zaid', 'ali', 'badr'])
            at(id, Position.def, order: orders[id]),
        ];

    List<String> drawn(WidgetTester tester) {
      final ids = ['zaid', 'ali', 'badr'];
      return ids
        ..sort(
            (a, b) => avatar(tester, a).left.compareTo(avatar(tester, b).left));
    }

    testWidgets('with an order: by it; without one: as handed over',
        (tester) async {
      // By name first, to learn which way the first slot is drawn.
      await pumpPitch(tester, defence(), order: lineOrderThenName(nameOf));
      final byName = drawn(tester);
      final ltr = byName.first == 'ali';
      List<String> asDrawn(List<String> slots) =>
          ltr ? slots : slots.reversed.toList();
      expect(byName, asDrawn(['ali', 'badr', 'zaid']));

      // The stored order wins over the name.
      await pumpPitch(
        tester,
        defence(orders: {'badr': 1, 'zaid': 2, 'ali': 3}),
        order: lineOrderThenName(nameOf),
      );
      expect(drawn(tester), asDrawn(['badr', 'zaid', 'ali']));

      // No order: exactly the caller's, which is what the Team of Period
      // relies on -- its players arrive already ranked.
      await pumpPitch(
        tester,
        defence(orders: {'badr': 1, 'zaid': 2, 'ali': 3}),
      );
      expect(drawn(tester), asDrawn(['zaid', 'ali', 'badr']));
    });
  });

  group('no line has a minimum or a maximum', () {
    testWidgets('six defenders and no attack: all six, on one row',
        (tester) async {
      final lineup = [
        at('gk', Position.gk),
        for (var i = 0; i < 6; i++) at('d$i', Position.def),
        at('m0', Position.mid),
      ];
      await pumpPitch(tester, lineup, order: lineOrderThenName(nameOf));

      final pitch = tester.getRect(find.byKey(const ValueKey('match-pitch')));
      final rows = {
        for (var i = 0; i < 6; i++) avatar(tester, 'd$i').center.dy
      };
      expect(rows, hasLength(1), reason: 'one defence row, nobody borrowed');
      for (var i = 0; i < 6; i++) {
        final rect = avatar(tester, 'd$i');
        expect(pitch.contains(rect.center), isTrue, reason: 'd$i on the pitch');
      }
      expect(avatar(tester, 'm0').center.dy, isNot(rows.single),
          reason: 'the midfielder is not pulled into the defence');
    });

    testWidgets('eleven in one line and none elsewhere: all eleven drawn',
        (tester) async {
      final lineup = [for (var i = 0; i < 11; i++) at('m$i', Position.mid)];
      await pumpPitch(tester, lineup, order: lineOrderThenName(nameOf));

      final pitch = tester.getRect(find.byKey(const ValueKey('match-pitch')));
      for (var i = 0; i < 11; i++) {
        expect(pitch.contains(avatar(tester, 'm$i').center), isTrue,
            reason: 'm$i on the pitch');
      }
    });

    testWidgets('a guest with no position is drawn, in a row of their own',
        (tester) async {
      final lineup = [
        at('gk', Position.gk),
        at('d0', Position.def),
        at('m0', Position.mid),
        at('g1', null, guest: true),
        at('f0', Position.fwd),
      ];
      await pumpPitch(tester, lineup, order: lineOrderThenName(nameOf));

      final guest = avatar(tester, 'g1').center.dy;
      expect(guest, isNot(avatar(tester, 'm0').center.dy));
      expect(guest, isNot(avatar(tester, 'f0').center.dy));
      // Between the midfield and the attack, whichever way the half runs.
      final mid = avatar(tester, 'm0').center.dy;
      final attack = avatar(tester, 'f0').center.dy;
      expect(
        (guest - mid).sign == (attack - guest).sign,
        isTrue,
        reason: 'between midfield ($mid) and attack ($attack): $guest',
      );
    });
  });

  group('eleven a side: the goalkeeper is always visible', () {
    // The three approved shapes and one that is not.
    const shapes = <(int, int, int)>[
      (4, 3, 3),
      (4, 4, 2),
      (3, 4, 3),
      (5, 3, 2)
    ];

    List<TeamAssignment> eleven((int, int, int) shape, TeamId team) => [
          at('gk', Position.gk, team: team),
          for (var i = 0; i < shape.$1; i++)
            at('d$i', Position.def, team: team),
          for (var i = 0; i < shape.$2; i++)
            at('m$i', Position.mid, team: team),
          for (var i = 0; i < shape.$3; i++)
            at('f$i', Position.fwd, team: team),
        ];

    for (final presentation in PitchPresentation.values) {
      for (final team in TeamId.values) {
        for (final shape in shapes) {
          final label = '${shape.$1}-${shape.$2}-${shape.$3}, '
              'team ${team.name}, ${presentation.name}';
          testWidgets(label, (tester) async {
            final lineup = eleven(shape, team);
            await pumpPitch(
              tester,
              lineup,
              order: lineOrderThenName(nameOf),
              presentation: presentation,
              team: team,
            );

            final pitch =
                tester.getRect(find.byKey(const ValueKey('match-pitch')));
            final keeper = avatar(tester, 'gk');
            expect(keeper.width, greaterThan(0));
            expect(pitch.contains(keeper.center), isTrue,
                reason: 'keeper at ${keeper.center} on $pitch');
            expect(
                keeper.left >= pitch.left - 1 &&
                    keeper.right <= pitch.right + 1,
                isTrue,
                reason: 'keeper $keeper inside the pitch width $pitch');

            for (final other in lineup) {
              if (other.participantId == 'gk') continue;
              final rect = avatar(tester, other.participantId);
              expect(keeper.deflate(1).overlaps(rect.deflate(1)), isFalse,
                  reason:
                      'keeper $keeper overlaps ${other.participantId} $rect');
            }
            // Nearest its own goal: no outfield row stands behind the keeper.
            final outfield = [
              for (final other in lineup)
                if (other.participantId != 'gk')
                  avatar(tester, other.participantId).center.dy,
            ];
            final behind = team == TeamId.a
                ? outfield.every((dy) => dy > keeper.center.dy)
                : outfield.every((dy) => dy < keeper.center.dy);
            expect(behind, isTrue, reason: 'keeper is the hindmost row');
          });
        }
      }
    }
  });

  testWidgets(
      'a keeper with no GK in any profile is still drawn (the old layout left '
      'them off)', (tester) async {
    // The matchFormation layout draws a goalkeeper row only when somebody in
    // the squad names GK as primary or secondary. A player put in goal by
    // hand, with outfield positions in their profile, was then not drawn at
    // all: ten cards for eleven players. The exact layout asks the lineup.
    final lineup = [
      at('gk', Position.gk),
      for (var i = 0; i < 4; i++) at('d$i', Position.def),
      for (var i = 0; i < 3; i++) at('m$i', Position.mid),
      for (var i = 0; i < 3; i++) at('f$i', Position.fwd),
    ];
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(SizedBox(
      width: PitchView.phonePitchWidth,
      child: PitchView(
        assignments: lineup,
        nameOf: nameOf,
        hasNaturalGoalkeeper: false,
        layout: PitchLayoutMode.exactAssignedPositions,
        order: lineOrderThenName(nameOf),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(PitchView.avatarKey('gk')), findsOneWidget);
    expect(find.byType(PlayerCard), findsNWidgets(11));
  });

  group('the boards pass the layout to both pitches', () {
    List<TeamAssignment> lineup() => [
          at('a1', Position.gk),
          at('a2', Position.def),
          at('b1', Position.gk, team: TeamId.b),
          at('b2', Position.fwd, team: TeamId.b),
        ];

    testWidgets('MatchStageBoard: the given layout, and the stored order',
        (tester) async {
      await tester.pumpWidget(app(SingleChildScrollView(
        child: MatchStageBoard(
          lineup: lineup(),
          players: const {},
          nameOf: nameOf,
          hasNaturalGoalkeeper: true,
          layout: PitchLayoutMode.exactAssignedPositions,
        ),
      )));
      await tester.pumpAndSettle();

      final pitches = tester.widgetList<PitchView>(find.byType(PitchView));
      expect(pitches, hasLength(2));
      for (final pitch in pitches) {
        expect(pitch.layout, PitchLayoutMode.exactAssignedPositions);
        expect(pitch.order, isNotNull);
      }
    });

    testWidgets('MatchStageBoard: a caller that names none is unchanged',
        (tester) async {
      await tester.pumpWidget(app(SingleChildScrollView(
        child: MatchStageBoard(
          lineup: lineup(),
          players: const {},
          nameOf: nameOf,
          hasNaturalGoalkeeper: true,
        ),
      )));
      await tester.pumpAndSettle();

      for (final pitch
          in tester.widgetList<PitchView>(find.byType(PitchView))) {
        expect(pitch.layout, PitchLayoutMode.matchFormation);
      }
    });

    testWidgets('the public match page draws the recorded positions',
        (tester) async {
      PublicLineupEntry entry(String name, String team, String? position) =>
          PublicLineupEntry(
            team: team,
            assignedPosition: position,
            displayName: name,
            isProfessionalGuest: false,
            goals: 0,
            isMvp: false,
          );
      await tester.pumpWidget(app(SingleChildScrollView(
        child: PublicMatchStage(
          match: PublicCompletedMatch(
            id: 'm1',
            communityId: 'c1',
            communityName: 'Al Amerat FC',
            startAt: DateTime(2026, 10, 1, 20),
            endAt: DateTime(2026, 10, 1, 21),
            hasResult: false,
            lineup: [
              entry('Keeper A', 'A', 'GK'),
              for (var i = 0; i < 6; i++) entry('Back $i', 'A', 'DEF'),
              entry('Keeper B', 'B', 'GK'),
              entry('Wing B', 'B', 'FWD'),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();

      final pitches = tester.widgetList<PitchView>(find.byType(PitchView));
      expect(pitches, hasLength(2));
      for (final pitch in pitches) {
        expect(pitch.layout, PitchLayoutMode.exactAssignedPositions);
      }
      for (var i = 0; i < 6; i++) {
        expect(find.text('Back $i'), findsOneWidget);
      }
    });
  });
}
