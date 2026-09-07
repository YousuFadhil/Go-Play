import 'package:btge/btge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_selector.dart';

/// The Team of Period selector, as arithmetic.
///
/// Pure input, pure output: every test here hands the selector a period's
/// evidence and reads the team back. Nothing mocks, nothing waits and nothing
/// touches a database — which is the point of the selector being pure, and what
/// makes these the specification rather than a description of it.
///
/// Two properties are worth more than the rest and are checked repeatedly: the
/// input's order can never reach the output, and the current overall rating can
/// never reach the selection.
void main() {
  /// One played side. `teamSize` is derived so a fixture cannot accidentally
  /// describe a side that does not add up — the selector refuses those, and
  /// that refusal is tested deliberately rather than by accident.
  PositionShapeObservation side({
    int gk = 0,
    int def = 0,
    int mid = 0,
    int fwd = 0,
    int unassigned = 0,
  }) =>
      PositionShapeObservation(
        teamSize: gk + def + mid + fwd + unassigned,
        gk: gk,
        def: def,
        mid: mid,
        fwd: fwd,
        unassigned: unassigned,
      );

  /// The identity every fixture agrees on. The selector does not read it --
  /// checking a window against its candidates is the repository's job -- so it
  /// is one constant rather than something each test varies.
  final identity = TeamOfPeriodIdentity(
    kind: TeamOfPeriodKind.weekly,
    periodKey: '2026-W31',
    periodStart: DateTime.utc(2026, 7, 27),
    periodEnd: DateTime.utc(2026, 8, 3),
    qualifyingMatchCount: 4,
    requiredMatches: 1,
  );

  TeamOfPeriodWindow windowOf({
    int matches = 4,
    List<int> sizes = const [5, 5, 5],
    List<PositionShapeObservation>? shapes,
  }) =>
      TeamOfPeriodWindow(
        kind: TeamOfPeriodKind.weekly,
        periodKey: '2026-W31',
        periodStart: DateTime.utc(2026, 7, 27),
        periodEnd: DateTime.utc(2026, 8, 3),
        qualifyingMatchCount: matches,
        requiredMatches: 1,
        evidenceLastChangedAt: DateTime.utc(2026, 8, 2),
        teamSizeObservations: sizes,
        positionShapeObservations:
            shapes ?? [side(gk: 1, def: 2, mid: 1, fwd: 1)],
      );

  /// One candidate. Defaults are deliberately level, so a test varies exactly
  /// the one thing it is about and everything else falls to `userId`.
  TeamOfPeriodCandidate player(
    String id, {
    Position primary = Position.mid,
    Position? secondary,
    bool eligible = true,
    double form = 0.10,
    double participation = 1,
    int mvp = 0,
    double goalForm = 0,
    double rating = 5,
    int goals = 0,
  }) =>
      TeamOfPeriodCandidate(
        userId: id,
        periodIdentity: identity,
        eligible: eligible,
        matchesPlayed: 4,
        participationRate: participation,
        wins: 2,
        draws: 1,
        losses: 1,
        goals: goals,
        goalsPerMatch: goals / 4,
        mvpCount: mvp,
        winRate: 0.5,
        pointsPerGame: 1.75,
        periodFormScore: form,
        goalFormContributionTotal: goalForm,
        periodPrimaryPosition: primary,
        periodSecondaryPosition: secondary,
        currentOverallRating: rating,
      );

  TeamOfPeriod run(
    TeamOfPeriodWindow window,
    List<TeamOfPeriodCandidate> candidates,
  ) =>
      TeamOfPeriodSelector.select(window: window, candidates: candidates);

  List<String> idsOf(TeamOfPeriod team) =>
      [for (final entry in team.selected) entry.userId];

  List<String> idsAt(TeamOfPeriod team, Position role) => [
        for (final entry in team.selected)
          if (entry.assignedPosition == role) entry.userId,
      ];

  group('the squad size is the median actual side', () {
    test('an odd number of sides takes the middle one', () {
      expect(TeamOfPeriodSelector.targetSquadSize([5, 5, 5]), 5);
      expect(TeamOfPeriodSelector.targetSquadSize([5, 6, 7]), 6);
    });

    test('an even number takes the two middle ones', () {
      expect(TeamOfPeriodSelector.targetSquadSize([6, 6, 7, 7]), 7);
      expect(TeamOfPeriodSelector.targetSquadSize([6, 6, 6, 6]), 6);
    });

    test('an exact half rounds up', () {
      expect(TeamOfPeriodSelector.targetSquadSize([5, 6]), 6);
      expect(TeamOfPeriodSelector.targetSquadSize([6, 7]), 7);
    });

    test('one big fixture does not stretch a small-sided community', () {
      // A community that plays five-a-side and once played eleven-a-side is a
      // five-a-side community. The mean would have said seven.
      expect(TeamOfPeriodSelector.targetSquadSize([5, 5, 5, 11]), 5);
    });

    test('it is capped at eleven', () {
      expect(TeamOfPeriodSelector.targetSquadSize([12, 14, 16]), 11);
      expect(TeamOfPeriodSelector.targetSquadSize([11, 11]), 11);
    });

    test('the observations are read in any order', () {
      expect(TeamOfPeriodSelector.targetSquadSize([11, 5, 5, 5]), 5);
      expect(TeamOfPeriodSelector.targetSquadSize([7, 6]), 7);
    });
  });

  group('the shape weights each played side equally', () {
    test('one side is one observation whatever its size', () {
      // A side of one defender and a side of ten midfielders. Equal-weight says
      // half and half; counting player rows would have said one in eleven
      // against ten in eleven, and the award would have had no defenders.
      final shares = TeamOfPeriodSelector.periodShares([
        side(def: 1),
        side(mid: 10),
      ]);

      expect(shares[Position.def], closeTo(0.5, 1e-9));
      expect(shares[Position.mid], closeTo(0.5, 1e-9));
    });

    test('an eleven-a-side outlier cannot outvote three five-a-sides', () {
      final shares = TeamOfPeriodSelector.periodShares([
        side(gk: 1, def: 2, mid: 1, fwd: 1),
        side(gk: 1, def: 2, mid: 1, fwd: 1),
        side(gk: 1, def: 2, mid: 1, fwd: 1),
        side(mid: 11),
      ]);

      // Three sides at 0.4 defenders and one at nothing: 0.3, not the 0.24 a
      // player-row count would have produced.
      expect(shares[Position.def], closeTo(0.3, 1e-9));
      expect(shares[Position.mid], closeTo((0.2 * 3 + 1) / 4, 1e-9));
    });

    test('an unassigned player is size but not shape', () {
      // A guest nobody placed. They played, so they count toward how big the
      // side was; they say nothing about where anyone stood.
      final withGuest = TeamOfPeriodSelector.periodShares([
        side(def: 1, mid: 1, unassigned: 8),
      ]);
      final without = TeamOfPeriodSelector.periodShares([
        side(def: 1, mid: 1),
      ]);

      expect(withGuest[Position.def], closeTo(0.5, 1e-9));
      expect(withGuest[Position.def], without[Position.def]);
      expect(withGuest[Position.mid], without[Position.mid]);
    });

    test('a side of nobody positioned says nothing rather than nothing at all',
        () {
      // It is skipped, not counted as a side with no defenders — which would
      // have quietly halved every share.
      final shares = TeamOfPeriodSelector.periodShares([
        side(def: 1, mid: 1),
        side(unassigned: 6),
      ]);

      expect(shares[Position.def], closeTo(0.5, 1e-9));
      expect(shares[Position.mid], closeTo(0.5, 1e-9));
    });

    test('a goalkeeper slot is never more than one', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(gk: 1, def: 1)]),
        [
          for (var i = 1; i <= 4; i++) player('u$i', primary: Position.gk),
          for (var i = 5; i <= 8; i++) player('u$i', primary: Position.def),
        ],
      );

      expect(team.initialSlotCounts[Position.gk], 1);
      expect(team.finalSlotCounts[Position.gk], 1);
      expect(idsAt(team, Position.gk), hasLength(1));
    });

    test('no goalkeeper evidence means no goalkeeper slot', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(def: 1, mid: 1)]),
        [
          for (var i = 1; i <= 3; i++) player('u$i', primary: Position.def),
          for (var i = 4; i <= 6; i++) player('u$i', primary: Position.mid),
          player('u7', primary: Position.gk),
        ],
      );

      expect(team.initialSlotCounts[Position.gk], 0);
      expect(idsAt(team, Position.gk), isEmpty);
    });

    test('an exact tie is broken by the axis', () {
      // Half defenders and half midfielders across four seats. Equal deficits
      // and equal shares, so the axis decides and DEF takes the first seat.
      final slots = TeamOfPeriodSelector.allocateSlots(
        shares: TeamOfPeriodSelector.periodShares([side(def: 1, mid: 1)]),
        targetSize: 4,
      );

      expect(slots[Position.def], 2);
      expect(slots[Position.mid], 2);
      expect(
        TeamOfPeriodSelector.allocateSlots(
          shares: TeamOfPeriodSelector.periodShares([side(def: 1, mid: 1)]),
          targetSize: 1,
        )[Position.def],
        1,
        reason: 'a single seat between equals goes to the earlier axis role',
      );
    });

    test('the order of the observations cannot change the slots', () {
      final shapes = [
        side(gk: 1, def: 2, mid: 1, fwd: 1),
        side(mid: 11),
        side(def: 3, fwd: 2),
      ];
      final forward = TeamOfPeriodSelector.allocateSlots(
        shares: TeamOfPeriodSelector.periodShares(shapes),
        targetSize: 5,
      );
      final reversed = TeamOfPeriodSelector.allocateSlots(
        shares: TeamOfPeriodSelector.periodShares(shapes.reversed.toList()),
        targetSize: 5,
      );

      expect(forward, reversed);
    });
  });

  group('the candidate ranking is the approved one and nothing else', () {
    test('the period form score comes first', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('a', form: 0.05),
          player('b', form: 0.20),
          player('c', form: 0.12),
        ],
      );

      expect(idsOf(team), ['b', 'c']);
    });

    test('participation breaks a tie on form', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('a', participation: 0.25),
          player('b', participation: 1),
          player('c', participation: 0.5),
        ],
      );

      expect(idsOf(team), ['b', 'c']);
    });

    test('the MVP count breaks a tie on participation', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('a', mvp: 0),
          player('b', mvp: 3),
          player('c', mvp: 1),
        ],
      );

      expect(idsOf(team), ['b', 'c']);
    });

    test('the capped goal contribution breaks a tie on MVPs', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('a', goalForm: 0.02),
          player('b', goalForm: 0.20),
          player('c', goalForm: 0.10),
        ],
      );

      expect(idsOf(team), ['b', 'c']);
    });

    test('the user id is the last resort', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [player('c'), player('a'), player('b')],
      );

      expect(idsOf(team), ['a', 'b']);
    });

    test('the current overall rating cannot alter the selection', () {
      // The whole point of the rating being presentation evidence: it is a live
      // global number, and a match played next month would move it. An award
      // for a week that has closed must not move with it.
      final window = windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]);
      final flat = run(window, [
        player('a', rating: 5),
        player('b', rating: 5),
        player('c', rating: 5),
      ]);
      final skewed = run(window, [
        player('a', rating: 1),
        player('b', rating: 10),
        player('c', rating: 9.9),
      ]);

      expect(idsOf(flat), ['a', 'b']);
      expect(idsOf(skewed), idsOf(flat));
    });

    test('raw goals cannot alter the selection', () {
      // Goals reach the ranking only through the capped contribution, so one
      // nine-goal afternoon cannot outrank a period of steady scoring.
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('a', goals: 0),
          player('b', goals: 9),
          player('c', goals: 40),
        ],
      );

      expect(idsOf(team), ['a', 'b'],
          reason: 'level on approved evidence, so the user id decides');
    });

    test('the order of the candidates cannot alter the output', () {
      final window = windowOf();
      List<TeamOfPeriodCandidate> squad() => [
            player('gk1', primary: Position.gk),
            player('d1', primary: Position.def, form: 0.3),
            player('d2', primary: Position.def, form: 0.2),
            player('m1', primary: Position.mid, form: 0.25),
            player('f1', primary: Position.fwd, form: 0.15),
          ];

      final forward = run(window, squad());
      final backward = run(window, squad().reversed.toList());

      expect(idsOf(forward), idsOf(backward));
      expect(forward.finalSlotCounts, backward.finalSlotCounts);
    });
  });

  group('a player is only awarded a position they actually played', () {
    test('period primaries fill a role before any secondary is considered', () {
      // The secondary here is the best player in the period. He still does not
      // take a defensive seat while two players who actually played there most
      // are available.
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(def: 1)]),
        [
          player('d1', primary: Position.def, form: 0.10),
          player('d2', primary: Position.def, form: 0.09),
          player('star',
              primary: Position.fwd, secondary: Position.def, form: 0.90),
        ],
      );

      expect(team.initialSlotCounts[Position.def], 2);
      expect(idsAt(team, Position.def), ['d1', 'd2']);
      expect(idsOf(team), isNot(contains('star')));
    });

    test('a secondary fills only a role whose primaries ran out', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(def: 1)]),
        [
          player('d1', primary: Position.def, form: 0.10),
          player('sec',
              primary: Position.fwd, secondary: Position.def, form: 0.05),
        ],
      );

      expect(idsAt(team, Position.def), ['d1', 'sec']);
    });

    test('a player picked as a secondary is not also picked as a primary', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(def: 1, mid: 1)]),
        [
          player('both',
              primary: Position.mid, secondary: Position.def, form: 0.5),
          player('m1', primary: Position.mid, form: 0.4),
          player('m2', primary: Position.mid, form: 0.3),
          player('m3', primary: Position.mid, form: 0.2),
        ],
      );

      final appearances =
          idsOf(team).where((id) => id == 'both').length;
      expect(appearances, 1);
      expect(idsOf(team).toSet(), hasLength(idsOf(team).length));
    });

    test('a player who never played a role never fills it', () {
      // Two defensive seats, one defender, and three forwards with no secondary
      // anywhere. The second defensive seat is released rather than given to
      // somebody who never stood there.
      final team = run(
        windowOf(sizes: const [3, 3, 3], shapes: [side(def: 2, fwd: 1)]),
        [
          player('d1', primary: Position.def),
          player('f1', primary: Position.fwd),
          player('f2', primary: Position.fwd),
          player('f3', primary: Position.fwd),
        ],
      );

      expect(team.initialSlotCounts[Position.def], 2);
      for (final entry in team.selected) {
        if (entry.assignedPosition == Position.def) {
          expect(entry.candidate.userId, 'd1');
        }
      }
      expect(idsAt(team, Position.def), ['d1']);
    });
  });

  group('a shortage releases the seat rather than filling it wrongly', () {
    test('the final shape differs from the shape the period asked for', () {
      final team = run(
        windowOf(sizes: const [3, 3, 3], shapes: [side(def: 2, fwd: 1)]),
        [
          player('d1', primary: Position.def),
          player('f1', primary: Position.fwd, form: 0.3),
          player('f2', primary: Position.fwd, form: 0.2),
        ],
      );

      expect(team.initialSlotCounts[Position.def], 2);
      expect(team.finalSlotCounts[Position.def], 1);
      expect(team.finalSlotCounts[Position.fwd], 2);
      expect(team.selected, hasLength(3));
    });

    test('a released seat goes only to a role with a primary left', () {
      // Nobody else played in defence, so the released defensive seat attaches
      // to attack -- where a real, unselected player actually played most.
      final team = run(
        windowOf(sizes: const [3, 3, 3], shapes: [side(def: 2, fwd: 1)]),
        [
          player('d1', primary: Position.def),
          player('f1', primary: Position.fwd, form: 0.3),
          player('f2', primary: Position.fwd, form: 0.2),
          player('spare', primary: Position.fwd, form: 0.1),
        ],
      );

      // No unselected player has defence as their Period Primary, so the
      // released seat can only attach to attack -- and it goes to the best
      // remaining forward rather than to `spare`, who is ranked below him.
      expect(idsAt(team, Position.def), ['d1']);
      expect(idsAt(team, Position.fwd), ['f1', 'f2']);
      expect(idsOf(team), isNot(contains('spare')));
    });

    test('the reallocated role follows the proportional deficit', () {
      // Shape says midfield is the biggest role, so the seat released by the
      // missing goalkeeper deepens midfield rather than attack.
      final team = run(
        windowOf(
          sizes: const [4, 4, 4],
          shapes: [side(gk: 1, mid: 2, fwd: 1)],
        ),
        [
          player('m1', primary: Position.mid, form: 0.4),
          player('m2', primary: Position.mid, form: 0.3),
          player('m3', primary: Position.mid, form: 0.2),
          player('f1', primary: Position.fwd, form: 0.35),
        ],
      );

      expect(team.initialSlotCounts[Position.gk], 1);
      expect(team.finalSlotCounts[Position.gk], 0);
      expect(team.finalSlotCounts[Position.mid], 3);
      expect(team.finalSlotCounts[Position.fwd], 1);
    });

    test('reallocation cannot produce a second goalkeeper', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(gk: 1, def: 1)]),
        [
          for (var i = 1; i <= 5; i++)
            player('gk$i', primary: Position.gk, form: 0.5 - i * 0.01),
          player('d1', primary: Position.def),
        ],
      );

      expect(team.finalSlotCounts[Position.gk], 1);
      expect(idsAt(team, Position.gk), hasLength(1));
    });

    test('fewer eligible players than the target makes a smaller team', () {
      final team = run(
        windowOf(sizes: const [11, 11, 11], shapes: [side(gk: 1, def: 2, mid: 2, fwd: 1)]),
        [
          player('gk1', primary: Position.gk),
          player('d1', primary: Position.def),
          player('m1', primary: Position.mid),
        ],
      );

      expect(team.targetSize, 11);
      expect(team.state, TeamOfPeriodState.selected);
      expect(team.selected, hasLength(3));
      expect(idsOf(team), ['gk1', 'd1', 'm1']);
    });

    test('every eligible player is taken where the target allows', () {
      final team = run(
        windowOf(sizes: const [6, 6, 6], shapes: [side(gk: 1, def: 2, mid: 2, fwd: 1)]),
        [
          player('gk1', primary: Position.gk),
          player('d1', primary: Position.def),
          player('d2', primary: Position.def),
          player('m1', primary: Position.mid),
          player('m2', primary: Position.mid),
          player('f1', primary: Position.fwd),
        ],
      );

      expect(team.targetSize, 6);
      expect(team.selected, hasLength(6));
      expect(idsOf(team).toSet(), {'gk1', 'd1', 'd2', 'm1', 'm2', 'f1'});
    });

    test('an ineligible player is never selected, however good', () {
      final team = run(
        windowOf(sizes: const [2, 2, 2], shapes: [side(mid: 1)]),
        [
          player('best', form: 0.99, eligible: false),
          player('a'),
          player('b'),
        ],
      );

      expect(idsOf(team), ['a', 'b']);
    });
  });

  group('the selector reports what it concluded', () {
    test('no qualifying match is its own answer', () {
      final team = run(
        windowOf(matches: 0, sizes: const [], shapes: const []),
        [player('a')],
      );

      expect(team.state, TeamOfPeriodState.noQualifyingMatches);
      expect(team.selected, isEmpty);
      expect(team.targetSize, 0);
      expect(team.periodKey, '2026-W31');
      expect(team.window.periodStart, DateTime.utc(2026, 7, 27));
    });

    test('matches with nobody eligible is a different answer', () {
      final team = run(
        windowOf(),
        [player('a', eligible: false), player('b', eligible: false)],
      );

      expect(team.state, TeamOfPeriodState.insufficientEligiblePlayers);
      expect(team.selected, isEmpty);
      expect(team.targetSize, 5, reason: 'the period still had a size');
    });

    test('nobody eligible still reports the shape the period had', () {
      // The size and the shape are properties of the football that was played.
      // Who turned out often enough cannot change how big the sides were or
      // how they were filled, so an empty award still says what it was an
      // award for -- and a shape of zeros would have claimed the period had
      // none.
      final team = run(
        windowOf(),
        [player('a', eligible: false), player('b', eligible: false)],
      );

      expect(team.initialSlotCounts, {
        Position.gk: 1,
        Position.def: 2,
        Position.mid: 1,
        Position.fwd: 1,
      });
      expect(
        team.initialSlotCounts.values.reduce((a, b) => a + b),
        team.targetSize,
      );
      // Nothing was awarded, and the final shape says exactly that.
      expect(team.finalSlotCounts.values, everyElement(0));
      expect(team.selected, isEmpty);
    });

    test('the threshold is not relaxed to fill that shape', () {
      // An ineligible player is not promoted to fill a slot the period asked
      // for, however good they were.
      final team = run(
        windowOf(),
        [
          player('best', form: 0.99, eligible: false),
          player('next', form: 0.98, eligible: false),
        ],
      );

      expect(team.state, TeamOfPeriodState.insufficientEligiblePlayers);
      expect(team.selected, isEmpty);
      expect(team.initialSlotCounts[Position.def], 2);
    });

    test('one qualifying match can still produce a team', () {
      final team = run(
        windowOf(matches: 1, sizes: const [5], shapes: [side(gk: 1, def: 2, mid: 1, fwd: 1)]),
        [
          player('gk1', primary: Position.gk),
          player('d1', primary: Position.def),
          player('d2', primary: Position.def),
          player('m1', primary: Position.mid),
          player('f1', primary: Position.fwd),
        ],
      );

      expect(team.state, TeamOfPeriodState.selected);
      expect(team.targetSize, 5);
      expect(team.selected, hasLength(5));
    });

    test('the selected list is ordered by role, then by the ranking', () {
      final team = run(
        windowOf(),
        [
          player('f1', primary: Position.fwd, form: 0.9),
          player('m1', primary: Position.mid, form: 0.8),
          player('d1', primary: Position.def, form: 0.2),
          player('d2', primary: Position.def, form: 0.7),
          player('gk1', primary: Position.gk, form: 0.1),
        ],
      );

      // GK, DEF, MID, FWD -- and the two defenders in ranked order, not the
      // order the phase happened to take them in.
      expect(idsOf(team), ['gk1', 'd2', 'd1', 'm1', 'f1']);
    });
  });

  group('broken evidence fails loudly instead of inventing football', () {
    test('a negative count is refused', () {
      expect(
        () => run(
          windowOf(shapes: [
            const PositionShapeObservation(
                teamSize: 4, gk: -1, def: 3, mid: 1, fwd: 1, unassigned: 0),
          ]),
          [player('a')],
        ),
        throwsArgumentError,
      );
    });

    test('a side that fielded nobody is refused', () {
      expect(
        () => run(windowOf(sizes: const [5, 0, 5]), [player('a')]),
        throwsArgumentError,
      );
    });

    test('a side whose players do not add up is refused', () {
      expect(
        () => run(
          windowOf(shapes: [
            const PositionShapeObservation(
                teamSize: 9, gk: 1, def: 2, mid: 1, fwd: 1, unassigned: 0),
          ]),
          [player('a')],
        ),
        throwsStateError,
      );
    });

    test('matches with no played side at all is refused', () {
      expect(
        () => run(windowOf(sizes: const []), [player('a')]),
        throwsStateError,
      );
    });

    test('matches with no recorded position at all is refused', () {
      expect(
        () => run(
          windowOf(shapes: [side(unassigned: 6)]),
          [player('a')],
        ),
        throwsStateError,
      );
    });

    test('an empty period is not refused for having no evidence', () {
      // The one case where none of it is required: no football, nothing to
      // describe, and a legitimate answer.
      expect(
        () => run(windowOf(matches: 0, sizes: const [], shapes: const []),
            const []),
        returnsNormally,
      );
    });
  });

  group('the award depends on the period and nothing outside it', () {
    test('the same evidence selects the same team every time', () {
      final window = windowOf();
      List<TeamOfPeriodCandidate> squad() => [
            player('gk1', primary: Position.gk),
            player('d1', primary: Position.def, form: 0.3),
            player('d2', primary: Position.def, form: 0.3),
            player('m1', primary: Position.mid),
            player('f1', primary: Position.fwd),
            player('f2', primary: Position.fwd),
          ];

      final runs = [for (var i = 0; i < 5; i++) run(window, squad())];
      for (final team in runs) {
        expect(idsOf(team), idsOf(runs.first));
        expect(team.finalSlotCounts, runs.first.finalSlotCounts);
        expect(
          [for (final e in team.selected) e.assignedPosition],
          [for (final e in runs.first.selected) e.assignedPosition],
        );
      }
    });

    test('a rating that moves after the period cannot move the award', () {
      final window = windowOf();
      List<TeamOfPeriodCandidate> squad(double Function(int) rating) => [
            for (var i = 1; i <= 6; i++)
              player('u$i',
                  primary: Position.values[i % 4],
                  form: 0.5 - i * 0.01,
                  rating: rating(i)),
          ];

      final before = run(window, squad((i) => 5));
      final after = run(window, squad((i) => 10 - i.toDouble()));

      expect(idsOf(after), idsOf(before));
      expect(
        [for (final e in after.selected) e.assignedPosition],
        [for (final e in before.selected) e.assignedPosition],
      );
    });
  });

  group('the scenarios the review asked for', () {
    test('a field of equal form resolves down the whole chain', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(mid: 1)]),
        [
          player('e', mvp: 1, goalForm: 0.10),
          player('a', mvp: 1, goalForm: 0.10),
          player('c', mvp: 2, goalForm: 0.02),
          player('b', mvp: 1, goalForm: 0.20),
          player('d', mvp: 0, goalForm: 0.90),
        ],
      );

      // Two MVPs first; then one MVP ordered by capped goal contribution; then
      // the two that are level on everything, by user id; the no-MVP player
      // last however many goals he scored.
      expect(idsOf(team), ['c', 'b', 'a', 'e']);
    });

    test('a defender and a striker compete only within their own roles', () {
      final team = run(
        windowOf(sizes: const [4, 4, 4], shapes: [side(def: 1, fwd: 1)]),
        [
          player('d1', primary: Position.def, form: 0.10),
          player('d2', primary: Position.def, form: 0.09),
          player('f1', primary: Position.fwd, form: 0.80),
          player('f2', primary: Position.fwd, form: 0.70),
          player('f3', primary: Position.fwd, form: 0.60),
        ],
      );

      // The forwards are the better players and still take only their two
      // seats: f3 is left out while a weaker defender plays.
      expect(idsAt(team, Position.def), ['d1', 'd2']);
      expect(idsAt(team, Position.fwd), ['f1', 'f2']);
      expect(idsOf(team), isNot(contains('f3')));
    });

    test('a community that never records a goalkeeper is given none', () {
      final team = run(
        windowOf(sizes: const [5, 5, 5], shapes: [side(def: 2, mid: 2, fwd: 1)]),
        [
          for (var i = 1; i <= 3; i++) player('d$i', primary: Position.def),
          for (var i = 1; i <= 3; i++) player('m$i', primary: Position.mid),
          for (var i = 1; i <= 3; i++) player('f$i', primary: Position.fwd),
        ],
      );

      expect(team.finalSlotCounts[Position.gk], 0);
      expect(team.selected, hasLength(5));
    });

    test('one eligible goalkeeper fills the one goalkeeping seat', () {
      final team = run(
        windowOf(),
        [
          player('gk1', primary: Position.gk, form: 0.01),
          for (var i = 1; i <= 3; i++) player('d$i', primary: Position.def),
          for (var i = 1; i <= 3; i++) player('m$i', primary: Position.mid),
          for (var i = 1; i <= 3; i++) player('f$i', primary: Position.fwd),
        ],
      );

      expect(idsAt(team, Position.gk), ['gk1']);
      expect(team.selected, hasLength(5));
    });

    test('a thin week produces a thin team rather than a fabricated one', () {
      final team = run(
        windowOf(sizes: const [7, 7, 7], shapes: [side(gk: 1, def: 3, mid: 2, fwd: 1)]),
        [
          player('d1', primary: Position.def),
          player('d2', primary: Position.def),
        ],
      );

      expect(team.targetSize, 7);
      expect(team.selected, hasLength(2));
      expect(idsOf(team), ['d1', 'd2']);
      expect(team.finalSlotCounts[Position.gk], 0);
    });
  });
}
