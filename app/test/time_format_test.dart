import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/time_format.dart';

/// Time display follows the device, not a hardcoded format, and a range keeps
/// its start-then-end order in a right-to-left layout.
void main() {
  /// Pumps [builder] inside a localized app with the given device preference,
  /// which is the input `TimeOfDay.format` actually reads.
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

  final evening = DateTime(2026, 8, 1, 20, 30);
  final night = DateTime(2026, 8, 1, 22, 30);

  group('formatTime', () {
    testWidgets('a device set to 24 hours keeps 24-hour time', (tester) async {
      final text = await render(tester,
          use24Hour: true,
          locale: const Locale('en'),
          build: (context) => formatTime(context, evening));
      expect(text, '20:30');
    });

    testWidgets('a device set to 12 hours gets 12-hour time', (tester) async {
      final text = await render(tester,
          use24Hour: false,
          locale: const Locale('en'),
          build: (context) => formatTime(context, evening));
      expect(text, contains('8:30'));
      expect(text, isNot(contains('20:30')),
          reason: '24-hour must not be hardcoded');
    });

    testWidgets('Arabic follows the same device preference', (tester) async {
      final twelve = await render(tester,
          use24Hour: false,
          locale: const Locale('ar'),
          build: (context) => formatTime(context, evening));
      final twentyFour = await render(tester,
          use24Hour: true,
          locale: const Locale('ar'),
          build: (context) => formatTime(context, evening));
      expect(twelve, isNot(twentyFour),
          reason: 'the locale does not decide this; the device does');
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
      expect(text.indexOf('20:30'), lessThan(text.indexOf('22:30')));
    });

    testWidgets('the range respects the device preference too', (tester) async {
      final text = await render(tester,
          use24Hour: false,
          locale: const Locale('en'),
          build: (context) => formatTimeRange(context, evening, night));
      expect(text, contains('8:30'));
      expect(text, contains('10:30'));
    });
  });
}
