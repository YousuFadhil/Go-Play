// `Rect` only, and from `dart:ui` rather than from a package: where on screen a
// share was asked for is a fact about the app's own layout, not a type borrowed
// from whatever sends the picture.
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'share_card_renderer.dart';

/// What became of a share.
///
/// **Dismissing the sheet is an outcome, not a failure.** A reader who opens
/// the share sheet and changes their mind has done nothing wrong and nothing
/// broke; telling them "sharing failed" would be untrue and would need a
/// dismissal of its own. So it is reported as a value and the screen simply
/// says nothing.
enum ShareOutcome {
  /// The reader picked somewhere to send it.
  shared,

  /// The reader closed the sheet without picking anything.
  dismissed,

  /// The sheet was shown and the platform cannot say what happened. Android
  /// reports this for most shares — it knows an app was chosen, not whether
  /// that app went on to send anything — so it is the common answer rather
  /// than an unusual one, and it is never treated as an error.
  unknown,
}

/// Saving a card to wherever the platform keeps downloads, returning whether it
/// could.
///
/// **The fallback half of the sharing decision.** A share sheet is the primary
/// path on every platform that has one; this is what the reader gets where
/// there is none — desktop browsers, which implement no file sharing — so that a
/// composed card is never a picture with nowhere to go.
///
/// A function rather than an interface: it has one operation, no state and no
/// configuration, and the implementation is selected by a conditional import
/// rather than by construction. False means "this platform has no download",
/// which is an answer and not a failure; a platform that has one and could not
/// complete it raises a [Failure] like everything else.
typedef ShareCardDownloader = Future<bool> Function(ShareCardImage image);

/// The words that travel with a picture.
///
/// **A card without a link is a picture nobody can act on.** The image says
/// what happened; the link is what lets whoever receives it open the thing
/// itself, and a share sheet that carries only a PNG ends the journey at the
/// message. So the two are one value rather than two parameters that a caller
/// could supply half of.
///
/// [text] is already localized when it arrives. Composing it is the calling
/// feature's business — it is the one that knows whether this is a player's own
/// profile or somebody else's — and the engine never reaches for
/// `AppLocalizations` itself, exactly as it never reaches for a repository.
///
/// [url] is a public link (see `PublicLink`). Null is ordinary: a card of
/// something with no public address — a team lineup — carries words and no
/// link, and that is a complete message rather than a broken one.
@immutable
class ShareMessage {
  const ShareMessage({required this.text, this.url});

  final String text;
  final String? url;

  /// What the share sheet is actually handed.
  ///
  /// The link goes on its own line after a blank one, because every messaging
  /// app the sheet lists auto-links a bare URL at a line ending and several of
  /// them mangle one that is buried mid-sentence.
  String get body {
    final link = url?.trim();
    if (link == null || link.isEmpty) return text;
    if (text.trim().isEmpty) return link;
    return '$text\n\n$link';
  }
}

/// The application's one way of handing a picture to the operating system.
///
/// **One operation, and no destinations.** The product decision is that Go Play
/// does not integrate with messaging apps: the OS share sheet already lists
/// every app the reader has, in their own order, with their own defaults. So
/// there is no `shareToWhatsApp`, no target parameter and no place for one —
/// an implementation that named an application would be a different product
/// decision, not a different implementation.
///
/// Implementations raise a [Failure] rather than a platform exception (OP-5).
abstract interface class ShareService {
  /// Offers [image] to the operating system's share sheet.
  ///
  /// [origin] is where on screen the reader asked to share, in global
  /// coordinates — normally the bounds of the control they pressed.
  ///
  /// **It is for the platforms that show the sheet as a popover.** On iPad and
  /// macOS a share sheet is anchored to whatever invoked it, and one with
  /// nothing to anchor to opens in the middle of the screen, pointing at
  /// nothing — a share that looks like it came from somewhere else on the
  /// screen than the button the reader just pressed. Every other platform
  /// shows a sheet from the bottom edge and has nothing to anchor, so the
  /// argument changes nothing on Android or the web.
  ///
  /// Optional because a caller that genuinely has no position — a share
  /// triggered by something other than a control — should say so rather than
  /// invent one.
  ///
  /// [message] is the localized text and public link that travel with the
  /// picture. Optional, because the engine served image-only shares before
  /// Package 5 and a caller with nothing to say still has a card to send —
  /// null hands over exactly what it handed over before.
  ///
  /// **Still no destinations.** A message is words and a URL; it names no
  /// application, and the sheet decides where it goes exactly as before.
  ///
  /// Throws [InfrastructureFailure] when the sheet could not be shown at all.
  /// A sheet that was shown and closed returns [ShareOutcome.dismissed].
  Future<ShareOutcome> shareImage(
    ShareCardImage image, {
    Rect? origin,
    ShareMessage? message,
  });
}
