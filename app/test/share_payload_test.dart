import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/analytics/analytics_models.dart';
import 'package:go_play/features/sharing/public_link.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/infrastructure/platform/native_share_service.dart';
import 'package:share_plus/share_plus.dart';

/// The share payload: image, localized text, public URL — and what is recorded
/// about it.
///
/// The composition is asserted here rather than only through a screen, because
/// it is one rule that five surfaces depend on: the link goes on its own line
/// after a blank one, or the messaging apps that auto-link a bare URL at a line
/// ending will not.
void main() {
  ShareCardImage card() => ShareCardImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        pixelWidth: 1080,
        pixelHeight: 1920,
      );

  group('composing the message', () {
    test('words and a link arrive as two blocks', () {
      const message = ShareMessage(
        text: 'My player profile on Go Play.',
        url: 'https://example.test/#/player/x',
      );
      expect(
        message.body,
        'My player profile on Go Play.\n\nhttps://example.test/#/player/x',
      );
    });

    test('a card with no public address carries the words alone', () {
      // A team lineup has no public URL, and a message without one is complete
      // rather than broken.
      const message = ShareMessage(text: 'The lineup on Go Play.');
      expect(message.body, 'The lineup on Go Play.');
    });

    test('an empty or blank url is the same as none', () {
      for (final url in ['', '   ']) {
        expect(ShareMessage(text: 'Words.', url: url).body, 'Words.');
      }
    });

    test('a link with no words is still a link', () {
      const message = ShareMessage(text: '', url: 'https://example.test/');
      expect(message.body, 'https://example.test/');
    });
  });

  group('handing it to the operating system', () {
    test('the sheet is given the picture and the composed body', () async {
      ShareParams? captured;
      final service = NativeShareService((params) async {
        captured = params;
        return const ShareResult('com.example', ShareResultStatus.success);
      });

      final outcome = await service.shareImage(
        card(),
        message: const ShareMessage(
          text: 'Words.',
          url: 'https://example.test/#/match/x',
        ),
      );

      expect(outcome, ShareOutcome.shared);
      expect(captured!.files, hasLength(1));
      expect(captured!.text, 'Words.\n\nhttps://example.test/#/match/x');
    });

    test('an image-only share is unchanged, and still sends no text', () async {
      // The behaviour every card had before Package 5. A caller with nothing to
      // say hands over exactly what it handed over before.
      ShareParams? captured;
      final service = NativeShareService((params) async {
        captured = params;
        return const ShareResult('com.example', ShareResultStatus.success);
      });

      await service.shareImage(card());

      expect(captured!.files, hasLength(1));
      expect(captured!.text, isNull);
    });

    test('no destination is ever named', () async {
      // The product decision is that Go Play does not integrate with messaging
      // apps: the sheet lists what the reader has. There is no target
      // parameter and no place for one.
      // Comment lines removed, so an assertion about what the port *does* is
      // never satisfied — or defeated — by prose describing what it does not.
      // The port's own documentation names `shareToWhatsApp` precisely to say
      // there is no such thing.
      final code = File('lib/features/sharing/share_service.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final app in ['WhatsApp', 'Instagram', 'Snapchat', 'Telegram']) {
        expect(code, isNot(contains(app)));
      }
      expect(code, isNot(contains('shareTo')));
    });
  });

  group('what a share is recorded as', () {
    test('every approved share type has a wire name the database accepts', () {
      const approved = {
        ShareType.playerProfile: 'player_profile',
        ShareType.playerStatistics: 'player_statistics',
        ShareType.community: 'community',
        ShareType.match: 'match',
        ShareType.lineup: 'lineup',
        ShareType.result: 'result',
      };
      expect(ShareType.values.length, approved.length);
      approved.forEach((type, wireName) {
        expect(type.wireName, wireName);
      });
    });

    test('a public-link open is its own event', () {
      expect(ProductEvent.publicLinkOpened.wireName, 'public_link_opened');
      expect(
        ProductEvent.fromWireName('public_link_opened'),
        ProductEvent.publicLinkOpened,
      );
    });

    test('the sources the application actually passes are stable strings', () {
      // A funnel query groups by these, so they are gathered in one place even
      // though the column is deliberately not a closed set.
      for (final source in [
        ShareSource.playerProfile,
        ShareSource.playerStatistics,
        ShareSource.communityStatistics,
        ShareSource.teamOfPeriod,
        ShareSource.teams,
        ShareSource.matchResult,
        ShareSource.publicLink,
      ]) {
        expect(source, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        // The database truncates at 64; nothing here should come near it.
        expect(source.length, lessThan(64));
      }
    });
  });

  group('the instrumented share call sites', () {
    String read(String path) => File('lib/$path').readAsStringSync();

    test('each surface classifies its own card', () {
      // The engine cannot tell a profile from a lineup by looking at the
      // picture, so the kind is carried down from the screen that composed it.
      const sites = {
        'features/profile/profile_screen.dart': 'ShareType.playerProfile',
        'features/statistics/player_statistics_screen.dart':
            'ShareType.playerStatistics',
        'features/statistics/community_statistics_tab.dart':
            'ShareType.community',
        'features/statistics/team_of_period_screen.dart': 'ShareType.community',
        'features/teams/teams_screen.dart': 'ShareType.lineup',
        'features/football/football_match_screen.dart': 'ShareType.result',
      };
      sites.forEach((path, type) {
        final source = read(path);
        expect(source, contains(type), reason: path);
        expect(source, contains('source: ShareSource.'), reason: path);
        expect(source, contains('message: ShareMessage('), reason: path);
      });
    });

    test('a share is still only recorded when the sheet was not dismissed', () {
      final source = read('features/sharing/share_card_preview_screen.dart');
      expect(source, contains('if (outcome != ShareOutcome.dismissed) {'));
      expect(
        source.indexOf('if (outcome != ShareOutcome.dismissed) {'),
        lessThan(source.indexOf('ProductEvent.shareUsed')),
      );
      // And the metadata travels with it rather than being inferred here.
      expect(source, contains('shareType: widget.shareType'));
      expect(source, contains('source: widget.source'));
    });

    test('a public link open is recorded only for a signed-in reader', () {
      final source = read('app.dart');
      // The guard comes first: a visitor's target is left pending for the gate
      // and nothing is recorded for them.
      expect(
        source.indexOf('if (!_authService.isSignedIn) return;'),
        lessThan(source.indexOf('ProductEvent.publicLinkOpened')),
      );
      expect(source, contains('source: ShareSource.publicLink'));
      // The community and the match carry their ids; a player link has
      // neither, and null is recorded as null.
      expect(source, contains('communityId:'));
      expect(source, contains('matchId: target.kind == PublicLinkKind.match'));
    });

    test('nothing back-dates a guest open once they sign in', () {
      // The approved trade: an unauthenticated open is not measured at all,
      // and inventing the event afterwards would be fabricating one.
      final sources = [
        read('app.dart'),
        read('features/analytics/analytics_service.dart'),
        read('features/analytics/analytics_repository.dart'),
      ];
      for (final source in sources) {
        expect(source, isNot(contains('pendingLinkOpen')));
        expect(source, isNot(contains('replayPublicLink')));
      }
    });
  });

  group('the web fallback is unchanged', () {
    test('a sheet that cannot be shown still offers the download first', () {
      final source = File('lib/features/sharing/share_card_preview_screen.dart')
          .readAsStringSync();
      // On a desktop browser there is no file sharing. The reader is owed the
      // picture anyway, so the download is tried before anything is reported
      // as having gone wrong — and only then does the original failure stand.
      expect(source, contains('if (await _saved()) return;'));
      expect(
        source.indexOf('if (await _saved()) return;'),
        lessThan(source.indexOf('_report(failure);')),
      );
    });

    test('the public link never becomes a download of its own', () {
      final source =
          File('lib/features/sharing/share_service.dart').readAsStringSync();
      expect(source, isNot(contains('launchUrl')));
    });
  });

  group('a card that is not 9:16 is a defect rather than a variant', () {
    test('the shape contract still holds for the payload', () {
      expect(card().isShareCardShape, isTrue);
      expect(PublicLink.scheme, 'goplay');
    });
  });
}
