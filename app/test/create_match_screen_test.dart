import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/app_header.dart';
import 'package:go_play/core/club_task.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/create_match_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';

void main() {
  Future<void> pumpCreate(
    WidgetTester tester, {
    CreateMatchAdapter? adapter,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: CreateMatchScreen(
          communityId: 'c1',
          matchService:
              adapter == null ? null : MatchService(adapter),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the Club task primitives with a scrollable form',
      (tester) async {
    await pumpCreate(tester);

    expect(find.byType(ClubTaskBar), findsOneWidget);
    expect(find.byType(ClubTaskBody), findsOneWidget);
    expect(find.byType(ClubActionBar), findsOneWidget);
    expect(find.byType(CurrentUserMenu), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ClubTaskBody),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('Create match'),
      ),
      findsNothing,
      reason: 'the only commit action is pinned outside the scrolling form',
    );
  });

  testWidgets('the task back action still pops without submitting',
      (tester) async {
    final adapter = CreateMatchAdapter();
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreateMatchScreen(
                  communityId: 'c1',
                  matchService: MatchService(adapter),
                ),
              ),
            ),
            child: const Text('Open Create Match'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Create Match'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateMatchScreen), findsNothing);
    expect(adapter.writes, 0);
  });

  testWidgets('validation still prevents an invalid submission', (tester) async {
    final adapter = CreateMatchAdapter();
    await pumpCreate(tester, adapter: adapter);

    await tester.tap(find.widgetWithText(FilledButton, 'Create match'));
    await tester.pump();

    expect(adapter.writes, 0);
    expect(find.text('Pick the date and times'), findsOneWidget);
  });

  testWidgets('the pinned action submits once and disables while busy',
      (tester) async {
    final gate = Completer<void>();
    final adapter = CreateMatchAdapter(gate: gate.future);
    await pumpCreate(tester, adapter: adapter);
    await fillValidForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create match'));
    await tester.pump();

    expect(adapter.writes, 1);
    // Found by where it sits, not by what it says: while the submission is in
    // flight the button swaps its label for a spinner, so a finder that goes
    // by the text cannot see it in the one state this test is about.
    final pinned = find.descendant(
      of: find.byType(ClubActionBar),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(pinned).onPressed, isNull);

    await tester.tap(pinned);
    await tester.pump();
    expect(adapter.writes, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    expect(find.byType(CreateMatchScreen), findsNothing);
  });

  testWidgets('Arabic RTL builds at 320px without an overflow', (tester) async {
    await pumpCreate(
      tester,
      locale: const Locale('ar'),
      size: const Size(320, 700),
    );

    expect(find.byType(ClubTaskBar), findsOneWidget);
    expect(find.byType(ClubActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English builds at 480px without an overflow', (tester) async {
    await pumpCreate(tester, size: const Size(480, 900));

    expect(find.byType(ClubTaskBody), findsOneWidget);
    expect(find.byType(ClubActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Friday Night');
  await tester.enterText(find.byType(TextFormField).at(1), 'Al Amerat Pitch');

  await tester.tap(find.widgetWithText(ListTile, 'Date'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.chevron_right));
  await tester.pumpAndSettle();
  await tester.tap(find.text('1').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Keep the existing start default, then choose 9:00 PM as the end. The date
  // is next month, so this remains a valid future schedule in every test run.
  await tester.tap(find.widgetWithText(ListTile, 'Start time'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Through the picker's text-input mode rather than its dial. The dial's
  // numbers are painted by a `CustomPainter`, not built as `Text`, so there is
  // no '9' on the clock face for a finder to tap — the keyboard toggle is the
  // only way in from a test.
  await tester.tap(find.widgetWithText(ListTile, 'End time'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to text input mode'));
  await tester.pumpAndSettle();

  // Scoped to the dialog: the form's own fields are still in the tree behind
  // it, so an unscoped `byType(TextField)` picks one of those instead.
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  final hour = fields.at(0);
  final minute = fields.at(1);
  await tester.enterText(hour, '9');
  await tester.enterText(minute, '00');
  await tester.tap(find.text('PM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

class CreateMatchAdapter implements MatchAdapter {
  CreateMatchAdapter({this.gate});

  final Future<void>? gate;
  int writes = 0;

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
  }) async {
    writes++;
    if (gate != null) await gate;
  }

  @override
  Future<Match> fetchMatch(String matchId) => throw UnimplementedError();

  @override
  Future<MatchAccessContext> fetchAccessContext(String matchId) =>
      throw UnimplementedError();

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchCommunityMatches(String communityId) =>
      throw UnimplementedError();

  @override
  Future<List<Match>> fetchUpcomingMatches() => throw UnimplementedError();

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
}
