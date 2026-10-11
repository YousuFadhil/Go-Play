import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/analytics/analytics_repository.dart';
import 'package:go_play/features/analytics/analytics_service.dart';
import 'package:go_play/features/sharing/match_invitation_share.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/infrastructure/platform/native_text_share_service.dart';
import 'package:share_plus/share_plus.dart';

import 'product_analytics_test.dart' show FakeAnalyticsAdapter;

void main() {
  const matchId = '11111111-2222-4333-8444-555555555555';
  late FakeAnalyticsAdapter analytics;
  setUp(() {
    analytics = FakeAnalyticsAdapter();
    ProductAnalytics.instance = ProductAnalytics(
      repository: AnalyticsRepository(analytics),
    );
  });
  tearDown(() => ProductAnalytics.instance = ProductAnalytics());

  Future<void> pumpInvitation(
    WidgetTester tester,
    Locale locale, {
    NativeTextShareService? service,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => MatchInvitationShare.present(
                context,
                matchId: matchId,
                title: 'Friday Football',
                location: 'Sohar Pitch',
                startAt: DateTime(2026, 10, 16, 20),
                endAt: DateTime(2026, 10, 16, 22),
                communityId: 'c1',
                source: 'test',
                shareService: service,
              ),
              child: const Text('share'),
            ),
          ),
        ),
      ),
    );
  }

  for (final code in ['en', 'ar']) {
    testWidgets(
      'real invitation path ($code) sends readable details, a CTA and one URL',
      (tester) async {
        final calls = <MethodCall>[];
        const channel = MethodChannel('dev.fluttercommunity.plus/share');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'dev.fluttercommunity.plus/share/unavailable';
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await pumpInvitation(tester, Locale(code));
        expect(calls, isEmpty);
        await tester.tap(find.text('share'));
        await tester.pumpAndSettle();
        expect(calls, hasLength(1));
        final args = Map<String, dynamic>.from(calls.single.arguments as Map);
        final message = args['text'] as String;
        expect(
            message,
            startsWith(code == 'ar'
                ? '⚽ ننتظرك في Friday Football!'
                : '⚽ Join us for Friday Football!'));
        expect(message, contains('📅 '));
        expect(message, contains('🕗 '));
        expect(message, contains('📍 Sohar Pitch'));
        expect(
            message,
            contains(code == 'ar'
                ? 'اضغط الرابط لعرض التفاصيل والانضمام إلى المباراة 👇'
                : 'Open the link to view the details and join the match 👇'));
        expect(
            message,
            endsWith(
              PublicLink.matchInvitation(matchId, languageCode: code),
            ));
        expect(RegExp(r'https?://\S+').allMatches(message), hasLength(1));
        expect(args['paths'], isNull);
        expect(args['mimeTypes'], isNull);
        expect(find.byType(ShareCardPreviewScreen), findsNothing);
        expect(analytics.events, [ProductEvent.shareUsed]);
        final recorded = analytics.recorded.single;
        expect(recorded.matchId, matchId);
        expect(recorded.communityId, 'c1');
        expect(recorded.shareType, ShareType.match);
        expect(recorded.source, 'test');
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'text payload contains exactly the URL and no file or separate URI',
    () async {
      ShareParams? captured;
      final url = PublicLink.matchInvitation(matchId);
      final outcome = await NativeTextShareService((params) async {
        captured = params;
        return const ShareResult('com.example', ShareResultStatus.success);
      }).shareText(url);
      expect(captured!.text, url);
      expect(captured!.files, isNull);
      expect(captured!.uri, isNull);
      expect(outcome, ShareOutcome.shared);
    },
  );

  testWidgets('dismissed invitations do not record a share', (tester) async {
    await pumpInvitation(
      tester,
      const Locale('en'),
      service: NativeTextShareService(
        (_) async => const ShareResult('', ShareResultStatus.dismissed),
      ),
    );
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(analytics.events, isEmpty);
  });

  test('a platform failure remains an infrastructure failure', () async {
    final service = NativeTextShareService((_) async => throw Exception('OS'));
    await expectLater(
      service.shareText('https://example.test/'),
      throwsA(isA<InfrastructureFailure>()),
    );
  });
}
