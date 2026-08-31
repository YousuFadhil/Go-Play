import '../../features/sharing/share_card_renderer.dart';

/// Saving a card without a browser: there is nothing to do, and that is the
/// answer.
///
/// Android, iOS, macOS and Windows all show a share sheet, and the sheet is
/// where a picture is saved on those platforms — "Save image" is one of the
/// destinations it lists, alongside every app the reader has. A download of our
/// own would be a second, worse way to reach a place the sheet already reaches,
/// and it would need a file path, a permission prompt and a media-store entry to
/// get there.
///
/// So this returns false rather than throwing. False is not a failure: it is
/// "this platform has no download, use the sheet", and the caller has already
/// tried the sheet by the time it asks.
Future<bool> downloadShareCardImage(ShareCardImage image) async => false;
