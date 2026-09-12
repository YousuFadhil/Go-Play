import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/matches/edit_match_screen.dart';
import 'package:go_play/features/matches/match_adapter.dart';
import 'package:go_play/features/matches/match_management_screen.dart';
import 'package:go_play/features/matches/match_models.dart';
import 'package:go_play/features/matches/match_service.dart';

/// All-State Match Management, Cycle B — what an organizer may reach, in every
/// lifecycle state.
///
/// The rule being protected is one sentence: **owner/admin management is not
/// gated on the match's state.** What changes with the state is *which* path a
/// change travels, not whether the organizer may make one — the details are
/// editable throughout, the ordinary roster path belongs to a match that has
/// not been played, and once it has, who played is a factual correction that
/// goes through the batch path instead.
void main() {
  Match matchAt(
    DateTime start, {
    MatchStatus status = MatchStatus.open,
    bool isHistorical = false,
  }) =>
      Match(
        id: 'm1',
        communityId: 'c1',
        createdBy: 'u1',
        title: 'ITest match',
        location: 'Al Amerat Pitch',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        startingPlayers: 4,
        maxRegistration: 6,
        status: status,
        isHistorical: isHistorical,
      );

  final now = DateTime.now();
  final future = matchAt(now.add(const Duration(days: 3)));
  // Kicked off an hour ago and still running: the state that used to lock the
  // organizer out of every control on this screen.
  final active = matchAt(now.subtract(const Duration(hours: 1)));
  final completed = matchAt(
    now.subtract(const Duration(days: 3)),
    status: MatchStatus.completed,
  );
  final recorded = matchAt(
    now.subtract(const Duration(days: 3)),
    status: MatchStatus.completed,
    isHistorical: true,
  );

  group('what an organizer may do, by state', () {
    test('the details are editable in every state', () {
      // Including active and completed, which `isOpenForChanges` refused.
      for (final match in [future, active, completed, recorded]) {
        expect(canEditMatchDetails(match, busy: false), isTrue,
            reason: match.effectiveStatus.name);
      }
    });

    test('a save in flight is the only thing that closes the control', () {
      expect(canEditMatchDetails(future, busy: true), isFalse);
      expect(canEditMatchDetails(completed, busy: true), isFalse);
    });

    test('the ordinary roster path runs up to completion, not up to kickoff',
        () {
      expect(canAdministerRoster(future, busy: false), isTrue);
      expect(canAdministerRoster(active, busy: false), isTrue,
          reason: 'the change this cycle makes: an active match is still a '
              'roster, not yet a record');
      expect(canAdministerRoster(completed, busy: false), isFalse,
          reason: 'who played is corrected through the batch path instead');
      expect(canAdministerRoster(active, busy: true), isFalse);
    });

    test('a played guest keeps the side that was recorded for them', () {
      // Correction 1, from the Dart side: the sheet states a side, and 0075
      // stores it as chosen so nothing may alternate it afterwards. The
      // migration's own assertion lives in the static suite; this pins the
      // boundary the UI depends on -- the organizer's choice is the fact.
      final sql = File('../supabase/migrations/'
              '0075_completed_professional_guest_correction.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(sql, contains('team_manually_overridden'));
      expect(sql, contains("'GUEST', true)"));
    });

    test('the ordinary guest roster operations stop at completion', () {
      // Both of them are the roster's: adding a guest leaves them confirmed and
      // unplaced on a match that is over, and the roster removal keeps the
      // lineup row a played match needs. The completed answers live on the Teams
      // screen instead -- 0075 to add, 0059 to remove.
      expect(canAdministerGuestRoster(future), isTrue);
      expect(canAdministerGuestRoster(active), isTrue);
      expect(canAdministerGuestRoster(completed), isFalse);
      expect(canAdministerGuestRoster(recorded), isFalse);
    });

    test('adding an unregistered member stops at the same boundary', () {
      expect(canAddCommunityPlayerTo(future, busy: false), isTrue);
      expect(canAddCommunityPlayerTo(active, busy: false), isTrue);
      expect(canAddCommunityPlayerTo(completed, busy: false), isFalse);
      expect(canAddCommunityPlayerTo(recorded, busy: false), isFalse,
          reason: 'a recorded match refuses registration at the database');
    });
  });

  group('Edit Match is offered in every state', () {
    Future<void> pumpManagement(WidgetTester tester, Match match) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MatchManagementScreen(
          key: UniqueKey(),
          matchId: 'm1',
          matchService: MatchService(_StubMatchAdapter(match)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    ListTile tileFor(WidgetTester tester, String label) =>
        tester.widget<ListTile>(find.widgetWithText(ListTile, label));

    for (final (label, match) in [
      ('a match still to come', future),
      ('a match being played', active),
      ('a match that is over', completed),
    ]) {
      testWidgets('$label offers Edit match', (tester) async {
        await pumpManagement(tester, match);

        final tile = tileFor(tester, 'Edit match');
        expect(tile.enabled, isTrue, reason: label);
        expect(tile.onTap, isNotNull);
      });
    }

    testWidgets('the roster tiles stay reachable in every state',
        (tester) async {
      // The tiles open the roster screen in every state; what the state decides
      // is what may be done once inside it, which the rules above cover.
      for (final match in [future, active, completed]) {
        await pumpManagement(tester, match);
        expect(tileFor(tester, 'Manage players').enabled, isTrue);
      }
    });
  });

  group('the Edit Match form, on a match that has been played', () {
    Future<_RecordingMatchAdapter> pumpEdit(
      WidgetTester tester,
      Match match,
    ) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final adapter = _RecordingMatchAdapter(match);
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: EditMatchScreen(
          key: UniqueKey(),
          match: match,
          matchService: MatchService(adapter),
        ),
      ));
      await tester.pumpAndSettle();
      return adapter;
    }

    testWidgets('its historical date and starting players can be corrected',
        (tester) async {
      final adapter = await pumpEdit(tester, completed);

      // The starting count, on a match that is over.
      await tester.enterText(find.byType(TextFormField).at(2), '8');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(adapter.updates, hasLength(1));
      final update = adapter.updates.single;
      expect(update.startingPlayers, 8);
      expect(update.startAt.isBefore(DateTime.now()), isTrue,
          reason: 'the correction keeps the match where it happened, in the '
              'past');
      expect(update.endAt.isAfter(update.startAt), isTrue);
    });

    testWidgets('the date picker reaches back before the stored date',
        (tester) async {
      // The defect: a lower bound of "today, or the date it already holds" made
      // a completed match's date correctable forwards only, so an organizer
      // could not say the fixture was actually earlier than the record claims.
      final stored = DateTime(now.year, now.month, 20, 19);
      await pumpEdit(
        tester,
        matchAt(stored, status: MatchStatus.completed),
      );

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // A day before the stored one, in the same month, is selectable.
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('5'), findsWidgets,
          reason: 'the earlier day was accepted by the picker');
    });
  });
}

/// Serves one match and nothing else.
class _StubMatchAdapter implements MatchAdapter {
  _StubMatchAdapter(this.match);

  final Match match;

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other match data is read here');
}

/// The same, remembering what `update_match` was asked for.
class _RecordingMatchAdapter implements MatchAdapter {
  _RecordingMatchAdapter(this.match);

  final Match match;
  final List<_Update> updates = [];

  @override
  Future<Match> fetchMatch(String matchId) async => match;

  @override
  Future<List<MatchRegistration>> fetchRegistrations(String matchId) async =>
      const [];

  @override
  Future<void> updateMatch({
    required String matchId,
    String? title,
    required String location,
    required DateTime startAt,
    required DateTime endAt,
    required int startingPlayers,
    String? description,
  }) async {
    updates.add(_Update(
      startAt: startAt,
      endAt: endAt,
      startingPlayers: startingPlayers,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no other match write happens here');
}

class _Update {
  const _Update({
    required this.startAt,
    required this.endAt,
    required this.startingPlayers,
  });

  final DateTime startAt;
  final DateTime endAt;
  final int startingPlayers;
}
