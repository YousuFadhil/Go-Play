import 'dart:io';
import 'dart:typed_data';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/results/match_result_card.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/teams/match_stage.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_models.dart';

/// The Completed Match share card, and the way into it from Match Details.
///
/// Three things are asserted and they are deliberately separate: what the card
/// draws when handed a result, who is offered the action that makes one, and
/// what happens to the picture afterwards on a platform that cannot share it.
/// Neither the Share Card Engine nor the result rules are retested here — both
/// have their own suites, and this card's job is to reuse them.
void main() {
  const names = {
    'u1': 'Sara Al Balushi',
    'u2': 'Ahmed Al Harthy',
    'u3': 'Noor Al Kindi',
    'u4': 'Yousef Al Amri',
  };

  TeamAssignment assignment(String id, TeamId team, Position position) =>
      TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: position,
        basis: AssignmentBasis.primary,
      );

  List<TeamAssignment> lineup() => [
        assignment('u1', TeamId.a, Position.gk),
        assignment('u3', TeamId.a, Position.mid),
        assignment('u2', TeamId.b, Position.def),
        assignment('u4', TeamId.b, Position.fwd),
      ];

  MatchResultCardData cardData({
    int? teamAScore = 3,
    int? teamBScore = 1,
    Map<String, int> goals = const {'u3': 2, 'u1': 1, 'u2': 1},
    String? mvp = 'u3',
    List<TeamAssignment>? assignments,
  }) {
    final squad = assignments ?? lineup();
    return MatchResultCardData(
      teamAScore: teamAScore,
      teamBScore: teamBScore,
      lineup: squad,
      players: {
        for (final x in squad)
          x.participantId: PlayerCoreInputs(
            userId: x.userId!,
            fullName: names[x.participantId] ?? '—',
            overallRating: 6,
            primaryPosition: x.assignedPosition!,
          ),
      },
      names: {
        for (final x in squad) x.participantId: names[x.participantId] ?? '—',
      },
      goals: goals,
      mvpParticipantId: mvp,
      communityName: 'Al Amerat FC',
      matchTitle: 'Friday Night',
      playedAt: DateTime(2026, 8, 21, 20),
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    MatchResultCardData data, {
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
          child: ShareCardSurface(child: MatchResultCard(data: data)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('Gate 1 - REF04 canonical result share', () {
    testWidgets('matches every authoritative region and seven-player anchor',
        (tester) async {
      const sourceWidth = 941.0;
      const sourceHeight = 1672.0;
      const sx = 1080 / sourceWidth;
      const sy = 1920 / sourceHeight;
      final gateLineup = <TeamAssignment>[
        for (final team in [TeamId.a, TeamId.b]) ...[
          assignment('${team.name}-gk', team, Position.gk),
          for (var index = 0; index < 3; index++)
            assignment('${team.name}-d$index', team, Position.def),
          for (var index = 0; index < 3; index++)
            assignment('${team.name}-m$index', team, Position.mid),
        ],
      ];
      final gateNames = {
        for (final item in gateLineup)
          item.participantId: '${item.team.name}-${item.participantId}',
      };
      final data = MatchResultCardData(
        teamAScore: 7,
        teamBScore: 4,
        lineup: gateLineup,
        players: {
          for (final item in gateLineup)
            item.participantId: PlayerCoreInputs(
              userId: item.userId!,
              fullName: gateNames[item.participantId]!,
              overallRating: 5.3,
              primaryPosition: item.assignedPosition!,
            ),
        },
        names: gateNames,
        goals: const {'a-m0': 2, 'b-m1': 1},
        mvpParticipantId: 'a-m0',
        communityName: 'الشمال',
        matchTitle: 'تمرين السبت',
        playedAt: DateTime(2026, 8, 29),
      );
      final boundaryKey = GlobalKey();
      await pumpCard(
        tester,
        data,
        locale: const Locale('ar'),
        boundaryKey: boundaryKey,
      );

      void expectRect(Finder finder, Rect source, {double tolerance = .15}) {
        final actual = tester.getRect(finder);
        final expected = Rect.fromLTWH(
          source.left * sx,
          source.top * sy,
          source.width * sx,
          source.height * sy,
        );
        expect(actual.left, closeTo(expected.left, tolerance));
        expect(actual.top, closeTo(expected.top, tolerance));
        expect(actual.width, closeTo(expected.width, tolerance));
        expect(actual.height, closeTo(expected.height, tolerance));
      }

      expectRect(
        find.byKey(const ValueKey('match-header')),
        const Rect.fromLTWH(0, 0, 941, 170),
      );
      expectRect(
        find.byKey(const ValueKey('result-strip')),
        const Rect.fromLTWH(51, 178, 839, 87),
      );
      expectRect(
        find.byKey(const ValueKey('team-a-section')),
        const Rect.fromLTWH(21, 282, 898, 607),
      );
      expectRect(
        find.byKey(const ValueKey('team-a-pitch')),
        const Rect.fromLTWH(46.68, 369.74, 842.09, 502.90),
      );
      expectRect(
        find.byKey(const ValueKey('team-b-section')),
        const Rect.fromLTWH(21, 903, 898, 607),
      );
      expectRect(
        find.byKey(const ValueKey('team-b-pitch')),
        const Rect.fromLTWH(48.82, 999.30, 838.88, 502.90),
      );
      expectRect(
        find.byKey(const ValueKey('share-footer')),
        const Rect.fromLTWH(0, 1538, 941, 134),
      );

      List<Rect> avatarsOn(String pitchKey) {
        final avatars = find.descendant(
          of: find.byKey(ValueKey(pitchKey)),
          matching: find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('player-avatar-');
          }),
        );
        final rects = [
          for (final element in avatars.evaluate())
            tester.getRect(find.byWidget(element.widget))
        ];
        rects.sort((a, b) {
          final byY = a.center.dy.compareTo(b.center.dy);
          return byY != 0 ? byY : a.center.dx.compareTo(b.center.dx);
        });
        return rects;
      }

      const expectedA = <(double, double, double)>[
        (466.12, 392.21, 83.46),
        (222.16, 558.06, 79.18),
        (455.42, 559.13, 81.32),
        (697.24, 559.13, 74.90),
        (213.60, 737.82, 77.04),
        (457.56, 736.75, 74.90),
        (700.45, 737.82, 74.90),
      ];
      const expectedB = <(double, double, double)>[
        (466.12, 1022.84, 83.46),
        (202.90, 1189.76, 77.04),
        (453.28, 1189.76, 81.32),
        (700.45, 1189.76, 83.46),
        (201.83, 1363.10, 79.18),
        (455.42, 1363.10, 79.18),
        (700.45, 1362.03, 79.18),
      ];

      void expectAnchors(
          List<Rect> actual, List<(double, double, double)> expected) {
        expect(actual, hasLength(expected.length));
        final expectedSorted = [...expected]..sort((a, b) {
            final byY = a.$2.compareTo(b.$2);
            return byY != 0 ? byY : a.$1.compareTo(b.$1);
          });
        for (var index = 0; index < expectedSorted.length; index++) {
          expect(actual[index].center.dx,
              closeTo(expectedSorted[index].$1 * sx, .2));
          expect(actual[index].center.dy,
              closeTo(expectedSorted[index].$2 * sy, .2));
          expect(
              actual[index].width, closeTo(expectedSorted[index].$3 * sx, .2));
          expect(
              actual[index].height, closeTo(expectedSorted[index].$3 * sx, .2));
        }
      }

      expectAnchors(avatarsOn('team-a-pitch'), expectedA);
      expectAnchors(avatarsOn('team-b-pitch'), expectedB);

      final strip = find.byKey(const ValueKey('result-strip'));
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const ValueKey('winner-trophy')),
        ),
        findsOneWidget,
      );
      expect(find.text('Winner'), findsNothing);
      expect(find.text('الفائز'), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
      expect(tester.takeException(), isNull);

      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));
      await tester.runAsync(() async {
        final directory = Directory('build/visual-verification-v2');
        await directory.create(recursive: true);
        await File('${directory.path}/share_result_saved.png')
            .writeAsBytes(image!.bytes, flush: true);
      });
      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
    });
  });

  group('Gate 2 - REF03 canonical before-result share', () {
    testWidgets('removes only result metadata and preserves approved geometry',
        (tester) async {
      const sx = 1080 / 941.0;
      const sy = 1920 / 1672.0;
      final gateLineup = <TeamAssignment>[
        for (final team in [TeamId.a, TeamId.b]) ...[
          assignment('${team.name}-gk', team, Position.gk),
          for (var index = 0; index < 3; index++)
            assignment('${team.name}-d$index', team, Position.def),
          for (var index = 0; index < 3; index++)
            assignment('${team.name}-m$index', team, Position.mid),
        ],
      ];
      final gateNames = {
        for (final item in gateLineup)
          item.participantId: '${item.team.name}-${item.participantId}',
      };
      final boundaryKey = GlobalKey();
      await pumpCard(
        tester,
        MatchResultCardData(
          lineup: gateLineup,
          players: {
            for (final item in gateLineup)
              item.participantId: PlayerCoreInputs(
                userId: item.userId!,
                fullName: gateNames[item.participantId]!,
                overallRating: 5.3,
                primaryPosition: item.assignedPosition!,
              ),
          },
          names: gateNames,
          communityName: 'الشمال',
          matchTitle: 'تمرين السبت',
          playedAt: DateTime(2026, 8, 29),
        ),
        locale: const Locale('ar'),
        boundaryKey: boundaryKey,
      );

      void expectRect(Finder finder, Rect source) {
        final actual = tester.getRect(finder);
        final expected = Rect.fromLTWH(
          source.left * sx,
          source.top * sy,
          source.width * sx,
          source.height * sy,
        );
        expect(actual.left, closeTo(expected.left, .15));
        expect(actual.top, closeTo(expected.top, .15));
        expect(actual.width, closeTo(expected.width, .15));
        expect(actual.height, closeTo(expected.height, .15));
      }

      expectRect(
        find.byKey(const ValueKey('match-header')),
        const Rect.fromLTWH(0, 0, 941, 170),
      );
      expect(find.byKey(const ValueKey('match-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-context-line')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-strip')), findsNothing);
      expectRect(
        find.byKey(const ValueKey('team-a-section')),
        const Rect.fromLTWH(21, 220, 898, 607),
      );
      expectRect(
        find.byKey(const ValueKey('team-a-pitch')),
        const Rect.fromLTWH(46.68, 307.74, 842.09, 502.90),
      );
      expectRect(
        find.byKey(const ValueKey('team-b-section')),
        const Rect.fromLTWH(21, 855, 898, 607),
      );
      expectRect(
        find.byKey(const ValueKey('team-b-pitch')),
        const Rect.fromLTWH(48.82, 951.30, 838.88, 502.90),
      );
      expectRect(
        find.byKey(const ValueKey('share-footer')),
        const Rect.fromLTWH(0, 1538, 941, 134),
      );

      expect(find.byKey(const ValueKey('winner-trophy')), findsNothing);
      expect(_goalBadges(), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));
      await tester.runAsync(() async {
        final directory = Directory('build/visual-verification-v2');
        await directory.create(recursive: true);
        await File('${directory.path}/share_before_result.png')
            .writeAsBytes(image!.bytes, flush: true);
      });
      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
    });
  });

  group('Gate 4 - dense 11-player contracts', () {
    MatchResultCardData denseData(int defence, int midfield, int attack) {
      final dense = <TeamAssignment>[
        for (final team in [TeamId.a, TeamId.b]) ...[
          assignment('${team.name}-gk', team, Position.gk),
          for (var index = 0; index < defence; index++)
            assignment('${team.name}-d$index', team, Position.def),
          for (var index = 0; index < midfield; index++)
            assignment('${team.name}-m$index', team, Position.mid),
          for (var index = 0; index < attack; index++)
            assignment('${team.name}-f$index', team, Position.fwd),
        ],
      ];
      return MatchResultCardData(
        teamAScore: 3,
        teamBScore: 2,
        lineup: dense,
        players: {
          for (final item in dense)
            item.participantId: PlayerCoreInputs(
              userId: item.userId!,
              fullName: 'عبدالرحمن بن سليمان الحارثي',
              overallRating: 5.3,
              primaryPosition: item.assignedPosition!,
            ),
        },
        names: {
          for (final item in dense)
            item.participantId: 'عبدالرحمن بن سليمان الحارثي',
        },
        goals: const {'a-f0': 2},
        mvpParticipantId: 'a-f0',
        communityName: 'الشمال',
        matchTitle: 'تمرين السبت',
        playedAt: DateTime(2026, 8, 29),
      );
    }

    void expectNoCollisionsOrBoundaryViolations(WidgetTester tester) {
      for (final pitchKey in ['team-a-pitch', 'team-b-pitch']) {
        final pitch = find.byKey(ValueKey(pitchKey));
        final pitchRect = tester.getRect(pitch);
        final cards = find.descendant(
          of: pitch,
          matching: find.byType(PlayerCard),
        );
        final rects = [
          for (final element in cards.evaluate())
            tester.getRect(find.byWidget(element.widget)),
        ];
        expect(rects, hasLength(11));
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(pitchRect.left - .1));
          expect(rect.top, greaterThanOrEqualTo(pitchRect.top - .1));
          expect(rect.right, lessThanOrEqualTo(pitchRect.right + .1));
          expect(rect.bottom, lessThanOrEqualTo(pitchRect.bottom + .1));
        }
        for (var first = 0; first < rects.length; first++) {
          for (var second = first + 1; second < rects.length; second++) {
            expect(
              rects[first].intersect(rects[second]).isEmpty,
              isTrue,
              reason: '$pitchKey players $first and $second collide',
            );
          }
        }
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> verifyDenseShape(
      WidgetTester tester, {
      required int defence,
      required int midfield,
      required int attack,
      required String filename,
    }) async {
      final boundaryKey = GlobalKey();
      await pumpCard(
        tester,
        denseData(defence, midfield, attack),
        locale: const Locale('ar'),
        boundaryKey: boundaryKey,
      );
      expect(find.byType(PlayerCard), findsNWidgets(22));
      expectNoCollisionsOrBoundaryViolations(tester);
      expect(find.byKey(PitchView.mvpKey('a-f0')), findsOneWidget);
      expect(find.byKey(PitchView.goalKey('a-f0')), findsOneWidget);
      final goal = tester.getRect(find.byKey(PitchView.goalKey('a-f0')));
      final mvp = tester.getRect(find.byKey(PitchView.mvpKey('a-f0')));
      final name = tester.getRect(find.byKey(PitchView.nameKey('a-f0')));
      expect(
        goal.bottom,
        lessThan(name.top),
      );
      expect(mvp.bottom, lessThan(name.top));
      expect(goal.overlaps(mvp), isFalse);

      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await tester.runAsync(() => captureShareCard(boundary));
      await tester.runAsync(() async {
        final directory = Directory('build/visual-verification-v2');
        await directory.create(recursive: true);
        await File('${directory.path}/$filename')
            .writeAsBytes(image!.bytes, flush: true);
      });
      expect(image!.pixelWidth, 1080);
      expect(image.pixelHeight, 1920);
    }

    testWidgets('4-3-3 has zero collisions and boundary violations',
        (tester) async {
      await verifyDenseShape(
        tester,
        defence: 4,
        midfield: 3,
        attack: 3,
        filename: 'share_11_433.png',
      );
    });

    testWidgets('4-4-2 has zero collisions and boundary violations',
        (tester) async {
      await verifyDenseShape(
        tester,
        defence: 4,
        midfield: 4,
        attack: 2,
        filename: 'share_11_442.png',
      );
    });

    testWidgets('3-4-3 has zero collisions and boundary violations',
        (tester) async {
      await verifyDenseShape(
        tester,
        defence: 3,
        midfield: 4,
        attack: 3,
        filename: 'share_11_343.png',
      );
    });
  });

  group('who won', () {
    test('Team A takes the higher score', () {
      final data = cardData(teamAScore: 3, teamBScore: 1);
      expect(data.winner, TeamId.a);
      expect(data.isDraw, isFalse);
    });

    test('and so does Team B', () {
      final data = cardData(teamAScore: 0, teamBScore: 2);
      expect(data.winner, TeamId.b);
      expect(data.isDraw, isFalse);
    });

    test('level scores name nobody', () {
      final data = cardData(teamAScore: 2, teamBScore: 2);
      expect(data.winner, isNull);
      expect(data.isDraw, isTrue);
    });

    testWidgets('the winning side is marked once inside the strip',
        (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      expect(find.byKey(const ValueKey('winner-trophy')), findsOneWidget);
      expect(find.text('Winner'), findsNothing);
    });

    testWidgets('a win the other way is marked just the same', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 0, teamBScore: 2));

      expect(find.byKey(const ValueKey('winner-trophy')), findsOneWidget);
      expect(find.text('Winner'), findsNothing);
    });

    testWidgets('a draw names nobody and picks out neither score',
        (tester) async {
      await pumpCard(tester, cardData(teamAScore: 2, teamBScore: 2));

      expect(find.text('Winner'), findsNothing);
      expect(find.byKey(const ValueKey('winner-trophy')), findsNothing);
    });

    testWidgets('a win carries exactly one trophy', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      expect(find.byKey(const ValueKey('winner-trophy')), findsOneWidget);
    });
  });

  group('it is the Teams screen, with the result on it', () {
    testWidgets('both sides are drawn on the pitch the Teams screen uses',
        (tester) async {
      await pumpCard(tester, cardData());

      // The same painter the lineup card and `PitchView` use. Two of them, one
      // per side, which is what makes this the Teams screen rather than a
      // second layout that happens to list the same players.
      // The Teams screen's own pitch, twice - one per side. That is what makes
      // this a picture of the screen rather than a second layout that happens
      // to list the same players.
      expect(find.byType(PitchView), findsNWidgets(2));
      expect(find.byType(MatchStageSection), findsNWidgets(2));
    });

    testWidgets('every player of both lineups is on it', (tester) async {
      await pumpCard(tester, cardData());

      for (final name in names.values) {
        expect(find.text(name), findsOneWidget, reason: '$name played');
      }
      // Each side keeps the screen's own heading without a player count. The
      // other occurrence is the score strip's team label.
      expect(find.text('Team A'), findsNWidgets(2));
      expect(find.text('Team B'), findsNWidgets(2));
      expect(find.text('Team A (2)'), findsNothing);
      expect(find.text('Team B (2)'), findsNothing);
    });

    testWidgets('a goalkeeper is drawn even when nobody keeps goal naturally',
        (tester) async {
      // The lineup card leaves keepers out in that case, because it pictures a
      // formation still to be played. This is the record of a match, and
      // everybody who was on the pitch belongs on the picture of it.
      await pumpCard(tester, cardData());

      expect(find.text(names['u1']!), findsOneWidget);
    });

    testWidgets('the players are drawn with the lineup marks', (tester) async {
      await pumpCard(tester, cardData());

      expect(find.byType(PlayerCard), findsNWidgets(4));
    });
  });

  group('what each player did', () {
    testWidgets('a scorer carries a ball and their count', (tester) async {
      await pumpCard(tester, cardData(goals: {'u3': 2}, mvp: null));

      expect(_goalBadges(), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('one ball for each scorer, and nobody else', (tester) async {
      await pumpCard(
        tester,
        cardData(goals: {'u3': 2, 'u1': 1, 'u2': 1}, mvp: null),
      );

      expect(_goalBadges(), findsNWidgets(3));
    });

    testWidgets('the best player carries a star', (tester) async {
      await pumpCard(tester, cardData(goals: const {}, mvp: 'u3'));

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('a scorer who was also best on the pitch carries both',
        (tester) async {
      await pumpCard(tester, cardData(goals: {'u3': 2}, mvp: 'u3'));

      // Both remain independently readable beside the same player's avatar.
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(_goalBadges(), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      final goal = tester.getRect(find.byKey(PitchView.goalKey('u3')));
      final mvp = tester.getRect(find.byKey(PitchView.mvpKey('u3')));
      expect(goal.overlaps(mvp), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a goalless match with nobody named carries no marks at all',
        (tester) async {
      await pumpCard(
        tester,
        cardData(teamAScore: 0, teamBScore: 0, goals: const {}, mvp: null),
      );

      expect(_goalBadges(), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      // No placeholder, no empty pill, and no overflow from room reserved for
      // badges nobody needed.
      expect(tester.takeException(), isNull);
    });

    test('the card knows whether it carries a result at all', () {
      expect(cardData().hasResult, isTrue);
      expect(cardData(teamAScore: null, teamBScore: null).hasResult, isFalse);
      // A tally of zero is not a mark. Nobody scoring nothing is the absence of
      // a tally, not a tally of none.
      expect(cardData(goals: {'u3': 0}).goalsOf('u3'), 0);
    });
  });

  group('what the card says at the top', () {
    testWidgets('the score, the community and the date', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      expect(_scoreNumerals(tester), ['3', '1']);
      final scoreTexts = tester.widgetList<Text>(find.descendant(
        of: find.byType(MatchStageHeader),
        matching: find.byType(Text),
      ));
      expect(
        scoreTexts
            .where((text) => int.tryParse(text.data ?? '') != null)
            .map((text) => text.style?.fontSize)
            .toSet(),
        {55 * MatchStage.canonicalXScale},
      );
      // Community, match and date share one compact line of context above the
      // score, so they are asserted as parts of it rather than as three
      // separate headings.
      expect(find.textContaining('Al Amerat FC'), findsOneWidget);
      expect(find.textContaining('August 21, 2026'), findsOneWidget);
      expect(find.text('Team A'), findsNWidgets(2));
      expect(find.text('Team B'), findsNWidgets(2));
    });

    testWidgets('it signs itself, once', (tester) async {
      await pumpCard(tester, cardData());

      const sx = 1080 / 941.0;
      const sy = 1920 / 1672.0;
      final footer = find.byKey(const ValueKey('share-footer'));
      expect(footer, findsOneWidget);
      expect(
        tester.getSize(footer),
        const Size(941 * sx, 134 * sy),
      );
      final logo = tester.getRect(
        find.byKey(const ValueKey('share-footer-logo')),
      );
      expect(logo.left, closeTo(319 * sx, .1));
      expect(logo.top, closeTo((1538 + 32) * sy, .1));
      expect(logo.width, closeTo(295 * sx, .1));
      expect(logo.height, closeTo(60 * sy, .1));
      expect(
        find.byKey(const ValueKey('share-footer-stripes-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('share-footer-stripes-right')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: footer,
          matching: find.byIcon(Icons.sports_soccer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('restores both subtle header footballs', (tester) async {
      await pumpCard(tester, cardData());

      expect(
        find.byKey(const ValueKey('share-header-ball-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('share-header-ball-right')),
        findsOneWidget,
      );
    });

    testWidgets('it holds together in Arabic', (tester) async {
      await pumpCard(tester, cardData(), locale: const Locale('ar'));

      expect(find.text('الفريق أ'), findsWidgets);
      expect(find.text('الفريق أ (2)'), findsNothing);
      expect(find.text('الفائز'), findsNothing);
      expect(find.byKey(const ValueKey('winner-trophy')), findsOneWidget);
      // The score keeps its own order whatever the paragraph does around it.
      expect(_scoreNumerals(tester), ['3', '1']);
      expect(tester.takeException(), isNull);
    });
  });

  group('the picture itself', () {
    testWidgets('result share uses its dedicated pitch and player metrics',
        (tester) async {
      await pumpCard(tester, cardData());

      final teamAPitch =
          tester.getSize(find.byKey(const ValueKey('team-a-pitch')));
      final teamBPitch =
          tester.getSize(find.byKey(const ValueKey('team-b-pitch')));
      expect(
          teamAPitch.width, closeTo(842.09 * MatchStage.canonicalXScale, .02));
      expect(
          teamAPitch.height, closeTo(502.90 * MatchStage.canonicalYScale, .02));
      expect(
          teamBPitch.width, closeTo(838.88 * MatchStage.canonicalXScale, .02));
      expect(
          teamBPitch.height, closeTo(502.90 * MatchStage.canonicalYScale, .02));

      final avatars = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('player-avatar-');
      });
      for (final avatar in avatars.evaluate()) {
        expect(
          tester.getSize(find.byWidget(avatar.widget)).width,
          anyOf(
            closeTo(50 * MatchStage.canonicalXScale, .02),
            closeTo(50 * 838.88 / 842.09 * MatchStage.canonicalXScale, .02),
          ),
        );
      }
    });

    testWidgets('before-result share keeps the approved pitch geometry',
        (tester) async {
      await pumpCard(
        tester,
        cardData(
          teamAScore: null,
          teamBScore: null,
          goals: const {},
          mvp: null,
        ),
      );

      final teamAPitch =
          tester.getSize(find.byKey(const ValueKey('team-a-pitch')));
      final teamBPitch =
          tester.getSize(find.byKey(const ValueKey('team-b-pitch')));
      expect(
          teamAPitch.width, closeTo(842.09 * MatchStage.canonicalXScale, .02));
      expect(
          teamAPitch.height, closeTo(502.90 * MatchStage.canonicalYScale, .02));
      expect(
          teamBPitch.width, closeTo(838.88 * MatchStage.canonicalXScale, .02));
      expect(
          teamBPitch.height, closeTo(502.90 * MatchStage.canonicalYScale, .02));

      final avatars = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('player-avatar-');
      });
      for (final avatar in avatars.evaluate()) {
        expect(
          tester.getSize(find.byWidget(avatar.widget)).width,
          anyOf(
            closeTo(50 * MatchStage.canonicalXScale, .02),
            closeTo(50 * 838.88 / 842.09 * MatchStage.canonicalXScale, .02),
          ),
        );
      }
    });

    testWidgets('composes at the format the engine promises', (tester) async {
      final key = GlobalKey();
      await pumpCard(tester, cardData(), boundaryKey: key);

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // Through `runAsync`: encoding a picture is real engine work, and the
      // test binding's fake async never lets it finish.
      final image = await tester.runAsync(() => captureShareCard(boundary));

      expect(image!.bytes, isNotEmpty);
      expect(image.pixelWidth, ShareCardCanvas.designSize.width.round());
      expect(image.pixelHeight, ShareCardCanvas.designSize.height.round());
      expect(image.isShareCardShape, isTrue);
      expect(image.mimeType, 'image/png');
    });

    testWidgets('a crowded lineup composes without overflowing',
        (tester) async {
      // The badges buy room under every name, and the densest lineup the
      // product supports is where that room is tightest.
      await pumpCard(tester, _crowded());

      expect(tester.takeException(), isNull);
    });

    test('a match with nobody in the lineup is not a card', () {
      expect(
        const MatchResultCardData(
          lineup: [],
          players: {},
          names: {},
        ).isShareable,
        isFalse,
      );
    });
  });

  group('sending it', () {
    testWidgets('the share sheet is what a card is handed to', (tester) async {
      final share = _FakeShareService();
      await _pumpPreview(tester, share: share);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(share.shared, hasLength(1));
      expect(share.shared.single.mimeType, 'image/png');
    });

    testWidgets('where there is no sheet, the reader is given the file',
        (tester) async {
      final share = _FailingShareService();
      final saved = <ShareCardImage>[];
      await _pumpPreview(
        tester,
        share: share,
        downloader: (image) async {
          saved.add(image);
          return true;
        },
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1), reason: 'the download is the fallback');
      expect(find.text('Image saved to your downloads.'), findsOneWidget);
      // The share failure is not reported on top of a download that worked.
      expect(find.text('Sharing is not available right now.'), findsNothing);
    });

    testWidgets('a platform with neither still reports the share failure',
        (tester) async {
      await _pumpPreview(
        tester,
        share: _FailingShareService(),
        downloader: (_) async => false,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('Sharing is not available right now.'), findsOneWidget);
    });
  });
  group('Match Details no longer presents the result', () {
    // The result, the winner, the scorers and the best player all moved to the
    // Teams screen, which is now the single surface for the lineup and what
    // became of it. Match Details is match information, the roster, and the way
    // to the screens that hold the rest.
    testWidgets(
        'a completed match shows no score, no scorers and no best player',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
        registrations: _roster(),
      );

      expect(find.text('Scorers'), findsNothing);
      expect(find.text('Best player'), findsNothing);
      expect(find.text('Winner'), findsNothing);
      // The score would have been the only bare numerals on the screen.
      expect(find.text('3'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('and offers no share action of its own', (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
        registrations: _roster(),
      );

      // One share control in the product, and it is the Teams screen's.
      expect(find.text('Share the result'), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
    });

    testWidgets('an organizer still reaches Result Entry from here',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.admin,
        registrations: _roster(),
      );

      // Removing the presentation must not remove the way in to recording one.
      expect(find.text('Match result'), findsOneWidget);
    });

    testWidgets('and everybody still reaches the Teams screen', (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
        registrations: _roster(),
      );

      expect(find.text('Teams'), findsOneWidget);
    });
  });
}

/// The two numerals of the scoreboard, in the order they are drawn.
///
/// Identified by the one size nothing else on the card is set at, which is what
/// makes the score the score rather than a goal tally that happens to read the
/// same.
List<String> _scoreNumerals(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(MatchStageHeader),
      matching: find.byType(Text),
    ))
    .where((text) =>
        text.style?.fontWeight == FontWeight.w700 &&
        int.tryParse(text.data ?? '') != null)
    .map((text) => text.data ?? '')
    .toList();

/// Goal badges, scoped to the pitch so the card's own football watermark is not
/// counted as somebody's goal.
Finder _goalBadges() => find.descendant(
      of: find.byType(PitchView),
      matching: find.byIcon(Icons.sports_soccer),
    );

/// A one-pixel PNG. The preview decodes whatever it is handed, so the bytes
/// have to be a real picture even though nothing looks at it.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// A lineup dense enough to squeeze the badges: five a side, which is where the
/// solver has least room under each name.
MatchResultCardData _crowded() {
  final players = <TeamAssignment>[
    for (final (index, position) in [
      Position.gk,
      Position.def,
      Position.def,
      Position.mid,
      Position.fwd,
    ].indexed) ...[
      TeamAssignment(
        userId: 'a$index',
        team: TeamId.a,
        assignedPosition: position,
        basis: AssignmentBasis.primary,
      ),
      TeamAssignment(
        userId: 'b$index',
        team: TeamId.b,
        assignedPosition: position,
        basis: AssignmentBasis.primary,
      ),
    ],
  ];

  return MatchResultCardData(
    teamAScore: 4,
    teamBScore: 3,
    lineup: players,
    players: {
      for (final player in players)
        player.participantId: PlayerCoreInputs(
          userId: player.userId!,
          fullName: 'عبدالرحمن',
          overallRating: 6,
          primaryPosition: player.assignedPosition!,
        ),
    },
    names: {
      // Deliberately long, and Arabic: the widest name is what decides whether
      // a card buys a second line, and a second line is what the badges then
      // have to fit under.
      for (final player in players)
        player.participantId: 'عبدالرحمن بن سليمان الحارثي',
    },
    goals: {for (final player in players) player.participantId: 1},
    mvpParticipantId: players.first.participantId,
    communityName: 'Al Amerat FC',
    playedAt: DateTime(2026, 8, 21, 20),
  );
}

Match _playedMatch() {
  final start = DateTime.now().subtract(const Duration(days: 3));
  return Match(
    id: 'm1',
    communityId: 'c1',
    createdBy: 'u9',
    location: 'Al Amerat Pitch',
    startAt: start,
    endAt: start.add(const Duration(hours: 2)),
    startingPlayers: 4,
    maxRegistration: 10,
    status: MatchStatus.completed,
    title: 'Last Friday',
    communityName: 'Al Amerat FC',
  );
}

List<MatchRegistration> _roster() => const [
      MatchRegistration(
        registrationId: 'r1',
        userId: 'u1',
        fullName: 'Sara Al Balushi',
        status: RegistrationStatus.confirmed,
        registrationOrder: 1,
      ),
      MatchRegistration(
        registrationId: 'r2',
        userId: 'u2',
        fullName: 'Ahmed Al Harthy',
        status: RegistrationStatus.confirmed,
        registrationOrder: 2,
      ),
      MatchRegistration(
        registrationId: 'r3',
        userId: 'u3',
        fullName: 'Noor Al Kindi',
        status: RegistrationStatus.confirmed,
        registrationOrder: 3,
      ),
      MatchRegistration(
        registrationId: 'r4',
        userId: 'u4',
        fullName: 'Yousef Al Amri',
        status: RegistrationStatus.confirmed,
        registrationOrder: 4,
      ),
    ];

Future<void> _pumpPreview(
  WidgetTester tester, {
  required ShareService share,
  ShareCardDownloader? downloader,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: ShareCardPreviewScreen(
      image: ShareCardImage(
        bytes: _png,
        pixelWidth: 1080,
        pixelHeight: 1920,
      ),
      shareService: share,
      downloader: downloader,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required Match match,
  CommunityRole? role,
  List<MatchRegistration> registrations = const [],
}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: MatchDetailsScreen(
      matchId: match.id,
      matchService: MatchService(
        _MatchAdapter(match: match, registrations: registrations),
      ),
      memberRepository: MemberRepository(_MemberAdapter(role)),
      communityRepository: CommunityRepository(_CommunityAdapter()),
      authService: AuthService(_AuthAdapter()),
    ),
  ));
  await tester.pumpAndSettle();
}

class _FakeShareService implements ShareService {
  final List<ShareCardImage> shared = [];

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    shared.add(image);
    return ShareOutcome.shared;
  }
}

/// A platform that cannot show a sheet at all — a desktop browser, which is the
/// one the download exists for.
class _FailingShareService implements ShareService {
  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async =>
      throw const InfrastructureFailure();
}

class _MatchAdapter implements MatchAdapter {
  _MatchAdapter({required this.match, required this.registrations});

  final Match match;
  final List<MatchRegistration> registrations;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other match data is read here');
}

class _MemberAdapter implements MemberAdapter {
  _MemberAdapter(this.role);

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other member data is read here');
}

class _CommunityAdapter implements CommunityAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no community data is read here');
}

class _AuthAdapter implements AuthAdapter {
  @override
  String? get currentUserId => 'u1';

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other auth data is read here');
}
