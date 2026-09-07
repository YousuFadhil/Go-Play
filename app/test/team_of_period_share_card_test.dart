import 'dart:async';
import 'dart:typed_data';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/results/match_result_card.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';
import 'package:go_play/features/statistics/team_of_period_card.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_screen.dart';
import 'package:go_play/features/teams/pitch_view.dart';

/// The Team of Period share card, and the discipline around taking it.
///
/// The property worth most, and checked from several directions: the picture
/// is composed from the snapshot already on screen and never from a fresh
/// read. The rating on it is the player's current global one, taken from that
/// same snapshot — approved by the Product Owner, and drawn the way every
/// other Go Play player card draws it.
void main() {
  final start = DateTime.utc(2026, 8, 30, 20); // Muscat midnight, 31 August
  final end = DateTime.utc(2026, 9, 6, 20); // exclusive: through 6 September

  TeamOfPeriodIdentity identityOf({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    DateTime? from,
    DateTime? to,
    int matches = 3,
  }) =>
      TeamOfPeriodIdentity(
        kind: kind,
        periodKey: kind == TeamOfPeriodKind.weekly ? '2026-W36' : '2026-08',
        periodStart: from ?? start,
        periodEnd: to ?? end,
        qualifyingMatchCount: matches,
        requiredMatches: 1,
      );

  TeamOfPeriodWindow windowOf({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    int matches = 3,
    int side = 5,
    DateTime? from,
    DateTime? to,
  }) =>
      TeamOfPeriodWindow(
        kind: kind,
        periodKey: kind == TeamOfPeriodKind.weekly ? '2026-W36' : '2026-08',
        periodStart: from ?? start,
        periodEnd: to ?? end,
        qualifyingMatchCount: matches,
        requiredMatches: 1,
        evidenceLastChangedAt: null,
        teamSizeObservations: [side, side, side],
        positionShapeObservations: const [
          PositionShapeObservation(
              teamSize: 6, gk: 1, def: 2, mid: 2, fwd: 1, unassigned: 0),
        ],
      );

  TeamOfPeriodCandidate candidateOf(
    String id, {
    Position primary = Position.mid,
    double form = 0.1,
    int goals = 0,
    int mvp = 0,
    double rating = 7.4,
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    DateTime? from,
    DateTime? to,
  }) =>
      TeamOfPeriodCandidate(
        userId: id,
        periodIdentity: identityOf(kind: kind, from: from, to: to),
        eligible: true,
        matchesPlayed: 3,
        participationRate: 1,
        wins: 2,
        draws: 1,
        losses: 0,
        goals: goals,
        goalsPerMatch: goals / 3,
        mvpCount: mvp,
        winRate: 0.6666666666,
        pointsPerGame: 2.3333333333,
        periodFormScore: form,
        goalFormContributionTotal: 0.04,
        periodPrimaryPosition: primary,
        currentOverallRating: rating,
      );

  List<TeamOfPeriodCandidate> squad({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    DateTime? from,
    DateTime? to,
  }) =>
      [
        candidateOf('gk1',
            primary: Position.gk, form: 0.30, kind: kind, from: from, to: to),
        candidateOf('d1',
            primary: Position.def, form: 0.28, kind: kind, from: from, to: to),
        candidateOf('d2',
            primary: Position.def, form: 0.26, kind: kind, from: from, to: to),
        candidateOf('m1',
            primary: Position.mid,
            form: 0.24,
            goals: 3,
            mvp: 2,
            kind: kind,
            from: from,
            to: to),
        candidateOf('f1',
            primary: Position.fwd, form: 0.22, kind: kind, from: from, to: to),
      ];

  Map<String, TeamOfPeriodPlayerIdentity> namesFor(
    Iterable<String> ids, {
    Iterable<String> hidden = const [],
    Map<String, String> longNames = const {},
  }) =>
      {
        for (final id in ids)
          if (!hidden.contains(id))
            id: TeamOfPeriodPlayerIdentity(
              userId: id,
              fullName: longNames[id] ?? 'Player $id',
            ),
      };

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeAdapter adapter,
    _CapturingRenderer? renderer,
    String? communityName = 'Al Amerat FC',
    String? logoUrl,
    Locale locale = const Locale('en'),
    bool settle = true,
    Key? key,
  }) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: TeamOfPeriodScreen(
        key: key,
        communityId: 'c1',
        communityName: communityName,
        communityLogoUrl: logoUrl,
        repository: StatisticsRepository(adapter),
        renderer: renderer,
        shareService: _FakeShareService(),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  bool shareEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(find.byKey(const ValueKey('team-of-period-share')))
          .onPressed !=
      null;

  Future<void> tapShare(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('team-of-period-share')));
    await tester.pumpAndSettle();
  }

  /// Draws whatever template the screen handed the engine, on the real 9:16
  /// surface at its real design size.
  Future<void> pumpCard(
    WidgetTester tester,
    _CapturingRenderer renderer, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = ShareCardCanvas.designSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A fresh key, so the previous MaterialApp element is not reused with the
    // share preview still on its Navigator stack -- the card would then sit
    // offstage beneath that route and every finder would skip it.
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Align(
        alignment: Alignment.topLeft,
        child: ShareCardSurface(child: Builder(builder: renderer.captured!)),
      ),
    ));
    await tester.pump();
  }

  group('when a picture may be taken', () {
    testWidgets('a selected weekly award offers one', (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(find.byKey(const ValueKey('team-of-period-share')), findsOneWidget);
      expect(shareEnabled(tester), isTrue);
    });

    testWidgets('a selected monthly award offers one', (tester) async {
      final from = DateTime.utc(2026, 7, 31, 20);
      final to = DateTime.utc(2026, 8, 31, 20);
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(kind: TeamOfPeriodKind.monthly, from: from, to: to),
          candidates:
              squad(kind: TeamOfPeriodKind.monthly, from: from, to: to),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(shareEnabled(tester), isTrue);
    });

    testWidgets('a period still loading offers nothing to picture',
        (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      )..gate = Completer<void>();

      await pumpScreen(tester, adapter: adapter, settle: false);
      await tester.pump();

      expect(shareEnabled(tester), isFalse);

      adapter.gate!.complete();
      await tester.pumpAndSettle();
      expect(shareEnabled(tester), isTrue);
    });

    testWidgets('a period with no qualifying matches cannot be shared',
        (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: TeamOfPeriodWindow(
            kind: TeamOfPeriodKind.weekly,
            periodKey: '2026-W36',
            periodStart: start,
            periodEnd: end,
            qualifyingMatchCount: 0,
            requiredMatches: 0,
            evidenceLastChangedAt: null,
            teamSizeObservations: const [],
            positionShapeObservations: const [],
          ),
          candidates: const [],
          identities: const {},
        ),
      );

      expect(shareEnabled(tester), isFalse);
    });

    testWidgets('a period nobody qualified for cannot be shared',
        (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: [
            TeamOfPeriodCandidate(
              userId: 'u1',
              periodIdentity: identityOf(),
              eligible: false,
              matchesPlayed: 1,
              participationRate: 0.33,
              wins: 0,
              draws: 0,
              losses: 1,
              goals: 0,
              goalsPerMatch: 0,
              mvpCount: 0,
              winRate: 0,
              pointsPerGame: 0,
              periodFormScore: -0.1,
              goalFormContributionTotal: 0,
              periodPrimaryPosition: Position.mid,
              currentOverallRating: 5,
            ),
          ],
          identities: const {},
        ),
      );

      expect(shareEnabled(tester), isFalse);
    });

    testWidgets('a failed read cannot be shared', (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
          failure: const InfrastructureFailure(),
        ),
      );

      expect(shareEnabled(tester), isFalse);
    });

    testWidgets('switching period disables the stale picture at once',
        (tester) async {
      final from = DateTime.utc(2026, 7, 31, 20);
      final to = DateTime.utc(2026, 8, 31, 20);
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter);
      expect(shareEnabled(tester), isTrue);

      adapter.window =
          windowOf(kind: TeamOfPeriodKind.monthly, from: from, to: to);
      adapter.candidates =
          squad(kind: TeamOfPeriodKind.monthly, from: from, to: to);
      adapter.gate = Completer<void>();

      await tester.tap(find.text('Month'));
      await tester.pump();

      // The week is gone before the month has arrived, so there is no moment
      // at which a week could leave the phone under a month's name.
      expect(shareEnabled(tester), isFalse);

      adapter.gate!.complete();
      await tester.pumpAndSettle();
      expect(shareEnabled(tester), isTrue);
    });

    testWidgets('a community with no name cannot be shared', (tester) async {
      await pumpScreen(
        tester,
        communityName: null,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(shareEnabled(tester), isFalse);
    });
  });

  group('the picture is of what is on screen', () {
    testWidgets('taking it reads nothing again', (tester) async {
      final renderer = _CapturingRenderer();
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter, renderer: renderer);

      final windowReads = adapter.windowCalls.length;
      final candidateReads = adapter.candidateCalls.length;
      final identityReads = adapter.identityCalls.length;

      await tapShare(tester);

      expect(renderer.renders, 1);
      expect(adapter.windowCalls, hasLength(windowReads));
      expect(adapter.candidateCalls, hasLength(candidateReads));
      expect(adapter.identityCalls, hasLength(identityReads));
    });

    testWidgets('the card holds the award that was on screen', (tester) async {
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        logoUrl: null,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );
      await tapShare(tester);
      await pumpCard(tester, renderer);

      final card = tester.widget<TeamOfPeriodCard>(
        find.byType(TeamOfPeriodCard),
      );
      expect([for (final p in card.data.players) p.userId],
          ['gk1', 'd1', 'd2', 'm1', 'f1']);
      expect([for (final p in card.data.players) p.assignedPosition], [
        Position.gk,
        Position.def,
        Position.def,
        Position.mid,
        Position.fwd,
      ]);
      expect(card.data.kind, TeamOfPeriodKind.weekly);
      expect(card.data.periodStart, start);
      expect(card.data.periodEnd, end);
    });

    testWidgets('an unreadable identity keeps its place on the card',
        (tester) async {
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities:
              namesFor(['gk1', 'd1', 'd2', 'm1', 'f1'], hidden: ['gk1']),
        ),
      );
      await tapShare(tester);
      await pumpCard(tester, renderer);

      final card = tester.widget<TeamOfPeriodCard>(
        find.byType(TeamOfPeriodCard),
      );
      expect(card.data.players, hasLength(5));
      expect(card.data.players.first.userId, 'gk1');
      expect(card.data.players.first.name, 'Player');
      // No face to draw, and the pitch's own fallback disc handles that.
      expect(card.data.players.first.avatarUrl, isNull);
      // The award is theirs whether or not their profile can be read, so the
      // rating travels with it exactly as it does for everybody else.
      expect(card.data.players.first.currentOverallRating, 7.4);
    });

    testWidgets('an unreadable identity is still drawn on the card',
        (tester) async {
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities:
              namesFor(['gk1', 'd1', 'd2', 'm1', 'f1'], hidden: ['gk1']),
        ),
      );
      await tapShare(tester);
      await pumpCard(tester, renderer);

      // The neutral fallback, and nothing guessing at why it is neutral.
      expect(find.text('Player'), findsOneWidget);
      expect(find.textContaining('former'), findsNothing);
      expect(find.textContaining('deleted'), findsNothing);
      expect(find.byType(PitchView), findsOneWidget);
      final pitch = tester.widget<PitchView>(find.byType(PitchView));
      expect(pitch.assignments, hasLength(5));
      expect(pitch.avatarUrlOf!('gk1'), isNull);
      expect(pitch.ratingOf!('gk1'), 7.4);
    });
  });

  group('what the card draws', () {
    Future<_CapturingRenderer> compose(
      WidgetTester tester, {
      List<TeamOfPeriodCandidate>? candidates,
      Map<String, TeamOfPeriodPlayerIdentity>? identities,
      String? logoUrl,
      String communityName = 'Al Amerat FC',
      int side = 5,
      Locale locale = const Locale('en'),
    }) async {
      final renderer = _CapturingRenderer();
      final people = candidates ?? squad();
      await pumpScreen(
        tester,
        renderer: renderer,
        logoUrl: logoUrl,
        communityName: communityName,
        locale: locale,
        adapter: _FakeAdapter(
          window: windowOf(side: side),
          candidates: people,
          identities:
              identities ?? namesFor([for (final c in people) c.userId]),
        ),
      );
      await tapShare(tester);
      await pumpCard(tester, renderer, locale: locale);
      return renderer;
    }

    testWidgets('the community, the award and the resolved week',
        (tester) async {
      await compose(tester);

      expect(find.text('Al Amerat FC'), findsOneWidget);
      expect(find.text('Team of the Week'), findsOneWidget);
      // The dates, not the word. 31 August through 6 September in Muscat.
      expect(find.textContaining('Aug 31'), findsOneWidget);
      expect(find.textContaining('Sep 6'), findsOneWidget);
      expect(find.textContaining('Sep 7'), findsNothing);
    });

    testWidgets('a monthly card names the month and the year', (tester) async {
      final from = DateTime.utc(2026, 7, 31, 20);
      final to = DateTime.utc(2026, 8, 31, 20);
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        adapter: _FakeAdapter(
          window: windowOf(kind: TeamOfPeriodKind.monthly, from: from, to: to),
          candidates:
              squad(kind: TeamOfPeriodKind.monthly, from: from, to: to),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );
      await tapShare(tester);
      await pumpCard(tester, renderer);

      expect(find.text('Team of the Month'), findsOneWidget);
      expect(find.textContaining('August 2026'), findsOneWidget);
    });

    testWidgets('the crest is drawn, with or without a logo', (tester) async {
      await compose(tester, logoUrl: null);

      final crest = tester.widget<CommunityCrest>(
        find.byKey(const ValueKey('team-of-period-card-crest')),
      );
      expect(crest.logoUrl, isNull);
      expect(crest.name, 'Al Amerat FC');
      // The initials crest is the ordinary case, not a broken one.
      expect(find.text('AA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a logo is handed to the crest when there is one',
        (tester) async {
      await compose(tester, logoUrl: 'https://example.test/crest.png');

      final crest = tester.widget<CommunityCrest>(
        find.byKey(const ValueKey('team-of-period-card-crest')),
      );
      expect(crest.logoUrl, 'https://example.test/crest.png');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long community name does not overflow', (tester) async {
      await compose(
        tester,
        communityName:
            'Al Amerat Community Football and Recreation Association Muscat',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('one pitch, no opponent, no team headings', (tester) async {
      await compose(tester);

      expect(find.byType(PitchView), findsOneWidget);
      expect(find.byKey(const ValueKey('team-of-period-pitch')), findsOneWidget);
      expect(find.text('Team A'), findsNothing);
      expect(find.text('Team B'), findsNothing);
    });

    testWidgets('the pitch draws the award rows exactly', (tester) async {
      await compose(tester);

      final pitch = tester.widget<PitchView>(find.byType(PitchView));
      expect(pitch.layout, PitchLayoutMode.exactAssignedPositions);
      expect(pitch.team, TeamId.a, reason: 'non-mirrored, no second side');
      expect(
        [for (final a in pitch.assignments) a.assignedPosition],
        [Position.gk, Position.def, Position.def, Position.mid, Position.fwd],
      );
    });

    testWidgets('an award with no goalkeeper keeps none', (tester) async {
      await compose(
        tester,
        candidates: [
          candidateOf('d1', primary: Position.def, form: 0.3),
          candidateOf('d2', primary: Position.def, form: 0.29),
          candidateOf('m1', primary: Position.mid, form: 0.28),
          candidateOf('m2', primary: Position.mid, form: 0.27),
          candidateOf('f1', primary: Position.fwd, form: 0.26),
        ],
      );

      final pitch = tester.widget<PitchView>(find.byType(PitchView));
      expect(
        pitch.assignments.where((a) => a.assignedPosition == Position.gk),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a name, a goal badge and a star, and nothing else',
        (tester) async {
      await compose(tester);

      expect(find.text('Player m1'), findsOneWidget);
      expect(find.text('Player gk1'), findsOneWidget);
      // m1 scored three in the period.
      expect(find.text('3'), findsWidgets);

      // The current global rating, drawn the way every Go Play player card
      // draws it. It is the number the player holds today rather than a
      // reconstruction of the period, and the Product Owner approved it on
      // that basis.
      expect(find.text('7.4'), findsWidgets);
      final pitch = tester.widget<PitchView>(find.byType(PitchView));
      expect(pitch.ratingOf, isNotNull);
      expect(pitch.ratingOf!('m1'), 7.4);

      // And none of the selection evidence either.
      for (final absent in [
        'Participation',
        'Win rate',
        'Points per game',
        'Matches played',
        'PFS',
        'Form',
      ]) {
        expect(find.textContaining(absent), findsNothing, reason: absent);
      }
    });

    testWidgets('each rating belongs to the player wearing it', (tester) async {
      // Distinct ratings, so a card that drew one player's number under
      // another's face would fail rather than look plausible.
      await compose(
        tester,
        candidates: [
          candidateOf('gk1', primary: Position.gk, form: 0.30, rating: 9.1),
          candidateOf('d1', primary: Position.def, form: 0.28, rating: 8.2),
          candidateOf('d2', primary: Position.def, form: 0.26, rating: 7.3),
          candidateOf('m1', primary: Position.mid, form: 0.24, rating: 6.4),
          candidateOf('f1', primary: Position.fwd, form: 0.22, rating: 5.5),
        ],
      );

      final pitch = tester.widget<PitchView>(find.byType(PitchView));
      for (final (id, rating) in [
        ('gk1', 9.1),
        ('d1', 8.2),
        ('d2', 7.3),
        ('m1', 6.4),
        ('f1', 5.5),
      ]) {
        expect(pitch.ratingOf!(id), rating, reason: id);
        expect(find.text('$rating'), findsOneWidget, reason: id);
      }
    });

    testWidgets('the rating comes from the snapshot, not a fresh read',
        (tester) async {
      final renderer = _CapturingRenderer();
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, renderer: renderer, adapter: adapter);

      final reads = (
        adapter.windowCalls.length,
        adapter.candidateCalls.length,
        adapter.identityCalls.length,
      );
      await tapShare(tester);
      await pumpCard(tester, renderer);

      final card = tester.widget<TeamOfPeriodCard>(
        find.byType(TeamOfPeriodCard),
      );
      // Every rating on the card is the candidate evidence already loaded.
      expect(
        [for (final p in card.data.players) p.currentOverallRating],
        everyElement(7.4),
      );
      expect(
        (
          adapter.windowCalls.length,
          adapter.candidateCalls.length,
          adapter.identityCalls.length,
        ),
        reads,
        reason: 'drawing a rating asks the database nothing',
      );
    });

    testWidgets('the pitch is the dominant thing on the card', (tester) async {
      await compose(tester);

      final card = tester.getRect(find.byType(TeamOfPeriodCard));
      final pitch = tester.getRect(
        find.byKey(const ValueKey('team-of-period-card-pitch')),
      );

      // Full-bleed and better than a third of the card's height: the earlier
      // composition inset it to Share Result's per-side width and centred it in
      // the room left over, which read as a picture of a pitch rather than of
      // a team.
      expect(pitch.width, card.width);
      expect(pitch.height / card.height, greaterThan(0.3));
      // Still clear of the signature below it.
      final footer = tester.getRect(find.byKey(const ValueKey('share-footer')));
      expect(pitch.bottom, lessThanOrEqualTo(footer.top));
      // And clear of the heading above it.
      final period = tester.getRect(
        find.byKey(const ValueKey('team-of-period-card-period')),
      );
      expect(period.bottom, lessThanOrEqualTo(pitch.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the match count stays off the card', (tester) async {
      // Football-first: how many matches the period held is context for the
      // screen, where somebody can act on it, and clutter on a picture.
      await compose(tester);

      expect(find.textContaining('matches'), findsNothing);
      // The '1 of 5' form specifically -- 'Team of the Week' legitimately
      // contains ' of ', so the pattern is the digits around it.
      expect(find.textContaining(RegExp(r'\d+ of \d+')), findsNothing);
    });

    testWidgets('it carries the Go Play signature', (tester) async {
      await compose(tester);

      expect(find.byType(ShareCardSignature), findsOneWidget);
      expect(find.byKey(const ValueKey('share-footer')), findsOneWidget);
    });

    for (final size in [5, 7, 9, 11]) {
      testWidgets('a $size-player award composes without overflow',
          (tester) async {
        final people = [
          candidateOf('gk1', primary: Position.gk, form: 0.9),
          for (var i = 0; i < size - 1; i++)
            candidateOf('p$i',
                primary: Position.values[1 + i % 3], form: 0.5 - i * 0.01),
        ];
        await compose(tester, candidates: people, side: size);

        expect(tester.takeException(), isNull);
        expect(find.byType(PitchView), findsOneWidget);
        final pitch = tester.widget<PitchView>(find.byType(PitchView));
        expect(pitch.assignments, hasLength(size));
      });
    }

    testWidgets('Arabic composes right to left', (tester) async {
      await compose(tester, locale: const Locale('ar'));

      expect(
        Directionality.of(tester.element(find.byType(PitchView))),
        TextDirection.rtl,
      );
      expect(find.byType(TeamOfPeriodCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long name in either language truncates rather than spills',
        (tester) async {
      await compose(
        tester,
        identities: namesFor(
          ['gk1', 'd1', 'd2', 'm1', 'f1'],
          longNames: {
            'gk1': 'Abdulrahman Muhammad Al Balushi Al Hinai Al Amri',
            'd1': 'عبد الرحمن محمد بن سالم البلوشي الهنائي العامري',
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('the engine and the images', () {
    testWidgets('it goes through the one share engine, at 9:16',
        (tester) async {
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );
      await tapShare(tester);

      expect(renderer.renders, 1);
      // The preview the engine pushed is the shared one, and the community it
      // belongs to travelled with it.
      expect(find.text('Share card'), findsOneWidget);
      expect(
        ShareCardCanvas.isShareCardShape(ShareCardCanvas.designSize),
        isTrue,
      );

      await pumpCard(tester, renderer);
      final surface = tester.widget<ShareCardSurface>(
        find.byType(ShareCardSurface),
      );
      expect(surface, isNotNull);
      expect(find.byType(TeamOfPeriodCard), findsOneWidget);
    });

    testWidgets('faces and the crest are precached before composing',
        (tester) async {
      // Best effort: these URLs cannot load in a test, and the card is composed
      // all the same with fallbacks. A precache that aborted the card would
      // make a missing photograph a failure to share.
      final renderer = _CapturingRenderer();
      await pumpScreen(
        tester,
        renderer: renderer,
        logoUrl: 'https://example.test/crest.png',
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: {
            for (final id in ['gk1', 'd1', 'd2', 'm1', 'f1'])
              id: TeamOfPeriodPlayerIdentity(
                userId: id,
                fullName: 'Player $id',
                avatarUrl: 'https://example.test/$id.png',
              ),
          },
        ),
      );
      await tapShare(tester);

      expect(renderer.renders, 1, reason: 'a failed image still composes');

      await pumpCard(tester, renderer);
      final card = tester.widget<TeamOfPeriodCard>(
        find.byType(TeamOfPeriodCard),
      );
      // Every readable face plus the crest is what the screen precaches.
      expect(card.data.imageUrls, hasLength(6));
      expect(card.data.imageUrls, contains('https://example.test/crest.png'));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Keeps whatever template the screen handed the engine.
class _CapturingRenderer implements ShareCardRenderer {
  ShareCardTemplate? captured;
  int renders = 0;

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    renders++;
    captured = template;
    return ShareCardImage(
      bytes: Uint8List.fromList(_pixel),
      pixelWidth: 1080,
      pixelHeight: 1920,
    );
  }
}

const _pixel = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _FakeShareService implements ShareService {
  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async =>
      ShareOutcome.shared;
}

class _FakeAdapter implements StatisticsAdapter {
  _FakeAdapter({
    required this.window,
    required this.candidates,
    required this.identities,
    this.failure,
  });

  TeamOfPeriodWindow window;
  List<TeamOfPeriodCandidate> candidates;
  Map<String, TeamOfPeriodPlayerIdentity> identities;
  Failure? failure;
  Completer<void>? gate;

  final List<TeamOfPeriodKind> windowCalls = [];
  final List<TeamOfPeriodKind> candidateCalls = [];
  final List<List<String>> identityCalls = [];

  @override
  Future<TeamOfPeriodWindow> fetchTeamOfPeriodWindow(
    String communityId,
    TeamOfPeriodKind kind,
  ) async {
    windowCalls.add(kind);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return window;
  }

  @override
  Future<List<TeamOfPeriodCandidate>> fetchTeamOfPeriodCandidates(
    String communityId,
    TeamOfPeriodKind kind,
  ) async {
    candidateCalls.add(kind);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return candidates;
  }

  @override
  Future<Map<String, TeamOfPeriodPlayerIdentity>>
      fetchTeamOfPeriodPlayerIdentities(Iterable<String> userIds) async {
    identityCalls.add(userIds.toList());
    return identities;
  }

  @override
  Future<List<CommunityPlayerStatistics>> fetchCommunityPlayerStatistics(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError();

  @override
  Future<int> fetchCompletedMatches(String communityId, StatisticsPeriod p) =>
      throw UnimplementedError();

  @override
  Future<List<CommunityMemberRating>> fetchCommunityMemberRatings(String id) =>
      throw UnimplementedError();

  @override
  Future<Map<String, PlayerAchievementRecency>> fetchAchievementRecency(
    String communityId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<CommunityPlayerStatistics>> fetchPlayerPeriodStatistics(
    String userId,
    StatisticsPeriod period,
  ) =>
      throw UnimplementedError();
}
