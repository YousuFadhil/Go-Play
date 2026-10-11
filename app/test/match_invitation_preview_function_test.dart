import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/features/sharing/public_link.dart';

/// The contract between the link the app shares and the Pages Function that
/// answers it (`functions/share/match/[id].js`). The Function is JavaScript on
/// Cloudflare's side of the wire, so what is pinned here is what the two halves
/// must agree on; its own behaviour is tested in tests/cloudflare.
void main() {
  const id = '11111111-2222-4333-8444-555555555555';
  final function = File('../functions/share/match/[id].js');

  test('the app shares a route that the Function file serves', () {
    // Pages file-based routing: functions/share/match/[id].js is /share/match/:id.
    final shared =
        Uri.parse(PublicLink.matchInvitation(id, languageCode: 'en'));
    expect(shared.pathSegments, ['share', 'match', id]);
    expect(function.existsSync(), isTrue);
    expect(function.readAsStringSync(), contains('export const onRequest'));
  });

  test('people are moved on to the app route the app already resolves', () {
    final route = '/#${PublicLink.path(PublicLinkKind.match, '\${matchId}')}';
    expect(function.readAsStringSync(), contains(route));
    expect(
        PublicLink.format(PublicLinkKind.match, id), endsWith('/#/match/$id'));
  });

  test('the Function writes the languages the app can ask for, and no others',
      () {
    final source = function.readAsStringSync();
    expect(source, contains("const LANGUAGES = ['ar', 'en'];"));
    for (final code in ['ar', 'en']) {
      expect(PublicLink.matchInvitation(id, languageCode: code),
          endsWith('?lang=$code'));
    }
    expect(PublicLink.matchInvitation(id, languageCode: 'fr'),
        isNot(contains('lang=')));
  });

  test('the preview names the one thumbnail that ships with the web build', () {
    expect(function.readAsStringSync(),
        contains("'/og/go-play-match-invite.jpg'"));
    // `app/web` is copied into the build output, so this is served at /og/...
    expect(File('web/og/go-play-match-invite.jpg').existsSync(), isTrue);
  });

  test('the Function never holds a privileged key', () {
    final source = function.readAsStringSync();
    expect(
        source.contains(RegExp('service_role|SERVICE_ROLE|SUPABASE_SERVICE')),
        isFalse);
    expect(source, contains('SUPABASE_ANON_KEY'));
  });

  // One command for both halves: the Function's own tests run here when Node is
  // installed (it is wherever the web build is made).
  final hasNode = () {
    try {
      return Process.runSync('node', ['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test(
    'the Function behaves: Open Graph tags, escaping, fallbacks, identifiers, navigation',
    () async {
      final result = await Process.run(
        'node',
        ['--test', 'tests/cloudflare/share_match.test.mjs'],
        workingDirectory: '..',
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: hasNode ? false : 'Node is not installed',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
