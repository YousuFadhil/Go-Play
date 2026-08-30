import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/football_components.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/theme.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/matches/match_models.dart';

/// The shared match components.
///
/// These used to be four private widgets in four files, and the thing worth
/// asserting is not that each draws — it is that the same state now produces
/// the same drawing wherever it is met. So the chip tests read the colour
/// rather than the presence, and the capacity tests count segments rather than
/// looking for a bar.
///
/// [RegistrationStateView] is tested as the widget it is: handed the booleans
/// the screen works out, never a roster. That is the whole point of the
/// extraction — the conditions stay in Match Details, and what is proved here
/// is that each combination of them still reaches the state it always did.
void main() {
  /// [settle] is off for anything showing the in-flight spinner: it animates
  /// forever by design, so `pumpAndSettle` would wait for an end that never
  /// comes. That is the app's own loading indicator and not something this
  /// phase changed.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// The chip's own fill, read off the box it paints.
  Color chipBackground(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GoStatusChip),
            matching: find.byType(Container),
          )
          .first,
    );
    return ((container.decoration as BoxDecoration).color)!;
  }

  group('GoStatusChip', () {
    testWidgets('an open match is the open tone', (tester) async {
      await pump(
        tester,
        GoStatusChip(label: 'Open', tone: MatchStatus.open.chipTone),
      );

      expect(find.text('Open'), findsOneWidget);
      expect(chipBackground(tester), GoColors.statusOpenBg);
    });

    testWidgets('a full match is amber, not grey', (tester) async {
      // The one judgement the direction encodes: grey said "disabled", and a
      // match that has filled up is a healthy match.
      await pump(
        tester,
        GoStatusChip(label: 'Full', tone: MatchStatus.full.chipTone),
      );

      expect(chipBackground(tester), GoColors.statusFullBg);
      expect(chipBackground(tester), isNot(GoColors.statusOpenBg));
    });

    testWidgets('a played match is the completed tone', (tester) async {
      await pump(
        tester,
        GoStatusChip(label: 'Played', tone: MatchStatus.completed.chipTone),
      );

      expect(chipBackground(tester), GoColors.rowTintDeep);
    });

    testWidgets('a locked match carries the padlock', (tester) async {
      await pump(
        tester,
        const GoStatusChip(
          label: 'Full',
          tone: GoChipTone.full,
          icon: Icons.lock_outline,
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('an unlocked match carries no glyph', (tester) async {
      await pump(tester, const GoStatusChip(label: 'Open'));

      expect(find.byType(Icon), findsNothing);
    });
  });

  group('GoRoleChip', () {
    testWidgets('a role is drawn as a square, not a pill', (tester) async {
      await pump(tester, const GoRoleChip(label: 'Owner'));

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GoRoleChip),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      // The shape is what separates a person's role from a thing's status, and
      // the two sit side by side often enough for it to matter.
      expect(
        decoration.borderRadius,
        BorderRadius.circular(6),
      );
    });

    testWidgets('each role renders its own word', (tester) async {
      for (final role in ['Owner', 'Admin', 'Player']) {
        await pump(tester, GoRoleChip(label: role));
        expect(find.text(role.toUpperCase()), findsOneWidget);
      }
    });
  });

  group('SegmentedCapacityIndicator', () {
    /// Every drawn segment, in order. The spacers are Containers-free
    /// SizedBoxes, so counting decorated boxes counts places.
    List<Color> segments(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(
          of: find.byType(SegmentedCapacityIndicator),
          matching: find.byType(Container),
        ))
        .map((c) => (c.decoration as BoxDecoration).color!)
        .toList();

    testWidgets('one segment per place, starting and reserve', (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 4,
          starting: 10,
          reserve: 6,
        ),
      );

      expect(segments(tester), hasLength(16));
    });

    testWidgets('taken places are filled and the rest are track',
        (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 4,
          starting: 10,
          reserve: 6,
        ),
      );

      final drawn = segments(tester);
      expect(drawn.sublist(0, 4), everyElement(GoColors.primaryMid));
      expect(drawn.sublist(4, 10), everyElement(GoColors.capacityTrack));
      expect(drawn.sublist(10), everyElement(GoColors.capacityTrackReserve));
    });

    testWidgets('overflow past the starting places fills the reserve run',
        (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 13,
          starting: 10,
          reserve: 6,
        ),
      );

      final drawn = segments(tester);
      expect(drawn.sublist(0, 10), everyElement(GoColors.primaryMid));
      expect(drawn.sublist(10, 13), everyElement(GoColors.tertiary),
          reason: 'three people are queueing');
      expect(drawn.sublist(13), everyElement(GoColors.capacityTrackReserve));
    });

    testWidgets('a full match fills amber and a played one goes quiet',
        (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 10,
          starting: 10,
          status: MatchStatus.full,
        ),
      );
      expect(segments(tester), everyElement(GoColors.warn));

      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 10,
          starting: 10,
          status: MatchStatus.completed,
        ),
      );
      expect(segments(tester), everyElement(GoColors.capacityCompleted));
    });

    testWidgets('the ratio is isolated left to right', (tester) async {
      // `6/10` inside an Arabic paragraph is a neutral-first run and reverses
      // without this. It is the reason the label is a widget rather than a
      // string appended to the sentence above it.
      await pump(
        tester,
        const Directionality(
          textDirection: TextDirection.rtl,
          child: SegmentedCapacityIndicator(registered: 6, starting: 10),
        ),
      );

      expect(find.text('6/10'), findsOneWidget);
      final isolate = tester.widget<Directionality>(find.ancestor(
        of: find.text('6/10'),
        matching: find.byType(Directionality),
      ).first);
      expect(isolate.textDirection, TextDirection.ltr);
    });

    testWidgets('the label can be left off', (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(
          registered: 6,
          starting: 10,
          showLabel: false,
        ),
      );

      expect(find.text('6/10'), findsNothing);
    });

    testWidgets('a match with no reserve allowance draws no queue',
        (tester) async {
      await pump(
        tester,
        const SegmentedCapacityIndicator(registered: 2, starting: 6),
      );

      expect(segments(tester), hasLength(6));
    });
  });

  group('RegistrationStateView', () {
    const confirmed = MatchRegistration(
      registrationId: 'reg-1',
      userId: 'u1',
      fullName: 'Yousuf Al Amri',
      position: 'MID',
      status: RegistrationStatus.confirmed,
      registrationOrder: 1,
    );

    const reserve = MatchRegistration(
      registrationId: 'reg-2',
      userId: 'u1',
      fullName: 'Yousuf Al Amri',
      position: 'MID',
      status: RegistrationStatus.reserve,
      registrationOrder: 12,
    );

    Future<int> pumpView(
      WidgetTester tester, {
      MatchRegistration? mine,
      bool registrationClosed = false,
      bool startingFull = false,
      bool busy = false,
      VoidCallback? onJoin,
      VoidCallback? onWithdraw,
    }) async {
      await pump(
        settle: !busy,
        tester,
        RegistrationStateView(
          myRegistration: mine,
          registrationClosed: registrationClosed,
          startingFull: startingFull,
          busy: busy,
          onJoin: onJoin ?? () {},
          onWithdraw: onWithdraw ?? () {},
          confirmedCount: 6,
          startingPlayers: 10,
          reserveAllowance: 6,
        ),
      );
      return 0;
    }

    testWidgets('a confirmed place says so and offers only withdrawal',
        (tester) async {
      await pumpView(tester, mine: confirmed);

      expect(find.text('You are registered in this match.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Join match'), findsNothing);
    });

    testWidgets('a reserve place is a different sentence and a different glyph',
        (tester) async {
      await pumpView(tester, mine: reserve);

      expect(find.text('You are on the reserve list.'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      // Leaving is the same action either way: the queue is not a lesser
      // registration.
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets('holding no registration offers the join', (tester) async {
      await pumpView(tester);

      expect(find.text('Join match'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('You are registered in this match.'), findsNothing);
    });

    testWidgets('a full starting eleven warns before it offers',
        (tester) async {
      await pumpView(tester, startingFull: true);

      expect(
        find.text('The match is full. Joining now adds you to the reserve list.'),
        findsOneWidget,
      );
      // The note is a line above the button, not a replacement for it — joining
      // a full match is what puts somebody in the queue.
      expect(find.text('Join match'), findsOneWidget);
    });

    testWidgets('a closed registration offers nothing at all', (tester) async {
      await pumpView(tester, registrationClosed: true);

      expect(find.text('Registration is closed; the match reached its maximum.'),
          findsOneWidget);
      expect(find.text('Join match'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('holding a registration outranks a closed match',
        (tester) async {
      // The branch order this screen has always used. A player already in a
      // match that has since hit its cap must still be able to leave it.
      await pumpView(tester, mine: confirmed, registrationClosed: true);

      expect(find.text('You are registered in this match.'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
    });

    testWidgets('join and withdraw still reach the screen', (tester) async {
      var joins = 0;
      var withdrawals = 0;

      await pumpView(tester, onJoin: () => joins++);
      await tester.tap(find.text('Join match'));
      await tester.pumpAndSettle();
      expect(joins, 1);

      await pumpView(tester, mine: confirmed, onWithdraw: () => withdrawals++);
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(withdrawals, 1);
    });

    testWidgets('a request in flight disables both actions', (tester) async {
      var joins = 0;
      await pumpView(tester, busy: true, onJoin: () => joins++);

      final join = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(join.onPressed, isNull);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(joins, 0);

      await pumpView(tester, mine: confirmed, busy: true);
      final withdraw =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(withdraw.onPressed, isNull);
    });

    testWidgets('every state still shows how full the match is',
        (tester) async {
      for (final state in [
        (mine: confirmed, closed: false),
        (mine: null, closed: false),
        (mine: null, closed: true),
      ]) {
        await pumpView(tester, mine: state.mine, registrationClosed: state.closed);
        expect(find.byType(SegmentedCapacityIndicator), findsOneWidget);
        expect(find.text('6/10'), findsOneWidget);
      }
    });
  });
}
