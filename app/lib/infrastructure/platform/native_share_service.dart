// `XFile` arrives through this import: `share_plus` re-exports it, so the
// package that consumes the file is the one that defines how it is described.
import 'package:share_plus/share_plus.dart';

import '../../core/failures.dart';
import '../../features/sharing/share_card_renderer.dart';
import '../../features/sharing/share_service.dart';

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
  NativeShareService([SharePlus? sharePlus])
      : _sharePlus = sharePlus ?? SharePlus.instance;

  final SharePlus _sharePlus;

  @override
  Future<ShareOutcome> shareImage(ShareCardImage image) async {
    try {
      final result = await _sharePlus.share(
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
