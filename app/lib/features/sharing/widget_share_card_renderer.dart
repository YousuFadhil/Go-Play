import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/failures.dart';
import 'share_card_canvas.dart';
import 'share_card_renderer.dart';

/// The renderer the app uses: it mounts a card, lets Flutter paint it, and
/// photographs it.
///
/// **Why a card has to be in the widget tree at all.** A `RepaintBoundary` can
/// only be captured once Flutter has laid it out and painted it, and Flutter
/// only does that for something that is mounted. So the card is put into the
/// [Overlay] — above every screen, below nothing the reader is looking at — and
/// taken straight back out.
///
/// **Why it is moved off-screen rather than hidden.** `Offstage` and a zero
/// `Opacity` both skip painting, which is exactly the step the capture needs.
/// A translation keeps the card fully laid out and fully painted while putting
/// it where nobody sees it. An overlay has no viewport, so nothing culls it for
/// being out of view.
///
/// The card is drawn at [ShareCardCanvas.designSize] regardless of the screen
/// it is composed on, so the image does not depend on the phone that made it.
class WidgetShareCardRenderer implements ShareCardRenderer {
  WidgetShareCardRenderer(
    this._overlay, {
    Future<void> Function()? awaitFrame,
    Future<ShareCardImage> Function(
      RenderRepaintBoundary boundary, {
      double pixelRatio,
      String fileName,
    })? capture,
    this.fileName = ShareCardImage.defaultFileName,
  })  : _awaitFrame = awaitFrame ?? _endOfFrame,
        _capture = capture ?? captureShareCard;

  /// Built from a [BuildContext] under a `MaterialApp`, which is every signed-in
  /// screen. Taken as the overlay rather than the context so that this class
  /// holds nothing that expires.
  factory WidgetShareCardRenderer.of(BuildContext context) =>
      WidgetShareCardRenderer(Overlay.of(context, rootOverlay: true));

  final OverlayState _overlay;

  /// Waiting for Flutter to finish a frame. Injectable because a widget test
  /// drives frames itself and has no real vsync to wait on.
  final Future<void> Function() _awaitFrame;

  /// The imaging step, so that this class can be exercised for what it is
  /// responsible for — mounting a card and removing it again — without the
  /// engine's encoder in the way.
  final Future<ShareCardImage> Function(
    RenderRepaintBoundary boundary, {
    double pixelRatio,
    String fileName,
  }) _capture;

  final String fileName;

  /// Far enough that no part of a 1080×1920 card intrudes on any screen.
  static const _offscreen = 100000.0;

  static Future<void> _endOfFrame() {
    // A frame has to be *scheduled* as well as awaited: an app sitting idle
    // produces none, and `endOfFrame` on its own would then never complete.
    SchedulerBinding.instance.scheduleFrame();
    return SchedulerBinding.instance.endOfFrame;
  }

  @override
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio = 1.0,
  }) async {
    final boundaryKey = GlobalKey();
    final entry = OverlayEntry(
      // **`left` and `top` only, and that is what makes the card the right
      // size.** A `Positioned` child constrained on one edge per axis is given
      // no maximum on that axis, so the surface is laid out at the size it
      // declares. Constraining the opposite edges — or dropping `Positioned`
      // for a plain child — would hand it the phone's size as its maximum
      // instead, and a 1080×1920 card composed on a 400×800 screen would be
      // silently squeezed to 400×800: neither the design size nor 9:16, with
      // nothing on the way through to show that it happened.
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        child: Transform.translate(
          offset: const Offset(-_offscreen, -_offscreen),
          child: RepaintBoundary(
            key: boundaryKey,
            child: ShareCardSurface(child: template(context)),
          ),
        ),
      ),
    );

    _overlay.insert(entry);
    try {
      // Two frames, not one. The first mounts and lays the card out; the second
      // is where anything that only settles after a build — an image that
      // resolved, a layout that depended on a measured child — has been
      // painted. One frame captures a card that is occasionally half-composed,
      // and a card is sent to other people.
      await _awaitFrame();
      await _awaitFrame();

      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      // The entry was inserted a moment ago and nothing removes it but the
      // `finally` below, so a missing boundary means the overlay went away
      // underneath us — the screen was closed mid-compose.
      if (boundary == null) throw const InfrastructureFailure();

      return await _capture(
        boundary,
        pixelRatio: pixelRatio,
        fileName: fileName,
      );
    } finally {
      // Always. A card left in the overlay is an invisible widget rebuilding
      // above every screen for the rest of the session, and a failed compose is
      // exactly when it would be easiest to leave one behind.
      entry.remove();
      entry.dispose();
    }
  }
}
