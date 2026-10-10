import 'package:share_plus/share_plus.dart';

import '../../core/failures.dart';
import '../../features/sharing/share_card_renderer.dart';
import 'native_share_service.dart';

/// Match invitations share one preview image and one match URL in the same
/// OS sheet request. The existing text-only method remains for compatibility.
/// WhatsApp may be selected by the user; the app never sends on their behalf.
class NativeTextShareService {
  NativeTextShareService([ShareSheet? shareSheet])
      : _shareSheet = shareSheet ?? SharePlus.instance.share;

  final ShareSheet _shareSheet;

  Future<void> shareText(String text) async {
    try {
      await _shareSheet(ShareParams(text: text));
    } catch (_) {
      throw const InfrastructureFailure();
    }
  }

  /// One share-sheet invocation carries both the small PNG and a tappable
  /// match URL. This is only for invitations; display cards stay image-only.
  Future<void> shareInvitation(String link, ShareCardImage preview) async {
    try {
      final result = await _shareSheet(ShareParams(
        text: link,
        files: [
          XFile.fromData(
            preview.bytes,
            mimeType: preview.mimeType,
            name: preview.fileName,
          ),
        ],
        fileNameOverrides: [preview.fileName],
      ));
      if (result.status == ShareResultStatus.unavailable) {
        throw const InfrastructureFailure();
      }
    } catch (_) {
      throw const InfrastructureFailure();
    }
  }
}
