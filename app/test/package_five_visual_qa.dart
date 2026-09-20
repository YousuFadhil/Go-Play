// Renders real PNGs of the Package 5 surfaces, for visual review.
//
//   flutter test test/package_five_visual_qa.dart
//
// Not a `*_test.dart` file on purpose: it asserts almost nothing and exists to
// produce pictures, which is the only way to review a visual change. The files
// land in `build/visual_qa/` — inside the build directory, so nothing here is
// ever committed.
//
// Fonts: flutter_test's default font draws every glyph as a box, so Arabic
// would say nothing. Segoe UI and the Material icon font are registered from
// the machine and named by a `DefaultTextStyle` around each shot.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/features/discover/discover_tabs.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/discover/public_match_screen.dart';
import 'package:go_play/features/profile/player_profile_share_card.dart';
import 'package:go_play/features/profile/player_record_models.dart';
import 'package:go_play/features/profile/player_record_repository.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';

import 'player_record_fakes.dart';

const _userId = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _longEnglish = 'Abdulrahman Mohammed Al Balushi Al Hinai Al Amerat';
const _longArabic = 'عبد الرحمن محمد البلوشي الهنائي من العامرات';
const _arabicName = 'نور الكندي';
const _avatar = 'https://example.test/face.png';

final _out = Directory('build/visual_qa');

void main() {
  setUpAll(() async {
    _out.createSync(recursive: true);
    await _loadFonts();
    HttpOverrides.global = _FaceOverrides(await _face());
  });

  tearDownAll(() => HttpOverrides.global = null);

  // The screens, at the three widths the brief names, in both languages.
  for (final (locale, name, long) in [
    (const Locale('en'), 'Noor Al Kindi', _longEnglish),
    (const Locale('ar'), _arabicName, _longArabic),
  ]) {
    final tag = locale.languageCode;

    for (final width in [320.0, 412.0, 480.0]) {
      testWidgets('profile-own $tag $width', (tester) async {
        await _shoot(
          tester,
          'profile-own-$tag-${width.toInt()}',
          locale: locale,
          width: width,
          child: _ownProfile(fullName: name),
        );
      });

      testWidgets('profile-public $tag $width', (tester) async {
        await _shoot(
          tester,
          'profile-public-$tag-${width.toInt()}',
          locale: locale,
          width: width,
          child: _publicProfile(fullName: name),
        );
      });

      testWidgets('match-public $tag $width', (tester) async {
        await _shoot(
          tester,
          'match-public-$tag-${width.toInt()}',
          locale: locale,
          width: width,
          child: _publicMatch(),
        );
      });

      // Discover, both readers, all three tabs: the surface the approved
      // direction is really about.
      for (final (signedIn, who) in [(false, 'guest'), (true, 'member')]) {
        for (final (index, tab) in [
          (0, 'upcoming'),
          (1, 'results'),
          (2, 'communities'),
        ]) {
          testWidgets('discover-$who-$tab $tag $width', (tester) async {
            await _shoot(
              tester,
              'discover-$who-$tab-$tag-${width.toInt()}',
              locale: locale,
              width: width,
              child: _discover(signedIn: signedIn),
              openTab: index,
            );
          });
        }
      }

      testWidgets('community-public $tag $width', (tester) async {
        await _shoot(
          tester,
          'community-public-$tag-${width.toInt()}',
          locale: locale,
          width: width,
          child: _publicCommunity(),
        );
      });
    }

    // The states the brief lists, at the middle width.
    testWidgets('profile states $tag', (tester) async {
      await _shoot(
        tester,
        'profile-own-$tag-long-name',
        locale: locale,
        width: 412,
        child: _ownProfile(fullName: long, avatarUrl: null),
      );
      await _shoot(
        tester,
        'profile-own-$tag-no-avatar-no-form',
        locale: locale,
        width: 412,
        child: _ownProfile(
          fullName: name,
          avatarUrl: null,
          form: RecentForm.empty,
          highlight: null,
          statistics: _emptyStats(),
        ),
      );
      await _shoot(
        tester,
        'profile-own-$tag-mvp-highlight',
        locale: locale,
        width: 412,
        child: _ownProfile(fullName: name, highlight: _mvpHighlight()),
      );
      await _shoot(
        tester,
        'profile-public-$tag-two-results',
        locale: locale,
        width: 412,
        child: _publicProfile(
          fullName: name,
          form: formOf([MatchOutcome.win, MatchOutcome.loss]),
          highlight: null,
        ),
      );
      await _shoot(
        tester,
        'match-public-$tag-no-result',
        locale: locale,
        width: 412,
        child: _publicMatch(hasResult: false),
      );
    });

    // The card, at the size it is actually composed at.
    testWidgets('share card $tag', (tester) async {
      for (final (label, data) in [
        ('full', _card(fullName: name)),
        ('long-name', _card(fullName: long, avatarUrl: null)),
        ('no-avatar', _card(fullName: name, avatarUrl: null)),
        (
          'no-form',
          _card(fullName: name, form: RecentForm.empty, highlight: null)
        ),
      ]) {
        await _shootCard(tester, 'card-$tag-$label',
            locale: locale, data: data);
      }
    });
  }
}

// --- what the screens are given ---------------------------------------------

PlayerStatistics _stats() => const PlayerStatistics(
      userId: _userId,
      matchesPlayed: 24,
      wins: 16,
      losses: 6,
      draws: 2,
      goals: 18,
      mvpCount: 7,
      currentRating: 7.8,
    );

PlayerStatistics _emptyStats() => const PlayerStatistics.none(_userId, 5.0);

RecentForm _form() => formOf(
      [
        MatchOutcome.win,
        MatchOutcome.win,
        MatchOutcome.draw,
        MatchOutcome.loss,
        MatchOutcome.win,
      ],
      goals: [2, 1, 0, 0, 1],
      scores: [(2, 1), (3, 0), (1, 1), (0, 2), (4, 1)],
    );

RecentHighlight _highlight() => RecentHighlight(
      kind: HighlightKind.teamOfPeriod,
      period: HighlightPeriod.week,
      periodKey: '2026-W37',
      occurredAt: DateTime.utc(2026, 9, 13, 19, 59, 59),
      communityName: 'Al Seeb Community',
    );

RecentHighlight _mvpHighlight() => RecentHighlight(
      kind: HighlightKind.mvp,
      occurredAt: DateTime.utc(2026, 9, 11, 13),
      communityName: 'Al Seeb Community',
    );

PlayerProfileCardData _card({
  required String fullName,
  String? avatarUrl = _avatar,
  RecentForm? form,
  RecentHighlight? highlight = const _KeepHighlight(),
}) =>
    PlayerProfileCardData(
      fullName: fullName,
      avatarUrl: avatarUrl,
      primaryPosition: PlayerPosition.mid,
      rating: 7.8,
      matchesPlayed: 24,
      goals: 18,
      mvpCount: 7,
      wins: 16,
      losses: 6,
      draws: 2,
      form: form ?? _form(),
      highlight: highlight is _KeepHighlight ? _highlight() : highlight,
      publicUrl: 'https://go-play-staging.pages.dev/#/player/$_userId',
    );

/// A sentinel meaning "the ordinary highlight", so a caller can ask for none.
class _KeepHighlight implements RecentHighlight {
  const _KeepHighlight();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _ownProfile({
  required String fullName,
  String? avatarUrl = _avatar,
  RecentForm? form,
  RecentHighlight? highlight = const _KeepHighlight(),
  PlayerStatistics? statistics,
}) =>
    ProfileScreen(
      profileRepository: ProfileRepository(_Profiles(
        profile: PlayerProfile(
          fullName: fullName,
          phone: '+96890123456',
          primaryPosition: PlayerPosition.mid,
          secondaryPosition: PlayerPosition.fwd,
          dateOfBirth: DateTime(1992, 3, 10),
          avatarUrl: avatarUrl,
        ),
      )),
      resultRepository: ResultRepository(_Results(statistics ?? _stats())),
      playerRecordRepository: PlayerRecordRepository(FakePlayerRecordAdapter(
        form: form ?? _form(),
        teamOfPeriod: highlight is _KeepHighlight ? _highlight() : highlight,
      )),
      authService: AuthService(_Auth()),
    );

Widget _publicProfile({
  required String fullName,
  String? avatarUrl = _avatar,
  RecentForm? form,
  RecentHighlight? highlight = const _KeepHighlight(),
}) =>
    ProfileScreen(
      userId: _userId,
      asVisitor: true,
      profileRepository: ProfileRepository(_Profiles()),
      playerRecordRepository: PlayerRecordRepository(FakePlayerRecordAdapter(
        publicRecord: publicRecordOf(
          PlayerProfileView(
            userId: _userId,
            fullName: fullName,
            primaryPosition: PlayerPosition.mid,
            secondaryPosition: PlayerPosition.fwd,
            avatarUrl: avatarUrl,
            statistics: _stats(),
            isSelf: false,
          ),
          form: form ?? _form(),
          highlight: highlight is _KeepHighlight ? _highlight() : highlight,
        ),
      )),
    );

Widget _discover({required bool signedIn}) => DiscoverScreen(
      repository: DiscoverRepository(_Discover(hasResult: true)),
      authService: AuthService(_Auth(signedIn: signedIn)),
      // A signed-in Discover reads its own football history and the reader's
      // memberships. Supplied so the member shots show real results rather
      // than the failure state the real ports would produce in a test.
      footballRepository: signedIn ? FootballRepository(_Football()) : null,
      communityRepository: signedIn ? CommunityRepository(_Joined()) : null,
    );

Widget _publicCommunity() => PublicCommunityScreen(
      communityId: 'c1',
      repository: DiscoverRepository(_Discover(hasResult: true)),
      authService: AuthService(_Auth()),
    );

Widget _publicMatch({bool hasResult = true}) => PublicMatchScreen(
      matchId: 'm1',
      repository: DiscoverRepository(_Discover(hasResult: hasResult)),
      authService: AuthService(_Auth()),
    );

// --- the harness ------------------------------------------------------------

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required Locale locale,
  required double width,
  required Widget child,
  /// Which Discover tab to open before the shot, or null for screens that
  /// have none.
  int? openTab,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    // The theme sets the family, because Material re-states the default text
    // style from `theme.textTheme` below every Scaffold -- an outer
    // `DefaultTextStyle` would be overridden by it and every glyph would draw
    // as a box.
    theme: _withFont(buildAppTheme()),
    debugShowCheckedModeBanner: false,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: RepaintBoundary(key: key, child: child),
  ));
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
  await tester.pumpAndSettle();

  if (openTab != null && openTab > 0) {
    final tab = find
        .descendant(of: find.byType(DiscoverTabs), matching: find.byType(Tab))
        .at(openTab);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  await _save(tester, key, name);
}

/// The app's own theme, drawn in a font this machine actually has.
ThemeData _withFont(ThemeData theme) {
  ButtonStyle named(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(
          (style?.textStyle?.resolve(const {}) ?? const TextStyle())
              .copyWith(fontFamily: 'Segoe UI'),
        ),
      );

  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Segoe UI'),
    // The bar captured its title style from the *unpatched* text theme when
    // the theme was built, so patching `textTheme` alone left every app-bar
    // title drawing as boxes -- an artefact of this harness, never of the app.
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle:
          theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Segoe UI'),
      toolbarTextStyle:
          theme.appBarTheme.toolbarTextStyle?.copyWith(fontFamily: 'Segoe UI'),
    ),
    // A button draws its label from its own theme rather than from the text
    // theme, so the family has to be said again here.
    filledButtonTheme:
        FilledButtonThemeData(style: named(theme.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: named(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: named(theme.textButtonTheme.style)),
  );
}

Future<void> _shootCard(
  WidgetTester tester,
  String name, {
  required Locale locale,
  required PlayerProfileCardData data,
}) async {
  tester.view.physicalSize = const Size(2400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    debugShowCheckedModeBanner: false,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: key,
        // Inside the surface, because the card engine states its own default
        // text style -- deliberately, so a card never takes a colour from the
        // reader's theme. Merging under it names a font without touching that.
        child: ShareCardSurface(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Segoe UI'),
            child: PlayerProfileShareCard(data: data),
          ),
        ),
      ),
    ),
  ));
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
  await tester.pumpAndSettle();

  // Half scale: 1080x1920 at full size is a large file and the review is of
  // the composition, not of the pixels.
  await _save(tester, key, name, pixelRatio: 0.5);
}

Future<void> _save(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  double pixelRatio = 2,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${_out.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadFonts() async {
  const windows = r'C:\Windows\Fonts';
  final loader = FontLoader('Segoe UI');
  for (final face in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
    final file = File('$windows\\$face');
    if (file.existsSync()) {
      loader.addFont(Future.value(ByteData.view(
        Uint8List.fromList(file.readAsBytesSync()).buffer,
      )));
    }
  }
  await loader.load();

  final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\yousi\flutter'}'
      r'\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(
        Uint8List.fromList(icons.readAsBytesSync()).buffer,
      )));
    await iconLoader.load();
  }
}

/// A face for the avatars: generated, so nothing is fetched and every run
/// produces the same picture.
Future<Uint8List> _face() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = 320.0;
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, size, size),
    Paint()..color = const Color(0xFF2E6B45),
  );
  canvas.drawCircle(
    const Offset(size / 2, size * 0.38),
    size * 0.18,
    Paint()..color = const Color(0xFFE9C9A8),
  );
  canvas.drawOval(
    const Rect.fromLTWH(size * 0.18, size * 0.6, size * 0.64, size * 0.5),
    Paint()..color = const Color(0xFFE9C9A8),
  );
  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

class _FaceOverrides extends HttpOverrides {
  _FaceOverrides(this.bytes);

  final Uint8List bytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FaceClient(bytes);
}

class _FaceClient implements HttpClient {
  _FaceClient(this.bytes);

  final Uint8List bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FaceRequest(bytes, url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FaceRequest(bytes, url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FaceRequest implements HttpClientRequest {
  _FaceRequest(this.bytes, this.uri);

  final Uint8List bytes;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FaceHeaders();

  @override
  Future<HttpClientResponse> close() async => _FaceResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FaceHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FaceResponse implements HttpClientResponse {
  _FaceResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// --- ports ------------------------------------------------------------------

class _Profiles implements ProfileAdapter {
  _Profiles({this.profile});

  final PlayerProfile? profile;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile!;

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

/// A member's football history: three played matches with results.
class _Football implements FootballAdapter {
  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 5,
  }) async =>
      [
        for (var index = 0; index < 3; index++)
          CompletedMatch(
            matchId: 'f$index',
            communityId: 'c1',
            communityName: 'Al Seeb Community',
            location: 'Al Seeb Sports Complex',
            startAt: DateTime.utc(2026, 9, 11 - index, 15),
            endAt: DateTime.utc(2026, 9, 11 - index, 17),
            title: 'Friday football',
            isHistorical: false,
            hasResult: true,
            teamAScore: 3,
            teamBScore: 2,
            mvp: const FootballParticipant(
              type: ParticipantType.user,
              displayName: 'Noor Al Kindi',
              userId: _userId,
              avatarUrl: _avatar,
            ),
          ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The one community the reader is in.
class _Joined implements CommunityAdapter {
  @override
  Future<List<Community>> fetchMyCommunities() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth implements AuthAdapter {
  _Auth({this.signedIn = true});

  final bool signedIn;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentUserId => signedIn ? _userId : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Discover implements DiscoverAdapter {
  _Discover({required this.hasResult});

  final bool hasResult;

  static const _community = PublicCommunity(
    id: 'c1',
    name: 'Al Seeb Community',
    description: 'Five-a-side every Friday evening at Al Seeb Sports Complex.',
    memberCount: 24,
    upcomingMatchCount: 3,
  );

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async =>
      [
        for (final (index, title) in [
          'Friday five-a-side',
          'Sunday seven-a-side',
          'Midweek football',
        ].indexed)
          PublicMatch(
            id: 'up$index',
            communityId: 'c1',
            communityName: _community.name,
            title: title,
            location: 'Al Seeb Sports Complex',
            startAt: DateTime.utc(2026, 9, 25 + index, 15),
            endAt: DateTime.utc(2026, 9, 25 + index, 17),
            startingPlayers: 10,
            openSlots: index,
          ),
      ];

  @override
  Future<List<PublicCommunity>> fetchCommunities() async => [
        _community,
        const PublicCommunity(
          id: 'c2',
          name: 'Muscat United',
          memberCount: 18,
          upcomingMatchCount: 1,
        ),
      ];

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async =>
      _community;

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async =>
      [
        for (var index = 0; index < 5; index++)
          PublicResult(
            matchId: 'r$index',
            communityId: 'c1',
            communityName: _community.name,
            title: 'Friday football',
            location: 'Al Seeb Sports Complex',
            startAt: DateTime.utc(2026, 9, 11 - index, 15),
            teamAScore: 3,
            teamBScore: 2,
            mvpDisplayName: 'Noor Al Kindi',
            mvpAvatarUrl: _avatar,
          ),
      ];

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
        hasResult: hasResult,
        teamAScore: hasResult ? 3 : null,
        teamBScore: hasResult ? 2 : null,
        mvpDisplayName: hasResult ? 'Noor Al Kindi' : null,
        mvpAvatarUrl: hasResult ? _avatar : null,
        lineup: const [],
      );

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async => [
        const PublicLineupEntry(
          team: 'A',
          assignedPosition: 'GK',
          displayName: 'Salim Al Harthy',
          playerId: 'p1',
          goals: 0,
          isMvp: false,
          isProfessionalGuest: false,
        ),
        const PublicLineupEntry(
          team: 'A',
          assignedPosition: 'MID',
          displayName: 'Noor Al Kindi',
          avatarUrl: _avatar,
          playerId: _userId,
          goals: 2,
          isMvp: true,
          isProfessionalGuest: false,
        ),
        const PublicLineupEntry(
          team: 'A',
          assignedPosition: 'FWD',
          displayName: 'Yousef Al Balushi',
          goals: 1,
          isMvp: false,
          isProfessionalGuest: false,
        ),
        const PublicLineupEntry(
          team: 'B',
          assignedPosition: 'GK',
          displayName: 'Hamed Al Riyami',
          playerId: 'p4',
          goals: 0,
          isMvp: false,
          isProfessionalGuest: false,
        ),
        const PublicLineupEntry(
          team: 'B',
          assignedPosition: 'DEF',
          displayName: 'Khalid',
          goals: 0,
          isMvp: false,
          isProfessionalGuest: true,
        ),
        const PublicLineupEntry(
          team: 'B',
          assignedPosition: 'FWD',
          displayName: 'Ahmed Al Rashdi',
          playerId: 'p6',
          goals: 2,
          isMvp: false,
          isProfessionalGuest: false,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
