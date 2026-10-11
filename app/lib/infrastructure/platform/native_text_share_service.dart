import 'package:share_plus/share_plus.dart';

import '../../core/failures.dart';
import '../../features/sharing/share_service.dart';
import 'native_share_service.dart';

/// Text-only shares use the same OS share sheet as existing image shares.
/// WhatsApp may be selected by the user; the app never sends on their behalf.
class NativeTextShareService {
  NativeTextShareService([ShareSheet? shareSheet])
      : _shareSheet = shareSheet ?? SharePlus.instance.share;

  final ShareSheet _shareSheet;

  Future<ShareOutcome> shareText(String text) async {
    try {
      final result = await _shareSheet(ShareParams(text: text));
      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unknown,
      };
    } catch (_) {
      throw const InfrastructureFailure();
    }
  }
}
