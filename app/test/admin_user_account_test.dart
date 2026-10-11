import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/admin/admin_models.dart';
import 'package:go_play/features/admin/admin_repository.dart';
import 'package:go_play/features/admin/admin_user_detail_screen.dart';
import 'package:go_play/features/admin/admin_user_edit_screen.dart';
import 'package:go_play/features/auth/auth_models.dart' show PlayerPosition;
import 'package:go_play/features/locations/wilayat_repository.dart';
import 'package:go_play/features/profile/profile_models.dart'
    show ProfileVisibility;
import 'package:intl/intl.dart';

import 'admin_fakes.dart';
import 'wilayat_fixtures.dart';

/// Viewing and editing an account's data from the console (migration 0095).
///
/// The database refuses who may be edited and what is a valid value; what these
/// pin down is the console's side of that: the section that loads on its own,
/// the editor that is left out where the database would refuse it, five groups
/// that each send only their own RPC, and a refusal that arrives anyway being
/// worded rather than swallowed.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 4200);
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

  WilayatRepository wilayats() => WilayatRepository(FakeWilayatAdapter());

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
          wilayatRepository: wilayats(),
        ),
        locale: locale,
      );

  FakeAdminAdapter detailAdapter({
    AdminUserAccount? account,
    String? signedIn,
    Failure? accountFailure,
  }) =>
      FakeAdminAdapter(
        activitySummary: seenActivitySummary,
        accountResult: account,
        signedInUserId: signedIn,
        accountFailure: accountFailure,
      );

  // ---------------------------------------------------------------------------
  group('the repository', () {
    late FakeAdminAdapter adapter;
    late AdminRepository repository;

    setUp(() {
      adapter = FakeAdminAdapter();
      repository = AdminRepository(adapter);
    });

    test('a reason is trimmed, and a blank one is sent as no reason', () async {
      await repository.updateUserAccount('u1',
          fullName: 'Ali', phone: '+96891234567', reason: '  fixing a typo  ');
      await repository.updateUserAccount('u1',
          fullName: 'Ali', phone: '+96891234567', reason: '   ');
      await repository.updateUserAccount('u1',
          fullName: 'Ali', phone: '+96891234567');

      expect(adapter.calls, [
        'updateUserAccount:u1:Ali:+96891234567:fixing a typo',
        'updateUserAccount:u1:Ali:+96891234567:null',
        'updateUserAccount:u1:Ali:+96891234567:null',
      ]);
    });

    test('each of the five edits reaches its own port call, whole', () async {
      await repository.updateUserPlayerProfile('u1',
          dateOfBirth: DateTime(2000, 5, 5),
          primaryPosition: PlayerPosition.mid,
          secondaryPosition: null,
          reason: 'r');
      await repository.updateUserPrivacy('u1',
          visibility: ProfileVisibility.communityMembersOnly,
          ageVisible: false);
      await repository.updateUserDefaultWilayat('u1', wilayatCode: null);
      await repository.updateUserPushPreferences('u1',
          matchPush: true, communityPush: false, muteAll: true);

      expect(adapter.calls, [
        'updateUserPlayerProfile:u1:2000-05-05:mid:null:r',
        'updateUserPrivacy:u1:communityMembersOnly:false:null',
        'updateUserDefaultWilayat:u1:null:null',
        'updateUserPushPreferences:u1:true:false:true:null',
      ]);
    });

    test('a null date of birth is sent as null, not left out', () async {
      await repository.updateUserPlayerProfile('u1',
          dateOfBirth: null,
          primaryPosition: PlayerPosition.gk,
          secondaryPosition: PlayerPosition.def);

      expect(
          adapter.calls.single, 'updateUserPlayerProfile:u1:null:gk:def:null');
    });

    test('an edit the database refuses reaches the caller as its failure',
        () async {
      adapter.updateFailure = const AuthorizationFailure();

      await expectLater(
        repository.updateUserPrivacy('u1',
            visibility: ProfileVisibility.everyone, ageVisible: true),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('a read the database refuses is not swallowed into an empty account',
        () async {
      // Unlike isSystemAdmin, this is a read: a blank where the truth was "the
      // request was refused" would be a clean, wrong answer.
      adapter.accountFailure = const AuthorizationFailure();

      await expectLater(
        repository.userAccount('u1'),
        throwsA(isA<AuthorizationFailure>()),
      );
    });

    test('the signed-in id is the port\'s', () {
      adapter.signedInUserId = 'admin-1';
      expect(repository.currentUserId, 'admin-1');
      adapter.signedInUserId = null;
      expect(repository.currentUserId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('the Account data section', () {
    testWidgets('shows every field, including how they sign in',
        (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(
          account: adminAccount(
            dateOfBirth: DateTime(2000, 5, 5),
            primary: PlayerPosition.def,
            secondary: PlayerPosition.mid,
            visibility: ProfileVisibility.communityMembersOnly,
            ageVisible: false,
            wilayat: 7,
            matchPush: false,
            muteAll: true,
            providers: const ['email', 'google'],
            emailConfirmedAt: DateTime.utc(2026, 1, 15, 9),
            lastSignInAt: DateTime.utc(2026, 9, 3, 18, 30),
          ),
        ),
      );

      expect(find.text('Account data'), findsOneWidget);
      expect(find.text('Account Holder'), findsOneWidget);
      expect(find.text('+96891234567'), findsOneWidget);
      // The header above the section carries the same address.
      expect(find.text('u1@example.com'), findsNWidgets(2));
      expect(find.text('May 5, 2000'), findsOneWidget);
      expect(find.text('Defender'), findsOneWidget);
      expect(find.text('Midfielder'), findsOneWidget);
      expect(find.text('Community members only'), findsOneWidget);
      expect(find.text('Age visible to others'), findsOneWidget);
      // The Default Location by name; the code is a key and never shown.
      expect(find.text('Sohar'), findsOneWidget);
      expect(find.text('Match notifications'), findsOneWidget);
      expect(find.text('Mute all push notifications'), findsOneWidget);

      expect(find.text('Sign-in method'), findsOneWidget);
      expect(find.text('Email · Google'), findsOneWidget);
      expect(find.text('Email confirmed'), findsOneWidget);
      expect(find.text('Last sign-in'), findsOneWidget);
      expect(find.text('Account created'), findsOneWidget);
      // 09:00 UTC is 13:00 in Muscat, on the same day.
      final confirmed =
          '${DateFormat.yMMMEd('en').format(DateTime.utc(2026, 1, 15))} '
          '• 1:00 PM';
      expect(
        find.byWidgetPredicate((w) =>
            w is Text && (w.data ?? '').replaceAll(' ', ' ') == confirmed),
        findsWidgets,
      );
    });

    testWidgets(
        'a null date of birth, secondary position and location read as '
        'unset, not as a failure', (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount()),
      );

      // Date of birth and Default Location.
      expect(find.text('Not set'), findsNWidgets(2));
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Failed to load data.'), findsNothing);
    });

    testWidgets('never confirmed and never signed in say so', (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount()),
      );

      expect(find.text('Not confirmed'), findsOneWidget);
      expect(find.text('Never signed in'), findsOneWidget);
    });

    testWidgets('an account with no preferences row shows the defaults',
        (tester) async {
      // The database returns the column defaults for such an account, and the
      // section shows them as they are: match and community on, mute off.
      await pumpDetail(tester, detailAdapter(account: adminAccount()));

      expect(find.text('On'), findsNWidgets(2));
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('a method this build does not know is shown as named',
        (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount(providers: const ['apple'])),
      );

      expect(find.text('apple'), findsOneWidget);
    });

    testWidgets('a suspended account shows since when and why', (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount(isActive: false)),
      );

      expect(find.text('Account active'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Repeated no-shows'), findsOneWidget);
    });

    testWidgets('it reads in Arabic', (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(
          account: adminAccount(providers: const ['email', 'google']),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('بيانات الحساب'), findsOneWidget);
      expect(find.text('طريقة تسجيل الدخول'), findsOneWidget);
      expect(find.text('البريد الإلكتروني · Google'), findsOneWidget);
      expect(find.text('تعديل الحساب'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('the section loads on its own', () {
    for (final failure in <Failure>[
      // A caller the database refuses, a database that does not have the RPC
      // yet, a dropped connection, and an account that is gone.
      const AuthorizationFailure(),
      const InfrastructureFailure(),
      const NetworkFailure(),
      const NotFoundFailure(),
    ]) {
      testWidgets(
          '${failure.runtimeType}: the rest of the screen keeps working',
          (tester) async {
        await pumpDetail(tester, detailAdapter(accountFailure: failure));

        // The figures, the identity and the timeline all rendered.
        expect(find.text('Ali Al Amri'), findsOneWidget);
        expect(find.text('Joined'), findsOneWidget);
        expect(find.text('Recent activity'), findsOneWidget);
        // The section says it failed and offers its own retry.
        expect(find.text('Account data'), findsOneWidget);
        expect(find.text('Failed to load data.'), findsOneWidget);
        expect(find.byKey(const Key('adminAccountRetry')), findsOneWidget);
        // And no editor is offered for data that was not read.
        expect(find.byKey(const Key('adminAccountEdit')), findsNothing);
      });
    }

    testWidgets('its retry reads again, without redrawing the rest',
        (tester) async {
      final adapter = detailAdapter(accountFailure: const NetworkFailure());
      await pumpDetail(tester, adapter);
      expect(
          adapter.calls.where((c) => c == 'userActivitySummary:u1').length, 1);

      adapter.accountFailure = null;
      await tester.tap(find.byKey(const Key('adminAccountRetry')));
      await tester.pumpAndSettle();

      expect(find.text('Account Holder'), findsOneWidget);
      expect(find.text('Failed to load data.'), findsNothing);
      expect(adapter.calls.where((c) => c == 'userAccount:u1').length, 2);
      // The retry was the section's own: the summary was not read again.
      expect(
          adapter.calls.where((c) => c == 'userActivitySummary:u1').length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  group('the way into the editor', () {
    testWidgets('is offered for an ordinary account', (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount(), signedIn: 'admin-1'),
      );

      expect(find.byKey(const Key('adminAccountEdit')), findsOneWidget);
      expect(find.text('Edit account'), findsOneWidget);
    });

    testWidgets('is offered when the session cannot say who is signed in',
        (tester) async {
      // The database is what refuses, and the console words that refusal.
      await pumpDetail(tester, detailAdapter(account: adminAccount()));

      expect(find.byKey(const Key('adminAccountEdit')), findsOneWidget);
    });

    testWidgets('is left out for the administrator\'s own account',
        (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(account: adminAccount(id: 'u1'), signedIn: 'u1'),
      );

      expect(find.byKey(const Key('adminAccountEdit')), findsNothing);
      expect(
          find.text('You can\'t edit your own account here.'), findsOneWidget);
    });

    testWidgets('is left out for a System Admin, with the reason',
        (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(
          account: adminAccount(isSystemAdmin: true),
          signedIn: 'admin-1',
        ),
      );

      expect(find.byKey(const Key('adminAccountEdit')), findsNothing);
      expect(find.text('System Admin accounts are managed outside the app.'),
          findsOneWidget);
      // The section still shows the account: reading one is not editing it.
      expect(find.text('Account data'), findsOneWidget);
      expect(find.text('Account Holder'), findsOneWidget);
    });

    testWidgets('own account that is also a System Admin says it is their own',
        (tester) async {
      await pumpDetail(
        tester,
        detailAdapter(
          account: adminAccount(id: 'u1', isSystemAdmin: true),
          signedIn: 'u1',
        ),
      );

      expect(
          find.text('You can\'t edit your own account here.'), findsOneWidget);
    });

    testWidgets('opens the editor, and reads the section again on return',
        (tester) async {
      final adapter = detailAdapter(account: adminAccount());
      await pumpDetail(tester, adapter);

      await tester.tap(find.byKey(const Key('adminAccountEdit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminEditSave_account')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adminAccountEdit')), findsOneWidget);
      expect(adapter.calls.where((c) => c == 'userAccount:u1').length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('the editor', () {
    late FakeAdminAdapter adapter;

    Future<void> pumpEdit(
      WidgetTester tester,
      AdminUserAccount account, {
      Locale locale = const Locale('en'),
    }) async {
      adapter = FakeAdminAdapter(accountResult: account);
      await pump(
        tester,
        AdminUserEditScreen(
          account: account,
          repository: AdminRepository(adapter),
          wilayatRepository: wilayats(),
        ),
        locale: locale,
      );
    }

    Finder saveButton(String group) => find.byKey(Key('adminEditSave_$group'));

    bool canSave(WidgetTester tester, String group) =>
        tester.widget<FilledButton>(saveButton(group)).onPressed != null;

    Future<void> save(WidgetTester tester, String group) async {
      await tester.ensureVisible(saveButton(group));
      await tester.tap(saveButton(group));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, Key dropdown, String item) async {
      await tester.ensureVisible(find.byKey(dropdown));
      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    List<String> writes() =>
        adapter.calls.where((c) => c.startsWith('update')).toList();

    testWidgets('has the five groups, each with its own Save and reason',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      expect(find.text('Name and phone'), findsOneWidget);
      expect(find.text('Date of birth and positions'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      for (final group in [
        'account',
        'player',
        'privacy',
        'location',
        'push'
      ]) {
        expect(saveButton(group), findsOneWidget, reason: group);
        expect(find.byKey(Key('adminEditReason_$group')), findsOneWidget);
      }
      expect(find.text('Reason (optional)'), findsNWidgets(5));
    });

    testWidgets('Save is off until the group differs from what was read',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      for (final group in [
        'account',
        'player',
        'privacy',
        'location',
        'push'
      ]) {
        expect(canSave(tester, group), isFalse, reason: group);
      }
    });

    testWidgets('typing back what was there is not a change', (tester) async {
      await pumpEdit(tester, adminAccount(fullName: 'Ali Al Amri'));

      await tester.enterText(
          find.byKey(const Key('adminEditFullName')), 'Someone Else');
      await tester.pump();
      expect(canSave(tester, 'account'), isTrue);

      await tester.enterText(
          find.byKey(const Key('adminEditFullName')), 'Ali Al Amri');
      await tester.pump();
      expect(canSave(tester, 'account'), isFalse);
    });

    testWidgets(
        'the phone is shown as the eight digits and spacing alone is '
        'not a change', (tester) async {
      await pumpEdit(tester, adminAccount(phone: '+96891234567'));

      final field =
          tester.widget<TextFormField>(find.byKey(const Key('adminEditPhone')));
      expect(field.controller!.text, '91234567');

      await tester.enterText(
          find.byKey(const Key('adminEditPhone')), '9123 4567');
      await tester.pump();
      expect(canSave(tester, 'account'), isFalse);
    });

    // ---- name and phone
    testWidgets('name and phone save through their own RPC, as stored',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.enterText(
          find.byKey(const Key('adminEditFullName')), '  Sara Al Balushi ');
      await tester.enterText(
          find.byKey(const Key('adminEditPhone')), '9000 1111');
      await tester.pump();
      await save(tester, 'account');

      expect(
          writes(), ['updateUserAccount:u1:Sara Al Balushi:+96890001111:null']);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('a name that is too short is refused before anything is sent',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.enterText(find.byKey(const Key('adminEditFullName')), 'A');
      await tester.pump();
      await save(tester, 'account');

      expect(find.text('Full name is required'), findsOneWidget);
      expect(writes(), isEmpty);
    });

    testWidgets(
        'a phone that is not eight digits is refused before anything '
        'is sent', (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.enterText(find.byKey(const Key('adminEditPhone')), '12345');
      await tester.pump();
      await save(tester, 'account');

      expect(find.text('Enter an 8-digit phone number'), findsOneWidget);
      expect(writes(), isEmpty);
    });

    // ---- date of birth and positions
    testWidgets('a date of birth can be cleared, and clearing sends null',
        (tester) async {
      await pumpEdit(tester, adminAccount(dateOfBirth: DateTime(2000, 5, 5)));
      expect(find.text('May 5, 2000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('adminEditClearDateOfBirth')));
      await tester.pump();
      expect(find.text('Select date'), findsOneWidget);
      await save(tester, 'player');

      expect(writes(), ['updateUserPlayerProfile:u1:null:def:null:null']);
    });

    testWidgets('an account with no date of birth is editable as it is',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      await pick(tester, const Key('adminEditPrimary'), 'Forward');
      await save(tester, 'player');

      expect(writes(), ['updateUserPlayerProfile:u1:null:fwd:null:null']);
    });

    testWidgets('picking a date sends a date, not an instant', (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.tap(find.byKey(const Key('adminEditDateOfBirth')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await save(tester, 'player');

      final today = DateTime.now();
      final expected = DateTime(today.year - 25, today.month, today.day);
      expect(
        writes().single,
        'updateUserPlayerProfile:u1:'
        '${DateFormat('yyyy-MM-dd').format(expected)}:def:null:null',
      );
    });

    testWidgets(
        'the secondary can be removed with None, and is never the '
        'primary', (tester) async {
      await pumpEdit(tester, adminAccount(secondary: PlayerPosition.mid));

      // The primary is left out of the secondary's list.
      await tester.ensureVisible(find.byKey(const Key('adminEditSecondary')));
      await tester.tap(find.byKey(const Key('adminEditSecondary')));
      await tester.pumpAndSettle();
      expect(find.text('Defender'), findsOneWidget); // the primary field only
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      await save(tester, 'player');

      expect(writes(), ['updateUserPlayerProfile:u1:null:def:null:null']);
    });

    testWidgets('making the secondary the primary drops the secondary',
        (tester) async {
      await pumpEdit(tester, adminAccount(secondary: PlayerPosition.mid));

      await pick(tester, const Key('adminEditPrimary'), 'Midfielder');
      await save(tester, 'player');

      expect(writes(), ['updateUserPlayerProfile:u1:null:mid:null:null']);
    });

    // ---- privacy
    testWidgets('privacy sends both values', (tester) async {
      await pumpEdit(tester, adminAccount());

      await pick(
          tester, const Key('adminEditVisibility'), 'Community members only');
      await tester.ensureVisible(find.byKey(const Key('adminEditAgeVisible')));
      await tester.tap(find.byKey(const Key('adminEditAgeVisible')));
      await tester.pump();
      await save(tester, 'privacy');

      expect(
          writes(), ['updateUserPrivacy:u1:communityMembersOnly:false:null']);
    });

    // ---- default location
    testWidgets('a Default Location is chosen from the picker', (tester) async {
      await pumpEdit(tester, adminAccount());
      final field = find.byKey(const Key('adminEditDefaultLocation'));
      expect(find.descendant(of: field, matching: find.text('Not set')),
          findsOneWidget);

      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wilayat_7')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: field, matching: find.text('Sohar')),
          findsOneWidget);
      await save(tester, 'location');

      expect(writes(), ['updateUserDefaultWilayat:u1:7:null']);
    });

    testWidgets(
        'an existing Default Location is shown by name and can be '
        'cleared', (tester) async {
      await pumpEdit(tester, adminAccount(wilayat: 7));
      final field = find.byKey(const Key('adminEditDefaultLocation'));
      expect(find.descendant(of: field, matching: find.text('Sohar')),
          findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Clear default location'));
      await tester.tap(find.byTooltip('Clear default location'));
      await tester.pump();
      await save(tester, 'location');

      expect(writes(), ['updateUserDefaultWilayat:u1:null:null']);
    });

    // ---- push preferences
    testWidgets('push preferences send all three switches', (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
      await tester.tap(find.byKey(const Key('adminEditMuteAll')));
      await tester.pump();
      await save(tester, 'push');

      expect(writes(), ['updateUserPushPreferences:u1:true:true:true:null']);
    });

    // ---- reason, independence, re-read
    testWidgets('a reason is sent trimmed with the group it was typed in',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.enterText(find.byKey(const Key('adminEditReason_push')),
          '  asked by the player ');
      await tester.ensureVisible(find.byKey(const Key('adminEditMatchPush')));
      await tester.tap(find.byKey(const Key('adminEditMatchPush')));
      await tester.pump();
      await save(tester, 'push');

      expect(writes(), [
        'updateUserPushPreferences:u1:false:true:false:asked by the player'
      ]);
    });

    testWidgets('a reason typed in one group is not sent with another',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      await tester.enterText(
          find.byKey(const Key('adminEditReason_account')), 'wrong place');
      await tester.ensureVisible(find.byKey(const Key('adminEditAgeVisible')));
      await tester.tap(find.byKey(const Key('adminEditAgeVisible')));
      await tester.pump();
      await save(tester, 'privacy');

      expect(writes(), ['updateUserPrivacy:u1:everyone:false:null']);
    });

    testWidgets('saving one group sends one RPC and leaves the others alone',
        (tester) async {
      await pumpEdit(tester, adminAccount());

      // An unsaved edit sitting in another group.
      await tester.enterText(
          find.byKey(const Key('adminEditFullName')), 'Unsaved Name');
      await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
      await tester.tap(find.byKey(const Key('adminEditMuteAll')));
      await tester.pump();
      await save(tester, 'push');

      expect(writes(), ['updateUserPushPreferences:u1:true:true:true:null']);
      // The saved group was read again; the other group's edit is still there.
      expect(adapter.calls, contains('userAccount:u1'));
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('adminEditFullName')))
              .controller!
              .text,
          'Unsaved Name');
      expect(canSave(tester, 'account'), isTrue);
    });

    testWidgets('after a save the form follows what the database now holds',
        (tester) async {
      await pumpEdit(tester, adminAccount());
      adapter.accountResult = adminAccount(muteAll: true);

      await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
      await tester.tap(find.byKey(const Key('adminEditMuteAll')));
      await tester.pump();
      expect(canSave(tester, 'push'), isTrue);
      await save(tester, 'push');

      expect(canSave(tester, 'push'), isFalse);
    });

    testWidgets(
        'a save that went through is reported even if the re-read '
        'fails', (tester) async {
      await pumpEdit(tester, adminAccount());
      adapter.accountFailure = const NetworkFailure();

      await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
      await tester.tap(find.byKey(const Key('adminEditMuteAll')));
      await tester.pump();
      await save(tester, 'push');

      expect(writes(), hasLength(1));
      expect(find.text('Saved.'), findsOneWidget);
    });

    // ---- refusals
    for (final refusal in <(Failure, String)>[
      (const AuthorizationFailure(), 'You can\'t edit this account.'),
      (const AuthenticationFailure(), 'You can\'t edit this account.'),
      (
        const ValidationFailure(),
        'One of the values isn\'t valid. Check them and try again.'
      ),
      (const NotFoundFailure(), 'This account no longer exists.'),
      (
        const NetworkFailure(),
        'Could not reach the server. Check your internet connection.'
      ),
      (
        const InfrastructureFailure(),
        'Something went wrong. Please try again.'
      ),
    ]) {
      testWidgets('${refusal.$1.runtimeType} is worded and the edit stays',
          (tester) async {
        await pumpEdit(tester, adminAccount());
        adapter.updateFailure = refusal.$1;

        await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
        await tester.tap(find.byKey(const Key('adminEditMuteAll')));
        await tester.pump();
        await save(tester, 'push');

        expect(find.text(refusal.$2), findsOneWidget);
        expect(find.text('Saved.'), findsNothing);
        // The administrator's input is still there, and can be sent again.
        expect(canSave(tester, 'push'), isTrue);
        expect(adapter.calls.where((c) => c == 'userAccount:u1'), isEmpty,
            reason: 'nothing was saved, so nothing is read back');
      });
    }

    testWidgets('a suspended account is edited the same way', (tester) async {
      await pumpEdit(tester, adminAccount(isActive: false));

      await tester.ensureVisible(find.byKey(const Key('adminEditMuteAll')));
      await tester.tap(find.byKey(const Key('adminEditMuteAll')));
      await tester.pump();
      await save(tester, 'push');

      expect(writes(), ['updateUserPushPreferences:u1:true:true:true:null']);
    });

    testWidgets('it reads in Arabic', (tester) async {
      await pumpEdit(tester, adminAccount(), locale: const Locale('ar'));

      expect(find.text('تعديل الحساب'), findsOneWidget);
      expect(find.text('الاسم والجوال'), findsOneWidget);
      expect(find.text('تاريخ الميلاد والمراكز'), findsOneWidget);
      expect(find.text('السبب (اختياري)'), findsNWidgets(5));
    });
  });

  // ---------------------------------------------------------------------------
  group('the audit log', () {
    final updated = AdminAuditEntry(
      id: 'a9',
      action: 'USER_PROFILE_UPDATED',
      targetType: 'USER',
      createdAt: DateTime.utc(2026, 10, 7, 10),
      actorEmailSnapshot: 'admin@example.com',
      targetLabelSnapshot: 'Ali Al Amri',
      reason: 'Corrected at the player\'s request',
    );

    Future<void> openAudit(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      String tab = 'Audit Log',
    }) async {
      await pumpAdmin(tester, FakeAdminAdapter(audit: [updated]),
          locale: locale);
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    testWidgets('labels the new action rather than showing the raw token',
        (tester) async {
      await openAudit(tester);

      expect(find.text('Account updated'), findsOneWidget);
      expect(find.text('USER_PROFILE_UPDATED'), findsNothing);
      expect(find.text('Ali Al Amri'), findsOneWidget);
      expect(find.text('Corrected at the player\'s request'), findsOneWidget);
    });

    testWidgets('and reads it in Arabic', (tester) async {
      await openAudit(tester, locale: const Locale('ar'), tab: 'سجل الإدارة');

      expect(find.text('تعديل بيانات حساب'), findsOneWidget);
    });

    testWidgets(
        'shows the label only: the log RPC returns no metadata, so '
        'no field names are available to show', (tester) async {
      await openAudit(tester);

      expect(find.textContaining('changed_fields'), findsNothing);
      expect(find.textContaining('full_name'), findsNothing);
      expect(find.textContaining('phone'), findsNothing);
    });
  });
}
