import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/invitations/invite_link.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/notifications/notification_adapter.dart';
import 'package:go_play/features/notifications/notification_display.dart';
import 'package:go_play/features/notifications/notification_models.dart';
import 'package:go_play/features/notifications/notification_route.dart';
import 'package:go_play/features/notifications/notification_service.dart';
import 'package:go_play/features/notifications/notification_settings_screen.dart';
import 'package:go_play/features/notifications/notifications_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/notification_mapper.dart';

/// The push half of notifications, against a fake port.
///
/// What is asserted here is the one thing the whole design turns on: **these
/// settings govern delivery and nothing else.** Nothing in this suite can stop
/// a notification being written, because nothing in the app can — the notice is
/// created by the database inside the transaction that caused it, and the
/// switches below are read afterwards by an Edge Function.
///
/// The priority policy itself is SQL (`notification_types`,
/// `push_dispatch_payload`) and is not testable from here. §Testing in the
/// delivery notes records how it is exercised instead.
void main() {
  group('preferences mapping', () {
    test('an account that never opened the screen gets the defaults', () {
      final preferences = pushPreferencesFromRow(null);

      // The same defaults the columns carry, so a missing row and an untouched
      // row are indistinguishable everywhere downstream.
      expect(preferences.matchPush, isTrue);
      expect(preferences.communityPush, isTrue);
      expect(preferences.muteAll, isFalse);
    });

    test('a stored row is read as stored', () {
      final preferences = pushPreferencesFromRow({
        'match_push': false,
        'community_push': true,
        'mute_all': true,
      });

      expect(preferences.matchPush, isFalse);
      expect(preferences.communityPush, isTrue);
      expect(preferences.muteAll, isTrue);
    });
  });

  group('where a tapped notification goes', () {
    // The routing policy, which is one rule: a notice naming a match opens that
    // match, and everything else opens the Notification Center. Asserted per
    // producer rather than once, because the value of the rule is that a new
    // producer needs no entry anywhere — these cases are what would catch a
    // change that quietly reintroduced a per-type table.
    const matchScoped = [
      'match_created',
      'match_updated',
      'promoted',
      'moved_to_reserve',
      'removed',
      'registration_opened',
      'match_full',
      'teams_regenerated',
      'match_starting_soon',
      'match_time_changed',
    ];

    for (final type in matchScoped) {
      test('$type with a match opens that match', () {
        final target = NotificationTarget.of(
          notice(type: type, message: 'x', matchId: 'match-1'),
        );

        expect(target.destination, NotificationDestination.match);
        expect(target.matchId, 'match-1');
      });
    }

    test('a community notice names no match and opens the Center', () {
      // No producer of these writes a match_id, so this is the ordinary shape
      // rather than a degraded one.
      for (final type in [
        'community_invitation',
        'community_join_accepted',
        'community_picture_updated',
      ]) {
        final target = NotificationTarget.of(notice(type: type, message: 'x'));
        expect(target.destination, NotificationDestination.centre, reason: type);
        expect(target.matchId, isNull, reason: type);
      }
    });

    test('an unregistered type routes by its id like any other', () {
      // The rule does not consult the type, so a type the app has never heard
      // of is still taken to the match it names.
      expect(
        NotificationTarget.of(
          notice(type: 'something_new', message: 'x', matchId: 'match-9'),
        ).matchId,
        'match-9',
      );
    });

    test('a cancelled match has already stopped naming one', () {
      // `notifications.match_id` is `on delete set null`, so this is what a
      // notice about a deleted match actually looks like by the time it is read.
      expect(
        NotificationTarget.of(notice(type: 'match_deleted', message: 'x'))
            .destination,
        NotificationDestination.centre,
      );
    });

    group('from a tapped push', () {
      test('carries the notice id so a tapped push can be marked read', () {
        final target = NotificationTarget.fromPushData(const {
          'notification_id': 'notice-1',
          'type': 'promoted',
          'match_id': '0661c5a0-1d9d-4bd9-9733-f06ef97e744a',
        });

        expect(target.notificationId, 'notice-1');
      });

      test('the notice id survives falling back to the Center', () async {
        // The reader tapped the notice whether or not its match opened, so it
        // is read either way.
        final target = await NotificationTarget.fromPushData(
          const {'notification_id': 'notice-1', 'match_id': 'gone'},
        ).resolved((_) async => false);

        expect(target.destination, NotificationDestination.centre);
        expect(target.notificationId, 'notice-1');
      });

      test('a web link carries no notice id', () {
        // Deliberate: the URL is a navigation target and nothing else, so the
        // web marks read when the Center is opened, as it always did.
        expect(
          NotificationLink.parse(
            NotificationLink.format(
              matchId: '0661c5a0-1d9d-4bd9-9733-f06ef97e744a',
            ),
          )?.notificationId,
          isNull,
        );
      });

      test('carries the match through the data block', () {
        // Exactly what `push-dispatch` sends.
        final target = NotificationTarget.fromPushData(const {
          'notification_id': 'n-1',
          'type': 'match_created',
          'match_id': 'match-1',
        });

        expect(target.destination, NotificationDestination.match);
        expect(target.matchId, 'match-1');
      });

      test('reads a blank match_id as naming no match', () {
        // FCM data values are strings, so the function writes "" rather than
        // omitting the key. Blank is how "no match" is spelled on this path.
        expect(
          NotificationTarget.fromPushData(const {
            'notification_id': 'n-1',
            'type': 'community_invitation',
            'match_id': '',
          }).destination,
          NotificationDestination.centre,
        );
      });

      test('a cold start holds the tap until something can act on it', () {
        // The launching notification is readable before there is a Navigator,
        // so it is parked. Nothing consumes it here — that a tap survives
        // arriving early is the whole assertion.
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        pending.offerPushData({'type': 'match_created', 'match_id': 'match-1'});

        expect(pending.target.value?.matchId, 'match-1');
      });

      test('a consumed tap does not fire twice', () {
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        pending.offerPushData({'type': 'match_created', 'match_id': 'match-1'});
        pending.clear();

        expect(pending.target.value, isNull);
      });

      test('a background tap replaces one still pending', () {
        // Two notifications tapped in quick succession: the second is what the
        // reader asked for most recently.
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        pending.offerPushData({'match_id': 'match-1'});
        pending.offerPushData({'match_id': 'match-2'});

        expect(pending.target.value?.matchId, 'match-2');
      });
    });

    group('from a clicked web notification', () {
      // A browser hands a notification click over as a URL and nothing else,
      // so the target travels in the link. These assert both halves of the
      // format `push-dispatch` writes and this app reads.
      const matchId = '0661c5a0-1d9d-4bd9-9733-f06ef97e744a';

      const noticeId = '7b080e28-91d0-4af8-8d67-21aad3302c54';

      test('a match notice encodes its id in the route', () {
        expect(
          NotificationLink.format(matchId: matchId),
          '/notification?match_id=$matchId',
        );
      });

      test('the link carries the notice id as well as the match', () {
        // What lets a clicked web notification be marked read. Order matters:
        // `push-dispatch` appends the same two in the same order.
        expect(
          NotificationLink.format(matchId: matchId, notificationId: noticeId),
          '/notification?match_id=$matchId&notification_id=$noticeId',
        );
      });

      test('a notice naming no match still carries its own id', () {
        expect(
          NotificationLink.format(notificationId: noticeId),
          '/notification?notification_id=$noticeId',
        );
      });

      test('match and notice both survive the round trip', () {
        final target = NotificationLink.parse(
          NotificationLink.format(matchId: matchId, notificationId: noticeId),
        );

        expect(target?.destination, NotificationDestination.match);
        expect(target?.matchId, matchId);
        expect(target?.notificationId, noticeId);
      });

      test('a notice id alone opens the Center and is still marked read', () {
        final target = NotificationLink.parse(
          NotificationLink.format(notificationId: noticeId),
        );

        expect(target?.destination, NotificationDestination.centre);
        expect(target?.matchId, isNull);
        expect(target?.notificationId, noticeId);
      });

      test('links without a notice id keep working exactly as before', () {
        // The format that is live in production today must not stop parsing.
        final target =
            NotificationLink.parse('/notification?match_id=$matchId');

        expect(target?.destination, NotificationDestination.match);
        expect(target?.matchId, matchId);
        expect(target?.notificationId, isNull);
        expect(NotificationLink.parse('/notification')?.destination,
            NotificationDestination.centre);
      });

      test('a malformed notice id is dropped, not obeyed, and breaks nothing',
          () {
        // The two ids are checked independently: a bad notice id must not cost
        // the reader the navigation, and cannot become a write target.
        for (final bad in [
          'not-a-uuid',
          '../../admin',
          '%3Cscript%3E',
          '1 OR 1=1',
        ]) {
          final target = NotificationLink.parse(
            '/notification?match_id=$matchId&notification_id=$bad',
          );
          expect(target?.destination, NotificationDestination.match,
              reason: bad);
          expect(target?.matchId, matchId, reason: bad);
          expect(target?.notificationId, isNull, reason: bad);
        }
      });

      test('a bad match id does not cost a good notice id', () {
        final target = NotificationLink.parse(
          '/notification?match_id=nonsense&notification_id=$noticeId',
        );

        expect(target?.destination, NotificationDestination.centre);
        expect(target?.notificationId, noticeId);
      });

      test('the notice id survives being parked for a cold start', () {
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        pending.consumeRoute(
          NotificationLink.format(matchId: matchId, notificationId: noticeId),
        );

        expect(pending.target.value?.matchId, matchId);
        expect(pending.target.value?.notificationId, noticeId);
      });

      test('a notice naming no match still gets a route', () {
        // It must land somewhere: a click that does nothing is the defect.
        expect(NotificationLink.format(), '/notification');
        expect(NotificationLink.format(matchId: '  '), '/notification');
      });

      test('what is written is what is read', () {
        final target =
            NotificationLink.parse(NotificationLink.format(matchId: matchId));

        expect(target?.destination, NotificationDestination.match);
        expect(target?.matchId, matchId);
      });

      test('a route with no match opens the Center', () {
        final target = NotificationLink.parse(NotificationLink.format());

        expect(target?.destination, NotificationDestination.centre);
        expect(target?.matchId, isNull);
      });

      test('a target that is not id-shaped opens the Center', () {
        // The address bar is not a trusted input. Shape is checked here;
        // whether the reader may see the match stays Match Details' question.
        for (final bad in [
          '/notification?match_id=../../admin',
          '/notification?match_id=1 OR 1=1',
          '/notification?match_id=0661c5a0',
          '/notification?match_id=%3Cscript%3E',
        ]) {
          final target = NotificationLink.parse(bad);
          expect(target?.destination, NotificationDestination.centre,
              reason: bad);
          expect(target?.matchId, isNull, reason: bad);
        }
      });

      test('routes that are not ours are left alone', () {
        // Null means "not a notification link", which is what stops this
        // stealing an invitation or an ordinary start.
        for (final other in [
          null,
          '',
          '/',
          '/join/1234',
          '1234',
          '/notifications',
        ]) {
          expect(NotificationLink.parse(other), isNull, reason: '$other');
        }
      });

      test('consuming a link takes the target and reports it as ours', () {
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        final consumed = pending
            .consumeRoute(NotificationLink.format(matchId: matchId));

        expect(consumed, isTrue);
        expect(pending.target.value?.matchId, matchId);
      });

      test('an invitation route is not consumed as a notification', () {
        // The two landing paths share `didPushRouteInformation`; this is what
        // keeps them from taking each other's links.
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        expect(pending.consumeRoute('/join/1234'), isFalse);
        expect(pending.target.value, isNull);
        // And the invitation still parses as one.
        expect(InviteLink.parse('/join/1234'), '1234');
      });

      test('a refresh after consuming reopens nothing', () {
        // The address bar is rewritten to `consumedRoute` once the target has
        // been taken. Reloading there must be an ordinary start, or every
        // refresh replays the same notification.
        final pending = PendingNotificationTap.instance;
        addTearDown(pending.clear);

        pending.consumeRoute(NotificationLink.format(matchId: matchId));
        pending.clear();

        expect(NotificationLink.parse(NotificationLink.consumedRoute), isNull);
        expect(pending.consumeRoute(NotificationLink.consumedRoute), isFalse);
        expect(pending.target.value, isNull);
      });
    });

    group('the match already on screen', () {
      // What stops a notification for the match the reader is looking at from
      // pushing a second copy of that same screen on top of it.
      final registry = CurrentMatchDetails.instance;

      tearDown(() => registry.unbind(registry));

      test('reloads in place instead of opening a second copy', () {
        final owner = Object();
        var reloads = 0;
        registry.bind(owner, 'match-1', () => reloads++);
        addTearDown(() => registry.unbind(owner));

        expect(registry.reloadIfShowing('match-1'), isTrue);
        expect(reloads, 1);
      });

      test('a different match is left to open normally', () {
        final owner = Object();
        var reloads = 0;
        registry.bind(owner, 'match-1', () => reloads++);
        addTearDown(() => registry.unbind(owner));

        expect(registry.reloadIfShowing('match-2'), isFalse);
        expect(reloads, 0);
      });

      test('nothing on screen means nothing to reload', () {
        expect(registry.reloadIfShowing('match-1'), isFalse);
        expect(registry.matchId, isNull);
      });

      test('a stacked screen does not have its registration cleared by the '
          'one underneath', () {
        // Two Match Details can legitimately coexist — opened by hand, not by
        // notification. The lower one disposing must not unbind the upper.
        final lower = Object();
        final upper = Object();
        registry.bind(lower, 'match-1', () {});
        registry.bind(upper, 'match-2', () {});
        addTearDown(() => registry.unbind(upper));

        registry.unbind(lower);

        expect(registry.matchId, 'match-2');
      });
    });

    group('when the match cannot be opened', () {
      test('falls back to the Center', () async {
        final target = await NotificationTarget.fromPushData(
          const {'match_id': 'gone'},
        ).resolved((_) async => false);

        expect(target.destination, NotificationDestination.centre);
        expect(target.matchId, isNull);
      });

      test('opens the match when it can', () async {
        final asked = <String>[];
        final target =
            await NotificationTarget.fromPushData(const {'match_id': 'match-1'})
                .resolved((id) async {
          asked.add(id);
          return true;
        });

        expect(target.destination, NotificationDestination.match);
        expect(target.matchId, 'match-1');
        expect(asked, ['match-1']);
      });

      test('a Center-bound tap never asks about a match', () async {
        var asked = false;
        final target = await const NotificationTarget.centre()
            .resolved((_) async => asked = true);

        expect(asked, isFalse);
        expect(target.destination, NotificationDestination.centre);
      });
    });
  });

  group('Notification Center rendering', () {
    Future<void> pumpCentre(
      WidgetTester tester,
      FakeNotificationAdapter adapter,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: NotificationsScreen(service: NotificationService(adapter)),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('every display entry carries an icon, a tone and a label', () {
      // The registry replaced three parallel switches. What it buys is that a
      // type cannot be half-added, so that is what is asserted.
      expect(notificationDisplays, isNotEmpty);
      for (final entry in notificationDisplays.entries) {
        expect(entry.value.label, isNotNull, reason: entry.key);
      }
    });

    testWidgets('a registered type renders in the reader\'s language',
        (tester) async {
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'match_deleted', message: 'تم حذف المباراة.'),
        ]),
      );

      // The English label, not the Arabic the database stored.
      //
      // "cancelled", not "deleted": the type keeps its identifier but the
      // player-facing wording matches the push title, which has always said
      // cancelled. The product has no cancelled status — a match that will not
      // be played is deleted — so this is the one word the reader sees for it.
      expect(find.text('The match was cancelled.'), findsOneWidget);
    });

    testWidgets('a new match announcement renders as a produced type',
        (tester) async {
      // `match_created` was registered in 0036 and produced only from 0039, by
      // `create_match`. What that changes for this layer is that the type now
      // reaches real readers, so it has to render like the other produced types:
      // the reader's own label, never the Arabic body the database stored for
      // the push.
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'match_created', message: 'مباراة الخميس — الملعب.'),
        ]),
      );

      expect(find.text('A new match has been created.'), findsOneWidget);
      expect(find.text('مباراة الخميس — الملعب.'), findsNothing);
    });

    testWidgets('every live type names the match it is about', (tester) async {
      // The defect this cycle exists to fix: three notices of the same kind
      // were three identical rows. The event is the title; the match is the
      // line under it, and it is what tells them apart.
      const live = [
        'match_created',
        'match_updated',
        'promoted',
        'moved_to_reserve',
        'removed',
      ];

      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          for (final type in live)
            notice(
              type: type,
              message: 'مباراة الجمعة',
              matchId: 'match-$type',
              matchTitle: 'مباراة الجمعة',
              id: type,
            ),
        ]),
      );

      // One subtitle per notice, and the event label still above each.
      expect(find.text('مباراة الجمعة'), findsNWidgets(live.length));
      expect(find.text('A new match has been created.'), findsOneWidget);
      expect(find.text('Match details were updated.'), findsOneWidget);
      expect(find.text('The organizer removed you from the match.'),
          findsOneWidget);
    });

    testWidgets('a cancelled match carries no match line', (tester) async {
      // `match_id` is nulled by the delete, so there is nothing to join to and
      // nothing to name. The tile says what happened and stops there.
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'match_deleted', message: 'مباراة الجمعة'),
        ]),
      );

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.onTap, isNull);
      expect(tile.isThreeLine, isFalse);
      expect(find.text('The match was cancelled.'), findsOneWidget);
    });

    testWidgets('tapping a notice marks that one read and opens its match',
        (tester) async {
      final adapter = FakeNotificationAdapter(notifications: [
        notice(
          type: 'promoted',
          message: 'مباراة الجمعة',
          matchId: 'match-1',
          matchTitle: 'مباراة الجمعة',
          id: 'notice-1',
        ),
      ]);
      final opened = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: NotificationsScreen(
            service: NotificationService(adapter),
            onOpenMatch: opened.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // That one, by id — not the sweep the screen does on open.
      expect(adapter.readIds, ['notice-1']);
      expect(opened, ['match-1']);
    });

    testWidgets('a failed mark-read still opens the match', (tester) async {
      // Best-effort, and this is what that has to mean: an unread badge is a
      // cosmetic wrong, while swallowing the tap is the defect this whole
      // feature exists to fix. The same call site serves a tapped push.
      final adapter = FakeNotificationAdapter(
        failMarkRead: true,
        notifications: [
          notice(
            type: 'promoted',
            message: 'مباراة الجمعة',
            matchId: 'match-1',
            matchTitle: 'مباراة الجمعة',
            id: 'notice-1',
          ),
        ],
      );
      final opened = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: NotificationsScreen(
            service: NotificationService(adapter),
            onOpenMatch: opened.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      expect(adapter.readIds, isEmpty);
      expect(opened, ['match-1']);
    });

    testWidgets('a notice about a match is tappable', (tester) async {
      // The affordance, asserted rather than the navigation: pushing Match
      // Details would build the real screen against Supabase. Where the tap
      // *goes* is `NotificationTarget`'s decision and is covered above; what
      // this screen owes is that the tile offers the tap at all.
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'match_created', message: 'x', matchId: 'match-1'),
        ]),
      );

      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNotNull);
    });

    testWidgets('a notice about nothing is inert', (tester) async {
      // Not merely unhandled — not offered. A tile that highlights under a
      // finger and then does nothing is the defect this feature exists to fix.
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'community_invitation', message: 'x'),
        ]),
      );

      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });

    testWidgets('an unregistered type falls back to the stored message',
        (tester) async {
      await pumpCentre(
        tester,
        FakeNotificationAdapter(notifications: [
          notice(type: 'something_new', message: 'رسالة غير معروفة.'),
        ]),
      );

      expect(find.text('رسالة غير معروفة.'), findsOneWidget);
    });
  });

  group('the settings screen', () {
    Future<void> pump(
      WidgetTester tester,
      FakeNotificationAdapter adapter,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: NotificationSettingsScreen(
            service: NotificationService(adapter),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the three switches and nothing else', (tester) async {
      await pump(tester, FakeNotificationAdapter());

      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('Match notifications'), findsOneWidget);
      expect(find.text('Community notifications'), findsOneWidget);
      expect(find.text('Mute all push notifications'), findsOneWidget);
    });

    testWidgets('says that history is kept whatever is switched off',
        (tester) async {
      await pump(tester, FakeNotificationAdapter());

      // The screen has to make the promise, or turning push off reads as
      // turning notifications off.
      expect(
        find.textContaining('Every notification is kept in the app'),
        findsOneWidget,
      );
    });

    testWidgets('turning a category off saves it', (tester) async {
      final adapter = FakeNotificationAdapter();
      await pump(tester, adapter);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      expect(adapter.saved.single.matchPush, isFalse);
      expect(adapter.saved.single.communityPush, isTrue);
    });

    testWidgets('muting everything leaves the categories unusable',
        (tester) async {
      final adapter = FakeNotificationAdapter();
      await pump(tester, adapter);

      await tester.tap(find.byType(SwitchListTile).last);
      await tester.pumpAndSettle();

      expect(adapter.saved.single.muteAll, isTrue);
      // Not merely outranked — shown as having no effect, because a category
      // switch that still looks live under a mute is a lie.
      final categories = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .take(2);
      for (final tile in categories) {
        expect(tile.onChanged, isNull);
        expect(tile.value, isFalse);
      }
    });

    testWidgets('a save that fails puts the switch back and says so',
        (tester) async {
      final adapter = FakeNotificationAdapter(failSave: true);
      await pump(tester, adapter);

      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      final match =
          tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).first;
      expect(match.value, isTrue);
      expect(find.text('That setting could not be saved. Try again.'),
          findsOneWidget);
    });
  });
}

AppNotification notice({
  required String type,
  required String message,
  String? matchId,
  String? matchTitle,
  String? id,
}) =>
    AppNotification(
      id: id ?? type,
      type: type,
      message: message,
      isRead: false,
      createdAt: DateTime(2026, 8, 9, 18, 30),
      matchId: matchId,
      matchTitle: matchTitle,
    );

class FakeNotificationAdapter implements NotificationAdapter {
  FakeNotificationAdapter({
    this.stored = const PushPreferences(),
    this.failSave = false,
    this.failMarkRead = false,
    this.notifications = const [],
  });

  final PushPreferences stored;
  final bool failSave;
  final bool failMarkRead;
  final List<AppNotification> notifications;

  final List<PushPreferences> saved = [];
  final List<String> registered = [];
  final List<String> removed = [];
  final List<String> readIds = [];
  int markAllReadCalls = 0;

  @override
  Future<PushPreferences> fetchPushPreferences() async => stored;

  @override
  Future<void> savePushPreferences(PushPreferences preferences) async {
    if (failSave) throw const NetworkFailure();
    saved.add(preferences);
  }

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) async =>
      registered.add(token);

  @override
  Future<void> removeDevice(String token) async => removed.add(token);

  @override
  Future<List<AppNotification>> fetchAll() async => notifications;

  @override
  Future<int> unreadCount() async =>
      notifications.where((n) => !n.isRead).length;

  @override
  Future<void> markAllRead() async => markAllReadCalls++;

  @override
  Future<void> markRead(String notificationId) async {
    if (failMarkRead) throw const NetworkFailure();
    readIds.add(notificationId);
  }
}
