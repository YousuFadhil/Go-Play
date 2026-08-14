import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';

/// The header every signed-in screen carries.
///
/// What is asserted is that the signed-in player is named and pictured in one
/// place, that the two actions belonging to the person rather than the screen
/// are reachable from it, and that a screen's own actions survive being joined
/// by it. Which screens use it is not asserted here — that is each screen's own
/// test.
void main() {
  const profile = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.mid,
  );

  Future<void> pumpHeader(
    WidgetTester tester, {
    PlayerProfile? loaded = profile,
    List<Widget> actions = const [],
  }) async {
    CurrentUser.instance.useRepository(
      loaded == null
          ? ProfileRepository(_FailingProfileAdapter())
          : ProfileRepository(_StaticProfileAdapter(loaded)),
    );
    addTearDown(() => CurrentUser.instance.useRepository(null));

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        appBar: AppHeader(title: const Text('Teams'), actions: actions),
        body: const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('what the header shows', () {
    testWidgets('the screen title and the player, together', (tester) async {
      await pumpHeader(tester);

      expect(find.text('Teams'), findsOneWidget);
      // The first name in the bar: a header is not a place to wrap.
      expect(find.text('Salim'), findsOneWidget);
    });

    testWidgets('initials stand in for a picture that was never set',
        (tester) async {
      await pumpHeader(tester);

      // First and last word, not the first two: "Salim Al Harthy" is S.H to
      // somebody who knows them.
      expect(find.text('SH'), findsOneWidget);
    });

    testWidgets('a profile that cannot be read is not an error on screen',
        (tester) async {
      await pumpHeader(tester, loaded: null);

      // No name, no initials, no message — a header is not worth failing over.
      expect(find.text('Salim'), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('a screen keeps its own actions, and the player comes after',
        (tester) async {
      await pumpHeader(tester, actions: [
        IconButton(icon: const Icon(Icons.bar_chart), onPressed: () {}),
      ]);

      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
      expect(find.text('Salim'), findsOneWidget);
    });
  });

  group('the identity menu', () {
    testWidgets('carries the profile and logging out', (tester) async {
      await pumpHeader(tester);

      await tester.tap(find.text('Salim'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      // The full name, where there is room for it.
      expect(find.text('Salim Al Harthy'), findsOneWidget);
    });
  });

  group('the names a header is built from', () {
    test('the first word is the first name', () {
      expect(firstNameOf('Salim Al Harthy'), 'Salim');
      expect(firstNameOf('  Salim   Al Harthy '), 'Salim');
      expect(firstNameOf('Salim'), 'Salim');
    });

    test('an empty name gives an empty first name, never a placeholder', () {
      expect(firstNameOf(''), '');
      expect(firstNameOf('   '), '');
    });

    test('initials are the first and last word', () {
      expect(initialsOf('Salim Al Harthy'), 'SH');
      expect(initialsOf('Salim Harthy'), 'SH');
      expect(initialsOf('Salim'), 'S');
      expect(initialsOf(''), '');
    });

    test('Arabic names are read the same way', () {
      expect(initialsOf('سالم الحارثي'), 'سا');
      expect(firstNameOf('سالم الحارثي'), 'سالم');
    });
  });

  group('the cached identity', () {
    tearDown(() => CurrentUser.instance.useRepository(null));

    test('is read once and held for the session', () async {
      final adapter = _StaticProfileAdapter(profile);
      CurrentUser.instance.useRepository(ProfileRepository(adapter));

      await CurrentUser.instance.ensureLoaded();
      await CurrentUser.instance.ensureLoaded();

      expect(adapter.reads, 1,
          reason: 'a header on every screen must not be a request per screen');
      expect(CurrentUser.instance.profile.value?.fullName, 'Salim Al Harthy');
    });

    test('a refresh reads again, so a saved name stops being the old one',
        () async {
      final adapter = _StaticProfileAdapter(profile);
      CurrentUser.instance.useRepository(ProfileRepository(adapter));

      await CurrentUser.instance.ensureLoaded();
      await CurrentUser.instance.refresh();

      expect(adapter.reads, 2);
    });

    test('signing out forgets who was signed in', () async {
      CurrentUser.instance
          .useRepository(ProfileRepository(_StaticProfileAdapter(profile)));
      await CurrentUser.instance.ensureLoaded();

      CurrentUser.instance.clear();

      expect(CurrentUser.instance.profile.value, isNull,
          reason: 'the next account on this device must not be greeted by the '
              'previous one\'s name');
    });
  });
}

class _StaticProfileAdapter implements ProfileAdapter {
  _StaticProfileAdapter(this.profile);

  final PlayerProfile profile;
  int reads = 0;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    reads++;
    return profile;
  }

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

  // Requirement 2 added two members to the port. Neither is reached from this
  // test, so both refuse rather than answer.
  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}

class _FailingProfileAdapter extends _StaticProfileAdapter {
  _FailingProfileAdapter() : super(profileNeverReturned);

  static const profileNeverReturned = PlayerProfile(
    fullName: '',
    phone: '',
    primaryPosition: PlayerPosition.mid,
  );

  @override
  Future<PlayerProfile> fetchMyProfile() async => throw Exception('no session');
}
