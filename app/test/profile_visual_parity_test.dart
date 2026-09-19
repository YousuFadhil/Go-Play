import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_record_sections.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';

import 'player_record_fakes.dart';

/// The player's record, composed the way the approved reference composes it.
///
/// **The drift this pins.** The hero carried the ground, the face, the name and
/// the positions — three levels of identity on the green — and the white sheet
/// then opened straight onto a grid of figures. The approved transition is the
/// ground and the face, then the sheet, and the name and positions at the top
/// of it. A visitor and a signed-in reader must get the same composition; the
/// visitor in particular must never fall back to a plain bar over a form.
void main() {
  PlayerStatistics stats() => const PlayerStatistics(
        userId: 'u2',
        matchesPlayed: 12,
        wins: 7,
        losses: 3,
        draws: 2,
        goals: 9,
        mvpCount: 1,
        currentRating: 6.4,
      );

  PlayerProfileView viewOf({
    bool isSelf = false,
    String fullName = 'Noor Al Kindi',
  }) =>
      PlayerProfileView(
        userId: 'u2',
        fullName: fullName,
        isSelf: isSelf,
        statistics: stats(),
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: PlayerPosition.fwd,
      );

  RecentHighlight award({
    required HighlightPeriod period,
    required String periodKey,
    String community = 'Al Amerat FC',
    DateTime? at,
  }) =>
      RecentHighlight(
        kind: HighlightKind.teamOfPeriod,
        occurredAt: at ?? DateTime(2026, 9, 13, 23, 59),
        communityName: community,
        period: period,
        periodKey: periodKey,
      );

  Future<void> pumpProfile(
    WidgetTester tester, {
    required FakeProfileAdapter profiles,
    FakePlayerRecordAdapter? records,
    bool asVisitor = false,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 2200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ProfileScreen(
        userId: 'u2',
        asVisitor: asVisitor,
        profileRepository: ProfileRepository(profiles),
        resultRepository: ResultRepository(_Results(stats())),
        playerRecordRepository:
            PlayerRecordRepository(records ?? FakePlayerRecordAdapter()),
        authService: AuthService(_Auth()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the identity sits where the reference puts it', () {
    testWidgets('the ground carries the face, and only the face',
        (tester) async {
      await pumpProfile(tester, profiles: FakeProfileAdapter(player: viewOf()));

      final hero = find.byType(ClubHero);
      expect(hero, findsOneWidget);
      // The face is the focal point of the ground.
      expect(find.descendant(of: hero, matching: find.byType(PlayerAvatar)),
          findsOneWidget);
      // And the name is not on it any more.
      expect(
        find.descendant(of: hero, matching: find.text('Noor Al Kindi')),
        findsNothing,
      );
    });

    testWidgets('the sheet opens with the name and the positions',
        (tester) async {
      await pumpProfile(tester, profiles: FakeProfileAdapter(player: viewOf()));

      final sheet = find.byType(ClubSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Noor Al Kindi')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('MID')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('FWD')),
          findsOneWidget);
    });

    testWidgets('and the name comes above the career figures', (tester) async {
      await pumpProfile(tester, profiles: FakeProfileAdapter(player: viewOf()));

      final name = tester.getTopLeft(find.text('Noor Al Kindi')).dy;
      final positions = tester.getTopLeft(find.text('MID')).dy;
      final avatar = tester.getTopLeft(find.byType(PlayerAvatar).first).dy;

      expect(avatar, lessThan(name));
      expect(name, lessThan(positions));
    });
  });

  group('a visitor gets the same page', () {
    testWidgets('the Club composition, never a plain bar over a form',
        (tester) async {
      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: FakePlayerRecordAdapter(
          publicRecord: publicRecordOf(viewOf()),
        ),
        asVisitor: true,
      );

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(find.byType(ClubHeroBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      // Same identity transition as the signed-in reading.
      expect(
        find.descendant(
            of: find.byType(ClubSheet), matching: find.text('Noor Al Kindi')),
        findsOneWidget,
      );
    });

    testWidgets('and never mounts an authenticated read', (tester) async {
      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: FakePlayerRecordAdapter(
          publicRecord: publicRecordOf(viewOf()),
        ),
        asVisitor: true,
      );

      // `CurrentUserMenu` reads `my_profile` the moment it is built.
      expect(find.byType(CurrentUserMenu), findsNothing);
    });
  });

  group('recent achievements are what the database stored', () {
    testWidgets('a week and a month award both render', (tester) async {
      // The UAT case: a player selected in the last *closed* week and the last
      // closed month. Two stored rows, two cards.
      final records = FakePlayerRecordAdapter(
        teamOfPeriod: award(
          period: HighlightPeriod.week,
          periodKey: '2026-W37',
        ),
        extraAchievements: [
          award(
            period: HighlightPeriod.month,
            periodKey: '2026-08',
            at: DateTime(2026, 8, 31, 23, 59),
          ),
        ],
      );

      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: records,
      );

      expect(find.byType(RecentAchievementsSection), findsOneWidget);
      expect(find.byType(AchievementCard), findsNWidgets(2));
      expect(find.text('Team of the Week'), findsOneWidget);
      expect(find.text('Team of the Month'), findsOneWidget);
    });

    testWidgets('two communities in the same period are two achievements',
        (tester) async {
      final records = FakePlayerRecordAdapter(
        teamOfPeriod: award(
          period: HighlightPeriod.week,
          periodKey: '2026-W37',
        ),
        extraAchievements: [
          award(
            period: HighlightPeriod.week,
            periodKey: '2026-W37',
            community: 'Al Seeb FC',
          ),
        ],
      );

      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: records,
      );

      expect(find.byType(AchievementCard), findsNWidgets(2));
      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Al Seeb FC'), findsOneWidget);
    });

    testWidgets('nothing eligible hides the section entirely', (tester) async {
      // Which is the live state today: no snapshot has been written, so there
      // is no award to read and an empty card would be a placeholder for
      // something most players will never have.
      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: FakePlayerRecordAdapter(),
      );

      expect(find.byType(RecentAchievementsSection), findsNothing);
      expect(find.byType(AchievementCard), findsNothing);
    });

    testWidgets('the MVP and the awards are all kept, newest first',
        (tester) async {
      final records = FakePlayerRecordAdapter(
        mvp: RecentHighlight(
          kind: HighlightKind.mvp,
          occurredAt: DateTime(2026, 9, 18),
          communityName: 'Al Amerat FC',
        ),
        teamOfPeriod: award(
          period: HighlightPeriod.week,
          periodKey: '2026-W37',
        ),
        extraAchievements: [
          award(
            period: HighlightPeriod.month,
            periodKey: '2026-08',
            at: DateTime(2026, 8, 31, 23, 59),
          ),
        ],
      );

      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(player: viewOf()),
        records: records,
      );

      expect(find.byType(AchievementCard), findsNWidgets(3));
      // Nothing on the client drops a weekly or a monthly award.
      expect(find.text('Team of the Week'), findsOneWidget);
      expect(find.text('Team of the Month'), findsOneWidget);
    });
  });

  group('long names stay safe on a narrow phone', () {
    const longEn = 'Abdulrahman Mohammed Al Balushi Al Amri Al Hinai';
    const longAr = 'عبدالرحمن محمد البلوشي العامري الهنائي الكندي';

    for (final width in [320.0, 412.0, 480.0]) {
      testWidgets('at ${width.toInt()}px in en', (tester) async {
        await pumpProfile(
          tester,
          profiles: FakeProfileAdapter(player: viewOf(fullName: longEn)),
          size: Size(width, 2200),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ClubSheet), findsOneWidget);
      });

      testWidgets('at ${width.toInt()}px in ar', (tester) async {
        await pumpProfile(
          tester,
          profiles: FakeProfileAdapter(player: viewOf(fullName: longAr)),
          locale: const Locale('ar'),
          size: Size(width, 2200),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ClubSheet), findsOneWidget);
      });
    }
  });
}

class _Results implements ResultAdapter {
  _Results(this.stats);

  final PlayerStatistics stats;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async => stats;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => 'u1';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeProfileAdapter implements ProfileAdapter {
  FakeProfileAdapter({required this.player});

  final PlayerProfileView player;

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) async => player;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
