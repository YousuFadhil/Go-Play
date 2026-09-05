import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_adapter.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/auth/auth_service.dart';
import 'package:go_play/features/auth/register_screen.dart';

/// The registration screen against a fake identity port.
///
/// What is asserted is the screen's own behaviour: which fields it insists on,
/// what it hands to `AuthService.register`, and how the two positions are kept
/// distinct. The rules themselves live in `AuthService` and are covered in
/// `repository_behaviour_test.dart`; nothing here re-asserts them.
///
/// Every test drives the real `AuthService` with a fake adapter underneath, so
/// the path from the form to the port is the production one.
void main() {
  Future<void> pumpRegister(
    WidgetTester tester,
    FakeAuthAdapter adapter, {
    Locale locale = const Locale('en'),
  }) async {
    // A surface tall enough for the whole form. The default 800x600 leaves the
    // button below the fold, which is a fact about the test window rather than
    // about the screen — the screen scrolls.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: RegisterScreen(authService: AuthService(adapter)),
    ));
    await tester.pumpAndSettle();
  }

  /// Fills everything except the two profile inputs each test then chooses.
  Future<void> fillIdentity(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'Sara Al Balushi');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'sara@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), '90123456');
    await tester.enterText(find.byType(TextFormField).at(3), 'password1');
  }

  /// Picks a date of birth by accepting the date the picker opens on — 25 years
  /// ago today, which is what the field offers when nothing is chosen yet.
  Future<void> pickDateOfBirth(WidgetTester tester) async {
    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  DateTime defaultOfferedDate() {
    final now = DateTime.now();
    return DateTime(now.year - 25, now.month, now.day);
  }

  // The two dropdowns, told apart by what they hold rather than by their
  // labels: a floating label is not reliably the tap target of its own field.
  final primaryField = find.byType(DropdownButtonFormField<PlayerPosition>);
  final secondaryField = find.byType(DropdownButtonFormField<PlayerPosition?>);

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

  /// The button, not the app-bar title of the same name.
  Future<void> submit(WidgetTester tester, {String label = 'Create account'}) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  group('what the form asks for', () {
    testWidgets('the profile fields are on the screen', (tester) async {
      await pumpRegister(tester, FakeAuthAdapter());

      expect(find.text('Date of birth'), findsOneWidget);
      expect(find.text('Primary position'), findsOneWidget);
      expect(find.text('Secondary position (optional)'), findsOneWidget);
      expect(find.text('Select date'), findsOneWidget);
    });

    testWidgets('the rating is not among them (OP-1)', (tester) async {
      // It is system-managed and initialised by the database at 5.0. Nothing on
      // this screen asks for it, so nothing can send one.
      await pumpRegister(tester, FakeAuthAdapter());

      expect(find.textContaining('Rating'), findsNothing);
      expect(find.textContaining('rating'), findsNothing);
    });
  });

  group('registering', () {
    testWidgets('succeeds with a date of birth and a primary position',
        (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await choosePrimary(tester, 'Midfielder');
      await submit(tester);

      expect(adapter.signUpCount, 1);
      expect(adapter.lastDateOfBirth, defaultOfferedDate());
      expect(adapter.lastPosition, PlayerPosition.mid);
      expect(adapter.lastSecondaryPosition, isNull);
    });

    testWidgets('succeeds with a secondary position', (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await choosePrimary(tester, 'Goalkeeper');
      await chooseSecondary(tester, 'Defender');
      await submit(tester);

      expect(adapter.signUpCount, 1);
      expect(adapter.lastPosition, PlayerPosition.gk);
      expect(adapter.lastSecondaryPosition, PlayerPosition.def);
    });

    testWidgets('succeeds without one, and says so rather than leaving it '
        'blank', (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await choosePrimary(tester, 'Forward');
      expect(find.text('None'), findsOneWidget,
          reason: 'no secondary position is an offered choice, not an empty '
              'field the player has to interpret');
      await submit(tester);

      expect(adapter.signUpCount, 1);
      expect(adapter.lastSecondaryPosition, isNull);
    });

    testWidgets('the whole profile reaches the port as it was entered',
        (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await choosePrimary(tester, 'Defender');
      await chooseSecondary(tester, 'Midfielder');
      await submit(tester);

      expect(adapter.lastEmail, 'sara@example.com');
      expect(adapter.lastFullName, 'Sara Al Balushi');
      expect(adapter.lastPhone, '+96890123456',
          reason: 'the Oman phone behaviour is unchanged');
      expect(adapter.lastPosition, PlayerPosition.def);
      expect(adapter.lastSecondaryPosition, PlayerPosition.mid);
      expect(adapter.lastDateOfBirth, defaultOfferedDate());
      expect(adapter.lastDateOfBirth!.hour, 0,
          reason: 'a date, not a timestamp');
    });
  });

  group('what the form refuses', () {
    testWidgets('a missing date of birth stops the registration before the '
        'port is reached', (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await choosePrimary(tester, 'Midfielder');
      await submit(tester);

      expect(find.text('Date of birth is required'), findsOneWidget);
      expect(adapter.signUpCount, 0);
    });

    testWidgets('a missing primary position stops it too', (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await submit(tester);

      expect(find.text('Primary position is required'), findsOneWidget);
      expect(adapter.signUpCount, 0);
    });

    testWidgets('a date of birth in the future is never offered',
        (tester) async {
      await pumpRegister(tester, FakeAuthAdapter());

      await tester.tap(find.text('Select date'));
      await tester.pumpAndSettle();

      final picker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog));
      expect(picker.lastDate.isAfter(DateTime.now()), isFalse,
          reason: 'a birthday that has not happened yet cannot be picked');
    });
  });

  group('the two positions stay distinct', () {
    testWidgets('the primary is not offered as a secondary', (tester) async {
      await pumpRegister(tester, FakeAuthAdapter());
      await choosePrimary(tester, 'Goalkeeper');

      await tester.tap(secondaryField);
      await tester.pumpAndSettle();

      // The open menu holds None and the three positions that are not the
      // primary. 'Goalkeeper' remains once — on the closed primary field
      // behind the menu — and not as an option within it.
      expect(find.text('Defender'), findsWidgets);
      expect(find.text('Goalkeeper'), findsOneWidget);
    });

    testWidgets('changing the primary to the chosen secondary clears it',
        (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await choosePrimary(tester, 'Goalkeeper');
      await chooseSecondary(tester, 'Defender');
      await choosePrimary(tester, 'Defender');

      expect(find.text('None'), findsOneWidget,
          reason: 'a secondary that has become the primary is no longer a '
              'second choice');

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await submit(tester);

      expect(adapter.signUpCount, 1);
      expect(adapter.lastPosition, PlayerPosition.def);
      expect(adapter.lastSecondaryPosition, isNull);
    });

    testWidgets('changing the primary to something else keeps the secondary',
        (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter);

      await choosePrimary(tester, 'Goalkeeper');
      await chooseSecondary(tester, 'Defender');
      await choosePrimary(tester, 'Midfielder');

      await fillIdentity(tester);
      await pickDateOfBirth(tester);
      await submit(tester);

      expect(adapter.lastPosition, PlayerPosition.mid);
      expect(adapter.lastSecondaryPosition, PlayerPosition.def,
          reason: 'nothing was wrong with it, so nothing clears it');
    });
  });

  group('localization', () {
    testWidgets('Arabic renders the new fields in Arabic', (tester) async {
      await pumpRegister(tester, FakeAuthAdapter(), locale: const Locale('ar'));

      expect(find.text('تاريخ الميلاد'), findsOneWidget);
      expect(find.text('المركز الثانوي (اختياري)'), findsOneWidget);
      expect(find.text('اختر التاريخ'), findsOneWidget);
    });

    testWidgets('the required-date message is Arabic too', (tester) async {
      final adapter = FakeAuthAdapter();
      await pumpRegister(tester, adapter, locale: const Locale('ar'));

      await fillIdentity(tester);
      await submit(tester, label: 'إنشاء الحساب');

      expect(find.text('تاريخ الميلاد مطلوب'), findsOneWidget);
      expect(adapter.signUpCount, 0);
    });
  });
}

/// The identity port, answering from memory and recording what it was handed.
/// Methods the screen never reaches are left unimplemented on purpose.
class FakeAuthAdapter implements AuthAdapter {
  int signUpCount = 0;
  String? lastEmail;
  String? lastFullName;
  String? lastPhone;
  PlayerPosition? lastPosition;
  PlayerPosition? lastSecondaryPosition;
  DateTime? lastDateOfBirth;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required PlayerPosition position,
    required String phone,
    required DateTime dateOfBirth,
    required PlayerPosition? secondaryPosition,
  }) async {
    signUpCount++;
    lastEmail = email;
    lastFullName = fullName;
    lastPhone = phone;
    lastPosition = position;
    lastSecondaryPosition = secondaryPosition;
    lastDateOfBirth = dateOfBirth;
  }

  @override
  String? get currentUserId => null;

  @override
  String? get currentUserEmail => null;

  @override
  Future<void> changeEmail(String email, {required String redirectTo}) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(String password) => throw UnimplementedError();

  @override
  bool get isSignedIn => false;

  @override
  Stream<bool> get signedInChanges => const Stream.empty();

  @override
  Future<String?> fetchCurrentUserFullName() => throw UnimplementedError();

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<bool> isCurrentUserActive() async => true;

  @override
  Future<void> signOut() => throw UnimplementedError();
}
