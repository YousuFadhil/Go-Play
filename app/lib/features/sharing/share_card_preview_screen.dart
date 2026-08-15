import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../infrastructure/platform/native_share_service.dart';
import 'share_card_canvas.dart';
import 'share_card_renderer.dart';
import 'share_service.dart';

/// The card, before it is sent.
///
/// **Presentation only, and deliberately thin.** It shows one picture and
/// offers two things to do with it. There is no editor, no template picker and
/// no filter: a card is composed by the feature that asked for it, and anything
/// the reader could change here would be a second place the card is decided.
///
/// It does not render anything either — it is handed a finished
/// [ShareCardImage]. The composing happens before this screen opens, which is
/// why the reader never watches a blank preview fill in.
class ShareCardPreviewScreen extends StatefulWidget {
  const ShareCardPreviewScreen({
    super.key,
    required this.image,
    this.shareService,
  });

  final ShareCardImage image;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ShareService? shareService;

  @override
  State<ShareCardPreviewScreen> createState() => _ShareCardPreviewScreenState();
}

class _ShareCardPreviewScreenState extends State<ShareCardPreviewScreen> {
  late final ShareService _share = widget.shareService ?? NativeShareService();

  /// Guards against a second sheet being asked for while the first is opening.
  /// The share sheet is the operating system's and takes a moment to appear,
  /// which is exactly long enough to press the button twice.
  bool _sharing = false;

  Future<void> _shareNow() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _share.shareImage(widget.image);
      // Every outcome is silent. Sharing succeeded, or the reader closed the
      // sheet themselves — neither is news, and a confirmation of something
      // the reader just watched happen is noise.
    } on Failure catch (failure) {
      _report(failure);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _report(Failure failure) {
    if (!mounted) return;
    final l10n = context.l10n;
    // By type, never by reason, as OP-5 requires.
    final message = switch (failure) {
      NetworkFailure() => l10n.networkError,
      _ => l10n.errShareCardShare,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      // Not the AppHeader: this screen is a picture being looked at, and the
      // signed-in player's own face in the corner of it would read as part of
      // what is about to be sent.
      appBar: AppBar(
        title: Text(l10n.shareCardTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.shareCardCloseAction,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(kPageMargin),
                child: ShareCardPreviewImage(image: widget.image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPageMargin,
                0,
                kPageMargin,
                kPageMargin,
              ),
              child: SizedBox(
                width: double.infinity,
                height: kButtonHeight,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _shareNow,
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.shareCardShareAction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture itself, at the shape it was made in.
///
/// **The ratio comes from the canvas, not from the bytes.** `Image.memory` only
/// learns its size once it has decoded, so a preview sized by the image would
/// resize under the reader as it loads. Reserving 9:16 up front means the
/// picture appears where it was already going to be.
///
/// `BoxFit.contain` inside it: the reader is checking what they are about to
/// send, and a preview that cropped to fill would be showing them a different
/// picture from the one that leaves.
class ShareCardPreviewImage extends StatelessWidget {
  const ShareCardPreviewImage({super.key, required this.image});

  final ShareCardImage image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: AspectRatio(
        aspectRatio: ShareCardCanvas.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Image.memory(
              image.bytes,
              fit: BoxFit.contain,
              // The card is a fixed picture on a screen of any size, so letting
              // it be resampled up from a cache entry sized for a thumbnail
              // would show the reader a blurrier card than the one they send.
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
