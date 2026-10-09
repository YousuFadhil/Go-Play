import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/auth/auth_models.dart';
import 'package:go_play/features/profile/current_user.dart';
import 'package:go_play/features/profile/profile_adapter.dart';
import 'package:go_play/features/profile/profile_models.dart';
import 'package:go_play/features/profile/profile_repository.dart';
import 'package:go_play/features/support/admin_support_phone_screen.dart';
import 'package:go_play/features/support/support_adapter.dart';
import 'package:go_play/features/support/support_contact_screen.dart';
import 'package:go_play/features/support/support_repository.dart';
import 'package:go_play/features/support/support_whatsapp_link.dart';
import 'package:go_play/l10n/generated/app_localizations_ar.dart';
import 'package:go_play/l10n/generated/app_localizations_en.dart';

class _SupportFake implements SupportAdapter {
  _SupportFake(this.phone);

  String? phone;
  int updates = 0;

  @override
  Future<String?> fetchWhatsAppPhone() async => phone;

  @override
  Future<void> setWhatsAppPhone(String? value) async {
    updates++;
    phone = value;
  }
}

class _ProfileFake implements ProfileAdapter {
  @override
  Future<PlayerProfile> fetchMyProfile() async => const PlayerProfile(
        fullName: 'Test Player',
        phone: '+96890000000',
        primaryPosition: PlayerPosition.mid,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(() {
    CurrentUser.instance.useRepository(ProfileRepository(_ProfileFake()));
  });

  tearDown(() {
    CurrentUser.instance.useRepository(null);
  });

  test('accepts international E164 digits and refuses invalid input', () {
    expect(SupportWhatsAppLink.normalizePhone('+96891234567'), '96891234567');
    expect(SupportWhatsAppLink.normalizePhone('96891234567'), '96891234567');
    expect(SupportWhatsAppLink.normalizePhone(''), isNull);
    expect(SupportWhatsAppLink.normalizePhone('abc'), isNull);
    expect(SupportWhatsAppLink.normalizePhone('0123456789'), isNull);
  });

  test('wa.me link contains the selected topic and user text', () {
    final uri = SupportWhatsAppLink.build(
      phone: '+96891234567',
      reason: 'Technical issue',
      message: 'Cannot sign in',
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/96891234567');
    expect(uri.queryParameters['text'],
        'Go Play — Technical issue\nCannot sign in');
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Locale locale = const Locale('en'),
    Size size = const Size(900, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('unconfigured number prevents opening WhatsApp', (tester) async {
    final port = _SupportFake(null);
    var opened = 0;
    await pump(
        tester,
        SupportContactScreen(
          repository: SupportRepository(port),
          openWhatsApp: (uri) async {
            opened++;
            return true;
          },
        ));

    expect(
        find.text(
            'The support number is not configured yet. Please try again later.'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('openWhatsAppSupport')),
    );
    expect(button.onPressed, isNull);
    expect(opened, 0);
  });

  testWidgets('message is handed to WhatsApp only after user taps',
      (tester) async {
    final port = _SupportFake('96891234567');
    Uri? captured;
    await pump(
        tester,
        SupportContactScreen(
          repository: SupportRepository(port),
          openWhatsApp: (uri) async {
            captured = uri;
            return true;
          },
        ));

    final button = find.byKey(const Key('openWhatsAppSupport'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, 'Please help');
    await tester.pump();
    expect(captured, isNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(captured!.path, '/96891234567');
    expect(captured!.queryParameters['text'], contains('Please help'));
  });

  testWidgets('system admin form validates, saves, and clears number',
      (tester) async {
    final port = _SupportFake(null);
    await pump(
        tester, AdminSupportPhoneScreen(repository: SupportRepository(port)));

    final field = find.byType(TextField);
    final save = find.byKey(const Key('saveSupportPhone'));
    await tester.enterText(field, 'not-a-phone');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(port.updates, 0);

    await tester.enterText(field, '+96891234567');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(port.phone, '96891234567');

    await tester.enterText(field, '');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(port.phone, isNull);
    expect(port.updates, 2);
  });

  test('the link is percent-encoded and user text cannot add parameters', () {
    final uri = SupportWhatsAppLink.build(
      phone: '96891234567',
      reason: 'Question',
      message: 'Rate 5+5 & 100% sure? #1\nthanks',
    );

    expect(uri.query, isNot(contains('+')),
        reason: 'a space is %20 and a literal plus is %2B');
    expect(uri.query, contains('%20'));
    expect(uri.query, contains('%0A'));
    expect(uri.query, contains('5%2B5'));
    expect(uri.query, contains('%26'));
    expect(uri.query, contains('%23'));
    expect(uri.queryParametersAll.keys, ['text']);
    expect(Uri.parse(uri.toString()).queryParameters['text'],
        endsWith('Rate 5+5 & 100% sure? #1\nthanks'));
  });

  testWidgets('a malformed stored number counts as not configured',
      (tester) async {
    await pump(
      tester,
      SupportContactScreen(
        repository: SupportRepository(_SupportFake('0123')),
        openWhatsApp: (_) async => true,
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();

    expect(find.text(AppLocalizationsEn().supportPhoneNotConfigured),
        findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('openWhatsAppSupport')))
          .onPressed,
      isNull,
    );
  });

  final launchFailures = <String, Future<bool> Function(Uri)>{
    'WhatsApp reports it could not open': (_) async => false,
    'the platform throws': (_) async => throw Exception('no handler'),
  };
  for (final failure in launchFailures.entries) {
    testWidgets('launch failure (${failure.key}) is a message, then recovers',
        (tester) async {
      await pump(
        tester,
        SupportContactScreen(
          repository: SupportRepository(_SupportFake('96891234567')),
          openWhatsApp: failure.value,
        ),
      );
      final open = find.byKey(const Key('openWhatsAppSupport'));
      await tester.enterText(find.byType(TextField).first, 'Please help');
      await tester.pump();
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(find.text(AppLocalizationsEn().supportOpenFailed), findsOneWidget);
      expect(tester.widget<FilledButton>(open).onPressed, isNotNull,
          reason: 'the user can try again');
    });
  }

  testWidgets('Arabic RTL builds at 320px and keeps the phone field LTR',
      (tester) async {
    final ar = AppLocalizationsAr();
    await pump(
      tester,
      SupportContactScreen(
        repository: SupportRepository(_SupportFake('96891234567')),
        openWhatsApp: (_) async => true,
      ),
      locale: const Locale('ar'),
      size: const Size(320, 640),
    );
    expect(find.text(ar.supportContactTitle), findsWidgets);
    expect(find.text(ar.supportOpenWhatsApp), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pump(
      tester,
      AdminSupportPhoneScreen(
          repository: SupportRepository(_SupportFake('96891234567'))),
      locale: const Locale('ar'),
      size: const Size(320, 640),
    );
    expect(find.text(ar.supportAdminPhoneTitle), findsWidgets);
    expect(tester.takeException(), isNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textDirection, TextDirection.ltr,
        reason: 'else the leading + is drawn after the digits in RTL');
  });
}
