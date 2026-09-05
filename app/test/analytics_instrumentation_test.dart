import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:go_play/features/communities/join_community_flow.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';

import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

/// What the product actually records, and when.
///
/// The events that can be driven through a real screen are driven through one.
/// The rest are asserted against the instrumented source, and the group that
/// does so says why in each case — a screen that builds its own repository
/// cannot be given a fake one without changing the screen, and this cycle is
/// not permitted to restructure production code to make analytics observable.
void main() {
  late FakeAnalyticsAdapter analytics;

  setUp(() {
    analytics = FakeAnalyticsAdapter();
    ProductAnalytics.instance =
        ProductAnalytics(repository: AnalyticsRepository(analytics));
  });

  // Put the real one back, so a test that runs after these is not quietly
  // recording into a fake belonging to a finished test.
  tearDown(() => ProductAnalytics.instance = ProductAnalytics());

  final kickOff = DateTime.now().add(const Duration(days: 2));

  final match = Match(
    id: 'm1',
    communityId: 'c1',
    createdBy: 'u9',
    location: 'Al Amerat Pitch',
    startAt: kickOff,
    endAt: kickOff.add(const Duration(hours: 2)),
    startingPlayers: 10,
    maxRegistration: 16,
    status: MatchStatus.open,
    title: 'Friday Night',
  );

  Future<void> pumpMatch(
    WidgetTester tester,
    _FakeMatchAdapter matches, {
    Key? key,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MatchDetailsScreen(
        key: key ?? UniqueKey(),
        matchId: 'm1',
        matchService: MatchService(matches),
        memberRepository: MemberRepository(_FakeMemberAdapter()),
        communityRepository: CommunityRepository(_FakeCommunityAdapter()),
        // Injected so the screen builds no Supabase client of its own.
        authService: AuthService(_StubAuthAdapter()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('match_viewed', () {
    testWidgets('is recorded once, with the match and its community',
        (tester) async {
      await pumpMatch(tester, _FakeMatchAdapter(match: match));

      expect(analytics.events, [ProductEvent.matchViewed]);
      expect(analytics.recorded.single.matchId, 'm1');
      expect(analytics.recorded.single.communityId, 'c1');
    });

    testWidgets('a failed load records nothing', (tester) async {
      await pumpMatch(
        tester,
        _FakeMatchAdapter(match: match, readFailure: const NetworkFailure()),
      );

      expect(analytics.events, isEmpty);
    });

    testWidgets('a reload does not record a second view', (tester) async {
      // What a push arriving on an open match looks like: the screen re-reads
      // the roster. Nobody opened anything.
      final adapter = _FakeMatchAdapter(match: match);
      final key = UniqueKey();
      await pumpMatch(tester, adapter, key: key);
      await pumpMatch(tester, adapter, key: key);

      expect(analytics.events, [ProductEvent.matchViewed]);
    });
  });

  group('match_registered', () {
    testWidgets('is recorded after the registration really succeeds',
        (tester) async {
      final adapter = _FakeMatchAdapter(match: match);
      await pumpMatch(tester, adapter);
      analytics.recorded.clear();

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();

      expect(adapter.registrations1, 1);
      expect(analytics.events, [ProductEvent.matchRegistered]);
      expect(analytics.recorded.single.matchId, 'm1');
      expect(analytics.recorded.single.communityId, 'c1');
    });

    testWidgets('a refused registration records nothing', (tester) async {
      final adapter = _FakeMatchAdapter(
        match: match,
        registerFailure: const ConflictFailure(),
      );
      await pumpMatch(tester, adapter);
      analytics.recorded.clear();

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();

      expect(analytics.events, isEmpty);
    });
  });

  group('match_withdrawn', () {
    testWidgets('is recorded after the withdrawal really succeeds',
        (tester) async {
      // Registered already, so the screen offers Withdraw.
      final adapter = _FakeMatchAdapter(
        match: match,
        registrations: [
          const MatchRegistration(
            registrationId: 'r1',
            userId: 'me',
            fullName: 'Me',
            status: RegistrationStatus.confirmed,
            registrationOrder: 1,
          ),
        ],
      );
      await pumpMatch(tester, adapter);
      analytics.recorded.clear();

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      // The confirmation, which is where a withdrawal actually begins.
      await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
      await tester.pumpAndSettle();

      expect(adapter.withdrawals, 1);
      expect(analytics.events, [ProductEvent.matchWithdrawn]);
      expect(analytics.recorded.single.matchId, 'm1');
    });
  });

  group('share_used', () {
    Future<void> pumpPreview(WidgetTester tester, ShareService share) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ShareCardPreviewScreen(
          image: _blankCard,
          matchId: 'm1',
          communityId: 'c1',
          shareService: share,
          downloader: (_) async => true,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
    }

    testWidgets('a completed share is recorded', (tester) async {
      await pumpPreview(tester, _FakeShareService(ShareOutcome.shared));

      expect(analytics.events, [ProductEvent.shareUsed]);
      expect(analytics.recorded.single.matchId, 'm1');
      expect(analytics.recorded.single.communityId, 'c1');
    });

    testWidgets('a dismissed sheet is not', (tester) async {
      // The reader opened the sheet and changed their mind. Nothing was shared.
      await pumpPreview(tester, _FakeShareService(ShareOutcome.dismissed));

      expect(analytics.events, isEmpty);
    });

    testWidgets('an outcome the platform cannot report is', (tester) async {
      // Android's usual answer: an app was chosen, and what it did next is not
      // knowable. Handing the picture over is the closest true statement.
      await pumpPreview(tester, _FakeShareService(ShareOutcome.unknown));

      expect(analytics.events, [ProductEvent.shareUsed]);
    });

    testWidgets('a sheet that could not be shown at all is not', (tester) async {
      await pumpPreview(tester, _FakeShareService(null));

      expect(analytics.events, isEmpty);
    });
  });

  group('community_joined', () {
    Future<void> pumpJoin(
      WidgetTester tester,
      CommunityRepository repository,
    ) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => runJoinCommunity(
                context,
                repository: repository,
                communityId: 'c1',
              ),
              child: const Text('join'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('join'));
      await tester.pumpAndSettle();
    }

    testWidgets('a real join is recorded, with the community', (tester) async {
      await pumpJoin(
        tester,
        CommunityRepository(_FakeCommunityAdapter(joinResult: 'c1')),
      );

      expect(analytics.events, [ProductEvent.communityJoined]);
      expect(analytics.recorded.single.communityId, 'c1');
    });

    testWidgets('being a member already is not a join', (tester) async {
      await pumpJoin(
        tester,
        CommunityRepository(
          _FakeCommunityAdapter(joinFailure: const ConflictFailure(
            FailureReason.alreadyMember,
          )),
        ),
      );

      // The reader is told they are already a member, and the figure stays a
      // count of people who joined something rather than of buttons pressed.
      expect(analytics.events, isEmpty);
    });

    testWidgets('a failed join is not', (tester) async {
      await pumpJoin(
        tester,
        CommunityRepository(
          _FakeCommunityAdapter(joinFailure: const NetworkFailure()),
        ),
      );

      expect(analytics.events, isEmpty);
    });
  });

  /// The four events whose screens build their own repositories.
  ///
  /// `CreateCommunityScreen` constructs a `CommunityRepository()` outright, and
  /// `CommunityDetailsScreen`, `TeamsScreen` and `FootballMatchScreen` each
  /// need four to six ports stood up before they will build. Driving them here
  /// would mean either changing production code to accept a fake — which this
  /// cycle must not do for the sake of a measurement — or reimplementing most
  /// of the data layer in a test file.
  ///
  /// So what is checked is the instrumentation contract: that the event is
  /// recorded at the right place, under the right condition, and nowhere else.
  group('the instrumented call sites', () {
    String read(String path) => File('lib/$path').readAsStringSync();

    test('community_created is recorded after the community exists', () {
      final source = read('features/communities/create_community_screen.dart');
      // After the await that creates it, and before the screen closes.
      expect(
        source.indexOf('await _communityRepository.createCommunity'),
        lessThan(source.indexOf('ProductEvent.communityCreated')),
      );
      expect(source, contains('communityId: communityId'));
      expect(
        source.indexOf('ProductEvent.communityCreated'),
        lessThan(source.indexOf('Navigator.of(context).pop(true)')),
      );
    });

    test('community_viewed is recorded once, after a successful load', () {
      final source =
          read('features/communities/community_details_screen.dart');
      expect(source, contains('if (!_viewRecorded) {'));
      expect(source, contains('ProductEvent.communityViewed'));
      // Inside `_loadData`, after the awaited reads -- so a load that threw
      // never reaches it.
      expect(
        source.indexOf('await Future.wait'),
        lessThan(source.indexOf('ProductEvent.communityViewed')),
      );
    });

    test('teams_viewed is recorded once, from the successful load only', () {
      final source = read('features/teams/teams_screen.dart');
      expect(source, contains('if (!_viewRecorded) {'));
      expect(source, contains('ProductEvent.teamsViewed'));
      // `_recordViews` is called from `_track`'s success callback, never from
      // its `onError`.
      expect(source, contains('_recordViews(view);'));
      expect(
        source.indexOf('_recordViews(view);'),
        lessThan(source.indexOf('onError:')),
      );
    });

    test('result_viewed is recorded only when a result exists', () {
      // The Teams screen: a match with no recorded result loads a null.
      final teams = read('features/teams/teams_screen.dart');
      expect(
        teams,
        contains('if (!_resultViewRecorded && view.result != null) {'),
      );

      // The public completed-match screen: `hasResult` is the same question.
      final football = read('features/football/football_match_screen.dart');
      expect(
        football,
        contains('if (_resultViewRecorded || !view.detail.match.hasResult) return;'),
      );
    });

    test('entering result entry is not viewing a result', () {
      // The one confusion this event invites. The entry form records nothing.
      final entry = read('features/results/result_entry_screen.dart');
      expect(entry, isNot(contains('ProductEvent')));
      expect(entry, isNot(contains('ProductAnalytics')));
    });
  });

  group('nothing beyond the approved ten is instrumented', () {
    test('no screen writes a raw event name', () {
      // The enum carries the wire value. A screen that typed one would be able
      // to invent an eleventh event, or misspell an approved one.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.contains('analytics')) continue;
        final source = file.readAsStringSync();
        for (final event in ProductEvent.values) {
          if (source.contains("'${event.wireName}'")) {
            offenders.add('${file.path}: ${event.wireName}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('every approved event is instrumented somewhere', () {
      final instrumented = <ProductEvent>{};
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // The enum's own declaration is not an instrumentation site.
        if (file.path.endsWith('analytics_models.dart')) continue;
        final source = file.readAsStringSync();
        for (final event in ProductEvent.values) {
          if (source.contains('ProductEvent.${event.name}')) {
            instrumented.add(event);
          }
        }
      }
      expect(instrumented, ProductEvent.values.toSet());
    });

    test('no analytics call is awaited by a product flow', () {
      // `track` returns void, so this cannot compile anyway -- asserted so the
      // day somebody makes it return a Future, the reason it did not is here.
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('await ProductAnalytics')),
          reason: '${file.path} waits for a measurement',
        );
      }
    });
  });
}

/// A stand-in card. The preview renders it with `Image.memory`, so the bytes
/// have to be a real PNG rather than nonsense -- this is one transparent pixel.
final _blankCard = ShareCardImage(
  bytes: Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]),
  pixelWidth: 1,
  pixelHeight: 1,
);

/// A signed-in identity that reaches nothing.
class _StubAuthAdapter implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => 'me';

  @override
  String? get currentUserEmail => null;

  @override
  Stream<bool> get signedInChanges => const Stream<bool>.empty();

  @override
  Future<String?> fetchCurrentUserFullName() async => null;

  @override
  Future<bool> isCurrentUserActive() async => true;

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) => throw UnimplementedError();
}

class _FakeShareService implements ShareService {
  _FakeShareService(this.outcome);

  /// Null means the sheet could not be shown at all.
  final ShareOutcome? outcome;

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    final result = outcome;
    if (result == null) throw const InfrastructureFailure();
    return result;
  }
}

class _FakeMemberAdapter implements MemberAdapter {
  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async =>
      CommunityRole.player;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async =>
      const [];

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();

  @override
  Future<void> removeMember(String communityId, String userId) =>
      throw UnimplementedError();
}

class _FakeCommunityAdapter implements CommunityAdapter {
  _FakeCommunityAdapter({this.joinResult, this.joinFailure});

  final String? joinResult;
  final Failure? joinFailure;

  @override
  Future<String> joinCommunity(String communityId) async {
    if (joinFailure != null) throw joinFailure!;
    return joinResult ?? communityId;
  }

  @override
  Future<String> joinCommunityByCode(String code) async {
    if (joinFailure != null) throw joinFailure!;
    return joinResult ?? 'c1';
  }

  @override
  Future<Community> fetchCommunity(String communityId) async => Community(
        id: communityId,
        ownerId: 'u9',
        name: 'Al Amerat FC',
        joinPolicy: JoinPolicy.open,
      );

  @override
  Future<List<Community>> fetchMyCommunities() async => const [];

  @override
  Future<List<Community>> fetchAllCommunities() async => const [];

  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setJoinPolicy(
    String communityId, {
    required JoinPolicy joinPolicy,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> fetchJoinCode(String communityId) =>
      throw UnimplementedError();

  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      throw UnimplementedError();

  @override
  Future<String> regenerateJoinCode(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) =>
      throw UnimplementedError();
}

class _FakeMatchAdapter implements MatchAdapter {
  _FakeMatchAdapter({
    required this.match,
    this.readFailure,
    this.registerFailure,
    this.registrations = const [],
  });

  final Match match;
  final Failure? readFailure;
  final Failure? registerFailure;
  final List<MatchRegistration> registrations;

  int registrations1 = 0;
  int withdrawals = 0;

  @override
  Future<Match> fetchMatch(String matchId) async {
    if (readFailure != null) throw readFailure!;
    return match;
  }

  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) async =>
      const MatchAccessContext(matchExists: true, isMember: true);

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) async {
    if (registerFailure != null) throw registerFailure!;
    registrations1++;
    return RegistrationStatus.confirmed;
  }

  @override
  Future<void> withdrawFromMatch(String matchId) async => withdrawals++;

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchUpcomingMatches() => throw UnimplementedError();

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    bool isHistorical = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMatch(String matchId) => throw UnimplementedError();

  @override
  Future<void> setRosterOrder(String matchId, List<String> registrationIds) =>
      throw UnimplementedError();

  @override
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> removePlayer(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<String> addProfessionalGuest(String matchId, String name) =>
      throw UnimplementedError();

  @override
  Future<void> removeProfessionalGuest(String matchId, String guestId) =>
      throw UnimplementedError();

  @override
  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) =>
      throw UnimplementedError();

  @override
  Future<int?> fetchReservePlayers() => throw UnimplementedError();
}
