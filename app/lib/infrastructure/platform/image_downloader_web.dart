import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../features/sharing/share_card_renderer.dart';

/// Saving a card in a browser, for the browsers that cannot share one.
///
/// **This is the fallback, never the first choice.** Where the Web Share API
/// accepts files — Safari, and Chrome on Android — `share_plus` opens the
/// platform sheet and the reader picks a destination, exactly as they would on
/// a phone. Desktop Chrome and Firefox do not implement file sharing, so there
/// the sheet cannot open at all, and the card would be composed, previewed, and
/// then have nowhere to go. A download is the one thing every browser can do
/// with a picture.
///
/// **A blob and an anchor, which is the whole mechanism.** The bytes are already
/// in memory; wrapping them in a `Blob` and clicking a generated link hands them
/// to the browser's own download machinery, which decides where they land and
/// tells the reader about it. Nothing here writes a file, asks for a permission
/// or touches storage, so there is nothing to clean up but the object URL —
/// which is revoked on the way out.
///
/// The click has to come from this frame's own document, so the anchor is
/// attached before it is clicked and removed immediately after: a detached
/// anchor's click is ignored in some browsers, and one left attached would be an
/// invisible element accumulating in the body on every share.
Future<bool> downloadShareCardImage(ShareCardImage image) async {
  final blob = web.Blob(
    <JSAny>[image.bytes.toJS].toJS,
    web.BlobPropertyBag(type: image.mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      // What the file is called once it lands. The same name the share sheet
      // would have offered, so the two paths produce the same picture under the
      // same name.
      ..download = image.fileName;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } finally {
    // The blob stays alive as long as its URL does, and the download has
    // already taken its own reference by the time the click returns.
    web.URL.revokeObjectURL(url);
  }
}
