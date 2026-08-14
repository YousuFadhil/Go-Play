import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/profile/edit_profile_screen.dart';

/// The Edit Profile form against fake ports.
///
/// Sprint 2.5 split the profile in two: the record moved to `ProfileScreen` and
/// the fields came here. This suite followed the fields — every assertion below
/// is about the form's behaviour and none of it changed with the move.
///
/// Two things live on it and are asserted separately: the playing inputs the
/// engine reads (§4.1) — which is the path the accounts created before the
/// date-of-birth field take to supply one — and the account fields a player may
/// now correct. What is asserted is the screen's own behaviour: what it shows of
/// a stored profile, what it insists on before saving, and what it hands to each
/// port. The rules are covered in `repository_behaviour_test.dart` and the
/// payload in `mappers_test.dart`.
void main() {
  final birthday = DateTime(1995, 4, 17);

  /// A profile as an existing account holds one: no date of birth, because the
  /// field did not exist when the account was made.
  const unfinished = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.fwd,
  );

  final complete = PlayerProfile(
    fullName: 'Salim Al Harthy',
    phone: '+96890123456',
    primaryPosition: PlayerPosition.gk,
    dateOfBirth: birthday,
    secondaryPosition: PlayerPosition.def,
  );

  Future<void> pumpProfile(
    WidgetTester tester,
    FakeProfileAdapter adapter, {
    FakeAuthAdapter? auth,
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    // A surface tall enough for the whole form; the default leaves the button
    // below the fold.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The header reads the signed-in player for itself. Pointing it at the same
    // fake keeps it out of the data provider, and clearing it afterwards stops
    // one test's profile leaking into the next.
    CurrentUser.instance.useRepository(ProfileRepository(adapter));
    addTearDown(() => CurrentUser.instance.useRepository(null));

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: EditProfileScreen(
        repository: ProfileRepository(adapter),
        authService: AuthService(auth ?? FakeAuthAdapter()),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  // The two dropdowns, told apart by what they hold rather than by their
  // labels: a floating label is not reliably the tap target of its own field.
  final primaryField = find.byType(DropdownButtonFormField<PlayerPosition>);
  final secondaryField = find.byType(DropdownButtonFormField<PlayerPosition?>);

  // The account fields, in the order the form lays them out.
  Finder nameField() => find.byType(TextFormField).at(0);
  Finder phoneField() => find.byType(TextFormField).at(1);

  Future<void> choosePosition(
      WidgetTester tester, Finder field, String label) async {
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> choosePrimary(WidgetTester tester, String label) =>
      choosePosition(tester, primaryField, label);

  Future<void> chooseSecondary(WidgetTester tester, String label) =>
      choosePosition(tester, secondaryField, label);

  /// Picks a date of birth by accepting the date the picker opens on: the
  /// stored one, or 25 years ago today when there is none.
  Future<void> pickDateOfBirth(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {String label = 'Save'}) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  DateTime defaultOfferedDate() {
    final now = DateTime.now();
    return DateTime(now.year - 25, now.month, now.day);
  }

  group('loading', () {
    testWidgets('shows the indicator until the profile arrives', (tester) async {
      final gate = Completer<void>();
      await pumpProfile(
        tester,
        FakeProfileAdapter(profile: complete, gate: gate.future),
        settle: false,
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Apr 17, 1995'), findsOneWidget);
    });

    testWidgets('the stored values are the ones shown', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      expect(find.text('Apr 17, 1995'), findsOneWidget);
      expect(find.text('Goalkeeper'), findsOneWidget);
      expect(find.text('Defender'), findsOneWidget);
      // The name appears in the form field; the header shows the first name.
      expect(find.text('Salim Al Harthy'), findsOneWidget);
      // The stored number is E.164; the field shows the eight local digits and
      // the country code is a prefix rather than something to type.
      expect(find.text('90123456'), findsOneWidget);
    });

    testWidgets('the age is derived from the date of birth, never stored',
        (tester) async {
      final today = DateTime.now();
      final profile = PlayerProfile(
        fullName: 'Salim Al Harthy',
        phone: '+96890123456',
        primaryPosition: PlayerPosition.mid,
        // A birthday that has already passed this year, so the arithmetic is
        // the same whenever the suite runs.
        dateOfBirth: DateTime(today.year - 30, 1, 1),
      );
      await pumpProfile(tester, FakeProfileAdapter(profile: profile));

      // Its own labelled row, not a note in the margin of the date field.
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('30 years old'), findsOneWidget);
    });

    testWidgets('an account with no date of birth is shown as it is',
        (tester) async {
      // Nothing is invented for it: §4.3 refuses a substituted Core Player
      // Input, and the screen asks for one rather than filling it in.
      await pumpProfile(tester, FakeProfileAdapter(profile: unfinished));

      expect(find.text('Select date'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);
      // The row is still there, saying it has nothing: there is no date to
      // derive an age from, and a zero would be a number the profile does not
      // hold (§4.3). 'None' is the secondary position and '—' is the age.
      expect(find.text('Age'), findsOneWidget);
      expect(find.textContaining('years old'), findsNothing);
    });

    testWidgets('a load that fails offers a retry', (tester) async {
      final adapter = FakeProfileAdapter(readFailure: const NetworkFailure());
      await pumpProfile(tester, adapter);

      expect(find.text('Failed to load data.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(adapter.reads, greaterThanOrEqualTo(2));
    });
  });

  group('what the screen does not offer', () {
    testWidgets('the rating is neither shown nor editable (OP-1)',
        (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      expect(find.textContaining('Rating'), findsNothing);
      expect(find.textContaining('rating'), findsNothing);
      expect(find.text('5.0'), findsNothing);
    });

    testWidgets('a role is not on it either', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      for (final label in const ['Owner', 'Admin', 'Player', 'Role']) {
        expect(find.text(label), findsNothing);
      }
    });
  });

  group('saving', () {
    testWidgets('an existing account supplies the date it was missing',
        (tester) async {
      final adapter = FakeProfileAdapter(profile: unfinished);
      await pumpProfile(tester, adapter);

      await pickDateOfBirth(tester);
      await save(tester);

      expect(adapter.writes, 1);
      expect(adapter.lastDateOfBirth, defaultOfferedDate());
      expect(adapter.lastPrimaryPosition, PlayerPosition.fwd,
          reason: 'the position it already had is untouched');
      expect(adapter.lastSecondaryPosition, isNull);
      expect(find.text('Profile updated.'), findsOneWidget);
    });

    testWidgets('the primary position can be changed', (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await choosePrimary(tester, 'Midfielder');
      await save(tester);

      expect(adapter.lastPrimaryPosition, PlayerPosition.mid);
      expect(adapter.lastDateOfBirth, birthday,
          reason: 'the stored date is kept unless the player changes it');
    });

    testWidgets('a secondary position can be set', (tester) async {
      final adapter = FakeProfileAdapter(profile: unfinished);
      await pumpProfile(tester, adapter);

      await pickDateOfBirth(tester);
      await chooseSecondary(tester, 'Midfielder');
      await save(tester);

      expect(adapter.lastSecondaryPosition, PlayerPosition.mid);
    });

    testWidgets('a secondary position can be removed', (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await chooseSecondary(tester, 'None');
      await save(tester);

      expect(adapter.writes, 1);
      expect(adapter.lastSecondaryPosition, isNull,
          reason: 'removing one stores the absence, never a NONE value');
    });

    testWidgets('the name and the number are written by their own call',
        (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await tester.enterText(nameField(), 'Salim Al Balushi');
      await tester.enterText(phoneField(), '9911 2233');
      await save(tester);

      expect(adapter.accountWrites, 1);
      expect(adapter.lastFullName, 'Salim Al Balushi');
      // Composed into the stored form, separators and all.
      expect(adapter.lastPhone, '+96899112233');
      // The playing inputs still went, and went separately.
      expect(adapter.writes, 1);
    });

    testWidgets('a refused write says so and changes nothing', (tester) async {
      final adapter = FakeProfileAdapter(
        profile: complete,
        writeFailure: const AuthorizationFailure(),
      );
      await pumpProfile(tester, adapter);

      await save(tester);

      expect(find.text('You do not have permission to do this.'),
          findsOneWidget);
    });
  });

  group('what the screen refuses', () {
    testWidgets('saving without a date of birth', (tester) async {
      final adapter = FakeProfileAdapter(profile: unfinished);
      await pumpProfile(tester, adapter);

      await save(tester);

      expect(find.text('Date of birth is required'), findsOneWidget);
      expect(adapter.writes, 0,
          reason: 'an incomplete profile never reaches the port');
      expect(adapter.accountWrites, 0,
          reason: 'neither half is written when the form is invalid');
    });

    testWidgets('saving with an empty name', (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await tester.enterText(nameField(), '  ');
      await save(tester);

      expect(find.text('Full name is required'), findsOneWidget);
      expect(adapter.accountWrites, 0);
    });

    testWidgets('saving with a number that is not eight digits',
        (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await tester.enterText(phoneField(), '123');
      await save(tester);

      expect(find.text('Enter an 8-digit phone number'), findsOneWidget);
      expect(adapter.accountWrites, 0);
    });

    testWidgets('a date of birth in the future is never offered',
        (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: unfinished));

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate.isAfter(DateTime.now()), isFalse);
    });
  });

  group('credentials', () {
    testWidgets('the email in the session is the one shown', (tester) async {
      await pumpProfile(
        tester,
        FakeProfileAdapter(profile: complete),
        auth: FakeAuthAdapter(email: 'salim@example.com'),
      );

      expect(find.text('salim@example.com'), findsOneWidget);
    });

    testWidgets('changing the email reports that it needs confirming',
        (tester) async {
      final auth = FakeAuthAdapter(email: 'salim@example.com');
      await pumpProfile(tester, FakeProfileAdapter(profile: complete),
          auth: auth);

      await tester.tap(find.widgetWithText(TextButton, 'Change').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField).last, 'new@example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(auth.changedEmail, 'new@example.com');
      // The confirmation link has to come back to the app. Without a redirect
      // the provider uses its own Site URL and the player lands on a web page
      // this project does not serve.
      expect(auth.changedRedirect, AuthService.emailChangeRedirect);
      expect(auth.changedRedirect, startsWith('goplay://'));
      // Not "your email has changed": whether the provider requires the new
      // address to be confirmed is its setting, not something to assert.
      expect(find.text('Check your new address for the confirmation link.'),
          findsOneWidget);
    });

    testWidgets('an invalid email never reaches the port', (tester) async {
      final auth = FakeAuthAdapter(email: 'salim@example.com');
      await pumpProfile(tester, FakeProfileAdapter(profile: complete),
          auth: auth);

      await tester.tap(find.widgetWithText(TextButton, 'Change').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(auth.changedEmail, isNull);
    });

    testWidgets('a password is only changed when it is confirmed',
        (tester) async {
      final auth = FakeAuthAdapter(email: 'salim@example.com');
      await pumpProfile(tester, FakeProfileAdapter(profile: complete),
          auth: auth);

      await tester.tap(find.widgetWithText(TextButton, 'Change').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(fields.evaluate().length - 2),
          'longenoughpassword');
      await tester.enterText(fields.last, 'somethingelse');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(find.text('The two passwords do not match'), findsOneWidget);
      expect(auth.changedPassword, isNull);

      await tester.enterText(fields.last, 'longenoughpassword');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(auth.changedPassword, 'longenoughpassword');
      expect(find.text('Password changed.'), findsOneWidget);
    });
  });

  group('choosing where a picture comes from', () {
    testWidgets('both a camera and the gallery are offered', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();

      // Two different moments: an account being set up usually has a photo
      // already, and a phone handed over at the pitch does not.
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets('dismissing the sheet picks nothing and uploads nothing',
        (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      // Tapping the barrier is how a bottom sheet is dismissed.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(adapter.avatarUploads, 0,
          reason: 'closing the sheet is a decision not to change the picture');
    });
  });

  group('the picture', () {
    testWidgets('an account with none is offered no way to remove one',
        (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      expect(find.text('Change photo'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
    });

    testWidgets('an account with one can take it away', (tester) async {
      final adapter = FakeProfileAdapter(
        profile: PlayerProfile(
          fullName: 'Salim Al Harthy',
          phone: '+96890123456',
          primaryPosition: PlayerPosition.gk,
          dateOfBirth: birthday,
          avatarUrl: 'https://example.test/avatar.jpg',
        ),
      );
      await pumpProfile(tester, adapter);

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();

      expect(adapter.avatarRemovals, 1);
      expect(find.text('Photo removed.'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing,
          reason: 'there is nothing left to remove');
    });
  });

  group('logging out', () {
    testWidgets('the screen offers it, and asks before doing it',
        (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      expect(find.widgetWithText(OutlinedButton, 'Log out'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsNothing);
    });
  });

  group('the two positions stay distinct', () {
    testWidgets('the primary is not offered as a secondary', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete));

      await tester.tap(secondaryField);
      await tester.pumpAndSettle();

      // The open menu holds None and the three positions that are not the
      // primary; 'Goalkeeper' remains only on the closed primary field behind
      // it.
      expect(find.text('Goalkeeper'), findsOneWidget);
      expect(find.text('Midfielder'), findsWidgets);
    });

    testWidgets('changing the primary to the chosen secondary clears it',
        (tester) async {
      final adapter = FakeProfileAdapter(profile: complete);
      await pumpProfile(tester, adapter);

      await choosePrimary(tester, 'Defender');

      expect(find.text('None'), findsOneWidget);
      await save(tester);

      expect(adapter.lastPrimaryPosition, PlayerPosition.def);
      expect(adapter.lastSecondaryPosition, isNull);
    });
  });

  group('localization', () {
    testWidgets('Arabic renders the screen in Arabic', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete),
          locale: const Locale('ar'));

      expect(find.text('تعديل الملف الشخصي'), findsOneWidget);
      expect(find.text('تاريخ الميلاد'), findsOneWidget);
      expect(find.text('المركز الثانوي (اختياري)'), findsOneWidget);
      expect(find.text('حارس مرمى'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('تاريخ الميلاد'))),
          TextDirection.rtl);
    });

    testWidgets('the saved message is Arabic too', (tester) async {
      await pumpProfile(tester, FakeProfileAdapter(profile: complete),
          locale: const Locale('ar'));

      await save(tester, label: 'حفظ');

      expect(find.text('تم تحديث الملف الشخصي.'), findsOneWidget);
    });
  });
}

/// The profile port, answering from memory and recording what it was handed.
class FakeProfileAdapter implements ProfileAdapter {
  FakeProfileAdapter({
    this.profile = const PlayerProfile(
      fullName: 'Salim Al Harthy',
      phone: '+96890123456',
      primaryPosition: PlayerPosition.mid,
    ),
    this.readFailure,
    this.writeFailure,
    this.gate,
  });

  final PlayerProfile profile;
  final Failure? readFailure;
  final Failure? writeFailure;

  /// Held open to keep the first load pending while the test looks at it.
  final Future<void>? gate;

  int reads = 0;
  int writes = 0;
  DateTime? lastDateOfBirth;
  PlayerPosition? lastPrimaryPosition;
  PlayerPosition? lastSecondaryPosition;

  int accountWrites = 0;
  String? lastFullName;
  String? lastPhone;

  int avatarUploads = 0;
  int avatarRemovals = 0;
  String? lastFileExtension;

  @override
  Future<PlayerProfile> fetchMyProfile() async {
    reads++;
    if (gate != null) await gate;
    if (readFailure != null) throw readFailure!;
    return profile;
  }

  @override
  Future<void> updateMyProfile({
    required DateTime dateOfBirth,
    required PlayerPosition primaryPosition,
    required PlayerPosition? secondaryPosition,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    writes++;
    lastDateOfBirth = dateOfBirth;
    lastPrimaryPosition = primaryPosition;
    lastSecondaryPosition = secondaryPosition;
  }

  @override
  Future<void> updateMyAccount({
    required String fullName,
    required String phone,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    accountWrites++;
    lastFullName = fullName;
    lastPhone = phone;
  }

  @override
  Future<String> uploadMyAvatar({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    avatarUploads++;
    lastFileExtension = fileExtension;
    return 'https://example.test/avatar.$fileExtension';
  }

  @override
  Future<void> removeMyAvatar() async => avatarRemovals++;

  // Requirement 2 added two members to the port. Neither is reached from this
  // test, so both refuse rather than answer.
  @override
  Future<PlayerProfileView> fetchPlayerProfile(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateMyPrivacy(ProfilePrivacy privacy) =>
      throw UnimplementedError();
}

/// The identity port, holding an email and recording the two credential
/// changes. Nothing else on this screen reaches it.
class FakeAuthAdapter implements AuthAdapter {
  FakeAuthAdapter({this.email = 'player@example.com'});

  final String email;

  String? changedEmail;
  String? changedPassword;

  @override
  String? get currentUserEmail => email;

  String? changedRedirect;

  @override
  Future<void> changeEmail(String value, {required String redirectTo}) async {
    changedEmail = value;
    changedRedirect = redirectTo;
  }

  @override
  Future<void> changePassword(String value) async => changedPassword = value;

  @override
  String? get currentUserId => 'u1';

  @override
  bool get isSignedIn => true;

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  Future<String?> fetchCurrentUserFullName() => throw UnimplementedError();

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}
