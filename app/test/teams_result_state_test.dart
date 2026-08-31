import 'dart:typed_data' show Uint8List;

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
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
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_lineup_card.dart';
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
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: TeamsScreen(
        matchId: 'm1',
        matchService: MatchService(_Matches(match)),
        memberRepository: MemberRepository(_Members(role)),
        teamRepository: TeamRepository(_Teams(lineup(), roster())),
        resultRepository: ResultRepository(_Results(recorded)),
        renderer: renderer,
        shareService: share,
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('state A — no result yet', () {
    testWidgets('both lineups are drawn as they always were', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.text('Team A (2)'), findsOneWidget);
      expect(find.text('Team B (2)'), findsOneWidget);
      expect(find.byType(PitchView), findsNWidgets(2));
      for (final name in names.values) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('no summary, no winner, no marks', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.text('Winner'), findsNothing);
      expect(find.byIcon(Icons.sports_soccer), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('a completed match nobody has recorded is still state A',
        (tester) async {
      // The match being over is not the switch. A recorded result is.
      await pumpTeams(tester, match: playedMatch());

      expect(find.byIcon(Icons.sports_soccer), findsNothing);
      expect(find.text('Winner'), findsNothing);
    });

    testWidgets('the one Share action is in the header', (tester) async {
      await pumpTeams(tester, match: upcomingMatch());

      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      // And nowhere else: no bottom call to action anywhere on the screen.
      expect(find.text('Share the lineup'), findsNothing);
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

      expect(renderer.templates, hasLength(1));
      expect(renderer.lastBuilt, isA<TeamLineupCard>());
    });
  });

  group('state B — a result exists', () {
    testWidgets('a compact summary appears above the teams', (tester) async {
      await pumpTeams(tester, match: playedMatch(), recorded: result());

      expect(find.textContaining('Al Amerat FC'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('the winning side is named, once', (tester) async {
      await pumpTeams(tester, match: playedMatch(), recorded: result());

      expect(find.text('Winner'), findsOneWidget);
    });

    testWidgets('and so is the other one when it wins', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(a: 0, b: 2, goals: const []),
      );

      expect(find.text('Winner'), findsOneWidget);
    });

    testWidgets('a draw names nobody', (tester) async {
      await pumpTeams(
        tester,
        match: playedMatch(),
        recorded: result(a: 2, b: 2, goals: const []),
      );

      expect(find.text('Winner'), findsNothing);
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

      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
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
      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
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
      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
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
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
