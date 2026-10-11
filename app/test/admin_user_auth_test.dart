import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_audit_tab.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/infrastructure/supabase/mappers/admin_mapper.dart';
import 'package:go_play/l10n/generated/app_localizations_ar.dart';
import 'package:go_play/l10n/generated/app_localizations_en.dart';

import 'admin_fakes.dart';
import 'wilayat_fixtures.dart';

/// Changing another account's sign-in from the console (migration 0103): the email, the recovery
/// email, the password.
///
/// Whether the act is ALLOWED, and whether it HAPPENED, are the server's -- proved offline against
/// the real migration chain and against the Edge Function with a fake backend. What these pin down
/// is the console's side: that the actions are offered where the server would accept them and
/// worded where it would not, that each sends exactly one request carrying exactly what it should,
/// that an email that was changed but not followed by the mail is reported as that and not as a
/// failure, and that a password goes to the port once and is on no screen, in no failure and in no
/// text afterwards.
const _password = '  p@ss w0rd Ünicode ';

void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A screen pumped again over the previous one keeps its State -- and with it the first
    // adapter -- so a test that pumps in a loop starts from nothing each time.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  FakeAdminAdapter adapterFor({
    AdminUserAccount? account,
    String signedIn = 'admin',
  }) =>
      FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountResult: account ?? adminAccount(),
        signedInUserId: signedIn,
      );

  Future<void> pumpDetail(
    WidgetTester tester,
    FakeAdminAdapter adapter, {
    Locale locale = const Locale('en'),
  }) =>
      pump(
        tester,
        AdminUserDetailScreen(
          userId: 'u1',
          repository: AdminRepository(adapter),
          wilayatRepository: WilayatRepository(FakeWilayatAdapter()),
        ),
        locale: locale,
      );

  Future<void> open(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('adminAuthSubmit')));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  // ---------------------------------------------------------------------------
  group('what the mapper sends and reads', () {
    test('a request carries only what its action uses', () {
      expect(
        adminUserAuthParams(
          action: AdminUserAuthAction.changeEmail,
          userId: 'u1',
          reason: 'why',
          newEmail: 'a@b.test',
          redirectTo: 'goplay://login-callback/recovery',
        ),
        {
          'action': 'change_email',
          'user_id': 'u1',
          'reason': 'why',
          'new_email': 'a@b.test',
          'redirect_to': 'goplay://login-callback/recovery',
        },
      );
      expect(
        adminUserAuthParams(
          action: AdminUserAuthAction.sendRecovery,
          userId: 'u1',
          reason: 'why',
          redirectTo: 'goplay://login-callback/recovery',
        ).keys,
        ['action', 'user_id', 'reason', 'redirect_to'],
      );
      final set = adminUserAuthParams(
        action: AdminUserAuthAction.setPassword,
        userId: 'u1',
        reason: 'why',
        password: _password,
      );
      expect(set.keys, ['action', 'user_id', 'reason', 'password']);
      expect(set['password'], _password, reason: 'untouched, not trimmed');
    });

    test('the three action names are the ones the function takes', () {
      expect(AdminUserAuthAction.values.map((a) => a.wire),
          ['change_email', 'send_recovery', 'set_password']);
    });

    test('a complete email change, then each way it can be partial', () {
      final complete = adminUserAuthResultFromJson(
        {'ok': true, 'recovery_sent': true, 'audit_recorded': true},
        action: AdminUserAuthAction.changeEmail,
      );
      expect(
          [complete.emailChanged, complete.recoverySent, complete.isComplete],
          [true, true, true]);

      final limited = adminUserAuthResultFromJson(
        {'recovery_sent': false, 'recovery_error': 'RATE_LIMITED'},
        action: AdminUserAuthAction.changeEmail,
      );
      expect(limited.emailChanged, isTrue, reason: 'a 2xx means it changed');
      expect(limited.recoveryProblem, AdminRecoveryProblem.rateLimited);
      expect(limited.isComplete, isFalse);

      final failed = adminUserAuthResultFromJson(
        {'recovery_sent': false, 'recovery_error': 'RECOVERY_SEND_FAILED'},
        action: AdminUserAuthAction.changeEmail,
      );
      expect(failed.recoveryProblem, AdminRecoveryProblem.failed);

      final unexplained = adminUserAuthResultFromJson(
        {'recovery_sent': false},
        action: AdminUserAuthAction.changeEmail,
      );
      expect(unexplained.recoveryProblem, AdminRecoveryProblem.failed);
    });

    test('a missing audit flag is not a warning; only an explicit false is',
        () {
      for (final action in AdminUserAuthAction.values) {
        expect(adminUserAuthResultFromJson({}, action: action).auditRecorded,
            isTrue);
        expect(
            adminUserAuthResultFromJson({'audit_recorded': false},
                    action: action)
                .auditRecorded,
            isFalse);
      }
    });

    test(
        'whatever comes back, an answer that arrived is a change that happened',
        () {
      for (final garbage in <Map<String, dynamic>>[
        {},
        {'recovery_sent': 'yes'},
        {'audit_recorded': 7, 'recovery_error': 5},
      ]) {
        final email = adminUserAuthResultFromJson(garbage,
            action: AdminUserAuthAction.changeEmail);
        final pw = adminUserAuthResultFromJson(garbage,
            action: AdminUserAuthAction.setPassword);
        final rec = adminUserAuthResultFromJson(garbage,
            action: AdminUserAuthAction.sendRecovery);
        expect(email.emailChanged, isTrue, reason: '$garbage');
        expect(pw.passwordSet, isTrue, reason: '$garbage');
        expect(rec.recoverySent, isTrue, reason: '$garbage');
      }
    });

    test('sending the recovery email again completes a partial change', () {
      final partial = adminUserAuthResultFromJson(
        {'recovery_sent': false, 'recovery_error': 'RATE_LIMITED'},
        action: AdminUserAuthAction.changeEmail,
      );
      final again = partial.withRecoverySent(auditRecorded: true);
      expect([again.emailChanged, again.recoverySent, again.isComplete],
          [true, true, true]);
      expect(partial.withRecoverySent(auditRecorded: false).auditRecorded,
          isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('the repository', () {
    late FakeAdminAdapter adapter;
    late AdminRepository repository;

    setUp(() {
      adapter = FakeAdminAdapter();
      repository = AdminRepository(adapter);
    });

    test('the address and the reason are trimmed; the redirect is passed on',
        () async {
      await repository.changeUserEmail(
        'u1',
        newEmail: '  New@Example.test ',
        reason: '  ticket 12  ',
        redirectTo: 'goplay://login-callback/recovery',
      );
      expect(adapter.authRequests.single, {
        'action': 'change_email',
        'userId': 'u1',
        'newEmail': 'New@Example.test',
        'reason': 'ticket 12',
        'redirectTo': 'goplay://login-callback/recovery',
      });
    });

    test(
        'a password is passed on exactly as given -- a space can be part of it',
        () async {
      await repository.setUserPassword('u1',
          password: _password, reason: ' phone call ');
      expect(adapter.authRequests.single['password'], _password);
      expect(adapter.authRequests.single['reason'], 'phone call');
    });

    test('a request that breaks the rules is refused before the port is asked',
        () async {
      Future<void> refused(Future<Object?> Function() call) async {
        await expectLater(call(), throwsA(isA<ValidationFailure>()));
      }

      await refused(() => repository.changeUserEmail('u1',
          newEmail: 'not an address', reason: 'r', redirectTo: 'x'));
      await refused(() => repository.changeUserEmail('u1',
          newEmail: 'a@b.test', reason: '   ', redirectTo: 'x'));
      await refused(
          () => repository.sendUserRecovery('u1', reason: '', redirectTo: 'x'));
      await refused(() =>
          repository.setUserPassword('u1', password: '1234567', reason: 'r'));
      await refused(() =>
          repository.setUserPassword('u1', password: '12345678', reason: ' '));

      expect(adapter.authRequests, isEmpty);
      expect(adapter.calls, isEmpty);
    });

    test('exactly eight characters is a password; seven is not', () async {
      await repository.setUserPassword('u1', password: '12345678', reason: 'r');
      expect(adapter.authRequests, hasLength(1));
    });

    test('a failure of the port reaches the caller, not swallowed', () async {
      adapter.authQueue.add(const ConflictFailure(FailureReason.googleLinked));
      await expectLater(
        repository.changeUserEmail('u1',
            newEmail: 'a@b.test', reason: 'r', redirectTo: 'x'),
        throwsA(isA<ConflictFailure>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('the actions on the account screen', () {
    testWidgets('three actions for an ordinary account', (tester) async {
      await pumpDetail(tester, adapterFor());

      expect(find.byKey(const Key('adminAccountChangeEmail')), findsOneWidget);
      expect(find.byKey(const Key('adminAccountSendRecovery')), findsOneWidget);
      expect(find.byKey(const Key('adminAccountSetPassword')), findsOneWidget);
      expect(enabled(tester, 'adminAccountChangeEmail'), isTrue);
      expect(find.text(en.adminAuthGoogleNote), findsNothing);
    });

    testWidgets('none for the administrator\'s own account or a System Admin',
        (tester) async {
      await pumpDetail(tester, adapterFor(signedIn: 'u1'));
      for (final key in [
        'adminAccountChangeEmail',
        'adminAccountSendRecovery',
        'adminAccountSetPassword',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: 'self: $key');
      }
      expect(find.text(en.adminEditUnavailableSelf), findsOneWidget);

      await pumpDetail(
          tester, adapterFor(account: adminAccount(isSystemAdmin: true)));
      for (final key in [
        'adminAccountChangeEmail',
        'adminAccountSendRecovery',
        'adminAccountSetPassword',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: 'admin: $key');
      }
      expect(find.text(en.adminEditUnavailableSystemAdmin), findsOneWidget);
    });

    testWidgets(
        'a Google-linked account: the email change is disabled and says why; the other two stay',
        (tester) async {
      await pumpDetail(tester,
          adapterFor(account: adminAccount(providers: ['email', 'google'])));

      expect(enabled(tester, 'adminAccountChangeEmail'), isFalse);
      expect(find.text(en.adminAuthGoogleNote), findsOneWidget);
      expect(enabled(tester, 'adminAccountSendRecovery'), isTrue);
      expect(enabled(tester, 'adminAccountSetPassword'), isTrue);

      // a disabled action opens nothing
      await tester.tap(find.byKey(const Key('adminAccountChangeEmail')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminAuthDialog')), findsNothing);
    });

    testWidgets('the Google note and the actions read in Arabic',
        (tester) async {
      await pumpDetail(
        tester,
        adapterFor(account: adminAccount(providers: ['google'])),
        locale: const Locale('ar'),
      );
      expect(find.text(ar.adminAuthChangeEmailAction), findsOneWidget);
      expect(find.text(ar.adminAuthSendRecoveryAction), findsOneWidget);
      expect(find.text(ar.adminAuthSetPasswordAction), findsOneWidget);
      expect(find.text(ar.adminAuthGoogleNote), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('change email', () {
    testWidgets('what the form asks, and nothing is sent until it is right',
        (tester) async {
      final adapter = adapterFor();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');

      expect(find.text(en.adminAuthChangeEmailBody), findsOneWidget);
      expect(find.text(en.adminAuthCurrentEmail('u1@example.com')),
          findsOneWidget);

      await submit(tester);
      expect(find.text(en.emailRequired), findsOneWidget);
      expect(find.text(en.adminAuthReasonRequired), findsOneWidget);

      await type(tester, 'adminAuthNewEmail', 'nope');
      await submit(tester);
      expect(find.text(en.emailInvalid), findsOneWidget);

      await type(tester, 'adminAuthNewEmail', ' U1@Example.com ');
      await submit(tester);
      expect(find.text(en.adminAuthEmailSame), findsOneWidget,
          reason: 'the account\'s own address, in any case');

      await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@exemple.com');
      await type(tester, 'adminAuthReason', 'ticket 12');
      await submit(tester);
      expect(find.text(en.adminAuthEmailMismatch), findsOneWidget);

      expect(adapter.authRequests, isEmpty, reason: 'nothing was sent');
    });

    testWidgets(
        'success: one request with exactly the typed values, then the whole story',
        (tester) async {
      final adapter = adapterFor();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');

      await type(tester, 'adminAuthNewEmail', ' Fresh@Example.com ');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.COM');
      await type(tester, 'adminAuthReason', '  ticket 12 ');
      await submit(tester);

      expect(adapter.authRequests, [
        {
          'action': 'change_email',
          'userId': 'u1',
          'newEmail': 'Fresh@Example.com',
          'reason': 'ticket 12',
          'redirectTo': 'goplay://login-callback/recovery',
        }
      ]);
      expect(find.text(en.adminAuthEmailChangedDone), findsOneWidget);
      expect(find.byKey(const Key('adminAuthRetryRecovery')), findsNothing);
      expect(find.byKey(const Key('adminAuthAuditMissing')), findsNothing);

      // Done closes it and the account is read again
      final reads = adapter.calls.where((c) => c == 'userAccount:u1').length;
      await tester.tap(find.byKey(const Key('adminAuthDone')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminAuthDialog')), findsNothing);
      expect(
          adapter.calls.where((c) => c == 'userAccount:u1').length, reads + 1);
    });

    testWidgets(
        'one request in flight: the buttons are off and the work is shown',
        (tester) async {
      final adapter = adapterFor()..authGate = Completer<void>();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');
      await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
      await type(tester, 'adminAuthReason', 'r');

      await tester.tap(find.byKey(const Key('adminAuthSubmit')));
      await tester.pump();

      expect(find.text(en.adminAuthWorking), findsOneWidget);
      expect(enabled(tester, 'adminAuthSubmit'), isFalse);
      expect(enabled(tester, 'adminAuthCancel'), isFalse);
      await tester.tap(find.byKey(const Key('adminAuthSubmit')),
          warnIfMissed: false);
      await tester.pump();
      expect(adapter.authRequests, hasLength(1));

      adapter.authGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(en.adminAuthEmailChangedDone), findsOneWidget);
      expect(adapter.authRequests, hasLength(1));
    });

    testWidgets(
        'the email changed but the recovery email did not go: said as that, kept, and the mail can be sent again',
        (tester) async {
      final adapter = adapterFor()
        ..authQueue.addAll([
          const AdminUserAuthResult(
            action: AdminUserAuthAction.changeEmail,
            emailChanged: true,
            recoveryProblem: AdminRecoveryProblem.rateLimited,
          ),
          // the retry fails once, then works
          const InfrastructureFailure(FailureReason.tooManyRequests),
          const AdminUserAuthResult(
            action: AdminUserAuthAction.sendRecovery,
            recoverySent: true,
          ),
        ]);
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');
      await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
      await type(tester, 'adminAuthReason', 'ticket 12');
      await submit(tester);

      expect(find.text(en.adminAuthEmailChangedRateLimited), findsOneWidget);
      expect(find.byKey(const Key('adminAuthError')), findsNothing,
          reason: 'it is not presented as a failure');

      await tester.tap(find.byKey(const Key('adminAuthRetryRecovery')));
      await tester.pumpAndSettle();
      expect(find.text(en.adminAuthRateLimited), findsOneWidget);
      expect(find.text(en.adminAuthEmailChangedRateLimited), findsOneWidget,
          reason: 'the change is still reported as made');

      await tester.tap(find.byKey(const Key('adminAuthRetryRecovery')));
      await tester.pumpAndSettle();
      expect(find.text(en.adminAuthEmailChangedDone), findsOneWidget);
      expect(find.byKey(const Key('adminAuthRetryRecovery')), findsNothing);

      // the retry is the plain recovery request, with the same reason, and no second email change
      expect(adapter.authRequests.map((r) => r['action']),
          ['change_email', 'send_recovery', 'send_recovery']);
      expect(adapter.authRequests[1], {
        'action': 'send_recovery',
        'userId': 'u1',
        'reason': 'ticket 12',
        'redirectTo': 'goplay://login-callback/recovery',
      });
    });

    testWidgets(
        'a recovery email that failed for another reason is worded plainly',
        (tester) async {
      final adapter = adapterFor()
        ..authQueue.add(const AdminUserAuthResult(
          action: AdminUserAuthAction.changeEmail,
          emailChanged: true,
          recoveryProblem: AdminRecoveryProblem.failed,
        ));
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');
      await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);

      expect(find.text(en.adminAuthEmailChangedNoRecovery), findsOneWidget);
    });

    testWidgets(
        'the change was made but could not be recorded: said, in addition',
        (tester) async {
      final adapter = adapterFor()
        ..authQueue.add(const AdminUserAuthResult(
          action: AdminUserAuthAction.changeEmail,
          emailChanged: true,
          recoverySent: true,
          auditRecorded: false,
        ));
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountChangeEmail');
      await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
      await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);

      expect(find.text(en.adminAuthEmailChangedDone), findsOneWidget);
      expect(find.text(en.adminAuthAuditMissing), findsOneWidget);
    });

    testWidgets(
        'every refusal reads in plain words and leaves the form to try again',
        (tester) async {
      final cases = <Failure, String>{
        const ConflictFailure(FailureReason.googleLinked):
            en.adminAuthGoogleLinked,
        const ConflictFailure(FailureReason.emailAlreadyUsed):
            en.adminAuthEmailTaken,
        const ConflictFailure(): en.adminAuthNoEmail,
        const AuthorizationFailure(): en.adminAuthNotAllowed,
        const NotFoundFailure(FailureReason.profileNotFound):
            en.adminAuthAccountGone,
        const ValidationFailure(): en.adminAuthEmailRejected,
        const InfrastructureFailure(FailureReason.tooManyRequests):
            en.adminAuthRateLimited,
        const InfrastructureFailure(): en.adminAuthFailed,
      };
      for (final entry in cases.entries) {
        final adapter = adapterFor()..authQueue.add(entry.key);
        await pumpDetail(tester, adapter);
        await open(tester, 'adminAccountChangeEmail');
        await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
        await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
        await type(tester, 'adminAuthReason', 'r');
        await submit(tester);

        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
        expect(find.byKey(const Key('adminAuthSubmit')), findsOneWidget,
            reason: 'the form is still there');
        expect(enabled(tester, 'adminAuthSubmit'), isTrue);

        // closing after a plain refusal changes nothing, so the account is not read again
        final reads = adapter.calls.where((c) => c == 'userAccount:u1').length;
        await tester.tap(find.byKey(const Key('adminAuthCancel')));
        await tester.pumpAndSettle();
        expect(adapter.calls.where((c) => c == 'userAccount:u1').length, reads);
      }
    });

    testWidgets(
        'a lost answer is "not known": it is not called a failure to change, and closing reads the account again',
        (tester) async {
      for (final failure in <Failure>[
        const InfrastructureFailure(FailureReason.authOutcomeUnknown),
        const NetworkFailure(),
      ]) {
        final adapter = adapterFor()..authQueue.add(failure);
        await pumpDetail(tester, adapter);
        await open(tester, 'adminAccountChangeEmail');
        await type(tester, 'adminAuthNewEmail', 'fresh@example.com');
        await type(tester, 'adminAuthNewEmailAgain', 'fresh@example.com');
        await type(tester, 'adminAuthReason', 'r');
        await submit(tester);

        expect(find.text(en.adminAuthOutcomeUnknown), findsOneWidget,
            reason: '$failure');
        final reads = adapter.calls.where((c) => c == 'userAccount:u1').length;
        await tester.tap(find.byKey(const Key('adminAuthCancel')));
        await tester.pumpAndSettle();
        expect(
            adapter.calls.where((c) => c == 'userAccount:u1').length, reads + 1,
            reason: 'it may have been applied, so the screen looks again');
      }
    });

    testWidgets(
        'it reads in Arabic, right to left, with the address field left to right',
        (tester) async {
      await pumpDetail(tester, adapterFor(), locale: const Locale('ar'));
      await open(tester, 'adminAccountChangeEmail');

      expect(find.text(ar.adminAuthChangeEmailTitle), findsWidgets);
      expect(find.text(ar.adminAuthChangeEmailBody), findsOneWidget);
      expect(find.text(ar.adminAuthNewEmailLabel), findsOneWidget);
      expect(find.text(ar.adminAuthReasonLabel), findsOneWidget);
      expect(
        Directionality.of(
            tester.element(find.byKey(const Key('adminAuthDialog')))),
        TextDirection.rtl,
      );
      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('adminAuthNewEmail')),
        matching: find.byType(TextField),
      ));
      expect(field.textDirection, TextDirection.ltr);
    });
  });

  // ---------------------------------------------------------------------------
  group('send recovery', () {
    testWidgets('the address it goes to is named, nothing changes, one request',
        (tester) async {
      final adapter = adapterFor();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSendRecovery');

      expect(find.text(en.adminAuthSendRecoveryBody('u1@example.com')),
          findsOneWidget);
      expect(find.byKey(const Key('adminAuthNewEmail')), findsNothing);
      expect(find.byKey(const Key('adminAuthPassword')), findsNothing);

      await submit(tester);
      expect(find.text(en.adminAuthReasonRequired), findsOneWidget);
      expect(adapter.authRequests, isEmpty);

      await type(tester, 'adminAuthReason', ' locked out ');
      await submit(tester);

      expect(adapter.authRequests, [
        {
          'action': 'send_recovery',
          'userId': 'u1',
          'reason': 'locked out',
          'redirectTo': 'goplay://login-callback/recovery',
        }
      ]);
      expect(find.text(en.adminAuthRecoveryDone), findsOneWidget);
    });

    testWidgets('the provider\'s limit is worded and can be tried again',
        (tester) async {
      final adapter = adapterFor()
        ..authQueue
            .add(const InfrastructureFailure(FailureReason.tooManyRequests));
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSendRecovery');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);

      expect(find.text(en.adminAuthRateLimited), findsOneWidget);
      await submit(tester);
      expect(find.text(en.adminAuthRecoveryDone), findsOneWidget);
      expect(adapter.authRequests, hasLength(2));
    });

    testWidgets(
        'a dropped connection is a plain failure here: nothing could have changed',
        (tester) async {
      final adapter = adapterFor()..authQueue.add(const NetworkFailure());
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSendRecovery');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);

      expect(find.text(en.adminAuthFailed), findsOneWidget);
      expect(find.text(en.adminAuthOutcomeUnknown), findsNothing);
      final reads = adapter.calls.where((c) => c == 'userAccount:u1').length;
      await tester.tap(find.byKey(const Key('adminAuthCancel')));
      await tester.pumpAndSettle();
      expect(adapter.calls.where((c) => c == 'userAccount:u1').length, reads);
    });
  });

  // ---------------------------------------------------------------------------
  group('set password', () {
    testWidgets('the fields hide what is typed; the rules are the product\'s',
        (tester) async {
      final adapter = adapterFor();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSetPassword');

      for (final key in ['adminAuthPassword', 'adminAuthPasswordAgain']) {
        final field = tester.widget<TextField>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
        ));
        expect(field.obscureText, isTrue, reason: key);
        expect(field.autocorrect, isFalse, reason: key);
        expect(field.enableSuggestions, isFalse, reason: key);
      }

      await type(tester, 'adminAuthPassword', '1234567');
      await type(tester, 'adminAuthPasswordAgain', '1234567');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);
      expect(find.text(en.passwordTooShort), findsOneWidget);

      await type(tester, 'adminAuthPassword', '12345678');
      await type(tester, 'adminAuthPasswordAgain', '12345679');
      await submit(tester);
      expect(find.text(en.adminAuthPasswordMismatch), findsOneWidget);

      expect(adapter.authRequests, isEmpty);
    });

    testWidgets(
        'success: the password goes to the port once, exactly as typed, and is on no screen afterwards',
        (tester) async {
      final adapter = adapterFor();
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSetPassword');

      await type(tester, 'adminAuthPassword', _password);
      await type(tester, 'adminAuthPasswordAgain', _password);
      await type(tester, 'adminAuthReason', 'phone call verified');
      await submit(tester);

      expect(adapter.authRequests, [
        {
          'action': 'set_password',
          'userId': 'u1',
          'password': _password,
          'reason': 'phone call verified',
        }
      ]);
      expect(find.text(en.adminAuthPasswordDone), findsOneWidget);
      expect(find.textContaining('w0rd'), findsNothing);
      expect(find.byType(EditableText), findsNothing,
          reason: 'the fields are gone, and with them what they held');
      expect(find.textContaining('w0rd', findRichText: true), findsNothing);
    });

    testWidgets(
        'a refusal never repeats the password, and the form stays to try again',
        (tester) async {
      for (final failure in <Failure>[
        const ValidationFailure(),
        const InfrastructureFailure(FailureReason.tooManyRequests),
        const InfrastructureFailure(FailureReason.authOutcomeUnknown),
        const InfrastructureFailure(),
        const AuthorizationFailure(),
      ]) {
        final adapter = adapterFor()..authQueue.add(failure);
        await pumpDetail(tester, adapter);
        await open(tester, 'adminAccountSetPassword');
        await type(tester, 'adminAuthPassword', _password);
        await type(tester, 'adminAuthPasswordAgain', _password);
        await type(tester, 'adminAuthReason', 'r');
        await submit(tester);

        expect(find.byKey(const Key('adminAuthError')), findsOneWidget,
            reason: '$failure');
        final shown =
            tester.widget<Text>(find.byKey(const Key('adminAuthError'))).data!;
        expect(shown.contains('w0rd'), isFalse);
        expect(failure.toString().contains('w0rd'), isFalse);
        expect(find.byKey(const Key('adminAuthSubmit')), findsOneWidget);
        await tester.tap(find.byKey(const Key('adminAuthCancel')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the provider turning a password down is said in its own words',
        (tester) async {
      final adapter = adapterFor()..authQueue.add(const ValidationFailure());
      await pumpDetail(tester, adapter);
      await open(tester, 'adminAccountSetPassword');
      await type(tester, 'adminAuthPassword', '12345678');
      await type(tester, 'adminAuthPasswordAgain', '12345678');
      await type(tester, 'adminAuthReason', 'r');
      await submit(tester);

      expect(find.text(en.adminAuthPasswordRejected), findsOneWidget);
    });

    testWidgets('it reads in Arabic', (tester) async {
      await pumpDetail(tester, adapterFor(), locale: const Locale('ar'));
      await open(tester, 'adminAccountSetPassword');

      expect(find.text(ar.adminAuthSetPasswordBody), findsOneWidget);
      expect(find.text(ar.adminAuthConfirmPasswordLabel), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('the audit trail shows the three events', () {
    testWidgets('by name, in both languages, with the reason', (tester) async {
      final entries = [
        for (final (i, action) in [
          'USER_EMAIL_CHANGED',
          'USER_RECOVERY_SENT',
          'USER_PASSWORD_SET',
        ].indexed)
          AdminAuditEntry(
            id: 'a$i',
            action: action,
            targetType: 'USER',
            createdAt: DateTime.utc(2026, 10, 11, 9 - i),
            actorEmailSnapshot: 'admin@example.com',
            targetLabelSnapshot: 'Ali',
            reason: 'reason $i',
          ),
      ];
      for (final locale in [const Locale('en'), const Locale('ar')]) {
        await pump(
          tester,
          Scaffold(
            body: AdminAuditTab(
              repository: AdminRepository(FakeAdminAdapter(audit: entries)),
            ),
          ),
          locale: locale,
        );
        final l10n = locale.languageCode == 'en' ? en : ar;
        expect(find.text(l10n.adminActionUserEmailChanged), findsOneWidget);
        expect(find.text(l10n.adminActionUserRecoverySent), findsOneWidget);
        expect(find.text(l10n.adminActionUserPasswordSet), findsOneWidget);
        expect(find.text('USER_EMAIL_CHANGED'), findsNothing,
            reason: 'a label, not the raw code');
      }
    });
  });
}
