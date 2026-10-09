import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/features/discover/discover_tabs.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/skeleton.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/login_screen.dart';
import 'package:go_play/features/auth/register_screen.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/discover/discover_adapter.dart';
import 'package:go_play/features/discover/discover_models.dart';
import 'package:go_play/features/discover/discover_repository.dart';
import 'package:go_play/features/discover/discover_screen.dart';
import 'package:go_play/features/discover/discover_widgets.dart';
import 'package:go_play/features/discover/public_community_screen.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/features/locations/guest_location_store.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_adapter_defaults.dart';
import 'wilayat_fixtures.dart';

/// The public entry experience: what a visitor can see, and where they are
/// stopped.
///
/// The two halves are asserted separately on purpose, because Sprint 1 is a
/// claim about both. Browsing has to work with no session at all — every read
/// behind these screens goes through `DiscoverAdapter`, and nothing here is
/// given an `AuthService` that says anyone is signed in. Taking part has to
/// stop, at every one of the actions the sprint names, and stop in the same
/// place rather than in five.
void main() {
  PublicCommunity community(
    String id,
    String name, {
    String? description = 'Weekly six-a-side',
    int members = 12,
    int upcoming = 2,
  }) =>
      PublicCommunity(
        id: id,
        name: name,
        description: description,
        memberCount: members,
        upcomingMatchCount: upcoming,
      );

  /// A fixed future date, so the formatted day is the same on every run.
  final start = DateTime(2027, 3, 6, 20, 0);

  PublicMatch match(
    String id, {
    String? title = 'Friday night five-a-side',
    String communityName = 'Muscat United',
    String location = 'Al Amerat Pitch 2',
    int openSlots = 4,
  }) =>
      PublicMatch(
        id: id,
        communityId: 'c1',
        communityName: communityName,
        location: location,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 10,
        openSlots: openSlots,
        title: title,
      );

  /// Discover opens on Upcoming Matches; the communities are one tap away.
  ///
  /// Scrolled into view first, because at 320px the tab bar is deliberately
  /// scrollable rather than shrinking its labels -- so the third tab may start
  /// off screen, exactly as it does for a reader on a narrow phone.
  /// Upcoming Matches, the second tab since Latest Results became the first.
  Future<void> openUpcoming(WidgetTester tester) async {
    final tab = find
        .descendant(of: find.byType(DiscoverTabs), matching: find.byType(Tab))
        .at(1);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Future<void> openCommunities(WidgetTester tester) async {
    // By position, not by label: the Arabic build says `المجتمعات`, and a
    // helper that only knows the English word would silently skip the RTL
    // case this suite exists for.
    final tab = find
        .descendant(of: find.byType(DiscoverTabs), matching: find.byType(Tab))
        .at(2);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Future<void> pumpDiscover(
    WidgetTester tester, {
    List<PublicCommunity>? communities,
    List<PublicMatch>? matches,
    Object? failure,
    bool signedIn = false,
    PlayerProfile? profile,
    Locale locale = const Locale('en'),
    Size size = const Size(800, 2400),
    // Cycle 3: a signed-in Discover also reads football history and the
    // reader's own memberships. Supplied here so the screen never reaches the
    // real provider, exactly as the discover repository already is.
    List<CompletedMatch>? results,
    Object? footballFailure,
    List<String> joinedCommunityIds = const [],
    // Set together, these leave the screen standing in its loading state: the
    // adapter has not answered yet and the pump does not wait for it.
    Duration? delay,
    bool settle = true,
    // Which tab to show once loaded. Discover opens on Latest Results (0);
    // most of this suite is about the fixtures, so it moves to Upcoming (1).
    int tab = 1,
    // Nearby discovery: the Wilayat names, a guest's device storage, the
    // profile port (to see what is written to it) and the public results.
    WilayatRepository? wilayats,
    GuestLocationStore? guestStore,
    _StaticProfileAdapter? profileAdapter,
    List<PublicResult> recentResults = const [],
  }) async {
    // The greeting reads the profile the session holds. Left null nothing is
    // loaded, which is the case the headline has to fall back for.
    final profiles = profileAdapter ??
        (profile == null ? null : _StaticProfileAdapter(profile));
    CurrentUser.instance.useRepository(
      profiles == null ? null : ProfileRepository(profiles),
    );
    addTearDown(() => CurrentUser.instance.useRepository(null));

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _FakeDiscoverAdapter(
      communities: communities ?? [community('c1', 'Muscat United')],
      matches: matches ?? [match('m1')],
      failure: failure,
      delay: delay,
    )..recentResults = recentResults;

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: locale,
      home: DiscoverScreen(
        repository: DiscoverRepository(adapter),
        authService: AuthService(_StubAuthAdapter(signedIn: signedIn)),
        footballRepository: FootballRepository(
          _FakeFootballAdapter(
            results: results ?? const [],
            failure: footballFailure,
          ),
        ),
        communityRepository:
            CommunityRepository(_JoinedCommunitiesAdapter(joinedCommunityIds)),
        wilayatRepository: wilayats,
        guestLocationStore: guestStore,
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
      if (tab != 0) {
        final target = find
            .descendant(
                of: find.byType(DiscoverTabs), matching: find.byType(Tab))
            .at(tab);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
    } else {
      // One frame, which is the frame the skeleton is on.
      await tester.pump();
    }
  }

  group('the app opens on something to look at', () {
    testWidgets('uses the frozen Club place presentation', (tester) async {
      await pumpDiscover(tester);

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      // The crest lives on a community card, which is now behind its own tab.
      expect(find.byType(DiscoverTabs), findsOneWidget);
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityCrest), findsOneWidget);
    });

    testWidgets('the banner names the product and offers an account',
        (tester) async {
      await pumpDiscover(tester);

      expect(find.text('Go Play'), findsOneWidget);
      expect(find.text('Football, with your people.'), findsOneWidget);
      // Once. The closing call to action is gone: one per tab was the same
      // panel three times over, a screen of scrolling from the football each
      // tab exists for.
      expect(find.text('Create account'), findsOneWidget);
      // Sprint 2 made the second way in a real button beside the first rather
      // than a sentence under it, which is what took a row out of the banner.
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsOneWidget);
    });

    testWidgets('a guest sees the upcoming matches', (tester) async {
      await pumpDiscover(tester);

      expect(find.text('Friday night five-a-side'), findsOneWidget);
      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('Al Amerat Pitch 2'), findsOneWidget);
      expect(find.text('4 places left'), findsOneWidget);

      // The same three parts the stacked tile carried — weekday, day, month —
      // on one line now that Discover lays its matches out two across. Sprint 2
      // replaced "Sat, Mar 6, 2027" with the tile so the day read at a glance;
      // the grid keeps the glance and gives the card back the two lines the
      // stack was spending. The tile itself is unchanged where it still stands,
      // on the community pages that remain a single column.
      expect(find.text('Sat 6 Mar'), findsOneWidget);
    });

    testWidgets('a full match says so instead of offering places',
        (tester) async {
      await pumpDiscover(tester, matches: [match('m1', openSlots: 0)]);

      expect(find.text('Full'), findsOneWidget);
      expect(find.textContaining('places left'), findsNothing);
    });

    testWidgets('a match with no title falls back to its location',
        (tester) async {
      await pumpDiscover(tester, matches: [match('m1', title: null)]);

      expect(find.text('Al Amerat Pitch 2'), findsWidgets);
    });

    testWidgets('every community is listed, whatever its policy',
        (tester) async {
      // The sprint is explicit that this list is not filtered. A community the
      // visitor cannot join without a code is still one they can see exists.
      await pumpDiscover(tester, communities: [
        community('c1', 'Muscat United'),
        community('c2', 'Seeb Strikers'),
        community('c3', 'Sohar FC'),
      ]);
      await openCommunities(tester);

      expect(find.text('Muscat United'), findsWidgets);
      expect(find.text('Seeb Strikers'), findsOneWidget);
      expect(find.text('Sohar FC'), findsOneWidget);
    });

    testWidgets('a community card carries its mark, size and schedule',
        (tester) async {
      await pumpDiscover(tester, communities: [
        community('c1', 'Muscat United', members: 24, upcoming: 3),
      ]);
      await openCommunities(tester);

      // The initials are the logo: there is no logo column, and this sprint
      // adds none.
      expect(find.text('MU'), findsOneWidget);
      expect(find.text('Weekly six-a-side'), findsOneWidget);
      expect(find.text('24 members'), findsOneWidget);
      expect(find.text('3 upcoming matches'), findsOneWidget);
    });

    testWidgets('nothing to browse is said, not shown as an error',
        (tester) async {
      await pumpDiscover(tester, communities: [], matches: []);

      // Each empty state lives inside its own tab now, so each is asked for.
      expect(find.text('Nothing is scheduled just yet. Check back soon.'),
          findsOneWidget);
      expect(find.text('Failed to load data.'), findsNothing);

      await openCommunities(tester);
      expect(find.text('No communities yet. Be the first to start one.'),
          findsOneWidget);
      expect(find.text('Failed to load data.'), findsNothing);
    });

    testWidgets('a failed load still lets a visitor sign up', (tester) async {
      await pumpDiscover(tester, failure: StateError('offline'));

      expect(find.text('Failed to load data.'), findsOneWidget);
      // The banner survives: the product is describable without a working
      // connection.
      expect(find.text('Create account'), findsOneWidget);
    });
  });

  group('a guest may look but not take part', () {
    testWidgets('registering for a match asks for an account', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();

      expect(find.text('Account needed'), findsOneWidget);
      expect(find.text('Create an account to register for this match.'),
          findsOneWidget);
    });

    testWidgets('joining a community asks for an account', (tester) async {
      await pumpDiscover(tester);
      await openCommunities(tester);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to join this community.'),
          findsOneWidget);
    });

    testWidgets('a guest is not offered a community to create', (tester) async {
      // **The closing call to action is gone**, and with it the guest's
      // "create a community" ask. A guest cannot create one, and the hero
      // offers the thing that would let them: an account. The prompt that
      // used to say so lived on a panel repeated under every tab.
      await pumpDiscover(tester, communities: []);

      expect(find.text('Create community'), findsNothing);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsOneWidget);

      await openCommunities(tester);
      expect(find.text('Create community'), findsNothing);
    });

    testWidgets('the sheet leads to registration', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();
      // Scoped to the sheet: "Create account" is also on the page underneath it.
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(FilledButton, 'Create account'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('the sheet leads to signing in', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(OutlinedButton, 'Log in'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('the banner opens the forms directly', (tester) async {
      await pumpDiscover(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Log in'));
      await tester.pumpAndSettle();

      // Straight to the form: somebody who says they have an account is not
      // asked whether they need one.
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('a guest may open a community', () {
    testWidgets('opening it is the card\'s named primary action',
        (tester) async {
      // Not a tappable card somebody has to guess at: the sprint's flow is
      // browse, open, then decide, so the step in the middle is a button with
      // a name on it.
      await pumpDiscover(tester);
      await openCommunities(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'View community'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicCommunityScreen), findsOneWidget);
    });

    testWidgets('the card opens the public community page', (tester) async {
      await pumpDiscover(tester);
      await openCommunities(tester);

      await tester.tap(find.text('Weekly six-a-side'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicCommunityScreen), findsOneWidget);
      // What it shows is the community and what it has scheduled -- now on the
      // same Club hero a member's view of the identical community opens with,
      // so the figures are a value and a label rather than one sentence.
      expect(find.text('Muscat United'), findsWidgets);
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(ClubSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ClubHero),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      // It opens on Latest Results; what is scheduled is the second tab.
      expect(find.text('Friday night five-a-side'), findsNothing);
      await tester.tap(find
          .descendant(of: find.byType(DiscoverTabs), matching: find.byType(Tab))
          .at(1));
      await tester.pumpAndSettle();
      expect(find.text('Friday night five-a-side'), findsOneWidget);
    });

    testWidgets('joining from that page still asks for an account',
        (tester) async {
      await pumpDiscover(tester);
      await openCommunities(tester);
      await tester.tap(find.text('Weekly six-a-side'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();

      expect(find.text('Create an account to join this community.'),
          findsOneWidget);
    });
  });

  group('a member gets the same page, addressed to them', () {
    const profile = PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    );

    testWidgets('the banner greets them instead of pitching', (tester) async {
      await pumpDiscover(tester, signedIn: true, profile: profile);
      // The profile is read asynchronously by the identity menu.
      await tester.pumpAndSettle();

      expect(find.text('Welcome back, Salim'), findsOneWidget);
      expect(find.text('Football, with your people.'), findsNothing);
      // Nobody who is signed in is asked to sign up, in either place.
      expect(find.text('Create account'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Log in'), findsNothing);
    });

    testWidgets('a profile that has not arrived is not greeted by name',
        (tester) async {
      // The fallback matters: a greeting addressed to nobody is worse than the
      // headline it replaced.
      await pumpDiscover(tester, signedIn: true);

      expect(find.text('Football, with your people.'), findsOneWidget);
      expect(find.textContaining('Welcome back'), findsNothing);
    });

    testWidgets('both asks become the one a member can act on', (tester) async {
      await pumpDiscover(tester, signedIn: true);

      // The banner, and only the banner.
      expect(find.text('Create community'), findsOneWidget);
      expect(find.text('Start something of your own'), findsNothing);
    });

    testWidgets('the actions lead somewhere instead of asking for an account',
        (tester) async {
      await pumpDiscover(tester, signedIn: true);

      expect(find.text('View match'), findsOneWidget);
      expect(find.text('Join match'), findsNothing);

      // No sheet: the gate is open, so a tap goes to the real screen. That
      // navigation reaches the production repositories and is exercised on a
      // device, not here — what this asserts is that the gate does not fire.
      expect(find.text('Account needed'), findsNothing);
    });

    testWidgets('the identity menu is reachable from the home screen',
        (tester) async {
      // Discover has no AppHeader to carry it, and it is now the first thing a
      // signed-in player sees — without this there is no way to their profile
      // or out of the session from the screen the app opens on.
      await pumpDiscover(tester, signedIn: true, profile: profile);
      await tester.pumpAndSettle();

      expect(find.byType(CurrentUserMenu), findsOneWidget);
    });
  });

  group('a community mark is the letter you would name it by', () {
    String initialsOf(String name) => community('c1', name).initials;

    test('a Latin name gives up to two initials', () {
      expect(initialsOf('Muscat United'), 'MU');
      expect(initialsOf('Seeb'), 'S');
      expect(initialsOf('Sohar Football Club'), 'SF');
    });

    test('the Arabic definite article is skipped', () {
      // Every club named "الـ..." reduced to the same mark before this, which
      // made half the page look identical.
      expect(initialsOf('البحر'), 'ب');
      expect(initialsOf('الشمال'), 'ش');
      expect(initialsOf('السلام'), 'س');
      expect(initialsOf('النصر'), 'ن');
    });

    test('a name without the article is untouched', () {
      expect(initialsOf('نجوم'), 'ن');
      expect(initialsOf('صحار'), 'ص');
    });

    test('the article is skipped per word, not once', () {
      expect(initialsOf('البحر الأزرق'), 'بأ');
    });

    test('a name that is only the article keeps its own letters', () {
      // The stem would be empty, so the skip does not apply and nothing
      // indexes past the end.
      expect(initialsOf('ال'), 'ا');
    });

    test('an empty name has no mark rather than a crash', () {
      expect(initialsOf('   '), '');
    });
  });

  group('the sections are titled, not numbered', () {
    testWidgets('no count is shown beside a section heading', (tester) async {
      // A bare "1" beside a heading read as a debugging marker on the device.
      // The cards below are the count.
      await pumpDiscover(
        tester,
        communities: [community('c1', 'Muscat United')],
        matches: [match('m1')],
      );

      expect(find.text('Upcoming matches'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
      // '1' would be the old match-section pill; '2' never applied here.
      expect(find.text('1'), findsNothing);
      // And the banner no longer reports a total either.
      expect(find.text('1 upcoming match'), findsNothing);
    });
  });

  group('the banner reports what is on the platform', () {
    testWidgets('the hero claims no totals at all', (tester) async {
      // **The count chips are gone.** They were a live pulse of how much
      // football exists -- a statistic about the product rather than a way
      // into it -- and they pushed the tabs down the screen.
      await pumpDiscover(
        tester,
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Seeb Strikers'),
        ],
        matches: [match('m1'), match('m2'), match('m3')],
      );

      expect(find.text('2 communities'), findsNothing);
      expect(find.text('3 upcoming matches'), findsNothing);
      // What is under the headline is the way in.
      expect(find.byType(DiscoverTabs), findsOneWidget);
    });

    testWidgets('nothing is claimed before the read comes back',
        (tester) async {
      await pumpDiscover(tester, failure: StateError('offline'));

      expect(find.textContaining('communities'), findsNothing);
    });
  });

  group('long content stays inside Club cards', () {
    testWidgets('long English community, title, and location are safe at 320',
        (tester) async {
      const communityName =
          'The Extremely Long Community Name Football Association Of Muscat';
      const matchTitle =
          'The Very Long Friday Evening Football Match Title For Every Player';
      const location =
          'The Extremely Long Al Amerat Football Ground Location Description';
      await pumpDiscover(
        tester,
        communities: [community('c1', communityName)],
        matches: [match('m1', title: matchTitle, location: location)],
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text(matchTitle)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(location)).overflow,
          TextOverflow.ellipsis);

      await openCommunities(tester);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text(communityName)).overflow,
          TextOverflow.ellipsis);
    });

    testWidgets('long Arabic content is safe at 320 RTL', (tester) async {
      const communityName =
          'نادي المجتمع الرياضي لكرة القدم في ولاية العامرات بمحافظة مسقط';
      const matchTitle =
          'مباراة كرة القدم المسائية الطويلة جداً لجميع لاعبي المجتمع';
      const location = 'ملعب العامرات الرئيسي لكرة القدم في محافظة مسقط';
      await pumpDiscover(
        tester,
        communities: [community('c1', communityName)],
        matches: [match('m1', title: matchTitle, location: location)],
        locale: const Locale('ar'),
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(ClubHero))),
        TextDirection.rtl,
      );
      expect(tester.widget<Text>(find.text(matchTitle)).overflow,
          TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text(location)).overflow,
          TextOverflow.ellipsis);

      // The tab control itself has to survive 320px in Arabic, with every
      // label whole -- it scrolls rather than shrinking them.
      expect(find.byType(DiscoverTabs), findsOneWidget);

      await openCommunities(tester);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text(communityName)).overflow,
          TextOverflow.ellipsis);
    });
  });

  group('both sections are laid out as grids', () {
    /// How many cards share the topmost row.
    ///
    /// Position rather than tree structure: the claim is that two cards ended
    /// up beside each other, and a card's top edge says so however the rows
    /// happen to be built.
    int columnsOf(WidgetTester tester, Finder cards) {
      final count = tester.widgetList(cards).length;
      expect(count, greaterThan(0), reason: 'nothing was rendered');
      var top = double.infinity;
      for (var i = 0; i < count; i++) {
        final dy = tester.getTopLeft(cards.at(i)).dy;
        if (dy < top) top = dy;
      }
      var first = 0;
      for (var i = 0; i < count; i++) {
        if ((tester.getTopLeft(cards.at(i)).dy - top).abs() < 0.5) first++;
      }
      return first;
    }

    testWidgets('matches and communities both sit two across', (tester) async {
      await pumpDiscover(
        tester,
        matches: [match('m1'), match('m2'), match('m3')],
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Al Amerat FC'),
          community('c3', 'Seeb Rovers'),
        ],
      );

      expect(columnsOf(tester, find.byType(CompactPublicMatchCard)), 2);
      // Two, and never three: these are read at a glance, and a wide window
      // gets wider cards rather than more of them.
      expect(find.byType(CompactPublicMatchCard), findsNWidgets(3));

      await openCommunities(tester);
      expect(columnsOf(tester, find.byType(CompactPublicCommunityCard)), 2);
    });

    testWidgets('and give the column up on a narrow phone', (tester) async {
      // 320 wide leaves 292 to the cards once the sheet's gutters are taken,
      // which is under the 310 two columns of match card need.
      await pumpDiscover(
        tester,
        matches: [match('m1'), match('m2')],
        communities: [
          community('c1', 'Muscat United'),
          community('c2', 'Al Amerat FC'),
        ],
        size: const Size(320, 900),
      );

      expect(tester.takeException(), isNull);
      expect(columnsOf(tester, find.byType(CompactPublicMatchCard)), 1);

      await openCommunities(tester);
      expect(columnsOf(tester, find.byType(CompactPublicCommunityCard)), 1);
    });

    testWidgets('the community pages keep the single-column card',
        (tester) async {
      // The grid was approved for Discover. `PublicMatchCard` is still what a
      // community's own page draws, and this says so — the compact card is an
      // addition, not a replacement.
      await pumpDiscover(tester, matches: [match('m1')]);

      expect(find.byType(PublicMatchCard), findsNothing,
          reason: 'Discover uses the compact card now');
      expect(find.byType(CompactPublicMatchCard), findsOneWidget);
    });

    testWidgets('no community picture is introduced anywhere', (tester) async {
      // The community logo is a later phase. What identifies a community here
      // is its crest — its initials — exactly as it did before the grid.
      await pumpDiscover(
        tester,
        communities: [community('c1', 'Muscat United')],
      );
      await openCommunities(tester);

      expect(find.byType(CommunityCrest), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('the skeleton is laid out the way the cards will be',
        (tester) async {
      // Held mid-read, so this is the frame a visitor actually sees first. It
      // used to be a column of row-shaped placeholders under a page that then
      // arrived two across, and the page changed shape as it landed.
      await pumpDiscover(
        tester,
        delay: const Duration(seconds: 1),
        settle: false,
      );

      // The same skeleton stands in every tab while the one read is in
      // flight, so the shape a reader sees first is the shape that arrives.
      expect(find.byType(CompactMatchGridSkeleton), findsWidgets);
      expect(find.byType(CompactCommunityGridSkeleton), findsWidgets);
      expect(columnsOf(tester, find.byType(CompactMatchCardSkeleton)), 2);
      expect(tester.takeException(), isNull);

      // Let the held read finish so the test leaves no timer behind.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await openUpcoming(tester);
      expect(find.byType(CompactPublicMatchCard), findsWidgets);
    });

    testWidgets('and gives up its column on a narrow phone too',
        (tester) async {
      await pumpDiscover(
        tester,
        size: const Size(320, 900),
        delay: const Duration(seconds: 1),
        settle: false,
      );

      expect(columnsOf(tester, find.byType(CompactMatchCardSkeleton)), 1);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('and the page does not change shape when the read lands',
        (tester) async {
      // The correction, stated as the thing a reader would notice: the number
      // of columns before and after are the same number.
      await pumpDiscover(
        tester,
        matches: [match('m1'), match('m2'), match('m3')],
        delay: const Duration(seconds: 1),
        settle: false,
      );
      final loading = columnsOf(tester, find.byType(CompactMatchCardSkeleton));

      await tester.pumpAndSettle(const Duration(seconds: 2));
      await openUpcoming(tester);
      final loaded = columnsOf(tester, find.byType(CompactPublicMatchCard));

      expect(loading, loaded);
    });
  });

  group('Near: nearby discovery by Wilayat', () {
    const sohar = 7;
    const salalah = 51;
    const muscat = 1;

    final soon = DateTime.now().add(const Duration(days: 30));

    PublicMatch matchIn(
      String id,
      int? wilayat, {
      DateTime? start,
      DateTime? end,
      String? title,
    }) {
      final startAt = start ?? soon;
      return PublicMatch(
        id: id,
        communityId: 'c-$id',
        communityName: 'Club $id',
        location: 'Pitch $id',
        startAt: startAt,
        endAt: end ?? startAt.add(const Duration(hours: 2)),
        startingPlayers: 10,
        openSlots: 4,
        title: title ?? 'Match $id',
        wilayatCode: wilayat,
      );
    }

    PublicCommunity communityIn(String id, int? wilayat, {DateTime? active}) =>
        PublicCommunity(
          id: id,
          name: 'Club $id',
          memberCount: 8,
          upcomingMatchCount: 1,
          wilayatCode: wilayat,
          lastActivityAt: active,
        );

    const profileInSohar = PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890000000',
      primaryPosition: PlayerPosition.mid,
      defaultWilayatCode: sohar,
    );

    WilayatRepository catalogOf() => WilayatRepository(FakeWilayatAdapter());

    List<String> shownMatches(WidgetTester tester) => [
          for (final card in tester.widgetList<CompactPublicMatchCard>(
              find.byType(CompactPublicMatchCard)))
            card.match.id,
        ];

    List<String> shownCommunities(WidgetTester tester) => [
          for (final card in tester.widgetList<CompactPublicCommunityCard>(
              find.byType(CompactPublicCommunityCard)))
            card.community.id,
        ];

    Finder chip() => find.byKey(const Key('discoverNearChip'));

    Future<void> chooseNear(WidgetTester tester, int code) async {
      await tester.tap(chip());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('wilayat_$code')));
      await tester.pumpAndSettle();
    }

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('a signed-in reader starts from their Default Location',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: profileInSohar,
        wilayats: catalogOf(),
        matches: [
          matchIn('far', salalah, start: soon),
          matchIn('near', sohar, start: soon.add(const Duration(days: 2))),
        ],
      );

      expect(find.text('Near: Sohar'), findsOneWidget);
      expect(shownMatches(tester), ['near', 'far']);
    });

    testWidgets('Communities: local first, then the rest by latest activity',
        (tester) async {
      final old = DateTime.utc(2027, 1, 1);
      final recent = DateTime.utc(2027, 3, 1);
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: profileInSohar,
        wilayats: catalogOf(),
        tab: 2,
        communities: [
          communityIn('far-recent', salalah, active: recent),
          communityIn('none-old', null, active: old),
          communityIn('near-old', sohar, active: old),
        ],
      );

      expect(shownCommunities(tester), ['near-old', 'far-recent', 'none-old']);
    });

    testWidgets(
        'changing Near overrides the Default Location for the session '
        'and writes nothing', (tester) async {
      final profiles = _StaticProfileAdapter(profileInSohar);
      await pumpDiscover(
        tester,
        signedIn: true,
        profileAdapter: profiles,
        wilayats: catalogOf(),
        matches: [
          matchIn('sohar', sohar, start: soon.add(const Duration(days: 2))),
          matchIn('salalah', salalah, start: soon),
        ],
      );
      expect(shownMatches(tester), ['sohar', 'salalah']);

      await chooseNear(tester, salalah);

      expect(find.text('Near: Salalah'), findsOneWidget);
      expect(shownMatches(tester), ['salalah', 'sohar']);
      // The Default Location is the player's setting: Near never touches it.
      expect(profiles.defaultWilayatWrites, isEmpty);
      expect(CurrentUser.instance.profile.value?.defaultWilayatCode, sohar);
    });

    testWidgets('a new session returns to the Default Location',
        (tester) async {
      final profiles = _StaticProfileAdapter(profileInSohar);
      Future<void> session() => pumpDiscover(
            tester,
            signedIn: true,
            profileAdapter: profiles,
            wilayats: catalogOf(),
          );

      await session();
      await chooseNear(tester, salalah);
      expect(find.text('Near: Salalah'), findsOneWidget);

      // The screen going away and a new one being built is a new session.
      await tester.pumpWidget(const SizedBox());
      await session();

      expect(find.text('Near: Sohar'), findsOneWidget);
    });

    testWidgets(
        'a signed-in reader with no Default Location is asked to choose',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: const PlayerProfile(
          fullName: 'Salim Al Harthy',
          phone: '+96890000000',
          primaryPosition: PlayerPosition.mid,
        ),
        wilayats: catalogOf(),
      );

      expect(find.text('Near: choose Wilayat'), findsOneWidget);
    });

    testWidgets('a guest chooses a Wilayat on the device, and it is remembered',
        (tester) async {
      await pumpDiscover(tester, wilayats: catalogOf());
      expect(find.text('Near: choose Wilayat'), findsOneWidget);

      await chooseNear(tester, sohar);

      expect(find.text('Near: Sohar'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(GuestLocationStore.key), sohar);

      await tester.pumpWidget(const SizedBox());
      await pumpDiscover(tester, wilayats: catalogOf());
      expect(find.text('Near: Sohar'), findsOneWidget);
    });

    testWidgets('a guest choice is never sent to an account', (tester) async {
      final profiles = _StaticProfileAdapter(profileInSohar);
      await pumpDiscover(
        tester,
        profileAdapter: profiles,
        wilayats: catalogOf(),
      );

      await chooseNear(tester, salalah);

      expect(profiles.defaultWilayatWrites, isEmpty);
    });

    testWidgets('a stored code that is inactive or unknown is no location',
        (tester) async {
      for (final stale in [55, 999]) {
        SharedPreferences.setMockInitialValues({GuestLocationStore.key: stale});
        await pumpDiscover(tester, wilayats: catalogOf());

        expect(find.text('Near: choose Wilayat'), findsOneWidget,
            reason: 'code $stale is not offered any more');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Wilayat is labelled on Upcoming Matches and Communities only',
        (tester) async {
      final adapterResults = [
        PublicResult(
          matchId: 'r1',
          communityId: 'c-r1',
          communityName: 'Result Club',
          startAt: DateTime(2026, 9, 1, 20),
          teamAScore: 3,
          teamBScore: 1,
        ),
      ];
      await pumpDiscover(
        tester,
        wilayats: catalogOf(),
        recentResults: adapterResults,
        tab: 0,
        matches: [matchIn('m', sohar)],
        communities: [communityIn('m', sohar)],
      );

      // Latest Results: no Wilayat anywhere, and no Near control over it.
      expect(find.byType(PublicResultCard), findsOneWidget);
      expect(find.text('Sohar'), findsNothing);
      expect(chip(), findsNothing);

      await openUpcoming(tester);
      expect(
        find.descendant(
            of: find.byType(CompactPublicMatchCard),
            matching: find.text('Sohar')),
        findsOneWidget,
      );
      expect(chip(), findsOneWidget);

      await openCommunities(tester);
      expect(
        find.descendant(
            of: find.byKey(const Key('communityWilayatLine')),
            matching: find.text('Sohar')),
        findsOneWidget,
      );
      expect(chip(), findsOneWidget);
    });

    testWidgets('a community with no Wilayat carries no label', (tester) async {
      await pumpDiscover(
        tester,
        wilayats: catalogOf(),
        tab: 2,
        communities: [communityIn('a', null)],
      );

      expect(find.byKey(const Key('communityWilayatLine')), findsNothing);
      expect(find.byType(CompactPublicCommunityCard), findsOneWidget);
    });

    testWidgets('the label and the chip follow the reader\'s language',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: profileInSohar,
        wilayats: catalogOf(),
        locale: const Locale('ar'),
        matches: [matchIn('m', sohar)],
      );

      expect(find.text('قريب من: صحار'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(CompactPublicMatchCard),
            matching: find.text('صحار')),
        findsOneWidget,
      );
    });

    testWidgets('a match in play is badged LIVE, one that has not begun is not',
        (tester) async {
      final now = DateTime.now();
      await pumpDiscover(
        tester,
        wilayats: catalogOf(),
        matches: [
          matchIn('live', sohar,
              start: now.subtract(const Duration(hours: 1)),
              end: now.add(const Duration(hours: 1))),
          matchIn('later', sohar, start: now.add(const Duration(days: 1))),
        ],
      );

      expect(find.byKey(const Key('matchLiveBadge')), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      final liveCard = find.ancestor(
        of: find.byKey(const Key('matchLiveBadge')),
        matching: find.byType(CompactPublicMatchCard),
      );
      expect(
        tester.widget<CompactPublicMatchCard>(liveCard).match.id,
        'live',
      );
      // LIVE is a badge, and the order is still by start: it leads its group.
      expect(shownMatches(tester), ['live', 'later']);
    });

    testWidgets(
        'with nothing local everything is still shown, without a '
        'message', (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: const PlayerProfile(
          fullName: 'Salim',
          phone: '+96890000000',
          primaryPosition: PlayerPosition.mid,
          defaultWilayatCode: muscat,
        ),
        wilayats: catalogOf(),
        matches: [
          matchIn('a', sohar),
          matchIn('b', salalah, start: soon.add(const Duration(days: 1))),
        ],
      );

      expect(find.text('Near: Muscat'), findsOneWidget);
      expect(shownMatches(tester), ['a', 'b']);
      expect(find.byType(DiscoverEmpty), findsNothing);
    });

    testWidgets('the picker searches by either hamza spelling and by alias',
        (tester) async {
      await pumpDiscover(tester, wilayats: catalogOf());
      await tester.tap(chip());
      await tester.pumpAndSettle();

      Future<void> search(String text) async {
        await tester.enterText(
            find.byKey(const Key('wilayatSearchField')), text);
        await tester.pumpAndSettle();
      }

      await search('ازكي');
      expect(find.byKey(const Key('wilayat_34')), findsOneWidget);
      expect(find.byKey(const Key('wilayat_7')), findsNothing);

      await search('مجيس');
      expect(find.byKey(const Key('wilayat_7')), findsOneWidget);
      expect(find.byKey(const Key('wilayat_34')), findsNothing);

      await search('nothing-like-this');
      expect(find.text('No Wilayat matches your search.'), findsOneWidget);
    });

    testWidgets(
        'the picker offers active Wilayats only, grouped by Governorate',
        (tester) async {
      await pumpDiscover(tester, wilayats: catalogOf());
      await tester.tap(chip());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wilayat_51')), findsOneWidget);
      expect(find.byKey(const Key('wilayat_55')), findsNothing,
          reason: 'Sadh is retired');
      expect(find.text('Al Batinah North'), findsOneWidget);
      expect(find.text('Dhofar'), findsOneWidget);
    });

    testWidgets('without the names the page still orders, and offers a retry',
        (tester) async {
      await pumpDiscover(
        tester,
        signedIn: true,
        profile: profileInSohar,
        wilayats:
            WilayatRepository(FakeWilayatAdapter(failure: StateError('x'))),
        matches: [
          matchIn('far', salalah, start: soon),
          matchIn('near', sohar, start: soon.add(const Duration(days: 2))),
        ],
      );

      // Ordering needs codes, not names, so local still leads...
      expect(shownMatches(tester), ['near', 'far']);
      // ...and no card claims a Wilayat it cannot name.
      expect(find.text('Sohar'), findsNothing);
      expect(find.text('Near: choose Wilayat'), findsOneWidget);

      await tester.tap(chip());
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

/// Answers from memory, with no session anywhere in sight.
class _FakeDiscoverAdapter implements DiscoverAdapter {
  /// Nothing recorded and nobody ranked: this suite is not about football.
  @override
  Future<PublicCommunityFootballRecord> fetchCommunityFootballRecord(
    String communityId,
  ) async =>
      PublicCommunityFootballRecord(
        communityId: communityId,
        completedMatches: 0,
        players: 0,
        goals: 0,
        mvpCount: 0,
      );

  @override
  Future<List<PublicCommunityTopPlayer>> fetchCommunityTopPlayers(
    String communityId,
  ) async =>
      const [];

  @override
  Future<List<PublicResult>> fetchRecentResults({
    String? communityId,
    int limit = 5,
  }) async {
    recentResultsRequests.add(communityId);
    return [
      for (final result in recentResults)
        if (communityId == null || result.communityId == communityId) result,
    ].take(limit).toList();
  }

  /// What the public results contract answers with.
  List<PublicResult> recentResults = const [];

  /// One entry per read, carrying the community it was scoped to (null for
  /// Discover's list across every community).
  final List<String?> recentResultsRequests = [];
  _FakeDiscoverAdapter({
    required this.communities,
    required this.matches,
    this.failure,
    this.delay,
  });

  final List<PublicCommunity> communities;
  final List<PublicMatch> matches;

  /// Thrown by every read when set, which is how a visitor on a bad connection
  /// is reproduced.
  final Object? failure;

  /// Held for this long before answering, so a test can look at the screen
  /// while the read is still in flight. Null answers in the same turn, which is
  /// what every test that is not about the loading state wants.
  final Duration? delay;

  Future<void> _hold() async {
    if (delay != null) await Future<void>.delayed(delay!);
  }

  @override
  Future<List<PublicCommunity>> fetchCommunities() async {
    await _hold();
    if (failure != null) throw failure!;
    return communities;
  }

  @override
  Future<PublicCommunity> fetchCommunity(String communityId) async {
    if (failure != null) throw failure!;
    return communities.firstWhere((c) => c.id == communityId);
  }

  @override
  Future<PublicMatchDetail?> fetchMatchDetail(String matchId) async {
    if (failure != null) throw failure!;
    for (final match in matches) {
      if (match.id == matchId) return PublicUpcomingMatch(match: match);
    }
    // No row is how the public contract says "not publicly visible", and the
    // fake says it the same way rather than throwing.
    return null;
  }

  @override
  Future<List<PublicLineupEntry>> fetchMatchLineup(String matchId) async =>
      const [];

  @override
  Future<List<PublicMatch>> fetchUpcomingMatches({String? communityId}) async {
    await _hold();
    if (failure != null) throw failure!;
    if (communityId == null) return matches;
    return [
      for (final m in matches)
        if (m.communityId == communityId) m,
    ];
  }
}

/// Says whether somebody is signed in, and nothing else — every method that
/// would change that is out of this test's scope and says so.
class _StubAuthAdapter with AuthAdapterDefaults implements AuthAdapter {
  _StubAuthAdapter({required this.signedIn});

  final bool signedIn;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentUserId => signedIn ? 'u1' : null;

  @override
  String? get currentUserEmail => null;

  @override
  Stream<bool> get signedInChanges => const Stream<bool>.empty();

  @override
  Future<String?> fetchCurrentUserFullName() async => null;

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
    required String redirectTo,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> signIn(
          {required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) async =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) async =>
      throw UnimplementedError();

  @override
  Future<bool> isCurrentUserActive() async => true;

  @override
  Future<void> signOut() async => throw UnimplementedError();
}

/// The profile the greeting reads, answered from memory.
class _StaticProfileAdapter implements ProfileAdapter {
  _StaticProfileAdapter(this.profile);

  final PlayerProfile profile;

  /// Every Default Location written through this port. Near must never add to
  /// it: choosing where "near" is, in Discover, is not saving a setting.
  final defaultWilayatWrites = <int?>[];

  @override
  Future<void> updateMyDefaultWilayat(int? wilayatCode) async {
    defaultWilayatWrites.add(wilayatCode);
  }

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

  // Requirement 2 added two members to the port. Neither is reached from this
  // test, so both refuse rather than answer.
  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}

/// A football port that answers from a list, or refuses.
///
/// Only Discover's two signed-in reads are exercised here; the rest throw so a
/// screen that started calling them would say so rather than pass quietly.
class _FakeFootballAdapter implements FootballAdapter {
  _FakeFootballAdapter({this.results = const [], this.failure});

  final List<CompletedMatch> results;
  final Object? failure;
  var completedCalls = 0;

  @override
  Future<List<CompletedMatch>> fetchCompletedMatches({
    String? communityId,
    int limit = 50,
  }) async {
    completedCalls++;
    if (failure != null) throw failure!;
    return results;
  }

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) =>
      throw UnimplementedError();
  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) =>
      throw UnimplementedError();
  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) =>
      throw UnimplementedError();
  @override
  Future<CommunityFootballStats> fetchCommunityStats(String communityId) =>
      throw UnimplementedError();
  @override
  Future<List<CommunityPlayerStats>> fetchCommunityPlayerStats(
          String communityId) =>
      throw UnimplementedError();
}

/// A community port that reports which communities the reader has joined, and
/// refuses everything else — Discover reads exactly one thing from it.
class _JoinedCommunitiesAdapter implements CommunityAdapter {
  _JoinedCommunitiesAdapter(this.joinedIds);

  final List<String> joinedIds;
  var myCommunitiesCalls = 0;

  @override
  Future<void> setCommunityWilayat(String communityId, int wilayatCode) =>
      throw UnimplementedError();

  @override
  Future<List<Community>> fetchMyCommunities() async {
    myCommunitiesCalls++;
    return [
      for (final id in joinedIds)
        Community(
          id: id,
          ownerId: 'owner',
          name: 'Joined $id',
          joinPolicy: JoinPolicy.open,
        ),
    ];
  }

  @override
  Future<List<Community>> fetchManagedCommunities() =>
      throw UnimplementedError();

  @override
  Future<List<Community>> fetchAllCommunities() => throw UnimplementedError();
  @override
  Future<Community> fetchCommunity(String communityId) =>
      throw UnimplementedError();
  @override
  Future<String> createCommunity({
    required String name,
    String? description,
    required JoinPolicy joinPolicy,
    required int wilayatCode,
  }) =>
      throw UnimplementedError();
  @override
  Future<String> joinCommunity(String communityId) =>
      throw UnimplementedError();
  @override
  Future<String> joinCommunityByCode(String code) => throw UnimplementedError();
  @override
  Future<void> setJoinPolicy(String communityId,
          {required JoinPolicy joinPolicy}) =>
      throw UnimplementedError();
  @override
  Future<String> fetchJoinCode(String communityId) =>
      throw UnimplementedError();
  @override
  Future<CommunityInvitePreview> previewInvite(String code) =>
      throw UnimplementedError();
  @override
  Future<String> regenerateJoinCode(String communityId) =>
      throw UnimplementedError();
  @override
  Future<void> deleteCommunity(String communityId) =>
      throw UnimplementedError();

  @override
  Future<String> uploadCommunityLogo({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setCommunityLogo(String communityId, String? logoUrl) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCommunityLogoObject(String logoUrl) =>
      throw UnimplementedError();
}
