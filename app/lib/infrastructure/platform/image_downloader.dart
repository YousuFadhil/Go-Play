/// Saving a composed card to wherever the platform keeps downloads.
///
/// **The second half of one product decision, not a second way to share.** The
/// approved behaviour is: offer the share sheet, and where there is no share
/// sheet, let the reader keep the picture. Everything above this file asks for
/// exactly that, in that order, and neither implementation below is reachable
/// except after the sheet has already been tried.
///
/// The conditional export is what keeps `dart:js_interop` out of the mobile
/// build and the mobile answer out of the web one — the same arrangement
/// `firebase_web_config.dart` uses, and the reason nothing here imports
/// `dart:io`.
library;

export 'image_downloader_stub.dart'
    if (dart.library.js_interop) 'image_downloader_web.dart';
