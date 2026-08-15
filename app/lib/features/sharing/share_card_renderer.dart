import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/failures.dart';
import 'share_card_canvas.dart';

/// What a card is made of: a widget, built when the card is composed.
///
/// A template is a function rather than a class so that a future card is an
/// ordinary widget tree — the same `Text`, `Row` and `Image` the app is already
/// written in — instead of a subclass of something that exists only here.
///
/// It receives a [BuildContext] inside the surface, so `MediaQuery` describes
/// the card and `Theme`, `Directionality` and the localizations are the app's.
typedef ShareCardTemplate = Widget Function(BuildContext context);

/// A composed card, ready to be looked at and sent.
///
/// **Bytes, not a file.** The app builds for the web as well as for Android and
/// iOS, so a `dart:io` file here would not compile everywhere the app runs, and
/// a file written by this engine would be an artifact it then had to remember
/// to delete. The platform share layer writes a temporary file when the
/// platform needs one and owns its lifetime; nothing in the app's own storage
/// outlives a share.
@immutable
class ShareCardImage {
  const ShareCardImage({
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    this.fileName = defaultFileName,
    this.mimeType = 'image/png',
  });

  /// PNG, because a card is flat colour and text where PNG is exact and JPEG
  /// is not, and because every share sheet on every platform accepts it.
  final Uint8List bytes;

  /// The real size of the encoded image, which is [ShareCardCanvas.designSize]
  /// multiplied by the density it was captured at.
  final int pixelWidth;
  final int pixelHeight;

  /// What the share sheet offers to call the picture. A name, not a path: the
  /// engine never chooses where anything is written.
  final String fileName;
  final String mimeType;

  static const defaultFileName = 'go-play-share-card.png';

  double get aspectRatio => pixelWidth / pixelHeight;

  /// Whether this image is the 9:16 the engine promises. A card that is not is
  /// a defect rather than a variant — there is one format.
  bool get isShareCardShape => ShareCardCanvas.isShareCardShape(
        Size(pixelWidth.toDouble(), pixelHeight.toDouble()),
      );
}

/// Turns a template into an image.
///
/// **Domain-neutral, permanently.** Nothing here names a player, a community, a
/// match, a team or a statistic, and no implementation may accept one: a
/// template arrives already built, so the engine never learns what it is a
/// picture of and never reaches for a repository to find out. That is what lets
/// the same renderer serve all three cards that follow.
///
/// Implementations raise a [Failure] rather than a rendering exception, as the
/// rest of the app does (OP-5). Composition failure is an
/// [InfrastructureFailure]: the machinery that produces the picture did not,
/// which is nothing the reader got wrong and nothing they can correct.
abstract interface class ShareCardRenderer {
  /// Composes [template] and returns the picture.
  ///
  /// [pixelRatio] multiplies [ShareCardCanvas.designSize] into real pixels. The
  /// default of 1 is already 1080×1920 — a Story at full size — so raising it
  /// buys a larger file rather than a better card.
  Future<ShareCardImage> render(
    ShareCardTemplate template, {
    double pixelRatio,
  });
}

/// Captures an already-painted boundary as a PNG.
///
/// This is the whole of the actual imaging, kept apart from the widget
/// lifecycle that gets a card into the tree so that it can be driven — and
/// tested — against a boundary from any source.
///
/// Throws [InfrastructureFailure] when the boundary cannot be turned into an
/// image: it was never laid out, it has no size, or the engine declined to
/// encode it. Every one of those is the same thing to a caller — there is no
/// picture — and none is a distinction a reader could act on.
Future<ShareCardImage> captureShareCard(
  RenderRepaintBoundary boundary, {
  double pixelRatio = 1.0,
  String fileName = ShareCardImage.defaultFileName,
}) async {
  if (pixelRatio <= 0) {
    throw ArgumentError.value(pixelRatio, 'pixelRatio', 'must be positive');
  }
  // A boundary that has not been laid out reports a zero size, and asking the
  // engine to encode nothing produces an exception from deep inside it rather
  // than an answer. Refusing here says the same thing in the app's own words.
  if (!boundary.hasSize || boundary.size.isEmpty) {
    throw const InfrastructureFailure();
  }

  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const InfrastructureFailure();

    return ShareCardImage(
      bytes: data.buffer.asUint8List(),
      pixelWidth: image.width,
      pixelHeight: image.height,
      fileName: fileName,
    );
  } on Failure {
    rethrow;
  } catch (_) {
    // Whatever the engine threw stays here, as an adapter's provider exception
    // does: the app's error language has eight words and this is one of them.
    throw const InfrastructureFailure();
  } finally {
    // The handle is native memory and is not the bytes we return, so it is
    // released whether the encode succeeded or not.
    image?.dispose();
  }
}
