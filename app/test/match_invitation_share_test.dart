import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/sharing/match_invitation_share.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/infrastructure/platform/native_text_share_service.dart';
import 'package:go_play/infrastructure/platform/native_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  const matchId = '11111111-2222-4333-8444-555555555555';

  Future<String> messageIn(WidgetTester tester, Locale locale) async {
    String? message;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        message = MatchInvitationShare.message(
          context,
          matchId: matchId,
          title: 'Friday Football',
          location: 'Sohar Pitch',
          startAt: DateTime(2026, 10, 16, 20),
          endAt: DateTime(2026, 10, 16, 22),
        );
        return const SizedBox();
      }),
    ));
    return message!;
  }

  testWidgets('English invitation includes the correct match and time',
      (tester) async {
    final message = await messageIn(tester, const Locale('en'));
    expect(message, contains("You're invited to a match on Go Play:"));
    expect(message, contains('Friday Football'));
    expect(message, contains('Sohar Pitch'));
    expect(message, contains('8:00'));
    expect(message, contains(PublicLink.format(PublicLinkKind.match, matchId)));
  });

  testWidgets('Arabic invitation retains the same destination', (tester) async {
    final message = await messageIn(tester, const Locale('ar'));
    expect(message, contains('دعوة إلى مباراة'));
    expect(message, contains('Sohar Pitch'));
    expect(message, contains(PublicLink.format(PublicLinkKind.match, matchId)));
  });

  test('text sharing hands over a link, not an image or an app destination',
      () async {
    ShareParams? captured;
    await NativeTextShareService((params) async {
      captured = params;
      return const ShareResult('com.example', ShareResultStatus.success);
    }).shareText('Join here: https://example.test/#/match/$matchId');

    expect(captured!.text, contains('/#/match/$matchId'));
    expect(captured!.files, isNull);
    expect(captured!.uri, isNull);
  });
  testWidgets('invitation picture shows the same match and venue',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Center(
          child: FittedBox(
            child: SizedBox(
              width: 1080,
              height: 1920,
              child: MatchInvitationCard(
                title: 'Friday Football',
                location: 'Sohar Pitch',
                startAt: DateTime(2026, 10, 16, 20),
                endAt: DateTime(2026, 10, 16, 22),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Friday Football'), findsOneWidget);
    expect(find.textContaining('Sohar Pitch'), findsOneWidget);
    expect(find.textContaining('8:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one share contains the invitation PNG and clickable match URL',
      (tester) async {
    final message = await messageIn(tester, const Locale('en'));
    ShareParams? captured;
    final service = NativeShareService((params) async {
      captured = params;
      return const ShareResult('com.example', ShareResultStatus.success);
    });
    await service.shareImage(
      ShareCardImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        pixelWidth: 1080,
        pixelHeight: 1920,
      ),
      message: ShareMessage(text: message),
    );
    expect(captured!.files, hasLength(1));
    expect(captured!.files!.single.mimeType, 'image/png');
    expect(captured!.text,
        contains(PublicLink.format(PublicLinkKind.match, matchId)));
    expect(captured!.uri, isNull);
  });

}
