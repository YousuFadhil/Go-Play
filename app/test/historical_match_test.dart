import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/football_components.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/communities/community_adapter.dart';
import 'package:go_play/features/communities/community_models.dart';
import 'package:go_play/features/communities/community_repository.dart';
import 'package:go_play/features/matches/create_match_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_details_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';
import 'package:go_play/features/members/member_adapter.dart';
import 'package:go_play/features/members/member_repository.dart';
import 'package:go_play/features/results/result_adapter.dart';
import 'package:go_play/features/results/result_models.dart';
import 'package:go_play/features/results/result_repository.dart';
import 'package:go_play/features/teams/team_adapter.dart';
import 'package:go_play/features/teams/team_models.dart';
import 'package:go_play/features/teams/team_repository.dart';
import 'package:go_play/features/teams/teams_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/match_mapper.dart';
import 'package:go_play/infrastructure/supabase/supabase_failure_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Recording a match that has already been played (migration `0054`).
///
/// **One screen, two temporal rules.** The whole of Feature A on the client is
/// that Create Match can be put into a second mode, and that the mode reaches
/// the database. So what is asserted here is the mode: that an ordinary match
/// is still refused a past date, that a recorded one is not, that the flag
/// travels, and that nothing downstream treats the result as a fixture anybody
/// could have joined.
///
/// **What is deliberately not re-tested.** Participant selection, team
/// generation and result entry are the existing completed-match flows, already
/// covered by `teams_screen_test.dart` and `result_entry_screen_test.dart`. A
/// historical match reaches them by being completed, which is a property of its
/// end time — so what this file proves about them is that a historical match
/// *is* in that state and *does* get those controls, not that the controls work.
/// Proving those twice would be proving the wrong thing.
void main() {
  Match historicalMatch({
    String id = 'm1',
    Duration ago = const Duration(days: 7),
    List<MatchRegistration> ignored = const [],
  }) {
    final start = DateTime.now().subtract(ago);
    return Match(
      id: id,
      communityId: 'c1',
      createdBy: 'u9',
      location: 'Al Amerat Pitch',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      startingPlayers: 4,
      maxRegistration: 10,
      status: MatchStatus.open,
      title: 'Last Friday',
      communityName: 'Al Amerat FC',
      isHistorical: true,
    );
  }

  Match upcomingMatch() {
    final start = DateTime.now().add(const Duration(days: 2));
    return Match(
      id: 'm1',
      communityId: 'c1',
      createdBy: 'u9',
      location: 'Al Amerat Pitch',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      startingPlayers: 4,
      maxRegistration: 10,
      status: MatchStatus.open,
      title: 'Friday Night',
      communityName: 'Al Amerat FC',
    );
  }

  Future<void> pumpCreate(WidgetTester tester, _CreateAdapter adapter) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: CreateMatchScreen(
        communityId: 'c1',
        matchService: MatchService(adapter),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Fills the form in, choosing a day [dayOffset] days from today and a time
  /// written the way the en_US pickers accept it: a twelve-hour clock with a
  /// meridiem.
  ///
  /// The pickers are driven rather than stubbed, because which days they offer
  /// is half of what the mode changes: a form that accepted a past date only
  /// because the test reached around the picker would prove nothing about the
  /// screen a reader actually gets.
  Future<void> fillForm(
    WidgetTester tester, {
    required int dayOffset,
    required String start,
    required String end,
  }) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.enterText(find.byType(TextFormField).at(0), 'Last Friday');
    await tester.enterText(find.byType(TextFormField).at(1), 'Al Amerat Pitch');
    await tester.pumpAndSettle();

    final day = DateTime.now().add(Duration(days: dayOffset));
    await tester.tap(find.text(l10n.dateLabel));
    await tester.pumpAndSettle();
    // Typed rather than tapped out of the calendar grid: a grid cell moves with
    // the month and is ambiguous when the same number appears in the trailing
    // days of the previous one.
    // By tooltip rather than by icon: the icon is a code point that moves with
    // the Material font, and the tooltip is the string the framework's own
    // localizations define for this control.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(
      // Scoped to the dialog. The form's own title and location fields are
      // still mounted behind it, and an unscoped finder types the date into
      // one of those instead — silently, because both accept text.
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextField),
      ),
      '${day.month.toString().padLeft(2, '0')}/'
      '${day.day.toString().padLeft(2, '0')}/${day.year}',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    for (final (label, value) in [
      (l10n.startTimeLabel, start),
      (l10n.endTimeLabel, end),
    ]) {
      final parts = value.split(' ');
      final clock = parts[0].split(':');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      // Scoped for the same reason the date is: unscoped, `at(0)` and `at(1)`
      // are the form's title and location, and the hour lands in the match name.
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), clock[0]);
      await tester.enterText(fields.at(1), clock[1]);
      await tester.pumpAndSettle();
      // The meridiem is a control of its own in twelve-hour mode, and the hour
      // field alone cannot say which half of the day was meant.
      await tester.tap(find.text(parts[1]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  }

  /// The screen's one commit control. Found by its button rather than by its
  /// words: the task bar's title and the button's label are the same sentence,
  /// and `find.text` would match both.
  Finder submitButton() => find.byType(FilledButton).last;

  group('the temporal rule an ordinary match is under is unchanged', () {
    testWidgets('a future match is still created, and is not historical',
        (tester) async {
      final adapter = _CreateAdapter();
      await pumpCreate(tester, adapter);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await fillForm(
          tester, dayOffset: 3, start: '8:00 PM', end: '10:00 PM');
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(adapter.writes, 1);
      expect(adapter.lastIsHistorical, isFalse,
          reason: 'a scheduled match must not be recorded as a played one');
    });

    testWidgets('a past date is still refused while the mode is off',
        (tester) async {
      final adapter = _CreateAdapter();
      await pumpCreate(tester, adapter);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // The picker will not offer a past day in this mode, so the past is
      // reached the only way a reader could reach it: today, at a time that has
      // already gone by. Midnight is the one such time that is in the past on
      // every run, whatever hour the suite happens to start.
      await fillForm(
          tester, dayOffset: 0, start: '12:00 AM', end: '12:30 AM');
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(adapter.writes, 0, reason: 'nothing may be sent');
      expect(find.text(l10n.startInPastError), findsOneWidget);
    });
  });

  group('recording a match that was already played', () {
    testWidgets('the mode is offered on the existing screen, not a second one',
        (tester) async {
      await pumpCreate(tester, _CreateAdapter());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l10n.historicalMatchToggleLabel), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      // Still the one Create Match screen: the fields it always had are all
      // still on it.
      expect(find.text(l10n.matchTitleLabel), findsOneWidget);
      expect(find.text(l10n.startingPlayersLabel), findsOneWidget);
    });

    testWidgets('a past start and end are accepted and sent as historical',
        (tester) async {
      final adapter = _CreateAdapter();
      await pumpCreate(tester, adapter);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await fillForm(
          tester, dayOffset: -7, start: '8:00 PM', end: '10:00 PM');
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(adapter.writes, 1);
      expect(adapter.lastIsHistorical, isTrue);
      expect(adapter.lastStartAt!.isBefore(DateTime.now()), isTrue);
      expect(adapter.lastEndAt!.isBefore(DateTime.now()), isTrue);
    });

    testWidgets('the end must still be after the start', (tester) async {
      final adapter = _CreateAdapter();
      await pumpCreate(tester, adapter);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // An end before its start, by enough that rolling it into the next day
      // cannot rescue it. The screen treats an end that is not after its start
      // as a match running past midnight — which is right for 10pm to midnight
      // and absurd for 6am to 5am, and the twelve-hour bound is what tells the
      // two apart.
      await fillForm(
          tester, dayOffset: -7, start: '6:00 AM', end: '5:00 AM');
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(adapter.writes, 0);
      expect(find.text(l10n.endAfterStartError), findsOneWidget);
    });

    testWidgets('a match that has not finished cannot be recorded as played',
        (tester) async {
      final adapter = _CreateAdapter();
      await pumpCreate(tester, adapter);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // Today, ending late this evening: inside the picker's window and still
      // ahead of now.
      await fillForm(
          tester, dayOffset: 0, start: '11:00 PM', end: '11:59 PM');
      await tester.tap(submitButton());
      await tester.pumpAndSettle();

      expect(adapter.writes, 0);
      expect(find.text(l10n.historicalNotPastError), findsOneWidget);
    });

    testWidgets('turning the mode on clears a day picked for the other rule',
        (tester) async {
      await pumpCreate(tester, _CreateAdapter());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await fillForm(
          tester, dayOffset: 3, start: '8:00 PM', end: '10:00 PM');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // The date row is back to its empty mark rather than showing a day next
      // week on a form that now means "when was this played".
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(l10n.dateLabel),
            matching: find.byType(ListTile),
          ),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });
  });

  group('a recorded match never enters the registration flow', () {
    testWidgets('no registration or reserve control is offered on it',
        (tester) async {
      await _pumpDetails(tester, match: historicalMatch());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // `RegistrationStateView` is the whole of joining, withdrawing and the
      // reserve queue on this screen. A played match does not have it, so
      // there is no control to press and no reserve position to be offered.
      expect(find.byType(RegistrationStateView), findsNothing);
      expect(find.text(l10n.joinMatchButton), findsNothing);
      expect(find.text(l10n.reserveListTitle), findsNothing);
    });

    testWidgets('it says what it is, so an empty roster is not a mystery',
        (tester) async {
      await _pumpDetails(tester, match: historicalMatch());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l10n.historicalMatchBadge), findsOneWidget);
    });

    testWidgets('an ordinary upcoming match still offers registration',
        (tester) async {
      await _pumpDetails(tester, match: upcomingMatch());

      expect(find.byType(RegistrationStateView), findsOneWidget);
    });

    test('the database refusal reaches the client as its own reason', () {
      // `register_player_in_match` raises this for a historical match, on both
      // the self-registration and the admin-add path. What matters here is that
      // the client understands it as a rule rather than as an unknown fault.
      expect(
        SupabaseFailureMapper.from(
          const PostgrestException(
            message: 'error: MATCH_HISTORICAL',
            code: 'P0001',
          ),
        ),
        isA<ValidationFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.matchHistorical,
        ),
      );
    });

    test('so does the refusal to record a match that has not happened', () {
      expect(
        SupabaseFailureMapper.from(
          const PostgrestException(
            message: 'error: HISTORICAL_NOT_PAST',
            code: 'P0001',
          ),
        ),
        isA<ValidationFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.historicalNotPast,
        ),
      );
    });
  });

  group('the recorded match reaches the existing completed-match flows', () {
    test('it is completed from the moment it exists', () {
      final match = historicalMatch();
      expect(match.isCompleted, isTrue);
      expect(match.effectiveStatus, MatchStatus.completed);
      // Not "locked": locked is a match under way. This one is over.
      expect(match.isLocked, isFalse);
      expect(match.isOpenForChanges, isFalse);
    });

    testWidgets('an organizer gets the participant and team controls on it',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TeamsScreen(
          matchId: 'm1',
          matchService: MatchService(_DetailsMatchAdapter(
            match: historicalMatch(),
            registrations: const [],
          )),
          memberRepository:
              MemberRepository(_RoleAdapter(CommunityRole.admin)),
          teamRepository: TeamRepository(_LineupAdapter(const [])),
          // No lineup: a recorded match starts with nobody in it, which is
          // exactly the state the organizer has to be able to act from.
        ),
      ));
      await tester.pumpAndSettle();

      // The existing completed-match correction controls, reached because the
      // match is completed. This is the participant selection Feature A asks
      // for: `set_completed_match_player` behind the button that was already
      // there.
      expect(find.text(l10n.addPlayedPlayerAction), findsOneWidget);
    });

    test('the marker survives the round trip through the row', () {
      final row = <String, dynamic>{
        'id': 'm1',
        'community_id': 'c1',
        'created_by': 'u9',
        'location': 'Al Amerat Pitch',
        'start_at': '2026-08-20T17:00:00Z',
        'end_at': '2026-08-20T19:00:00Z',
        'starting_players': 4,
        'max_registration': 10,
        'status': 'open',
        'title': 'Last Friday',
        'description': null,
        'roster_order_mode': null,
        'is_historical': true,
      };
      expect(matchFromRow(row).isHistorical, isTrue);

      // A row from a project that has not run `0054` yet reads as false, which
      // is true of every match that existed before it.
      expect(
        matchFromRow({...row}..remove('is_historical')).isHistorical,
        isFalse,
      );
    });
  });
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required Match match,
  MatchResult? result,
  List<TeamAssignment> lineup = const [],
  CommunityRole? role = CommunityRole.player,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: MatchDetailsScreen(
      matchId: match.id,
      matchService: MatchService(
        _DetailsMatchAdapter(match: match, registrations: const []),
      ),
      memberRepository: MemberRepository(_RoleAdapter(role)),
      communityRepository: CommunityRepository(_CommunityAdapter()),
      authService: AuthService(_AuthAdapter()),
      resultRepository: ResultRepository(_ResultAdapter(result)),
      teamRepository: TeamRepository(_LineupAdapter(lineup)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Records exactly what the create screen sent.
class _CreateAdapter implements MatchAdapter {
  int writes = 0;
  bool? lastIsHistorical;
  DateTime? lastStartAt;
  DateTime? lastEndAt;

  @override
  Future<void> createMatch({
    required String communityId,
    required String title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    bool isHistorical = false,
  }) async {
    writes++;
    lastIsHistorical = isHistorical;
    lastStartAt = startAt;
    lastEndAt = endAt;
  }

  @override
  Future<int?> fetchReservePlayers() async => 6;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the create screen writes and nothing else');
}

class _DetailsMatchAdapter implements MatchAdapter {
  _DetailsMatchAdapter({required this.match, required this.registrations});

  final Match match;
  final List<MatchRegistration> registrations;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      registrations;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other match data is read here');
}

class _RoleAdapter implements MemberAdapter {
  _RoleAdapter(this.role);

  final CommunityRole? role;

  @override
  Future<CommunityRole?> fetchMyRole(String communityId) async => role;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other member data is read here');
}

class _ResultAdapter implements ResultAdapter {
  _ResultAdapter(this.result);

  final MatchResult? result;

  @override
  Future<MatchResult?> fetchResult(String matchId) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other result data is read here');
}

class _LineupAdapter implements TeamAdapter {
  _LineupAdapter(this.lineup);

  final List<TeamAssignment> lineup;

  @override
  Future<List<TeamAssignment>> fetchLineup(String matchId) async => lineup;

  @override
  Future<List<PlayerCoreInputs>> fetchConfirmedPlayerInputs(
    String matchId,
  ) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other team data is read here');
}

class _CommunityAdapter implements CommunityAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no community data is read here');
}

class _AuthAdapter implements AuthAdapter {
  @override
  String? get currentUserId => 'u1';

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other auth data is read here');
}
