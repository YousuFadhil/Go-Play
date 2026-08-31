import 'dart:async';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_task.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/core/tokens.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/profile/player_identity.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_entry_screen.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';

/// The result entry screen against fake ports.
///
/// What is asserted is the screen's own behaviour — what it shows, which
/// controls it offers to whom, and what it sends. The rules themselves are
/// covered by `result_rules_test.dart` and the repository's use of them by
/// `result_repository_test.dart`; nothing here re-asserts either.
///
/// Every test drives the real repositories with a fake adapter underneath, so
/// the path the screen takes to the data is the production one.
void main() {
  final kickOff = DateTime(2026, 7, 1, 20);

  /// A match that has been played: recording a result is offered on one that is
  /// over, and the screen is only ever reached from there.
  final match = Match(
    id: 'm1',
    communityId: 'c1',
    createdBy: 'u1',
    location: 'Al Amerat Pitch',
    startAt: kickOff,
    endAt: kickOff.add(const Duration(hours: 2)),
    startingPlayers: 4,
    maxRegistration: 6,
    status: MatchStatus.completed,
    title: 'Wednesday match',
  );

  MatchRegistration seat(String id, String name) => MatchRegistration(
        registrationId: 'reg-$id',
        userId: id,
        fullName: name,
        position: 'MID',
        status: RegistrationStatus.confirmed,
        registrationOrder: int.parse(id.substring(1)),
      );

  List<MatchRegistration> fourSeats() => [
        seat('u1', 'Sara Al Balushi'),
        seat('u2', 'Ahmed Al Harthy'),
        seat('u3', 'Noor Al Kindi'),
        seat('u4', 'Yousef Al Amri'),
      ];

  TeamAssignment at(String id, TeamId team) => TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: Position.mid,
        basis: AssignmentBasis.primary,
      );

  List<TeamAssignment> storedLineup() => [
        at('u1', TeamId.a),
        at('u2', TeamId.a),
        at('u3', TeamId.b),
        at('u4', TeamId.b),
      ];

  Future<void> pumpResult(
    WidgetTester tester, {
    required FakeResultAdapter results,
    List<TeamAssignment>? lineup,
    List<MatchRegistration>? registrations,
    CommunityRole? role = CommunityRole.admin,
    Future<void>? gate,
    void Function(bool? popped)? onPopped,
    Locale locale = const Locale('en'),
    Size size = const Size(800, 1600),
  }) async {
    // Taller than the 800x600 default so the form tests can see the player rows
    // without affecting the layout asserted by the narrow-width cases.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorKey: navigator,
      home: const Scaffold(body: SizedBox.shrink()),
    ));

    // Pushed rather than used as `home`. Sprint 2.5 made a saved result close
    // this screen and report to the match behind it, and a screen that is the
    // only route has nothing to close and nothing to report to — the push is
    // what makes both observable.
    unawaited(
      navigator.currentState!
          .push<bool>(MaterialPageRoute(
            builder: (_) => ResultEntryScreen(
              matchId: 'm1',
              resultRepository: ResultRepository(results),
              teamRepository:
                  TeamRepository(FakeTeamAdapter(lineup ?? storedLineup())),
              matchService: MatchService(FakeMatchAdapter(
                match: match,
                registrations: registrations ?? fourSeats(),
                gate: gate,
              )),
              memberRepository:
                  MemberRepository(FakeMemberAdapter(role: role)),
            ),
          ))
          .then((value) => onPopped?.call(value)),
    );
    await tester.pump();
    // Past the route transition, so the screen is settled in place before a
    // test looks at it.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapGoal(WidgetTester tester, String userId, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byKey(Key('goalPlus_$userId')));
      await tester.pump();
    }
  }

  Future<void> enterScore(
      WidgetTester tester, String field, String value) async {
    await tester.enterText(find.byKey(Key(field)), value);
    await tester.pump();
  }

  /// The save is pinned below the scrollable lineup.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save result').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save result').first);
    await tester.pumpAndSettle();
  }

  group('loading', () {
    testWidgets('shows the loading indicator until the data arrives',
        (tester) async {
      final gate = Completer<void>();
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        gate: gate.future,
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sara Al Balushi'), findsOneWidget);
    });
  });

  group('Club task presentation', () {
    testWidgets('uses the task bar, scrollable body, and pinned action',
        (tester) async {
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        size: const Size(412, 900),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClubTaskBar), findsOneWidget);
      expect(find.byType(ClubTaskBody), findsOneWidget);
      expect(find.byType(ClubActionBar), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('Save result'),
        ),
        findsNothing,
      );
    });

    testWidgets('back leaves the form without submitting', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(results.writes, 0);
      expect(find.byType(ResultEntryScreen), findsNothing);
    });

    testWidgets('long English and Arabic names are safe on narrow screens',
        (tester) async {
      final longEnglish =
          'Alexanderson Montgomery-Wellington the Third of Al Amerat';
      final longArabic = 'عبدالرحمن بن محمد بن عبدالله السالمي الطويل جداً';
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        size: const Size(320, 800),
        locale: const Locale('ar'),
        registrations: [
          seat('u1', longArabic),
          seat('u2', longEnglish),
          seat('u3', longArabic),
          seat('u4', longEnglish),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text(longArabic), findsWidgets);
      expect(find.text(longEnglish), findsWidgets);
      // The score row is laid out left-to-right by a `Directionality` above
      // the fields, not by a property on any one of them, so the ambient
      // direction at the field is what the screen actually guarantees.
      expect(
        Directionality.of(tester.element(find.byKey(const Key('teamAScore')))),
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the pinned action remains usable at 480 pixels',
        (tester) async {
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        size: const Size(480, 900),
      );
      await tester.pumpAndSettle();

      expect(find.text('Save result'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the score is legible', () {
    // The defect this guards against: `buildAppTheme` fills every text field
    // with `surfaceContainerLow`, a near-white. The score fields overrode only
    // the *borders*, so the fill stayed and a white numeral was drawn on a
    // near-white box — the score was there, at 38 points, and could not be
    // read. Nothing in the suite noticed, because every assertion about the
    // score reads its text and text has no colour.
    /// The `TextField` the `TextFormField` builds, which is where the
    /// decoration and the text style actually live.
    TextField fieldOf(WidgetTester tester, Key key) => tester.widget<TextField>(
          find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
        );

    Color? fillOf(WidgetTester tester, Key key) {
      final decoration = fieldOf(tester, key).decoration;
      return decoration?.filled == true ? decoration?.fillColor : null;
    }

    Color? inkOf(WidgetTester tester, Key key) =>
        fieldOf(tester, key).style?.color;

    /// WCAG relative luminance, which is what "these two are far enough apart"
    /// actually means. Asserting the exact pair would pin the palette; asserting
    /// the distance pins the property the reader cares about.
    double luminance(Color c) => c.computeLuminance();

    double contrast(Color a, Color b) {
      final l1 = luminance(a);
      final l2 = luminance(b);
      final hi = l1 > l2 ? l1 : l2;
      final lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    testWidgets('each numeral stands clear of the tile behind it',
        (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      for (final key in [const Key('teamAScore'), const Key('teamBScore')]) {
        final fill = fillOf(tester, key);
        final ink = inkOf(tester, key);
        expect(fill, isNotNull, reason: 'the tile is stated, not inherited');
        expect(ink, isNotNull);
        expect(
          contrast(ink!, fill!),
          greaterThan(7),
          reason: 'a score has to be readable at a glance, not merely present',
        );
      }
    });

    testWidgets('the tile is not the one the theme would have given it',
        (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      // The field opts out of the app's own input decoration deliberately: that
      // fill is right on a pale page and wrong on this deep-green row.
      expect(
        fillOf(tester, const Key('teamAScore')),
        isNot(GoColors.surfaceContainerLow),
      );
    });

    testWidgets('the team each score belongs to is still named',
        (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      // Moved out of the field's own decoration, where it would have been a
      // white label floating inside a white tile.
      expect(find.text('Team A'), findsWidgets);
      expect(find.text('Team B'), findsWidgets);
    });
  });

  group('who is offered the form', () {
    testWidgets('an admin gets it', (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      expect(find.text('Save result'), findsOneWidget);
    });

    testWidgets('a player is told whose job it is', (tester) async {
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        role: CommunityRole.player,
      );
      await tester.pumpAndSettle();

      expect(find.text('Save result'), findsNothing);
      expect(
        find.text('Only the community owner and admins can record a match '
            'result.'),
        findsOneWidget,
      );
    });

    testWidgets('a match with no lineup has no result to enter',
        (tester) async {
      // Without sides there is no winner to reward, so there is nothing to fill
      // in rather than a form that would be refused.
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        lineup: const [],
      );
      await tester.pumpAndSettle();

      expect(find.text('Save result'), findsNothing);
      expect(
        find.textContaining('Teams have not been generated'),
        findsOneWidget,
      );
    });
  });

  group('a player identity on the result form', () {
    testWidgets('the face is a profile control and the MVP star is still the '
        'MVP star', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      // The identity moved into the title so the leading slot can stay the MVP
      // star and the trailing one the goal stepper. All three are on the row.
      expect(
        tester.widget<PlayerIdentityTap>(find.byKey(const Key('identity_u1')))
            .userId,
        'u1',
      );
      expect(find.byKey(const Key('mvp_u1')), findsOneWidget);
      expect(find.byKey(const Key('goalPlus_u1')), findsOneWidget);

      // And they still do what they did: naming a best player, then scoring.
      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapGoal(tester, 'u1', 1);
      await enterScore(tester, 'teamAScore', '1');
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('a player picture is drawn where there is one', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      final avatars =
          tester.widgetList<PlayerAvatar>(find.byType(PlayerAvatar)).toList();
      expect(avatars, isNotEmpty);
      expect(avatars.every((a) => !a.isProfessionalGuest), isTrue);
    });

    testWidgets('a professional guest remains visible without result controls',
        (tester) async {
      await pumpResult(
        tester,
        results: FakeResultAdapter(),
        lineup: [
          at('u1', TeamId.a),
          const TeamAssignment(
            professionalGuestId: 'guest-1',
            team: TeamId.a,
            assignedPosition: null,
            basis: null,
          ),
          at('u3', TeamId.b),
          at('u4', TeamId.b),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player_guest-1')), findsOneWidget);
      expect(find.byKey(const Key('mvp_guest-1')), findsNothing);
      expect(find.byKey(const Key('goalPlus_guest-1')), findsNothing);
    });
  });

  group('filling the form in', () {
    testWidgets('the save is withheld until the goals add up', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await enterScore(tester, 'teamAScore', '2');
      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();

      expect(saveButton(tester).onPressed, isNull,
          reason: '0 of 2 goals assigned');

      await tapGoal(tester, 'u1', 2);
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('the save does not wait for a best player', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      // 0-0 already adds up, and naming a best player is optional, so there is
      // nothing left for the form to be waiting on.
      expect(saveButton(tester).onPressed, isNotNull);

      await tapSave(tester);

      expect(results.writes, 1);
      expect(results.lastMvpUserId, isNull);
    });

    testWidgets('a named best player can be taken back off', (tester) async {
      // Tapping the lit star is the only way back to nobody, and an organizer
      // who named the wrong player has to have one.
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mvp_u3')));
      await tester.pump();
      await tapSave(tester);

      expect(results.lastMvpUserId, isNull);
    });

    testWidgets('the running total says how far off the goals are',
        (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      await enterScore(tester, 'teamAScore', '3');
      expect(find.text('0 of 3 goals assigned to a scorer.'), findsOneWidget);

      await tapGoal(tester, 'u2', 3);
      expect(find.text('3 of 3 goals assigned to a scorer.'), findsOneWidget);
    });

    testWidgets('naming a second best player replaces the first',
        (tester) async {
      // Exactly one MVP per match: the control cannot express two.
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mvp_u4')));
      await tester.pump();
      await tapSave(tester);

      expect(results.lastMvpUserId, 'u4');
    });

    testWidgets('goals cannot be taken below zero', (tester) async {
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      final minus = tester.widget<IconButton>(
        find.byKey(const Key('goalMinus_u1')),
      );
      expect(minus.onPressed, isNull);
    });

    testWidgets('a score field takes digits only', (tester) async {
      // "Scores cannot be negative" is not a refusal the organizer has to read
      // about: the field cannot express one.
      await pumpResult(tester, results: FakeResultAdapter());
      await tester.pumpAndSettle();

      await enterScore(tester, 'teamAScore', '-3');
      expect(find.text('3 of 3 goals assigned to a scorer.'), findsNothing);
      expect(find.text('0 of 3 goals assigned to a scorer.'), findsOneWidget);
    });

    testWidgets('several goals by one player are sent as one tally',
        (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await enterScore(tester, 'teamAScore', '3');
      await tapGoal(tester, 'u1', 3);
      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapSave(tester);

      expect(results.lastGoals, hasLength(1));
      expect(results.lastGoals!.single.goals, 3);
    });
  });

  group('saving', () {
    testWidgets('a busy save prevents duplicate submissions', (tester) async {
      final gate = Completer<void>();
      final results = FakeResultAdapter(gate: gate.future);
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save result'));
      await tester.pump();

      expect(results.writes, 1);
      expect(saveButton(tester).onPressed, isNull);
      await tester.tap(saveButtonFinder());
      await tester.pump();
      expect(results.writes, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the numbers on screen are the ones sent', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await enterScore(tester, 'teamAScore', '2');
      await enterScore(tester, 'teamBScore', '1');
      await tapGoal(tester, 'u1', 2);
      await tapGoal(tester, 'u3', 1);
      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapSave(tester);

      expect(results.lastTeamAScore, 2);
      expect(results.lastTeamBScore, 1);
      expect(results.lastMvpUserId, 'u1');
      expect(
        {for (final tally in results.lastGoals!) tally.userId: tally.goals},
        {'u1': 2, 'u3': 1},
      );
      // Sprint 2.5: a saved result closes the form rather than announcing
      // itself over it. The confirmation is the match screen's now, and the
      // contract between them — that the form returns true — is asserted in
      // 'a saved result closes the form and reports it' below.
      expect(find.byType(ResultEntryScreen), findsNothing);
    });

    testWidgets('a saved result closes the form and reports it',
        (tester) async {
      final results = FakeResultAdapter();
      bool? returned;

      await pumpResult(
        tester,
        results: results,
        onPopped: (value) => returned = value,
      );
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(results.writes, 1);
      expect(returned, isTrue,
          reason: 'the match screen shows the confirmation on this');
      expect(find.byType(ResultEntryScreen), findsNothing);
    });

    testWidgets('a refused save keeps the form open with the numbers in it',
        (tester) async {
      // The organizer has a correction to make and nowhere else to make it, so
      // a refusal must not close the form.
      final results = FakeResultAdapter(
        thrown: const ValidationFailure(FailureReason.goalsDoNotMatchScore),
      );
      bool? returned;

      await pumpResult(
        tester,
        results: results,
        onPopped: (value) => returned = value,
      );
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(returned, isNull);
      expect(find.byType(ResultEntryScreen), findsOneWidget);
      expect(
        find.text('The goals assigned to scorers must add up to the final '
            'score.'),
        findsOneWidget,
      );
    });

    testWidgets('a goalless draw sends no scorers', (tester) async {
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u2')));
      await tester.pump();
      await tapSave(tester);

      expect(results.lastTeamAScore, 0);
      expect(results.lastTeamBScore, 0);
      expect(results.lastGoals, isEmpty);
    });

    testWidgets('a refusal is shown in the organizer\'s words',
        (tester) async {
      final results = FakeResultAdapter(
        thrown: const ValidationFailure(FailureReason.goalsDoNotMatchScore),
      );
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapSave(tester);

      expect(
        find.text('The goals assigned to scorers must add up to the final '
            'score.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused permission says so', (tester) async {
      final results = FakeResultAdapter(thrown: const AuthorizationFailure());
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapSave(tester);

      expect(find.text('Result saved.'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('correcting a recorded result', () {
    FakeResultAdapter recorded() => FakeResultAdapter(
          result: const MatchResult(
            matchId: 'm1',
            teamAScore: 2,
            teamBScore: 1,
            mvpUserId: 'u2',
            goals: [
              GoalTally(userId: 'u1', goals: 2),
              GoalTally(userId: 'u3', goals: 1),
            ],
          ),
        );

    testWidgets('the form opens on what was recorded', (tester) async {
      await pumpResult(tester, results: recorded());
      await tester.pumpAndSettle();

      expect(find.text('3 of 3 goals assigned to a scorer.'), findsOneWidget);
      expect(find.text('2 goals'), findsOneWidget);
      expect(find.text('1 goal'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('mvp_u2')),
          matching: find.byType(Icon),
        )).icon,
        Icons.star,
      );
    });

    testWidgets('replacing it is asked for before anything is sent',
        (tester) async {
      final results = recorded();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(find.text('Replace the recorded result?'), findsOneWidget);
      expect(results.writes, 0);
    });

    testWidgets('answering no leaves the recorded result alone',
        (tester) async {
      final results = recorded();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(results.writes, 0);
    });

    testWidgets('answering yes sends the corrected result', (tester) async {
      final results = recorded();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      // 2-1 to u1 and u3 becomes 1-1, scored by u1 and u3 once each.
      await enterScore(tester, 'teamAScore', '1');
      await tester.tap(find.byKey(const Key('goalMinus_u1')));
      await tester.pump();
      await tapSave(tester);
      await tester.tap(find.text('Save result').last);
      await tester.pumpAndSettle();

      expect(results.writes, 1);
      expect(results.lastTeamAScore, 1);
      expect(results.lastTeamBScore, 1);
      expect(
        {for (final tally in results.lastGoals!) tally.userId: tally.goals},
        {'u1': 1, 'u3': 1},
      );
    });

    testWidgets('a first recording is not asked about', (tester) async {
      // There is nothing to replace, so there is nothing to confirm.
      final results = FakeResultAdapter();
      await pumpResult(tester, results: results);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mvp_u1')));
      await tester.pump();
      await tapSave(tester);

      expect(find.text('Replace the recorded result?'), findsNothing);
      expect(results.writes, 1);
    });
  });
}

/// The pinned action, found by where it sits rather than by what it says.
///
/// While a save is in flight the button swaps its label for a spinner, so a
/// finder that goes by the text cannot see the button in the one state this
/// suite most needs to inspect.
Finder saveButtonFinder() => find.descendant(
      of: find.byType(ClubActionBar),
      matching: find.byType(FilledButton),
    );

FilledButton saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(saveButtonFinder());

/// Answers from memory and records what it was handed.
class FakeResultAdapter implements ResultAdapter {
  FakeResultAdapter({this.result, this.thrown, this.gate});

  final MatchResult? result;
  final Failure? thrown;
  final Future<void>? gate;

  int writes = 0;
  int? lastTeamAScore;
  int? lastTeamBScore;
  String? lastMvpUserId;
  List<GoalTally>? lastGoals;

  @override
  Future<MatchResult?> fetchResult(String matchId) async => result;

  @override
  Future<void> recordResult({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    required String? mvpUserId,
    required List<GoalTally> goals,
  }) async {
    if (thrown != null) throw thrown!;
    writes++;
    if (gate != null) await gate;
    lastTeamAScore = teamAScore;
    lastTeamBScore = teamBScore;
    lastMvpUserId = mvpUserId;
    lastGoals = goals;
  }

  @override
  Future<List<RatingChange>> fetchRatingHistory(String matchId) async =>
      const [];

  @override
  Future<PlayerStatistics> fetchStatistics(String userId) async =>
      PlayerStatistics.none(userId, 5.0);
}

/// Serves one stored lineup; nothing on this screen generates or writes one.
class FakeTeamAdapter implements TeamAdapter {
  FakeTeamAdapter(this.lineup);

  final List<TeamAssignment> lineup;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> assignments) =>
      throw UnimplementedError();

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(String matchId) =>
      throw UnimplementedError();

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) =>
      throw UnimplementedError();
}

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    required this.match,
    required this.registrations,
    this.gate,
  });

  final Match match;
  final List<MatchRegistration> registrations;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  @override
  Future<Match> fetchMatch(String matchId) async {
    if (gate != null) await gate;
    return match;
  }

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchUpcomingMatches() => throw UnimplementedError();

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    bool isHistorical = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMatch(String matchId) => throw UnimplementedError();

  @override
  Future<RegistrationStatus> registerForMatch(String matchId) =>
      throw UnimplementedError();

  @override
  Future<void> withdrawFromMatch(String matchId) => throw UnimplementedError();

  @override
  Future<void> setRosterOrder(String matchId, List<String> registrationIds) =>
      throw UnimplementedError();

  @override
  Future<void> swapParticipants(
    String matchId,
    String firstRegistrationId,
    String secondRegistrationId,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> removePlayer(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<String> addProfessionalGuest(String matchId, String name) =>
      throw UnimplementedError();

  @override
  Future<void> removeProfessionalGuest(String matchId, String guestId) =>
      throw UnimplementedError();

  @override
  Future<void> renameProfessionalGuest(
    String matchId,
    String guestId,
    String name,
  ) =>
      throw UnimplementedError();

  @override
  Future<int?> fetchReservePlayers() => throw UnimplementedError();

  // Asked only when a match read failed as not-found or unauthorized, which
  // this test never provokes.
  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) =>
      throw UnimplementedError();
}

class FakeMemberAdapter implements MemberAdapter {
  FakeMemberAdapter({this.role});

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) =>
      throw UnimplementedError();

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> removeMember(String communityId, String userId) =>
      throw UnimplementedError();

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();
}
