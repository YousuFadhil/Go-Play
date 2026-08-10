import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/locale_controller.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/settings/settings_screen.dart';

/// Where the language is chosen, and where it is not.
///
/// The control used to be on the login screen and on Discover. It is in
/// Settings now and nowhere else, and the app follows the device until somebody
/// goes there and says otherwise — so what is pinned here is both halves of
/// that: the choice exists in one place, and the screens it was taken off no
/// longer offer it.
void main() {
  const profile = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.mid,
  );

  setUp(() {
    CurrentUser.instance
        .useRepository(ProfileRepository(_StaticProfileAdapter(profile)));
  });

  tearDown(() {
    CurrentUser.instance.useRepository(null);
    // A singleton, so a language chosen in one test must not reach the next.
    LocaleController.instance.locale.value = null;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: SettingsScreen(),
    ));
    await tester.pumpAndSettle();
  }

  group('the language setting', () {
    testWidgets('offers the device language and the two the app speaks',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('Device language'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('opens on the device language, which is the default',
        (tester) async {
      await pumpSettings(tester);

      final selected = tester
          .widgetList<RadioListTile<String?>>(
              find.byType(RadioListTile<String?>))
          .where((tile) => tile.value == null);

      expect(selected, hasLength(1));
      expect(LocaleController.instance.locale.value, isNull,
          reason: 'no stored choice means the phone decides');
    });

    testWidgets('choosing a language sets it, and it can be given back',
        (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(LocaleController.instance.locale.value, const Locale('en'));

      await tester.tap(find.text('Device language'));
      await tester.pumpAndSettle();
      expect(LocaleController.instance.locale.value, isNull,
          reason: 'following the device again is a choice like any other');
    });
  });

  group('where the language is no longer chosen', () {
    testWidgets('the login screen carries no language control', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: LoginScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.text('العربية'), findsNothing);
      // The form itself is untouched by the removal.
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });
  });
}

class _StaticProfileAdapter implements ProfileAdapter {
  _StaticProfileAdapter(this.profile);

  final PlayerProfile profile;

  @override
  Future<PlayerProfile> fetchMyProfile() async => profile;

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeMyAvatar() => throw UnimplementedError();
}
