import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/sharing/match_invitation_preview.dart';
import 'package:go_play/features/sharing/match_invitation_share.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/infrastructure/platform/native_text_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  const matchId = '11111111-2222-4333-8444-555555555555';
  final link = PublicLink.format(PublicLinkKind.match, matchId);

  test('invitation has the public match URL and nothing added to it', () {
    expect(MatchInvitationShare.link(matchId), link);
    expect(link, contains('/#/match/$matchId'));
  });

  test('the OS gets one PNG and the match URL in the same share', () async {
    ShareParams? captured;
    final preview = ShareCardImage(
      bytes: Uint8List.fromList(const [137, 80, 78, 71]),
      pixelWidth: 1080,
      pixelHeight: 1920,
      fileName: 'match-preview.png',
    );
    await NativeTextShareService((params) async {
      captured = params;
      return const ShareResult('com.example', ShareResultStatus.success);
    }).shareInvitation(link, preview);

    expect(captured, isNotNull);
    expect(captured!.files, hasLength(1));
    expect(captured!.text, link);
    expect(captured!.uri, isNull);
    expect(captured!.fileNameOverrides, ['match-preview.png']);
    expect(captured!.files!.single.mimeType, 'image/png');
  });

  test('an unavailable image-plus-link sheet is not called successful',
      () async {
    final service = NativeTextShareService((_) async =>
        const ShareResult('', ShareResultStatus.unavailable));
    final preview = ShareCardImage(
      bytes: Uint8List.fromList([1]),
      pixelWidth: 1080,
      pixelHeight: 1920,
    );
    await expectLater(
      service.shareInvitation(link, preview),
      throwsA(isA<Exception>()),
    );
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets('the invite preview contains its match facts in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: MatchInvitationPreview(
            title: 'Friday Football',
            location: 'Sohar Pitch',
            startAt: DateTime(2026, 10, 16, 20),
            endAt: DateTime(2026, 10, 16, 22),
          ),
        ),
      ));
      expect(find.text('Friday Football'), findsOneWidget);
      expect(find.textContaining('Sohar Pitch'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-preview-time')), findsOneWidget);
      expect(find.textContaining(link), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
