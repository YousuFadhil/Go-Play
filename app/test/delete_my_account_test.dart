import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/settings/account_deletion_adapter.dart';
import 'package:go_play/features/settings/account_deletion_models.dart';
import 'package:go_play/features/settings/account_deletion_repository.dart';
import 'package:go_play/features/settings/delete_account_screen.dart';
import 'package:go_play/features/settings/settings_screen.dart';
import 'package:go_play/infrastructure/supabase/mappers/account_deletion_mapper.dart';

import 'account_deletion_fixtures.dart';

/// Deleting your own account (migration 0102): what the mapper reads from the database's
/// answer, and what the Settings flow lets a person do with it. Whether the deletion is
/// CORRECT is the database's to prove and is proved by the offline SQL runs; these tests
/// prove that the screen offers it only when it should, hands the person to the existing
/// ownership transfer, asks for the word, sends one request, and ends the session only after
/// the account is really gone.
MyAccountDeletionPreview _preview(String json) =>
    myAccountDeletionPreviewFromJson(jsonDecode(json) as Map<String, dynamic>);

class _FakeAdapter implements AccountDeletionAdapter {
  _FakeAdapter(this.previews, {this.deleteFailure, this.previewFailure});

  /// The answers to successive questions; the last one repeats.
  final List<MyAccountDeletionPreview> previews;
  Failure? deleteFailure;
  Failure? previewFailure;
  Completer<void>? gate;
  final List<String> calls = [];
  int _asked = 0;

  @override
  Future<MyAccountDeletionPreview> previewMyDeletion() async {
    calls.add('preview');
    if (previewFailure != null) throw previewFailure!;
    final index = _asked < previews.length ? _asked : previews.length - 1;
    _asked++;
    return previews[index];
  }

  @override
  Future<void> deleteMyAccount() async {
    calls.add('delete');
    final g = gate;
    if (g != null) await g.future;
    if (deleteFailure != null) throw deleteFailure!;
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 5000);
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
    test('while the user owns a community: the blocker and what to hand over',
        () {
      final preview = _preview(myBlockedDoc);

      expect(preview.hasBlockers, isTrue);
      expect(preview.blockers, {'OWNS_COMMUNITIES'});
      expect(preview.ownsCommunities, isTrue);
      expect(preview.ownedTotal, 1);
      expect(preview.ownedCommunities.single.name, 'Beta');
      expect(preview.ownedCommunities.single.memberCount, 3);
      expect(preview.ownedCommunities.single.id, isNotEmpty);
      expect(preview.upcomingRegistrations, 2);
    });

    test('nothing in the way', () {
      final preview = _preview(myClearDoc);

      expect(preview.hasBlockers, isFalse);
      expect(preview.blockers, isEmpty);
      expect(preview.ownedCommunities, isEmpty);
      expect(preview.upcomingRegistrations, 2);
    });

    test('a System Admin and a suspended account are told apart', () {
      expect(_preview(mySystemAdminDoc).isSystemAdmin, isTrue);
      expect(_preview(mySystemAdminDoc).hasBlockers, isTrue);
      expect(_preview(mySuspendedDoc).isSuspended, isTrue);
      expect(_preview(mySuspendedDoc).hasBlockers, isTrue);
      expect(_preview(myEmptyDoc).hasBlockers, isFalse);
      expect(_preview(myEmptyDoc).upcomingRegistrations, 0);
    });

    test('a document this build cannot read is BLOCKED, never clear', () {
      for (final doc in [
        <String, dynamic>{},
        {'has_blockers': 'false'},
        {'has_blockers': null, 'findings': 7},
        // an explicit "no" that a blocker finding contradicts
        {
          'has_blockers': false,
          'findings': [
            {'code': 'OWNS_COMMUNITIES', 'severity': 'BLOCKER', 'count': 1}
          ],
        },
      ]) {
        expect(myAccountDeletionPreviewFromJson(doc).hasBlockers, isTrue,
            reason: '$doc');
      }
    });

    test('rows that are not communities are skipped, not fatal', () {
      final preview = myAccountDeletionPreviewFromJson({
        'has_blockers': true,
        'findings': [
          {'code': 'OWNS_COMMUNITIES', 'severity': 'BLOCKER'}
        ],
        'owned_communities': {
          'total': 'two',
          'items': [
            7,
            {'name': 'No id'},
            {'community_id': 'c1', 'name': 'Good', 'member_count': 'x'},
          ],
        },
      });

      expect(preview.ownedCommunities.map((c) => c.id), ['c1']);
      expect(preview.ownedCommunities.single.memberCount, 0);
      expect(preview.ownedTotal, 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('the repository', () {
    test('the question and the deletion are passed through, nothing added',
        () async {
      final adapter = _FakeAdapter([_preview(myClearDoc)]);
      final repository = AccountDeletionRepository(adapter);

      expect((await repository.previewMyDeletion()).hasBlockers, isFalse);
      await repository.deleteMyAccount();

      expect(adapter.calls, ['preview', 'delete']);
    });

    test('a refusal reaches the caller as itself', () async {
      final adapter = _FakeAdapter([_preview(myClearDoc)],
          deleteFailure: const ConflictFailure());

      await expectLater(AccountDeletionRepository(adapter).deleteMyAccount(),
          throwsA(isA<ConflictFailure>()));
    });
  });

  // ---------------------------------------------------------------------------
  group('the delete-my-account screen', () {
    late _FakeAdapter adapter;
    late List<String> events;
    late List<String> opened;

    Future<void> open(
      WidgetTester tester,
      List<MyAccountDeletionPreview> previews, {
      Failure? deleteFailure,
      Failure? previewFailure,
      Completer<void>? gate,
      Locale locale = const Locale('en'),
      Future<void> Function()? signOut,
    }) async {
      events = [];
      opened = [];
      adapter = _FakeAdapter(previews,
          deleteFailure: deleteFailure, previewFailure: previewFailure)
        ..gate = gate;
      await pump(
        tester,
        DeleteAccountScreen(
          repository: AccountDeletionRepository(adapter),
          onSignOut: signOut ??
              () async {
                events.add('signOut');
              },
          onOpenCommunity: (context, community) async {
            opened.add(community.id);
          },
        ),
        locale: locale,
      );
    }

    Finder deleteButton() => find.byKey(const Key('deleteAccountButton'));

    bool canDelete(WidgetTester tester) =>
        tester.widget<FilledButton>(deleteButton()).onPressed != null;

    Future<void> confirm(WidgetTester tester,
        {String word = 'DELETE', bool press = true}) async {
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), word);
      await tester.pump();
      if (press) {
        await tester.tap(find.byKey(const Key('deleteAccountConfirmAction')));
      }
    }

    // ---- before anything is asked -----------------------------------------------------------
    testWidgets('says what deleting means, before anything is chosen',
        (tester) async {
      await open(tester, [_preview(myClearDoc)]);

      expect(find.text('Delete my account'), findsOneWidget);
      expect(find.byKey(const Key('deleteAccountIntro')), findsOneWidget);
      expect(find.textContaining('Deleting your account is permanent'),
          findsOneWidget);
      expect(find.textContaining('shown as Deleted Player'), findsOneWidget);
      expect(adapter.calls, ['preview'],
          reason: 'nothing is deleted by reading');
    });

    testWidgets('a failed read offers a retry, and no deletion',
        (tester) async {
      await open(tester, [_preview(myClearDoc)],
          previewFailure: const NetworkFailure());

      expect(find.text('Failed to load data.'), findsOneWidget);
      expect(deleteButton(), findsNothing);
    });

    testWidgets(
        'nothing in the way: the button is open and matches to come '
        'are mentioned', (tester) async {
      await open(tester, [_preview(myClearDoc)]);

      expect(canDelete(tester), isTrue);
      expect(find.byKey(const Key('deleteAccountOwnsBody')), findsNothing);
      expect(find.text('You will be withdrawn from 2 upcoming matches.'),
          findsOneWidget);
    });

    // ---- ownership ---------------------------------------------------------------------------
    testWidgets(
        'owning a community blocks, names it, and offers the existing '
        'transfer', (tester) async {
      await open(tester, [_preview(myBlockedDoc), _preview(myClearDoc)]);
      final community = _preview(myBlockedDoc).ownedCommunities.single;

      expect(canDelete(tester), isFalse);
      expect(find.text('You own communities'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(
        find.text('Transfer ownership of each community below to another '
            'member first. Then you can delete your account.'),
        findsOneWidget,
      );
      await tester.tap(deleteButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteAccountConfirmDialog')), findsNothing);

      await tester.tap(find.text('Manage members'));
      await tester.pumpAndSettle();

      expect(opened, [community.id],
          reason: 'the screen where ownership moves');
      expect(adapter.calls, ['preview', 'preview'],
          reason: 'coming back asks the question again');
      expect(canDelete(tester), isTrue,
          reason: 'ownership moved, so nothing blocks any more');
      expect(find.text('You own communities'), findsNothing);
    });

    testWidgets('a System Admin is told, and cannot go on', (tester) async {
      await open(tester, [_preview(mySystemAdminDoc)]);

      expect(canDelete(tester), isFalse);
      expect(find.text('System Admin accounts cannot be deleted from the app.'),
          findsOneWidget);
    });

    testWidgets('a suspended account is told, and cannot go on',
        (tester) async {
      await open(tester, [_preview(mySuspendedDoc)]);

      expect(canDelete(tester), isFalse);
      expect(
          find.text('A suspended account cannot be deleted.'), findsOneWidget);
    });

    // ---- the confirmation ----------------------------------------------------------------------
    testWidgets('a word has to be typed, in the language of the app',
        (tester) async {
      await open(tester, [_preview(myClearDoc)]);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(find.text('Delete your account permanently?'), findsOneWidget);
      expect(
        find.text('This cannot be undone. Your account, profile and picture '
            'will be deleted and you will be signed out.'),
        findsOneWidget,
      );
      bool enabled() =>
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('deleteAccountConfirmAction')))
              .onPressed !=
          null;
      expect(enabled(), isFalse, reason: 'nothing typed');
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), 'DELET');
      await tester.pump();
      expect(enabled(), isFalse);
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), ' delete ');
      await tester.pump();
      expect(enabled(), isTrue, reason: 'case and spaces do not matter');
      expect(adapter.calls, ['preview'], reason: 'not before the press');
    });

    testWidgets('cancelling changes nothing and sends nothing', (tester) async {
      await open(tester, [_preview(myClearDoc)]);

      await confirm(tester, press: false);
      await tester.tap(find.byKey(const Key('deleteAccountConfirmCancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deleteAccountConfirmDialog')), findsNothing);
      expect(adapter.calls, ['preview']);
      expect(events, isEmpty);
      expect(canDelete(tester), isTrue);
    });

    testWidgets('two taps in one frame open one confirmation, and one request',
        (tester) async {
      await open(tester, [_preview(myClearDoc)]);

      await tester.tap(deleteButton());
      await tester.tap(deleteButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('deleteAccountConfirmDialog')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), 'DELETE');
      await tester.pump();
      await tester.tap(find.byKey(const Key('deleteAccountConfirmAction')));
      await tester.pumpAndSettle();

      expect(adapter.calls.where((c) => c == 'delete'), hasLength(1));
    });

    // ---- the deletion, and the session --------------------------------------------------------
    testWidgets(
        'success: one request, then the session ends, then the app '
        'goes back to its first screen', (tester) async {
      adapter = _FakeAdapter([_preview(myClearDoc)]);
      events = [];
      adapter.calls.clear();
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('host'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeleteAccountScreen(
                    repository: AccountDeletionRepository(adapter),
                    onSignOut: () async {
                      events.add('signOut:after:${adapter.calls.join(",")}');
                    },
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

      await confirm(tester);
      await tester.pumpAndSettle();

      expect(adapter.calls.where((c) => c == 'delete'), hasLength(1));
      expect(events, ['signOut:after:preview,delete'],
          reason: 'the session ends only after the account is really gone');
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(find.byKey(const Key('host')), findsOneWidget);
    });

    testWidgets(
        'a sign-out that cannot reach the server does not undo or hide the '
        'deletion', (tester) async {
      await open(tester, [_preview(myClearDoc)],
          signOut: () async => throw const NetworkFailure());

      await confirm(tester);
      await tester.pumpAndSettle();

      // The account is gone and the screen says so; nothing was thrown.
      expect(find.byKey(const Key('deleteAccountDone')), findsOneWidget);
      expect(find.text('Your account was deleted'), findsOneWidget);
      expect(find.byKey(const Key('deleteAccountFailure')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('success says so at once, before the session has ended',
        (tester) async {
      final gate = Completer<void>();
      await open(tester, [_preview(myClearDoc)], signOut: () => gate.future);

      await confirm(tester);
      await tester.pump();
      await tester.pump();

      expect(find.text('Your account was deleted'), findsOneWidget);
      expect(
        find.text('You have been signed out. The matches you played stay in '
            'their communities, shown as Deleted Player.'),
        findsOneWidget,
      );
      expect(deleteButton(), findsNothing, reason: 'nothing left to press');
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('while it runs nothing else can be done', (tester) async {
      final gate = Completer<void>();
      await open(tester, [_preview(myClearDoc)], gate: gate);

      await confirm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Deleting your account…'), findsOneWidget);
      expect(canDelete(tester), isFalse);
      await tester.tap(deleteButton(), warnIfMissed: false);
      await tester.pump();
      expect(adapter.calls.where((c) => c == 'delete'), hasLength(1));
      expect(events, isEmpty, reason: 'not signed out before the answer');

      gate.complete();
      await tester.pumpAndSettle();

      expect(events, ['signOut']);
    });

    // ---- what goes wrong --------------------------------------------------------------------------
    for (final entry in <(String, Failure, String)>[
      (
        'a conflict',
        const ConflictFailure(),
        'Your account was not deleted. Something is in the way. Check again.'
      ),
      (
        'a refusal of permission',
        const AuthorizationFailure(),
        'You are not allowed to delete this account.'
      ),
      (
        'a request the database did not accept',
        const ValidationFailure(),
        'Your account was not deleted. Nothing was changed. Try again.'
      ),
      (
        'the picture could not be removed, so no deletion was attempted',
        const InfrastructureFailure(FailureReason.avatarCleanupFailed),
        'Your account was not deleted. Your profile picture could not be '
            'removed, so nothing else was changed. Try again.'
      ),
      (
        'the database refused after the picture was removed',
        const ConflictFailure(FailureReason.avatarRemovedFirst),
        'Your account was not deleted. Something is in the way. Check again. '
            'Your profile picture had already been removed.'
      ),
      (
        'the answer was lost',
        const NetworkFailure(),
        'Deleting your account may or may not have worked. Sign in again to '
            'check: if it did, your account no longer exists.'
      ),
    ]) {
      testWidgets('${entry.$1}: said exactly, and the session is NOT ended',
          (tester) async {
        await open(tester, [_preview(myClearDoc)], deleteFailure: entry.$2);

        await confirm(tester);
        await tester.pumpAndSettle();

        expect(find.text(entry.$3), findsOneWidget);
        expect(events, isEmpty, reason: 'nothing is deleted, or nobody knows');
        expect(find.byType(DeleteAccountScreen), findsOneWidget);
        expect(canDelete(tester), isFalse,
            reason:
                'nothing more is offered until the question is asked again');
        expect(
            find.byKey(const Key('deleteAccountCheckAgain')), findsOneWidget);
      });
    }

    testWidgets('checking again asks again and drops the failure',
        (tester) async {
      await open(tester, [_preview(myClearDoc)],
          deleteFailure: const ConflictFailure());
      await confirm(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('deleteAccountCheckAgain')));
      await tester.pumpAndSettle();

      expect(adapter.calls.where((c) => c == 'preview'), hasLength(2));
      expect(find.byKey(const Key('deleteAccountFailure')), findsNothing);
      expect(canDelete(tester), isTrue);
    });

    // ---- in Arabic -----------------------------------------------------------------------------------
    testWidgets('it reads in Arabic and asks for the Arabic word',
        (tester) async {
      await open(tester, [_preview(myBlockedDoc)], locale: const Locale('ar'));

      expect(find.text('حذف حسابي'), findsOneWidget);
      expect(find.textContaining('حذف حسابك نهائي'), findsOneWidget);
      expect(find.text('أنت مالك لمجتمعات'), findsOneWidget);
      expect(find.text('إدارة الأعضاء'), findsOneWidget);
    });

    testWidgets('the confirmation word is the Arabic one', (tester) async {
      await open(tester, [_preview(myClearDoc)], locale: const Locale('ar'));

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), 'DELETE');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('deleteAccountConfirmAction')))
            .onPressed,
        isNull,
        reason: 'the English word does not confirm in Arabic',
      );
      await tester.enterText(
          find.byKey(const Key('deleteAccountConfirmField')), 'حذف');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('deleteAccountConfirmAction')))
            .onPressed,
        isNotNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('Settings', () {
    testWidgets('has a Delete my account entry that opens the screen',
        (tester) async {
      final adapter = _FakeAdapter([_preview(myClearDoc)]);
      await pump(
        tester,
        SettingsScreen(
            accountDeletionRepository: AccountDeletionRepository(adapter)),
      );

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Delete my account'), findsOneWidget);
      expect(adapter.calls, isEmpty, reason: 'nothing is read until asked');

      await tester
          .ensureVisible(find.byKey(const Key('settingsDeleteAccount')));
      await tester.tap(find.byKey(const Key('settingsDeleteAccount')));
      await tester.pumpAndSettle();

      expect(find.byType(DeleteAccountScreen), findsOneWidget);
      expect(adapter.calls, ['preview']);
    });
  });
}
