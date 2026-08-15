import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_play/core/failures.dart';
import 'package:go_play/core/l10n.dart';
import 'package:go_play/features/sharing/share_card_canvas.dart';
import 'package:go_play/features/sharing/share_card_flow.dart';
import 'package:go_play/features/sharing/share_card_preview_screen.dart';
import 'package:go_play/features/sharing/share_card_renderer.dart';
import 'package:go_play/features/sharing/share_service.dart';
import 'package:go_play/features/sharing/widget_share_card_renderer.dart';

/// The Share Card Engine, against fakes.
///
/// The engine has three parts and they are tested as three, because they fail
/// for unrelated reasons: the canvas is a contract about a shape, the capture
/// is imaging, and the preview is a screen. What is asserted throughout is that
/// none of them knows what a card is a picture of — the whole point of building
/// this before any of the three templates that will use it.
void main() {
  /// A neutral card. Deliberately not a player, a community or a lineup: this
  /// suite must not be the place any of those first appear, and a template made
  /// of two coloured boxes proves the same things about the engine.
  Widget neutralTemplate(BuildContext context) => const Column(
        children: [
          Expanded(child: ColoredBox(color: Color(0xFF1B5E20))),
          Expanded(child: ColoredBox(color: Color(0xFFF5F5F5))),
        ],
      );

  // --- 1. the 9:16 contract ---------------------------------------------------

  group('the canvas is 9:16 and says so once', () {
    test('the ratio is nine over sixteen', () {
      expect(ShareCardCanvas.widthUnits, 9);
      expect(ShareCardCanvas.heightUnits, 16);
      expect(ShareCardCanvas.aspectRatio, closeTo(0.5625, 1e-9));
    });

    test('the design canvas is portrait and is that ratio', () {
      const size = ShareCardCanvas.designSize;
      expect(size.height, greaterThan(size.width),
          reason: 'the master format is a portrait Story');
      expect(ShareCardCanvas.isShareCardShape(size), isTrue);
      expect(size, const Size(1080, 1920));
    });

    test('a shape that is not 9:16 is refused', () {
      // The formats explicitly out of scope this cycle, plus the landscape of
      // the same ratio -- 16:9 is not 9:16, and a check on the ratio alone
      // without regard to which side is longer would accept it.
      expect(ShareCardCanvas.isShareCardShape(const Size(1080, 1350)), isFalse,
          reason: '4:5 is not this cycle');
      expect(ShareCardCanvas.isShareCardShape(const Size(1080, 1080)), isFalse,
          reason: '1:1 is not this cycle');
      expect(ShareCardCanvas.isShareCardShape(const Size(1920, 1080)), isFalse,
          reason: 'landscape is not this cycle');
      expect(ShareCardCanvas.isShareCardShape(Size.zero), isFalse);
    });

    test('a capture rounded by a pixel is still the right shape', () {
      // Real output lands on whole pixels, so the contract has to survive one.
      expect(ShareCardCanvas.isShareCardShape(const Size(1081, 1920)), isTrue);
    });
  });

  group('the surface makes two devices produce one card', () {
    /// The unbounded room the renderer gives a card. Without it a `Stack` hands
    /// the surface the phone's size as its maximum and the card is silently
    /// squeezed -- which is the bug this test exists to keep fixed.
    Widget unbounded(Widget child) => OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: child,
        );

    testWidgets('it is laid out at the design size, not the screen size',
        (tester) async {
      // A small phone: smaller in both directions than the card it composes.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late Size seenByTemplate;
      await tester.pumpWidget(MaterialApp(
        home: unbounded(ShareCardSurface(
          child: Builder(builder: (context) {
            seenByTemplate = MediaQuery.sizeOf(context);
            return const SizedBox.expand();
          }),
        )),
      ));

      expect(tester.getSize(find.byType(ShareCardSurface)),
          ShareCardCanvas.designSize);
      expect(
        ShareCardCanvas.isShareCardShape(
            tester.getSize(find.byType(ShareCardSurface))),
        isTrue,
      );
      // And a template asking where it is gets the card, not the phone.
      expect(seenByTemplate, ShareCardCanvas.designSize);
    });

    testWidgets('the reader\'s text scale does not reflow the card',
        (tester) async {
      // Someone who has turned system text up wants the app larger, not the
      // picture they are about to send to other people rearranged.
      late TextScaler scaler;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.4)),
          child: Align(
            alignment: Alignment.topLeft,
            child: ShareCardSurface(
              child: Builder(builder: (context) {
                scaler = MediaQuery.textScalerOf(context);
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      ));

      expect(scaler.scale(10), 10);
    });

    testWidgets('reading direction is inherited, so Arabic composes RTL',
        (tester) async {
      late TextDirection direction;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Align(
          alignment: Alignment.topLeft,
          child: ShareCardSurface(
            child: Builder(builder: (context) {
              direction = Directionality.of(context);
              return const SizedBox.expand();
            }),
          ),
        ),
      ));

      expect(direction, TextDirection.rtl);
    });
  });

  // --- 2 & 3. the capture produces a real image, at the right size -------------

  group('capturing a card', () {
    /// Mounts the surface and hands back its boundary.
    Future<RenderRepaintBoundary> mountCard(WidgetTester tester) async {
      final key = GlobalKey();
      tester.view.physicalSize = const Size(2400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ShareCardSurface(child: Builder(builder: neutralTemplate)),
          ),
        ),
      ));
      await tester.pump();
      return key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    }

    testWidgets('it produces a real PNG', (tester) async {
      final boundary = await mountCard(tester);

      final card = await tester.runAsync(() => captureShareCard(boundary));

      expect(card, isNotNull);
      expect(card!.bytes, isNotEmpty);
      expect(card.mimeType, 'image/png');
      // The PNG signature, so this is an encoded image rather than any bytes at
      // all: \x89 P N G \r \n \x1a \n.
      expect(card.bytes.sublist(0, 8),
          orderedEquals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
      expect(card.fileName, endsWith('.png'));
    });

    testWidgets('the output is the design size, and is 9:16', (tester) async {
      final boundary = await mountCard(tester);

      final card = await tester.runAsync(() => captureShareCard(boundary));

      expect(card!.pixelWidth, ShareCardCanvas.designSize.width.round());
      expect(card.pixelHeight, ShareCardCanvas.designSize.height.round());
      expect(card.aspectRatio, closeTo(ShareCardCanvas.aspectRatio, 1e-9));
      expect(card.isShareCardShape, isTrue);
    });

    testWidgets('a higher density is a bigger image of the same shape',
        (tester) async {
      final boundary = await mountCard(tester);

      final card =
          await tester.runAsync(() => captureShareCard(boundary, pixelRatio: 2));

      expect(card!.pixelWidth, (ShareCardCanvas.designSize.width * 2).round());
      expect(card.pixelHeight, (ShareCardCanvas.designSize.height * 2).round());
      expect(card.isShareCardShape, isTrue,
          reason: 'density changes the pixels, never the format');
    });

    testWidgets('the caller names the file, and it reaches the result',
        (tester) async {
      final boundary = await mountCard(tester);

      final card = await tester.runAsync(
          () => captureShareCard(boundary, fileName: 'chosen-name.png'));

      expect(card!.fileName, 'chosen-name.png');
    });
  });

  // --- 7. error handling when generation fails --------------------------------

  group('when a card cannot be composed', () {
    testWidgets('a boundary that was never laid out is an InfrastructureFailure',
        (tester) async {
      // Nothing mounted it, so it has no size and there is nothing to encode.
      // The engine's own exception stays inside the engine (OP-5).
      final orphan = RenderRepaintBoundary();

      await expectLater(
        () => captureShareCard(orphan),
        throwsA(isA<InfrastructureFailure>()),
      );
    });

    testWidgets('a density of zero is refused before the engine is asked',
        (tester) async {
      final orphan = RenderRepaintBoundary();

      expect(() => captureShareCard(orphan, pixelRatio: 0),
          throwsA(isA<ArgumentError>()));
      expect(() => captureShareCard(orphan, pixelRatio: -1),
          throwsA(isA<ArgumentError>()));
    });
  });

  // --- the renderer mounts a card and always takes it back out ----------------

  group('the widget renderer', () {
    /// Pumps an app on a phone smaller than the card it composes, and hands
    /// back its overlay. The size matters: an overlay hands a positioned child
    /// the screen as its maximum, so this is the case where a card would be
    /// squeezed out of shape if the renderer did not ask for unbounded room.
    Future<OverlayState> pumpHost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
      return tester.state<OverlayState>(find.byType(Overlay).first);
    }

    testWidgets('it composes through the capture and returns the card',
        (tester) async {
      final overlay = await pumpHost(tester);
      RenderRepaintBoundary? captured;
      double? seenRatio;

      final renderer = WidgetShareCardRenderer(
        overlay,
        awaitFrame: () async => tester.pump(),
        capture: (boundary, {double pixelRatio = 1.0, String fileName = ''}) async {
          captured = boundary;
          seenRatio = pixelRatio;
          return _card();
        },
      );

      final card = await renderer.render(neutralTemplate, pixelRatio: 3);

      expect(card.pixelWidth, 9);
      expect(seenRatio, 3);
      // What it handed the capture was a boundary that had actually been laid
      // out at the design size -- the card was mounted, not merely built, and
      // it kept its shape on a phone smaller than itself.
      expect(captured!.hasSize, isTrue);
      expect(captured!.size, ShareCardCanvas.designSize);
      expect(ShareCardCanvas.isShareCardShape(captured!.size), isTrue);
    });

    testWidgets('the card is taken out of the overlay afterwards',
        (tester) async {
      final overlay = await pumpHost(tester);
      final renderer = WidgetShareCardRenderer(
        overlay,
        awaitFrame: () async => tester.pump(),
        capture: (boundary, {double pixelRatio = 1.0, String fileName = ''}) async =>
            _card(),
      );

      await renderer.render(neutralTemplate);
      await tester.pump();

      expect(find.byType(ShareCardSurface), findsNothing,
          reason: 'an invisible card left in the overlay would rebuild above '
              'every screen for the rest of the session');
    });

    testWidgets('and taken out even when composing fails', (tester) async {
      final overlay = await pumpHost(tester);
      final renderer = WidgetShareCardRenderer(
        overlay,
        awaitFrame: () async => tester.pump(),
        capture: (boundary, {double pixelRatio = 1.0, String fileName = ''}) async =>
            throw const InfrastructureFailure(),
      );

      await expectLater(
        () => renderer.render(neutralTemplate),
        throwsA(isA<InfrastructureFailure>()),
      );
      await tester.pump();

      expect(find.byType(ShareCardSurface), findsNothing,
          reason: 'a failed compose is exactly when a card is easiest to leave '
              'behind');
    });

    testWidgets('the card is composed where nobody sees it', (tester) async {
      final overlay = await pumpHost(tester);
      final renderer = WidgetShareCardRenderer(
        overlay,
        awaitFrame: () async => tester.pump(),
        capture: (boundary, {double pixelRatio = 1.0, String fileName = ''}) async {
          // Mid-compose: the card is mounted, and entirely off the screen.
          final origin = boundary.localToGlobal(Offset.zero);
          expect(origin.dx + ShareCardCanvas.designSize.width, lessThan(0));
          expect(origin.dy + ShareCardCanvas.designSize.height, lessThan(0));
          return _card();
        },
      );

      await renderer.render(neutralTemplate);
    });
  });

  // --- 4. the preview keeps the shape -----------------------------------------

  group('the preview', () {
    Future<void> pumpPreview(
      WidgetTester tester, {
      ShareService? shareService,
      Locale locale = const Locale('en'),
      Size size = const Size(400, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ShareCardPreviewScreen(
          image: _card(),
          shareService: shareService,
        ),
      ));
      await tester.pump();
    }

    testWidgets('it reserves 9:16 and fits inside the screen', (tester) async {
      await pumpPreview(tester);

      final ratio = tester.widget<AspectRatio>(find.descendant(
        of: find.byType(ShareCardPreviewImage),
        matching: find.byType(AspectRatio),
      ));
      expect(ratio.aspectRatio, ShareCardCanvas.aspectRatio);

      // And the space it actually occupies is that shape, and is on-screen.
      final box = tester.getSize(find.byType(AspectRatio).first);
      expect(ShareCardCanvas.isShareCardShape(box), isTrue);
      expect(box.height, lessThanOrEqualTo(800));
      expect(box.width, lessThanOrEqualTo(400));
    });

    testWidgets('a tall narrow phone still fits the whole card', (tester) async {
      await pumpPreview(tester, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(AspectRatio).first);
      expect(ShareCardCanvas.isShareCardShape(box), isTrue);
      expect(box.width, lessThanOrEqualTo(320));
    });

    testWidgets('the picture is shown whole rather than cropped to fill',
        (tester) async {
      // The reader is checking what they are about to send.
      await pumpPreview(tester);

      final image = tester.widget<Image>(find.descendant(
        of: find.byType(ShareCardPreviewImage),
        matching: find.byType(Image),
      ));
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('it offers exactly a Share and a Close, and no editor',
        (tester) async {
      await pumpPreview(tester);

      expect(find.text('Share'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      // Presentation only: nothing to type into, nothing to adjust.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('Arabic renders the preview in Arabic', (tester) async {
      await pumpPreview(tester, locale: const Locale('ar'));

      expect(find.text('بطاقة المشاركة'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('مشاركة'))),
        TextDirection.rtl,
      );
    });
  });

  // --- 5 & 8. the share service gets the card; failure and cancel --------------

  group('sending the card', () {
    Future<void> pumpPreview(
      WidgetTester tester,
      FakeShareService share, {
      ShareCardImage? image,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ShareCardPreviewScreen(
          image: image ?? _card(),
          shareService: share,
        ),
      ));
      await tester.pump();
    }

    testWidgets('Share hands the generated card to the service exactly once',
        (tester) async {
      final share = FakeShareService();
      final card = _card(fileName: 'the-card.png');
      await pumpPreview(tester, share, image: card);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(share.shared, hasLength(1));
      // The same artifact, not a re-encoded or re-wrapped one.
      expect(identical(share.shared.single, card), isTrue);
      expect(share.shared.single.fileName, 'the-card.png');
      expect(share.shared.single.bytes, card.bytes);
    });

    testWidgets('a dismissed sheet says nothing at all', (tester) async {
      // The reader closed it themselves. Nothing failed and nothing is news.
      final share = FakeShareService(outcome: ShareOutcome.dismissed);
      await pumpPreview(tester, share);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an outcome the platform cannot report says nothing either',
        (tester) async {
      // Android answers this for most shares. It is the common case.
      final share = FakeShareService(outcome: ShareOutcome.unknown);
      await pumpPreview(tester, share);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a sheet that could not be shown is reported', (tester) async {
      final share = FakeShareService(failure: const InfrastructureFailure());
      await pumpPreview(tester, share);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text('Sharing is not available right now.'), findsOneWidget);
    });

    testWidgets('a connectivity failure keeps the app\'s own wording',
        (tester) async {
      // By failure type, never by reason (OP-5).
      final share = FakeShareService(failure: const NetworkFailure());
      await pumpPreview(tester, share);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text('Sharing is not available right now.'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a failed share leaves the button usable again', (tester) async {
      final share = FakeShareService(failure: const InfrastructureFailure());
      await pumpPreview(tester, share);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      // The button is live again rather than stuck disabled by the guard that
      // stops a second sheet being asked for while the first is opening.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull, reason: 'a refusal is not a dead end');

      // And it can actually be pressed again. The floating snack bar sits over
      // the button, so it is dismissed first -- the reader would simply wait.
      ScaffoldMessenger.of(tester.element(find.byType(FilledButton)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(share.attempts, 2);
    });
  });

  // --- the flow: compose, preview, and what happens when composing fails -------

  group('the flow a feature calls', () {
    Future<void> pumpFlow(
      WidgetTester tester, {
      required ShareCardRenderer renderer,
      ShareService? share,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => presentShareCard(
                context,
                template: neutralTemplate,
                renderer: renderer,
                shareService: share,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
    }

    testWidgets('a composed card is shown in the preview', (tester) async {
      await pumpFlow(tester, renderer: FakeRenderer());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardPreviewScreen), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('the reader is told a card is being made', (tester) async {
      final renderer = FakeRenderer(hold: true);
      await pumpFlow(tester, renderer: renderer);

      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.text('Preparing your card…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      renderer.release();
      await tester.pumpAndSettle();
      expect(find.text('Preparing your card…'), findsNothing);
    });

    testWidgets('a compose that fails reports it and opens no preview',
        (tester) async {
      await pumpFlow(
        tester,
        renderer: FakeRenderer(failure: const InfrastructureFailure()),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardPreviewScreen), findsNothing);
      expect(find.text('The card could not be created. Please try again.'),
          findsOneWidget);
      // And the barrier is gone rather than left over the screen.
      expect(find.text('Preparing your card…'), findsNothing);
    });

    testWidgets('a template that throws is handled like any other failure',
        (tester) async {
      // A template is ordinary widget code written by a future feature.
      await pumpFlow(tester, renderer: FakeRenderer(thrown: StateError('bad')));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardPreviewScreen), findsNothing);
      expect(find.text('The card could not be created. Please try again.'),
          findsOneWidget);
    });

    testWidgets('the preview it opens can send the card', (tester) async {
      final share = FakeShareService();
      await pumpFlow(tester, renderer: FakeRenderer(), share: share);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(share.shared, hasLength(1));
    });

    testWidgets('Close returns to where the reader was', (tester) async {
      await pumpFlow(tester, renderer: FakeRenderer());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardPreviewScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  // --- 6. the engine knows nothing about the app's domains --------------------

  group('the engine is domain-neutral', () {
    test('nothing in it imports a feature, a repository or a data provider', () {
      // The whole reason this cycle exists before any card does: one renderer
      // has to serve a player's statistics, a community's, and a team lineup,
      // and it can only do that by never learning what it is picturing. This
      // reads the engine's own source, because the constraint is about what
      // the files are allowed to depend on rather than about any behaviour.
      const engine = [
        'lib/features/sharing/share_card_canvas.dart',
        'lib/features/sharing/share_card_renderer.dart',
        'lib/features/sharing/widget_share_card_renderer.dart',
        'lib/features/sharing/share_service.dart',
        'lib/features/sharing/share_card_preview_screen.dart',
        'lib/features/sharing/share_card_flow.dart',
        'lib/infrastructure/platform/native_share_service.dart',
      ];
      const forbidden = [
        'statistics',
        'teams',
        'btge',
        'supabase',
        'results',
        'matches',
        'communities',
        'members',
        'profile',
      ];

      for (final path in engine) {
        final imports = File(path)
            .readAsLinesSync()
            .where((line) => line.startsWith('import '))
            .toList();
        for (final line in imports) {
          for (final word in forbidden) {
            expect(line.contains(word), isFalse,
                reason: '$path imports "$word" -- the engine must receive a '
                    'built template, never reach for what is in it');
          }
        }
      }
    });

    test('the result carries a picture and nothing about its subject', () {
      // If a field here ever named a player or a community, the three future
      // templates would stop being interchangeable.
      final card = _card();
      expect(card.bytes, isNotEmpty);
      expect(card.mimeType, 'image/png');
      expect(card.pixelWidth, 9);
      expect(card.pixelHeight, 16);
      expect(card.isShareCardShape, isTrue);
    });
  });
}

/// A stand-in card. Nine by sixteen actual pixels: the shape is what the engine
/// promises, and the bytes only have to be bytes.
ShareCardImage _card({String fileName = ShareCardImage.defaultFileName}) =>
    ShareCardImage(
      bytes: Uint8List.fromList(_transparentPng),
      pixelWidth: 9,
      pixelHeight: 16,
      fileName: fileName,
    );

/// A valid one-pixel PNG, so `Image.memory` in the preview decodes something
/// real rather than throwing on nonsense bytes.
const _transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

/// The share port, answering from memory and keeping what it was handed.
class FakeShareService implements ShareService {
  FakeShareService({this.outcome = ShareOutcome.shared, this.failure});

  final ShareOutcome outcome;
  final Failure? failure;

  /// Every card actually handed over, so a test can assert it is the generated
  /// artifact rather than something rebuilt on the way.
  final List<ShareCardImage> shared = [];

  /// Counted separately from [shared]: a refused share is still an attempt.
  int attempts = 0;

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image) async {
    attempts++;
    if (failure != null) throw failure!;
    shared.add(image);
    return outcome;
  }
}

/// The renderer port, composing nothing.
class FakeRenderer implements ShareCardRenderer {
  FakeRenderer({this.failure, this.thrown, this.hold = false});

  final Failure? failure;

  /// Something that is not a [Failure] -- what a template's own bug looks like.
  final Object? thrown;

  /// Keeps the compose pending so a test can look at what the reader sees
  /// while it runs.
  final bool hold;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    if (hold) await _gate.future;
    if (failure != null) throw failure!;
    if (thrown != null) throw thrown!;
    return _card();
  }
}
