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

/// The words that travel with a picture: a short localized sentence, and
/// nothing else.
///
/// **No link, by construction.** The approved share is the image plus a line of
/// text. A public address is not attached automatically, and this type has no
/// field that could carry one, so no caller can append a URL again by
/// accident. Public links still exist — direct routes, external arrivals and
/// their acquisition evidence are untouched (`PublicLink`) — they are simply
/// not part of what a share sends.
///
/// [text] is already localized when it arrives. Composing it is the calling
/// feature's business — it is the one that knows whether this is a player's own
/// profile or somebody else's — and the engine never reaches for
/// `AppLocalizations` itself, exactly as it never reaches for a repository.
@immutable
class ShareMessage {
  const ShareMessage({required this.text});

  final String text;

  /// What the share sheet is actually handed: the sentence, as written.
  String get body => text;
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
  /// [message] is the localized text that travels with the picture. Optional,
  /// because the engine served image-only shares before Package 5 and a caller
  /// with nothing to say still has a card to send — null hands over exactly
  /// what it handed over before.
  ///
  /// **Still no destinations.** A message is words only; it names no
  /// application and carries no link, and the sheet decides where it goes
  /// exactly as before.
  ///
  /// Throws [InfrastructureFailure] when the sheet could not be shown at all.
  /// A sheet that was shown and closed returns [ShareOutcome.dismissed].
  Future<ShareOutcome> shareImage(
    ShareCardImage image, {
    Rect? origin,
    ShareMessage? message,
  });
}
