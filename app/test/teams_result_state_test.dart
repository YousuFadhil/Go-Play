import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/results/match_result_card.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/teams/match_stage.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/features/teams/teams_screen.dart';

/// The Teams screen, before and after a result exists.
///
/// **One screen, two states, and the result is the only thing that decides
/// which.** Before a result, this is the lineup it has always been. After one,
/// the same screen carries a compact summary above the pitches and a mark on
/// each player who did something — and the one Share button in the header sends
/// whichever of the two the reader is looking at, without being asked.
///
/// Neither the pitch nor the Share Card Engine is retested here; both have their
/// own suites. What is asserted is the switch.
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

  PlayerCoreInputs player(String id, Position primary) => PlayerCoreInputs(
        userId: id,
        fullName: names[id]!,
        overallRating: 6,
        primaryPosition: primary,
      );

  List<PlayerCoreInputs> roster() => [
        player('u1', Position.gk),
        player('u3', Position.mid),
        player('u2', Position.def),
        player('u4', Position.fwd),
      ];

  Match playedMatch() {
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

  Match upcomingMatch() {
    final start = DateTime.now().add(const Duration(days: 2));
    return Match(
      id: 'm1',
      communityId: 'c1',
      createdBy: 'u9',
      location: 'Al Amerat Pitch',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      startingPlayers: 4,
      maxRegistration: 10,
      status: MatchStatus.open,
      title: 'Friday Night',
      communityName: 'Al Amerat FC',
    );
  }

  MatchResult result({
    int a = 3,
    int b = 1,
    String? mvp = 'u3',
    List<GoalTally> goals = const [
      GoalTally(userId: 'u3', goals: 2),
      GoalTally(userId: 'u1', goals: 1),
      GoalTally(userId: 'u2', goals: 1),
    ],
  }) =>
      MatchResult(
        matchId: 'm1',
        teamAScore: a,
        teamBScore: b,
        mvpUserId: mvp,
        goals: goals,
      );

  Future<void> pumpTeams(
    WidgetTester tester, {
    required Match match,
    MatchResult? recorded,
    CommunityRole? role = CommunityRole.player,
    Locale locale = const Locale('en'),
    _Renderer? renderer,
    _Share? share,
    Size physicalSize = const Size(390, 1800),
    List<TeamAssignment>? assignments,
    List<PlayerCoreInputs>? players,
    GlobalKey? boundaryKey,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: RepaintBoundary(
        key: boundaryKey,
        child: TeamsScreen(
          matchId: 'm1',
          matchService: MatchService(_Matches(match)),
          memberRepository: MemberRepository(_Members(role)),
          teamRepository: TeamRepository(
            _Teams(assignments ?? lineup(), players ?? roster()),
          ),
          resultRepository: ResultRepository(_Results(recorded)),
          renderer: renderer,
          shareService: share,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('Gate 3 - REF05 and REF06 live Teams screen', () {
    final visualLineup = <TeamAssignment>[
      for (final team in [TeamId.a, TeamId.b]) ...[
        assignment('${team.name}-gk', team, Position.gk),
        for (var index = 0; index < 3; index++)
          assignment('${team.name}-d$index', team, Position.def),
        for (var index = 0; index < 3; index++)
          assignment('${team.name}-m$index', team, Position.mid),
      ],
    ];
    final visualPlayers = <PlayerCoreInputs>[
      for (final item in visualLineup)
        PlayerCoreInputs(
          userId: item.userId!,
          fullName: item.participantId,
          overallRating: 5.3,
          primaryPosition: item.assignedPosition!,
        ),
    ];
    final visualMatch = Match(
      id: 'm1',
      communityId: 'c1',
      createdBy: 'u9',
      location: 'الشمال',
      startAt: DateTime(2026, 8, 29, 20),
      endAt: DateTime(2026, 8, 29, 22),
      startingPlayers: 14,
      maxRegistration: 14,
      status: MatchStatus.completed,
      title: 'تمرين السبت',
      communityName: 'الشمال',
    );

    Future<void> captureScreen(
      WidgetTester tester,
      GlobalKey boundaryKey,
      String filename,
    ) async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/visual-verification-v2');
        await directory.create(recursive: true);
        await File('${directory.path}/$filename')
            .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      });
    }

    void expectSourceRect(WidgetTester tester, Finder finder, Rect expected) {
      final actual = tester.getRect(finder);
      expect(actual.left, closeTo(expected.left, .15));
      expect(actual.top, closeTo(expected.top, .15));
      expect(actual.width, closeTo(expected.width, .15));
      expect(actual.height, closeTo(expected.height, .15));
    }

    /// What the phone stage is now measured against, in place of the source
    /// raster it used to be measured against.
    ///
    /// The screen and the share card were one drawing at two sizes, and the
    /// approved refresh separates them: the phone gets a margin a thumb can
    /// see, a deeper pitch, and no dark card between the ground and the grass.
    /// So the rectangles below are the phone's own, in phone points, and the
    /// raster ones live on in `match_result_share_card_test.dart` where they
    /// still describe what is actually drawn.
    void expectPhoneStage(WidgetTester tester, {required bool hasResult}) {
      const margin = MatchStage.phoneMargin;
      const width = 390.0;
      const pitchWidth = width - 2 * margin;

      for (final key in const ['team-a-section', 'team-b-section']) {
        final section = tester.getRect(find.byKey(ValueKey(key)));
        expect(section.left, closeTo(margin, .15), reason: key);
        expect(section.width, closeTo(pitchWidth, .15), reason: key);
      }

      // Both sides get the whole width now. They used to differ by three
      // points, which was two slightly different traces of one drawing and
      // never a fact about either team.
      for (final key in const ['team-a-pitch', 'team-b-pitch']) {
        final pitch = tester.getRect(find.byKey(ValueKey(key)));
        expect(pitch.left, closeTo(margin, .15), reason: key);
        expect(pitch.width, closeTo(pitchWidth, .15), reason: key);
        expect(
          pitch.width / pitch.height,
          closeTo(MatchStage.phonePitchAspect, .001),
          reason: key,
        );
        // The approved band, with a hair of tolerance for the division.
        expect(pitch.width / pitch.height, inInclusiveRange(1.379, 1.451),
            reason: key);
      }

      // The pitch is the surface, not a panel on it: each side gives its own
      // pitch more than four fifths of its height.
      for (final side in const [
        ('team-a-section', 'team-a-pitch'),
        ('team-b-section', 'team-b-pitch'),
      ]) {
        final section = tester.getRect(find.byKey(ValueKey(side.$1)));
        final pitch = tester.getRect(find.byKey(ValueKey(side.$2)));
        expect(pitch.height / section.height, greaterThan(.82),
            reason: side.$1);
      }

      final strip = find.byKey(const ValueKey('result-strip'));
      if (hasResult) {
        final rect = tester.getRect(strip);
        expect(rect.left, closeTo(margin, .15));
        expect(rect.width, closeTo(pitchWidth, .15));
        expect(rect.height, inInclusiveRange(60, 64));
      } else {
        expect(strip, findsNothing);
      }
    }

    testWidgets('the result state is the approved phone stage', (tester) async {
      final boundaryKey = GlobalKey();
      await pumpTeams(
        tester,
        match: visualMatch,
        recorded: result(a: 7, b: 4),
        locale: const Locale('ar'),
        assignments: visualLineup,
        players: visualPlayers,
        boundaryKey: boundaryKey,
      );

      expectSourceRect(tester, find.byKey(const ValueKey('teams-app-bar')),
          const Rect.fromLTWH(0, 0, 390, 82 * 390 / MatchStage.referenceWidth));
      expectPhoneStage(tester, hasResult: true);
      expect(find.byKey(const ValueKey('share-footer')), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await captureScreen(tester, boundaryKey, 'teams_result_saved.png');
    });

    testWidgets('and so is the before-result state', (tester) async {
      final boundaryKey = GlobalKey();
      await pumpTeams(
        tester,
        match: visualMatch,
        locale: const Locale('ar'),
        assignments: visualLineup,
        players: visualPlayers,
        boundaryKey: boundaryKey,
      );

      expectSourceRect(tester, find.byKey(const ValueKey('teams-app-bar')),
          const Rect.fromLTWH(0, 0, 390, 82 * 390 / MatchStage.referenceWidth));
      expectPhoneStage(tester, hasResult: false);
      expect(find.byKey(const ValueKey('share-footer')), findsNothing);
      expect(_goalBadges(), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await captureScreen(tester, boundaryKey, 'teams_before_result.png');
    });
  });

  group('state A — no result yet', () {
    testWidgets('both lineups are drawn as they always were', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      expect(find.text('Team A (2)'), findsNothing);
      expect(find.text('Team B (2)'), findsNothing);
      expect(find.byType(PitchView), findsNWidgets(2));
      final teamAPitch =
          tester.getSize(find.byKey(const ValueKey('team-a-pitch')));
      final teamBPitch =
          tester.getSize(find.byKey(const ValueKey('team-b-pitch')));
      // One depth, both sides, and it is the phone's own rather than the share
      // raster's.
      expect(teamAPitch.width / teamAPitch.height,
          closeTo(MatchStage.phonePitchAspect, .001));
      expect(teamBPitch.width / teamBPitch.height,
          closeTo(MatchStage.phonePitchAspect, .001));
      expect(teamAPitch.width, teamBPitch.width);
      for (final name in names.values) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('the phone stage spends the screen on the pitch',
        (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      const scale = 390 / MatchStage.referenceWidth;
      const content = 390 - 2 * MatchStage.phoneMargin;
      // The bar is still drawn from the raster; it is not part of this
      // refresh and is asserted so that it is seen not to have moved.
      expect(
          tester.getSize(find.byType(AppBar)).height, closeTo(82 * scale, .01));

      for (final section in find.byType(MatchStageSection).evaluate()) {
        expect(tester.getSize(find.byWidget(section.widget)).width,
            closeTo(content, .01));
      }
      final teamAPitch =
          tester.getSize(find.byKey(const ValueKey('team-a-pitch')));
      final teamBPitch =
          tester.getSize(find.byKey(const ValueKey('team-b-pitch')));
      for (final pitch in [teamAPitch, teamBPitch]) {
        expect(pitch.width, closeTo(content, .01));
        expect(
            pitch.height, closeTo(content / MatchStage.phonePitchAspect, .01));
      }
      // Wider and deeper than the raster geometry it replaces, which is the
      // whole of what this change was for.
      expect(teamAPitch.width, greaterThan(842.09 * scale));
      expect(teamAPitch.height, greaterThan(502.90 * scale));
    });

    testWidgets('no summary, no winner, no marks', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.text('Winner'), findsNothing);
      expect(_goalBadges(), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('a completed match nobody has recorded is still state A',
        (tester) async {
      // The match being over is not the switch. A recorded result is.
      await pumpTeams(tester, match: playedMatch());

      expect(_goalBadges(), findsNothing);
      expect(find.text('Winner'), findsNothing);
    });

    testWidgets('the one Share action is in the header', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      // And nowhere else: no bottom call to action anywhere on the screen.
      expect(find.text('Share the lineup'), findsNothing);
    });

    testWidgets('the app-bar controls use a high-contrast foreground',
        (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.foregroundColor, Colors.white);
      expect(appBar.iconTheme?.color, Colors.white);
      expect(appBar.actionsIconTheme?.color, Colors.white);
    });

    testWidgets('and it sends the lineup card', (tester) async {
      final renderer = _Renderer();
      await pumpTeams(
        tester,
        match: upcomingMatch(),
        renderer: renderer,
        share: _Share(),
      );

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      // One card, in both states - so what is asserted is not which class was
      // built but what it was built with: a picture of a lineup that has no
      // result carries no score.
      expect(renderer.templates, hasLength(1));
      expect(renderer.lastBuilt, isA<MatchResultCard>());
      expect((renderer.lastBuilt! as MatchResultCard).data.hasResult, isFalse);
    });
  });

  group('state B — a result exists', () {
    testWidgets('a compact summary appears above the teams', (tester) async {
      await pumpTeams(tester, match: playedMatch(), recorded: result());

      // Team A, the score, Team B, in one capsule of the approved height —
      // and the capsule is the only thing the result adds to the header.
      final strip = tester.getSize(find.byKey(const ValueKey('result-strip')));
      expect(strip.height, inInclusiveRange(60, 64));
      expect(find.textContaining('Al Amerat FC'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('the winning side is marked in green, and not with a trophy',
        (tester) async {
      await pumpTeams(tester, match: playedMatch(), recorded: result());

      // The trophy was a third thing to read in a strip whose whole job is to
      // be read at a glance. On the phone the winner is said in accent green
      // and the loser in plain ink; the share card keeps its trophy, and keeps
      // it in `match_result_share_card_test.dart`.
      expect(find.byKey(const ValueKey('winner-trophy')), findsNothing);
      expect(find.text('Winner'), findsNothing);
      expect(_stripLabelColour(tester, 'Team A'), MatchStage.accent);
      expect(_stripLabelColour(tester, 'Team B'), MatchStage.ink);
    });

    testWidgets('a right-to-left reading never swaps the two scores',
        (tester) async {
      // The one thing about this strip that is not a matter of taste. Each
      // numeral has to stay against its own team's name whichever end of the
      // row a reader starts from, so the pairing is asserted by position:
      // Team A and its 3 on one side of the pod, Team B and its 1 on the other.
      for (final locale in const [Locale('en'), Locale('ar')]) {
        await pumpTeams(
          tester,
          match: playedMatch(),
          recorded: result(a: 3, b: 1),
          locale: locale,
        );

        final strip = find.byKey(const ValueKey('result-strip'));
        final labelA = tester.getCenter(
          find.descendant(of: strip, matching: find.text(l10nTeamA(locale))),
        );
        final labelB = tester.getCenter(
          find.descendant(of: strip, matching: find.text(l10nTeamB(locale))),
        );
        final three = tester.getCenter(
          find.descendant(of: strip, matching: find.text('3')),
        );
        final one = tester.getCenter(
          find.descendant(of: strip, matching: find.text('1')),
        );

        // Team A's score sits on Team A's side of the strip, and Team B's on
        // Team B's — in either direction.
        expect((three.dx - labelA.dx).abs(),
            lessThan((three.dx - labelB.dx).abs()),
            reason: '$locale: 3 belongs to Team A');
        expect((one.dx - labelB.dx).abs(), lessThan((one.dx - labelA.dx).abs()),
            reason: '$locale: 1 belongs to Team B');
        // And the winner is still the side that scored three.
        expect(_stripLabelColour(tester, l10nTeamA(locale)), MatchStage.accent,
            reason: '$locale');
      }
    });

    testWidgets('and so is the other one when it wins', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(a: 0, b: 2, goals: const []),
      );

      expect(_stripLabelColour(tester, 'Team B'), MatchStage.accent);
      expect(_stripLabelColour(tester, 'Team A'), MatchStage.ink);
      expect(find.text('Winner'), findsNothing);
    });

    testWidgets('a draw names nobody', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(a: 2, b: 2, goals: const []),
      );

      expect(find.text('Winner'), findsNothing);
      expect(find.byKey(const ValueKey('winner-trophy')), findsNothing);
      // Neither side is marked, rather than both being marked faintly.
      expect(_stripLabelColour(tester, 'Team A'), MatchStage.ink);
      expect(_stripLabelColour(tester, 'Team B'), MatchStage.ink);
    });

    testWidgets('a scorer carries a ball and their count', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(
          mvp: null,
          goals: const [GoalTally(userId: 'u3', goals: 2)],
        ),
      );

      expect(_goalBadges(), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('and nobody else does — a zero is not a badge', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(
          mvp: null,
          goals: const [GoalTally(userId: 'u3', goals: 2)],
        ),
      );

      // Four players on the pitch, one ball between them.
      expect(_goalBadges(), findsOneWidget);
    });

    testWidgets('the best player carries a star', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(mvp: 'u3', goals: const []),
      );

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('a scorer who was also best on the pitch carries both',
        (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(
          mvp: 'u3',
          goals: const [GoalTally(userId: 'u3', goals: 2)],
        ),
      );

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(_goalBadges(), findsOneWidget);
      final goal = tester.getRect(find.byKey(PitchView.goalKey('u3')));
      final mvp = tester.getRect(find.byKey(PitchView.mvpKey('u3')));
      final name = tester.getRect(find.byKey(PitchView.nameKey('u3')));
      expect(goal.bottom, lessThan(name.top));
      expect(mvp.bottom, lessThan(name.top));
      expect(goal.overlaps(mvp), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lineups are still the subject of the screen',
        (tester) async {
      await pumpTeams(tester, match: playedMatch(), recorded: result());

      expect(find.byType(PitchView), findsNWidgets(2));
      for (final name in names.values) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('the same header button now sends the result card',
        (tester) async {
      final renderer = _Renderer();
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(),
        renderer: renderer,
        share: _Share(),
      );

      // Still one button, in the same place, and the reader chose nothing.
      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(renderer.lastBuilt, isA<MatchResultCard>());
      final data = (renderer.lastBuilt! as MatchResultCard).data;
      expect(data.hasResult, isTrue);
      expect(data.winner, TeamId.a);
      expect(data.goalsOf('u3'), 2);
      expect(data.isMvp('u3'), isTrue);
    });

    testWidgets('an ordinary member gets the action too', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(),
        role: CommunityRole.player,
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.ios_share),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      // And still cannot edit anything: generation is the organizer's.
      expect(find.text('Generate teams'), findsNothing);
    });
  });
}

/// Goal badges, scoped to the pitch so the screen's own football watermark is
/// not counted as somebody's goal.
Finder _goalBadges() => find.descendant(
      of: find.byType(PitchView),
      matching: find.byIcon(Icons.sports_soccer),
    );

/// The colour one side's name is written in inside the result strip.
///
/// Which side won is said in that colour and nowhere else on the phone, so this
/// is how the winner is read back — scoped to the strip, because the same two
/// words also head each team's own section.
Color? _stripLabelColour(WidgetTester tester, String label) => tester
    .widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('result-strip')),
      matching: find.text(label),
    ))
    .style
    ?.color;

String l10nTeamA(Locale locale) =>
    locale.languageCode == 'ar' ? 'الفريق أ' : 'Team A';

String l10nTeamB(Locale locale) =>
    locale.languageCode == 'ar' ? 'الفريق ب' : 'Team B';

class _Matches implements MatchAdapter {
  _Matches(this.match);

  final Match match;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other match data is read here');
}

class _Members implements MemberAdapter {
  _Members(this.role);

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other member data is read here');
}

class _Teams implements TeamAdapter {
  _Teams(this.lineup, this.roster);

  final List<TeamAssignment> lineup;
  final List<PlayerCoreInputs> roster;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
    String matchId,
  ) async =>
      roster;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other team data is read here');
}

class _Results implements ResultAdapter {
  _Results(this.result);

  final MatchResult? result;

  @override
  Future<MatchResult?> fetchResult(String matchId) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other result data is read here');
}

/// Captures which template the screen handed the engine, which is the whole of
/// what "the same button adapts" means.
class _Renderer implements ShareCardRenderer {
  final List<ShareCardTemplate> templates = [];
  Widget? lastBuilt;

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    templates.add(template);
    lastBuilt = template(_StubContext());
    return ShareCardImage(
      bytes: _png,
      pixelWidth: 1080,
      pixelHeight: 1920,
    );
  }
}

/// The template is a function of a context it does not read until it builds, so
/// calling it with a stub is enough to learn which widget it makes.
class _StubContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Share implements ShareService {
  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async =>
      ShareOutcome.shared;
}

/// A one-pixel PNG. The preview screen decodes whatever it is handed, so the
/// bytes have to be a real picture even though nothing here looks at it.
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
