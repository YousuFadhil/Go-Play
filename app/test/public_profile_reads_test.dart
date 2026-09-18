import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/app.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/profile/player_record_adapter.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_models.dart';

import 'player_record_fakes.dart';

/// Two defects found on staging, and the reasons they happened.
///
///  1. A guest opening `/player/{id}` sent `my_profile` and was refused with a
///     401. The read was not the profile's: [AppHeader] always mounts
///     [CurrentUserMenu], whose `initState` loads the signed-in player, and the
///     screen used that bar for its loading and error states — so a visitor
///     asked an authenticated contract before the page had drawn anything.
///
///  2. The same page read each public contract three times. Navigator expands
///     an initial route into one route per path segment, so `/player/<id>` cold
///     started three copies of the entry point.
///
/// Both are pinned here at the level they were caused: the screen's own tree,
/// and the app's initial-route rule.
void main() {
  const userId = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  PlayerProfileView publicProfile() => const PlayerProfileView(
        userId: userId,
        fullName: 'Noor Al Kindi',
        primaryPosition: PlayerPosition.mid,
        statistics: PlayerStatistics(
          userId: userId,
          matchesPlayed: 12,
          wins: 6,
          losses: 4,
          draws: 2,
          goals: 5,
          mvpCount: 1,
          currentRating: 6.4,
        ),
        isSelf: false,
      );

  Future<void> pumpVisitorProfile(
    WidgetTester tester, {
    required PlayerRecordAdapter records,
    required _CountingProfileAdapter profiles,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ProfileScreen(
        userId: userId,
        asVisitor: true,
        profileRepository: ProfileRepository(profiles),
        playerRecordRepository: PlayerRecordRepository(records),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  group('a guest never asks an authenticated question', () {
    testWidgets('the loaded public profile reads only the public contract',
        (tester) async {
      final profiles = _CountingProfileAdapter();
      final records = FakePlayerRecordAdapter(
        publicRecord: publicRecordOf(publicProfile()),
      );

      await pumpVisitorProfile(tester, records: records, profiles: profiles);

      expect(find.text('Noor Al Kindi'), findsOneWidget);
      expect(records.requestedPublicUserId, userId);
      expect(profiles.myProfileReads, 0,
          reason: 'my_profile is the signed-in self read and 401s for a guest');
      expect(profiles.playerProfileReads, 0);
      // The structural reason, pinned: the bar that would have made that call
      // is not in this screen's tree at all.
      expect(find.byType(CurrentUserMenu), findsNothing);
      expect(find.byType(AppHeader), findsNothing);
    });

    testWidgets('nor while the page is still loading', (tester) async {
      // The state the defect actually happened in: the skeleton was wearing
      // the app header, so the read went out before any record arrived.
      final profiles = _CountingProfileAdapter();
      final records = _PendingRecordAdapter();

      await pumpVisitorProfile(
        tester,
        records: records,
        profiles: profiles,
        settle: false,
      );
      await tester.pump();

      expect(profiles.myProfileReads, 0);
      expect(find.byType(CurrentUserMenu), findsNothing);

      records.complete(publicRecordOf(publicProfile()));
      await tester.pumpAndSettle();
      expect(profiles.myProfileReads, 0);
    });

    testWidgets('nor when the link points at nothing', (tester) async {
      final profiles = _CountingProfileAdapter();
      final records = FakePlayerRecordAdapter(thrown: const NotFoundFailure());

      await pumpVisitorProfile(tester, records: records, profiles: profiles);

      expect(profiles.myProfileReads, 0);
      expect(find.byType(CurrentUserMenu), findsNothing);
    });

    testWidgets('a signed-in reader still gets the authenticated reads',
        (tester) async {
      // The fix must not have narrowed the other two readings of the screen:
      // this is somebody else's profile, opened with a session.
      final profiles = _CountingProfileAdapter();
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ProfileScreen(
          userId: userId,
          profileRepository: ProfileRepository(profiles),
          playerRecordRepository:
              PlayerRecordRepository(FakePlayerRecordAdapter()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(profiles.playerProfileReads, 1);
      expect(find.text('Noor Al Kindi'), findsOneWidget);
    });
  });

  group('a cold start on a deep link opens one page', () {
    test('the app generates exactly one initial route', () {
      // Whatever the path, one route: the link itself is taken from
      // PendingPublicLink rather than from the route name.
      for (final path in [
        '/',
        '/player/$userId',
        '/community/$userId',
        '/match/$userId',
      ]) {
        expect(initialRoutesFor(path), hasLength(1), reason: path);
      }
    });

    testWidgets('Navigator would otherwise build one route per path segment',
        (tester) async {
      // The defect itself, reproduced against the framework's own default —
      // three routes for `/player/<id>` is three entry points, three profile
      // screens and three identical reads.
      final generated = <String>[];

      Route<dynamic> record(RouteSettings settings) {
        generated.add(settings.name ?? '');
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      }

      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          initialRoute: '/player/$userId',
          onGenerateRoute: record,
        ),
      ));
      expect(generated, ['/', '/player', '/player/$userId']);

      generated.clear();
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          key: const ValueKey('fixed'),
          initialRoute: '/player/$userId',
          onGenerateRoute: record,
          onGenerateInitialRoutes: (_, initialRoute) => [
            record(RouteSettings(name: initialRoute)),
          ],
        ),
      ));
      expect(generated, ['/player/$userId'],
          reason: 'one initial route, built once');
    });
  });
}

/// A profile port that answers nothing and counts what it was asked.
///
/// The two authenticated reads are counted separately because the defect was
/// about one of them: `my_profile` is "who am I", which a guest has no answer
/// to and no right to ask.
class _CountingProfileAdapter implements ProfileAdapter {
  int myProfileReads = 0;
  int playerProfileReads = 0;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    myProfileReads++;
    return const PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    );
  }

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) async {
    playerProfileReads++;
    return PlayerProfileView(
      userId: userId,
      fullName: 'Noor Al Kindi',
      primaryPosition: PlayerPosition.mid,
      statistics: PlayerStatistics(
        userId: userId,
        matchesPlayed: 12,
        wins: 6,
        losses: 4,
        draws: 2,
        goals: 5,
        mvpCount: 1,
        currentRating: 6.4,
      ),
      isSelf: false,
    );
  }

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) async {}

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) async {}

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) async {}

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) async =>
      '';

  @override
  Future<void> removeMyAvatar() async {}
}

/// A record port whose public read is still in flight until a test completes
/// it, so the loading state can be inspected.
class _PendingRecordAdapter implements PlayerRecordAdapter {
  final _completer = Completer<PublicPlayerRecord?>();

  void complete(PublicPlayerRecord record) => _completer.complete(record);

  @override
  Future<PublicPlayerRecord?> fetchPublicRecord(
    String userId, {
    int limit = 5,
  }) =>
      _completer.future;

  @override
  Future<RecentForm> fetchRecentForm(String userId, {int limit = 5}) async =>
      RecentForm.empty;

  @override
  Future<List<RecentHighlight>> fetchRecentHighlights(String userId) async =>
      const [];
}
