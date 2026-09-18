import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/config.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/notifications/notification_route.dart';
import 'package:go_play/features/sharing/public_link.dart';

/// How a public link is written and read back.
///
/// The parsing is what a deep link's behaviour actually rests on: every route
/// the platform hands the app goes through it, including ones meant for the
/// invitation and notification handlers, so what it *refuses* matters as much
/// as what it accepts.
void main() {
  const player = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
  const community = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const match = '11111111-2222-4333-8444-555555555555';

  group('writing a link', () {
    test('a shared link points at the deployed web app', () {
      final url = PublicLink.format(PublicLinkKind.player, player);
      expect(url, startsWith(AppConfig.publicWebBase));
      // The route sits after the `#`: the web build is a single page served
      // without server-side rewriting, which is the same arrangement web push
      // already relies on.
      expect(url, endsWith('/#/player/$player'));
    });

    test('each kind has its own path', () {
      expect(
        PublicLink.format(PublicLinkKind.community, community),
        endsWith('/#/community/$community'),
      );
      expect(
        PublicLink.format(PublicLinkKind.match, match),
        endsWith('/#/match/$match'),
      );
    });

    test('the app link opens the app directly', () {
      expect(
        PublicLink.appLink(PublicLinkKind.player, player),
        'goplay://player/$player',
      );
    });

    test('a target knows its own address', () {
      const target = PublicLinkTarget(PublicLinkKind.match, match);
      expect(target.url, PublicLink.format(PublicLinkKind.match, match));
    });

    test('the base is not a domain the product does not own', () {
      // `goplay.app` is unregistered. A shared card carrying a link nobody can
      // open would be worse than one carrying no link at all.
      expect(AppConfig.publicWebBase, isNot(contains('goplay.app')));
      expect(AppConfig.publicWebBase, startsWith('https://'));
      expect(AppConfig.publicWebBase, isNot(endsWith('/')));
    });
  });

  group('reading a link back', () {
    test('the three shapes all resolve to the same target', () {
      const expected = PublicLinkTarget(PublicLinkKind.player, player);
      for (final input in [
        PublicLink.format(PublicLinkKind.player, player),
        PublicLink.appLink(PublicLinkKind.player, player),
        '/player/$player',
      ]) {
        expect(PublicLink.parse(input), expected, reason: input);
      }
    });

    test('a community and a match are read the same way', () {
      expect(
        PublicLink.parse('/community/$community'),
        const PublicLinkTarget(PublicLinkKind.community, community),
      );
      expect(
        PublicLink.parse('goplay://match/$match'),
        const PublicLinkTarget(PublicLinkKind.match, match),
      );
    });

    test('an id is normalised, so one link is one target', () {
      expect(
        PublicLink.parse('/player/${player.toUpperCase()}')?.id,
        player,
      );
    });

    test('a route with the origin still attached resolves', () {
      expect(
        PublicLink.parse('https://example.test/some/prefix/match/$match'),
        const PublicLinkTarget(PublicLinkKind.match, match),
      );
    });

    test('whitespace and empties are not destinations', () {
      for (final input in [null, '', '   ', '/', '#']) {
        expect(PublicLink.parse(input), isNull, reason: '$input');
      }
    });

    test('an id that is not id-shaped is not a destination', () {
      // Shape-checking, never authorization: this refuses a route, it does not
      // decide what anybody may read.
      for (final input in [
        '/player/not-a-uuid',
        '/player/12345',
        '/match/$player-extra',
        '/player/',
        '/player',
      ]) {
        expect(PublicLink.parse(input), isNull, reason: input);
      }
    });

    test('a kind the product does not publish is not a destination', () {
      expect(PublicLink.parse('/team/$player'), isNull);
      expect(PublicLink.parse('/admin/$player'), isNull);
    });
  });

  group('the three link handlers do not take each other\'s routes', () {
    test('an invitation is not a public link', () {
      final invite = InviteLink.format('4821');
      expect(PublicLink.parse(invite), isNull);
      expect(InviteLink.parse(invite), '4821');
    });

    test('a notification route is not a public link', () {
      final route = NotificationLink.format(matchId: match);
      expect(
        PublicLink.parse(route),
        isNull,
        reason: 'a notification carries its match as a query parameter, not '
            'as a /match/{id} path — and must keep reaching its own handler',
      );
    });

    test('a public link is not an invitation', () {
      final link = PublicLink.format(PublicLinkKind.match, match);
      expect(InviteLink.parse(link), isNull);
    });
  });

  group('holding a link until something can open it', () {
    setUp(PendingPublicLink.instance.clear);
    tearDown(PendingPublicLink.instance.clear);

    test('an offer that is not a public link is declined and changes nothing',
        () {
      expect(PendingPublicLink.instance.offer('/join/4821'), isFalse);
      expect(PendingPublicLink.instance.target.value, isNull);
    });

    test('an offer that is one is held until it is taken', () {
      expect(
        PendingPublicLink.instance.offer('/player/$player'),
        isTrue,
      );
      expect(
        PendingPublicLink.instance.target.value,
        const PublicLinkTarget(PublicLinkKind.player, player),
      );

      PendingPublicLink.instance.clear();
      expect(PendingPublicLink.instance.target.value, isNull);
    });

    test('a second link replaces the first rather than queueing behind it', () {
      PendingPublicLink.instance.offer('/player/$player');
      PendingPublicLink.instance.offer('/match/$match');
      expect(
        PendingPublicLink.instance.target.value,
        const PublicLinkTarget(PublicLinkKind.match, match),
      );
    });

    test('a listener hears the offer, which is how a cold start is collected',
        () {
      var heard = 0;
      void listener() => heard++;
      PendingPublicLink.instance.target.addListener(listener);
      addTearDown(
        () => PendingPublicLink.instance.target.removeListener(listener),
      );

      PendingPublicLink.instance.offer('/community/$community');
      expect(heard, 1);
    });
  });
}
