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

    testWidgets('the winning side is named, once', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      // One tag, beside one heading. The score above has already said who won;
      // this names it for a reader scanning the two sides, and saying it twice
      // would be saying it worse.
      expect(find.text('Winner'), findsOneWidget);
    });

    testWidgets('a win the other way is named just the same', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 0, teamBScore: 2));

      expect(find.text('Winner'), findsOneWidget);
    });

    testWidgets('a draw names nobody and picks out neither score',
        (tester) async {
      await pumpCard(tester, cardData(teamAScore: 2, teamBScore: 2));

      expect(find.text('Winner'), findsNothing);
      // Neither numeral is in the winner's green: on a level score the two are
      // drawn identically, so the card cannot be misread at a glance as a
      // narrow win for whichever side happens to be drawn first.
      expect(_emphasisedNumerals(tester), 0);
    });

    testWidgets('a win picks out exactly one numeral', (tester) async {
      await pumpCard(tester, cardData(teamAScore: 3, teamBScore: 1));

      expect(_emphasisedNumerals(tester), 1);
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

      // Both, on one player, in one pill: star, ball, 2.
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(_goalBadges(), findsOneWidget);
      expect(find.text('2'), findsWidgets);
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
        {58.0},
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

      expect(find.text('GO PLAY'), findsOneWidget);
    });

    testWidgets('it holds together in Arabic', (tester) async {
      await pumpCard(tester, cardData(), locale: const Locale('ar'));

      expect(find.text('الفريق أ'), findsWidgets);
      expect(find.text('الفريق أ (2)'), findsNothing);
      expect(find.text('الفائز'), findsOneWidget);
      // The score keeps its own order whatever the paragraph does around it.
      expect(_scoreNumerals(tester), ['3', '1']);
      expect(tester.takeException(), isNull);
    });
  });

  group('the picture itself', () {
    testWidgets('result share uses its dedicated pitch and player metrics',
        (tester) async {
      await pumpCard(tester, cardData());

      final pitchFinders = find.byKey(const ValueKey('match-pitch'));
      expect(pitchFinders, findsNWidgets(2));
      for (final element in pitchFinders.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, closeTo(MatchResultCard.sharePitchWidth, 0.01));
        expect(
          size.height,
          closeTo(MatchResultCard.shareResultPitchHeight, 0.01),
        );
        expect(
          size.width / size.height,
          closeTo(PitchView.shareResultAspectRatio, 0.001),
        );
      }

      for (final avatar
          in find.byKey(const ValueKey('player-avatar')).evaluate()) {
        expect(
          tester.getSize(find.byWidget(avatar.widget)).width,
          PitchView.shareResultAvatarDiameter,
        );
      }
    });

    testWidgets('before-result share uses independent larger geometry',
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

      final pitchFinders = find.byKey(const ValueKey('match-pitch'));
      expect(pitchFinders, findsNWidgets(2));
      for (final element in pitchFinders.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, MatchResultCard.sharePitchWidth);
        expect(size.height, MatchResultCard.shareBeforePitchHeight);
        expect(
          size.width / size.height,
          closeTo(PitchView.shareBeforeAspectRatio, 0.001),
        );
      }

      for (final avatar
          in find.byKey(const ValueKey('player-avatar')).evaluate()) {
        expect(
          tester.getSize(find.byWidget(avatar.widget)).width,
          PitchView.shareBeforeAvatarDiameter,
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

/// How many of the two score numerals are picked out in the winner's green.
///
/// One on a win, none on a draw. Counted rather than described, because the
/// colour is the whole of the emphasis on the numerals themselves.
int _emphasisedNumerals(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(MatchStageHeader),
      matching: find.byType(Text),
    ))
    .where((text) =>
        int.tryParse(text.data ?? '') != null &&
        text.style?.color == MatchStage.accent)
    .length;

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
