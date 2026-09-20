import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/discover/public_match_stage.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/teams/pitch_view.dart';

/// A completed match, drawn the same way for both readers.
///
/// **The defect this closes.** A guest opened a played match onto a white
/// sheet with two name lists under a pair of score cards, while a member
/// opened the same match onto the pitch. Two audiences were looking at the
/// same football and seeing two different products.
///
/// What is asserted here is that the public route now draws through the *same*
/// Match Stage primitives — and, just as deliberately, that it gained no
/// capability by doing so.
void main() {
  PublicLineupEntry entry({
    required String team,
    required String name,
    String? position = 'MID',
    String? playerId,
    bool guest = false,
    int goals = 0,
    bool mvp = false,
    String? avatarUrl,
  }) =>
      PublicLineupEntry(
        team: team,
        displayName: name,
        isProfessionalGuest: guest,
        goals: goals,
        isMvp: mvp,
        assignedPosition: position,
        avatarUrl: avatarUrl,
        playerId: playerId,
      );

  PublicCompletedMatch completed({
    List<PublicLineupEntry>? lineup,
    bool hasResult = true,
    String? location = 'Al Amerat Pitch',
  }) =>
      PublicCompletedMatch(
        id: 'm1',
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: 'Friday football',
        location: location,
        startAt: DateTime(2026, 9, 11, 17),
        endAt: DateTime(2026, 9, 11, 19),
        hasResult: hasResult,
        teamAScore: hasResult ? 3 : null,
        teamBScore: hasResult ? 2 : null,
        mvpDisplayName: 'Yousif Adhil',
        lineup: lineup ??
            [
              entry(
                team: 'A',
                name: 'Yousif Adhil',
                position: 'GK',
                playerId: 'u1',
                mvp: true,
              ),
              entry(
                  team: 'A', name: 'Salim Al Harthy', playerId: 'u2', goals: 2),
              entry(team: 'A', name: 'A Guest', guest: true),
              entry(
                  team: 'B',
                  name: 'Noor Al Kindi',
                  playerId: 'u3',
                  position: 'DEF'),
              entry(team: 'B', name: 'Hidden Profile', position: 'FWD'),
            ],
      );

  Future<_Routes> pump(
    WidgetTester tester, {
    PublicCompletedMatch? match,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 2200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: [routes],
      home: PublicMatchScreen(
        matchId: 'm1',
        repository: DiscoverRepository(_Discover(match ?? completed())),
        authService: AuthService(_Guest()),
      ),
    ));
    await tester.pumpAndSettle();
    return routes;
  }

  group('it is the Match Stage, not a team sheet', () {
    testWidgets('the ground, the board and two pitches', (tester) async {
      await pump(tester);

      expect(find.byType(MatchStageGround), findsOneWidget);
      expect(find.byType(PublicMatchStage), findsOneWidget);
      expect(find.byType(MatchStageBoard), findsOneWidget);
      expect(find.byType(PitchView), findsNWidgets(2));
    });

    testWidgets('and the old white team-sheet composition is gone',
        (tester) async {
      await pump(tester);

      // The page used to open on a Club hero over a white sheet with two
      // name lists on it.
      expect(find.byType(ClubSheet), findsNothing);
      expect(find.byType(StadiumBackdrop), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('both sides are named and drawn', (tester) async {
      await pump(tester);

      // Twice each: the section heading over the pitch, and the name under
      // that side's figure in the score strip.
      expect(find.text('Team A'), findsWidgets);
      expect(find.text('Team B'), findsWidgets);
      expect(find.text('Yousif Adhil'), findsWidgets);
      expect(find.text('Noor Al Kindi'), findsWidgets);
    });
  });

  group('what the public contract carries reaches the pitch', () {
    testWidgets('positions place the players', (tester) async {
      await pump(tester);

      final stage = tester.widget<PublicMatchStage>(
        find.byType(PublicMatchStage),
      );
      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );

      expect(board.lineup, hasLength(5));
      // A goalkeeper was fielded, so a goalkeeper position exists.
      expect(board.hasNaturalGoalkeeper, isTrue);
      expect(stage.match.lineup.first.assignedPosition, 'GK');
    });

    testWidgets('no goalkeeper in the lineup fields no goalkeeper',
        (tester) async {
      await pump(
        tester,
        match: completed(lineup: [
          entry(team: 'A', name: 'One', playerId: 'u1'),
          entry(team: 'B', name: 'Two', playerId: 'u2'),
        ]),
      );

      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );
      expect(board.hasNaturalGoalkeeper, isFalse);
    });

    testWidgets('goals and the MVP are on the players', (tester) async {
      await pump(tester);

      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );
      final scorer = board.lineup.firstWhere(
          (a) => board.nameOf(a.participantId) == 'Salim Al Harthy');
      final best = board.lineup
          .firstWhere((a) => board.nameOf(a.participantId) == 'Yousif Adhil');

      expect(board.goalsOf!(scorer.participantId), 2);
      expect(board.isMvpOf!(best.participantId), isTrue);
      expect(board.isMvpOf!(scorer.participantId), isFalse);
    });

    testWidgets('the score is on the header, bound to its side',
        (tester) async {
      await pump(tester);

      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );
      expect(board.teamAScore, 3);
      expect(board.teamBScore, 2);
      expect(board.winner, isNotNull);
    });

    testWidgets('and no rating is invented for anybody', (tester) async {
      // A rating is not public. The cards carry none rather than a zero,
      // which would be a claim the contract never made.
      await pump(tester);

      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );
      expect(board.ratingOf, isNull);
      expect(board.players, isEmpty);
      expect(board.avatarUrlOf, isNotNull);
    });
  });

  group('a name leads somewhere only where the database published it', () {
    testWidgets('a registered player with a public profile opens it',
        (tester) async {
      final routes = await pump(tester);
      routes.pushed.clear();

      await tester.tap(find.text('Noor Al Kindi').first);
      await tester.pumpAndSettle();

      expect(routes.pushed, isNotEmpty);
    });

    testWidgets('a player whose profile was not published opens nothing',
        (tester) async {
      final routes = await pump(tester);
      routes.pushed.clear();

      await tester.tap(find.text('Hidden Profile').first);
      await tester.pumpAndSettle();

      expect(routes.pushed, isEmpty);
    });

    testWidgets('and a Professional Guest opens nothing', (tester) async {
      final routes = await pump(tester);
      routes.pushed.clear();

      await tester.tap(find.text('A Guest').first);
      await tester.pumpAndSettle();

      expect(routes.pushed, isEmpty);
    });

    testWidgets('a guest is drawn as a guest, a player as a player',
        (tester) async {
      await pump(tester);

      final board = tester.widget<MatchStageBoard>(
        find.byType(MatchStageBoard),
      );
      final guest = board.lineup
          .firstWhere((a) => board.nameOf(a.participantId) == 'A Guest');
      final hidden = board.lineup
          .firstWhere((a) => board.nameOf(a.participantId) == 'Hidden Profile');

      expect(guest.isProfessionalGuest, isTrue);
      // Unpublished is not the same as unregistered: a real player whose
      // profile is private still played, and is still drawn as a player.
      expect(hidden.isProfessionalGuest, isFalse);
    });
  });

  group('a visitor gains nothing by the shared drawing', () {
    testWidgets('no management, no editing, no roster administration',
        (tester) async {
      await pump(tester);

      for (final forbidden in [
        'Edit result',
        'Record result',
        'Manage',
        'Reserves',
        'Remove',
        'Generate teams',
        'Share',
      ]) {
        expect(find.text(forbidden), findsNothing, reason: forbidden);
      }
    });

    testWidgets('the auth affordance sits under the football, not in it',
        (tester) async {
      await pump(tester);

      final pitch = tester.getBottomLeft(find.byType(PitchView).last).dy;
      final login = tester.getTopLeft(find.text('Log in')).dy;
      expect(login, greaterThan(pitch));
    });

    testWidgets('and it does not change the football presentation',
        (tester) async {
      await pump(tester);

      // The board is the same object whether or not the auth panel is below
      // it: nothing about the stage is conditioned on a session.
      expect(find.byType(MatchStageBoard), findsOneWidget);
      expect(find.byType(PitchView), findsNWidgets(2));
    });
  });

  group('a match with no published lineup', () {
    testWidgets('says so with the header rather than an empty pitch',
        (tester) async {
      await pump(tester, match: completed(lineup: const []));

      // An empty pitch would report that nobody turned up, which is a
      // different claim from "the teams were not published".
      expect(find.byType(PitchView), findsNothing);
      expect(find.byType(MatchStageGround), findsOneWidget);
      expect(
        find.textContaining('Al Amerat FC', findRichText: true),
        findsWidgets,
      );
    });
  });

  group('it survives a narrow phone in both languages', () {
    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets('at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(tester, locale: locale, size: Size(width, 2200));

          expect(tester.takeException(), isNull);
          expect(find.byType(MatchStageBoard), findsOneWidget);
          expect(find.byType(PitchView), findsNWidgets(2));
        });
      }
    }
  });
}

class _Routes extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

class _Discover implements DiscoverAdapter {
  _Discover(this.match);

  final PublicCompletedMatch match;

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async => match;

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      match.lineup;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Guest implements AuthAdapter {
  @override
  bool get isSignedIn => false;

  @override
  String? get currentUserId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
