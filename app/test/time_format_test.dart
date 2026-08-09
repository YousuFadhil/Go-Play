import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/time_format.dart';

/// Clock times are 12-hour everywhere, whatever the device is set to, and a
/// range keeps its start-then-end order in a right-to-left layout.
///
/// The device preference is still supplied to every case below — that is the
/// point. It used to decide the format; it no longer decides anything, and the
/// only way to hold that is to keep passing both settings and assert the answer
/// does not move.
void main() {
  /// Pumps [builder] inside a localized app with the given device preference,
  /// which `formatTime` deliberately no longer reads.
  Future<String> render(
    WidgetTester tester, {
    required bool use24Hour,
    required Locale locale,
    required String Function(BuildContext) build,
  }) async {
    late String result;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: use24Hour,
          ),
          child: child!,
        ),
        home: Builder(builder: (context) {
          result = build(context);
          return const SizedBox.shrink();
        }),
      ),
    );
    await tester.pump();
    return result;
  }

  /// CLDR separates the time from its meridiem with U+202F NARROW NO-BREAK
  /// SPACE, which is correct typography and invisible in a failure message —
  /// two strings that look identical would otherwise compare unequal. Asserting
  /// on the normalized form keeps these tests about the format rather than
  /// about which space character ICU shipped this year.
  String plain(String value) =>
      value.replaceAll(' ', ' ').replaceAll(' ', ' ');

  final morning = DateTime(2026, 8, 1, 8, 15);
  final evening = DateTime(2026, 8, 1, 20, 30);
  final night = DateTime(2026, 8, 1, 22, 30);

  group('formatTime', () {
    testWidgets('a device set to 24 hours still gets 12-hour time',
        (tester) async {
      final text = await render(tester,
          use24Hour: true,
          locale: const Locale('en'),
          build: (context) => formatTime(context, evening));

      expect(plain(text), '8:30 PM');
      expect(text, isNot(contains('20:30')),
          reason: 'the device preference no longer decides the format');
    });

    testWidgets('a device set to 12 hours gets the same thing',
        (tester) async {
      final text = await render(tester,
          use24Hour: false,
          locale: const Locale('en'),
          build: (context) => formatTime(context, evening));

      expect(plain(text), '8:30 PM');
    });

    testWidgets('morning reads as AM', (tester) async {
      final text = await render(tester,
          use24Hour: true,
          locale: const Locale('en'),
          build: (context) => formatTime(context, morning));

      expect(plain(text), '8:15 AM');
    });

    testWidgets('Arabic is 12-hour with an Arabic meridiem', (tester) async {
      final twelve = await render(tester,
          use24Hour: false,
          locale: const Locale('ar'),
          build: (context) => formatTime(context, evening));
      final twentyFour = await render(tester,
          use24Hour: true,
          locale: const Locale('ar'),
          build: (context) => formatTime(context, evening));

      // The device no longer changes anything.
      expect(twelve, twentyFour);
      // The locale still decides the wording: م for the afternoon, and never
      // the English meridiem.
      expect(twelve, contains('م'));
      expect(twelve, isNot(contains('PM')));
      expect(twelve, contains('8:30'));
    });
  });

  group('formatTimeRange', () {
    testWidgets('reads start then end, isolated left-to-right',
        (tester) async {
      final text = await render(tester,
          use24Hour: true,
          locale: const Locale('ar'),
          build: (context) => formatTimeRange(context, evening, night));

      expect(text.startsWith(String.fromCharCode(0x2066)), isTrue,
          reason: 'without the isolate an RTL layout reverses the range');
      expect(text.endsWith(String.fromCharCode(0x2069)), isTrue);
      // Start really does come before end inside the isolate.
      expect(text.indexOf('8:30'), lessThan(text.indexOf('10:30')));
    });

    testWidgets('the range is 12-hour on both ends', (tester) async {
      final text = await render(tester,
          use24Hour: true,
          locale: const Locale('en'),
          build: (context) => formatTimeRange(context, evening, night));

      expect(plain(text), contains('8:30 PM'));
      expect(plain(text), contains('10:30 PM'));
    });
  });
}
