import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/config.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/profile/player_profile_share_card.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_record_sections.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';

import 'player_record_fakes.dart';
import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

/// Sharing a Player Profile: the card, the payload, and who may send one.
///
/// The rule the whole feature rests on is one sentence — **content the viewer
/// is already allowed to see may be shared** — and it is structural rather
/// than a check: the card is composed from what the screen was given, so a
/// public reading produces a public card and there is no second read a share
/// could widen the disclosure with.
void main() {
  const userId = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  PlayerStatistics stats({double rating = 7.4}) => PlayerStatistics(
        userId: userId,
        matchesPlayed: 24,
        wins: 13,
        losses: 7,
        draws: 4,
        goals: 11,
        mvpCount: 3,
        currentRating: rating,
      );

  PlayerProfileView viewOf({
    String fullName = 'Noor Al Kindi',
    String? avatarUrl,
    bool isSelf = false,
  }) =>
      PlayerProfileView(
        userId: userId,
        fullName: fullName,
        primaryPosition: PlayerPosition.mid,
        secondaryPosition: PlayerPosition.fwd,
        avatarUrl: avatarUrl,
        statistics: stats(),
        isSelf: isSelf,
      );

  PlayerProfileCardData cardOf({
    String fullName = 'Noor Al Kindi',
    String? avatarUrl,
    RecentForm form = RecentForm.empty,
  }) =>
      PlayerProfileCardData(
        fullName: fullName,
        avatarUrl: avatarUrl,
        primaryPosition: PlayerPosition.mid,
        rating: 7.4,
        matchesPlayed: 24,
        goals: 11,
        mvpCount: 3,
        form: form,
      );

  // --- the card itself --------------------------------------------------------

  /// Pumps the card at the engine's own size, so what is measured is the card
  /// as it will be composed rather than one squeezed into a phone.
  Future<void> pumpCard(
    WidgetTester tester,
    PlayerProfileCardData data, {
    Locale locale = const Locale('en'),
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
          child: ShareCardSurface(child: PlayerProfileShareCard(data: data)),
        ),
      ),
    ));
    await tester.pump();
  }

  group('the Player Profile card', () {
    testWidgets('leads with who the player is', (tester) async {
      await pumpCard(tester, cardOf());

      expect(find.text('Noor Al Kindi'), findsOneWidget);
      expect(find.text('Position · Midfielder'), findsOneWidget);
      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('GO PLAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('carries three indicators and not the statistics card\'s six',
        (tester) async {
      await pumpCard(tester, cardOf());

      expect(find.text('MATCHES'), findsOneWidget);
      expect(find.text('GOALS'), findsOneWidget);
      expect(find.text('MVP'), findsOneWidget);
      // The three the other card adds. This one is an identity card; showing
      // all six would make it the Player Statistics card with a different
      // background.
      expect(find.text('WINS'), findsNothing);
      expect(find.text('DRAWS'), findsNothing);
      expect(find.text('LOSSES'), findsNothing);
    });

    testWidgets('shows no date of birth, because it is handed none',
        (tester) async {
      await pumpCard(tester, cardOf());
      // Structural rather than a check: `PlayerProfileCardData` has nowhere to
      // put one, so no screen above can send one to the card.
      expect(find.textContaining('19'), findsNothing);
      expect(find.textContaining('years'), findsNothing);
    });

    testWidgets('fills the 1080x1920 surface without overflowing',
        (tester) async {
      await pumpCard(
        tester,
        cardOf(
          form: formOf([
            MatchOutcome.win,
            MatchOutcome.win,
            MatchOutcome.draw,
            MatchOutcome.loss,
            MatchOutcome.win,
          ]),
        ),
      );

      expect(
        tester.getSize(find.byType(ShareCardSurface)),
        ShareCardCanvas.designSize,
      );
      expect(tester.takeException(), isNull,
          reason: 'a card that overflows its own surface is a broken picture');
    });

    testWidgets('draws the recent form newest first', (tester) async {
      await pumpCard(
        tester,
        cardOf(form: formOf([MatchOutcome.win, MatchOutcome.loss])),
      );

      expect(find.text('RECENT FORM'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);

      // The most recent is the leading one, which in English is the left.
      final win = tester.getCenter(find.text('W'));
      final loss = tester.getCenter(find.text('L'));
      expect(win.dx, lessThan(loss.dx));
    });

    testWidgets('a player with no form gets a card with no strip',
        (tester) async {
      await pumpCard(tester, cardOf());

      expect(find.text('RECENT FORM'), findsNothing);
      expect(find.text('W'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a player with no picture still gets everyone else\'s card',
        (tester) async {
      await pumpCard(tester, cardOf());
      // The app's own initials fallback, not a gap and not a broken image.
      expect(find.text('NK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long name is scaled down rather than cut off',
        (tester) async {
      const long = 'Abdulrahman Mohammed Al Balushi Al Hinai Al Amerat';
      await pumpCard(tester, cardOf(fullName: long));

      expect(find.text(long), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic composes right to left, with no second layout',
        (tester) async {
      await pumpCard(
        tester,
        cardOf(
          fullName: 'نور الكندي',
          form: formOf([MatchOutcome.win, MatchOutcome.loss]),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('نور الكندي'), findsOneWidget);
      expect(find.text('المركز · وسط'), findsOneWidget);
      // The rating is a number and reads left to right in both languages.
      expect(find.text('7.4'), findsOneWidget);
      // The mark is a name, not a sentence: Go Play in Arabic too.
      expect(find.text('GO PLAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Arabic form strip runs the other way', (tester) async {
      await pumpCard(
        tester,
        cardOf(
          fullName: 'نور الكندي',
          form: formOf([MatchOutcome.win, MatchOutcome.loss]),
        ),
        locale: const Locale('ar'),
      );

      // Newest first is the reading direction, not the list order: in Arabic
      // the most recent match is on the right.
      final win = tester.getCenter(find.text('ف'));
      final loss = tester.getCenter(find.text('خ'));
      expect(win.dx, greaterThan(loss.dx));
    });

    testWidgets('a long Arabic name does not overflow either', (tester) async {
      const long = 'عبد الرحمن محمد البلوشي الهنائي من العامرات';
      await pumpCard(
        tester,
        cardOf(fullName: long),
        locale: const Locale('ar'),
      );

      expect(find.text(long), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // --- sharing it from the screen ---------------------------------------------

  Future<_Share> pumpProfile(
    WidgetTester tester, {
    String? openUserId = userId,
    bool asVisitor = false,
    FakeProfileAdapter? profiles,
    FakePlayerRecordAdapter? records,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final share = _Share();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ProfileScreen(
        userId: openUserId,
        asVisitor: asVisitor,
        profileRepository: ProfileRepository(
          profiles ?? FakeProfileAdapter(player: viewOf()),
        ),
        resultRepository: ResultRepository(_FakeResultAdapter(stats())),
        communityRepository: CommunityRepository(_FakeCommunityAdapter()),
        playerRecordRepository:
            PlayerRecordRepository(records ?? FakePlayerRecordAdapter()),
        authService: AuthService(_StubAuthAdapter()),
        renderer: _StubRenderer(),
        shareService: share,
      ),
    ));
    await tester.pumpAndSettle();
    return share;
  }

  group('the share action on a profile', () {
    testWidgets('the player\'s own record offers to share their profile',
        (tester) async {
      await pumpProfile(
        tester,
        openUserId: null,
        profiles: FakeProfileAdapter(
          profile: const PlayerProfile(
            fullName: 'Salim Al Harthy',
            phone: '+96890123456',
            primaryPosition: PlayerPosition.def,
          ),
        ),
      );

      expect(find.byTooltip('Share my profile'), findsOneWidget);
    });

    testWidgets('another visible player can be shared too', (tester) async {
      await pumpProfile(tester);

      // The approved rule: a profile the reader is allowed to see is a profile
      // they are allowed to send.
      expect(find.byTooltip('Share profile'), findsOneWidget);
    });

    testWidgets('a profile the reader may not open offers no share at all',
        (tester) async {
      await pumpProfile(
        tester,
        profiles: FakeProfileAdapter(
          failure: const AuthorizationFailure(FailureReason.profileNotVisible),
        ),
      );

      expect(find.byTooltip('Share profile'), findsNothing);
      expect(find.byTooltip('Share my profile'), findsNothing);
      // Nothing was composed, so nothing could have been sent.
      expect(find.byIcon(Icons.ios_share), findsNothing);
    });

    testWidgets('sharing hands over an image, words and a public link',
        (tester) async {
      final share = await pumpProfile(tester);

      await tester.tap(find.byTooltip('Share profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();

      expect(share.image, isNotNull, reason: 'the picture still travels');
      final message = share.message;
      expect(message, isNotNull);
      expect(message!.text, 'Noor Al Kindi — player profile on Go Play.');
      expect(message.url, PublicLink.format(PublicLinkKind.player, userId));
      // The body is what the sheet is actually handed: the words, then the
      // link on its own line so every messaging app auto-links it.
      expect(share.body, '${message.text}\n\n${message.url}');
      expect(share.body, contains(AppConfig.publicWebBase));
    });

    testWidgets('a player sharing themselves says so', (tester) async {
      final share = await pumpProfile(
        tester,
        openUserId: null,
        profiles: FakeProfileAdapter(
          profile: const PlayerProfile(
            fullName: 'Salim Al Harthy',
            phone: '+96890123456',
            primaryPosition: PlayerPosition.def,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Share my profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();

      expect(share.message!.text, 'My player profile on Go Play.');
    });

    testWidgets('the words are the reader\'s language', (tester) async {
      final share = await pumpProfile(tester, locale: const Locale('ar'));

      await tester.tap(find.byTooltip('مشاركة الملف'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'مشاركة'));
      await tester.pumpAndSettle();

      expect(share.message!.text, contains('ملف اللاعب'));
      expect(share.message!.url, isNotNull);
    });

    testWidgets('a visitor shares the public card, and only that',
        (tester) async {
      final records = FakePlayerRecordAdapter(
        publicRecord: publicRecordOf(
          viewOf(),
          form: formOf([MatchOutcome.win, MatchOutcome.draw]),
        ),
      );
      final share = await pumpProfile(
        tester,
        asVisitor: true,
        records: records,
        // The authenticated port is present and must never be asked.
        profiles: FakeProfileAdapter(player: viewOf()),
      );

      expect(records.requestedPublicUserId, userId);
      expect(records.reads, 0,
          reason: 'a visitor never reaches the authenticated reads');

      await tester.tap(find.byTooltip('Share profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();

      // The card was composed from the public record and nothing else, so the
      // share cannot carry more than the visitor was shown.
      expect(
          share.message!.url, PublicLink.format(PublicLinkKind.player, userId));
    });

    testWidgets('a share is recorded with its type and where it came from',
        (tester) async {
      final analytics = FakeAnalyticsAdapter();
      ProductAnalytics.instance =
          ProductAnalytics(repository: AnalyticsRepository(analytics));
      addTearDown(() => ProductAnalytics.instance = ProductAnalytics());

      await pumpProfile(tester);
      await tester.tap(find.byTooltip('Share profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();

      final recorded = analytics.recorded.singleWhere(
        (event) => event.event == ProductEvent.shareUsed,
      );
      expect(recorded.shareType, ShareType.playerProfile);
      expect(recorded.source, ShareSource.playerProfile);
    });

    testWidgets('a dismissed sheet is not a share and records nothing',
        (tester) async {
      final analytics = FakeAnalyticsAdapter();
      ProductAnalytics.instance =
          ProductAnalytics(repository: AnalyticsRepository(analytics));
      addTearDown(() => ProductAnalytics.instance = ProductAnalytics());

      final share = await pumpProfile(tester);
      share.outcome = ShareOutcome.dismissed;

      await tester.tap(find.byTooltip('Share profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();

      expect(analytics.events, isNot(contains(ProductEvent.shareUsed)));
    });
  });

  group('the profile\'s content order', () {
    testWidgets('runs identity, career, form, highlight, statistics',
        (tester) async {
      await pumpProfile(
        tester,
        openUserId: null,
        profiles: FakeProfileAdapter(
          profile: const PlayerProfile(
            fullName: 'Salim Al Harthy',
            phone: '+96890123456',
            primaryPosition: PlayerPosition.def,
          ),
        ),
        records: FakePlayerRecordAdapter(
          form: formOf([MatchOutcome.win]),
          mvp: RecentHighlight(
            kind: HighlightKind.mvp,
            occurredAt: DateTime(2026, 9, 14),
            communityName: 'Al Amerat FC',
          ),
        ),
      );

      double topOf(Finder finder) => tester.getTopLeft(finder).dy;

      expect(
        // The career snapshot's own label, which the recent window
        // deliberately does not repeat.
        topOf(find.text('Matches played')),
        lessThan(topOf(find.text('Recent form'))),
      );
      expect(
        topOf(find.text('Recent form')),
        lessThan(topOf(find.text('Recent highlight'))),
      );
      expect(
        topOf(find.text('Recent highlight')),
        lessThan(topOf(find.text('My statistics'))),
      );
    });

    testWidgets('a player with no highlight gets no section, not an empty one',
        (tester) async {
      await pumpProfile(tester, records: FakePlayerRecordAdapter());

      expect(find.text('Recent form'), findsOneWidget);
      expect(find.text('Recent highlight'), findsNothing);
    });

    testWidgets('an empty form says so rather than drawing five blanks',
        (tester) async {
      await pumpProfile(tester);

      expect(find.text('Recent form'), findsOneWidget);
      expect(find.textContaining('No completed matches yet'), findsOneWidget);
      expect(find.text('W'), findsNothing);
    });

    testWidgets('a form summarises the same window it draws', (tester) async {
      await pumpProfile(
        tester,
        records: FakePlayerRecordAdapter(
          form: formOf(
            [
              MatchOutcome.win,
              MatchOutcome.loss,
              MatchOutcome.win,
              MatchOutcome.draw,
              MatchOutcome.win,
            ],
            goals: [1, 0, 2, 0, 1],
          ),
        ),
      );

      Finder inForm(Finder finder) => find.descendant(
            of: find.byType(RecentFormSection),
            matching: finder,
          );

      expect(inForm(find.text('W')), findsNWidgets(3));
      expect(inForm(find.text('D')), findsOneWidget);
      expect(inForm(find.text('L')), findsOneWidget);
      // The summary counts the same five the badges draw.
      expect(inForm(find.text('5')), findsOneWidget);
      expect(inForm(find.text('4')), findsOneWidget);
      expect(inForm(find.text('3')), findsOneWidget);
      expect(find.textContaining('last 5 completed matches'), findsOneWidget);
    });
  });
}

// --- fakes ------------------------------------------------------------------

/// A share service that remembers what it was handed.
class _Share implements ShareService {
  ShareCardImage? image;
  ShareMessage? message;
  ShareOutcome outcome = ShareOutcome.shared;

  /// What the platform would actually be given.
  String? get body => message?.body;

  @override
  Future<ShareOutcome> shareImage(
    ShareCardImage image, {
    Rect? origin,
    ShareMessage? message,
  }) async {
    this.image = image;
    this.message = message;
    return outcome;
  }
}

/// A renderer that composes nothing: these tests are about the payload and the
/// screen, and the real renderer has its own suite.
class _StubRenderer implements ShareCardRenderer {
  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async =>
      ShareCardImage(
        bytes: Uint8List.fromList(_pixel),
        pixelWidth: 1080,
        pixelHeight: 1920,
      );
}

/// A one-pixel PNG: the preview screen decodes whatever it is handed, and these
/// tests are about the payload rather than the picture.
const _pixel = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class FakeProfileAdapter implements ProfileAdapter {
  FakeProfileAdapter({this.profile, this.player, this.failure});

  final PlayerProfile? profile;
  final PlayerProfileView? player;
  final Failure? failure;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    if (failure != null) throw failure!;
    return profile!;
  }

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) async {
    if (failure != null) throw failure!;
    return player!;
  }

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) async {}

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) async {}

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) async {}

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) async =>
      '';

  @override
  Future<void> removeMyAvatar() async {}
}

class _FakeResultAdapter implements ResultAdapter {
  _FakeResultAdapter(this.statistics);

  final PlayerStatistics statistics;

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async => statistics;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeCommunityAdapter implements CommunityAdapter {
  @override
  Future<List<Community>> fetchMyCommunities() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubAuthAdapter implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
