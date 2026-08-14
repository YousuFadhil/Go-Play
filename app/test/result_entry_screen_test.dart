import 'dart:async';

import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
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
    CommunityRole? role = CommunityRole.admin,
    Future<void>? gate,
    void Function(bool? popped)? onPopped,
  }) async {
    // Taller than the 800x600 default. The form is a ListView, so a widget
    // below the fold is never built and `find` cannot see it at all — and the
    // save button now sits below two team sections and the note saying the best
    // player is optional. This is the viewport, not the assertions: every test
    // below still looks for exactly what it looked for before.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
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
                registrations: fourSeats(),
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

  /// The save sits below the lineup, so a four-player match already puts it past
  /// the bottom of the test viewport.
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

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Save result'),
        matching: find.byType(FilledButton),
      ),
    );

/// Answers from memory and records what it was handed.
class FakeResultAdapter implements ResultAdapter {
  FakeResultAdapter({this.result, this.thrown});

  final MatchResult? result;
  final Failure? thrown;

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
  Future<void> removePlayer(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<RegistrationStatus> addPlayerToMatch(String matchId, String userId) =>
      throw UnimplementedError();

  @override
  Future<int?> fetchReservePlayers() => throw UnimplementedError();
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
