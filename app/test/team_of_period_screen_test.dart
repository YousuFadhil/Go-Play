import 'dart:async';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/statistics/statistics_adapter.dart';
import 'package:go_play/features/statistics/statistics_models.dart';
import 'package:go_play/features/statistics/statistics_period.dart';
import 'package:go_play/features/statistics/statistics_repository.dart';
import 'package:go_play/features/statistics/team_of_period_models.dart';
import 'package:go_play/features/statistics/team_of_period_screen.dart';
import 'package:go_play/features/teams/pitch_view.dart';

/// The Team of Period experience: the screen, the pitch it draws on, the sheet
/// behind a player, and the two states that have no team to show.
///
/// The selector's own arithmetic is not retested here. What these hold is that
/// the award reaches the screen intact — the right period, the right people, on
/// the rows the evidence gave them — and that nothing the screen fetches
/// afterwards can change any of it.
void main() {
  final start = DateTime.utc(2026, 8, 30, 20); // Muscat midnight, 31 August
  final end = DateTime.utc(2026, 9, 6, 20); // exclusive: through 6 September

  TeamOfPeriodIdentity identityOf({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    String key = '2026-W36',
    int matches = 3,
    DateTime? from,
    DateTime? to,
  }) =>
      TeamOfPeriodIdentity(
        kind: kind,
        periodKey: key,
        periodStart: from ?? start,
        periodEnd: to ?? end,
        qualifyingMatchCount: matches,
        requiredMatches: 1,
      );

  TeamOfPeriodWindow windowOf({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    int matches = 3,
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
        teamSizeObservations: const [5, 5, 5],
        positionShapeObservations: const [
          PositionShapeObservation(
              teamSize: 5, gk: 1, def: 2, mid: 1, fwd: 1, unassigned: 0),
        ],
      );

  TeamOfPeriodCandidate candidateOf(
    String id, {
    Position primary = Position.mid,
    double form = 0.1,
    int goals = 0,
    int mvp = 0,
    double rating = 6.5,
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    int matches = 3,
    int? played,
    DateTime? from,
    DateTime? to,
  }) =>
      TeamOfPeriodCandidate(
        userId: id,
        periodIdentity: identityOf(
          kind: kind,
          key: kind == TeamOfPeriodKind.weekly ? '2026-W36' : '2026-08',
          matches: matches,
          from: from,
          to: to,
        ),
        eligible: true,
        matchesPlayed: played ?? matches,
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

  /// A five-a-side award: one keeper, two defenders, a midfielder, a forward.
  List<TeamOfPeriodCandidate> squad({
    TeamOfPeriodKind kind = TeamOfPeriodKind.weekly,
    int matches = 3,
    DateTime? from,
    DateTime? to,
  }) {
    TeamOfPeriodCandidate at(String id, Position p, double f,
            {int goals = 0, int mvp = 0}) =>
        candidateOf(id,
            primary: p,
            form: f,
            goals: goals,
            mvp: mvp,
            kind: kind,
            matches: matches,
            from: from,
            to: to);
    return [
      at('gk1', Position.gk, 0.30),
      at('d1', Position.def, 0.28),
      at('d2', Position.def, 0.26),
      at('m1', Position.mid, 0.24, goals: 3, mvp: 2),
      at('f1', Position.fwd, 0.22),
    ];
  }

  Map<String, TeamOfPeriodPlayerIdentity> namesFor(
    Iterable<String> ids, {
    Iterable<String> hidden = const [],
  }) =>
      {
        for (final id in ids)
          if (!hidden.contains(id))
            id: TeamOfPeriodPlayerIdentity(
              userId: id,
              fullName: 'Player $id',
            ),
      };

  Future<_FakeAdapter> pumpScreen(
    WidgetTester tester, {
    required _FakeAdapter adapter,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
    bool settle = true,
    Key? key,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: TeamOfPeriodScreen(
        // A second pump of the same widget type in one test would otherwise
        // reuse the element, so initState -- and the load -- would not run.
        key: key,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        repository: StatisticsRepository(adapter),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
    return adapter;
  }

  group('the screen opens on the last completed week', () {
    testWidgets('weekly is what it asks for first', (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter);

      expect(adapter.windowCalls, [TeamOfPeriodKind.weekly]);
      expect(adapter.candidateCalls, [TeamOfPeriodKind.weekly]);
    });

    testWidgets('the heading names the resolved dates, not "weekly"',
        (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      // 31 August through 6 September, in Muscat -- the exclusive end instant
      // is 7 September, and drawing the range to it would claim a day the
      // football never happened on.
      expect(find.textContaining('Aug 31'), findsOneWidget);
      expect(find.textContaining('Sep 6'), findsOneWidget);
      expect(find.textContaining('Sep 7'), findsNothing);
    });

    testWidgets('switching to month refetches and renames', (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter);

      adapter.window = windowOf(
        kind: TeamOfPeriodKind.monthly,
        from: DateTime.utc(2026, 7, 31, 20),
        to: DateTime.utc(2026, 8, 31, 20),
      );
      adapter.candidates = squad(
        kind: TeamOfPeriodKind.monthly,
        from: DateTime.utc(2026, 7, 31, 20),
        to: DateTime.utc(2026, 8, 31, 20),
      );

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(adapter.windowCalls.last, TeamOfPeriodKind.monthly);
      expect(find.textContaining('August 2026'), findsOneWidget);
      expect(find.textContaining('Aug 31'), findsNothing);
    });

    testWidgets('a stale week cannot be shown under a month heading',
        (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter);
      expect(find.text('Player gk1'), findsOneWidget);

      adapter.window = windowOf(
        kind: TeamOfPeriodKind.monthly,
        from: DateTime.utc(2026, 7, 31, 20),
        to: DateTime.utc(2026, 8, 31, 20),
      );
      adapter.candidates = squad(
        kind: TeamOfPeriodKind.monthly,
        from: DateTime.utc(2026, 7, 31, 20),
        to: DateTime.utc(2026, 8, 31, 20),
      );
      adapter.gate = Completer<void>();

      await tester.tap(find.text('Month'));
      await tester.pump();

      // Loading, and the previous team is gone: a week's players under a
      // month's dates is the one thing this screen must never draw.
      expect(find.text('Player gk1'), findsNothing);
      expect(find.byType(PitchView), findsNothing);

      adapter.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PitchView), findsOneWidget);
    });
  });

  group('the states with no team', () {
    testWidgets('a period with no qualifying matches draws no pitch',
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

      expect(find.byType(PitchView), findsNothing);
      expect(
        find.textContaining('No qualifying matches'),
        findsOneWidget,
      );
      // The period is still named, which is what the reader came for.
      expect(find.textContaining('Aug 31'), findsOneWidget);
    });

    testWidgets('matches with nobody eligible names the requirement',
        (tester) async {
      final adapter = _FakeAdapter(
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
      );
      await pumpScreen(tester, adapter: adapter);

      expect(find.byType(PitchView), findsNothing);
      expect(find.textContaining('1'), findsWidgets);
      expect(find.textContaining('qualify'), findsOneWidget);
      // Nothing was asked of `users`: nobody was selected.
      expect(adapter.identityCalls, isEmpty);
    });

    testWidgets('a team smaller than the target is drawn as it is',
        (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: [
            candidateOf('d1', primary: Position.def),
            candidateOf('d2', primary: Position.def),
          ],
          identities: namesFor(['d1', 'd2']),
        ),
      );

      expect(find.byType(PitchView), findsOneWidget);
      expect(find.text('Player d1'), findsOneWidget);
      expect(find.text('Player d2'), findsOneWidget);
      // Nothing padded the missing three seats.
      expect(find.text('Player'), findsNothing);
    });

    testWidgets('a failed read offers a retry', (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: squad(),
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        failure: const InfrastructureFailure(),
      );
      await pumpScreen(tester, adapter: adapter);

      expect(find.byType(PitchView), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      adapter.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(PitchView), findsOneWidget);
    });
  });

  group('identity is fetched after the award and cannot change it', () {
    testWidgets('only the selected ids are asked for', (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(),
        candidates: [
          ...squad(),
          // Ranked last and not selected into the five-a-side shape.
          candidateOf('spare', primary: Position.mid, form: 0.01),
        ],
        identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
      );
      await pumpScreen(tester, adapter: adapter);

      expect(adapter.identityCalls, hasLength(1));
      expect(adapter.identityCalls.single.toSet(),
          {'gk1', 'd1', 'd2', 'm1', 'f1'});
      expect(adapter.identityCalls.single, isNot(contains('spare')));
    });

    testWidgets('a readable identity shows the name', (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(find.text('Player gk1'), findsOneWidget);
      expect(find.text('Player m1'), findsOneWidget);
    });

    testWidgets('an unreadable identity keeps the player, neutrally named',
        (tester) async {
      // A profile this reader cannot see is a display problem. The award was
      // earned and is not taken away, and the screen does not guess why the
      // name is missing.
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities:
              namesFor(['gk1', 'd1', 'd2', 'm1', 'f1'], hidden: ['gk1']),
        ),
      );

      expect(find.text('Player gk1'), findsNothing);
      expect(find.text('Player'), findsOneWidget);
      expect(find.textContaining('former'), findsNothing);
      expect(find.textContaining('deleted'), findsNothing);
    });

    testWidgets('who is readable cannot change who was selected',
        (tester) async {
      Future<List<String>> names(Iterable<String> hidden) async {
        final adapter = _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities:
              namesFor(['gk1', 'd1', 'd2', 'm1', 'f1'], hidden: hidden),
        );
        await pumpScreen(
          tester,
          adapter: adapter,
          key: ValueKey(hidden.join(',')),
        );
        return adapter.identityCalls.single;
      }

      final all = await names(const []);
      final none = await names(const ['gk1', 'd1', 'd2', 'm1', 'f1']);
      expect(none, all);
    });
  });

  group('the pitch nodes', () {
    Future<void> pumpTeam(WidgetTester tester) => pumpScreen(
          tester,
          adapter: _FakeAdapter(
            window: windowOf(),
            candidates: squad(),
            identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
          ),
        ).then((_) {});

    testWidgets('a node carries a name and the current rating', (tester) async {
      await pumpTeam(tester);

      expect(find.text('Player m1'), findsOneWidget);
      expect(find.text('6.5'), findsWidgets);
    });

    testWidgets('the goal badge counts period goals', (tester) async {
      await pumpTeam(tester);

      // m1 scored three in the period; nobody else scored.
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('the period detail is not printed on every node',
        (tester) async {
      await pumpTeam(tester);

      // Participation, win rate and points per game belong in the sheet.
      expect(find.textContaining('Points per game'), findsNothing);
      expect(find.textContaining('Participation'), findsNothing);
      expect(find.textContaining('Win rate'), findsNothing);
    });

    testWidgets('the rating is never called a period rating', (tester) async {
      await pumpTeam(tester);

      expect(find.textContaining('rating today'), findsOneWidget);
      expect(find.textContaining('period rating'), findsNothing);
    });
  });

  group('the player period detail', () {
    Future<void> openDetail(WidgetTester tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );
      await tester.tap(find.text('Player m1'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a player opens their period evidence',
        (tester) async {
      await openDetail(tester);

      expect(find.text('Awarded position: Midfielder'), findsOneWidget);
    });

    testWidgets('it shows the period figures', (tester) async {
      await openDetail(tester);

      for (final label in [
        'Matches played',
        'Participation',
        'Goals',
        'Goals per match',
        'Won / Drawn / Lost',
        'Win rate',
        'Points per game',
        'Best player awards',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('2 / 1 / 0'), findsOneWidget);
      expect(find.text('2.33'), findsOneWidget, reason: 'points per game');
      expect(find.text('100%'), findsOneWidget, reason: 'participation');
    });

    testWidgets('the rating is labelled as current', (tester) async {
      await openDetail(tester);

      expect(find.text('Current rating'), findsOneWidget);
      expect(find.textContaining('rating today'), findsWidgets);
    });

    testWidgets('the form score is not shown as a user-facing score',
        (tester) async {
      await openDetail(tester);

      expect(find.textContaining('Form'), findsNothing);
      expect(find.textContaining('PFS'), findsNothing);
      // The internal value itself never reaches the sheet.
      expect(find.text('0.24'), findsNothing);
    });
  });

  group('the period says how much football it held', () {
    testWidgets('the header carries the qualifying match count',
        (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(matches: 5),
          candidates: squad(matches: 5),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      // Secondary to the dates, and the answer to the question every figure
      // below provokes.
      expect(find.text('5 matches'), findsOneWidget);
      expect(find.textContaining('Aug 31'), findsOneWidget);
    });

    testWidgets('one match is one match, not "1 matches"', (tester) async {
      await pumpScreen(
        tester,
        adapter: _FakeAdapter(
          window: windowOf(matches: 1),
          candidates: squad(matches: 1),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(find.text('1 match'), findsOneWidget);
    });

    testWidgets('the sheet reads 1 of 5 rather than 1', (tester) async {
      final adapter = _FakeAdapter(
        window: windowOf(matches: 5),
        candidates: [
          candidateOf('m1', primary: Position.mid, played: 1, matches: 5),
        ],
        identities: namesFor(['m1']),
      );
      await pumpScreen(tester, adapter: adapter);
      final reads = adapter.identityCalls.length;

      await tester.tap(find.text('Player m1'));
      await tester.pumpAndSettle();

      // Numerator from the player, denominator from the loaded window.
      expect(find.text('1 of 5'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      // The proportion is still stated separately.
      expect(find.text('Participation'), findsOneWidget);
      // Opening it asked the database nothing.
      expect(adapter.identityCalls, hasLength(reads));
      expect(adapter.windowCalls, hasLength(1));
      expect(adapter.candidateCalls, hasLength(1));
    });

    testWidgets('Arabic reads 1 من 5', (tester) async {
      await pumpScreen(
        tester,
        locale: const Locale('ar'),
        adapter: _FakeAdapter(
          window: windowOf(matches: 5),
          candidates: [
            candidateOf('m1', primary: Position.mid, played: 1, matches: 5),
          ],
          identities: namesFor(['m1']),
        ),
      );

      await tester.tap(find.text('Player m1'));
      await tester.pumpAndSettle();

      expect(find.text('1 من 5'), findsOneWidget);
    });

    testWidgets('switching period takes the denominator with it',
        (tester) async {
      final from = DateTime.utc(2026, 7, 31, 20);
      final to = DateTime.utc(2026, 8, 31, 20);
      final adapter = _FakeAdapter(
        window: windowOf(matches: 5),
        candidates: [
          candidateOf('m1', primary: Position.mid, played: 1, matches: 5),
        ],
        identities: namesFor(['m1']),
      );
      await pumpScreen(tester, adapter: adapter);
      expect(find.text('5 matches'), findsOneWidget);

      adapter.window = windowOf(
        kind: TeamOfPeriodKind.monthly,
        matches: 12,
        from: from,
        to: to,
      );
      adapter.candidates = [
        candidateOf('m1',
            primary: Position.mid,
            played: 1,
            matches: 12,
            kind: TeamOfPeriodKind.monthly,
            from: from,
            to: to),
      ];

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('12 matches'), findsOneWidget);
      await tester.tap(find.text('Player m1'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 12'), findsOneWidget);
    });
  });

  group('both languages, and the widths a phone actually has', () {
    testWidgets('Arabic lays out right to left', (tester) async {
      await pumpScreen(
        tester,
        locale: const Locale('ar'),
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: namesFor(['gk1', 'd1', 'd2', 'm1', 'f1']),
        ),
      );

      expect(Directionality.of(tester.element(find.byType(PitchView))),
          TextDirection.rtl);
      expect(find.byType(PitchView), findsOneWidget);
    });

    for (final width in [320.0, 412.0, 480.0]) {
      for (final size in [5, 7, 11]) {
        testWidgets('a $size-player award fits ${width.toInt()} points',
            (tester) async {
          final many = <TeamOfPeriodCandidate>[
            candidateOf('gk1', primary: Position.gk, form: 0.9),
            for (var i = 0; i < size - 1; i++)
              candidateOf(
                'p$i',
                primary: Position.values[1 + i % 3],
                form: 0.5 - i * 0.01,
              ),
          ];
          await pumpScreen(
            tester,
            size: Size(width, 900),
            adapter: _FakeAdapter(
              window: TeamOfPeriodWindow(
                kind: TeamOfPeriodKind.weekly,
                periodKey: '2026-W36',
                periodStart: start,
                periodEnd: end,
                qualifyingMatchCount: 3,
                requiredMatches: 1,
                evidenceLastChangedAt: null,
                teamSizeObservations: [size, size, size],
                positionShapeObservations: const [
                  PositionShapeObservation(
                      teamSize: 6, gk: 1, def: 2, mid: 2, fwd: 1,
                      unassigned: 0),
                ],
              ),
              candidates: many,
              identities: namesFor([
                'gk1',
                for (var i = 0; i < size - 1; i++) 'p$i',
              ]),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PitchView), findsOneWidget);
        });
      }
    }

    testWidgets('a very long name truncates rather than overflowing',
        (tester) async {
      await pumpScreen(
        tester,
        size: const Size(320, 900),
        adapter: _FakeAdapter(
          window: windowOf(),
          candidates: squad(),
          identities: {
            'gk1': const TeamOfPeriodPlayerIdentity(
              userId: 'gk1',
              fullName: 'Abdulrahman Muhammad Al Balushi Al Hinai Al Amri',
            ),
            ...namesFor(['d1', 'd2', 'm1', 'f1']),
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

/// Answers from memory and records what it was asked.
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

  /// Held open so a test can look at the screen mid-load.
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
