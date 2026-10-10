import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_merge_preview_screen.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_preview_widgets.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';
import 'package:go_play/l10n/generated/app_localizations_en.dart';

import 'admin_fakes.dart';
import 'admin_merge_fixtures.dart';
import 'wilayat_fixtures.dart';

/// Merging two accounts for good (migration 0101): what the mapper reads, what the
/// repository passes on, and what the System Admin screen lets the administrator do
/// with it.
///
/// The documents are in `admin_merge_fixtures.dart` and are what the database
/// really returned. Whether the merge is *correct* is the database's to prove and
/// is proved by the offline SQL runs; these tests prove that the screen offers it
/// only when it should, asks for what it should, sends exactly what was chosen, and
/// tells the truth about what happened.
const _retainedId = 'u1';
const _sourceId = 'u2';

// The ids inside the documents.
const _confirmedLineup = 'e15d4a62-9c37-4e79-ad50-b84e36d458f3';
const _friendly = '250a22ba-6589-45c9-afed-e3f6716742ab';
const _played = 'dbe9f954-2736-430f-91d9-40a558382be3';

Map<String, dynamic> _doc(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

AdminMergePreview _merge(String json) => adminMergePreviewFromJson(_doc(json));

AdminMergeResult _result([String json = mergeResultDoc]) =>
    adminMergeResultFromJson(
      _doc(json),
      retainedUserId: _retainedId,
      sourceUserId: _sourceId,
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  group('the mapper reads what the database really returns', () {
    test('a pair with matches to choose for: accounts, plan and matches', () {
      final preview = _merge(mergeChoicesDoc);

      expect(preview.retained.fullName, 'Retained Rita');
      expect(preview.source.fullName, 'Source Sam');
      expect(preview.source.count('goal_rows'), 1);
      expect(preview.source.count('lineup_assignments'), 2);
      expect(preview.retained.rating, 5.0);
      expect(preview.source.rating, 5.135);
      expect(preview.hasBlockers, isFalse);
      expect(preview.sharedLimit, 100);
      expect(preview.unresolvableMatchesTotal, 0);
      expect(preview.plan.sharedMatches, 3);
      expect(preview.plan.membershipsMerged, 1);
      expect(preview.plan.isEmpty, isFalse);
      expect(preview.communityStatisticsCollisions, 1);
      expect(preview.teamAwardCollisions, 0);

      final shared = preview.sharedMatches;
      expect(shared.total, 3);
      expect(shared.items.map((m) => m.matchId),
          [_confirmedLineup, _friendly, _played]);
    });

    test(
        'each shared match says which side may be kept, and what holds the '
        'other', () {
      final shared = _merge(mergeChoicesDoc).sharedMatches.items;
      final lineup = shared[0];
      final friendly = shared[1];
      final played = shared[2];

      // Keeping the retained side removes the source's. The source holds a
      // confirmed lineup, so that is closed; the other way round is open.
      expect(lineup.canKeepRetained, isFalse);
      expect(lineup.canKeepSource, isTrue);
      expect(lineup.sourceDropBlockers, ['CONFIRMED_LINEUP']);
      expect(lineup.retainedDropBlockers, isEmpty);

      expect(friendly.canKeepRetained, isTrue);
      expect(friendly.canKeepSource, isTrue);
      expect(friendly.sourceDropBlockers, isEmpty);

      expect(played.canKeepRetained, isFalse);
      expect(played.canKeepSource, isTrue);
      expect(played.sourceDropBlockers,
          ['GOALS', 'MVP', 'LINEUP_IN_RESULT', 'RATING_IN_EFFECT']);
      expect(played.sourceEvidence,
          ['GOALS', 'LINEUP', 'MVP', 'RATING', 'REGISTRATION']);
      expect(played.retainedEvidence, ['REGISTRATION']);
      expect(played.status, 'completed');
      expect(played.communityName, 'Alpha');
      expect(played.startAt, isNotNull);

      for (final match in shared) {
        expect(match.isResolvable, isTrue);
        expect(match.canKeep(AdminMergeKeep.retained), match.canKeepRetained);
        expect(match.canKeep(AdminMergeKeep.source), match.canKeepSource);
      }
    });

    test('findings keep their severity and order: a choice is a conflict', () {
      final preview = _merge(mergeChoicesDoc);

      expect(preview.findings.map((f) => f.code),
          ['SHARED_MATCH_CHOICE_REQUIRED', 'EVENT_LOGS_NAME_SOURCE']);
      expect(preview.findings.first.severity, AdminFindingSeverity.conflict);
      expect(preview.findings.first.count, 3);
      expect(preview.findings.last.severity, AdminFindingSeverity.constraint);
      expect(preview.findingsOf(AdminFindingSeverity.blocker), isEmpty);
    });

    test('a match neither side can leave is the blocker, and says why', () {
      final preview = _merge(mergeUnresolvableDoc);
      final match = preview.sharedMatches.items.single;

      expect(preview.hasBlockers, isTrue);
      expect(preview.unresolvableMatchesTotal, 1);
      expect(preview.findings.first.code, 'SHARED_MATCH_NOT_RESOLVABLE');
      expect(preview.findings.first.severity, AdminFindingSeverity.blocker);
      expect(match.canKeepRetained, isFalse);
      expect(match.canKeepSource, isFalse);
      expect(match.isResolvable, isFalse);
      expect(match.retainedDropBlockers, contains('MVP'));
      expect(match.sourceDropBlockers, isNot(contains('MVP')));
    });

    test(
        'the blockers that need no match: audit log, rating, stored file, '
        'award', () {
      final preview = _merge(mergeBlockedDoc);

      expect(preview.hasBlockers, isTrue);
      expect(
        preview.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
        [
          'AUDIT_LOG_NAMES_SOURCE',
          'RETAINED_RATING_INCONSISTENT',
          'SOURCE_HAS_STORED_FILES',
          'TEAM_AWARD_COLLISION',
        ],
      );
      expect(preview.teamAwardCollisions, 1);
      expect(preview.plan.teamAwardsMoved, 1);
    });

    test('a System Admin is a blocker', () {
      final preview = _merge(mergeSystemAdminDoc);

      expect(preview.source.isSystemAdmin, isTrue);
      expect(preview.hasBlockers, isTrue);
      expect(preview.findings.map((f) => f.code), ['SOURCE_IS_SYSTEM_ADMIN']);
    });

    test('a pair with nothing to choose still says what the merge will do', () {
      final preview = _merge(mergeCleanDoc);
      final plan = preview.plan;

      expect(preview.hasBlockers, isFalse);
      expect(preview.sharedMatches.total, 0);
      expect(preview.findingsOf(AdminFindingSeverity.conflict), isEmpty);
      expect(plan.communitiesTransferred, 1);
      expect(plan.membershipsMoved, 1);
      expect(plan.membershipsMerged, 2);
      expect(plan.rolesUpgraded, 1);
      expect(plan.registrationsMoved, 4);
      expect(plan.lineupPlacesMoved, 3);
      expect(plan.goalRowsMoved, 2);
      expect(plan.mvpAwardsMoved, 2);
      expect(plan.teamAwardsMoved, 1);
      expect(plan.createdMatchesReattributed, 2);
      expect(plan.isEmpty, isFalse);

      final owned = preview.sourceOwnedCommunities.items.single;
      expect(owned.name, 'Beta');
      expect(owned.retainedIsMember, isFalse);
      expect(
        preview.findings.map((f) => f.code),
        ['EVENT_LOGS_NAME_SOURCE', 'RATING_ARCHIVE_MAPPED'],
        reason:
            'the old id stays in archives and logs; that is told, not hidden',
      );
      expect(
        preview.findings
            .every((f) => f.severity == AdminFindingSeverity.constraint),
        isTrue,
      );
    });

    test('two accounts with nothing in the database naming them', () {
      final preview = _merge(mergeEmptyDoc);

      expect(preview.hasBlockers, isFalse);
      expect(preview.findings, isEmpty);
      expect(preview.plan.isEmpty, isTrue);
      expect(preview.sharedMatches.items, isEmpty);
      expect(preview.unresolvableMatchesTotal, 0);
    });

    test('a side the document does not say may be kept is read as closed', () {
      final json = _doc(mergeChoicesDoc);
      final item = ((json['shared_matches'] as Map)['items'] as List).first
          as Map<String, dynamic>;
      item
        ..remove('can_keep_retained')
        ..remove('can_keep_source');

      final match = adminMergePreviewFromJson(json).sharedMatches.items.first;

      expect(match.canKeepRetained, isFalse);
      expect(match.canKeepSource, isFalse);
      expect(match.isResolvable, isFalse);
    });

    test('a flag that says "none" never hides a blocker in the findings', () {
      final json = _doc(mergeUnresolvableDoc)..['has_blockers'] = false;

      expect(adminMergePreviewFromJson(json).hasBlockers, isTrue);
    });

    test('the request carries the ids and exactly the choices made', () {
      final params = adminMergeAccountsParams(
        retainedUserId: 'r',
        sourceUserId: 's',
        resolutions: const [
          AdminMergeResolution(matchId: 'm1', keep: AdminMergeKeep.retained),
          AdminMergeResolution(matchId: 'm2', keep: AdminMergeKeep.source),
        ],
      );

      expect(params, {
        'p_retained_user_id': 'r',
        'p_source_user_id': 's',
        'p_resolutions': [
          {'match_id': 'm1', 'keep': 'retained'},
          {'match_id': 'm2', 'keep': 'source'},
        ],
      });
      expect(
        adminMergeAccountsParams(
            retainedUserId: 'r',
            sourceUserId: 's',
            resolutions: const [])['p_resolutions'],
        isEmpty,
      );
    });

    test(
        'the result: what moved, what was dropped, the rating before and '
        'after', () {
      final result = _result(mergeResultWithChoicesDoc);

      expect(result.retainedUserId, '00000000-0000-4000-8000-000000000002');
      expect(result.sourceUserId, '00000000-0000-4000-8000-000000000003');
      expect(result.droppedRegistrations, 3);
      expect(result.droppedLineupPlaces, 0);
      expect(result.movedCount('goal_rows'), 1);
      expect(result.movedCount('mvp_awards'), 1);
      expect(result.movedCount('lineup_places'), 2);
      expect(result.movedCount('does_not_exist'), 0);
      expect(result.ratingBefore, 5.0);
      expect(result.ratingAfter, 5.135);
      expect(result.matchesReplayed, 1);
    });

    test('a result this build cannot read is still a merge that happened', () {
      for (final doc in [
        <String, dynamic>{},
        {'merged': true, 'rating': 'not a map', 'moved': [], 'dropped': 7},
        {
          'rating': {'before': 'x', 'after': null}
        },
      ]) {
        final result = adminMergeResultFromJson(
          doc,
          retainedUserId: _retainedId,
          sourceUserId: _sourceId,
        );

        expect(result.retainedUserId, _retainedId, reason: '$doc');
        expect(result.sourceUserId, _sourceId, reason: '$doc');
        expect(result.ratingBefore, isNull, reason: '$doc');
        expect(result.ratingAfter, isNull, reason: '$doc');
      }
    });

    test('the documents never carry a credential', () {
      const text = '$mergeChoicesDoc$mergeBlockedDoc$mergeCleanDoc'
          '$mergeResultDoc$mergeResultWithChoicesDoc';
      for (final secret in [
        'encrypted_password',
        'identity_data',
        'access_token',
        'refresh_token',
        'raw_user_meta_data',
        'password',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('a word the screen does not know is shown as it was sent', () {
      final l10n = AppLocalizationsEn();

      expect(AdminPreviewLabels.dropBlocker(l10n, 'GOALS'), 'scored goals');
      expect(AdminPreviewLabels.dropBlocker(l10n, 'SOMETHING_NEW'),
          'SOMETHING_NEW');
      expect(
          AdminPreviewLabels.finding(l10n, 'SOMETHING_NEW'), 'SOMETHING_NEW');
    });
  });

  // ---------------------------------------------------------------------------
  group('the repository', () {
    test('the same account twice is refused without asking the database',
        () async {
      final adapter = FakeAdminAdapter(mergeResult: _result());
      final repository = AdminRepository(adapter);

      await expectLater(
        repository.mergeAccounts(
          retainedUserId: 'u1',
          sourceUserId: 'u1',
          resolutions: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(adapter.calls, isEmpty);
    });

    test(
        'two different accounts are passed through with their choices, in '
        'order', () async {
      final adapter = FakeAdminAdapter(mergeResult: _result());
      final repository = AdminRepository(adapter);
      const choices = [
        AdminMergeResolution(matchId: 'm2', keep: AdminMergeKeep.source),
        AdminMergeResolution(matchId: 'm1', keep: AdminMergeKeep.retained),
      ];

      final result = await repository.mergeAccounts(
        retainedUserId: 'u1',
        sourceUserId: 'u2',
        resolutions: choices,
      );

      expect(result.retainedUserId, '00000000-0000-4000-8000-000000000002');
      expect(adapter.mergeRequests, hasLength(1));
      expect(adapter.mergeRequests.single.retainedUserId, 'u1');
      expect(adapter.mergeRequests.single.sourceUserId, 'u2');
      expect(adapter.mergeRequests.single.resolutions, choices);
    });

    test('a refusal reaches the caller as itself, never as a result', () async {
      final repository = AdminRepository(
          FakeAdminAdapter(mergeFailure: const ConflictFailure()));

      await expectLater(
        repository.mergeAccounts(
          retainedUserId: 'u1',
          sourceUserId: 'u2',
          resolutions: const [],
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('the merge screen', () {
    final retained = adminUser(id: _retainedId, name: 'Retained Rita');
    final source = adminUser(id: _sourceId, name: 'Source Sam');

    late FakeAdminAdapter adapter;

    Future<void> chooseSource(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('adminMergePick_$id')));
      await tester.pumpAndSettle();
    }

    Future<void> open(
      WidgetTester tester, {
      String doc = mergeCleanDoc,
      Failure? previewFailure,
      Failure? mergeFailure,
      AdminMergeResult? mergeResult,
      Completer<void>? gate,
      Locale locale = const Locale('en'),
      bool preview = true,
    }) async {
      adapter = FakeAdminAdapter(
        users: [retained, source, adminUser(id: 'u3', name: 'Third Player')],
        mergePreview: _merge(doc),
        previewFailure: previewFailure,
        mergeResult: mergeResult ?? _result(),
        mergeFailure: mergeFailure,
      )..mergeGate = gate;
      await pump(
        tester,
        AdminMergePreviewScreen(
          retained: retained,
          repository: AdminRepository(adapter),
        ),
        locale: locale,
      );
      if (preview) {
        await chooseSource(tester, _sourceId);
        await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
        await tester.pumpAndSettle();
      }
    }

    Finder executeButton() => find.byKey(const Key('adminMergeExecuteButton'));

    bool canExecute(WidgetTester tester) =>
        tester.widget<FilledButton>(executeButton()).onPressed != null;

    Finder choice(String matchId, String side) =>
        find.byKey(Key('adminMergeChoice_${matchId}_$side'));

    bool chipEnabled(WidgetTester tester, Finder chip) =>
        tester.widget<ChoiceChip>(chip).onSelected != null;

    bool chipSelected(WidgetTester tester, Finder chip) =>
        tester.widget<ChoiceChip>(chip).selected;

    Future<void> choose(
        WidgetTester tester, String matchId, String side) async {
      await tester.tap(choice(matchId, side));
      await tester.pumpAndSettle();
    }

    /// Opens the confirmation, types [name] and presses the confirming button.
    Future<void> confirm(WidgetTester tester,
        {String name = 'Source Sam', bool press = true}) async {
      await tester.tap(executeButton());
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), name);
      await tester.pump();
      if (press) {
        await tester.tap(find.byKey(const Key('adminMergeConfirmAction')));
      }
    }

    Future<void> chooseAll(WidgetTester tester) async {
      await choose(tester, _confirmedLineup, 'source');
      await choose(tester, _friendly, 'retained');
      await choose(tester, _played, 'source');
    }

    // ---- before anything is asked -------------------------------------------------------------
    testWidgets(
        'says up front that merging is permanent, and offers no merge '
        'until a preview has been read', (tester) async {
      await open(tester, preview: false);

      expect(find.text('Merge accounts'), findsOneWidget);
      expect(find.byKey(const Key('adminMergeNotice')), findsOneWidget);
      expect(find.textContaining('Merging is permanent'), findsOneWidget);
      expect(find.textContaining('deleted for good'), findsOneWidget);
      expect(executeButton(), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget,
          reason: 'only the button that previews');
      expect(adapter.calls, isEmpty, reason: 'nothing is read until asked');
    });

    testWidgets('the picker never offers the account already chosen',
        (tester) async {
      await open(tester, preview: false);

      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergePick_u1')), findsNothing);
      expect(find.byKey(const Key('adminMergePick_u2')), findsOneWidget);
      expect(find.byKey(const Key('adminMergePick_u3')), findsOneWidget);
    });

    // ---- what the merge will do -----------------------------------------------------------------
    testWidgets('shows what the merge will do, and only what it will do',
        (tester) async {
      await open(tester);

      expect(find.byKey(const Key('adminMergePlan')), findsOneWidget);
      expect(find.text('What the merge will do'), findsOneWidget);
      expect(find.text('Communities passed to the account to keep'),
          findsOneWidget);
      expect(find.text('Match registrations moved'), findsOneWidget);
      expect(find.text('Goal records moved'), findsOneWidget);
      expect(find.text('Team of the period awards moved'), findsOneWidget);
      expect(find.textContaining('Nobody else\'s rating or statistics change'),
          findsOneWidget);
    });

    testWidgets('a plan row that moves nothing is not shown', (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      expect(find.text('Duplicate memberships merged (the higher role stays)'),
          findsOneWidget);
      expect(find.text('Goal records moved'), findsNothing);
      expect(
          find.text('Communities passed to the account to keep'), findsNothing);
    });

    testWidgets('grades the findings, blockers first', (tester) async {
      await open(tester, doc: mergeBlockedDoc);

      for (final code in [
        'AUDIT_LOG_NAMES_SOURCE',
        'RETAINED_RATING_INCONSISTENT',
        'SOURCE_HAS_STORED_FILES',
        'TEAM_AWARD_COLLISION',
        'EVENT_LOGS_NAME_SOURCE',
      ]) {
        expect(find.byKey(Key('adminFinding_$code')), findsOneWidget,
            reason: code);
      }
      expect(find.text('Blocker'), findsNWidgets(4));
      expect(find.text('4 blockers found.'), findsOneWidget);
      expect(find.textContaining('still has a profile picture in storage'),
          findsOneWidget);
    });

    // ---- the choices ------------------------------------------------------------------------------
    testWidgets('lists every shared match with a choice for each side',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      expect(find.text('Matches both appear in'), findsOneWidget);
      expect(find.byKey(const Key('adminMergeChoiceHelp')), findsOneWidget);
      for (final id in [_confirmedLineup, _friendly, _played]) {
        expect(find.byKey(Key('adminSharedMatch_$id')), findsOneWidget);
        expect(choice(id, 'retained'), findsOneWidget);
        expect(choice(id, 'source'), findsOneWidget);
      }
      expect(find.text('Confirmed lineup'), findsOneWidget);
      expect(find.text('Played with a goal'), findsOneWidget);
      expect(find.text('Keep Retained Rita'), findsNWidgets(3));
      expect(find.text('Keep Source Sam'), findsNWidgets(3));
    });

    testWidgets('a side that cannot be removed is closed, with the reasons',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      // Source holds the confirmed lineup: keeping Rita would remove it.
      expect(
          chipEnabled(tester, choice(_confirmedLineup, 'retained')), isFalse);
      expect(chipEnabled(tester, choice(_confirmedLineup, 'source')), isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('adminSharedMatch_$_confirmedLineup')),
          matching: find.text(
              "Source Sam can't be removed here: is in a confirmed lineup"),
        ),
        findsOneWidget,
      );
      // Open on both sides: nothing explains because nothing is held.
      expect(chipEnabled(tester, choice(_friendly, 'retained')), isTrue);
      expect(chipEnabled(tester, choice(_friendly, 'source')), isTrue);
      expect(find.byKey(const Key('adminMergeHeld_${_friendly}_source')),
          findsNothing);
      // The played match: goals, MVP, the lineup a result came from, a rating.
      expect(chipEnabled(tester, choice(_played, 'retained')), isFalse);
      expect(
        find.text("Source Sam can't be removed here: scored goals, "
            "is the match's MVP, is in the lineup a result was recorded from, "
            'has a rating in effect from this match'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a closed side chooses nothing', (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      await tester.tap(choice(_played, 'retained'));
      await tester.pumpAndSettle();

      expect(chipSelected(tester, choice(_played, 'retained')), isFalse);
      expect(chipSelected(tester, choice(_played, 'source')), isFalse);
    });

    testWidgets(
        'the merge waits for a choice for every match, and says how '
        'many are missing', (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      expect(canExecute(tester), isFalse);
      expect(find.text('Choose which participation to keep in 3 matches.'),
          findsOneWidget);

      await choose(tester, _confirmedLineup, 'source');
      expect(canExecute(tester), isFalse);
      expect(find.text('Choose which participation to keep in 2 matches.'),
          findsOneWidget);

      await choose(tester, _friendly, 'retained');
      expect(canExecute(tester), isFalse);
      expect(find.text('Choose which participation to keep in 1 match.'),
          findsOneWidget);

      await choose(tester, _played, 'source');
      expect(canExecute(tester), isTrue);
      expect(find.byKey(const Key('adminMergeWhyNot')), findsNothing);
    });

    testWidgets('a choice can be changed, and only one side is chosen',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc);

      await choose(tester, _friendly, 'retained');
      expect(chipSelected(tester, choice(_friendly, 'retained')), isTrue);
      expect(chipSelected(tester, choice(_friendly, 'source')), isFalse);

      await choose(tester, _friendly, 'source');
      expect(chipSelected(tester, choice(_friendly, 'retained')), isFalse);
      expect(chipSelected(tester, choice(_friendly, 'source')), isTrue);
    });

    testWidgets('a match neither side can leave blocks the merge outright',
        (tester) async {
      await open(tester, doc: mergeUnresolvableDoc);
      const match = 'a5959613-38d9-4fe4-92e9-90a7eb1e56c5';

      expect(chipEnabled(tester, choice(match, 'retained')), isFalse);
      expect(chipEnabled(tester, choice(match, 'source')), isFalse);
      expect(find.byKey(const Key('adminFinding_SHARED_MATCH_NOT_RESOLVABLE')),
          findsOneWidget);
      expect(canExecute(tester), isFalse);
      expect(find.text('Resolve the blockers above first.'), findsOneWidget);
      expect(find.byKey(const Key('adminMergeHeld_${match}_source')),
          findsOneWidget);
      expect(find.byKey(const Key('adminMergeHeld_${match}_retained')),
          findsOneWidget);
    });

    testWidgets(
        'a blocker closes the merge even when nothing is left to '
        'choose', (tester) async {
      for (final doc in [mergeBlockedDoc, mergeSystemAdminDoc]) {
        await open(tester, doc: doc);

        expect(canExecute(tester), isFalse, reason: doc.substring(0, 20));
        expect(find.text('Resolve the blockers above first.'), findsOneWidget);

        await tester.tap(executeButton(), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('adminMergeConfirmDialog')), findsNothing);
        expect(adapter.mergeRequests, isEmpty);
      }
    });

    testWidgets('a pair with nothing to choose can be merged at once',
        (tester) async {
      await open(tester, doc: mergeEmptyDoc);

      expect(canExecute(tester), isTrue);
      expect(find.byKey(const Key('adminMergeWhyNot')), findsNothing);
      expect(find.text('Matches both appear in'), findsOneWidget);
    });

    // ---- the confirmation ----------------------------------------------------------------------------
    testWidgets(
        'the destructive action needs the name of the account that is '
        'deleted', (tester) async {
      await open(tester);

      await tester.tap(executeButton());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergeConfirmDialog')), findsOneWidget);
      expect(find.text('Merge permanently?'), findsOneWidget);
      expect(
        find.text('Source Sam will be deleted for good, including their '
            'sign-in. Their football record will be added to Retained Rita. '
            'This cannot be undone.'),
        findsOneWidget,
      );
      expect(find.text('Type the name of the account to delete: Source Sam'),
          findsOneWidget);

      bool confirmEnabled() =>
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('adminMergeConfirmAction')))
              .onPressed !=
          null;

      expect(confirmEnabled(), isFalse, reason: 'nothing typed');
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), 'Retained Rita');
      await tester.pump();
      expect(confirmEnabled(), isFalse,
          reason: 'the name of the account that is kept does not confirm');
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), 'Source Sa');
      await tester.pump();
      expect(confirmEnabled(), isFalse);
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), ' Source Sam ');
      await tester.pump();
      expect(confirmEnabled(), isTrue);
      expect(adapter.mergeRequests, isEmpty, reason: 'not before the press');
    });

    testWidgets('cancelling changes nothing and sends nothing', (tester) async {
      await open(tester);

      await confirm(tester, press: false);
      await tester.tap(find.byKey(const Key('adminMergeConfirmCancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergeConfirmDialog')), findsNothing);
      expect(adapter.mergeRequests, isEmpty);
      expect(
          adapter.calls.where((c) => c.startsWith('mergeAccounts')), isEmpty);
      expect(canExecute(tester), isTrue);
      expect(find.byKey(const Key('adminMergeDone')), findsNothing);
    });

    // ---- the merge --------------------------------------------------------------------------------------
    testWidgets(
        'one request with the two accounts and no choice when there is '
        'none to make', (tester) async {
      await open(tester);

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(adapter.mergeRequests, hasLength(1));
      expect(adapter.mergeRequests.single.retainedUserId, _retainedId);
      expect(adapter.mergeRequests.single.sourceUserId, _sourceId);
      expect(adapter.mergeRequests.single.resolutions, isEmpty);
    });

    testWidgets('two taps in one frame open one confirmation, and one request',
        (tester) async {
      await open(tester);

      // No frame between the taps. (The `_confirming` and `_merging` guards behind
      // this are defence in depth the widget harness cannot reach: it does not
      // deliver the second tap. What is asserted is what the administrator sees.)
      await tester.tap(executeButton());
      await tester.tap(executeButton(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergeConfirmDialog')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), 'Source Sam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminMergeConfirmAction')));
      await tester.pumpAndSettle();

      expect(adapter.mergeRequests, hasLength(1));
      expect(find.byKey(const Key('adminMergeDone')), findsOneWidget);
    });

    testWidgets(
        'one request, carrying exactly the choices made, in the order '
        'of the matches', (tester) async {
      await open(tester, doc: mergeChoicesDoc);
      await chooseAll(tester);

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(adapter.mergeRequests, hasLength(1));
      expect(
        adapter.mergeRequests.single.resolutions.map((r) => r.toJson()),
        [
          {'match_id': _confirmedLineup, 'keep': 'source'},
          {'match_id': _friendly, 'keep': 'retained'},
          {'match_id': _played, 'keep': 'source'},
        ],
      );
    });

    testWidgets(
        'while it runs nothing else can be done, and a second tap '
        'sends nothing', (tester) async {
      final gate = Completer<void>();
      await open(tester, gate: gate);

      await confirm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Merging…'), findsOneWidget);
      expect(canExecute(tester), isFalse);
      expect(adapter.mergeRequests, hasLength(1));
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('adminMergeSwap')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('adminMergePreviewButton')))
            .onPressed,
        isNull,
      );

      await tester.tap(executeButton(), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')),
          warnIfMissed: false);
      await tester.pump();
      expect(adapter.mergeRequests, hasLength(1));
      expect(find.byKey(const Key('adminMergePick_u3')), findsNothing,
          reason: 'the picker does not open mid-merge');

      gate.complete();
      await tester.pumpAndSettle();

      expect(adapter.mergeRequests, hasLength(1));
      expect(find.byKey(const Key('adminMergeDone')), findsOneWidget);
    });

    testWidgets('success says what happened, and offers nothing else to do',
        (tester) async {
      await open(tester);

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminMergeDone')), findsOneWidget);
      expect(find.text('Accounts merged'), findsOneWidget);
      expect(
        find.text('Source Sam was deleted. Their football record now belongs '
            'to Retained Rita.'),
        findsOneWidget,
      );
      expect(
        find.text("Retained Rita's rating was recalculated: 5.160 → 5.245."),
        findsOneWidget,
      );
      expect(executeButton(), findsNothing);
      expect(find.byKey(const Key('adminMergePreviewButton')), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(adapter.mergeRequests, hasLength(1));
    });

    testWidgets('a result without a rating still says the merge happened',
        (tester) async {
      await open(
        tester,
        mergeResult: const AdminMergeResult(
          retainedUserId: _retainedId,
          sourceUserId: _sourceId,
        ),
      );

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.text('Accounts merged'), findsOneWidget);
      expect(find.textContaining('rating was recalculated'), findsNothing);
    });

    testWidgets('Done answers with the account that survived', (tester) async {
      adapter = FakeAdminAdapter(
        users: [retained, source],
        mergePreview: _merge(mergeCleanDoc),
        mergeResult: _result(),
      );
      String? answer = 'not asked';
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () async {
                answer = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => AdminMergePreviewScreen(
                      retained: retained,
                      repository: AdminRepository(adapter),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('host')));
      await tester.pumpAndSettle();
      await chooseSource(tester, _sourceId);
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      await confirm(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adminMergeDoneButton')));
      await tester.pumpAndSettle();

      expect(answer, _retainedId);
    });

    testWidgets('leaving without merging answers with nothing', (tester) async {
      adapter = FakeAdminAdapter(
        users: [retained, source],
        mergePreview: _merge(mergeCleanDoc),
        mergeResult: _result(),
      );
      String? answer = 'not asked';
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () async {
                answer = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => AdminMergePreviewScreen(
                      retained: retained,
                      repository: AdminRepository(adapter),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('host')));
      await tester.pumpAndSettle();
      await chooseSource(tester, _sourceId);
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(answer, isNull);
      expect(adapter.mergeRequests, isEmpty);
    });

    // ---- what goes wrong ----------------------------------------------------------------------------------
    for (final entry in <(String, Failure, String)>[
      (
        'a conflict',
        const ConflictFailure(),
        'The merge was not performed. Something changed or is in the way. '
            'Review the preview again.'
      ),
      (
        'an account that is gone',
        const NotFoundFailure(),
        'One of the accounts no longer exists. If a merge just ran, the '
            'account to merge in is already gone.'
      ),
      (
        'a refusal of permission',
        const AuthorizationFailure(),
        'You are not allowed to merge these accounts.'
      ),
      (
        'a request the database did not accept',
        const ValidationFailure(),
        'The request was not accepted. Nothing was changed.'
      ),
    ]) {
      testWidgets('${entry.$1}: said as it is, with the preview to read again',
          (tester) async {
        await open(tester, mergeFailure: entry.$2);

        await confirm(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('adminMergeFailure')), findsOneWidget);
        expect(find.text(entry.$3), findsOneWidget);
        expect(find.byKey(const Key('adminMergeDone')), findsNothing);
        expect(find.text('Accounts merged'), findsNothing);
        expect(find.byKey(const Key('adminMergeCheckAgain')), findsOneWidget);
        expect(canExecute(tester), isFalse,
            reason: 'nothing more is offered until the preview is read again');
        expect(adapter.mergeRequests, hasLength(1));
      });
    }

    for (final entry in <(String, Failure)>[
      ('a dropped connection', const NetworkFailure()),
      ('a database error', const InfrastructureFailure()),
    ]) {
      testWidgets('${entry.$1}: never worded as "nothing happened"',
          (tester) async {
        await open(tester, mergeFailure: entry.$2);

        await confirm(tester);
        await tester.pumpAndSettle();

        expect(
          find.text('The merge may or may not have been performed. Check the '
              'preview before trying again: if it went through, the account to '
              'merge in no longer exists.'),
          findsOneWidget,
        );
        expect(find.textContaining('Nothing was changed'), findsNothing);
        expect(find.byKey(const Key('adminMergeDone')), findsNothing);
        expect(canExecute(tester), isFalse);
      });
    }

    testWidgets(
        'checking again reads the preview again and drops the failure '
        'and the choices', (tester) async {
      await open(tester,
          doc: mergeChoicesDoc, mergeFailure: const ConflictFailure());
      await chooseAll(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminMergeFailure')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adminMergeCheckAgain')));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.where((c) => c.startsWith('previewAccountMerge')),
        hasLength(2),
        reason: 'the preview is asked again for the same pair',
      );
      expect(find.byKey(const Key('adminMergeFailure')), findsNothing);
      expect(chipSelected(tester, choice(_friendly, 'retained')), isFalse,
          reason: 'choices made against the old answer are gone');
      expect(canExecute(tester), isFalse);
      expect(find.text('Choose which participation to keep in 3 matches.'),
          findsOneWidget);
    });

    testWidgets(
        'after a failure that did reach the database, checking again '
        'finds the account gone', (tester) async {
      await open(tester, mergeFailure: const NetworkFailure());
      await confirm(tester);
      await tester.pumpAndSettle();

      adapter.previewFailure = const NotFoundFailure();
      await tester.tap(find.byKey(const Key('adminMergeCheckAgain')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(executeButton(), findsNothing);
    });

    // ---- a different question ------------------------------------------------------------------------------
    testWidgets('swapping the accounts drops the answer and the choices',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc);
      await choose(tester, _friendly, 'retained');

      await tester.tap(find.byKey(const Key('adminMergeSwap')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminPreviewVerdict')), findsNothing);
      expect(executeButton(), findsNothing);
      final keep = find.descendant(
          of: find.byKey(const Key('adminMergeRetainedSlot')),
          matching: find.text('Source Sam'));
      expect(keep, findsOneWidget);

      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      expect(adapter.calls.last, 'previewAccountMerge:u2:u1');
      expect(chipSelected(tester, choice(_friendly, 'retained')), isFalse);
      expect(canExecute(tester), isFalse);
    });

    testWidgets('choosing a different account drops the answer',
        (tester) async {
      await open(tester);

      await chooseSource(tester, 'u3');

      expect(find.byKey(const Key('adminPreviewVerdict')), findsNothing);
      expect(executeButton(), findsNothing);
    });

    testWidgets('a failed read offers a retry, and no merge', (tester) async {
      await open(tester, previewFailure: const AuthorizationFailure());

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(find.byKey(const Key('adminMergeRetry')), findsOneWidget);
      expect(executeButton(), findsNothing);

      adapter.previewFailure = null;
      await tester.tap(find.byKey(const Key('adminMergeRetry')));
      await tester.pumpAndSettle();
      expect(executeButton(), findsOneWidget);
      expect(canExecute(tester), isTrue);
    });

    testWidgets('nothing is merged by reading, however many times',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc);
      await chooseAll(tester);

      expect(
          adapter.calls.where((c) => c.startsWith('mergeAccounts')), isEmpty);
      expect(adapter.mergeRequests, isEmpty);
    });

    // ---- in Arabic ---------------------------------------------------------------------------------------------
    testWidgets('it reads in Arabic, from the notice to the confirmation',
        (tester) async {
      await open(tester, doc: mergeChoicesDoc, locale: const Locale('ar'));

      expect(find.text('دمج الحسابات'), findsOneWidget);
      expect(find.textContaining('الدمج نهائي'), findsOneWidget);
      expect(find.text('ما الذي سيفعله الدمج'), findsOneWidget);
      expect(find.text('إبقاء Retained Rita'), findsNWidgets(3));
      expect(find.text('اختر المشاركة التي تُبقيها في 3 مباريات.'),
          findsOneWidget);
      expect(find.textContaining('لا يمكن إزالة مشاركة Source Sam هنا'),
          findsWidgets);

      await chooseAll(tester);
      expect(find.text('دمج الحسابين…'), findsOneWidget);
      await tester.tap(executeButton());
      await tester.pumpAndSettle();
      expect(find.text('هل تدمج نهائياً؟'), findsOneWidget);
      expect(find.text('ادمج نهائياً'), findsOneWidget);
    });

    testWidgets('and says that it is done in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.text('تم دمج الحسابين'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('from the account screen', () {
    Future<FakeAdminAdapter> openDetail(WidgetTester tester) async {
      final adapter = FakeAdminAdapter(
        users: [
          adminUser(id: _retainedId, name: 'Retained Rita'),
          adminUser(id: _sourceId, name: 'Source Sam'),
        ],
        activitySummary: seenActivitySummary,
        accountResult: adminAccount(id: _retainedId, fullName: 'Retained Rita'),
        signedInUserId: 'admin-1',
        mergePreview: _merge(mergeCleanDoc),
        mergeResult: const AdminMergeResult(
          retainedUserId: _retainedId,
          sourceUserId: _sourceId,
        ),
      );
      await pump(
        tester,
        Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminUserDetailScreen(
                    userId: _retainedId,
                    repository: AdminRepository(adapter),
                    wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          );
        }),
      );
      await tester.tap(find.byKey(const Key('host')));
      await tester.pumpAndSettle();
      return adapter;
    }

    Future<void> mergeFromDetail(WidgetTester tester,
        {bool swap = false}) async {
      await tester
          .ensureVisible(find.byKey(const Key('adminAccountPreviewMerge')));
      await tester.tap(find.byKey(const Key('adminAccountPreviewMerge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergeSourceSlot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergePick_$_sourceId')));
      await tester.pumpAndSettle();
      if (swap) {
        await tester.tap(find.byKey(const Key('adminMergeSwap')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('adminMergePreviewButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergeExecuteButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('adminMergeConfirmField')), 'Source Sam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminMergeConfirmAction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminMergeDoneButton')));
      await tester.pumpAndSettle();
    }

    testWidgets('the account that was kept is read again after the merge',
        (tester) async {
      final adapter = await openDetail(tester);
      final reads = adapter.calls
          .where((c) => c == 'userActivitySummary:$_retainedId')
          .length;

      await mergeFromDetail(tester);

      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
      expect(
        adapter.calls.where((c) => c == 'userActivitySummary:$_retainedId'),
        hasLength(reads + 1),
      );
    });

    testWidgets('an account that was merged away leaves its own screen',
        (tester) async {
      final adapter = await openDetail(tester);
      adapter.mergeResult = const AdminMergeResult(
        retainedUserId: _sourceId,
        sourceUserId: _retainedId,
      );

      await mergeFromDetail(tester, swap: true);

      expect(find.byType(AdminUserDetailScreen), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
      expect(adapter.mergeRequests.single.retainedUserId, _sourceId);
      expect(adapter.mergeRequests.single.sourceUserId, _retainedId);
    });
  });
}
