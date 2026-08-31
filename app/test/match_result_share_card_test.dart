import 'dart:typed_data';
import 'dart:ui' show Rect;

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
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';

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
    int teamAScore = 3,
    int teamBScore = 1,
    Map<String, int> goals = const {'u3': 2, 'u1': 1, 'u2': 1},
    String? mvp = 'u3',
    List<TeamAssignment>? assignments,
  }) {
    final players = assignments ?? lineup();
    return MatchResultCardData(
      teamAScore: teamAScore,
      teamBScore: teamBScore,
      lineup: players,
      names: {
        for (final a in players) a.participantId: names[a.participantId] ?? '—',
      },
      goals: goals,
      mvpParticipantId: mvp,
      communityName: 'Al Amerat FC',
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

    testWidgets('the winning side is the one that is filled', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      // The fill is the whole of the emphasis, so it is counted rather than
      // described: exactly one of the two panels carries it.
      expect(_filledPanels(tester), 1);
    });

    testWidgets('a draw fills neither, so neither reads as the winner',
        (tester) async {
      await pumpCard(tester, cardData(teamAScore: 2, teamBScore: 2));

      expect(_filledPanels(tester), 0);
    });

    testWidgets('a win the other way still fills exactly one', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 0, teamBScore: 2));

      expect(_filledPanels(tester), 1);
    });
  });

  group('what the card says', () {
    testWidgets('the score is on it, and so is the community and the date',
        (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      // The scoreboard's own numerals, not every digit on the card: a goal
      // tally of one is also the text "1", and the score is the thing being
      // asserted here.
      expect(_scoreNumerals(tester), ['3', '1']);
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('August 21, 2026'), findsOneWidget);
    });

    testWidgets('every player of both lineups is drawn', (tester) async {
      await pumpCard(tester, cardData());

      for (final name in names.values) {
        expect(find.text(name), findsWidgets, reason: '$name played');
      }
      // Each side is headed with its own count, so a missing player is visible
      // as well as absent.
      expect(find.text('Team A (2)'), findsOneWidget);
      expect(find.text('Team B (2)'), findsOneWidget);
    });

    testWidgets('a scorer carries their goal count', (tester) async {
      await pumpCard(tester, cardData(goals: {'u3': 2, 'u1': 1, 'u2': 1}));

      // Noor scored two and appears twice — once in her own lineup row and once
      // in the scorer run — so the tally is asserted through the data as well as
      // on screen.
      expect(find.text('2'), findsWidgets);
      expect(find.text('Scorers'), findsOneWidget);
    });

    test('scorers come back most goals first, and are named', () {
      final rows = cardData(goals: {'u1': 1, 'u3': 2, 'u2': 1}).scorers;

      expect(rows.map((r) => r.name).toList(), [
        'Noor Al Kindi', // 2
        'Ahmed Al Harthy', // 1, alphabetically before Sara
        'Sara Al Balushi', // 1
      ]);
      expect(rows.first.goals, 2);
    });

    test('somebody who did not play is not a scorer of this match', () {
      // A tally naming a participant absent from the lineup is dropped rather
      // than drawn against a name the card cannot resolve.
      final rows = cardData(goals: {'u3': 2, 'nobody': 4}).scorers;

      expect(rows.map((r) => r.participantId), isNot(contains('nobody')));
    });

    testWidgets('the best player is named where there is one', (tester) async {
      await pumpCard(tester, cardData(mvp: 'u3'));

      expect(find.text('Best player'), findsOneWidget);
      expect(find.text('Noor Al Kindi'), findsWidgets);
    });

    testWidgets('and the line is simply absent where there is not',
        (tester) async {
      await pumpCard(tester, cardData(mvp: null));

      expect(find.text('Best player'), findsNothing);
      // No placeholder, no dash standing in for a name nobody gave.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a goalless draw draws no scorer run at all', (tester) async {
      await pumpCard(
        tester,
        cardData(teamAScore: 0, teamBScore: 0, goals: const {}, mvp: null),
      );

      expect(find.text('Scorers'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it signs itself, once', (tester) async {
      await pumpCard(tester, cardData());

      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('it holds together in Arabic', (tester) async {
      await pumpCard(tester, cardData(), locale: const Locale('ar'));

      expect(find.text('الفريق أ (2)'), findsOneWidget);
      expect(find.text('الهدّافون'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the picture itself', () {
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

    test('a match with nobody in the lineup is not a card', () {
      expect(
        MatchResultCardData(
          teamAScore: 0,
          teamBScore: 0,
          lineup: const [],
          names: const {},
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

  group('who is offered the action', () {
    testWidgets('an ordinary member of a played match can send the card',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
        result: _recorded(),
        lineup: lineup(),
      );

      expect(find.text('Share the result'), findsOneWidget);
      // And still cannot record one: that row is the organizer's.
      expect(find.text('Match result'), findsNothing);
    });

    testWidgets('so can an organizer, who also keeps the way to edit it',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.admin,
        result: _recorded(),
        lineup: lineup(),
      );

      expect(find.text('Share the result'), findsOneWidget);
      expect(find.text('Match result'), findsWidgets);
    });

    testWidgets('a match still to come offers no completed-match card',
        (tester) async {
      final start = DateTime.now().add(const Duration(days: 2));
      await _pumpDetails(
        tester,
        match: Match(
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
        ),
        role: CommunityRole.player,
      );

      expect(find.text('Share the result'), findsNothing);
    });

    testWidgets('a played match with nothing recorded says so and offers no card',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
      );

      expect(
        find.text('No result has been recorded for this match yet.'),
        findsOneWidget,
      );
      expect(find.text('Share the result'), findsNothing);
    });

    testWidgets('the summary shows the score, the scorers and the best player',
        (tester) async {
      await _pumpDetails(
        tester,
        match: _playedMatch(),
        role: CommunityRole.player,
        result: _recorded(),
        lineup: lineup(),
        registrations: _roster(),
      );

      expect(find.text('3'), findsWidgets);
      expect(find.text('1'), findsWidgets);
      expect(find.text('Scorers'), findsOneWidget);
      expect(find.text('Best player'), findsOneWidget);
      expect(find.textContaining('Noor Al Kindi'), findsWidgets);
    });
  });
}

/// The two numerals of the scoreboard, in the order they are drawn.
///
/// Identified by the one size nothing else on the card is set at, which is what
/// makes the score the score rather than any other digit.
List<String> _scoreNumerals(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((text) => text.style?.fontSize == 132)
    .map((text) => text.data ?? '')
    .toList();

/// A one-pixel PNG. The preview decodes whatever it is handed, so the bytes
/// have to be a real picture even though nothing looks at it.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// How many of the card's two score panels carry the winner's fill.
int _filledPanels(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .where((box) {
      final decoration = box.decoration;
      return decoration is BoxDecoration &&
          decoration.color == const Color(0xFF123D24);
    })
    .length;

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

MatchResult _recorded() => const MatchResult(
      matchId: 'm1',
      teamAScore: 3,
      teamBScore: 1,
      mvpUserId: 'u3',
      goals: [
        GoalTally(userId: 'u3', goals: 2),
        GoalTally(userId: 'u1', goals: 1),
        GoalTally(userId: 'u2', goals: 1),
      ],
    );

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
  MatchResult? result,
  List<TeamAssignment> lineup = const [],
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
      resultRepository: ResultRepository(_ResultAdapter(result)),
      teamRepository: TeamRepository(_TeamAdapter(lineup)),
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

class _ResultAdapter implements ResultAdapter {
  _ResultAdapter(this.result);

  final MatchResult? result;

  @override
  Future<MatchResult?> fetchResult(String matchId) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other result data is read here');
}

class _TeamAdapter implements TeamAdapter {
  _TeamAdapter(this.lineup);

  final List<TeamAssignment> lineup;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other team data is read here');
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
