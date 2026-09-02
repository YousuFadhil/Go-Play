import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';

/// The way to your own profile, on the screens the shell navigates between.
///
/// [AppHeader] guarantees it structurally — every screen using it gets the
/// identity appended whether it asks or not — and the Club redesign moved the
/// three shell screens off [AppHeader] onto [ClubHeroBar], which made no such
/// guarantee. Discover had it put back by hand; Home and Communities were left
/// without one, so where a player could reach their profile depended on which
/// tab they were standing on.
///
/// What is pinned here is the contract that replaced the hand-written one, and
/// that a task screen is still not made to carry it.
void main() {
  const profile = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.mid,
  );

  /// A loaded session, so the menu has a player to name.
  void withSession() {
    CurrentUser.instance
        .useRepository(ProfileRepository(_StaticProfileAdapter(profile)));
    addTearDown(() => CurrentUser.instance.useRepository(null));
  }

  Future<void> pumpBar(WidgetTester tester, Widget bar) async {
    withSession();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: bar),
    ));
    await tester.pumpAndSettle();
  }

  group('the ClubHeroBar contract', () {
    testWidgets('carries no identity by default', (tester) async {
      // The default is what every task screen gets. A screen reached from the
      // shell has a back button and its own actions; a second way out beside
      // them is noise, and the default must not put one there.
      await pumpBar(tester, const ClubHeroBar(title: 'A task'));

      expect(find.byType(CurrentUserMenu), findsNothing);
    });

    testWidgets('carries exactly one when a place asks for it', (tester) async {
      await pumpBar(
        tester,
        const ClubHeroBar(title: 'A place', showCurrentUserMenu: true),
      );

      expect(find.byType(CurrentUserMenu), findsOneWidget);
    });

    testWidgets('appends it after the screen\'s own actions', (tester) async {
      // The same order [AppHeader] uses, so a screen's own actions keep their
      // position as they differ from screen to screen.
      await pumpBar(
        tester,
        const ClubHeroBar(
          title: 'A place',
          showCurrentUserMenu: true,
          actions: [Icon(Icons.link, key: Key('ownAction'))],
        ),
      );

      expect(find.byKey(const Key('ownAction')), findsOneWidget);
      expect(find.byType(CurrentUserMenu), findsOneWidget);

      final own = tester.getTopLeft(find.byKey(const Key('ownAction')));
      final menu = tester.getTopLeft(find.byType(CurrentUserMenu));
      expect(own.dx, lessThan(menu.dx),
          reason: 'the identity closes the bar rather than displacing what the '
              'screen put there');
    });
  });

  // Home is not pumped here. `_HomeTabState` builds `MatchService()`,
  // `NotificationService()` and `AuthService()` in its field initializers, and
  // each of those reaches `Supabase.instance` at construction, so the widget
  // throws before it builds in a test with no initialized client. That is why
  // the suite has never held a Home test, and giving it optional ports is a
  // change to a screen this cycle is not otherwise touching.
  //
  // What Home does carry is the contract above, opted into the same way
  // Communities does — see `communities_screen_test.dart` for the same
  // assertion made against a screen that can be pumped.
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

  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}
