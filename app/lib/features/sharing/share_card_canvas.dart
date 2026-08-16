import 'package:flutter/material.dart';

/// The one shape a Go Play share card has.
///
/// **9:16 portrait, and for this cycle nothing else.** Every surface that will
/// ever produce a card — a player's statistics, a community's, a team lineup —
/// produces this one, so the format is stated once here rather than agreed on
/// three times. A second format is a product decision, not a parameter, and
/// adding one means changing this file deliberately.
///
/// **A fixed design coordinate system, not the device's.** A template lays
/// itself out against [designSize] and is captured at that size on every phone,
/// so a card composed on a small screen and a card composed on a tablet are the
/// same image. Without this each future template would have to derive its own
/// geometry from whatever screen it happened to be opened on, and three
/// templates would drift into three geometries.
abstract final class ShareCardCanvas {
  /// The ratio's two halves, kept as the integers the format is named by so
  /// that "9:16" appears in the code as 9 and 16 rather than as 0.5625.
  static const int widthUnits = 9;
  static const int heightUnits = 16;

  /// Width over height — the form `AspectRatio` and `Image` want.
  static const double aspectRatio = widthUnits / heightUnits;

  /// The logical canvas every template is laid out on.
  ///
  /// 1080×1920 because it is the Story size the platforms expect, so a card
  /// captured at a pixel ratio of 1 is already the right number of pixels and
  /// no upscaling is needed for the common case. It is a *logical* size here —
  /// the density that turns it into pixels is the renderer's argument.
  static const Size designSize = Size(1080, 1920);

  /// Whether [size] is the portrait 9:16 this engine produces.
  ///
  /// [tolerance] exists because a capture rounds to whole pixels: a 1080×1920
  /// card is exact, but an odd pixel ratio can land a pixel either way, and a
  /// card one pixel off is the right card rather than a broken contract.
  static bool isShareCardShape(Size size, {double tolerance = 0.01}) {
    if (size.width <= 0 || size.height <= 0) return false;
    return (size.width / size.height - aspectRatio).abs() <= tolerance;
  }
}

/// The surface a template paints on, and the thing that makes two devices
/// produce one image.
///
/// It fixes three things a template must not inherit from the phone it is being
/// composed on:
///
///  * **the size** — [ShareCardCanvas.designSize], so `MediaQuery.sizeOf` inside
///    a template describes the card rather than the screen behind it;
///  * **the text scale** — reset to none, because a reader who has turned system
///    text up wants *their app* larger, not the picture they are about to send
///    to somebody else reflowed;
///  * **the padding** — cleared, because a card has no notch and no status bar
///    to avoid.
///
/// Reading direction is deliberately *not* fixed: it is inherited, so an Arabic
/// card composes right-to-left exactly as the app does.
///
/// It holds no colours, no typography and no chrome. What a card looks like
/// belongs to the templates, which are a later cycle; this is only the paper.
class ShareCardSurface extends StatelessWidget {
  const ShareCardSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: ShareCardCanvas.designSize,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: ShareCardCanvas.designSize,
          textScaler: TextScaler.noScaling,
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          devicePixelRatio: 1,
        ),
        // A card is opaque: it is a picture, and a transparent PNG sent to a
        // messaging app is composited against whatever that app decides.
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: child,
        ),
      ),
    );
  }
}
