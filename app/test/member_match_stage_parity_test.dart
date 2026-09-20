import 'package:btge/btge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/club_place.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/football/football_adapter.dart';
import 'package:go_play/features/football/football_models.dart';
import 'package:go_play/features/football/football_repository.dart';
import 'package:go_play/features/football/member_match_stage.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/teams/match_stage_board.dart';
import 'package:go_play/features/teams/pitch_view.dart';

/// A member's own completed match is the same football as everybody else's.
///
/// **The route this closes.** A guest opening a played match got the Match
/// Stage; a member opening it from Discover got the Match Stage; a member
/// opening the *same match* from their own community got a roster list on a
/// white sheet. Completed-match parity was two thirds done.
///
/// What is asserted here is that the member's community route now mounts the
/// same primitives — and, just as carefully, that it gave nothing away doing
/// so: every action is still behind the role that always guarded it, and an
/// upcoming match is untouched.
void main() {
  Match match({
    required bool completed,
    String id = 'm1',
    String createdBy = 'someone-else',
  }) =>
      Match(
        id: id,
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        title: 'Friday football',
        location: 'Al Amerat Pitch',
        startAt: completed
            ? DateTime.now().subtract(const Duration(days: 2))
            : DateTime.now().add(const Duration(days: 2)),
        endAt: completed
            ? DateTime.now().subtract(const Duration(days: 2, hours: -2))
            : DateTime.now().add(const Duration(days: 2, hours: 2)),
        startingPlayers: 10,
        maxRegistration: 14,
        status: completed ? MatchStatus.completed : MatchStatus.open,
        createdBy: createdBy,
      );

  CompletedMatch football({bool hasResult = true}) => CompletedMatch(
        matchId: 'm1',
        communityId: 'c1',
        communityName: 'Al Amerat FC',
        location: 'Al Amerat Pitch',
        startAt: DateTime.now().subtract(const Duration(days: 2)),
        endAt: DateTime.now().subtract(const Duration(days: 2, hours: -2)),
        title: 'Friday football',
        isHistorical: false,
        hasResult: hasResult,
        teamAScore: hasResult ? 3 : null,
        teamBScore: hasResult ? 2 : null,
      );

  LineupSlot slot(String id, String name, FootballTeam team, String position) =>
      LineupSlot(
        matchId: 'm1',
        participant: FootballParticipant(
          type: ParticipantType.user,
          displayName: name,
          userId: id,
        ),
        team: team,
        assignedPosition: position,
        goals: 0,
        isMvp: false,
        isOutOfPosition: false,
      );

  Future<void> pump(
    WidgetTester tester, {
    required bool completed,
    CommunityRole? role,
    List<LineupSlot>? lineup,
    bool footballFails = false,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 2600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MatchDetailsScreen(
        matchId: 'm1',
        matchService: MatchService(_Matches(match(completed: completed))),
        memberRepository: MemberRepository(_Members(role)),
        authService: AuthService(_Auth()),
        footballRepository: FootballRepository(_Football(
          detail: football(),
          lineup: lineup ??
              [
                slot('u1', 'Salim Al Harthy', FootballTeam.a, 'GK'),
                slot('u2', 'Noor Al Kindi', FootballTeam.a, 'MID'),
                slot('u3', 'Yousef Al Balushi', FootballTeam.b, 'FWD'),
              ],
          fails: footballFails,
        )),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('a completed match is football first', () {
    testWidgets('it mounts the Match Stage, not a white sheet of rosters',
        (tester) async {
      await pump(tester, completed: true, role: CommunityRole.player);

      expect(find.byType(MemberMatchStage), findsOneWidget);
      expect(find.byType(MatchStageGround), findsOneWidget);
      expect(find.byType(MatchStageBoard), findsOneWidget);
      expect(find.byType(PitchView), findsNWidgets(2));
      // The Club hero the screen used to open on is gone for this state.
      expect(find.byType(ClubHero), findsNothing);
    });

    testWidgets('and the same primitives the public route uses',
        (tester) async {
      // The guest route is asserted in public_match_stage_parity_test; what
      // matters here is that this one reaches the same three.
      await pump(tester, completed: true, role: CommunityRole.player);

      expect(find.byType(MatchStageGround), findsOneWidget);
      expect(find.byType(MatchStageBoard), findsOneWidget);
      expect(find.byType(PitchView), findsNWidgets(2));
    });

    testWidgets('the players are on the pitch, by side', (tester) async {
      await pump(tester, completed: true, role: CommunityRole.player);

      final board =
          tester.widget<MatchStageBoard>(find.byType(MatchStageBoard));
      final names =
          board.lineup.map((a) => board.nameOf(a.participantId)).toList();

      expect(
          names,
          containsAll(<String>[
            'Salim Al Harthy',
            'Noor Al Kindi',
            'Yousef Al Balushi',
          ]));
      // Both sides were built, and the sides are named on the stage.
      expect(board.lineup.where((a) => a.team == TeamId.a), hasLength(2));
      expect(board.lineup.where((a) => a.team == TeamId.b), hasLength(1));
      expect(find.text('Team A'), findsWidgets);
      expect(find.text('Team B'), findsWidgets);
    });

    testWidgets('a football read that fails leaves the screen standing',
        (tester) async {
      // Presentation only: the stage is what is lost, never the match.
      await pump(
        tester,
        completed: true,
        role: CommunityRole.player,
        footballFails: true,
      );

      expect(find.byType(MemberMatchStage), findsNothing);
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
    });
  });

  group('an upcoming match is untouched', () {
    testWidgets('it keeps the Club hero and its registration UI',
        (tester) async {
      await pump(tester, completed: false, role: CommunityRole.player);

      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.byType(MemberMatchStage), findsNothing);
      expect(find.byType(MatchStageGround), findsNothing);
    });
  });

  group('management is exactly where it always was', () {
    testWidgets(
        'an admin keeps the result and management actions on a '
        'completed match', (tester) async {
      await pump(tester, completed: true, role: CommunityRole.admin);

      expect(find.byType(MemberMatchStage), findsNothing);
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.text('Match result'), findsOneWidget);
      expect(find.text('Match management'), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
    });

    testWidgets('an owner does too', (tester) async {
      await pump(tester, completed: true, role: CommunityRole.owner);

      expect(find.byType(MemberMatchStage), findsNothing);
      expect(find.byType(ClubHero), findsOneWidget);
      expect(find.text('Match result'), findsOneWidget);
      expect(find.text('Match management'), findsOneWidget);
      expect(find.text('Teams'), findsOneWidget);
    });

    testWidgets('and an ordinary player gains neither', (tester) async {
      await pump(tester, completed: true, role: CommunityRole.player);

      // The football is the same; the capability is not.
      expect(find.byType(MemberMatchStage), findsOneWidget);
      expect(find.text('Match result'), findsNothing);
      expect(find.text('Match management'), findsNothing);
      // What every member may still reach.
      expect(find.text('Teams'), findsOneWidget);
    });

    testWidgets('a reader with no role at all gains neither', (tester) async {
      await pump(tester, completed: true, role: null);

      expect(find.text('Match result'), findsNothing);
      expect(find.text('Match management'), findsNothing);
    });
  });

  group('it survives a narrow phone in both languages', () {
    for (final width in [320.0, 412.0, 480.0]) {
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        testWidgets('at ${width.toInt()}px in ${locale.languageCode}',
            (tester) async {
          await pump(
            tester,
            completed: true,
            role: CommunityRole.player,
            locale: locale,
            size: Size(width, 2600),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(MatchStageBoard), findsOneWidget);
        });
      }
    }
  });
}

class _Matches implements MatchAdapter {
  _Matches(this.match);

  final Match match;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Members implements MemberAdapter {
  _Members(this.role);

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Football implements FootballAdapter {
  _Football({required this.detail, required this.lineup, this.fails = false});

  final CompletedMatch detail;
  final List<LineupSlot> lineup;
  final bool fails;

  @override
  Future<CompletedMatch> fetchCompletedMatch(String matchId) async {
    if (fails) throw StateError('football offline');
    return detail;
  }

  @override
  Future<List<MatchRosterEntry>> fetchMatchRoster(String matchId) async {
    if (fails) throw StateError('football offline');
    return const [];
  }

  @override
  Future<List<LineupSlot>> fetchMatchLineup(String matchId) async {
    if (fails) throw StateError('football offline');
    return lineup;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth implements AuthAdapter {
  @override
  bool get isSignedIn => true;

  @override
  String? get currentUserId => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
