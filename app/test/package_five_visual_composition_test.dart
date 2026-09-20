import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';

import 'player_record_fakes.dart';

/// The approved Package 5 composition, as the widget tree.
///
/// The pictures are what a visual review is actually done against — this suite
/// is what stops the composition drifting back afterwards. It pins the things
/// the Product Owner asked for by name: a ground behind the identity rather
/// than a flat block, seven career figures and no eighth, a scoreline under
/// every result, the stored week rather than a counted one, and no prose in
/// the middle of the page.
void main() {
  const userId = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  PlayerStatistics stats() => const PlayerStatistics(
        userId: userId,
        matchesPlayed: 24,
        wins: 16,
        losses: 6,
        draws: 2,
        goals: 18,
        mvpCount: 7,
        currentRating: 7.8,
      );

  RecentForm form() => formOf(
        [
          MatchOutcome.win,
          MatchOutcome.win,
          MatchOutcome.draw,
          MatchOutcome.loss,
          MatchOutcome.win,
        ],
        scores: [(2, 1), (3, 0), (1, 1), (0, 2), (4, 1)],
      );

  RecentHighlight teamOfWeek() => RecentHighlight(
        kind: HighlightKind.teamOfPeriod,
        period: HighlightPeriod.week,
        periodKey: '2026-W37',
        occurredAt: DateTime.utc(2026, 9, 13, 19, 59, 59),
        communityName: 'Al Seeb Community',
      );

  Future<void> pumpOwnProfile(
    WidgetTester tester, {
    double width = 412,
    Locale locale = const Locale('en'),
    String fullName = 'Noor Al Kindi',
    RecentForm? recentForm,
    RecentHighlight? highlight,
    bool noHighlight = false,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ProfileScreen(
        profileRepository: ProfileRepository(_Profiles(PlayerProfile(
          fullName: fullName,
          phone: '+96890123456',
          primaryPosition: PlayerPosition.mid,
          secondaryPosition: PlayerPosition.fwd,
          dateOfBirth: DateTime(1992, 3, 10),
        ))),
        resultRepository: ResultRepository(_Results(stats())),
        playerRecordRepository: PlayerRecordRepository(FakePlayerRecordAdapter(
          form: recentForm ?? form(),
          teamOfPeriod: noHighlight ? null : (highlight ?? teamOfWeek()),
        )),
        authService: AuthService(_Auth()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the hero is a ground, not a block', () {
    testWidgets('the player stands on a stadium the app draws itself',
        (tester) async {
      await pumpOwnProfile(tester);

      expect(find.byType(StadiumBackdrop), findsOneWidget);
      // Drawn rather than fetched: no asset, no network, nothing to licence.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a completed public match opens on the Match Stage ground',
        (tester) async {
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: PublicMatchScreen(
          matchId: 'm1',
          repository: DiscoverRepository(_Discover()),
          authService: AuthService(_Auth()),
        ),
      ));
      await tester.pumpAndSettle();

      // **Stronger than the stadium hero it used to open on.** A played match
      // is a pitch, and the Match Stage is where this product draws one -- so
      // the public route now uses the stage's own ground, exactly as the
      // member's route does, rather than a Club hero over a white sheet.
      expect(find.byType(MatchStageGround), findsOneWidget);
      expect(find.byType(StadiumBackdrop), findsNothing);
      // The stage header carries the community as a rich-text span, beside
      // the date, exactly as it does on the member's route.
      expect(
        find.textContaining('Al Seeb Community', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('and carries no age pill', (tester) async {
      await pumpOwnProfile(tester);

      // The approved identity is the face, the name and where they play.
      expect(find.text('34 years old'), findsNothing);
      expect(find.textContaining('years old'), findsNothing);
      expect(find.text('Midfielder'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);
    });
  });

  group('the career grid is seven figures', () {
    testWidgets('four results, then goals, MVP and the rating', (tester) async {
      await pumpOwnProfile(tester);

      for (final label in [
        'Matches',
        'Wins',
        'Losses',
        'Draws',
        'Goals',
        'MVP',
        'Current rating',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No eighth cell: how many clubs a player is in is what the Communities
      // tab is, and it is not one of the seven football figures.
      expect(find.text('Communities'), findsNothing);
    });

    testWidgets('the rating is the product 0-10 value, never a hundredth',
        (tester) async {
      await pumpOwnProfile(tester);

      expect(find.text('7.8'), findsOneWidget);
      expect(find.text('78'), findsNothing);
    });
  });

  group('Recent Form is badges and scorelines', () {
    testWidgets('each result carries the score from the player side',
        (tester) async {
      await pumpOwnProfile(tester);

      for (final scoreline in ['2 - 1', '3 - 0', '1 - 1', '0 - 2', '4 - 1']) {
        expect(find.text(scoreline), findsOneWidget, reason: scoreline);
      }
      expect(find.text('W'), findsNWidgets(3));
      expect(find.text('D'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('and no paragraph explaining itself', (tester) async {
      await pumpOwnProfile(tester);

      expect(find.textContaining('completed matches, most recent first'),
          findsNothing);
      expect(find.textContaining('Matches  ·'), findsNothing);
    });

    testWidgets('fewer than five results still lay out', (tester) async {
      await pumpOwnProfile(
        tester,
        recentForm: formOf([MatchOutcome.win, MatchOutcome.loss]),
      );

      expect(find.text('3 - 1'), findsOneWidget);
      expect(find.text('0 - 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and none at all says so', (tester) async {
      await pumpOwnProfile(tester, recentForm: RecentForm.empty);

      expect(find.textContaining('No completed matches yet'), findsOneWidget);
      expect(find.text('W'), findsNothing);
    });
  });

  group('Recent Highlight names its period', () {
    testWidgets('a stored Team of the Week says which week', (tester) async {
      await pumpOwnProfile(tester);

      expect(find.text('Team of the Week'), findsOneWidget);
      // The stored key's week, and the day the period closed in Muscat.
      expect(find.text('Week 37 • Sep 13, 2026'), findsOneWidget);
      expect(find.text('Al Seeb Community'), findsOneWidget);
      // No affordance that leads nowhere.
      expect(
        find.descendant(
          of: find.text('Team of the Week'),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
      );
    });

    testWidgets('an MVP is dated, because a match is not a period',
        (tester) async {
      await pumpOwnProfile(
        tester,
        highlight: RecentHighlight(
          kind: HighlightKind.mvp,
          occurredAt: DateTime.utc(2026, 9, 11, 13),
          communityName: 'Al Seeb Community',
        ),
      );

      expect(find.text('Player of the match'), findsOneWidget);
      expect(find.text('Sep 11, 2026'), findsOneWidget);
      expect(find.textContaining('Week'), findsNothing);
    });

    testWidgets('nothing eligible is no section at all', (tester) async {
      await pumpOwnProfile(tester, noHighlight: true);
      // `FakePlayerRecordAdapter` returns no candidates, so the screen has
      // nothing to draw and draws nothing.
      expect(find.text('Recent highlight'), findsNothing);
    });
  });

  group('the composition holds at every width, in both languages', () {
    for (final width in [320.0, 412.0, 480.0]) {
      testWidgets('English at $width', (tester) async {
        await pumpOwnProfile(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('Recent form'), findsOneWidget);
        expect(find.text('2 - 1'), findsOneWidget);
      });

      testWidgets('Arabic at $width', (tester) async {
        await pumpOwnProfile(
          tester,
          width: width,
          locale: const Locale('ar'),
          fullName: 'نور الكندي',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('الأداء الأخير'), findsOneWidget);
        // A scoreline reads the same way round in both languages.
        expect(find.text('2 - 1'), findsOneWidget);
      });
    }

    testWidgets('a long English name does not overflow the hero',
        (tester) async {
      await pumpOwnProfile(
        tester,
        width: 320,
        fullName: 'Abdulrahman Mohammed Al Balushi Al Hinai Al Amerat',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('nor a long Arabic one', (tester) async {
      await pumpOwnProfile(
        tester,
        width: 320,
        locale: const Locale('ar'),
        fullName: 'عبد الرحمن محمد البلوشي الهنائي من العامرات',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _Profiles implements ProfileAdapter {
  _Profiles(this.profile);

  final PlayerProfile profile;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Results implements ResultAdapter {
  _Results(this.statistics);

  final PlayerStatistics statistics;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async => statistics;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Discover implements DiscoverAdapter {
  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async =>
      PublicCompletedMatch(
        id: matchId,
        communityId: 'c1',
        communityName: 'Al Seeb Community',
        title: 'Friday football',
        location: 'Al Seeb Sports Complex',
        startAt: DateTime.utc(2026, 9, 11, 15),
        endAt: DateTime.utc(2026, 9, 11, 17),
        hasResult: true,
        teamAScore: 3,
        teamBScore: 2,
        lineup: const [],
      );

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
