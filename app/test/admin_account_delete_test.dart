import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_deletion_preview_screen.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_preview_widgets.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';
import 'package:go_play/l10n/generated/app_localizations_en.dart';

import 'account_deletion_fixtures.dart';
import 'admin_fakes.dart';
import 'wilayat_fixtures.dart';

/// Deleting an account for good, as an administrator (migration 0102): what the mapper reads,
/// what the repository passes on, and what the deletion screen lets the administrator do with
/// it. Whether the deletion is CORRECT is the database's to prove and is proved by the offline
/// SQL runs; these tests prove that the screen offers it only when it should, asks for what it
/// should, sends exactly one request, and tells the truth about what happened.
const _userId = 'u2';

Map<String, dynamic> _doc(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

AdminDeletionPreview _preview(String json) =>
    adminDeletionPreviewFromJson(_doc(json));

AdminDeletionResult _result() => adminDeletionResultFromJson(
      _doc(deleteResultDoc),
      userId: _userId,
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
    test('an account that owns a community: one blocker, and what to hand over',
        () {
      final preview = _preview(deleteBlockedDoc);

      expect(preview.hasBlockers, isTrue);
      expect(
        preview.findingsOf(AdminFindingSeverity.blocker).map((f) => f.code),
        ['OWNS_COMMUNITIES'],
      );
      expect(preview.ownedCommunities.items.map((c) => c.name), ['Beta']);
      expect(preview.account.fullName, 'Source Sam');
    });

    test('nothing in the way: what is withdrawn, kept and told', () {
      final preview = _preview(deleteClearDoc);

      expect(preview.hasBlockers, isFalse);
      expect(preview.findingsOf(AdminFindingSeverity.blocker), isEmpty);
      expect(
        preview.findingsOf(AdminFindingSeverity.conflict).map((f) => f.code),
        ['UPCOMING_REGISTRATIONS'],
        reason: 'withdrawing from a match to come is told, not blocking',
      );
      expect(
        preview.findingsOf(AdminFindingSeverity.constraint).map((f) => f.code),
        containsAll([
          'HISTORY_KEPT',
          'CREATED_MATCHES_KEPT',
          'RATING_ARCHIVE_KEPT',
          'AUDIT_LOG_REDACTED',
          'STORED_FILES_REMOVED',
        ]),
      );
    });

    test('football history is KEPT, memberships and matches to come REMOVED',
        () {
      final treatment = {
        for (final r in _preview(deleteClearDoc).historicalRecords)
          r.code: r.treatment,
      };

      for (final kept in [
        'MATCH_REGISTRATIONS',
        'LINEUP_ASSIGNMENTS',
        'GOAL_RECORDS',
        'MVP_RESULTS',
        'RATING_HISTORY',
        'RECORDED_RESULTS',
        'PLAYER_STATISTICS',
      ]) {
        expect(treatment[kept], 'KEPT', reason: kept);
      }
      for (final removed in [
        'COMMUNITY_MEMBERSHIPS',
        'UPCOMING_REGISTRATIONS',
        'UPCOMING_LINEUP_PLACES',
      ]) {
        expect(treatment[removed], 'REMOVED', reason: removed);
      }
      expect(treatment.values, isNot(contains('CASCADE_DELETE')),
          reason: 'nothing is erased with the account any more');
    });

    test('another System Admin is the one blocker', () {
      final preview = _preview(deleteSystemAdminDoc);

      expect(preview.hasBlockers, isTrue);
      expect(preview.findings.map((f) => f.code), ['TARGET_IS_SYSTEM_ADMIN']);
    });

    test('the request names the account, and only the account', () {
      expect(adminDeleteAccountParams('abc'), {'p_user_id': 'abc'});
    });

    test('the result: what was withdrawn, removed and redacted', () {
      final result = _result();

      expect(result.userId, '00000000-0000-4000-8000-000000000003');
      expect(result.withdrawnRegistrations, 2);
      expect(result.withdrawnLineupPlaces, 1);
      expect(result.membershipsRemoved, 3);
      expect(result.auditEntriesRedacted, 1);
      expect(result.avatarFilesRemoved, 0);
    });

    test('a result this build cannot read is still a deletion that happened',
        () {
      for (final doc in [
        <String, dynamic>{},
        {'withdrawn': 7, 'memberships_removed': 'many', 'user_id': 4},
        {
          'withdrawn': {'registrations': 'x', 'lineup_places': null},
          'audit_entries_redacted': [],
        },
      ]) {
        final result = adminDeletionResultFromJson(doc, userId: _userId);

        expect(result.userId, _userId, reason: '$doc');
        expect(result.withdrawnRegistrations, 0, reason: '$doc');
        expect(result.membershipsRemoved, 0, reason: '$doc');
        expect(result.auditEntriesRedacted, 0, reason: '$doc');
      }
    });

    test('every new finding code and treatment has a sentence of its own', () {
      final l10n = AppLocalizationsEn();

      for (final code in [
        'HISTORY_KEPT',
        'CREATED_MATCHES_KEPT',
        'RATING_ARCHIVE_KEPT',
        'AUDIT_LOG_REDACTED',
        'STORED_FILES_REMOVED',
      ]) {
        expect(AdminPreviewLabels.finding(l10n, code), isNot(code),
            reason: code);
      }
      expect(AdminPreviewLabels.treatment(l10n, 'KEPT'),
          'Kept, shown as Deleted Player');
      expect(AdminPreviewLabels.treatment(l10n, 'REMOVED'), 'Removed');
      expect(AdminPreviewLabels.history(l10n, 'UPCOMING_LINEUP_PLACES'),
          isNot('UPCOMING_LINEUP_PLACES'));
    });
  });

  // ---------------------------------------------------------------------------
  group('the repository', () {
    test('the account is passed through, once', () async {
      final adapter = FakeAdminAdapter(deleteResult: _result());

      final result = await AdminRepository(adapter).deleteAccount(_userId);

      expect(result.membershipsRemoved, 3);
      expect(adapter.deleteRequests, [_userId]);
    });

    test('a refusal reaches the caller as itself, never as a result', () async {
      final repository = AdminRepository(
          FakeAdminAdapter(deleteFailure: const ConflictFailure()));

      await expectLater(
          repository.deleteAccount(_userId), throwsA(isA<ConflictFailure>()));
    });
  });

  // ---------------------------------------------------------------------------
  group('the deletion screen', () {
    late FakeAdminAdapter adapter;

    Future<void> open(
      WidgetTester tester, {
      String doc = deleteClearDoc,
      Failure? deleteFailure,
      Failure? previewFailure,
      Completer<void>? gate,
      Locale locale = const Locale('en'),
    }) async {
      adapter = FakeAdminAdapter(
        deletionPreview: _preview(doc),
        previewFailure: previewFailure,
        deleteResult: _result(),
        deleteFailure: deleteFailure,
      )..deleteGate = gate;
      await pump(
        tester,
        AdminDeletionPreviewScreen(
          userId: _userId,
          repository: AdminRepository(adapter),
        ),
        locale: locale,
      );
    }

    Finder executeButton() => find.byKey(const Key('adminDeleteExecuteButton'));

    bool canDelete(WidgetTester tester) =>
        tester.widget<FilledButton>(executeButton()).onPressed != null;

    /// Opens the confirmation, types [name] and presses the confirming button.
    Future<void> confirm(WidgetTester tester,
        {String name = 'Source Sam', bool press = true}) async {
      await tester.tap(executeButton());
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), name);
      await tester.pump();
      if (press) {
        await tester.tap(find.byKey(const Key('adminDeleteConfirmAction')));
      }
    }

    // ---- before anything is asked ------------------------------------------------------------
    testWidgets('says up front that deleting is permanent', (tester) async {
      await open(tester);

      expect(find.text('Delete account'), findsOneWidget);
      expect(find.byKey(const Key('adminDeleteNotice')), findsOneWidget);
      expect(find.textContaining('Deleting is permanent'), findsOneWidget);
      expect(find.textContaining('shown as Deleted Player'), findsWidgets);
      expect(adapter.deleteRequests, isEmpty);
    });

    testWidgets('a failed read offers a retry, and no deletion',
        (tester) async {
      await open(tester, previewFailure: const AuthorizationFailure());

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(executeButton(), findsNothing);
    });

    // ---- what the deletion will do ---------------------------------------------------------
    testWidgets('tells what is kept, removed and redacted', (tester) async {
      await open(tester);

      expect(
          find.byKey(const Key('adminFinding_HISTORY_KEPT')), findsOneWidget);
      expect(find.byKey(const Key('adminFinding_AUDIT_LOG_REDACTED')),
          findsOneWidget);
      expect(find.byKey(const Key('adminFinding_STORED_FILES_REMOVED')),
          findsOneWidget);
      expect(find.text('Kept, shown as Deleted Player'), findsWidgets);
      expect(find.text('Removed'), findsWidgets);
      expect(
        find.text('The football history of matches played is kept and shown as '
            'Deleted Player'),
        findsOneWidget,
      );
    });

    // ---- the gate ---------------------------------------------------------------------------
    testWidgets('ownership closes the control and says why', (tester) async {
      await open(tester, doc: deleteBlockedDoc);

      expect(find.byKey(const Key('adminFinding_OWNS_COMMUNITIES')),
          findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(canDelete(tester), isFalse);
      expect(find.text('Resolve the blockers above first.'), findsOneWidget);

      await tester.tap(executeButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminDeleteConfirmDialog')), findsNothing);
      expect(adapter.deleteRequests, isEmpty);
    });

    testWidgets('a System Admin closes it too', (tester) async {
      await open(tester, doc: deleteSystemAdminDoc);

      expect(canDelete(tester), isFalse);
      expect(find.byKey(const Key('adminFinding_TARGET_IS_SYSTEM_ADMIN')),
          findsOneWidget);
    });

    testWidgets('nothing in the way opens it', (tester) async {
      await open(tester);

      expect(canDelete(tester), isTrue);
      expect(find.byKey(const Key('adminDeleteWhyNot')), findsNothing);
    });

    // ---- the confirmation ---------------------------------------------------------------------
    testWidgets('the name of the account has to be typed', (tester) async {
      await open(tester);

      await tester.tap(executeButton());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminDeleteConfirmDialog')), findsOneWidget);
      expect(find.text('Delete permanently?'), findsOneWidget);
      expect(
        find.text('Source Sam will be deleted for good, including their '
            'sign-in and profile picture. Their football history stays and is '
            'shown as Deleted Player. This cannot be undone.'),
        findsOneWidget,
      );
      expect(find.text('Type the name of the account to delete: Source Sam'),
          findsOneWidget);

      bool confirmEnabled() =>
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('adminDeleteConfirmAction')))
              .onPressed !=
          null;

      expect(confirmEnabled(), isFalse, reason: 'nothing typed');
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), 'Source');
      await tester.pump();
      expect(confirmEnabled(), isFalse);
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), ' Source Sam ');
      await tester.pump();
      expect(confirmEnabled(), isTrue);
      expect(adapter.deleteRequests, isEmpty, reason: 'not before the press');
    });

    testWidgets('cancelling changes nothing and sends nothing', (tester) async {
      await open(tester);

      await confirm(tester, press: false);
      await tester.tap(find.byKey(const Key('adminDeleteConfirmCancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminDeleteConfirmDialog')), findsNothing);
      expect(adapter.deleteRequests, isEmpty);
      expect(canDelete(tester), isTrue);
    });

    testWidgets('two taps in one frame open one confirmation, and one request',
        (tester) async {
      await open(tester);

      await tester.tap(executeButton());
      await tester.tap(executeButton(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminDeleteConfirmDialog')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), 'Source Sam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminDeleteConfirmAction')));
      await tester.pumpAndSettle();

      expect(adapter.deleteRequests, [_userId]);
    });

    // ---- the deletion -------------------------------------------------------------------------
    testWidgets('one request, for the account on the screen', (tester) async {
      await open(tester);

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(adapter.deleteRequests, [_userId]);
    });

    testWidgets('while it runs nothing else can be done', (tester) async {
      final gate = Completer<void>();
      await open(tester, gate: gate);

      await confirm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Deleting…'), findsOneWidget);
      expect(canDelete(tester), isFalse);
      await tester.tap(executeButton(), warnIfMissed: false);
      await tester.pump();
      expect(adapter.deleteRequests, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();

      expect(adapter.deleteRequests, hasLength(1));
      expect(find.byKey(const Key('adminDeleteDone')), findsOneWidget);
    });

    testWidgets('success says what happened, and offers nothing else to do',
        (tester) async {
      await open(tester);

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.text('Account deleted'), findsOneWidget);
      expect(
        find.text('Source Sam was deleted. Their football history stays and is '
            'shown as Deleted Player.'),
        findsOneWidget,
      );
      expect(executeButton(), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('Done answers true, so the screens behind it leave too',
        (tester) async {
      adapter = FakeAdminAdapter(
          deletionPreview: _preview(deleteClearDoc), deleteResult: _result());
      bool? answer;
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () async {
                answer = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => AdminDeletionPreviewScreen(
                      userId: _userId,
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
      await confirm(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adminDeleteDoneButton')));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
    });

    // ---- what goes wrong ------------------------------------------------------------------------
    for (final entry in <(String, Failure, String)>[
      (
        'a conflict',
        const ConflictFailure(),
        'The account was not deleted. Something changed or is in the way. '
            'Review the preview again.'
      ),
      (
        'an account that is gone',
        const NotFoundFailure(),
        'The account no longer exists. If a deletion just ran, it is already '
            'gone.'
      ),
      (
        'a refusal of permission',
        const AuthorizationFailure(),
        'You are not allowed to delete this account.'
      ),
      (
        'a request the database did not accept',
        const ValidationFailure(),
        'The request was not accepted. Nothing was changed.'
      ),
      (
        'the picture could not be removed, so no deletion was attempted',
        const InfrastructureFailure(FailureReason.avatarCleanupFailed),
        'The account was not deleted. Its profile picture could not be '
            'removed, so nothing else was changed. Try again.'
      ),
      (
        'the database refused after the picture was removed',
        const ConflictFailure(FailureReason.avatarRemovedFirst),
        'The account was not deleted. Something changed or is in the way. '
            'Review the preview again. The account\'s profile picture had '
            'already been removed.'
      ),
      (
        'the answer was lost',
        const NetworkFailure(),
        'The deletion may or may not have been performed. Check the preview '
            'before trying again: if it went through, the account no longer '
            'exists.'
      ),
      (
        'the answer was lost after the picture was removed',
        const InfrastructureFailure(FailureReason.avatarRemovedFirst),
        'The deletion may or may not have been performed. Check the preview '
            'before trying again: if it went through, the account no longer '
            'exists. The account\'s profile picture had already been removed.'
      ),
    ]) {
      testWidgets('${entry.$1}: said exactly, with nothing more to press',
          (tester) async {
        await open(tester, deleteFailure: entry.$2);

        await confirm(tester);
        await tester.pumpAndSettle();

        expect(find.text(entry.$3), findsOneWidget);
        expect(find.byKey(const Key('adminDeleteDone')), findsNothing);
        expect(find.byKey(const Key('adminDeleteCheckAgain')), findsOneWidget);
        expect(canDelete(tester), isFalse,
            reason: 'nothing more is offered until the preview is read again');
        expect(adapter.deleteRequests, hasLength(1));
      });
    }

    testWidgets('a failed cleanup never claims the deletion may have happened',
        (tester) async {
      await open(
        tester,
        deleteFailure:
            const InfrastructureFailure(FailureReason.avatarCleanupFailed),
      );

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('may or may not'), findsNothing);
    });

    testWidgets('checking again reads the preview again and drops the failure',
        (tester) async {
      await open(tester, deleteFailure: const ConflictFailure());
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminDeleteFailure')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adminDeleteCheckAgain')));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.where((c) => c.startsWith('previewAccountDeletion')),
        hasLength(2),
      );
      expect(find.byKey(const Key('adminDeleteFailure')), findsNothing);
      expect(canDelete(tester), isTrue);
    });

    // ---- in Arabic -------------------------------------------------------------------------------
    testWidgets('it reads in Arabic, from the notice to the confirmation',
        (tester) async {
      await open(tester, locale: const Locale('ar'));

      expect(find.text('حذف حساب'), findsOneWidget);
      expect(find.textContaining('الحذف نهائي'), findsOneWidget);
      expect(find.text('حذف الحساب…'), findsOneWidget);
      await tester.tap(executeButton());
      await tester.pumpAndSettle();
      expect(find.text('هل تحذف نهائياً؟'), findsOneWidget);
      expect(find.text('احذف نهائياً'), findsOneWidget);
    });

    testWidgets('and says that it is done in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));

      await tester.tap(executeButton());
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), 'Source Sam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminDeleteConfirmAction')));
      await tester.pumpAndSettle();

      expect(find.text('تم حذف الحساب'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('from the account screen', () {
    testWidgets('a deleted account takes its own screen with it',
        (tester) async {
      final adapter = FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountResult: adminAccount(id: 'u1', fullName: 'Account Holder'),
        signedInUserId: 'admin-1',
        deletionPreview: _preview(deleteClearDoc),
        deleteResult: _result(),
      );
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminUserDetailScreen(
                    userId: 'u1',
                    repository: AdminRepository(adapter),
                    wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('host')));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.tap(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminDeleteExecuteButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('adminDeleteConfirmField')), 'Source Sam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('adminDeleteConfirmAction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adminDeleteDoneButton')));
      await tester.pumpAndSettle();

      expect(adapter.deleteRequests, ['u1']);
      expect(find.byType(AdminUserDetailScreen), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
    });

    testWidgets('leaving the deletion screen without deleting keeps it',
        (tester) async {
      final adapter = FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountResult: adminAccount(id: 'u1', fullName: 'Account Holder'),
        signedInUserId: 'admin-1',
        deletionPreview: _preview(deleteClearDoc),
        deleteResult: _result(),
      );
      await pump(
        tester,
        AdminUserDetailScreen(
          userId: 'u1',
          repository: AdminRepository(adapter),
          wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
        ),
      );
      await tester
          .ensureVisible(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.tap(find.byKey(const Key('adminAccountPreviewDeletion')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(AdminUserDetailScreen), findsOneWidget);
      expect(adapter.deleteRequests, isEmpty);
    });
  });
}
