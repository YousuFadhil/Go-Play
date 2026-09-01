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
import 'package:go_play/features/profile/profile_screen.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/teams/formation.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/pitch_view.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/features/teams/teams_screen.dart';

/// The Teams screen against fake ports.
///
/// What is asserted is the screen's own behaviour — which state it shows, which
/// control it offers to whom, and what it does with the result — not the
/// engine's rules and not the repository's. Those are covered by
/// `packages/btge/test` and `team_generation_repository_test.dart`, and nothing
/// here re-asserts them.
///
/// Every test drives the real `TeamRepository`, `MatchService` and
/// `MemberRepository` with a fake adapter underneath, so the path the screen
/// takes to the data is the production one.
void main() {
  // Relative to now, not a fixed date. Completion is time-driven
  // (`Match.effectiveStatus`), and which controls this screen offers now depends
  // on it — a hard-coded kick-off would silently turn every "upcoming match"
  // test into a "played match" one the day it passed.
  final kickOff = DateTime.now().add(const Duration(days: 3));

  Match matchAt(DateTime start, {MatchStatus status = MatchStatus.open}) =>
      Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u1',
        location: 'Al Amerat Pitch',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 10,
        maxRegistration: 16,
        status: status,
      );

  final match = matchAt(kickOff);

  /// The same match, played and finished.
  final playedMatch = matchAt(
    DateTime.now().subtract(const Duration(days: 3)),
    status: MatchStatus.completed,
  );

  MatchRegistration seat(String id, String name, String position) =>
      MatchRegistration(
        registrationId: 'reg-$id',
        userId: id,
        fullName: name,
        position: position,
        status: RegistrationStatus.confirmed,
        registrationOrder: int.parse(id.substring(1)),
      );

  /// Four confirmed players — the approved minimum match (`OP-2`).
  List<MatchRegistration> fourSeats() => [
        seat('u1', 'Sara Al Balushi', 'GK'),
        seat('u2', 'Ahmed Al Harthy', 'DEF'),
        seat('u3', 'Noor Al Kindi', 'MID'),
        seat('u4', 'Yousef Al Amri', 'FWD'),
      ];

  /// The names here match `seat()` above on purpose: the pitch names a player
  /// from their profile, and the roster is only the fallback for somebody who
  /// left the match after the lineup was stored.
  const names = {
    'u1': 'Sara Al Balushi',
    'u2': 'Ahmed Al Harthy',
    'u3': 'Noor Al Kindi',
    'u4': 'Yousef Al Amri',
    'u5': 'Layla Al Riyami',
  };

  PlayerCoreInputs input(
    String id,
    Position primary, {
    Position? secondary,
    double rating = 6,
  }) =>
      PlayerCoreInputs(
        userId: id,
        fullName: names[id] ?? 'Player $id',
        overallRating: rating,
        primaryPosition: primary,
        secondaryPosition: secondary,
        dateOfBirth: DateTime(kickOff.year - 25, kickOff.month, kickOff.day),
      );

  List<PlayerCoreInputs> fourInputs() => [
        input('u1', Position.gk),
        input('u2', Position.def),
        input('u3', Position.mid),
        input('u4', Position.fwd),
      ];

  TeamAssignment assignment(
    String id,
    TeamId team,
    Position position, {
    AssignmentBasis basis = AssignmentBasis.primary,
  }) =>
      TeamAssignment(
        userId: id,
        team: team,
        assignedPosition: position,
        basis: basis,
      );

  /// A stored lineup for the four seats above, two a side.
  List<TeamAssignment> storedLineup() => [
        assignment('u1', TeamId.a, Position.gk),
        assignment('u3', TeamId.a, Position.mid),
        assignment('u2', TeamId.b, Position.def),
        assignment('u4', TeamId.b, Position.fwd),
      ];

  Future<void> pumpTeams(
    WidgetTester tester, {
    required FakeTeamAdapter teams,
    required FakeMatchAdapter matches,
    CommunityRole? role = CommunityRole.admin,
    Locale locale = const Locale('en'),
    FakeMemberAdapter? members,
    NavigatorObserver? observer,
  }) async {
    // Two pitches and the controls under them need more than the default
    // 800x600, or the buttons sit below the fold and a tap lands on nothing.
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: observer == null ? const [] : [observer],
      home: TeamsScreen(
        matchId: 'm1',
        teamRepository: TeamRepository(teams),
        matchService: MatchService(matches),
        memberRepository:
            MemberRepository(members ?? FakeMemberAdapter(role: role)),
        // A completed match now reads its result here too, so the port is
        // supplied for the same reason every other one is: nothing in a widget
        // test may reach a provider. None of these tests is about a recorded
        // result, so it is always absent — which is the state they were all
        // implicitly written against.
        resultRepository: ResultRepository(_NoResult()),
      ),
    ));
  }

  // Regression for the production failure fixed by migration 0052: a match
  // holding a Professional Guest could not have teams generated at all.
  //
  // The fault itself was in PL/pgSQL and is covered by the integration suite.
  // What belongs here is the half this layer owns: a stored lineup that
  // contains a guest — no user id, no position, `GUEST` basis reading as a null
  // `AssignmentBasis` — has to render. If the screen cannot draw the result of
  // a successful generation, fixing the database would only move the failure.
  group('a lineup that holds a Professional Guest', () {
    TeamAssignment guestAssignment(String guestId, TeamId team) =>
        TeamAssignment(
          professionalGuestId: guestId,
          team: team,
          assignedPosition: null,
          basis: null,
        );

    testWidgets('8. the screen renders it without a position or a profile',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(
          lineup: [...storedLineup(), guestAssignment('g1', TeamId.a)],
          roster: fourInputs(),
        ),
        matches: FakeMatchAdapter(
          match: match,
          registrations: [
            ...fourSeats(),
            const MatchRegistration(
              registrationId: 'reg-g1',
              professionalGuestId: 'g1',
              fullName: 'Ahmed',
              status: RegistrationStatus.confirmed,
              registrationOrder: 5,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Five cards on the pitch, the guest among them: the existing formation
      // fallback places a positionless participant in whichever line is short,
      // which is the approved behaviour and not a new presentation rule.
      expect(find.byType(PlayerCard), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a guest is never taken for a goalkeeper', (tester) async {
      // `assignedPosition == Position.gk` is false for null, so a positionless
      // guest cannot displace the real keeper.
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(
          lineup: [...storedLineup(), guestAssignment('g1', TeamId.a)],
          roster: fourInputs(),
        ),
        matches: FakeMatchAdapter(
          match: match,
          registrations: [
            ...fourSeats(),
            const MatchRegistration(
              registrationId: 'reg-g1',
              professionalGuestId: 'g1',
              fullName: 'Ahmed',
              status: RegistrationStatus.confirmed,
              registrationOrder: 5,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final formation = buildFormation(
        [...storedLineup(), guestAssignment('g1', TeamId.a)],
      );
      expect(
        formation.goalkeepers.map((a) => a.participantId),
        ['u1'],
        reason: 'only the player whose stored position is GK keeps goal',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('loading', () {
    testWidgets('shows the loading indicator until the data arrives',
        (tester) async {
      final gate = Completer<void>();
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(
            match: match, registrations: fourSeats(), gate: gate.future),
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Team A'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Team A'), findsOneWidget);
    });
  });

  group('no teams yet', () {
    testWidgets('an admin is offered the generation', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Teams have not been generated for this match yet.'),
          findsOneWidget);
      expect(find.text('Generate teams'), findsOneWidget);
    });

    testWidgets('a player gets the empty state and no control', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: CommunityRole.player,
      );
      await tester.pumpAndSettle();

      expect(find.text('Teams have not been generated for this match yet.'),
          findsOneWidget);
      expect(find.text('Generate teams'), findsNothing);
      expect(find.text('Regenerate teams'), findsNothing);
    });

    testWidgets('a non-member gets no control either', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: null,
      );
      await tester.pumpAndSettle();

      expect(find.text('Generate teams'), findsNothing);
    });

    testWidgets('a roster below the minimum says so instead (OP-2)',
        (tester) async {
      final threeSeats = fourSeats()..removeLast();
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()..removeLast()),
        matches: FakeMatchAdapter(match: match, registrations: threeSeats),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generate teams'), findsNothing);
      expect(
        find.text('Generating teams needs between 4 and 30 confirmed players. '
            'This match has 3.'),
        findsOneWidget,
      );
    });

    testWidgets('a reserve player does not count towards the minimum',
        (tester) async {
      // Four registrations, but only three hold a seat. The engine generates
      // from confirmed players, so this roster is still short of OP-2.
      final registrations = [
        ...fourSeats().take(3),
        const MatchRegistration(
          registrationId: 'reg-u4',
          userId: 'u4',
          fullName: 'Yousef Al Amri',
          position: 'FWD',
          status: RegistrationStatus.reserve,
          registrationOrder: 4,
        ),
      ];
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()..removeLast()),
        matches: FakeMatchAdapter(match: match, registrations: registrations),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generate teams'), findsNothing);
      expect(
        find.text('Generating teams needs between 4 and 30 confirmed players. '
            'This match has 3.'),
        findsOneWidget,
      );
    });
  });

  group('generated teams', () {
    testWidgets('both sides are shown, each player on their own card',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      for (final name in const [
        'Sara Al Balushi',
        'Ahmed Al Harthy',
        'Noor Al Kindi',
        'Yousef Al Amri',
      ]) {
        expect(find.text(name), findsOneWidget);
      }

      // The position is no longer written on the card: it is *where the card
      // is*, which is the point of a pitch. The rating is, because the Product
      // Owner asked for it there.
      expect(find.text('Goalkeeper'), findsNothing);
      expect(find.text('6.0'), findsNWidgets(4));
      expect(find.byType(PitchView), findsNWidgets(2));
    });

    testWidgets('the rows run attack at the top down to goal at the bottom',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      // Team A is a goalkeeper and a midfielder. The outfielder is nearer the
      // top of the pitch than the keeper, whatever the formation: the keeper is
      // taken out of the outfield rules and drawn in goal underneath them.
      final keeper = tester.getCenter(find.text('Sara Al Balushi')).dy;
      final midfielder = tester.getCenter(find.text('Noor Al Kindi')).dy;
      expect(midfielder, lessThan(keeper));

      // Team B is a defender and a forward, and both are drawn on one line.
      // That is the approved rule rather than a compromise: defence is filled
      // to three before attack takes anybody, so a two-player side is all
      // defence. `formation_test.dart` states this directly.
      final defender = tester.getCenter(find.text('Ahmed Al Harthy')).dy;
      final forward = tester.getCenter(find.text('Yousef Al Amri')).dy;
      expect(forward, equals(defender));
    });

    testWidgets('a squad with nobody who keeps goal fields no goalkeeper',
        (tester) async {
      // §10.1's natural-goalkeeper test is a fact about the profiles, and the
      // engine will not create a goalkeeper slot without one. The pitch must
      // not draw a position the match did not have.
      final outfieldOnly = [
        input('u1', Position.def),
        input('u2', Position.def),
        input('u3', Position.mid),
        input('u4', Position.fwd),
      ];
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(
          lineup: [
            assignment('u1', TeamId.a, Position.def),
            assignment('u3', TeamId.a, Position.mid),
            assignment('u2', TeamId.b, Position.def),
            assignment('u4', TeamId.b, Position.fwd),
          ],
          roster: outfieldOnly,
        ),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Team A'), findsOneWidget);
      for (final name in const ['Sara Al Balushi', 'Noor Al Kindi']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('a player who left the match is still drawn', (tester) async {
      // `KB-017` records that they played. The card falls back to the roster
      // name and shows no rating, because there is no profile left to read one
      // from — it does not drop them.
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(
          lineup: storedLineup(),
          roster: fourInputs()..removeWhere((p) => p.userId == 'u4'),
        ),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yousef Al Amri'), findsOneWidget);
      expect(find.text('6.0'), findsNWidgets(3));
    });

    testWidgets('a transition has no presentation badge', (tester) async {
      final lineup = storedLineup()
        ..[1] = assignment('u3', TeamId.a, Position.def,
            basis: AssignmentBasis.transition);
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: lineup),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Out of position'), findsNothing);
      expect(find.byIcon(Icons.north), findsNothing);
    });

    testWidgets('no quality metric is displayed (§5.2)', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      // §5.2 keeps the §15 quality metrics internal, and the repository returns
      // none to begin with. The player's Overall Rating is not one of them — it
      // is an input the Product Owner asked to see on the card — so what is
      // asserted here is the absence of the metrics themselves.
      for (final metric in const [
        'distribution',
        'Distribution',
        'balance',
        'Balance',
        'out of position cost',
        'repeat',
        'Repeat',
        'imbalance',
      ]) {
        expect(find.textContaining(metric), findsNothing);
      }
    });

    testWidgets('an admin is offered a regeneration', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Regenerate teams'), findsOneWidget);
    });

    testWidgets('a player sees the teams but cannot regenerate them',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: CommunityRole.player,
      );
      await tester.pumpAndSettle();

      expect(find.text('Regenerate teams'), findsNothing);
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Sara Al Balushi'), findsOneWidget);
    });
  });

  group('generating', () {
    testWidgets('the result is stored and read back as the teams shown',
        (tester) async {
      final teams = FakeTeamAdapter(roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(teams.savedLineup, hasLength(4),
          reason: 'generation alone stores nothing; the screen records it');
      expect(teams.lineupReads, 2,
          reason: 'the teams shown come from a fresh read, not from what the '
              'screen was handed');
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      expect(find.text('Teams generated.'), findsOneWidget);
      // Nothing else follows the success, now or once it expires. A second
      // message queued behind it would mean the screen swallowed something on
      // a path it reported as having worked.
      expect(
          find.text('Something went wrong. Please try again.'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'), findsNothing,
          reason: 'a generation that worked reports nothing else');
    });

    testWidgets('the approved configuration is the one used (§18.1.1)',
        (tester) async {
      final teams = FakeTeamAdapter(roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(teams.lastLimit, 5, reason: 'the approved OP-6 lookback');
      expect(teams.lastCommunityId, 'c1');
      expect(teams.lastExcludedMatchId, 'm1');
    });

    testWidgets('a second tap while one is running starts nothing',
        (tester) async {
      final gate = Completer<void>();
      final teams =
          FakeTeamAdapter(roster: fourInputs(), saveGate: gate.future);
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pump();
      // The control is disabled while the operation runs, and the guard behind
      // it refuses anyway.
      final button =
          tester.widget<FilledButton>(find.byType(FilledButton).first);
      expect(button.onPressed, isNull);
      await tester.tap(find.text('Generate teams'), warnIfMissed: false);
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(teams.saveCount, 1, reason: 'one tap, one generation');
    });

    testWidgets('a refusal is reported and the teams are left alone',
        (tester) async {
      // Three players: the engine refuses under the approved minimum. The
      // roster the screen reads is short too, so the button is hidden; the
      // failure path is reached by making the read disagree with what the
      // engine is then handed, which is what a withdrawal between the two
      // looks like.
      final teams = FakeTeamAdapter(roster: fourInputs()..removeLast());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(find.text('Teams could not be generated from this roster.'),
          findsOneWidget);
      expect(teams.savedLineup, isNull, reason: 'a refusal stores nothing');
      expect(find.text('Teams have not been generated for this match yet.'),
          findsOneWidget);
    });

    testWidgets('an unfinished profile names its own sentence (§4.3)',
        (tester) async {
      final roster = fourInputs()
        ..[1] = const PlayerCoreInputs(
          userId: 'u2',
          fullName: 'Ahmed Al Harthy',
          overallRating: 6,
          primaryPosition: Position.def,
        );
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: roster),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(
        find.text('Some confirmed players have an incomplete profile. Each of '
            'them needs a date of birth before teams can be generated.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused write says so without exposing the provider',
        (tester) async {
      final teams = FakeTeamAdapter(
        roster: fourInputs(),
        saveFailure: const AuthorizationFailure(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(
          find.text('You do not have permission to do this.'), findsOneWidget);
    });

    testWidgets('a save that failed part-way leaves no stale teams on screen',
        (tester) async {
      // Storing a lineup clears the previous one first, so a failure after
      // that point leaves the match with none. What must not happen is the
      // screen going on showing teams the database no longer holds.
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
        failAfterClearing: true,
        saveFailure: const InfrastructureFailure(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Team A'), findsOneWidget);

      await tester.tap(find.text('Regenerate teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate teams').last);
      await tester.pumpAndSettle();

      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('Team A'), findsNothing,
          reason: 'the teams shown must never outlive the stored lineup');
      expect(find.text('Teams have not been generated for this match yet.'),
          findsOneWidget);
    });

    testWidgets('regenerating asks first, and a cancel changes nothing',
        (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Regenerate teams'));
      await tester.pumpAndSettle();
      expect(find.text('Generate the teams again?'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(teams.savedLineup, isNull);
      expect(find.text('Team A'), findsOneWidget);
    });

    testWidgets('a confirmed regeneration replaces the stored lineup',
        (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Regenerate teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate teams').last);
      await tester.pumpAndSettle();

      expect(teams.savedLineup, hasLength(4));
      expect(find.text('Teams generated.'), findsOneWidget);
    });
  });

  group('failures on the way in', () {
    testWidgets('a load that fails offers a retry', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(),
        matches: FakeMatchAdapter(
            match: match,
            registrations: const [],
            thrown: const NetworkFailure()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('manual override (§13)', () {
    /// Opens the action dialog on a player's row.
    Future<void> tapPlayer(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('a player row offers nothing to a player', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: CommunityRole.player,
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');

      expect(find.text('Move to the other team'), findsNothing);
      expect(find.text('Swap with a player'), findsNothing);
      expect(find.text('Change position'), findsNothing);
    });

    testWidgets('a non-member is offered nothing either', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: null,
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');

      expect(find.text('Move to the other team'), findsNothing);
    });

    for (final role in [CommunityRole.owner, CommunityRole.admin]) {
      testWidgets('an ${role.name} is offered the three operations',
          (tester) async {
        await pumpTeams(
          tester,
          teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
          matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
          role: role,
        );
        await tester.pumpAndSettle();

        await tapPlayer(tester, 'Sara Al Balushi');

        expect(find.text('Edit Sara Al Balushi'), findsOneWidget);
        expect(find.text('Move to the other team'), findsOneWidget);
        expect(find.text('Swap with a player'), findsOneWidget);
        expect(find.text('Change position'), findsOneWidget);
      });
    }

    testWidgets('a move is persisted and read back', (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Team A'), findsOneWidget);

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Move to the other team'));
      await tester.pumpAndSettle();

      expect(teams.savedLineup, hasLength(4));
      expect(teams.savedLineup!.singleWhere((a) => a.userId == 'u1').team,
          TeamId.b);
      expect(find.text('Team A'), findsOneWidget,
          reason: 'the sides shown come from a fresh read');
      expect(find.text('Team B'), findsOneWidget);
      expect(find.text('Lineup updated.'), findsOneWidget);
    });

    testWidgets('a swap asks which player, then persists it', (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Swap with a player'));
      await tester.pumpAndSettle();

      // Only the other side is offered: a swap within one team is not one.
      // The finders are scoped to the dialog because the lineup behind it
      // names all four players too.
      Finder inDialog(String name) => find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.text(name),
          );

      expect(find.text('Swap with'), findsOneWidget);
      expect(inDialog('Ahmed Al Harthy'), findsOneWidget);
      expect(inDialog('Yousef Al Amri'), findsOneWidget);
      expect(inDialog('Noor Al Kindi'), findsNothing,
          reason: 'Noor is on the same side as Sara');
      expect(inDialog('Sara Al Balushi'), findsNothing,
          reason: 'nobody swaps with themselves');

      await tester.tap(inDialog('Ahmed Al Harthy'));
      await tester.pumpAndSettle();

      final saved = teams.savedLineup!;
      expect(saved.singleWhere((a) => a.userId == 'u1').team, TeamId.b);
      expect(saved.singleWhere((a) => a.userId == 'u2').team, TeamId.a);
      expect(saved, hasLength(4));
      expect(find.text('Team A'), findsOneWidget,
          reason: 'a swap leaves the sides the size they were');
    });

    testWidgets('a position change asks which, then persists it',
        (tester) async {
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Change position'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned position'), findsOneWidget);
      await tester.tap(find.text('Forward').last);
      await tester.pumpAndSettle();

      final changed = teams.savedLineup!.singleWhere((a) => a.userId == 'u1');
      expect(changed.assignedPosition, Position.fwd);
      expect(changed.team, TeamId.a, reason: 'only the position changes');
      expect(find.text('Out of position'), findsNothing,
          reason: 'the stored transition is not presentation chrome');
    });

    testWidgets('choosing the position already held changes nothing',
        (tester) async {
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Change position'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goalkeeper').last);
      await tester.pumpAndSettle();

      expect(teams.savedLineup, isNull, reason: 'nothing to write');
    });

    testWidgets('dismissing the action dialog writes nothing', (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(teams.savedLineup, isNull);
      expect(find.text('Team A'), findsOneWidget);
    });

    testWidgets('a refused edit reports it and reloads what is stored',
        (tester) async {
      // The database refused the replacement, so it happened in full or not at
      // all — and the screen must show what is actually there rather than the
      // edit it asked for.
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
        saveFailure: const ConflictFailure(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Move to the other team'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'That change was refused. A team cannot have two goalkeepers.'),
        findsOneWidget,
      );
      expect(find.text('Team A'), findsOneWidget,
          reason: 'the stored lineup is untouched and is what is shown');
      expect(teams.lineupReads, 3,
          reason: 'one read for the screen, one for the edit, and one more '
              'because a refusal reloads too');
    });

    testWidgets('an unauthorized write says so', (tester) async {
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
        saveFailure: const AuthorizationFailure(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Move to the other team'));
      await tester.pumpAndSettle();

      expect(
          find.text('You do not have permission to do this.'), findsOneWidget);
      expect(find.text('Team A'), findsOneWidget);
    });

    testWidgets('a second edit while one is running starts nothing',
        (tester) async {
      final gate = Completer<void>();
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
        saveGate: gate.future,
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Move to the other team'));
      // Never pumpAndSettle while the write is held: the busy indicator runs
      // for as long as it is, so nothing would ever settle. Pumping the
      // dialog's dismissal through by hand is what that costs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The rows stop offering an edit while one is being written.
      await tester.tap(find.text('Ahmed Al Harthy'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Move to the other team'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(teams.saveCount, 1, reason: 'one edit, one write');
    });

    testWidgets('a match with one side empty says there is nobody to swap with',
        (tester) async {
      final teams = FakeTeamAdapter(
        lineup: [
          assignment('u1', TeamId.a, Position.gk),
          assignment('u3', TeamId.a, Position.mid),
        ],
        roster: fourInputs(),
      );
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Swap with a player'));
      await tester.pumpAndSettle();

      expect(
          find.text('The other team has nobody to swap with.'), findsOneWidget);
      expect(teams.savedLineup, isNull);
    });

    testWidgets('regenerating still replaces a manually edited lineup (§11)',
        (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Move to the other team'));
      await tester.pumpAndSettle();
      expect(find.text('Team A'), findsOneWidget);

      await tester.tap(find.text('Regenerate teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate teams').last);
      await tester.pumpAndSettle();

      // The engine split four players two a side; the manual move is gone and
      // nothing tried to preserve or reapply it.
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
    });
  });

  group('correcting a completed match', () {
    Future<void> tapPlayer(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    CommunityMember member(String id, String name) => CommunityMember(
          userId: id,
          fullName: name,
          position: 'MID',
          role: CommunityRole.player,
        );

    FakeMemberAdapter roster() => FakeMemberAdapter(
          role: CommunityRole.admin,
          members: [
            member('u1', 'Sara Al Balushi'),
            member('u2', 'Ahmed Al Harthy'),
            member('u3', 'Noor Al Kindi'),
            member('u4', 'Yousef Al Amri'),
            member('u5', 'Layla Al Riyami'),
          ],
        );

    testWidgets('an upcoming match offers none of it', (tester) async {
      // Before the match is over there is no record of who played to correct;
      // the roster is the players' own to join and leave.
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add a player who played'), findsNothing);

      await tapPlayer(tester, 'Sara Al Balushi');
      expect(find.text('Remove from the match'), findsNothing);
    });

    testWidgets('a player who has no role is offered none of it either',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches:
            FakeMatchAdapter(match: playedMatch, registrations: fourSeats()),
        role: CommunityRole.player,
      );
      await tester.pumpAndSettle();

      expect(find.text('Add a player who played'), findsNothing);
    });

    testWidgets('a member who played can be added to a side', (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      final members = roster();
      await pumpTeams(
        tester,
        teams: teams,
        matches:
            FakeMatchAdapter(match: playedMatch, registrations: fourSeats()),
        members: members,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a player who played'));
      await tester.pumpAndSettle();

      // Only the members who are not already in the lineup are offered.
      expect(find.text('Layla Al Riyami'), findsOneWidget);
      expect(find.text('Sara Al Balushi'), findsOneWidget,
          reason: 'the one behind the dialog, in the lineup itself');

      await tester.tap(find.text('Layla Al Riyami'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Team B'),
      ));
      await tester.pumpAndSettle();
      // The dialog is over the lineup, which names a defender of its own.
      await tester.tap(find.text('Defender').last);
      await tester.pumpAndSettle();

      expect(teams.addedUserId, 'u5');
      expect(teams.addedTeam, TeamId.b);
      expect(teams.addedPosition, Position.def);
      expect(members.memberReads, 1,
          reason: 'the member list is read when it is needed, not on every '
              'visit to the screen');
      expect(find.text('Team B'), findsOneWidget);
    });

    testWidgets('with everybody already in the lineup there is nobody to add',
        (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches:
            FakeMatchAdapter(match: playedMatch, registrations: fourSeats()),
        members: FakeMemberAdapter(
          role: CommunityRole.admin,
          members: [
            member('u1', 'Sara Al Balushi'),
            member('u2', 'Ahmed Al Harthy'),
            member('u3', 'Noor Al Kindi'),
            member('u4', 'Yousef Al Amri'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a player who played'));
      await tester.pumpAndSettle();

      expect(find.text('Every community member is already in this lineup.'),
          findsOneWidget);
    });

    testWidgets('a player can be taken out, after being asked about',
        (tester) async {
      final teams =
          FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs());
      await pumpTeams(
        tester,
        teams: teams,
        matches:
            FakeMatchAdapter(match: playedMatch, registrations: fourSeats()),
        members: roster(),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Remove from the match'));
      await tester.pumpAndSettle();

      expect(find.text('Remove this player?'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(teams.removedUserId, isNull,
          reason: 'answering no takes nothing back');

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Remove from the match'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Remove from the match'));
      await tester.pumpAndSettle();

      expect(teams.removedUserId, 'u1');
      expect(find.text('Team A'), findsOneWidget);
    });

    testWidgets('taking out the recorded MVP says which rule refused it',
        (tester) async {
      final teams = FakeTeamAdapter(
        lineup: storedLineup(),
        roster: fourInputs(),
      )..participationFailure =
          const ConflictFailure(FailureReason.resultParticipantRemoved);
      await pumpTeams(
        tester,
        teams: teams,
        matches:
            FakeMatchAdapter(match: playedMatch, registrations: fourSeats()),
        members: roster(),
      );
      await tester.pumpAndSettle();

      await tapPlayer(tester, 'Sara Al Balushi');
      await tester.tap(find.text('Remove from the match'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Remove from the match'));
      await tester.pumpAndSettle();

      // Not "the lineup was refused": the organizer has to know to correct the
      // result first.
      expect(
        find.text('This player is the best player or a scorer in the recorded '
            'result. Edit the result first.'),
        findsOneWidget,
      );
    });
  });

  group('localization', () {
    testWidgets('Arabic renders the screen in Arabic', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();

      expect(find.text('الفريقان'), findsWidgets);
      expect(find.text('الفريق أ'), findsOneWidget);
      expect(find.text('الفريق ب'), findsOneWidget);
      expect(find.text('الفريق أ (2)'), findsNothing);
      expect(find.text('الفريق ب (2)'), findsNothing);
      expect(find.text('إعادة إنشاء الفرق'), findsOneWidget);
      // The position label is gone from the card — the row it sits in says it —
      // so what is checked here is that the names and the chrome are Arabic.
      expect(find.text('Sara Al Balushi'), findsOneWidget);
    });

    testWidgets('Arabic reads right to left', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();

      expect(Directionality.of(tester.element(find.text('الفريق أ'))),
          TextDirection.rtl);
    });

    testWidgets('the manual override dialogs are Arabic too', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sara Al Balushi'));
      await tester.pumpAndSettle();

      expect(find.text('تعديل Sara Al Balushi'), findsOneWidget);
      expect(find.text('نقل إلى الفريق الآخر'), findsOneWidget);
      expect(find.text('تبديل مع لاعب'), findsOneWidget);
      expect(find.text('تغيير المركز'), findsOneWidget);
      expect(
          Directionality.of(tester.element(find.text('نقل إلى الفريق الآخر'))),
          TextDirection.rtl);
    });

    testWidgets('the empty state is Arabic too', (tester) async {
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();

      expect(find.text('لم تُنشأ فرق هذه المباراة بعد.'), findsOneWidget);
      expect(find.text('إنشاء الفرق'), findsOneWidget);
    });
  });

  // --- player identity on the pitch ---------------------------------------------

  group('a face on the pitch', () {
    TeamAssignment guestOnPitch(String guestId, TeamId team) => TeamAssignment(
          professionalGuestId: guestId,
          team: team,
          assignedPosition: null,
          basis: null,
        );

    testWidgets('a reader who cannot manage opens the player instead',
        (tester) async {
      final observer = _PitchRouteRecorder();
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: CommunityRole.player,
        observer: observer,
      );
      await tester.pumpAndSettle();
      observer.pushed.clear();

      await tester.tap(find.text('Sara Al Balushi'));

      final screen = observer.pushed.single
          .builder(tester.element(find.byType(TeamsScreen)));
      expect((screen as ProfileScreen).userId, 'u1');
      observer.discard();
    });

    testWidgets('an organizer still gets the management sheet', (tester) async {
      final observer = _PitchRouteRecorder();
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(lineup: storedLineup(), roster: fourInputs()),
        matches: FakeMatchAdapter(match: match, registrations: fourSeats()),
        role: CommunityRole.admin,
        observer: observer,
      );
      await tester.pumpAndSettle();
      observer.pushed.clear();

      await tester.tap(find.text('Sara Al Balushi'));
      await tester.pumpAndSettle();

      expect(find.text('Move to the other team'), findsOneWidget,
          reason: 'the management action wins where there is one');
      expect(observer.pushed, isEmpty);
    });

    testWidgets('a Professional Guest is marked as one and opens nothing',
        (tester) async {
      final observer = _PitchRouteRecorder();
      await pumpTeams(
        tester,
        teams: FakeTeamAdapter(
          lineup: [...storedLineup(), guestOnPitch('g1', TeamId.a)],
          roster: fourInputs(),
        ),
        matches: FakeMatchAdapter(
          match: match,
          registrations: [
            ...fourSeats(),
            const MatchRegistration(
              registrationId: 'reg-g1',
              professionalGuestId: 'g1',
              fullName: 'Ahmed',
              status: RegistrationStatus.confirmed,
              registrationOrder: 5,
            ),
          ],
        ),
        role: CommunityRole.player,
        observer: observer,
      );
      await tester.pumpAndSettle();
      observer.pushed.clear();

      // The badge the roster uses for a guest, on the pitch as well: before
      // this they shared the plain disc with a player who had left the match.
      expect(find.byIcon(Icons.workspace_premium_outlined), findsOneWidget);

      // The pitch prints the participant's own name, not the roster label.
      await tester.tap(find.text('Ahmed'));
      await tester.pumpAndSettle();
      expect(observer.pushed, isEmpty,
          reason: 'a guest has no account and therefore no record to open');
    });
  });
}

/// Records a pushed route without letting it build: `ProfileScreen` makes the
/// production repositories when nobody injects any, and this suite has no data
/// provider.
class _PitchRouteRecorder extends NavigatorObserver {
  final List<MaterialPageRoute<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }

  void discard() {
    for (final route in pushed) {
      navigator?.removeRoute(route);
    }
    pushed.clear();
  }
}

// --- Fake ports -------------------------------------------------------------
//
// Each answers from memory and records what it was handed, as the fakes in
// `repository_behaviour_test.dart` do. Methods the screen never reaches are
// left unimplemented on purpose.

class FakeTeamAdapter implements TeamAdapter {
  FakeTeamAdapter({
    this.roster = const [],
    List<TeamAssignment> lineup = const [],
    this.saveFailure,
    this.saveGate,
    this.failAfterClearing = false,
  }) : _lineup = [...lineup];

  final List<PlayerCoreInputs> roster;
  final Failure? saveFailure;

  /// Fails the save the way the real one can: storing a lineup replaces the
  /// previous one by clearing it first, so a failure after that point leaves
  /// the match with no lineup at all.
  final bool failAfterClearing;

  /// Held open to keep a save running while the test looks at the screen.
  final Future<void>? saveGate;

  List<TeamAssignment> _lineup;

  int lineupReads = 0;
  int saveCount = 0;
  String? lastCommunityId;
  String? lastExcludedMatchId;
  int? lastLimit;
  List<TeamAssignment>? savedLineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
          String matchId) async =>
      roster;

  @override
  Future<List<PastMatch>> fetchPlayedLineups({
    required String communityId,
    required String excludeMatchId,
    required int limit,
  }) async {
    lastCommunityId = communityId;
    lastExcludedMatchId = excludeMatchId;
    lastLimit = limit;
    return const [];
  }

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async {
    lineupReads++;
    return _lineup;
  }

  @override
  Future<void> saveLineup(String matchId, List<TeamAssignment> lineup) async {
    if (saveGate != null) await saveGate;
    if (failAfterClearing) _lineup = [];
    if (saveFailure != null) throw saveFailure!;
    saveCount++;
    savedLineup = lineup;
    _lineup = [...lineup];
  }

  /// What the completed-match corrections asked for. The database is what
  /// recalculates around them, so a fake only has to record the request and
  /// leave the stored lineup showing it.
  String? addedUserId;
  TeamId? addedTeam;
  Position? addedPosition;
  String? removedUserId;
  Failure? participationFailure;

  @override
  Future<void> addPlayedPlayer(
    String matchId,
    String userId, {
    required TeamId team,
    required Position position,
  }) async {
    if (participationFailure != null) throw participationFailure!;
    addedUserId = userId;
    addedTeam = team;
    addedPosition = position;
    _lineup = [
      ..._lineup,
      TeamAssignment(
        userId: userId,
        team: team,
        assignedPosition: position,
        basis: AssignmentBasis.primary,
      ),
    ];
  }

  @override
  Future<void> removePlayedPlayer(String matchId, String userId) async {
    if (participationFailure != null) throw participationFailure!;
    removedUserId = userId;
    _lineup = [
      for (final assignment in _lineup)
        if (assignment.userId != userId) assignment,
    ];
  }
}

class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({
    required this.match,
    required this.registrations,
    this.thrown,
    this.gate,
  });

  final Match match;
  final List<MatchRegistration> registrations;
  final Failure? thrown;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  @override
  Future<Match> fetchMatch(String matchId) async {
    if (gate != null) await gate;
    if (thrown != null) throw thrown!;
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
  FakeMemberAdapter({this.role, this.members = const []});

  final CommunityRole? role;

  /// Read only when a completed match is being corrected, which is the point:
  /// the screen fetches the list when the dialog opens rather than with every
  /// visit.
  final List<CommunityMember> members;
  int memberReads = 0;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  Future<List<CommunityMember>> fetchMembers(String communityId) async {
    memberReads++;
    return members;
  }

  @override
  Future<void> setMemberRole(
    String communityId,
    String userId,
    CommunityRole role,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> transferOwnership(String communityId, String newOwnerId) =>
      throw UnimplementedError();

  @override
  Future<void> removeMember(String communityId, String userId) =>
      throw UnimplementedError();
}

/// A match with no recorded result, which is every match in this file.
class _NoResult implements ResultAdapter {
  @override
  Future<MatchResult?> fetchResult(String matchId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the teams screen reads no other result data');
}
