import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/analytics_adapter.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/sharing/match_invitation_share.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/infrastructure/platform/native_text_share_service.dart';
import 'package:share_plus/share_plus.dart';

typedef _Recorded = ({
  ProductEvent event,
  String? matchId,
  String? communityId,
  ShareType? shareType,
  String? source,
});

class _RecordingAnalytics implements AnalyticsAdapter {
  final recorded = <_Recorded>[];

  @override
  Future<void> record(
    ProductEvent event, {
    String? communityId,
    String? matchId,
    ShareType? shareType,
    String? source,
    String? targetUserId,
  }) async {
    recorded.add((
      event: event,
      matchId: matchId,
      communityId: communityId,
      shareType: shareType,
      source: source,
    ));
  }
}

void main() {
  const matchId = '11111111-2222-4333-8444-555555555555';

  late _RecordingAnalytics analytics;

  setUp(() {
    analytics = _RecordingAnalytics();
    ProductAnalytics.instance =
        ProductAnalytics(repository: AnalyticsRepository(analytics));
  });

  tearDown(() => ProductAnalytics.instance = ProductAnalytics());

  Future<BuildContext> contextIn(WidgetTester tester, Locale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    return captured;
  }

  group('the invitation link', () {
    test(
        'is the server preview route, with the sharer language when it is one we write',
        () {
      expect(
        PublicLink.matchInvitation(matchId, languageCode: 'en'),
        '${PublicLink.webBase}/share/match/$matchId?lang=en',
      );
      expect(
        PublicLink.matchInvitation(matchId, languageCode: 'ar'),
        '${PublicLink.webBase}/share/match/$matchId?lang=ar',
      );
      expect(
        PublicLink.matchInvitation(matchId, languageCode: 'AR'),
        endsWith('?lang=ar'),
      );
    });

    test('leaves the language off when it is absent or not one we write', () {
      final bare = '${PublicLink.webBase}/share/match/$matchId';
      expect(PublicLink.matchInvitation(matchId), bare);
      expect(PublicLink.matchInvitation(matchId, languageCode: 'fr'), bare);
      expect(PublicLink.matchInvitation(matchId, languageCode: ''), bare);
    });

    test('is https on the public web base and has no fragment', () {
      final uri =
          Uri.parse(PublicLink.matchInvitation(matchId, languageCode: 'en'));
      expect(uri.scheme, 'https');
      expect(uri.path, '/share/match/$matchId');
      expect(uri.fragment, isEmpty);
    });

    test('is read back by the app as the same match as the in-app route', () {
      const target = PublicLinkTarget(PublicLinkKind.match, matchId);
      expect(
        PublicLink.parse(
            PublicLink.matchInvitation(matchId, languageCode: 'ar')),
        target,
      );
      expect(PublicLink.parse(PublicLink.matchInvitation(matchId)), target);
      // ...and the route the preview page moves people on to is the existing one.
      expect(PublicLink.parse(PublicLink.format(PublicLinkKind.match, matchId)),
          target);
      expect(PublicLink.format(PublicLinkKind.match, matchId),
          endsWith('/#/match/$matchId'));
    });

    testWidgets('follows the language the screen is showing', (tester) async {
      final en = await contextIn(tester, const Locale('en'));
      expect(MatchInvitationShare.url(en, matchId: matchId),
          PublicLink.matchInvitation(matchId, languageCode: 'en'));
      final ar = await contextIn(tester, const Locale('ar'));
      expect(MatchInvitationShare.url(ar, matchId: matchId),
          PublicLink.matchInvitation(matchId, languageCode: 'ar'));
    });
  });

  group('sharing the invitation', () {
    testWidgets(
        'hands the text sheet exactly the link: no picture, no file, no extra words',
        (tester) async {
      ShareParams? captured;
      var calls = 0;
      final service = NativeTextShareService((params) async {
        calls++;
        captured = params;
        return const ShareResult('com.example', ShareResultStatus.success);
      });
      final context = await contextIn(tester, const Locale('en'));

      await MatchInvitationShare.share(
        context,
        matchId: matchId,
        source: 'match_details_screen',
        shareText: service.shareText,
      );

      expect(calls, 1, reason: 'one share action');
      expect(captured!.text,
          PublicLink.matchInvitation(matchId, languageCode: 'en'));
      expect(captured!.text, isNot(contains('\n')));
      expect(captured!.files, isNull);
      expect(captured!.uri, isNull);
      expect(captured!.subject, isNull);
    });

    testWidgets(
        'records the existing share_used event, once, with the match and source',
        (tester) async {
      final context = await contextIn(tester, const Locale('en'));

      await MatchInvitationShare.share(
        context,
        matchId: matchId,
        communityId: 'c1',
        source: 'create_match_screen',
        shareText: (_) async {},
      );
      await tester.pump();

      expect(analytics.recorded, [
        (
          event: ProductEvent.shareUsed,
          matchId: matchId,
          communityId: 'c1',
          shareType: ShareType.match,
          source: 'create_match_screen',
        ),
      ]);
    });

    testWidgets(
        'a sheet that could not be shown is thrown to the caller and is not recorded',
        (tester) async {
      final context = await contextIn(tester, const Locale('en'));
      final service = NativeTextShareService(
        (_) async => throw Exception('no share sheet'),
      );

      await expectLater(
        MatchInvitationShare.share(
          context,
          matchId: matchId,
          source: 'match_details_screen',
          shareText: service.shareText,
        ),
        throwsA(isA<InfrastructureFailure>()),
      );
      await tester.pump();

      expect(analytics.recorded, isEmpty);
    });
  });

  test('text sharing hands over a link, not an image or an app destination',
      () async {
    ShareParams? captured;
    await NativeTextShareService((params) async {
      captured = params;
      return const ShareResult('com.example', ShareResultStatus.success);
    }).shareText(PublicLink.matchInvitation(matchId, languageCode: 'en'));

    expect(captured!.text, contains('/share/match/$matchId'));
    expect(captured!.files, isNull);
    expect(captured!.uri, isNull);
  });
}
