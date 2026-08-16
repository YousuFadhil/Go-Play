import 'dart:ui' show Rect;

// `XFile` arrives through this import: `share_plus` re-exports it, so the
// package that consumes the file is the one that defines how it is described.
import 'package:share_plus/share_plus.dart';

import '../../core/failures.dart';
import '../../features/sharing/share_card_renderer.dart';
import '../../features/sharing/share_service.dart';

/// Summoning the operating system's share sheet. `SharePlus.instance.share` in
/// the app; supplied by a test to read what was handed over.
typedef ShareSheet = Future<ShareResult> Function(ShareParams params);

/// The operating system's own share sheet, reached through `share_plus`.
///
/// This is the only file in the app that knows a sharing package exists, which
/// is the same arrangement the Supabase adapters have with their client: the
/// package's types stop here and the application above sees [ShareOutcome] and
/// [Failure].
///
/// **The temporary file is the platform's, not ours.** The picture is handed
/// over as bytes; `share_plus` writes it into the OS temporary directory only
/// on the platforms that need a path, under a folder it generates, and the
/// system reclaims that directory when it wants the space back. So the app
/// creates no artifact, records nothing, and has nothing to clean up — which is
/// also why nothing here imports `dart:io`, a file the web build could not
/// compile.
///
/// **No application is named here, and none may be.** The sheet lists what the
/// reader has installed. See [ShareService].
class NativeShareService implements ShareService {
  NativeShareService([ShareSheet? sheet])
      : _sheet = sheet ?? SharePlus.instance.share;

  /// The sheet itself, as a function.
  ///
  /// Taken this way rather than as a `SharePlus` because that class can only be
  /// substituted through `SharePlus.custom`, which wants a `SharePlatform` —
  /// a type `share_plus` does not re-export, so reaching it would mean this app
  /// depending on the platform-interface package for no reason but a test. A
  /// function is the smaller seam and lets a test read the exact [ShareParams]
  /// this class builds.
  final ShareSheet _sheet;

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image, {Rect? origin}) async {
    try {
      final result = await _sheet(
        ShareParams(
          files: [
            XFile.fromData(
              image.bytes,
              mimeType: image.mimeType,
              name: image.fileName,
            ),
          ],
          // `XFile.fromData` carries no path, and some platforms take the name
          // from the path alone — without this the picture arrives called
          // something the reader did not choose.
          fileNameOverrides: [image.fileName],
          // Where the popover points on iPad and macOS. The package ignores it
          // everywhere else, so Android and the web are unaffected, and it
          // accepts null by falling back to the centre of the screen — which
          // is the behaviour this exists to avoid rather than a crash to
          // prevent.
          sharePositionOrigin: origin,
        ),
      );

      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unknown,
      };
    } catch (_) {
      // The platform exception stays here, as a provider exception stays in an
      // adapter. Nothing above this layer learns which package failed.
      throw const InfrastructureFailure();
    }
  }
}
