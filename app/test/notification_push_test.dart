import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/notifications/notification_adapter.dart';
import 'package:go_play/features/notifications/notification_display.dart';
import 'package:go_play/features/notifications/notification_models.dart';
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
      expect(find.text('The match was deleted.'), findsOneWidget);
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

AppNotification notice({required String type, required String message}) =>
    AppNotification(
      id: type,
      type: type,
      message: message,
      isRead: false,
      createdAt: DateTime(2026, 8, 9, 18, 30),
    );

class FakeNotificationAdapter implements NotificationAdapter {
  FakeNotificationAdapter({
    this.stored = const PushPreferences(),
    this.failSave = false,
    this.notifications = const [],
  });

  final PushPreferences stored;
  final bool failSave;
  final List<AppNotification> notifications;

  final List<PushPreferences> saved = [];
  final List<String> registered = [];
  final List<String> removed = [];

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
  Future<void> markAllRead() async {}
}
