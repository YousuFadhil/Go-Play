import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/failures.dart';
import '../../core/l10n.dart';
import '../../infrastructure/platform/image_downloader.dart';
import '../../infrastructure/platform/native_share_service.dart';
import '../analytics/analytics_models.dart';
import '../analytics/analytics_service.dart';
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
    this.matchId,
    this.communityId,
    this.shareService,
    this.downloader,
  });

  final ShareCardImage image;

  /// What the card is of, passed down by [presentShareCard] from whichever
  /// screen composed it, and used for one thing: saying which match or
  /// community a share belonged to.
  ///
  /// Both are null for a card that is of neither — a player's own statistics,
  /// for instance — and null is a perfectly ordinary answer. Nothing is read to
  /// populate them and the screen does not otherwise know they exist.
  final String? matchId;
  final String? communityId;

  /// Supplied only by tests, exactly as the repositories take an optional port.
  final ShareService? shareService;

  /// How the card is saved where it cannot be shared. Supplied only by tests;
  /// left null the screen uses the platform's own, which is a download in a
  /// browser and nothing at all anywhere else.
  final ShareCardDownloader? downloader;

  @override
  State<ShareCardPreviewScreen> createState() => _ShareCardPreviewScreenState();
}

class _ShareCardPreviewScreenState extends State<ShareCardPreviewScreen> {
  late final ShareService _share = widget.shareService ?? NativeShareService();
  late final ShareCardDownloader _download =
      widget.downloader ?? downloadShareCardImage;

  /// Guards against a second sheet being asked for while the first is opening.
  /// The share sheet is the operating system's and takes a moment to appear,
  /// which is exactly long enough to press the button twice.
  bool _sharing = false;

  /// The Share button, so the sheet can be anchored to it.
  final GlobalKey _shareButtonKey = GlobalKey();

  /// Where the Share button is on screen, or null if it is not laid out.
  ///
  /// On iPad and macOS the share sheet is a popover that points at whatever
  /// summoned it; without this it points at the middle of the screen instead
  /// of at the button the reader just pressed. It is read here, in the screen
  /// that owns the button, because a position is a fact about this layout —
  /// the service is handed the answer rather than a widget to interrogate.
  Rect? _shareOrigin() {
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    // Global, as the platform wants it: the popover is positioned against the
    // window, not against anything in this screen's coordinate space.
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _shareNow() async {
    if (_sharing) return;
    // Read before the await: after it the button is disabled and the screen
    // may have been rebuilt, and an origin measured then is measured against a
    // layout the reader no longer pressed.
    final origin = _shareOrigin();
    setState(() => _sharing = true);
    try {
      final outcome = await _share.shareImage(widget.image, origin: origin);
      // Every outcome is silent. Sharing succeeded, or the reader closed the
      // sheet themselves — neither is news, and a confirmation of something
      // the reader just watched happen is noise.
      //
      // It is not, however, all the same thing to count. A reader who opened
      // the sheet and changed their mind did not share, and recording them
      // would turn `share_used` into a count of button presses. So
      // [ShareOutcome.dismissed] records nothing, and so does the failure below
      // — a sheet that could not be shown was never a share.
      //
      // [ShareOutcome.unknown] does count. Android reports it for most shares:
      // it knows an app was chosen, not what that app went on to do. Treating
      // "the picture was handed over" as a share is the closest true statement
      // the platform allows, and the alternative would be to record almost no
      // Android shares at all.
      if (outcome != ShareOutcome.dismissed) {
        ProductAnalytics.instance.track(
          ProductEvent.shareUsed,
          matchId: widget.matchId,
          communityId: widget.communityId,
        );
      }
    } on Failure catch (failure) {
      // The sheet could not be shown at all. On a desktop browser that is not a
      // fault but a fact about the platform — it implements no file sharing —
      // and the reader is owed the picture anyway, so it is offered as a
      // download before anything is reported as having gone wrong.
      //
      // Only after the download has also come to nothing does the original
      // failure stand. Reported as the share failure it was, never as a
      // download failure the reader never asked for.
      if (await _saved()) return;
      _report(failure);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Hands the card to the platform's own download, and says whether it took
  /// it.
  ///
  /// A saved picture is confirmed, unlike a shared one: sharing ends in an app
  /// the reader chose and watched open, and a download ends in a folder they
  /// cannot see from here.
  Future<bool> _saved() async {
    try {
      if (!await _download(widget.image)) return false;
    } catch (_) {
      // Whatever the browser threw stays here, as a platform exception stays in
      // an adapter. To the reader this is simply a download that did not
      // happen, and the share failure they already had is the truer report.
      return false;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.shareCardDownloaded)),
      );
    }
    return true;
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
                  // The key is what lets the sheet be anchored here; the button
                  // itself is unchanged in size, place and behaviour.
                  key: _shareButtonKey,
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
