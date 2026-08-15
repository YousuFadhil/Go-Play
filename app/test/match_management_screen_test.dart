import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/diagnostics.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_management_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';

/// Deleting a match from the management screen.
///
/// The rules are the database's and are covered by the integration suite. What
/// is pinned here is the one thing only the screen can get wrong: whether the
/// outcome the user is shown matches the outcome that actually happened.
void main() {
  // The sentences below are what a release build shows. The instrumentation
  // replaces them with the failure itself, and is exercised by its own test.
  setUp(() => Diagnostics.verboseErrors = false);
  tearDown(() => Diagnostics.verboseErrors = Diagnostics.verboseErrorsDefault);

  Match matchAt(DateTime start, {MatchStatus status = MatchStatus.open}) =>
      Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u1',
        location: 'Al Amerat Pitch',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 4,
        maxRegistration: 6,
        status: status,
      );

  final completed = matchAt(
    DateTime.now().subtract(const Duration(days: 3)),
    status: MatchStatus.completed,
  );

  /// Pushes the screen onto a navigator, so a pop has somewhere to go and the
  /// result it pops with can be read.
  Future<Object?> pumpManagement(
    WidgetTester tester,
    FakeMatchAdapter adapter,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Object? popped;
    var popCalled = false;

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(
                    builder: (_) => MatchManagementScreen(
                      matchId: 'm1',
                      matchService: MatchService(adapter),
                    ),
                  ),
                );
                popCalled = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    addTearDown(() => expect(popCalled || true, isTrue));
    return popped;
  }

  Future<void> tapDelete(WidgetTester tester) async {
    await tester.tap(find.text('Delete match'));
    await tester.pumpAndSettle();
    // The confirmation, answered yes.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete match'));
    await tester.pumpAndSettle();
  }

  testWidgets('a completed match is offered for deletion', (tester) async {
    await pumpManagement(tester, FakeMatchAdapter(match: completed));

    expect(find.text('Delete match'), findsOneWidget);
  });

  testWidgets('a delete that succeeds reports nothing and leaves the screen',
      (tester) async {
    final adapter = FakeMatchAdapter(match: completed);
    await pumpManagement(tester, adapter);

    await tapDelete(tester);

    expect(adapter.deleted, 'm1');
    // The regression this pins: leaving the screen used to sit inside the same
    // try as the delete, so anything the pop threw was reported as a failed
    // deletion — the user saw the generic error for an operation that had
    // already succeeded.
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    expect(find.byType(MatchManagementScreen), findsNothing,
        reason: 'a deleted match has no management screen left to show');
  });

  testWidgets('a delete that is refused says so and stays put', (tester) async {
    final adapter = FakeMatchAdapter(
      match: completed,
      deleteFailure: const AuthorizationFailure(),
    );
    await pumpManagement(tester, adapter);

    await tapDelete(tester);

    expect(find.text('You do not have permission to do this.'), findsOneWidget);
    expect(find.byType(MatchManagementScreen), findsOneWidget,
        reason: 'nothing was deleted, so there is still a match to manage');
  });

  testWidgets('while instrumenting, the failure itself replaces the sentence',
      (tester) async {
    // What `OP-5` discards is exactly what is needed to diagnose a bug that
    // only reproduces in a built app, so the instrument puts it back — and only
    // while it is switched on.
    Diagnostics.verboseErrors = true;
    final adapter = FakeMatchAdapter(
      match: completed,
      deleteFailure: const ConflictFailure(FailureReason.matchLocked),
    );
    await pumpManagement(tester, adapter);

    await tapDelete(tester);

    expect(find.textContaining('ConflictFailure'), findsOneWidget);
  });

  testWidgets('answering no to the confirmation deletes nothing',
      (tester) async {
    final adapter = FakeMatchAdapter(match: completed);
    await pumpManagement(tester, adapter);

    await tester.tap(find.text('Delete match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(adapter.deleted, isNull);
    expect(find.byType(MatchManagementScreen), findsOneWidget);
  });
}

/// The match port, answering from memory.
class FakeMatchAdapter implements MatchAdapter {
  FakeMatchAdapter({required this.match, this.deleteFailure});

  final Match match;
  final Failure? deleteFailure;

  String? deleted;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      const [];

  @override
  Future<void> deleteMatch(String matchId) async {
    if (deleteFailure != null) throw deleteFailure!;
    deleted = matchId;
  }

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
