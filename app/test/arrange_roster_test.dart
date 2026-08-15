import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/arrange_roster_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';

/// Administrative roster arrangement, from the client's side.
///
/// **The rules are not tested here and cannot be.** Which participant starts,
/// when administrative ordering activates, what a withdrawal promotes and what
/// a change does to a stored lineup all live in one SQL transaction that this
/// layer only calls. Those are exercised against the database directly —
/// `test/integration/roster_arrangement_test.dart`.
///
/// What this file proves is the half the app owns, and it is a short list:
///
///   1. the two lists drawn are the two lists the server returned, split by the
///      status it wrote and in the order it sent;
///   2. a reorder sends the **whole** participant order, starting first, and
///      sends no seat;
///   3. a swap sends two seat ids and nothing else, in either direction and for
///      either kind of participant;
///   4. every operation is followed by a fresh read, so what is shown
///      afterwards is what the server did rather than what was asked for;
///   5. a refusal is worded, and the roster is re-read anyway.
void main() {
  const matchId = 'match-1';

  Match matchOf({
    int startingPlayers = 3,
    RosterOrderMode mode = RosterOrderMode.registration,
    MatchStatus status = MatchStatus.open,
    Duration startsIn = const Duration(days: 3),
  }) {
    final start = DateTime.now().add(startsIn);
    return Match(
      id: matchId,
      communityId: 'community-1',
      createdBy: 'u0',
      location: 'Pitch',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      startingPlayers: startingPlayers,
      maxRegistration: 9,
      status: status,
      title: 'Wednesday match',
      rosterOrderMode: mode,
    );
  }

  MatchRegistration player(
    String id, {
    required RegistrationStatus status,
    required int order,
    String? name,
  }) =>
      MatchRegistration(
        registrationId: 'reg-$id',
        userId: id,
        fullName: name ?? 'Player $id',
        position: 'MID',
        status: status,
        registrationOrder: order,
      );

  MatchRegistration guest(
    String id,
    String name, {
    required RegistrationStatus status,
    required int order,
  }) =>
      MatchRegistration(
        registrationId: 'reg-$id',
        professionalGuestId: id,
        fullName: name,
        status: status,
        registrationOrder: order,
      );

  /// Three starting community players, then a reserve player and a reserve
  /// guest — the shape every approved example is written over.
  List<MatchRegistration> roster() => [
        player('u1', status: RegistrationStatus.confirmed, order: 1, name: 'Yousuf'),
        player('u2', status: RegistrationStatus.confirmed, order: 2, name: 'Khalid'),
        player('u3', status: RegistrationStatus.confirmed, order: 3, name: 'Ahmed'),
        player('u4', status: RegistrationStatus.reserve, order: 4, name: 'Salem'),
        guest('g1', 'Said', status: RegistrationStatus.reserve, order: 5),
      ];

  Future<FakeMatchAdapter> pumpArrange(
    WidgetTester tester, {
    FakeMatchAdapter? adapter,
    Locale locale = const Locale('en'),
  }) async {
    final matches = adapter ??
        FakeMatchAdapter(match: matchOf(), registrations: roster());
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ArrangeRosterScreen(
          matchId: matchId,
          service: MatchService(matches),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return matches;
  }

  // --- 1. the two lists are the server's --------------------------------------

  group('1. the arrangement shown is the arrangement returned', () {
    testWidgets('starting and reserve are split by the status the server wrote',
        (tester) async {
      await pumpArrange(tester);

      expect(find.text('Starting (3/3)'), findsOneWidget);
      expect(find.text('Reserve (2)'), findsOneWidget);
      // Every participant is drawn, guests included.
      for (final name in ['Yousuf', 'Khalid', 'Ahmed', 'Salem']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Professional (Said)'), findsOneWidget);
    });

    testWidgets('the order drawn is the order the server sent', (tester) async {
      // Deliberately not registration order: the server has arranged this
      // match, and the screen must not re-sort it back.
      await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(mode: RosterOrderMode.manual),
          registrations: [
            guest('g1', 'Said', status: RegistrationStatus.confirmed, order: 5),
            player('u1', status: RegistrationStatus.confirmed, order: 1, name: 'Yousuf'),
            player('u2', status: RegistrationStatus.confirmed, order: 2, name: 'Khalid'),
            player('u3', status: RegistrationStatus.reserve, order: 3, name: 'Ahmed'),
          ],
        ),
      );

      final drawn = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('startingList')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      expect(drawn.indexOf('Professional (Said)') < drawn.indexOf('Yousuf'),
          isTrue,
          reason: 'the guest the server put first is drawn first');
    });

    testWidgets('a match nobody has arranged says so', (tester) async {
      await pumpArrange(tester);
      expect(find.text('Registration order'), findsOneWidget);
      expect(find.text('Arranged by an organizer'), findsNothing);
    });

    testWidgets('an arranged match says so', (tester) async {
      // The state is worth showing because it is permanent: after the first
      // change, registration order stops deciding anything.
      await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(mode: RosterOrderMode.manual),
          registrations: roster(),
        ),
      );
      expect(find.text('Arranged by an organizer'), findsOneWidget);
      expect(find.text('Registration order'), findsNothing);
    });

    testWidgets('a played match says its starting list is a record',
        (tester) async {
      await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(
            status: MatchStatus.completed,
            startsIn: const Duration(days: -3),
          ),
          registrations: roster(),
        ),
      );

      expect(find.byKey(const Key('arrangeCompletedNote')), findsOneWidget);
      // And it is still arrangeable: the approved rule is that an owner or
      // admin manages a match in every state.
      expect(find.byKey(const Key('startingList')), findsOneWidget);
    });
  });

  // --- 2. reordering sends the whole order ------------------------------------

  group('2. a reorder sends the whole participant order', () {
    testWidgets('dragging inside the starting list sends starting then reserve',
        (tester) async {
      final matches = await pumpArrange(tester);

      // The handle, not the row: the row body carries the cross-list drag.
      final handles = find.descendant(
        of: find.byKey(const Key('startingList')),
        matching: find.byIcon(Icons.drag_handle),
      );
      await tester.drag(handles.first, const Offset(0, 140));
      await tester.pumpAndSettle();

      expect(matches.orders, hasLength(1));
      // Every seat exactly once, starting participants first. The reserve half
      // is untouched and still trails the starting half.
      expect(matches.orders.single.$2, hasLength(5));
      expect(matches.orders.single.$2.toSet(), hasLength(5));
      expect(matches.orders.single.$2.sublist(3), ['reg-u4', 'reg-g1']);
      expect(matches.orders.single.$2.first, isNot('reg-u1'),
          reason: 'the dragged participant left the first position');
    });

    testWidgets('the roster is re-read after the order is written',
        (tester) async {
      final matches = await pumpArrange(tester);
      final before = matches.registrationFetches;

      await tester.drag(
        find
            .descendant(
              of: find.byKey(const Key('startingList')),
              matching: find.byIcon(Icons.drag_handle),
            )
            .first,
        const Offset(0, 140),
      );
      await tester.pumpAndSettle();

      expect(matches.registrationFetches, greaterThan(before),
          reason: 'promotion, demotion and lineup reconciliation are all the '
              'server\'s, so the screen re-reads rather than guessing');
    });
  });

  // --- 3. swapping sends two seats --------------------------------------------

  group('3. a swap names two seats and nothing else', () {
    testWidgets('a reserve participant is swapped onto a starting one',
        (tester) async {
      final matches = await pumpArrange(tester);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arrangeSelectionBanner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u3')));
      await tester.pumpAndSettle();

      expect(matches.swaps, [(matchId, 'reg-u4', 'reg-u3')]);
      expect(matches.orders, isEmpty,
          reason: 'a swap is a swap; it never rewrites the whole order');
    });

    testWidgets('a starting participant is swapped onto a reserve one',
        (tester) async {
      final matches = await pumpArrange(tester);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-g1')));
      await tester.pumpAndSettle();

      expect(matches.swaps, [(matchId, 'reg-u1', 'reg-g1')]);
    });

    testWidgets('a Professional Guest is swapped like any other participant',
        (tester) async {
      final matches = await pumpArrange(tester);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u2')));
      await tester.pumpAndSettle();

      // A seat id travels, not a guest id: a guest and a community player are
      // the same kind of thing to this operation.
      expect(matches.swaps, [(matchId, 'reg-g1', 'reg-u2')]);
    });

    testWidgets('tapping the same participant twice cancels the selection',
        (tester) async {
      final matches = await pumpArrange(tester);

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('arrangeSelectionBanner')), findsNothing);
      expect(matches.swaps, isEmpty);
    });

    testWidgets('dropping one participant onto another swaps them',
        (tester) async {
      final matches = await pumpArrange(tester);

      final from = tester.getCenter(find.byKey(const Key('arrangeTile_reg-g1')));
      final to = tester.getCenter(find.byKey(const Key('arrangeTile_reg-u1')));
      final gesture = await tester.startGesture(from);
      // A long press starts the cross-list drag; the reorder handle owns the
      // other one, which is why the two gestures do not collide.
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(matches.swaps, [(matchId, 'reg-g1', 'reg-u1')]);
    });
  });

  // --- 4. refusals -------------------------------------------------------------

  group('4. a refusal is worded and the roster re-read', () {
    testWidgets('a roster that moved underneath says so', (tester) async {
      final matches = await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(),
          registrations: roster(),
          failure: const ConflictFailure(FailureReason.rosterChanged),
        ),
      );
      final before = matches.registrationFetches;

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u3')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The roster changed while you were arranging it'),
        findsOneWidget,
      );
      expect(matches.registrationFetches, greaterThan(before),
          reason: 'a refusal usually means the roster moved, and the next '
              'attempt should see the truth');
    });

    testWidgets('a refused permission says so', (tester) async {
      await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(),
          registrations: roster(),
          failure: const AuthorizationFailure(),
        ),
      );

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u3')));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'),
          findsOneWidget);
    });

    testWidgets('a pair that cannot be exchanged says so', (tester) async {
      await pumpArrange(
        tester,
        adapter: FakeMatchAdapter(
          match: matchOf(),
          registrations: roster(),
          failure: const ValidationFailure(FailureReason.invalidSwap),
        ),
      );

      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrangeSwap_reg-u3')));
      await tester.pumpAndSettle();

      expect(find.text('Those two participants cannot be swapped.'),
          findsOneWidget);
    });
  });

  // --- 5. localization ----------------------------------------------------------

  group('5. the screen is Arabic too', () {
    testWidgets('the sections and the mode are in Arabic', (tester) async {
      await pumpArrange(tester, locale: const Locale('ar'));

      expect(find.text('ترتيب التسجيل'), findsOneWidget);
      expect(find.text('الاحتياط (2)'), findsOneWidget);
      expect(find.text('محترف (Said)'), findsOneWidget);
    });
  });
}

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    required this.match,
    required this.registrations,
    this.failure,
  });

  final Match match;
  List<MatchRegistration> registrations;

  /// What the server refuses with, when it refuses.
  final Failure? failure;

  final List<(String, List<String>)> orders = [];
  final List<(String, String, String)> swaps = [];
  int registrationFetches = 0;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async {
    registrationFetches++;
    return registrations;
  }

  @override
  Future<void> setRosterOrder(
      String matchId, List<String> registrationIds) async {
    if (failure != null) throw failure!;
    orders.add((matchId, registrationIds));
  }

  @override
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) async {
    if (failure != null) throw failure!;
    swaps.add((matchId, firstRegistrationId, secondRegistrationId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
